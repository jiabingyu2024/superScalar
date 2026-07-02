// 预取指令阶段
// 负责: 确定下一个pc，将pc发往irom
// pc 来源： 1. pc + sizeof(WAY_NUM*) 或者分支预测器预测的地址
//          2. 分支预测模块命中结果
//          3. recovery manager 恢复的地址
//          4. stall 或者 flush 信号导致的地址（如异常处理地址）

import BasicTypes::*;
import PipelineTypes::*;
import RecoveryTypes::*;

module PreFetchStage(
    PreFetchStageIF.PreFetchStage self,
    IromAccessIF.core             iromAccess,
    CtrlIF.PreFetchStage          ctrl,
    RecoveryManagerIF.PreFetchStage recovery
);
    
    always_comb begin
        logic predTakenSeen;

        self.pcIn = self.pcOut + PC_STEP;
        self.predictPc = self.pcOut + PC_STEP;
        self.pcWe = !ctrl.pfPipe.stall;
        predTakenSeen = 1'b0;

        if (recovery.pcUpdateEn) begin
            self.pcIn = recovery.pcUpdate;
            self.predictPc = recovery.pcUpdate;
            self.pcWe = 1'b1;
        end else begin
            for (int i = 0; i < WAY_NUM; i++) begin
                if (!predTakenSeen && self.bpuResult[i].btbhit && self.bpuResult[i].taken) begin
                    self.pcIn = self.bpuResult[i].target;
                    self.predictPc = self.bpuResult[i].target;
                    predTakenSeen = 1'b1;
                end
            end
        end

        iromAccess.ena = !ctrl.pfPipe.stall;
        iromAccess.iromAddr = self.pcOut;

        predTakenSeen = 1'b0;
        for (int i = 0; i < WAY_NUM; i++) begin
            self.nextStage[i].valid = !ctrl.pfPipe.flush && !ctrl.pfPipe.stall && !predTakenSeen;
            self.nextStage[i].pc = self.pcOut + PcPath'(i * 4);
            self.nextStage[i].predInfo.pcPred = self.bpuResult[i].taken ?
                                                self.bpuResult[i].target :
                                                (self.pcOut + PcPath'(i * 4) + 32'd4);
            self.nextStage[i].predInfo.isPred = self.bpuResult[i].taken;
            if (self.bpuResult[i].taken) begin
                predTakenSeen = 1'b1;
            end
        end
    end

endmodule
