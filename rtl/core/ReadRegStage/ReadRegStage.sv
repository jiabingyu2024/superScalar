import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module RegReadStage(
    IssueStageIF.ReadRegStage prev,
    ReadRegStageIF.ReadRegStage self,
    RegFileIF.ReadRegStage regFile,
    CtrlIF.ReadRegStage ctrl
);
    IsToRrPath pipeReg [ISSUE_WIDTH];

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.rrPipe.flush) begin
            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.rrPipe.stall) begin
            pipeReg <= prev.nextStage;
        end
    end

    always_comb begin
        int aluCnt;
        int memCnt;
        int mulCnt;
        int brcCnt;
        int sysCnt;

        ctrl.rrStallReq = 1'b0;
        ctrl.rrStageEmpty = 1'b1;
        aluCnt = 0;
        memCnt = 0;
        mulCnt = 0;
        brcCnt = 0;
        sysCnt = 0;

        for (int i = 0; i < REGFILE_READ_PORT_NUM; i++) begin
            regFile.regFileReadReq[i] = '0;
        end
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            self.nextToAluStage[i] = '0;
            self.nextToBrcStage[i] = '0;
            self.nextToSysStage[i] = '0;
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            self.nextToMemStage[i] = '0;
        end
        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            self.nextToMulStage[i] = '0;
        end

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            int rp;
            DataPath dataA;
            DataPath dataB;
            logic fire;

            rp = i * 2;
            fire = pipeReg[i].valid && !ctrl.rrPipe.flush;
            regFile.regFileReadReq[rp + 0].enaRead = fire;
            regFile.regFileReadReq[rp + 0].regIndex = pipeReg[i].srcA;
            regFile.regFileReadReq[rp + 1].enaRead = fire;
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

            if (fire) begin
                unique case (pipeReg[i].tubeType)
                    TUBE_TYPE_ALU: begin
                        if (aluCnt < INT_ISSUE_WIDTH) begin
                            self.nextToAluStage[aluCnt].valid = 1'b1;
                            self.nextToAluStage[aluCnt].subType = pipeReg[i].SubType;
                            self.nextToAluStage[aluCnt].dataA = dataA;
                            self.nextToAluStage[aluCnt].dataB = dataB;
                            self.nextToAluStage[aluCnt].Rs1 = pipeReg[i].srcA;
                            self.nextToAluStage[aluCnt].Rs2 = pipeReg[i].srcB;
                            self.nextToAluStage[aluCnt].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                            self.nextToAluStage[aluCnt].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                            self.nextToAluStage[aluCnt].Rd = pipeReg[i].dst;
                            self.nextToAluStage[aluCnt].writeRd = pipeReg[i].writeDst;
                            self.nextToAluStage[aluCnt].robIndex = pipeReg[i].robIndex;
                        end
                        aluCnt++;
                    end
                    TUBE_TYPE_MEM: begin
                        if (memCnt < MEM_ISSUE_WIDTH) begin
                            self.nextToMemStage[memCnt].valid = 1'b1;
                            self.nextToMemStage[memCnt].subType = pipeReg[i].SubType;
                            self.nextToMemStage[memCnt].dataA = dataA;
                            self.nextToMemStage[memCnt].dataB = dataB;
                            self.nextToMemStage[memCnt].Rs1 = pipeReg[i].srcA;
                            self.nextToMemStage[memCnt].Rs2 = pipeReg[i].srcB;
                            self.nextToMemStage[memCnt].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                            self.nextToMemStage[memCnt].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                            self.nextToMemStage[memCnt].imm = pipeReg[i].imm;
                            self.nextToMemStage[memCnt].Rd = pipeReg[i].dst;
                            self.nextToMemStage[memCnt].writeRd = pipeReg[i].writeDst;
                            self.nextToMemStage[memCnt].robIndex = pipeReg[i].robIndex;
                            self.nextToMemStage[memCnt].storeBufferIndexValid =
                                pipeReg[i].storeBufferIndexValid;
                            self.nextToMemStage[memCnt].storeBufferIndex =
                                pipeReg[i].storeBufferIndex;
                        end
                        memCnt++;
                    end
                    TUBE_TYPE_MUL: begin
                        if (mulCnt < MUL_ISSUE_WIDTH) begin
                            self.nextToMulStage[mulCnt].valid = 1'b1;
                            self.nextToMulStage[mulCnt].subType = pipeReg[i].SubType;
                            self.nextToMulStage[mulCnt].dataA = dataA;
                            self.nextToMulStage[mulCnt].dataB = dataB;
                            self.nextToMulStage[mulCnt].Rs1 = pipeReg[i].srcA;
                            self.nextToMulStage[mulCnt].Rs2 = pipeReg[i].srcB;
                            self.nextToMulStage[mulCnt].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                            self.nextToMulStage[mulCnt].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                            self.nextToMulStage[mulCnt].Rd = pipeReg[i].dst;
                            self.nextToMulStage[mulCnt].writeRd = pipeReg[i].writeDst;
                            self.nextToMulStage[mulCnt].robIndex = pipeReg[i].robIndex;
                        end
                        mulCnt++;
                    end
                    TUBE_TYPE_BRC: begin
                        if (brcCnt < INT_ISSUE_WIDTH) begin
                            self.nextToBrcStage[brcCnt].valid = 1'b1;
                            self.nextToBrcStage[brcCnt].subType = pipeReg[i].SubType;
                            self.nextToBrcStage[brcCnt].dataA = dataA;
                            self.nextToBrcStage[brcCnt].dataB = dataB;
                            self.nextToBrcStage[brcCnt].Rs1 = pipeReg[i].srcA;
                            self.nextToBrcStage[brcCnt].Rs2 = pipeReg[i].srcB;
                            self.nextToBrcStage[brcCnt].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                            self.nextToBrcStage[brcCnt].srcBIsRs2 = pipeReg[i].opTypeB == OP_TYPE_REG;
                            self.nextToBrcStage[brcCnt].pc = pipeReg[i].pc;
                            self.nextToBrcStage[brcCnt].imm = pipeReg[i].imm;
                            self.nextToBrcStage[brcCnt].Rd = pipeReg[i].dst;
                            self.nextToBrcStage[brcCnt].writeRd = pipeReg[i].writeDst;
                            self.nextToBrcStage[brcCnt].robIndex = pipeReg[i].robIndex;
                        end
                        brcCnt++;
                    end
                    default: begin
                        if (sysCnt < INT_ISSUE_WIDTH) begin
                            self.nextToSysStage[sysCnt].valid = 1'b1;
                            self.nextToSysStage[sysCnt].subType = pipeReg[i].SubType;
                            self.nextToSysStage[sysCnt].pc = pipeReg[i].pc;
                            self.nextToSysStage[sysCnt].dataA = dataA;
                            self.nextToSysStage[sysCnt].Rs1 = pipeReg[i].srcA;
                            self.nextToSysStage[sysCnt].srcAIsRs1 = pipeReg[i].opTypeA == OP_TYPE_REG;
                            self.nextToSysStage[sysCnt].csrAddr = pipeReg[i].csrAddr;
                            self.nextToSysStage[sysCnt].Rd = pipeReg[i].dst;
                            self.nextToSysStage[sysCnt].writeRd = pipeReg[i].writeDst;
                            self.nextToSysStage[sysCnt].robIndex = pipeReg[i].robIndex;
                        end
                        sysCnt++;
                    end
                endcase
            end

            ctrl.rrStageEmpty &= !fire;
        end
    end
endmodule
