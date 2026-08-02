//==============================================================================
// 模块: reg_m1_m2
// 功能概述：
//   M1/M2 流水线寄存器。锁存 ALU 结果、rd 与写回控制，供 M2 级访存数据处理与后续 WB 使用。
//==============================================================================
`include "cpu_defines.svh"

module reg_m1_m2 (
    input logic                               i_clk,
    input logic                               i_rst_n,
    input logic                               i_flush,
    input logic                               i_stall,

    input logic [`RF_BUS]                     i_rd_addr,
    input logic [`DATA_BUS]                   i_alu_res,
    input logic [`DATA_BUS]                   i_mem_data,

    input logic                               i_wb_src,
    input logic                               i_reg_write,
    input logic                               i_f_reg_write,
    input logic                               i_is_mul,
    input logic [`M_OP_BUS]                   i_m_op,

    output logic [`RF_BUS]                    o_rd_addr,
    output logic [`DATA_BUS]                  o_alu_res,
    output logic [`DATA_BUS]                  o_mem_data,

    output logic                              o_wb_src,
    output logic                              o_reg_write,
    output logic                              o_f_reg_write,
    output logic                              o_is_mul,
    output logic [`M_OP_BUS]                  o_m_op

);

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_mem_data      <= '0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_f_reg_write   <= 1'b0;
            o_is_mul        <= 1'b0;
            o_m_op          <= '0;
        end else if (i_flush) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_mem_data      <= '0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_f_reg_write   <= 1'b0;
            o_is_mul        <= 1'b0;
            o_m_op          <= '0;
        end else if (!i_stall) begin
            o_rd_addr       <= i_rd_addr;
            o_alu_res       <= i_alu_res;
            o_mem_data      <= i_mem_data;
            o_wb_src        <= i_wb_src;
            o_reg_write     <= i_reg_write;
            o_f_reg_write   <= i_f_reg_write;
            o_is_mul        <= i_is_mul;
            o_m_op          <= i_m_op;
        end
    end

endmodule
