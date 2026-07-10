import CoreConfigPkg::*;
import CoreTypesPkg::*;

module core(
    input logic clk,
    input logic rst,

    IromAccessIF.core iromAccess,
    DramAccessIF      dromAccess,
    DebugIF.core      debug,
    PerfIF.core       perf
`ifdef VERILATOR_TB
    ,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_valid,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_pc,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_inst,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_wen,
    output logic [RETIRE_WIDTH-1:0][4:0]  dbg_commit_rd,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_wdata,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_load,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_store,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_mmio,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_trap,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_cause,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_next_pc
`endif
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

`ifdef VERILATOR_TB
    logic [RETIRE_WIDTH-1:0] trace_valid;
    PcPath [RETIRE_WIDTH-1:0] trace_next_pc;
`endif

    logic [2:0] commit_inc;
    logic [2:0] branch_inc;
    logic [2:0] branch_miss_inc;
    logic [2:0] cond_branch_inc;
    logic [2:0] cond_branch_miss_inc;
    logic [2:0] jal_inc;
    logic [2:0] jal_miss_inc;
    logic [2:0] jalr_inc;
    logic [2:0] jalr_miss_inc;
    logic [2:0] issue_inc;
    logic bpu_pred_valid;
    logic bpu_pred_taken;
    PcPath bpu_pred_target;
    logic bpu_update_valid;
    PcPath bpu_update_pc;
    logic bpu_update_taken;
    PcPath bpu_update_target;
    logic bpu_update_is_call;
    logic bpu_update_is_return;
    PcPath bpu_update_return_pc;

    function automatic logic is_link_reg(input logic [4:0] reg_idx);
        begin
            is_link_reg = (reg_idx == 5'd1) || (reg_idx == 5'd5);
        end
    endfunction

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
        .pred_valid_i    (bpu_pred_valid),
        .pred_pc_i       (bpu_pred_target),
        .pc_o            (fetch_pc)
    );

    CoreBranchPredictor u_bpu (
        .clk            (clk),
        .rst            (rst),
        .pc_i           (fetch_pc),
        .pred_valid_o   (bpu_pred_valid),
        .pred_taken_o   (bpu_pred_taken),
        .pred_target_o  (bpu_pred_target),
        .update_valid_i (bpu_update_valid),
        .update_pc_i    (bpu_update_pc),
        .update_taken_i (bpu_update_taken),
        .update_target_i(bpu_update_target),
        .update_is_call_i(bpu_update_is_call),
        .update_is_return_i(bpu_update_is_return),
        .update_return_pc_i(bpu_update_return_pc)
    );

    CoreIromFetch2 u_fetch (
        .clk          (clk),
        .rst          (rst),
        .clear_i      (backend_recover_valid),
        .resp_ready_i (&fetch_push_ready),
        .req_valid_i  (fetch_req_valid),
        .req_pc_i     (fetch_pc),
        .req_pred_taken_i (bpu_pred_taken),
        .req_pred_target_i(bpu_pred_target),
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

`ifdef VERILATOR_TB
    always_comb begin
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            // Exception retirement has no commit_valid pulse, but is still an
            // architectural event and must be visible to the trace consumer.
            trace_valid[i] = commit_valid[i] || (commit_entry[i].valid &&
                                                 commit_entry[i].exception);
            trace_next_pc[i] = commit_entry[i].uop.pc + 32'd4;
            if (commit_entry[i].exception || commit_entry[i].uop.is_mret) begin
                trace_next_pc[i] = backend_recover_pc;
            end else if (commit_entry[i].uop.is_branch ||
                         commit_entry[i].uop.is_jal ||
                         commit_entry[i].uop.is_jalr) begin
                trace_next_pc[i] = commit_entry[i].redirect_pc;
            end
        end
    end
`endif

    always_comb begin
        commit_inc = '0;
        branch_inc = '0;
        branch_miss_inc = '0;
        cond_branch_inc = '0;
        cond_branch_miss_inc = '0;
        jal_inc = '0;
        jal_miss_inc = '0;
        jalr_inc = '0;
        jalr_miss_inc = '0;
        issue_inc = '0;
        bpu_update_valid = 1'b0;
        bpu_update_pc = '0;
        bpu_update_taken = 1'b0;
        bpu_update_target = '0;
        bpu_update_is_call = 1'b0;
        bpu_update_is_return = 1'b0;
        bpu_update_return_pc = '0;
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            if (commit_valid[i]) begin
                commit_inc = commit_inc + 3'd1;
                if (commit_entry[i].uop.is_branch ||
                    commit_entry[i].uop.is_jal ||
                    commit_entry[i].uop.is_jalr) begin
                    branch_inc = branch_inc + 3'd1;
                    if (commit_entry[i].uop.is_jalr) begin
                        jalr_inc = jalr_inc + 3'd1;
                    end else if (commit_entry[i].uop.is_jal) begin
                        jal_inc = jal_inc + 3'd1;
                    end else begin
                        cond_branch_inc = cond_branch_inc + 3'd1;
                    end
                    if (!bpu_update_valid) begin
                        bpu_update_valid = 1'b1;
                        bpu_update_pc = commit_entry[i].uop.pc;
                        bpu_update_taken = commit_entry[i].branch_miss ?
                                           (commit_entry[i].redirect_pc != (commit_entry[i].uop.pc + 32'd4)) :
                                           commit_entry[i].uop.pred_taken;
                        bpu_update_target = commit_entry[i].branch_miss ?
                                            commit_entry[i].redirect_pc :
                                            commit_entry[i].uop.pred_target;
                        bpu_update_is_call = (commit_entry[i].uop.is_jal ||
                                              commit_entry[i].uop.is_jalr) &&
                                             is_link_reg(commit_entry[i].uop.rd);
                        bpu_update_is_return = commit_entry[i].uop.is_jalr &&
                                               is_link_reg(commit_entry[i].uop.rs1) &&
                                               !is_link_reg(commit_entry[i].uop.rd);
                        bpu_update_return_pc = commit_entry[i].uop.pc + 32'd4;
                    end
                    if (commit_entry[i].branch_miss) begin
                        branch_miss_inc = branch_miss_inc + 3'd1;
                        if (commit_entry[i].uop.is_jalr) begin
                            jalr_miss_inc = jalr_miss_inc + 3'd1;
                        end else if (commit_entry[i].uop.is_jal) begin
                            jal_miss_inc = jal_miss_inc + 3'd1;
                        end else begin
                            cond_branch_miss_inc = cond_branch_miss_inc + 3'd1;
                        end
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
`ifdef VERILATOR_TB
            dbg_commit_valid <= '0;
            dbg_commit_pc <= '0;
            dbg_commit_inst <= '0;
            dbg_commit_wen <= '0;
            dbg_commit_rd <= '0;
            dbg_commit_wdata <= '0;
            dbg_commit_is_load <= '0;
            dbg_commit_is_store <= '0;
            dbg_commit_is_mmio <= '0;
            dbg_commit_is_trap <= '0;
            dbg_commit_cause <= '0;
            dbg_commit_next_pc <= '0;
`endif
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
`ifdef VERILATOR_TB
            for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
                dbg_commit_valid[i] <= trace_valid[i];
                dbg_commit_pc[i] <= commit_entry[i].uop.pc;
                dbg_commit_inst[i] <= commit_entry[i].uop.inst;
                dbg_commit_wen[i] <= commit_valid[i] && commit_entry[i].alloc_prd &&
                                     (commit_entry[i].uop.rd != '0);
                dbg_commit_rd[i] <= commit_entry[i].uop.rd;
                dbg_commit_wdata[i] <= commit_entry[i].result;
                dbg_commit_is_load[i] <= commit_entry[i].uop.is_load;
                dbg_commit_is_store[i] <= commit_entry[i].uop.is_store;
                dbg_commit_is_mmio[i] <= (commit_entry[i].uop.is_load ||
                                          commit_entry[i].uop.is_store) &&
                                         (commit_entry[i].result[31:12] == 20'h80200);
                dbg_commit_is_trap[i] <= commit_entry[i].exception;
                dbg_commit_cause[i] <= commit_entry[i].exception_cause;
                dbg_commit_next_pc[i] <= trace_next_pc[i];
            end
`endif
            perf.cycle <= perf.cycle + 64'd1;
            perf.commitCnt <= perf.commitCnt + 64'(commit_inc);
            perf.branchCnt <= perf.branchCnt + 64'(branch_inc);
            perf.branchMissCnt <= perf.branchMissCnt + 64'(branch_miss_inc);
            perf.condBranchCnt <= perf.condBranchCnt + 64'(cond_branch_inc);
            perf.condBranchMissCnt <= perf.condBranchMissCnt + 64'(cond_branch_miss_inc);
            perf.jalCnt <= perf.jalCnt + 64'(jal_inc);
            perf.jalMissCnt <= perf.jalMissCnt + 64'(jal_miss_inc);
            perf.jalrCnt <= perf.jalrCnt + 64'(jalr_inc);
            perf.jalrMissCnt <= perf.jalrMissCnt + 64'(jalr_miss_inc);
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
