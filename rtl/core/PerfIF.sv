interface PerfIF(input logic clk, rst);
    logic [63:0] cycle;
    logic [63:0] commitCnt;
    logic [63:0] branchCnt;
    logic [63:0] branchMissCnt;

    modport core(
        output
            cycle,
            commitCnt,
            branchCnt,
            branchMissCnt
    );
endinterface : PerfIF
