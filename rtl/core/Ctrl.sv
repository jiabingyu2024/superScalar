import BasicTypes::*;
import PipelineTypes::*;

module Ctrl(
    CtrlIF.CtrlUnit ctrl,
    RecoveryManagerIF.CtrlUnit recovery
);
    logic frontendBlock;
    logic backendBlock;

    always_comb begin
        ctrl.exStageEmpty = ctrl.aluStageEmpty &&
                            ctrl.memStageEmpty &&
                            ctrl.mulStageEmpty &&
                            ctrl.brcStageEmpty &&
                            ctrl.sysStageEmpty;

        backendBlock = ctrl.isStallReq | ctrl.rrStallReq |
                       ctrl.exStallReq | ctrl.wbStallReq;
        frontendBlock = ctrl.serialBlock | backendBlock | ctrl.robFull | ctrl.issueQueueFull |
                        ctrl.freeListEmpty | ctrl.idStallReq | ctrl.rnStallReq |
                        ctrl.dsStallReq;

        ctrl.pfPipe = '{stall: frontendBlock, flush: 1'b0};
        ctrl.ifPipe = '{stall: frontendBlock, flush: 1'b0};
        ctrl.idPipe = '{stall: frontendBlock, flush: 1'b0};
        ctrl.rnPipe = '{stall: ctrl.serialBlock | ctrl.rnStallReq | ctrl.dsStallReq | ctrl.robFull |
                              ctrl.issueQueueFull | ctrl.freeListEmpty,
                        flush: 1'b0};
        ctrl.dsPipe = '{stall: ctrl.dsStallReq | ctrl.robFull | ctrl.issueQueueFull,
                        flush: 1'b0};
        ctrl.isPipe = '{stall: ctrl.isStallReq | ctrl.rrStallReq | ctrl.exStallReq, flush: 1'b0};
        ctrl.rrPipe = '{stall: ctrl.rrStallReq | ctrl.exStallReq, flush: 1'b0};
        ctrl.exPipe = '{stall: ctrl.exStallReq, flush: 1'b0};
        ctrl.wbPipe = '{stall: ctrl.wbStallReq, flush: 1'b0};

        if (recovery.recoveryInfo.valid) begin
            ctrl.pfPipe.flush = recovery.recoveryInfo.frontendFlush;
            ctrl.ifPipe.flush = recovery.recoveryInfo.frontendFlush;
            ctrl.idPipe.flush = recovery.recoveryInfo.frontendFlush;
            ctrl.rnPipe.flush = recovery.recoveryInfo.backendFlush;
            ctrl.dsPipe.flush = recovery.recoveryInfo.backendFlush;
            ctrl.isPipe.flush = recovery.recoveryInfo.backendFlush;
            ctrl.rrPipe.flush = recovery.recoveryInfo.backendFlush;
            ctrl.exPipe.flush = recovery.recoveryInfo.backendFlush;
            ctrl.wbPipe.flush = recovery.recoveryInfo.backendFlush;

            ctrl.pfPipe.stall = 1'b0;
            ctrl.ifPipe.stall = 1'b0;
            ctrl.idPipe.stall = 1'b0;
            ctrl.rnPipe.stall = 1'b0;
            ctrl.dsPipe.stall = 1'b0;
            ctrl.isPipe.stall = 1'b0;
            ctrl.rrPipe.stall = 1'b0;
            ctrl.exPipe.stall = 1'b0;
            ctrl.wbPipe.stall = 1'b0;
        end
    end
endmodule
