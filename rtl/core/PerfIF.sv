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

    modport core(
        output
            cycle,
            commitCnt,
            branchCnt,
            branchMissCnt,
            condBranchCnt,
            condBranchMissCnt,
            jalCnt,
            jalMissCnt,
            jalrCnt,
            jalrMissCnt,
            frontendStallCycles,
            idStallCycles,
            rnStallCycles,
            dsStallCycles,
            isStallCycles,
            rrStallCycles,
            exStallCycles,
            wbStallCycles,
            robFullCycles,
            issueQueueFullCycles,
            freeListEmptyCycles,
            storeBufferFullCycles,
            serialBlockCycles,
            memLoadReturnBlockCycles,
            memLoadAccessBlockCycles,
            storeCommitBlockedByLoadCycles,
            recoveryCycles,
            dispatchWidth0Cycles,
            dispatchWidth1Cycles,
            dispatchWidth2Cycles,
            issueWidth0Cycles,
            issueWidth1Cycles,
            issueWidth2Cycles,
            commitWidth0Cycles,
            commitWidth1Cycles,
            commitWidth2Cycles
    );
endinterface : PerfIF
