//==============================================================================
// 模块: reg_m2_wb
// 功能概述：
//   MEM/WB 流水线寄存器。锁存待写回寄存器数据（ALU 结果与 load 数据）、rd、写回控制，供 WB 写寄存器堆。
// 接口/协作审查（供采纳）：
//   - i_mem_data 为 load 读出的数据（经 dram 一拍或组合读则与顶层时序一致）。
//==============================================================================
`include "cpu_defines.svh"

module reg_m2_wb(
    input  logic                         i_clk,
    input  logic                         i_rst_n,
    input  logic                         i_flush,
    input  logic                         i_stall,

    input  logic                         i_reg_write,
    input  logic                         i_wb_src,

    input  logic [`DATA_BUS]             i_alu_res,
    input  logic [`RF_BUS]               i_rd_addr,
    input  logic [`DATA_BUS]             i_mem_data,

    output logic [`DATA_BUS]             o_alu_res,
    output logic [`RF_BUS]               o_rd_addr,
    output logic [`DATA_BUS]             o_mem_data,

    output logic                         o_wb_src,
    output logic                         o_reg_write


);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_alu_res   <= '0;
            o_rd_addr   <= '0;
            o_mem_data  <= '0;
            o_wb_src    <= `WB_SRC_ALU;
            o_reg_write <= 1'b0;
        end else if (i_flush) begin
            o_alu_res   <= '0;
            o_rd_addr   <= '0;
            o_mem_data  <= '0;
            o_wb_src    <= `WB_SRC_ALU;
            o_reg_write <= 1'b0;
        end else if (!i_stall) begin
            o_alu_res   <= i_alu_res;
            o_rd_addr   <= i_rd_addr;
            o_mem_data  <= i_mem_data;
            o_wb_src    <= i_wb_src;
            o_reg_write <= i_reg_write;
        end
    end
endmodule