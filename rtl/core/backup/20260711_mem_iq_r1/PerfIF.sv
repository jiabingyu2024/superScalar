interface PerfIF(input logic clk, rst);
    logic [63:0] cycle;
    logic [63:0] commitCnt;
    logic [63:0] branchCnt;
    logic [63:0] branchMissCnt;
    logic [63:0] condBranchCnt;
    logic [63:0] condBranchMissCnt;
    logic [63:0] jalCnt;
    logic [63:0] jalMissCnt;
    logic [63:0] jalrCnt;
    logic [63:0] jalrMissCnt;
    logic [63:0] frontendStallCycles;
    logic [63:0] idStallCycles;
    logic [63:0] rnStallCycles;
    logic [63:0] dsStallCycles;
    logic [63:0] isStallCycles;
    logic [63:0] rrStallCycles;
    logic [63:0] exStallCycles;
    logic [63:0] wbStallCycles;
    logic [63:0] robFullCycles;
    logic [63:0] issueQueueFullCycles;
    logic [63:0] intIssueQueueFullCycles;
    logic [63:0] memIssueQueueFullCycles;
    logic [63:0] mulIssueQueueFullCycles;
    logic [63:0] robHeadNotDoneCycles;
    logic [63:0] robHeadNotDoneIntCycles;
    logic [63:0] robHeadNotDoneMemCycles;
    logic [63:0] robHeadNotDoneMulCycles;
    logic [63:0] robHeadNotDoneOtherCycles;
    logic [63:0] robHeadStoreCommitWaitCycles;
    logic [63:0] freeListEmptyCycles;
    logic [63:0] storeBufferFullCycles;
    logic [63:0] serialBlockCycles;
    logic [63:0] memLoadReturnBlockCycles;
    logic [63:0] memLoadAccessBlockCycles;
    logic [63:0] storeCommitBlockedByLoadCycles;
    logic [63:0] recoveryCycles;
    logic [63:0] dispatchWidth0Cycles;
    logic [63:0] dispatchWidth1Cycles;
    logic [63:0] dispatchWidth2Cycles;
    logic [63:0] issueWidth0Cycles;
    logic [63:0] issueWidth1Cycles;
    logic [63:0] issueWidth2Cycles;
    logic [63:0] commitWidth0Cycles;
    logic [63:0] commitWidth1Cycles;
    logic [63:0] commitWidth2Cycles;
    logic [63:0] intIssueCount;
    logic [63:0] memIssueCount;
    logic [63:0] mulIssueCount;
    logic [63:0] memReqValidCycles;
    logic [63:0] memPartialAliasCycles;
    logic [63:0] memNoAliasCycles;
    logic [63:0] memForwardCycles;
    logic [63:0] memIqHeadNotReadyCycles;
    logic [63:0] memIqYoungerReadyCycles;
    logic [63:0] mulOpCount;
    logic [63:0] divOpCount;
    logic [63:0] remOpCount;
    logic [63:0] muldivBusyCycles;

    modport core(
        output cycle,
        output commitCnt,
        output branchCnt,
        output branchMissCnt,
        output condBranchCnt,
        output condBranchMissCnt,
        output jalCnt,
        output jalMissCnt,
        output jalrCnt,
        output jalrMissCnt,
        output frontendStallCycles,
        output idStallCycles,
        output rnStallCycles,
        output dsStallCycles,
        output isStallCycles,
        output rrStallCycles,
        output exStallCycles,
        output wbStallCycles,
        output robFullCycles,
        output issueQueueFullCycles,
        output intIssueQueueFullCycles,
        output memIssueQueueFullCycles,
        output mulIssueQueueFullCycles,
        output robHeadNotDoneCycles,
        output robHeadNotDoneIntCycles,
        output robHeadNotDoneMemCycles,
        output robHeadNotDoneMulCycles,
        output robHeadNotDoneOtherCycles,
        output robHeadStoreCommitWaitCycles,
        output freeListEmptyCycles,
        output storeBufferFullCycles,
        output serialBlockCycles,
        output memLoadReturnBlockCycles,
        output memLoadAccessBlockCycles,
        output storeCommitBlockedByLoadCycles,
        output recoveryCycles,
        output dispatchWidth0Cycles,
        output dispatchWidth1Cycles,
        output dispatchWidth2Cycles,
        output issueWidth0Cycles,
        output issueWidth1Cycles,
        output issueWidth2Cycles,
        output commitWidth0Cycles,
        output commitWidth1Cycles,
        output commitWidth2Cycles,
        output intIssueCount,
        output memIssueCount,
        output mulIssueCount,
        output memReqValidCycles,
        output memPartialAliasCycles,
        output memNoAliasCycles,
        output memForwardCycles,
        output memIqHeadNotReadyCycles,
        output memIqYoungerReadyCycles,
        output mulOpCount,
        output divOpCount,
        output remOpCount,
        output muldivBusyCycles
    );
endinterface : PerfIF
