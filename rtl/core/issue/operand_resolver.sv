`timescale 1ns / 1ps

module operand_resolver (
    input  core_types_pkg::uop_t uop_i,
    input  logic [31:0] rf_rs1_data_i,
    input  logic [31:0] rf_rs2_data_i,
    input  logic wb_valid_i,
    input  logic [4:0] wb_rd_i,
    input  logic [31:0] wb_data_i,

    input  logic rs1_found_i,
    input  logic rs1_scoreboard_ready_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] rs1_trans_id_i,
    input  logic [31:0] rs1_scoreboard_data_i,
    input  logic rs2_found_i,
    input  logic rs2_scoreboard_ready_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] rs2_trans_id_i,
    input  logic [31:0] rs2_scoreboard_data_i,

    input  logic fixed_completion_valid_i,
    input  core_types_pkg::completion_t fixed_completion_i,
    input  logic load_completion_valid_i,
    input  core_types_pkg::load_entry_t load_completion_meta_i,
    input  logic [31:0] load_result_i,
    input  logic slow_completion_valid_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] slow_completion_trans_id_i,
    input  logic [31:0] slow_completion_result_i,

    output logic [31:0] src1_value_o,
    output logic [31:0] src2_value_o,
    output logic [31:0] src1_memory_value_o,
    output logic src1_ready_o,
    output logic src2_ready_o,
    output logic src1_memory_ready_o,
    output logic src1_found_o,
    output logic src2_found_o
);
    always_comb begin
        src1_value_o = rf_rs1_data_i;
        src2_value_o = rf_rs2_data_i;
        if (uop_i.rs1 == 0) src1_value_o = 32'd0;
        if (uop_i.rs2 == 0) src2_value_o = 32'd0;

        // Commit writes the architectural RF one cycle later. This bypass is
        // the exact bridge for that single-cycle visibility gap.
        if (wb_valid_i && uop_i.rs1 == wb_rd_i && uop_i.rs1 != 0)
            src1_value_o = wb_data_i;
        if (wb_valid_i && uop_i.rs2 == wb_rd_i && uop_i.rs2 != 0)
            src2_value_o = wb_data_i;

        src1_found_o = rs1_found_i;
        src2_found_o = rs2_found_i;
        src1_ready_o = 1'b1;
        src2_ready_o = 1'b1;
        if (rs1_found_i) begin
            src1_ready_o = rs1_scoreboard_ready_i;
            src1_value_o = rs1_scoreboard_data_i;
        end
        if (rs2_found_i) begin
            src2_ready_o = rs2_scoreboard_ready_i;
            src2_value_o = rs2_scoreboard_data_i;
        end

        // A DCache completion may feed the general consumer bypass but never
        // the address-generation path. This preserves the intentional timing
        // break on load-to-address dependencies.
        src1_memory_ready_o = src1_ready_o;
        src1_memory_value_o = src1_value_o;
        if (rs1_found_i) begin
            if (fixed_completion_valid_i &&
                fixed_completion_i.trans_id == rs1_trans_id_i) begin
                src1_ready_o = 1'b1;
                src1_value_o = fixed_completion_i.result;
                src1_memory_ready_o = 1'b1;
                src1_memory_value_o = fixed_completion_i.result;
            end else if (load_completion_valid_i &&
                         load_completion_meta_i.trans_id == rs1_trans_id_i) begin
                src1_ready_o = 1'b1;
                src1_value_o = load_result_i;
            end else if (slow_completion_valid_i &&
                         slow_completion_trans_id_i == rs1_trans_id_i) begin
                src1_ready_o = 1'b1;
                src1_value_o = slow_completion_result_i;
                src1_memory_ready_o = 1'b1;
                src1_memory_value_o = slow_completion_result_i;
            end
        end
        if (rs2_found_i) begin
            if (fixed_completion_valid_i &&
                fixed_completion_i.trans_id == rs2_trans_id_i) begin
                src2_ready_o = 1'b1;
                src2_value_o = fixed_completion_i.result;
            end else if (load_completion_valid_i &&
                         load_completion_meta_i.trans_id == rs2_trans_id_i) begin
                src2_ready_o = 1'b1;
                src2_value_o = load_result_i;
            end else if (slow_completion_valid_i &&
                         slow_completion_trans_id_i == rs2_trans_id_i) begin
                src2_ready_o = 1'b1;
                src2_value_o = slow_completion_result_i;
            end
        end
    end
endmodule
