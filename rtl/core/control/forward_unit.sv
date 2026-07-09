//==============================================================================
// 模块: forward_unit
// 功能概述：
//   旁路（前递）控制。在 ID 级提前比较当前指令 rs1/rs2 与更老流水级 rd，
//   产生下一拍 EX 级使用的 rs1/rs2 前递选择信号。
//==============================================================================
`include "cpu_defines.svh"

module forward_unit (

    input  logic  [`RF_BUS]                 i_rs1_addr,
    input  logic  [`RF_BUS]                 i_rs2_addr,
    input  logic  [`RF_BUS]                 i_rd_addr_e,
    input  logic  [`RF_BUS]                 i_rd_addr_m,
    input  logic  [`RF_BUS]                 i_rd_addr_m2,

    input  logic                            i_reg_write_e,
    input  logic                            i_reg_write_m,
    input  logic                            i_reg_write_m2,

    output logic  [1:0]                     o_rs1_fwd_sel,
    output logic  [1:0]                     o_rs2_fwd_sel
);

    logic hit_rs1_e;
    logic hit_rs1_m;
    logic hit_rs1_m2;
    logic hit_rs2_e;
    logic hit_rs2_m;
    logic hit_rs2_m2;

    assign hit_rs1_e  = i_reg_write_e  && (i_rd_addr_e  != '0) && (i_rd_addr_e  == i_rs1_addr);
    assign hit_rs1_m  = i_reg_write_m  && (i_rd_addr_m  != '0) && (i_rd_addr_m  == i_rs1_addr);
    assign hit_rs1_m2 = i_reg_write_m2 && (i_rd_addr_m2 != '0) && (i_rd_addr_m2 == i_rs1_addr);
    assign hit_rs2_e  = i_reg_write_e  && (i_rd_addr_e  != '0) && (i_rd_addr_e  == i_rs2_addr);
    assign hit_rs2_m  = i_reg_write_m  && (i_rd_addr_m  != '0) && (i_rd_addr_m  == i_rs2_addr);
    assign hit_rs2_m2 = i_reg_write_m2 && (i_rd_addr_m2 != '0) && (i_rd_addr_m2 == i_rs2_addr);

    always_comb begin
        o_rs1_fwd_sel = `FWD_RF;
        o_rs2_fwd_sel = `FWD_RF;

        if (hit_rs1_e) begin
            o_rs1_fwd_sel = `FWD_E_M;
        end else if (hit_rs1_m) begin
            o_rs1_fwd_sel = `FWD_M_M;
        end else if (hit_rs1_m2) begin
            o_rs1_fwd_sel = `FWD_M_W;
        end

        if (hit_rs2_e) begin
            o_rs2_fwd_sel = `FWD_E_M;
        end else if (hit_rs2_m) begin
            o_rs2_fwd_sel = `FWD_M_M;
        end else if (hit_rs2_m2) begin
            o_rs2_fwd_sel = `FWD_M_W;
        end
    end
endmodule
