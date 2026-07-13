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

    input logic [3:0]                         i_mem_mask,

    input logic                               i_wb_src,
    input logic                               i_reg_write,
    input logic                               i_load_unsigned,

    output logic [`RF_BUS]                    o_rd_addr,
    output logic [`DATA_BUS]                  o_alu_res,

    output logic [3:0]                        o_mem_mask,

    output logic                              o_wb_src,
    output logic                              o_reg_write,
    output logic                              o_load_unsigned

);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_load_unsigned <= 1'b0;
            o_mem_mask      <= 4'b0000;
        end else if (i_flush) begin
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_load_unsigned <= 1'b0;
            o_mem_mask      <= 4'b0000;
        end else if (!i_stall) begin
            o_rd_addr       <= i_rd_addr;
            o_alu_res       <= i_alu_res;
            o_wb_src        <= i_wb_src;
            o_reg_write     <= i_reg_write;
            o_load_unsigned <= i_load_unsigned;
            o_mem_mask      <= i_mem_mask;
        end
    end

endmodule
