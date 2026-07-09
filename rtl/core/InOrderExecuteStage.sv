`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderExecuteStage(
    input Uop exUop[2],
    input DataPath regs[32],
    input WbEntry wbPkt[2],
    input CsrState csr,
    input logic [63:0] cycle,
    input logic [63:0] commitCnt,

    output ExecuteResult exResult[2]
    );
    function automatic DataPath read_reg_forwarded(
        input logic [4:0] regNum,
        input WbEntry olderSlotWb
    );
        read_reg_forwarded = regs[regNum];
        if (regNum != 5'd0) begin
            for (int i = 0; i < 2; i++) begin
                if (wbPkt[i].valid && wbPkt[i].rd == regNum) begin
                    read_reg_forwarded = wbPkt[i].data;
                end
            end
            if (olderSlotWb.valid && olderSlotWb.rd == regNum) begin
                read_reg_forwarded = olderSlotWb.data;
            end
        end
    endfunction

    function automatic logic [7:0] reverse8(input logic [7:0] value);
        for (int i = 0; i < 8; i++) begin
            reverse8[i] = value[7 - i];
        end
    endfunction

    function automatic DataPath brev8(input DataPath value);
        for (int i = 0; i < 4; i++) begin
            brev8[i*8 +: 8] = reverse8(value[i*8 +: 8]);
        end
    endfunction

    function automatic DataPath clmul32(input DataPath a, input DataPath b);
        clmul32 = '0;
        for (int i = 0; i < 32; i++) begin
            if (b[i]) clmul32 ^= a << i;
        end
    endfunction

    function automatic DataPath xperm4(input DataPath a, input DataPath b);
        logic [3:0] idx;

        xperm4 = '0;
        for (int i = 0; i < 8; i++) begin
            idx = b[i*4 +: 4];
            if (idx < 4'd8) xperm4[i*4 +: 4] = a[idx*4 +: 4];
        end
    endfunction

    function automatic DataPath csr_read_value(
        input logic [11:0] addr,
        input CsrState csrState,
        input logic [63:0] cycleValue,
        input logic [63:0] commitValue
    );
        unique case (addr)
            CSR_MSTATUS:   csr_read_value = csrState.mstatus;
            CSR_MTVEC:     csr_read_value = csrState.mtvec;
            CSR_MSCRATCH:  csr_read_value = csrState.mscratch;
            CSR_MEPC:      csr_read_value = csrState.mepc;
            CSR_MCAUSE:    csr_read_value = csrState.mcause;
            CSR_MHARTID:   csr_read_value = '0;
            CSR_CYCLE,
            CSR_MCYCLE:    csr_read_value = cycleValue[31:0];
            CSR_CYCLEH,
            CSR_MCYCLEH:   csr_read_value = cycleValue[63:32];
            CSR_INSTRET,
            CSR_MINSTRET:  csr_read_value = commitValue[31:0];
            CSR_INSTRETH,
            CSR_MINSTRETH: csr_read_value = commitValue[63:32];
            default:       csr_read_value = '0;
        endcase
    endfunction

    function automatic DataPath csr_next_value(
        input logic [2:0] funct3,
        input DataPath oldValue,
        input DataPath operand
    );
        unique case (funct3)
            3'b001,
            3'b101: csr_next_value = operand;
            3'b010,
            3'b110: csr_next_value = oldValue | operand;
            3'b011,
            3'b111: csr_next_value = oldValue & ~operand;
            default: csr_next_value = oldValue;
        endcase
    endfunction

    task automatic apply_csr_write(
        input logic [11:0] addr,
        input DataPath value,
        inout CsrUpdate update
    );
        update.valid = 1'b1;
        unique case (addr)
            CSR_MSTATUS: begin
                update.state.mstatus = '0;
                update.state.mstatus[3] = value[3];
                update.state.mstatus[7] = value[7];
            end
            CSR_MTVEC:    update.state.mtvec = {value[31:2], 2'b00};
            CSR_MSCRATCH: update.state.mscratch = value;
            CSR_MEPC:     update.state.mepc = value;
            CSR_MCAUSE:   update.state.mcause = value;
            default: begin end
        endcase
    endtask

    task automatic execute_one(
        input Uop uop,
        input WbEntry olderSlotWb,
        output ExecuteResult result
    );
        logic [6:0] opc;
        logic [2:0] f3;
        logic [6:0] f7;
        DataPath a;
        DataPath b;
        DataPath aluResult;
        logic takeBranch;
        PcPath actualNextPc;
        PcPath predictedNextPc;
        DataPath csrOld;
        DataPath csrOperand;
        DataPath csrNew;
        logic csrDoWrite;

        result = '0;
        result.commit = uop.valid;
        result.redirectPc = uop.pc + 32'd4;
        result.csrUpdate.state = csr;

        opc = uop.inst[6:0];
        f3 = uop.inst[14:12];
        f7 = uop.inst[31:25];
        a = read_reg_forwarded(rs1(uop.inst), olderSlotWb);
        b = read_reg_forwarded(rs2(uop.inst), olderSlotWb);
        aluResult = '0;
        takeBranch = 1'b0;
        actualNextPc = uop.pc + 32'd4;
        predictedNextPc = uop.predTaken ? uop.predTarget : (uop.pc + 32'd4);

        if (uop.valid) begin
            unique case (opc)
                OP_LUI: begin
                    result.wb.valid = writes_rd(uop.inst);
                    result.wb.rd = rd(uop.inst);
                    result.wb.data = imm_u(uop.inst);
                end
                OP_AUIPC: begin
                    result.wb.valid = writes_rd(uop.inst);
                    result.wb.rd = rd(uop.inst);
                    result.wb.data = uop.pc + imm_u(uop.inst);
                end
                OP_JAL: begin
                    result.wb.valid = writes_rd(uop.inst);
                    result.wb.rd = rd(uop.inst);
                    result.wb.data = uop.pc + 32'd4;
                    result.branch = 1'b1;
                    result.jal = 1'b1;
                    result.redirect = 1'b1;
                    result.redirectPc = uop.pc + imm_j(uop.inst);
                    result.branchMiss = 1'b1;
                    result.jalMiss = 1'b1;
                end
                OP_JALR: begin
                    result.wb.valid = writes_rd(uop.inst);
                    result.wb.rd = rd(uop.inst);
                    result.wb.data = uop.pc + 32'd4;
                    result.branch = 1'b1;
                    result.jalr = 1'b1;
                    result.redirect = 1'b1;
                    result.redirectPc = (a + imm_i(uop.inst)) & ~32'd1;
                    result.branchMiss = 1'b1;
                    result.jalrMiss = 1'b1;
                end
                OP_BRANCH: begin
                    unique case (f3)
                        3'b000: takeBranch = (a == b);
                        3'b001: takeBranch = (a != b);
                        3'b100: takeBranch = ($signed(a) < $signed(b));
                        3'b101: takeBranch = ($signed(a) >= $signed(b));
                        3'b110: takeBranch = (a < b);
                        3'b111: takeBranch = (a >= b);
                        default: takeBranch = 1'b0;
                    endcase
                    result.branch = 1'b1;
                    result.condBranch = 1'b1;
                    actualNextPc = takeBranch ? uop.pc + imm_b(uop.inst) : uop.pc + 32'd4;
                    result.redirect = (actualNextPc != predictedNextPc);
                    result.redirectPc = actualNextPc;
                    result.branchMiss = result.redirect;
                    result.condBranchMiss = result.redirect;
                end
                OP_LOAD: begin
                    result.loadReq = 1'b1;
                    result.loadInfo.valid = 1'b1;
                    result.loadInfo.rd = rd(uop.inst);
                    result.loadInfo.funct3 = f3;
                    result.loadInfo.addr = a + imm_i(uop.inst);
                    result.commit = 1'b0;
                end
                OP_STORE: begin
                    result.storeReq = 1'b1;
                    result.storeInfo.valid = 1'b1;
                    result.storeInfo.addr = a + imm_s(uop.inst);
                    result.storeInfo.data = b;
                    result.storeInfo.mask = store_wstrb(f3);
                    result.commit = 1'b0;
                end
                OP_OP_IMM: begin
                    if (uop.inst[31:20] == 12'h687 && f3 == 3'b101) begin
                        aluResult = brev8(a);
                    end else begin
                        unique case (f3)
                            3'b000: aluResult = a + imm_i(uop.inst);
                            3'b001: aluResult = a << uop.inst[24:20];
                            3'b010: aluResult = DataPath'($signed(a) < $signed(imm_i(uop.inst)));
                            3'b011: aluResult = DataPath'(a < imm_i(uop.inst));
                            3'b100: aluResult = a ^ imm_i(uop.inst);
                            3'b101: aluResult = uop.inst[30] ?
                                                 DataPath'($signed(a) >>> uop.inst[24:20]) :
                                                 DataPath'(a >> uop.inst[24:20]);
                            3'b110: aluResult = a | imm_i(uop.inst);
                            3'b111: aluResult = a & imm_i(uop.inst);
                            default: aluResult = '0;
                        endcase
                    end
                    result.wb.valid = writes_rd(uop.inst);
                    result.wb.rd = rd(uop.inst);
                    result.wb.data = aluResult;
                end
                OP_OP: begin
                    if (f7 == 7'b0010000 && f3 == 3'b010) begin
                        aluResult = (a << 1) + b;
                    end else if (f7 == 7'b0100000 && f3 == 3'b111) begin
                        aluResult = a & ~b;
                    end else if (f7 == 7'b0000101 && f3 == 3'b001) begin
                        aluResult = clmul32(a, b);
                    end else if (f7 == 7'b0010100 && f3 == 3'b010) begin
                        aluResult = xperm4(a, b);
                    end else if (f7 == 7'b0100100 && f3 == 3'b001) begin
                        aluResult = a & ~(32'd1 << b[4:0]);
                    end else if (f7 == 7'b0000001) begin
                        result.mulDivReq = 1'b1;
                        result.mulDivInfo.valid = 1'b1;
                        result.mulDivInfo.funct3 = f3;
                        result.mulDivInfo.rd = rd(uop.inst);
                        result.mulDivInfo.a = a;
                        result.mulDivInfo.b = b;
                        result.commit = 1'b0;
                    end else begin
                        unique case (f3)
                            3'b000: aluResult = uop.inst[30] ? (a - b) : (a + b);
                            3'b001: aluResult = a << b[4:0];
                            3'b010: aluResult = DataPath'($signed(a) < $signed(b));
                            3'b011: aluResult = DataPath'(a < b);
                            3'b100: aluResult = a ^ b;
                            3'b101: aluResult = uop.inst[30] ?
                                                 DataPath'($signed(a) >>> b[4:0]) :
                                                 DataPath'(a >> b[4:0]);
                            3'b110: aluResult = a | b;
                            3'b111: aluResult = a & b;
                            default: aluResult = '0;
                        endcase
                        result.wb.valid = writes_rd(uop.inst);
                        result.wb.rd = rd(uop.inst);
                        result.wb.data = aluResult;
                    end
                    if (!result.mulDivReq) begin
                        result.wb.valid = writes_rd(uop.inst);
                        result.wb.rd = rd(uop.inst);
                        result.wb.data = aluResult;
                    end
                end
                OP_MISC_MEM: begin
                end
                OP_SYSTEM: begin
                    if (uop.inst == 32'h0000_0073) begin
                        result.csrUpdate.valid = 1'b1;
                        result.csrUpdate.state.mepc = uop.pc;
                        result.csrUpdate.state.mcause = 32'd11;
                        result.csrUpdate.state.mstatus[7] = csr.mstatus[3];
                        result.csrUpdate.state.mstatus[3] = 1'b0;
                        result.branch = 1'b1;
                        result.redirect = 1'b1;
                        result.redirectPc = {csr.mtvec[31:2], 2'b00};
                        result.branchMiss = 1'b1;
                    end else if (uop.inst == 32'h0010_0073) begin
                        result.csrUpdate.valid = 1'b1;
                        result.csrUpdate.state.mepc = uop.pc;
                        result.csrUpdate.state.mcause = 32'd3;
                        result.csrUpdate.state.mstatus[7] = csr.mstatus[3];
                        result.csrUpdate.state.mstatus[3] = 1'b0;
                        result.branch = 1'b1;
                        result.redirect = 1'b1;
                        result.redirectPc = {csr.mtvec[31:2], 2'b00};
                        result.branchMiss = 1'b1;
                    end else if (uop.inst == 32'h3020_0073) begin
                        result.csrUpdate.valid = 1'b1;
                        result.csrUpdate.state.mstatus[3] = csr.mstatus[7];
                        result.csrUpdate.state.mstatus[7] = 1'b1;
                        result.branch = 1'b1;
                        result.redirect = 1'b1;
                        result.redirectPc = csr.mepc;
                        result.branchMiss = 1'b1;
                    end else if (f3 != 3'b000) begin
                        csrOld = csr_read_value(uop.inst[31:20], csr, cycle, commitCnt);
                        csrOperand = f3[2] ? {27'b0, uop.inst[19:15]} : a;
                        csrNew = csr_next_value(f3, csrOld, csrOperand);
                        csrDoWrite = (f3 == 3'b001 || f3 == 3'b101) ||
                                     ((f3 == 3'b010 || f3 == 3'b011) && rs1(uop.inst) != 5'd0) ||
                                     ((f3 == 3'b110 || f3 == 3'b111) && uop.inst[19:15] != 5'd0);
                        if (csrDoWrite) apply_csr_write(uop.inst[31:20], csrNew, result.csrUpdate);
                        result.wb.valid = writes_rd(uop.inst);
                        result.wb.rd = rd(uop.inst);
                        result.wb.data = csrOld;
                    end
                end
                default: begin
                end
            endcase
        end
    endtask

    always_comb begin
        execute_one(exUop[0], '0, exResult[0]);
        execute_one(exUop[1], exResult[0].wb, exResult[1]);
    end
endmodule
