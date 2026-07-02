import BasicTypes::*;

module BPU(
    PreFetchStageIF.BPU pf,
    FetchStageIF.FetchStage fetch,
    CtrlIF.PreFetchStage ctrl,
    RecoveryManagerIF.BPU recovery
);
    localparam int BTB_ENTRY_NUM = 32;
    localparam int BHB_PHT_ENTRY_NUM = 64;
    localparam int BHB_LOCAL_ENTRY_NUM = 64;

    PcPath lookupPc [WAY_NUM];
    logic  btbHit   [WAY_NUM];
    PcPath btbTarget[WAY_NUM];
    logic  bhbTaken [WAY_NUM];

    logic  updateValid;
    PcPath updatePc;
    PcPath updateTarget;
    logic  updateTaken;

    assign updateValid = recovery.branchUpdateValid;
    assign updatePc = recovery.branchPc;
    assign updateTarget = recovery.branchTarget;
    assign updateTaken = recovery.branchTaken;

    BTB #(
        .ENTRY_NUM(BTB_ENTRY_NUM),
        .TAG_WIDTH(10)
    ) btb (
        .clk(fetch.clk),
        .rst(fetch.rst),
        .lookupPc(lookupPc),
        .hit(btbHit),
        .target(btbTarget),
        .updateValid(updateValid),
        .updatePc(updatePc),
        .updateTarget(updateTarget)
    );

    BHB #(
        .PHT_ENTRY_NUM(BHB_PHT_ENTRY_NUM),
        .LOCAL_ENTRY_NUM(BHB_LOCAL_ENTRY_NUM),
        .LOCAL_HISTORY_WIDTH(4),
        .GLOBAL_HISTORY_WIDTH(6)
    ) bhb (
        .clk(fetch.clk),
        .rst(fetch.rst),
        .lookupPc(lookupPc),
        .lookupBtbHit(btbHit),
        .taken(bhbTaken),
        .updateValid(updateValid),
        .updatePc(updatePc),
        .updateTaken(updateTaken)
    );

    always_comb begin
        logic takenFound;
        logic predictEnable;

        takenFound = 1'b0;
        predictEnable = !ctrl.pfPipe.flush;
        for (int i = 0; i < WAY_NUM; i++) begin
            lookupPc[i] = pf.pcOut + PcPath'(i * 4);

            pf.bpuResult[i].btbhit = predictEnable && btbHit[i];
            pf.bpuResult[i].taken = predictEnable && btbHit[i] && bhbTaken[i] && !takenFound;
            pf.bpuResult[i].target = pf.bpuResult[i].taken ? btbTarget[i] : (pf.pcOut + PC_STEP);

            if (pf.bpuResult[i].taken) begin
                takenFound = 1'b1;
            end
        end
    end
endmodule
