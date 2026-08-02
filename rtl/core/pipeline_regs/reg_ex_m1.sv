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
    input logic [`DATA_BUS]                   i_mem_addr,
    input logic [`DATA_BUS]                   i_a2_data,

    input logic                               i_mem_read,
    input logic                               i_mem_write,
    input logic                               i_wb_src,
    input logic                               i_reg_write,
    input logic                               i_f_reg_write,
    input logic  [3:0]                        i_mem_mask,
    input logic                               i_load_unsigned,
    input logic                               i_is_mul,
    input logic [`M_OP_BUS]                   i_m_op,
    input logic                               i_update_taken,
    input logic                               i_update_en,
    input logic [`PC_BUS]                     i_update_pc,
    input logic [`PC_BUS]                     i_update_target,
    input logic [`PC_BUS]                     i_update_bpu_target,
    input logic [7:0]                         i_update_pht_idx,
    input logic                               i_update_is_cond,
    input logic                               i_update_is_call,
    input logic                               i_update_is_return,
    input logic                               i_branch_error,

    output logic [`RF_BUS]                    o_rd_addr,
    // The M1 address/result fans out into all DCache LUTRAM banks.  Request
    // synthesis-time register replication so each physical copy serves a
    // bounded bank group; this does not add a pipeline stage.
    (* max_fanout = 32 *) output logic [`DATA_BUS] o_alu_res,
    output logic [`DATA_BUS]                  o_mem_addr,
    output logic [`DATA_BUS]                  o_a2_data,

    output logic                              o_mem_read,
    output logic                              o_mem_write,
    output logic                              o_wb_src,
    output logic                              o_reg_write,
    output logic                              o_f_reg_write,
    output logic [3:0]                        o_mem_mask,
    output logic                              o_load_unsigned,
    output logic                              o_is_mul,
    output logic [`M_OP_BUS]                  o_m_op,
    output logic                              o_update_taken,
    output logic                              o_update_en,
    output logic [`PC_BUS]                    o_update_pc,
    output logic [`PC_BUS]                    o_update_target,
    output logic [`PC_BUS]                    o_update_bpu_target,
    output logic [7:0]                        o_update_pht_idx,
    output logic                              o_update_is_cond,
    output logic                              o_update_is_call,
    output logic                              o_update_is_return,
    output logic                              o_branch_error

);

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_mem_addr      <= '0;
            o_a2_data       <= '0;
            o_mem_read      <= 1'b0;
            o_mem_write     <= 1'b0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_f_reg_write   <= 1'b0;
            o_mem_mask      <= `MASK_WORD;
            o_load_unsigned <= 1'b0;
            o_is_mul        <= 1'b0;
            o_m_op          <= '0;
            o_update_taken  <= 1'b0;
            o_update_en     <= 1'b0;
            o_update_pc     <= '0;
            o_update_target <= '0;
            o_update_bpu_target <= '0;
            o_update_pht_idx <= '0;
            o_update_is_cond <= 1'b0;
            o_update_is_call <= 1'b0;
            o_update_is_return <= 1'b0;
            o_branch_error  <= 1'b0;
        end else if (i_flush) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_mem_addr      <= '0;
            o_a2_data       <= '0;
            o_mem_read      <= 1'b0;
            o_mem_write     <= 1'b0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_f_reg_write   <= 1'b0;
            o_mem_mask      <= `MASK_WORD;
            o_load_unsigned <= 1'b0;
            o_is_mul        <= 1'b0;
            o_m_op          <= '0;
            o_update_taken  <= 1'b0;
            o_update_en     <= 1'b0;
            o_update_pc     <= '0;
            o_update_target <= '0;
            o_update_bpu_target <= '0;
            o_update_pht_idx <= '0;
            o_update_is_cond <= 1'b0;
            o_update_is_call <= 1'b0;
            o_update_is_return <= 1'b0;
            o_branch_error  <= 1'b0;
        end else if (!i_stall) begin
            o_rd_addr       <= i_rd_addr;
            o_alu_res       <= i_alu_res;
            o_mem_addr      <= i_mem_addr;
            o_a2_data       <= i_a2_data;
            o_mem_read      <= i_mem_read;
            o_mem_write     <= i_mem_write;
            o_wb_src        <= i_wb_src;
            o_reg_write     <= i_reg_write;
            o_f_reg_write   <= i_f_reg_write;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
            o_is_mul        <= i_is_mul;
            o_m_op          <= i_m_op;
            o_update_taken  <= i_update_taken;
            o_update_en     <= i_update_en;
            o_update_pc     <= i_update_pc;
            o_update_target <= i_update_target;
            o_update_bpu_target <= i_update_bpu_target;
            o_update_pht_idx <= i_update_pht_idx;
            o_update_is_cond <= i_update_is_cond;
            o_update_is_call <= i_update_is_call;
            o_update_is_return <= i_update_is_return;
            o_branch_error  <= i_branch_error;
        end
    end
endmodule
