import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module ExecuteSysStage(
    ReadRegStageIF.ExecuteSysStage prev,
    ExecuteStageIF.ExecuteSysStage self,
    CtrlIF.ExecuteStage ctrl,
    BypassIF.ExecuteSysStage bypass
);
    localparam logic [11:0] CSR_MSTATUS = 12'h300;
    localparam logic [11:0] CSR_MTVEC   = 12'h305;
    localparam logic [11:0] CSR_MEPC    = 12'h341;
    localparam logic [11:0] CSR_MCAUSE  = 12'h342;
    localparam DataPath     MCAUSE_ECALL_M = 32'd11;

    RrToExSysPath pipeReg [WAY_NUM];
    DataPath mstatus;
    DataPath mtvec;
    DataPath mepc;
    DataPath mcause;

    function automatic logic is_mret(input RrToExSysPath uop);
        return uop.subType.sysSubType == SYS_SUBTYPE_EBREAK &&
               uop.csrAddr.valid &&
               uop.csrAddr.csrAddr == 12'h302;
    endfunction

    function automatic logic is_csr(input SysSubType st);
        return st inside {SYS_SUBTYPE_CSRRW, SYS_SUBTYPE_CSRRS, SYS_SUBTYPE_CSRRC,
                          SYS_SUBTYPE_CSRRWI, SYS_SUBTYPE_CSRRSI, SYS_SUBTYPE_CSRRCI};
    endfunction

    function automatic DataPath csr_read(input logic [11:0] addr);
        unique case (addr)
            CSR_MSTATUS: csr_read = mstatus;
            CSR_MTVEC:   csr_read = mtvec;
            CSR_MEPC:    csr_read = mepc;
            CSR_MCAUSE:  csr_read = mcause;
            default:     csr_read = '0;
        endcase
    endfunction

    function automatic DataPath mstatus_mask(input DataPath value);
        DataPath masked;
        masked = '0;
        masked[3] = value[3];
        masked[7] = value[7];
        return masked;
    endfunction

    function automatic DataPath csr_write_value(
        input SysSubType st,
        input DataPath oldValue,
        input DataPath operand
    );
        unique case (st)
            SYS_SUBTYPE_CSRRW,
            SYS_SUBTYPE_CSRRWI: csr_write_value = operand;
            SYS_SUBTYPE_CSRRS,
            SYS_SUBTYPE_CSRRSI: csr_write_value = oldValue | operand;
            SYS_SUBTYPE_CSRRC,
            SYS_SUBTYPE_CSRRCI: csr_write_value = oldValue & ~operand;
            default:            csr_write_value = oldValue;
        endcase
    endfunction

    function automatic logic csr_should_write(input RrToExSysPath uop, input DataPath operand);
        unique case (uop.subType.sysSubType)
            SYS_SUBTYPE_CSRRW,
            SYS_SUBTYPE_CSRRWI: csr_should_write = 1'b1;
            SYS_SUBTYPE_CSRRS,
            SYS_SUBTYPE_CSRRC:  csr_should_write = (uop.Rs1 != '0);
            SYS_SUBTYPE_CSRRSI,
            SYS_SUBTYPE_CSRRCI: csr_should_write = (operand[4:0] != '0);
            default:            csr_should_write = 1'b0;
        endcase
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToSysStage;
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            mstatus <= '0;
            mtvec <= '0;
            mepc <= '0;
            mcause <= '0;
        end else if (!ctrl.exPipe.flush && !ctrl.exPipe.stall) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                DataPath operand;
                DataPath oldValue;
                DataPath newValue;

                operand = bypass.sysReadRes[i*2].hit ? bypass.sysReadRes[i*2].data :
                          pipeReg[i].dataA;
                oldValue = csr_read(pipeReg[i].csrAddr.csrAddr);
                newValue = csr_write_value(pipeReg[i].subType.sysSubType, oldValue, operand);

                if (pipeReg[i].valid && pipeReg[i].subType.sysSubType == SYS_SUBTYPE_ECALL) begin
                    mepc <= pipeReg[i].pc;
                    mcause <= MCAUSE_ECALL_M;
                    mstatus[7] <= mstatus[3];
                    mstatus[3] <= 1'b0;
                end else if (pipeReg[i].valid && is_mret(pipeReg[i])) begin
                    mstatus[3] <= mstatus[7];
                    mstatus[7] <= 1'b1;
                end else if (pipeReg[i].valid && is_csr(pipeReg[i].subType.sysSubType) &&
                             pipeReg[i].csrAddr.valid &&
                             csr_should_write(pipeReg[i], operand)) begin
                    unique case (pipeReg[i].csrAddr.csrAddr)
                        CSR_MSTATUS: mstatus <= mstatus_mask(newValue);
                        CSR_MTVEC:   mtvec <= {newValue[31:2], 2'b00};
                        CSR_MEPC:    mepc <= newValue;
                        CSR_MCAUSE:  mcause <= newValue;
                        default: begin end
                    endcase
                end
            end
        end
    end

    always_comb begin
        ctrl.sysStageEmpty = 1'b1;
        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.sysReadReq[i] = '0;
        for (int i = 0; i < WAY_NUM; i++) begin
            DataPath operand;
            DataPath csrOld;

            bypass.sysReadReq[i*2].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.sysReadReq[i*2].phyRegNum = pipeReg[i].Rs1;
            operand = bypass.sysReadRes[i*2].hit ? bypass.sysReadRes[i*2].data : pipeReg[i].dataA;
            csrOld = pipeReg[i].csrAddr.valid ? csr_read(pipeReg[i].csrAddr.csrAddr) : '0;

            self.nextSysToStage[i].valid = pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall;
            self.nextSysToStage[i].Rd = pipeReg[i].Rd;
            self.nextSysToStage[i].writeRd = pipeReg[i].writeRd;
            self.nextSysToStage[i].data = is_csr(pipeReg[i].subType.sysSubType) ? csrOld : operand;
            self.nextSysToStage[i].robIndex = pipeReg[i].robIndex;
            self.nextSysToStage[i].trueTargetPc = '0;
            self.nextSysToStage[i].isSerial = 1'b1;
            self.nextSysToStage[i].exception =
                pipeReg[i].subType.sysSubType == SYS_SUBTYPE_ECALL || is_mret(pipeReg[i]);

            if (pipeReg[i].subType.sysSubType == SYS_SUBTYPE_ECALL) begin
                self.nextSysToStage[i].trueTargetPc = {mtvec[31:2], 2'b00};
            end else if (is_mret(pipeReg[i])) begin
                self.nextSysToStage[i].trueTargetPc = mepc;
            end
            ctrl.sysStageEmpty &= !self.nextSysToStage[i].valid;
        end
    end
endmodule
