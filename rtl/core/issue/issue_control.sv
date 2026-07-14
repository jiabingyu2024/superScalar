`timescale 1ns / 1ps

module issue_control #(
    parameter int unsigned SB_CNT_W = $clog2(core_config_pkg::SCOREBOARD_DEPTH + 1),
    parameter int unsigned ST_CNT_W = $clog2(core_config_pkg::STORE_BUFFER_DEPTH + 1),
    parameter int unsigned LD_CNT_W = $clog2(core_config_pkg::LOAD_QUEUE_DEPTH + 1)
) (
    input  logic id_valid_i,
    input  core_types_pkg::uop_t uop_i,
    input  logic src1_ready_i,
    input  logic src1_memory_ready_i,
    input  logic src2_ready_i,
    input  logic [SB_CNT_W-1:0] scoreboard_count_i,
    input  logic [ST_CNT_W-1:0] store_count_i,
    input  logic [LD_CNT_W-1:0] load_count_i,
    input  core_types_pkg::exec_req_t exec_i,
    input  logic serial_pending_i,
    input  logic mdu_req_ready_i,
    input  logic mdu_busy_i,
    input  logic bitmanip_req_ready_i,
    input  logic bitmanip_busy_i,
    input  logic bitmanip_clmul_start_i,
    input  logic commit_i,
    input  logic branch_resolve_i,
    input  logic redirect_i,
    output logic issue_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    logic fu_ready;

    always_comb begin
        fu_ready = 1'b1;
        unique case (uop_i.fu)
            FU_LOAD: fu_ready =
                (load_count_i + LD_CNT_W'(exec_i.valid && exec_i.uop.fu == FU_LOAD)) <
                LD_CNT_W'(LOAD_QUEUE_DEPTH);
            FU_STORE: fu_ready =
                (store_count_i + ST_CNT_W'(exec_i.valid && exec_i.uop.fu == FU_STORE)) <
                ST_CNT_W'(STORE_BUFFER_DEPTH);
            FU_MULDIV: fu_ready = mdu_req_ready_i && !bitmanip_busy_i &&
                                      !(exec_i.valid && exec_i.uop.fu == FU_MULDIV) &&
                                      !bitmanip_clmul_start_i;
            FU_BITMANIP: fu_ready = bitmanip_req_ready_i && !mdu_busy_i &&
                                         !(exec_i.valid && exec_i.uop.fu == FU_MULDIV) &&
                                         !bitmanip_clmul_start_i;
            default: fu_ready = 1'b1;
        endcase

        if (uop_i.serialize)
            fu_ready = fu_ready && scoreboard_count_i == 0 && !serial_pending_i;
        else
            fu_ready = fu_ready && !serial_pending_i;

        // A committing done head provides a same-cycle allocation credit.
        issue_o = id_valid_i &&
                  ((uop_i.fu == FU_LOAD || uop_i.fu == FU_STORE) ?
                   src1_memory_ready_i : src1_ready_i) &&
                  src2_ready_i && fu_ready &&
                  (scoreboard_count_i < SB_CNT_W'(SCOREBOARD_DEPTH) || commit_i) &&
                  !branch_resolve_i && !redirect_i;
    end
endmodule
