//==============================================================================
// 模块: reg_id_ex
// 功能概述：
//   ID/EX 流水线寄存器。将译码后的寄存器数据/地址、立即数、控制域（访存、写回、ALU、mask、分支、PC 等）
//   打入 EX 级，是前递与 hazard 观测的关键边界。
// 接口/协作审查（供采纳）：
//   - i_rs1_addr/i_rs2_addr 为 [4:0]，与 `RF_BUS` 一致；建议统一用宏书写。
//   - i_mem_mask 在 ID 由译码生成（lb/lh/lw 等），与 dram 访存类型一致。
//==============================================================================
`include "cpu_defines.svh"

module reg_id_ex(
    input logic                     i_clk,
    input logic                     i_rst_n,
    input logic                     i_flush,
    input logic                     i_stall,

    input logic [`DATA_BUS]         i_rs1_data,
    input logic [`RF_BUS]           i_rs1_addr,
    input logic [`DATA_BUS]         i_rs2_data,
    input logic [`RF_BUS]           i_rs2_addr,
    input logic [`RF_BUS]           i_rd_addr,

    input logic [`DATA_BUS]         i_imm,

    input logic                     i_mem_read,
    input logic                     i_reg_write,
    input logic                     i_mem_write,
    input logic                     i_wb_src,
    // input logic                     i_alu2_src,  // 0: rs2, 1: imm
    // input logic                     i_alu1_src,  // 0: rs1, 1: pc

    input  logic                    i_is_rs2_imm,
    input  logic  [3:0]             i_inst_spec,  

    input logic [3:0]               i_alu_ctrl,
    input logic [2:0]               i_func3,
    input logic [3:0]               i_mem_mask,
    input logic                     i_load_unsigned,

    input logic                     i_is_branch,
    // input logic                     i_is_jtype,
    // input logic                     i_is_lui,
    input logic [`PC_BUS]           i_pc_d_e,
    input logic [`PC_BUS]           i_pc_target,
    input logic [`PC_BUS]           i_pc_predict,
    input logic [1:0]               i_rs1_fwd_sel,
    input logic [1:0]               i_rs2_fwd_sel,


    output logic [`DATA_BUS]        o_rs1_data,
    output logic [`DATA_BUS]        o_rs2_data,
    output logic [4:0]              o_rd_addr,
    output logic [4:0]              o_rs1_addr,
    output logic [4:0]              o_rs2_addr,

    output logic [`DATA_BUS]        o_imm,

    output logic                    o_mem_read,
    output logic                    o_reg_write,
    output logic                    o_mem_write,
    output logic                    o_wb_src,
    // output logic                    o_alu2_src,
    // output logic                    o_alu1_src,
    output logic                    o_is_rs2_imm,
    output logic [3:0]              o_inst_spec,

    output logic [3:0]              o_alu_ctrl,
    output logic [2:0]              o_func3,
    output logic [3:0]              o_mem_mask,
    output logic                    o_load_unsigned,

    output logic                    o_is_branch,
    // output logic                    o_is_jtype,
    // output logic                    o_bcmp1_src,
    output logic [`PC_BUS]          o_pc_d_e,
    output logic [`PC_BUS]          o_pc_target,
    output logic [`PC_BUS]          o_pc_predict,
    output logic [1:0]              o_rs1_fwd_sel,
    output logic [1:0]              o_rs2_fwd_sel
);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_rs1_data       <= '0;
            o_rs2_data       <= '0;
            o_rd_addr        <= '0;
            o_rs1_addr       <= '0;
            o_rs2_addr       <= '0;
            o_imm            <= '0;
            o_mem_read       <= 1'b0;
            o_reg_write      <= 1'b0;
            o_mem_write      <= 1'b0;
            o_wb_src         <= `WB_SRC_ALU;
            o_is_rs2_imm     <= 1'b0;
            o_inst_spec      <= '0;
            o_alu_ctrl       <= `ALU_ADD;
            o_func3          <= 3'b000;
            o_mem_mask       <= `MASK_WORD;
            o_load_unsigned  <= 1'b0;
            o_is_branch      <= 1'b0;
            o_pc_d_e         <= '0;
            o_pc_target      <= '0;
            o_pc_predict     <= '0;
            o_rs1_fwd_sel    <= `FWD_RF;
            o_rs2_fwd_sel    <= `FWD_RF;
        end else if (i_flush) begin
            o_rs1_data       <= '0;
            o_rs2_data       <= '0;
            o_rd_addr        <= '0;
            o_rs1_addr       <= '0;
            o_rs2_addr       <= '0;
            o_imm            <= '0;
            o_mem_read       <= 1'b0;
            o_reg_write      <= 1'b0;
            o_mem_write      <= 1'b0;
            o_wb_src         <= `WB_SRC_ALU;
            o_is_rs2_imm     <= 1'b0;
            o_inst_spec      <= '0;
            o_alu_ctrl       <= `ALU_ADD;
            o_func3          <= 3'b000;
            o_mem_mask       <= `MASK_WORD;
            o_load_unsigned  <= 1'b0;
            o_is_branch      <= 1'b0;
            o_pc_d_e         <= '0;
            o_pc_target      <= '0;
            o_pc_predict     <= '0;
            o_rs1_fwd_sel    <= `FWD_RF;
            o_rs2_fwd_sel    <= `FWD_RF;
        end else if (!i_stall) begin
            o_rs1_data       <= i_rs1_data;
            o_rs2_data       <= i_rs2_data;
            o_rd_addr        <= i_rd_addr;
            o_rs1_addr       <= i_rs1_addr;
            o_rs2_addr       <= i_rs2_addr;
            o_imm            <= i_imm;
            o_mem_read       <= i_mem_read;
            o_reg_write      <= i_reg_write;
            o_mem_write      <= i_mem_write;
            o_wb_src         <= i_wb_src;
            o_is_rs2_imm     <= i_is_rs2_imm;
            o_inst_spec      <= i_inst_spec;
            o_alu_ctrl       <= i_alu_ctrl;
            o_func3          <= i_func3;
            o_mem_mask       <= i_mem_mask;
            o_load_unsigned  <= i_load_unsigned;
            o_is_branch      <= i_is_branch;
            o_pc_d_e         <= i_pc_d_e;
            o_pc_target      <= i_pc_target;
            o_pc_predict     <= i_pc_predict;
            o_rs1_fwd_sel    <= i_rs1_fwd_sel;
            o_rs2_fwd_sel    <= i_rs2_fwd_sel;
        end
    end
endmodule
