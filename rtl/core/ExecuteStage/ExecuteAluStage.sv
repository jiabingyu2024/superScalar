import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module ExecuteAluStage(
    ReadRegStageIF.ExecuteAluStage prev,
    ExecuteStageIF.ExecuteAluStage self,
    CtrlIF.ExecuteStage ctrl,
    BypassIF.ExecuteAluStage bypass
);
    RrToExAluPath pipeReg [WAY_NUM];

    function automatic DataPath alu(input SubTypePath st, input DataPath a, input DataPath b);
        unique case (st.aluSubType)
            ALU_SUBTYPE_ADD: alu = a + b;
            ALU_SUBTYPE_SUB: alu = a - b;
            ALU_SUBTYPE_SLL: alu = a << b[4:0];
            ALU_SUBTYPE_SRL: alu = a >> b[4:0];
            ALU_SUBTYPE_SRA: alu = DataPath'($signed(a) >>> b[4:0]);
            ALU_SUBTYPE_XOR: alu = a ^ b;
            ALU_SUBTYPE_OR:  alu = a | b;
            ALU_SUBTYPE_AND: alu = a & b;
            ALU_SUBTYPE_SLT: alu = DataPath'($signed(a) < $signed(b));
            ALU_SUBTYPE_SLTU: alu = DataPath'(a < b);
            default:         alu = '0;
        endcase
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToAluStage;
        end
    end

    always_comb begin
        ctrl.aluStageEmpty = 1'b1;
        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) begin
            bypass.aluReadReq[i] = '0;
        end
        for (int i = 0; i < WAY_NUM; i++) begin
            DataPath a;
            DataPath b;
            bypass.aluReadReq[i*2+0].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.aluReadReq[i*2+0].phyRegNum = pipeReg[i].Rs1;
            bypass.aluReadReq[i*2+1].valid = pipeReg[i].valid && pipeReg[i].srcBIsRs2;
            bypass.aluReadReq[i*2+1].phyRegNum = pipeReg[i].Rs2;
            a = bypass.aluReadRes[i*2+0].hit ? bypass.aluReadRes[i*2+0].data : pipeReg[i].dataA;
            b = bypass.aluReadRes[i*2+1].hit ? bypass.aluReadRes[i*2+1].data : pipeReg[i].dataB;

            self.nextAluToStage[i].valid = pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall;
            self.nextAluToStage[i].Rd = pipeReg[i].Rd;
            self.nextAluToStage[i].writeRd = pipeReg[i].writeRd;
            self.nextAluToStage[i].data = alu(pipeReg[i].subType, a, b);
            self.nextAluToStage[i].robIndex = pipeReg[i].robIndex;
            ctrl.aluStageEmpty &= !self.nextAluToStage[i].valid;
        end
    end
endmodule
