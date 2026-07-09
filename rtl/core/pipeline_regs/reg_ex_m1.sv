//==============================================================================
// 模块: reg_ex_m1
// 功能概述：
//==============================================================================
`include "cpu_defines.svh"

module reg_ex_m1 (
    input logic                               i_clk,
    input logic                               i_rst_n,
    input logic                               i_flush,
    input logic                               i_stall,

    input logic [`RF_BUS]                     i_rd_addr,
    input logic [`DATA_BUS]                   i_alu_res,
    input logic [`DATA_BUS]                   i_a2_data,

    input logic                               i_mem_read,
    input logic                               i_mem_write,
    input logic                               i_wb_src,
    input logic                               i_reg_write,
    input logic  [3:0]                        i_mem_mask,
    input logic                               i_load_unsigned,
    input logic                               i_update_taken,
    input logic                               i_update_en,
    input logic [`PC_BUS]                     i_update_pc,
    input logic [`PC_BUS]                     i_update_target,
    input logic                               i_branch_error,
    input logic [`PC_BUS]                     i_branch_right_pc,

    output logic [`RF_BUS]                    o_rd_addr,
    output logic [`DATA_BUS]                  o_alu_res,
    output logic [`DATA_BUS]                  o_a2_data,

    output logic                              o_mem_read,
    output logic                              o_mem_write,
    output logic                              o_wb_src,
    output logic                              o_reg_write,
    output logic [3:0]                        o_mem_mask,
    output logic                              o_load_unsigned,
    output logic                              o_update_taken,
    output logic                              o_update_en,
    output logic [`PC_BUS]                    o_update_pc,
    output logic [`PC_BUS]                    o_update_target,
    output logic                              o_branch_error,
    output logic [`PC_BUS]                    o_branch_right_pc

);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_a2_data       <= '0;
            o_mem_read      <= 1'b0;
            o_mem_write     <= 1'b0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_mem_mask      <= `MASK_WORD;
            o_load_unsigned <= 1'b0;
            o_update_taken  <= 1'b0;
            o_update_en     <= 1'b0;
            o_update_pc     <= '0;
            o_update_target <= '0;
            o_branch_error  <= 1'b0;
            o_branch_right_pc <= '0;
        end else if (i_flush) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_a2_data       <= '0;
            o_mem_read      <= 1'b0;
            o_mem_write     <= 1'b0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_mem_mask      <= `MASK_WORD;
            o_load_unsigned <= 1'b0;
            o_update_taken  <= 1'b0;
            o_update_en     <= 1'b0;
            o_update_pc     <= '0;
            o_update_target <= '0;
            o_branch_error  <= 1'b0;
            o_branch_right_pc <= '0;
        end else if (!i_stall) begin
            o_rd_addr       <= i_rd_addr;
            o_alu_res       <= i_alu_res;
            o_a2_data       <= i_a2_data;
            o_mem_read      <= i_mem_read;
            o_mem_write     <= i_mem_write;
            o_wb_src        <= i_wb_src;
            o_reg_write     <= i_reg_write;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
            o_update_taken  <= i_update_taken;
            o_update_en     <= i_update_en;
            o_update_pc     <= i_update_pc;
            o_update_target <= i_update_target;
            o_branch_error  <= i_branch_error;
            o_branch_right_pc <= i_branch_right_pc;
        end
    end
endmodule
