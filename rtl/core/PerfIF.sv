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
            jalrMissCnt
    );
endinterface : PerfIF
