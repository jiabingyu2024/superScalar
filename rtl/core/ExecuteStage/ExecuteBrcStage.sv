import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module ExecuteBrcStage(
    ReadRegStageIF.ExecuteBrcStage prev,
    ExecuteStageIF.ExecuteBrcStage self,
    CtrlIF.ExecuteStage ctrl,
    BypassIF.ExecuteBrcStage bypass
);
    RrToExBrcPath pipeReg [WAY_NUM];

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToBrcStage;
        end
    end

    always_comb begin
        ctrl.brcStageEmpty = 1'b1;
        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.brcReadReq[i] = '0;
        for (int i = 0; i < WAY_NUM; i++) begin
            DataPath a;
            DataPath b;
            bypass.brcReadReq[i*2+0].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.brcReadReq[i*2+0].phyRegNum = pipeReg[i].Rs1;
            bypass.brcReadReq[i*2+1].valid = pipeReg[i].valid && pipeReg[i].srcBIsRs2;
            bypass.brcReadReq[i*2+1].phyRegNum = pipeReg[i].Rs2;
            a = bypass.brcReadRes[i*2+0].hit ? bypass.brcReadRes[i*2+0].data : pipeReg[i].dataA;
            b = bypass.brcReadRes[i*2+1].hit ? bypass.brcReadRes[i*2+1].data : pipeReg[i].dataB;

            self.nextBrcToStage[i].valid = pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall;
            self.nextBrcToStage[i].Rd = pipeReg[i].Rd;
            self.nextBrcToStage[i].writeRd = pipeReg[i].writeRd;
            self.nextBrcToStage[i].data = pipeReg[i].pc + 32'd4;
            self.nextBrcToStage[i].robIndex = pipeReg[i].robIndex;
            self.nextBrcToStage[i].taken = 1'b0;
            self.nextBrcToStage[i].trueTargetPc = pipeReg[i].pc + 32'd4;

            unique case (pipeReg[i].subType.brcSubType)
                BRC_SUBTYPE_BEQ:  self.nextBrcToStage[i].taken = (a == b);
                BRC_SUBTYPE_BNE:  self.nextBrcToStage[i].taken = (a != b);
                BRC_SUBTYPE_BLT:  self.nextBrcToStage[i].taken = ($signed(a) < $signed(b));
                BRC_SUBTYPE_BGE:  self.nextBrcToStage[i].taken = ($signed(a) >= $signed(b));
                BRC_SUBTYPE_BLTU: self.nextBrcToStage[i].taken = (a < b);
                BRC_SUBTYPE_BGEU: self.nextBrcToStage[i].taken = (a >= b);
                BRC_SUBTYPE_JAL,
                BRC_SUBTYPE_JALR: self.nextBrcToStage[i].taken = 1'b1;
                default:          self.nextBrcToStage[i].taken = 1'b0;
            endcase

            if (pipeReg[i].subType.brcSubType == BRC_SUBTYPE_JALR) begin
                self.nextBrcToStage[i].trueTargetPc = (a + pipeReg[i].imm) & ~32'd1;
            end else if (self.nextBrcToStage[i].taken) begin
                self.nextBrcToStage[i].trueTargetPc = pipeReg[i].pc + pipeReg[i].imm;
            end
            ctrl.brcStageEmpty &= !self.nextBrcToStage[i].valid;
        end
    end
endmodule
