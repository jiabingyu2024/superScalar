//==============================================================================
// 模块: reg_m2_wb
// 功能概述：
//   M2/WB 流水线寄存器。锁存 M2 级已经选择完成的最终写回数据、rd 和写使能。
// 接口/协作审查（供采纳）：
//   - ALU/load 选择必须在本寄存器之前完成，使 WB 前递只经过寄存器 Q。
//==============================================================================
`include "cpu_defines.svh"

module reg_m2_wb(
    input  logic                         i_clk,
    input  logic                         i_rst_n,
    input  logic                         i_flush,
    input  logic                         i_stall,

    input  logic                         i_reg_write,
    input  logic                         i_f_reg_write,

    input  logic [`RF_BUS]               i_rd_addr,
    input  logic [`DATA_BUS]             i_wb_data,
    input  logic                         i_is_mul,
    input  logic [`M_OP_BUS]              i_m_op,

    output logic [`RF_BUS]               o_rd_addr,
    output logic [`DATA_BUS]             o_wb_data,

    output logic                         o_reg_write,
    output logic                         o_f_reg_write,
    output logic                         o_is_mul,
    output logic [`M_OP_BUS]              o_m_op


);

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_rd_addr   <= '0;
            o_wb_data   <= '0;
            o_reg_write <= 1'b0;
            o_f_reg_write <= 1'b0;
            o_is_mul    <= 1'b0;
            o_m_op      <= '0;
        end else if (i_flush) begin
            o_rd_addr   <= '0;
            o_wb_data   <= '0;
            o_reg_write <= 1'b0;
            o_f_reg_write <= 1'b0;
            o_is_mul    <= 1'b0;
            o_m_op      <= '0;
        end else if (!i_stall) begin
            o_rd_addr   <= i_rd_addr;
            o_wb_data   <= i_wb_data;
            o_reg_write <= i_reg_write;
            o_f_reg_write <= i_f_reg_write;
            o_is_mul    <= i_is_mul;
            o_m_op      <= i_m_op;
        end
    end
endmodule
