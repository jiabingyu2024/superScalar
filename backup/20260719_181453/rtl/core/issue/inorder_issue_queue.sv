`timescale 1ns / 1ps

module inorder_issue_queue #(
    parameter int unsigned DEPTH = 4,
    parameter int unsigned CNT_W = $clog2(DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic enqueue_i,
    input  core_types_pkg::uop_t enqueue_uop_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] enqueue_trans_id_i,
    input  logic enqueue_src1_ready_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] enqueue_src1_trans_id_i,
    input  logic [31:0] enqueue_src1_value_i,
    input  logic enqueue_src2_ready_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] enqueue_src2_trans_id_i,
    input  logic [31:0] enqueue_src2_value_i,

    input  logic fixed_complete_i,
    input  core_types_pkg::completion_t fixed_completion_i,
    input  logic fixed_mem_addr_defer_i,
    input  logic load_complete_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] load_trans_id_i,
    input  logic [31:0] load_result_i,
    input  logic slow_complete_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] slow_trans_id_i,
    input  logic [31:0] slow_result_i,

    input  logic load_ready_i,
    input  logic store_ready_i,
    input  logic muldiv_ready_i,
    input  logic bitmanip_ready_i,
    input  logic issue_block_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] commit_trans_id_i,

    output logic issue_valid_o,
    output core_types_pkg::uop_t issue_uop_o,
    output logic [core_config_pkg::TRANS_ID_W-1:0] issue_trans_id_o,
    output logic [31:0] issue_src1_o,
    output logic [31:0] issue_src2_o,
    output logic issue_src1_load_bypass_o,
    output logic issue_src2_load_bypass_o,
    output logic memory_addr_valid_o,
    output logic [31:0] memory_addr_o,
    output logic [CNT_W-1:0] count_o
);
    import core_types_pkg::*;

    localparam int unsigned INDEX_W = $clog2(DEPTH);

    typedef struct packed {
        logic valid;
        uop_t uop;
        logic [core_config_pkg::TRANS_ID_W-1:0] trans_id;
        logic src1_ready;
        logic [core_config_pkg::TRANS_ID_W-1:0] src1_trans_id;
        logic [31:0] src1_value;
        logic src2_ready;
        logic [core_config_pkg::TRANS_ID_W-1:0] src2_trans_id;
        logic [31:0] src2_value;
        logic mem_addr_ready;
    } entry_t;

    entry_t entries_q [0:DEPTH-1];
    entry_t entries_d [0:DEPTH-1];
    entry_t enqueue_entry_c;
    logic [INDEX_W-1:0] selected_index_c;
    logic [INDEX_W-1:0] enqueue_index_c;
    logic selected_c, enqueue_slot_found_c, fu_ready_c;
    logic older_memory_c, memory_addr_selected_c;
    logic [core_config_pkg::TRANS_ID_W-1:0] selected_age_c;
    logic [core_config_pkg::TRANS_ID_W-1:0] memory_addr_age_c;
    logic [core_config_pkg::TRANS_ID_W-1:0] entry_age_c;
    logic load_addr_wakeup_valid_q;
    logic [core_config_pkg::TRANS_ID_W-1:0] load_addr_wakeup_trans_id_q;
    logic [31:0] load_addr_wakeup_result_q;
    logic fixed_mem_addr_wakeup_valid_q;
    logic [core_config_pkg::TRANS_ID_W-1:0] fixed_mem_addr_wakeup_trans_id_q;
    logic select_src1_ready_c [0:DEPTH-1];
    logic select_src2_ready_c [0:DEPTH-1];
    logic select_src1_load_bypass_c [0:DEPTH-1];
    logic select_src2_load_bypass_c [0:DEPTH-1];
    integer comb_i;
    integer comb_j;
    integer seq_i;

    always_comb begin
        enqueue_entry_c = '0;
        enqueue_entry_c.valid = enqueue_i;
        enqueue_entry_c.uop = enqueue_uop_i;
        enqueue_entry_c.trans_id = enqueue_trans_id_i;
        enqueue_entry_c.src1_ready = enqueue_src1_ready_i;
        enqueue_entry_c.src1_trans_id = enqueue_src1_trans_id_i;
        enqueue_entry_c.src1_value = enqueue_src1_value_i;
        enqueue_entry_c.src2_ready = enqueue_src2_ready_i;
        enqueue_entry_c.src2_trans_id = enqueue_src2_trans_id_i;
        enqueue_entry_c.src2_value = enqueue_src2_value_i;
        enqueue_entry_c.mem_addr_ready = enqueue_i &&
            (enqueue_uop_i.fu == FU_LOAD || enqueue_uop_i.fu == FU_STORE) &&
            enqueue_src1_ready_i;

        for (comb_i = 0; comb_i < DEPTH; comb_i = comb_i + 1) begin
            entries_d[comb_i] = entries_q[comb_i];
            if (entries_d[comb_i].valid && !entries_d[comb_i].src1_ready) begin
                if (fixed_complete_i &&
                    entries_d[comb_i].src1_trans_id == fixed_completion_i.trans_id) begin
                    entries_d[comb_i].src1_ready = 1'b1;
                    entries_d[comb_i].src1_value = fixed_completion_i.result;
                    if ((entries_d[comb_i].uop.fu == FU_LOAD ||
                         entries_d[comb_i].uop.fu == FU_STORE) &&
                        !fixed_mem_addr_defer_i)
                        entries_d[comb_i].mem_addr_ready = 1'b1;
                end else if (load_addr_wakeup_valid_q &&
                             entries_d[comb_i].src1_trans_id ==
                             load_addr_wakeup_trans_id_q) begin
                    entries_d[comb_i].src1_ready = 1'b1;
                    entries_d[comb_i].src1_value = load_addr_wakeup_result_q;
                    if (entries_d[comb_i].uop.fu == FU_LOAD ||
                        entries_d[comb_i].uop.fu == FU_STORE)
                        entries_d[comb_i].mem_addr_ready = 1'b1;
                end else if (slow_complete_i &&
                             entries_d[comb_i].src1_trans_id == slow_trans_id_i) begin
                    entries_d[comb_i].src1_ready = 1'b1;
                    entries_d[comb_i].src1_value = slow_result_i;
                    if (entries_d[comb_i].uop.fu == FU_LOAD ||
                        entries_d[comb_i].uop.fu == FU_STORE)
                        entries_d[comb_i].mem_addr_ready = 1'b1;
                end
            end
            // A fixed result produced from the load-return bypass would make
            // load data cross the ALU, completion wakeup and AGU in one cycle.
            // The operand value may wake immediately, but make a dependent
            // memory operation wait one cycle before its address can issue.
            if (entries_d[comb_i].valid &&
                (entries_d[comb_i].uop.fu == FU_LOAD ||
                 entries_d[comb_i].uop.fu == FU_STORE) &&
                !entries_d[comb_i].mem_addr_ready &&
                fixed_mem_addr_wakeup_valid_q &&
                entries_d[comb_i].src1_trans_id ==
                fixed_mem_addr_wakeup_trans_id_q)
                entries_d[comb_i].mem_addr_ready = 1'b1;
            if (entries_d[comb_i].valid && !entries_d[comb_i].src2_ready) begin
                if (fixed_complete_i &&
                    entries_d[comb_i].src2_trans_id == fixed_completion_i.trans_id) begin
                    entries_d[comb_i].src2_ready = 1'b1;
                    entries_d[comb_i].src2_value = fixed_completion_i.result;
                end else if (load_addr_wakeup_valid_q &&
                             entries_d[comb_i].src2_trans_id ==
                             load_addr_wakeup_trans_id_q) begin
                    entries_d[comb_i].src2_ready = 1'b1;
                    entries_d[comb_i].src2_value = load_addr_wakeup_result_q;
                end else if (slow_complete_i &&
                             entries_d[comb_i].src2_trans_id == slow_trans_id_i) begin
                    entries_d[comb_i].src2_ready = 1'b1;
                    entries_d[comb_i].src2_value = slow_result_i;
                end
            end
            select_src1_load_bypass_c[comb_i] = entries_d[comb_i].valid &&
                !entries_d[comb_i].src1_ready && load_complete_i &&
                entries_d[comb_i].uop.fu != FU_LOAD &&
                entries_d[comb_i].uop.fu != FU_STORE &&
                entries_d[comb_i].src1_trans_id == load_trans_id_i;
            select_src2_load_bypass_c[comb_i] = entries_d[comb_i].valid &&
                !entries_d[comb_i].src2_ready && load_complete_i &&
                entries_d[comb_i].src2_trans_id == load_trans_id_i;
            select_src1_ready_c[comb_i] = entries_d[comb_i].src1_ready ||
                                                select_src1_load_bypass_c[comb_i];
            select_src2_ready_c[comb_i] = entries_d[comb_i].src2_ready ||
                                                select_src2_load_bypass_c[comb_i];
        end

        issue_valid_o = 1'b0;
        issue_uop_o = '0;
        issue_trans_id_o = '0;
        issue_src1_o = '0;
        issue_src2_o = '0;
        issue_src1_load_bypass_o = 1'b0;
        issue_src2_load_bypass_o = 1'b0;
        memory_addr_valid_o = 1'b0;
        memory_addr_o = '0;
        selected_index_c = '0;
        enqueue_index_c = '0;
        selected_c = 1'b0;
        enqueue_slot_found_c = 1'b0;
        selected_age_c = '1;
        memory_addr_selected_c = 1'b0;
        memory_addr_age_c = '1;

        // Enqueue only uses a slot that was already free at the start of the
        // cycle.  It therefore never depends on the current issue decision.
        for (comb_i = 0; comb_i < DEPTH; comb_i = comb_i + 1) begin
            if (!enqueue_slot_found_c && !entries_q[comb_i].valid) begin
                enqueue_slot_found_c = 1'b1;
                enqueue_index_c = INDEX_W'(comb_i);
            end
        end

        for (comb_i = 0; comb_i < DEPTH; comb_i = comb_i + 1) begin
            entry_age_c = entries_d[comb_i].trans_id - commit_trans_id_i;
            older_memory_c = 1'b0;
            for (comb_j = 0; comb_j < DEPTH; comb_j = comb_j + 1) begin
                if (entries_d[comb_j].valid &&
                    (entries_d[comb_j].uop.fu == FU_LOAD ||
                     entries_d[comb_j].uop.fu == FU_STORE) &&
                    ((entries_d[comb_j].trans_id - commit_trans_id_i) < entry_age_c))
                    older_memory_c = 1'b1;
            end

            fu_ready_c = 1'b1;
            unique case (entries_d[comb_i].uop.fu)
                FU_LOAD: fu_ready_c = load_ready_i && !older_memory_c &&
                                           entries_d[comb_i].mem_addr_ready;
                FU_STORE: fu_ready_c = store_ready_i && !older_memory_c &&
                                            entries_d[comb_i].mem_addr_ready;
                FU_MULDIV: fu_ready_c = muldiv_ready_i;
                FU_BITMANIP: fu_ready_c = bitmanip_ready_i;
                // Branches may execute before reaching the commit head.  Their
                // outcome is held by core_top and only becomes architectural
                // (predictor update/redirect/full flush) at in-order commit.
                FU_BRANCH: fu_ready_c = 1'b1;
                default: fu_ready_c = 1'b1;
            endcase

            if (entries_d[comb_i].valid && !older_memory_c &&
                (entries_d[comb_i].uop.fu == FU_LOAD ||
                 entries_d[comb_i].uop.fu == FU_STORE) &&
                entries_d[comb_i].mem_addr_ready &&
                (!memory_addr_selected_c || entry_age_c < memory_addr_age_c)) begin
                memory_addr_selected_c = 1'b1;
                memory_addr_age_c = entry_age_c;
                memory_addr_valid_o = 1'b1;
                memory_addr_o = entries_d[comb_i].src1_value +
                                entries_d[comb_i].uop.imm;
            end

            if (!issue_block_i && entries_d[comb_i].valid &&
                select_src1_ready_c[comb_i] && select_src2_ready_c[comb_i] &&
                fu_ready_c && (!selected_c || entry_age_c < selected_age_c)) begin
                selected_c = 1'b1;
                selected_age_c = entry_age_c;
                selected_index_c = INDEX_W'(comb_i);
                issue_valid_o = 1'b1;
                issue_uop_o = entries_d[comb_i].uop;
                issue_trans_id_o = entries_d[comb_i].trans_id;
                issue_src1_o = entries_d[comb_i].src1_value;
                issue_src2_o = entries_d[comb_i].src2_value;
                issue_src1_load_bypass_o = select_src1_load_bypass_c[comb_i];
                issue_src2_load_bypass_o = select_src2_load_bypass_c[comb_i];
            end
        end

        if (issue_valid_o)
            entries_d[selected_index_c].valid = 1'b0;
        if (enqueue_i)
            entries_d[enqueue_index_c] = enqueue_entry_c;
    end

    always_ff @(posedge clk) begin
        if (rst || flush_i) begin
            count_o <= '0;
            load_addr_wakeup_valid_q <= 1'b0;
            load_addr_wakeup_trans_id_q <= '0;
            load_addr_wakeup_result_q <= '0;
            fixed_mem_addr_wakeup_valid_q <= 1'b0;
            fixed_mem_addr_wakeup_trans_id_q <= '0;
            for (seq_i = 0; seq_i < DEPTH; seq_i = seq_i + 1)
                entries_q[seq_i] <= '0;
        end else begin
            load_addr_wakeup_valid_q <= load_complete_i;
            fixed_mem_addr_wakeup_valid_q <= fixed_complete_i &&
                                             fixed_mem_addr_defer_i;
            if (fixed_complete_i && fixed_mem_addr_defer_i)
                fixed_mem_addr_wakeup_trans_id_q <= fixed_completion_i.trans_id;
            if (load_complete_i) begin
                load_addr_wakeup_trans_id_q <= load_trans_id_i;
                load_addr_wakeup_result_q <= load_result_i;
            end
            for (seq_i = 0; seq_i < DEPTH; seq_i = seq_i + 1)
                entries_q[seq_i] <= entries_d[seq_i];
            unique case ({enqueue_i, issue_valid_o})
                2'b10: count_o <= count_o + 1'b1;
                2'b01: count_o <= count_o - 1'b1;
                default: begin end
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst && !flush_i) begin
            assert (count_o <= CNT_W'(DEPTH));
            if (enqueue_i) begin
                assert (count_o < CNT_W'(DEPTH));
                assert (enqueue_slot_found_c);
            end
            if (issue_valid_o) assert (count_o != 0);
        end
    end
`endif
endmodule
