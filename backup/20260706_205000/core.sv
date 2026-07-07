import BasicTypes::*;
import PipelineTypes::*;
import RenameTypes::*;
import IssueTypes::*;
import ReadRegTypes::*;
import ROBTypes::*;
import StoreBufferTypes::*;
import RecoveryTypes::*;

module core(
    input logic clk,
    input logic rst,

    // irom interface
    IromAccessIF.core iromAccess,

    // dram interface
    DramAccessIF dromAccess,

    //debug interface
    DebugIF.core debug,

    // performance counter interface
    PerfIF.core perf

);
    PreFetchStageIF    pfStageIF(clk, rst);
    FetchStageIF       ifStageIF(clk, rst);
    DecodeStageIF      idStageIF(clk, rst);
    RenameStageIF      rnStageIF(clk, rst);
    DispatchStageIF    dsStageIF(clk, rst);
    IssueStageIF       isStageIF(clk, rst);
    ReadRegStageIF     rrStageIF(clk, rst);
    ExecuteStageIF     exStageIF(clk, rst);
    WriteBackStageIF   wbStageIF(clk, rst);
    CommitStageIF      cmStageIF(clk, rst);
    CtrlIF             ctrlIF(clk, rst);
    RecoveryManagerIF  recoveryManagerIF(clk, rst);
    ROBIF              robIF(clk, rst);
    IssueQueueIF       issueQueueIF(clk, rst);
    PayloadIF          payloadIF(clk, rst);
    StoreBufferIF      storeBufferIF(clk, rst);
    SpecRATIF          specRATIF(clk, rst);
    ArchRATIF          archRATIF(clk, rst);
    FreeListIF         freeListIF(clk, rst);
    ReadyTableIF       readyTableIF(clk, rst);
    RegFileIF          regFileIF(clk, rst);
    BypassIF           bypassIF(clk, rst);

    assign readyTableIF.recoverReadyAll = recoveryManagerIF.recoveryInfo.valid &&
                                          recoveryManagerIF.recoveryInfo.backendFlush;
    //PF
    /*
    更新 PC 的选择逻辑
    */
    PreFetchStage preFetchStage( pfStageIF, iromAccess, ctrlIF, recoveryManagerIF );
        PC pc( pfStageIF);
        // 分支预测部分
        BPU bpu( pfStageIF, ifStageIF, ctrlIF, recoveryManagerIF);
    //IF   接口例化格式：(上一级，本级，控制，其他)
    /*

    */
    FetchStage fetchStage  (pfStageIF, ifStageIF, iromAccess, ctrlIF);
    
    //ID
    DecodeStage decodeStage (ifStageIF, idStageIF, ctrlIF);

    //RN
    // RenameStage 内完成 组内相关性检查  部分预测错误纠正recovery和 分支限制一条出错后的恢复ctrl
    RenameStage renameStage (idStageIF, rnStageIF, ctrlIF, specRATIF, freeListIF, readyTableIF, recoveryManagerIF);
        SpecRAT specRAT(specRATIF);
        ArchRAT archRAT(archRATIF);
        FreeList freeList(freeListIF);
        ReadyTable readyTable(readyTableIF);

    //DS dispatch
    DispatchStage dispatchStage (rnStageIF, dsStageIF, issueQueueIF, payloadIF, ctrlIF, robIF, storeBufferIF);
        ROB rob(robIF);
        IssueQueue issueQueue(issueQueueIF);
        Payload payload(payloadIF);
        StoreBuffer storeBuffer(storeBufferIF, dromAccess);
    //IS issue 
    IssueStage issueStage (dsStageIF, isStageIF, ctrlIF, issueQueueIF, payloadIF);

    //RR
    RegReadStage regReadStage (isStageIF, rrStageIF, regFileIF, ctrlIF);
        RegFile regFile(regFileIF);
    //EX
    //RW
    ExecuteAluStage executeAluStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteBrcStage executeBrcStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteMulStage executeMulStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteMemStage executeMemStage (rrStageIF, exStageIF, ctrlIF, dromAccess, storeBufferIF, bypassIF);
    ExecuteSysStage executeSysStage (rrStageIF, exStageIF, ctrlIF, bypassIF);

    WriteBackStage writeBackStage (exStageIF, wbStageIF, ctrlIF, recoveryManagerIF,
                                   bypassIF, regFileIF, robIF, readyTableIF, issueQueueIF);

    Bypass bypass(bypassIF);
    //CM

    CommitStage cmStage (cmStageIF, recoveryManagerIF, ctrlIF, archRATIF, specRATIF, freeListIF, storeBufferIF, robIF);

    RecoveryManager recoveryManager(recoveryManagerIF,ctrlIF,specRATIF,freeListIF);

    Ctrl ctrl(ctrlIF,recoveryManagerIF);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            perf.cycle <= '0;
            perf.commitCnt <= '0;
            perf.branchCnt <= '0;
            perf.branchMissCnt <= '0;
            perf.condBranchCnt <= '0;
            perf.condBranchMissCnt <= '0;
            perf.jalCnt <= '0;
            perf.jalMissCnt <= '0;
            perf.jalrCnt <= '0;
            perf.jalrMissCnt <= '0;
            perf.frontendStallCycles <= '0;
            perf.idStallCycles <= '0;
            perf.rnStallCycles <= '0;
            perf.dsStallCycles <= '0;
            perf.isStallCycles <= '0;
            perf.rrStallCycles <= '0;
            perf.exStallCycles <= '0;
            perf.wbStallCycles <= '0;
            perf.robFullCycles <= '0;
            perf.issueQueueFullCycles <= '0;
            perf.intIssueQueueFullCycles <= '0;
            perf.memIssueQueueFullCycles <= '0;
            perf.mulIssueQueueFullCycles <= '0;
            perf.robHeadNotDoneCycles <= '0;
            perf.robHeadNotDoneIntCycles <= '0;
            perf.robHeadNotDoneMemCycles <= '0;
            perf.robHeadNotDoneMulCycles <= '0;
            perf.robHeadNotDoneOtherCycles <= '0;
            perf.robHeadStoreCommitWaitCycles <= '0;
            perf.freeListEmptyCycles <= '0;
            perf.storeBufferFullCycles <= '0;
            perf.serialBlockCycles <= '0;
            perf.memLoadReturnBlockCycles <= '0;
            perf.memLoadAccessBlockCycles <= '0;
            perf.storeCommitBlockedByLoadCycles <= '0;
            perf.recoveryCycles <= '0;
            perf.dispatchWidth0Cycles <= '0;
            perf.dispatchWidth1Cycles <= '0;
            perf.dispatchWidth2Cycles <= '0;
            perf.issueWidth0Cycles <= '0;
            perf.issueWidth1Cycles <= '0;
            perf.issueWidth2Cycles <= '0;
            perf.commitWidth0Cycles <= '0;
            perf.commitWidth1Cycles <= '0;
            perf.commitWidth2Cycles <= '0;
            perf.intIssueCount <= '0;
            perf.memIssueCount <= '0;
            perf.mulIssueCount <= '0;
        end else begin
            int commitThisCycle;
            int dispatchThisCycle;
            int issueThisCycle;
            int intIssueThisCycle;
            int memIssueThisCycle;
            int mulIssueThisCycle;
            commitThisCycle = 0;
            dispatchThisCycle = 0;
            issueThisCycle = 0;
            intIssueThisCycle = 0;
            memIssueThisCycle = 0;
            mulIssueThisCycle = 0;
            perf.cycle <= perf.cycle + 1'b1;
            for (int i = 0; i < WAY_NUM; i++) begin
                if (cmStageIF.commitValid[i]) begin
                    commitThisCycle++;
                end
                if (dsStageIF.nextStage[i].valid) begin
                    dispatchThisCycle++;
                end
            end
            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                if (isStageIF.nextStage[i].valid) begin
                    issueThisCycle++;
                    if (isStageIF.nextStage[i].tubeType inside {TUBE_TYPE_ALU,
                                                                TUBE_TYPE_BRC,
                                                                TUBE_TYPE_SYS}) begin
                        intIssueThisCycle++;
                    end else if (isStageIF.nextStage[i].tubeType == TUBE_TYPE_MEM) begin
                        memIssueThisCycle++;
                    end else if (isStageIF.nextStage[i].tubeType == TUBE_TYPE_MUL) begin
                        mulIssueThisCycle++;
                    end
                end
            end
            perf.commitCnt <= perf.commitCnt + commitThisCycle;
            perf.frontendStallCycles <= perf.frontendStallCycles + ctrlIF.pfPipe.stall;
            perf.idStallCycles <= perf.idStallCycles + ctrlIF.idPipe.stall;
            perf.rnStallCycles <= perf.rnStallCycles + ctrlIF.rnPipe.stall;
            perf.dsStallCycles <= perf.dsStallCycles + ctrlIF.dsPipe.stall;
            perf.isStallCycles <= perf.isStallCycles + ctrlIF.isPipe.stall;
            perf.rrStallCycles <= perf.rrStallCycles + ctrlIF.rrPipe.stall;
            perf.exStallCycles <= perf.exStallCycles + ctrlIF.exPipe.stall;
            perf.wbStallCycles <= perf.wbStallCycles + ctrlIF.wbPipe.stall;
            perf.robFullCycles <= perf.robFullCycles + ctrlIF.robFull;
            perf.issueQueueFullCycles <= perf.issueQueueFullCycles + ctrlIF.issueQueueFull;
            perf.intIssueQueueFullCycles <= perf.intIssueQueueFullCycles + ctrlIF.intIssueQueueFull;
            perf.memIssueQueueFullCycles <= perf.memIssueQueueFullCycles + ctrlIF.memIssueQueueFull;
            perf.mulIssueQueueFullCycles <= perf.mulIssueQueueFullCycles + ctrlIF.mulIssueQueueFull;
            if (robIF.RobPopRes[0].valid && !robIF.RobPopRes[0].entry.done) begin
                perf.robHeadNotDoneCycles <= perf.robHeadNotDoneCycles + 1'b1;
                unique case (robIF.RobPopRes[0].entry.tubeType)
                    TUBE_TYPE_ALU,
                    TUBE_TYPE_BRC,
                    TUBE_TYPE_SYS: perf.robHeadNotDoneIntCycles <=
                        perf.robHeadNotDoneIntCycles + 1'b1;
                    TUBE_TYPE_MEM: perf.robHeadNotDoneMemCycles <=
                        perf.robHeadNotDoneMemCycles + 1'b1;
                    TUBE_TYPE_MUL: perf.robHeadNotDoneMulCycles <=
                        perf.robHeadNotDoneMulCycles + 1'b1;
                    default: perf.robHeadNotDoneOtherCycles <=
                        perf.robHeadNotDoneOtherCycles + 1'b1;
                endcase
            end
            if (robIF.RobPopRes[0].valid &&
                robIF.RobPopRes[0].entry.done &&
                robIF.RobPopRes[0].entry.isStore &&
                !storeBufferIF.StoreBufferCommitReady) begin
                perf.robHeadStoreCommitWaitCycles <= perf.robHeadStoreCommitWaitCycles + 1'b1;
            end
            perf.freeListEmptyCycles <= perf.freeListEmptyCycles + ctrlIF.freeListEmpty;
            perf.storeBufferFullCycles <= perf.storeBufferFullCycles +
                                          (ctrlIF.dsStallReq && !storeBufferIF.allocRdy);
            perf.serialBlockCycles <= perf.serialBlockCycles + ctrlIF.serialBlock;
            perf.memLoadReturnBlockCycles <= perf.memLoadReturnBlockCycles +
                                             ctrlIF.memLoadReturnBlockReq;
            perf.memLoadAccessBlockCycles <= perf.memLoadAccessBlockCycles +
                                             ctrlIF.memLoadAccessBlockReq;
            perf.storeCommitBlockedByLoadCycles <= perf.storeCommitBlockedByLoadCycles +
                (storeBufferIF.StoreBufferCommitReq.valid &&
                 storeBufferIF.StoreBufferCommit.valid &&
                 dromAccess.readEn);
            perf.intIssueCount <= perf.intIssueCount + intIssueThisCycle;
            perf.memIssueCount <= perf.memIssueCount + memIssueThisCycle;
            perf.mulIssueCount <= perf.mulIssueCount + mulIssueThisCycle;
            perf.recoveryCycles <= perf.recoveryCycles + recoveryManagerIF.recoveryInfo.valid;
            unique case (dispatchThisCycle)
                0: perf.dispatchWidth0Cycles <= perf.dispatchWidth0Cycles + 1'b1;
                1: perf.dispatchWidth1Cycles <= perf.dispatchWidth1Cycles + 1'b1;
                default: perf.dispatchWidth2Cycles <= perf.dispatchWidth2Cycles + 1'b1;
            endcase
            unique case (issueThisCycle)
                0: perf.issueWidth0Cycles <= perf.issueWidth0Cycles + 1'b1;
                1: perf.issueWidth1Cycles <= perf.issueWidth1Cycles + 1'b1;
                default: perf.issueWidth2Cycles <= perf.issueWidth2Cycles + 1'b1;
            endcase
            unique case (commitThisCycle)
                0: perf.commitWidth0Cycles <= perf.commitWidth0Cycles + 1'b1;
                1: perf.commitWidth1Cycles <= perf.commitWidth1Cycles + 1'b1;
                default: perf.commitWidth2Cycles <= perf.commitWidth2Cycles + 1'b1;
            endcase
            if (recoveryManagerIF.commitBranchUpdateValid) begin
                perf.branchCnt <= perf.branchCnt + 1'b1;
                unique case (cmStageIF.commitBranchSubType)
                    BRC_SUBTYPE_JAL:  perf.jalCnt <= perf.jalCnt + 1'b1;
                    BRC_SUBTYPE_JALR: perf.jalrCnt <= perf.jalrCnt + 1'b1;
                    default:          perf.condBranchCnt <= perf.condBranchCnt + 1'b1;
                endcase
            end
            if (cmStageIF.commitBranchMiss) begin
                perf.branchMissCnt <= perf.branchMissCnt + 1'b1;
                unique case (cmStageIF.commitBranchSubType)
                    BRC_SUBTYPE_JAL:  perf.jalMissCnt <= perf.jalMissCnt + 1'b1;
                    BRC_SUBTYPE_JALR: perf.jalrMissCnt <= perf.jalrMissCnt + 1'b1;
                    default:          perf.condBranchMissCnt <= perf.condBranchMissCnt + 1'b1;
                endcase
            end
        end
    end

endmodule
