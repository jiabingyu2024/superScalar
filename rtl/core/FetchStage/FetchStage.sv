
import BasicTypes::*;
import PipelineTypes::*;


module FetchStage(
    PreFetchStageIF.FetchStage prev,
    FetchStageIF.FetchStage    self,
    IromAccessIF.core          iromAccess,
    CtrlIF.FetchStage          ctrl
);
    PfToIfPath pipeReg[WAY_NUM];
    IfToIdPath nextStage[WAY_NUM];

    always_ff @(posedge self.clk) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end 
        else if (!ctrl.ifPipe.stall) begin
            pipeReg <= prev.nextStage; 
        end
    end

    always_comb begin
        for (int i = 0; i < WAY_NUM; i++) begin
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].inst = iromAccess.inst[i];
            nextStage[i].predInfo = pipeReg[i].predInfo;
            nextStage[i].valid = pipeReg[i].valid && !ctrl.ifPipe.flush; // 如果当前指令有效且没有被清空，则传递到下一阶段
        end
    end

    assign self.nextStage = nextStage;


endmodule
