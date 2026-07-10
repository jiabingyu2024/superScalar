import CoreConfigPkg::*;
import CoreTypesPkg::*;

module core(
    input logic clk,
    input logic rst,

    IromAccessIF.core iromAccess,
    DramAccessIF      dromAccess,
    DebugIF.core      debug,
    PerfIF.core       perf
);
    PcPath fetch_pc;
    logic pc_hold;
    logic fetch_req_valid;
    logic fetch_req_ready;
    logic [FETCH_WIDTH-1:0] fetch_valid;
    CoreFetchPacket [FETCH_WIDTH-1:0] fetch_pkt;
    logic [FETCH_WIDTH-1:0] fetch_push_ready;

    logic [DECODE_WIDTH-1:0] fetch_pop_valid;
    CoreFetchPacket [DECODE_WIDTH-1:0] fetch_pop_pkt;
    logic [DECODE_WIDTH-1:0] fetch_pop_ready;
    logic [DECODE_WIDTH-1:0] decode_valid;
    CoreDecodeUop [DECODE_WIDTH-1:0] decode_uop;
    logic [DECODE_WIDTH-1:0] decode_ready;

    logic backend_recover_valid;
    PcPath backend_recover_pc;
    logic [RETIRE_WIDTH-1:0] commit_valid;
    CoreRobEntry [RETIRE_WIDTH-1:0] commit_entry;

    logic [2:0] commit_inc;
    logic [2:0] branch_inc;
    logic [2:0] branch_miss_inc;
    logic [2:0] issue_inc;

    assign fetch_req_valid = (&fetch_push_ready) && !debug.halt && !backend_recover_valid;
    assign pc_hold = !(fetch_req_valid && fetch_req_ready);
    assign fetch_pop_ready = decode_ready;
    assign decode_valid = fetch_pop_valid;

    CorePcGen u_pc_gen (
        .clk             (clk),
        .rst             (rst),
        .hold_i          (pc_hold),
        .recovery_valid_i(backend_recover_valid),
        .recovery_pc_i   (backend_recover_pc),
        .pred_valid_i    (1'b0),
        .pred_pc_i       ('0),
        .pc_o            (fetch_pc)
    );

    CoreIromFetch2 u_fetch (
        .clk          (clk),
        .rst          (rst),
        .clear_i      (backend_recover_valid),
        .resp_ready_i (&fetch_push_ready),
        .req_valid_i  (fetch_req_valid),
        .req_pc_i     (fetch_pc),
        .req_ready_o  (fetch_req_ready),
        .irom         (iromAccess),
        .fetch_valid_o(fetch_valid),
        .fetch_pkt_o  (fetch_pkt)
    );

    CoreFetchBuffer u_fetch_buffer (
        .clk         (clk),
        .rst         (rst),
        .clear_i     (backend_recover_valid),
        .push_valid_i(fetch_valid),
        .push_pkt_i  (fetch_pkt),
        .push_ready_o(fetch_push_ready),
        .pop_ready_i (fetch_pop_ready),
        .pop_valid_o (fetch_pop_valid),
        .pop_pkt_o   (fetch_pop_pkt)
    );

    for (genvar i = 0; i < DECODE_WIDTH; i = i + 1) begin : gen_decoder
        CoreRv32Decoder u_decoder (
            .fetch_i(fetch_pop_pkt[i]),
            .uop_o  (decode_uop[i])
        );
    end

    CoreBackend u_backend (
        .clk            (clk),
        .rst            (rst),
        .clear_i        (1'b0),
        .recover_i      (backend_recover_valid),
        .decode_valid_i (decode_valid),
        .decode_uop_i   (decode_uop),
        .decode_ready_o (decode_ready),
        .recover_valid_o(backend_recover_valid),
        .recover_pc_o   (backend_recover_pc),
        .commit_valid_o (commit_valid),
        .commit_entry_o (commit_entry),
        .dmem           (dromAccess)
    );

    always_comb begin
        commit_inc = '0;
        branch_inc = '0;
        branch_miss_inc = '0;
        issue_inc = '0;
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            if (commit_valid[i]) begin
                commit_inc = commit_inc + 3'd1;
                if (commit_entry[i].uop.is_branch ||
                    commit_entry[i].uop.is_jal ||
                    commit_entry[i].uop.is_jalr) begin
                    branch_inc = branch_inc + 3'd1;
                    if (commit_entry[i].branch_miss) begin
                        branch_miss_inc = branch_miss_inc + 3'd1;
                    end
                end
            end
        end
        for (int j = 0; j < DECODE_WIDTH; j = j + 1) begin
            if (decode_valid[j] && decode_ready[j]) begin
                issue_inc = issue_inc + 3'd1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            perf.cycle <= 64'b0;
            perf.commitCnt <= 64'b0;
            perf.branchCnt <= 64'b0;
            perf.branchMissCnt <= 64'b0;
            perf.condBranchCnt <= 64'b0;
            perf.condBranchMissCnt <= 64'b0;
            perf.jalCnt <= 64'b0;
            perf.jalMissCnt <= 64'b0;
            perf.jalrCnt <= 64'b0;
            perf.jalrMissCnt <= 64'b0;
            perf.frontendStallCycles <= 64'b0;
            perf.idStallCycles <= 64'b0;
            perf.rnStallCycles <= 64'b0;
            perf.dsStallCycles <= 64'b0;
            perf.isStallCycles <= 64'b0;
            perf.rrStallCycles <= 64'b0;
            perf.exStallCycles <= 64'b0;
            perf.wbStallCycles <= 64'b0;
            perf.robFullCycles <= 64'b0;
            perf.issueQueueFullCycles <= 64'b0;
            perf.intIssueQueueFullCycles <= 64'b0;
            perf.memIssueQueueFullCycles <= 64'b0;
            perf.mulIssueQueueFullCycles <= 64'b0;
            perf.robHeadNotDoneCycles <= 64'b0;
            perf.robHeadNotDoneIntCycles <= 64'b0;
            perf.robHeadNotDoneMemCycles <= 64'b0;
            perf.robHeadNotDoneMulCycles <= 64'b0;
            perf.robHeadNotDoneOtherCycles <= 64'b0;
            perf.robHeadStoreCommitWaitCycles <= 64'b0;
            perf.freeListEmptyCycles <= 64'b0;
            perf.storeBufferFullCycles <= 64'b0;
            perf.serialBlockCycles <= 64'b0;
            perf.memLoadReturnBlockCycles <= 64'b0;
            perf.memLoadAccessBlockCycles <= 64'b0;
            perf.storeCommitBlockedByLoadCycles <= 64'b0;
            perf.recoveryCycles <= 64'b0;
            perf.dispatchWidth0Cycles <= 64'b0;
            perf.dispatchWidth1Cycles <= 64'b0;
            perf.dispatchWidth2Cycles <= 64'b0;
            perf.issueWidth0Cycles <= 64'b0;
            perf.issueWidth1Cycles <= 64'b0;
            perf.issueWidth2Cycles <= 64'b0;
            perf.commitWidth0Cycles <= 64'b0;
            perf.commitWidth1Cycles <= 64'b0;
            perf.commitWidth2Cycles <= 64'b0;
            perf.intIssueCount <= 64'b0;
            perf.memIssueCount <= 64'b0;
            perf.mulIssueCount <= 64'b0;
        end else begin
            perf.cycle <= perf.cycle + 64'd1;
            perf.commitCnt <= perf.commitCnt + 64'(commit_inc);
            perf.branchCnt <= perf.branchCnt + 64'(branch_inc);
            perf.branchMissCnt <= perf.branchMissCnt + 64'(branch_miss_inc);
            perf.condBranchCnt <= perf.condBranchCnt + 64'(branch_inc);
            perf.condBranchMissCnt <= perf.condBranchMissCnt + 64'(branch_miss_inc);
            perf.recoveryCycles <= perf.recoveryCycles + (backend_recover_valid ? 64'd1 : 64'd0);
            perf.issueWidth0Cycles <= perf.issueWidth0Cycles + ((issue_inc == 3'd0) ? 64'd1 : 64'd0);
            perf.issueWidth1Cycles <= perf.issueWidth1Cycles + ((issue_inc == 3'd1) ? 64'd1 : 64'd0);
            perf.issueWidth2Cycles <= perf.issueWidth2Cycles + ((issue_inc >= 3'd2) ? 64'd1 : 64'd0);
            perf.commitWidth0Cycles <= perf.commitWidth0Cycles + ((commit_inc == 3'd0) ? 64'd1 : 64'd0);
            perf.commitWidth1Cycles <= perf.commitWidth1Cycles + ((commit_inc == 3'd1) ? 64'd1 : 64'd0);
            perf.commitWidth2Cycles <= perf.commitWidth2Cycles + ((commit_inc >= 3'd2) ? 64'd1 : 64'd0);
            if (pc_hold) begin
                perf.frontendStallCycles <= perf.frontendStallCycles + 64'd1;
            end
        end
    end
endmodule
