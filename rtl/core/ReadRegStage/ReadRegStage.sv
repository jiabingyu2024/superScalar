import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module RegReadStage(
    IssueStageIF.ReadRegStage prev,
    ReadRegStageIF.ReadRegStage self,
    RegFileIF.ReadRegStage regFile,
    CtrlIF.ReadRegStage ctrl
);
    IsToRrPath pipeReg [WAY_NUM];

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.rrPipe.stall) begin
            pipeReg <= prev.nextStage;
        end
    end

    always_comb begin
        ctrl.rrStallReq = 1'b0;
        ctrl.rrStageEmpty = 1'b1;

        for (int i = 0; i < REGFILE_READ_PORT_NUM; i++) begin
            regFile.regFileReadReq[i] = '0;
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            int rp;
            DataPath dataA;
            DataPath dataB;

            rp = i * 2;
            regFile.regFileReadReq[rp + 0].enaRead = pipeReg[i].valid && !ctrl.rrPipe.flush;
            regFile.regFileReadReq[rp + 0].regIndex = pipeReg[i].srcA;
            regFile.regFileReadReq[rp + 1].enaRead = pipeReg[i].valid && !ctrl.rrPipe.flush;
            regFile.regFileReadReq[rp + 1].regIndex = pipeReg[i].srcB;

            unique case (pipeReg[i].opTypeA)
                OP_TYPE_PC:  dataA = pipeReg[i].pc;
                OP_TYPE_IMM: dataA = pipeReg[i].imm;
                default:     dataA = regFile.regFileReadRes[rp + 0].data;
            endcase
            unique case (pipeReg[i].opTypeB)
                OP_TYPE_IMM: dataB = pipeReg[i].imm;
                OP_TYPE_PC:  dataB = pipeReg[i].pc;
                default:     dataB = regFile.regFileReadRes[rp + 1].data;
            endcase

            self.nextToAluStage[i] = '0;
            self.nextToMemStage[i] = '0;
            self.nextToMulStage[i] = '0;
            self.nextToBrcStage[i] = '0;
            self.nextToSysStage[i] = '0;

            unique case (pipeReg[i].tubeType)
                TUBE_TYPE_ALU: begin
                    self.nextToAluStage[i].valid = pipeReg[i].valid && !ctrl.rrPipe.flush;
                    self.nextToAluStage[i].subType = pipeReg[i].SubType;
                    self.nextToAluStage[i].dataA = dataA;
                    self.nextToAluStage[i].dataB = dataB;
                    self.nextToAluStage[i].Rs1 = pipeReg[i].srcA;
                    self.nextToAluStage[i].Rs2 = pipeReg[i].srcB;
                    self.nextToAluStage[i].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                    self.nextToAluStage[i].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                    self.nextToAluStage[i].Rd = pipeReg[i].dst;
                    self.nextToAluStage[i].writeRd = pipeReg[i].writeDst;
                    self.nextToAluStage[i].robIndex = pipeReg[i].robIndex;
                end
                TUBE_TYPE_MEM: begin
                    self.nextToMemStage[i].valid = pipeReg[i].valid && !ctrl.rrPipe.flush;
                    self.nextToMemStage[i].subType = pipeReg[i].SubType;
                    self.nextToMemStage[i].dataA = dataA;
                    self.nextToMemStage[i].dataB = dataB;
                    self.nextToMemStage[i].Rs1 = pipeReg[i].srcA;
                    self.nextToMemStage[i].Rs2 = pipeReg[i].srcB;
                    self.nextToMemStage[i].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                    self.nextToMemStage[i].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                    self.nextToMemStage[i].imm = pipeReg[i].imm;
                    self.nextToMemStage[i].Rd = pipeReg[i].dst;
                    self.nextToMemStage[i].writeRd = pipeReg[i].writeDst;
                    self.nextToMemStage[i].robIndex = pipeReg[i].robIndex;
                    self.nextToMemStage[i].storeBufferIndexValid = pipeReg[i].storeBufferIndexValid;
                    self.nextToMemStage[i].storeBufferIndex = pipeReg[i].storeBufferIndex;
                end
                TUBE_TYPE_MUL: begin
                    self.nextToMulStage[i].valid = pipeReg[i].valid && !ctrl.rrPipe.flush;
                    self.nextToMulStage[i].subType = pipeReg[i].SubType;
                    self.nextToMulStage[i].dataA = dataA;
                    self.nextToMulStage[i].dataB = dataB;
                    self.nextToMulStage[i].Rs1 = pipeReg[i].srcA;
                    self.nextToMulStage[i].Rs2 = pipeReg[i].srcB;
                    self.nextToMulStage[i].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                    self.nextToMulStage[i].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                    self.nextToMulStage[i].Rd = pipeReg[i].dst;
                    self.nextToMulStage[i].writeRd = pipeReg[i].writeDst;
                    self.nextToMulStage[i].robIndex = pipeReg[i].robIndex;
                end
                TUBE_TYPE_BRC: begin
                    self.nextToBrcStage[i].valid = pipeReg[i].valid && !ctrl.rrPipe.flush;
                    self.nextToBrcStage[i].subType = pipeReg[i].SubType;
                    self.nextToBrcStage[i].dataA = dataA;
                    self.nextToBrcStage[i].dataB = dataB;
                    self.nextToBrcStage[i].Rs1 = pipeReg[i].srcA;
                    self.nextToBrcStage[i].Rs2 = pipeReg[i].srcB;
                    self.nextToBrcStage[i].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                    self.nextToBrcStage[i].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                    self.nextToBrcStage[i].pc = pipeReg[i].pc;
                    self.nextToBrcStage[i].imm = pipeReg[i].imm;
                    self.nextToBrcStage[i].Rd = pipeReg[i].dst;
                    self.nextToBrcStage[i].writeRd = pipeReg[i].writeDst;
                    self.nextToBrcStage[i].robIndex = pipeReg[i].robIndex;
                end
                default: begin
                    self.nextToSysStage[i].valid = pipeReg[i].valid && !ctrl.rrPipe.flush;
                    self.nextToSysStage[i].subType = pipeReg[i].SubType;
                    self.nextToSysStage[i].pc = pipeReg[i].pc;
                    self.nextToSysStage[i].dataA = dataA;
                    self.nextToSysStage[i].Rs1 = pipeReg[i].srcA;
                    self.nextToSysStage[i].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                    self.nextToSysStage[i].csrAddr = pipeReg[i].csrAddr;
                    self.nextToSysStage[i].Rd = pipeReg[i].dst;
                    self.nextToSysStage[i].writeRd = pipeReg[i].writeDst;
                    self.nextToSysStage[i].robIndex = pipeReg[i].robIndex;
                end
            endcase

            ctrl.rrStageEmpty &= !(pipeReg[i].valid && !ctrl.rrPipe.flush);
        end
    end
endmodule
