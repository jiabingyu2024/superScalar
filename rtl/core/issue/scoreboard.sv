`timescale 1ns / 1ps

module scoreboard #(
    parameter int unsigned DEPTH = core_config_pkg::SCOREBOARD_DEPTH,
    parameter int unsigned CNT_W = $clog2(DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic allocate_i,
    input  core_types_pkg::uop_t allocate_uop_i,
    input  logic [31:0] allocate_csr_src_i,
    output logic [core_config_pkg::TRANS_ID_W-1:0] allocate_trans_id_o,

    input  logic fixed_complete_i,
    input  core_types_pkg::completion_t fixed_completion_i,
    input  logic load_complete_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] load_trans_id_i,
    input  logic [31:0] load_result_i,
    output logic load_complete_accepted_o,
    input  logic slow_complete_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] slow_trans_id_i,
    input  logic [31:0] slow_result_i,

    input  logic commit_i,
    output logic [core_config_pkg::TRANS_ID_W-1:0] commit_trans_id_o,
    output core_types_pkg::scoreboard_entry_t commit_entry_o,
    output logic [CNT_W-1:0] count_o,
    output logic serial_pending_o,

    input  core_types_pkg::uop_t query_uop_i,
    output logic query_rs1_found_o,
    output logic query_rs1_ready_o,
    output logic [core_config_pkg::TRANS_ID_W-1:0] query_rs1_trans_id_o,
    output logic [31:0] query_rs1_data_o,
    output logic query_rs2_found_o,
    output logic query_rs2_ready_o,
    output logic [core_config_pkg::TRANS_ID_W-1:0] query_rs2_trans_id_o,
    output logic [31:0] query_rs2_data_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    scoreboard_entry_t entries_q [0:DEPTH-1];
    logic [31:0] producer_valid_q;
    logic [TRANS_ID_W-1:0] producer_tid_q [0:31];
    logic [TRANS_ID_W-1:0] allocate_ptr_q, commit_ptr_q;
    integer i;

    assign allocate_trans_id_o = allocate_ptr_q;
    assign commit_trans_id_o = commit_ptr_q;
    assign commit_entry_o = entries_q[commit_ptr_q];

    always_comb begin
        query_rs1_found_o = query_uop_i.uses_rs1 && query_uop_i.rs1 != 0 &&
                            producer_valid_q[query_uop_i.rs1];
        query_rs1_trans_id_o = query_rs1_found_o ?
                               producer_tid_q[query_uop_i.rs1] : '0;
        query_rs1_ready_o = !query_rs1_found_o ||
                            entries_q[query_rs1_trans_id_o].done;
        query_rs1_data_o = query_rs1_found_o ?
                           entries_q[query_rs1_trans_id_o].result : 32'd0;

        query_rs2_found_o = query_uop_i.uses_rs2 && query_uop_i.rs2 != 0 &&
                            producer_valid_q[query_uop_i.rs2];
        query_rs2_trans_id_o = query_rs2_found_o ?
                               producer_tid_q[query_uop_i.rs2] : '0;
        query_rs2_ready_o = !query_rs2_found_o ||
                            entries_q[query_rs2_trans_id_o].done;
        query_rs2_data_o = query_rs2_found_o ?
                           entries_q[query_rs2_trans_id_o].result : 32'd0;
        load_complete_accepted_o = load_complete_i && entries_q[load_trans_id_i].occupied;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            allocate_ptr_q <= '0;
            commit_ptr_q <= '0;
            count_o <= '0;
            producer_valid_q <= '0;
            serial_pending_o <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1)
                entries_q[i].occupied <= 1'b0;
        end else if (flush_i) begin
            allocate_ptr_q <= '0;
            commit_ptr_q <= '0;
            count_o <= '0;
            producer_valid_q <= '0;
            serial_pending_o <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1)
                entries_q[i].occupied <= 1'b0;
        end else begin
            // Preserve the original same-cycle priority: a new allocation is
            // younger than completion and commit updates to the reused slot.
            if (fixed_complete_i && entries_q[fixed_completion_i.trans_id].occupied) begin
                entries_q[fixed_completion_i.trans_id].done <= 1'b1;
                entries_q[fixed_completion_i.trans_id].result <= fixed_completion_i.result;
                entries_q[fixed_completion_i.trans_id].exception_valid <=
                    fixed_completion_i.exception_valid;
                entries_q[fixed_completion_i.trans_id].exception_cause <=
                    fixed_completion_i.exception_cause;
                entries_q[fixed_completion_i.trans_id].exception_tval <=
                    fixed_completion_i.exception_tval;
                entries_q[fixed_completion_i.trans_id].store_slot_valid <=
                    fixed_completion_i.store_slot_valid;
                entries_q[fixed_completion_i.trans_id].store_slot <=
                    fixed_completion_i.store_slot;
            end
            if (load_complete_accepted_o) begin
                entries_q[load_trans_id_i].done <= 1'b1;
                entries_q[load_trans_id_i].result <= load_result_i;
            end
            if (slow_complete_i && entries_q[slow_trans_id_i].occupied) begin
                entries_q[slow_trans_id_i].done <= 1'b1;
                entries_q[slow_trans_id_i].result <= slow_result_i;
            end

            if (commit_i) begin
                if (commit_entry_o.writes_rd && commit_entry_o.rd != 0 &&
                    producer_valid_q[commit_entry_o.rd] &&
                    producer_tid_q[commit_entry_o.rd] == commit_ptr_q)
                    producer_valid_q[commit_entry_o.rd] <= 1'b0;
                entries_q[commit_ptr_q].occupied <= 1'b0;
                commit_ptr_q <= commit_ptr_q + 1'b1;
                if (commit_entry_o.sys_op != SYS_NONE || commit_entry_o.exception_valid)
                    serial_pending_o <= 1'b0;
            end

            if (allocate_i) begin
                entries_q[allocate_ptr_q].occupied <= 1'b1;
                entries_q[allocate_ptr_q].done <= allocate_uop_i.exception_valid ||
                                                  allocate_uop_i.fu == FU_SYSTEM;
                entries_q[allocate_ptr_q].pc <= allocate_uop_i.pc;
                entries_q[allocate_ptr_q].instr <= allocate_uop_i.instr;
                entries_q[allocate_ptr_q].rd <= allocate_uop_i.rd;
                entries_q[allocate_ptr_q].writes_rd <= allocate_uop_i.writes_rd;
                entries_q[allocate_ptr_q].fu <= allocate_uop_i.fu;
                entries_q[allocate_ptr_q].sys_op <= allocate_uop_i.sys_op;
                entries_q[allocate_ptr_q].csr_op <= allocate_uop_i.csr_op;
                entries_q[allocate_ptr_q].csr_addr <= allocate_uop_i.csr_addr;
                if (allocate_uop_i.sys_op == SYS_CSR)
                    entries_q[allocate_ptr_q].csr_src <= allocate_uop_i.csr_imm ?
                        {27'd0, allocate_uop_i.rs1} : allocate_csr_src_i;
                entries_q[allocate_ptr_q].exception_valid <= allocate_uop_i.exception_valid;
                entries_q[allocate_ptr_q].exception_cause <= allocate_uop_i.exception_cause;
                entries_q[allocate_ptr_q].exception_tval <= allocate_uop_i.exception_tval;
                entries_q[allocate_ptr_q].store_slot_valid <= 1'b0;
                entries_q[allocate_ptr_q].is_call <=
                    (allocate_uop_i.is_jal || allocate_uop_i.is_jalr) &&
                    (allocate_uop_i.rd == 5'd1 || allocate_uop_i.rd == 5'd5);
                entries_q[allocate_ptr_q].is_return <= allocate_uop_i.is_jalr &&
                    (allocate_uop_i.rs1 == 5'd1 || allocate_uop_i.rs1 == 5'd5) &&
                    allocate_uop_i.rd == 0;
                entries_q[allocate_ptr_q].link_addr <= allocate_uop_i.pc + 32'd4;
                if (allocate_uop_i.writes_rd && allocate_uop_i.rd != 0) begin
                    producer_valid_q[allocate_uop_i.rd] <= 1'b1;
                    producer_tid_q[allocate_uop_i.rd] <= allocate_ptr_q;
                end
                allocate_ptr_q <= allocate_ptr_q + 1'b1;
                if (allocate_uop_i.serialize) serial_pending_o <= 1'b1;
            end

            unique case ({allocate_i, commit_i})
                2'b10: count_o <= count_o + 1'b1;
                2'b01: count_o <= count_o - 1'b1;
                default: begin end
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst) begin
            assert (count_o <= CNT_W'(DEPTH));
            if (fixed_complete_i)
                assert (entries_q[fixed_completion_i.trans_id].occupied);
            if (load_complete_i) assert (entries_q[load_trans_id_i].occupied);
            if (slow_complete_i) assert (entries_q[slow_trans_id_i].occupied);
        end
    end
`endif
endmodule
