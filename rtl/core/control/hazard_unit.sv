//==============================================================================
// 模块: hazard_unit
// 功能概述：
//   冒险处理单元。产生 load-use 停顿（stall）与分支预测失败/异常恢复时的流水线 flush；
//   输出下一拍 PC（o_pc_next）供 IF 使用，并与各级流水线寄存器的 i_stall/i_flush 配合。
// 接口/协作审查（供采纳）：
//   - i_predict_taken/i_predict_target：与 BPU 输出对齐，用于与 branch_cmp 的 error/right_pc 仲裁下一地址。
//   - i_rigit_pc 建议视为正确 PC（right_pc 拼写）；与 branch_cmp.o_rigit_pc 对接。
//   - 输出 4 级 stall/flush 需与 reg_* 命名一致；若某级恒不刷，实现时可 tie 0 但端口保留便于扩展。
//==============================================================================
`include "cpu_defines.svh"

module hazard_unit(
    input  logic                            i_clk,
    input  logic                            i_rst_n,
    input  logic  [`PC_BUS]                 i_pc_cur,
    input  logic  [`RF_BUS]                 i_rs1_addr_f,
    input  logic  [`RF_BUS]                 i_rs2_addr_f,
    input  logic  [`RF_BUS]                 i_rs1_addr_d,
    input  logic  [`RF_BUS]                 i_rs2_addr_d,
    input  logic  [`RF_BUS]                 i_rd_addr_e,
    input  logic                            i_mem_read_e,
    input  logic                            i_reg_write_e,//load_use

    input  logic                            i_predict_taken,
    input  logic  [`PC_BUS]                 i_predict_target,

    input  logic                            i_error,
    input  logic  [`PC_BUS]                 i_right_pc,

    output logic                            o_stall_p_f,
    output logic                            o_stall_f_d,
    output logic                            o_stall_d_e,
    output logic                            o_stall_e_m,
    output logic                            o_stall_m_w,

    output logic                            o_flush_p_f,
    output logic                            o_flush_f_d,
    output logic                            o_flush_d_e,
    output logic                            o_flush_e_m,
    output logic                            o_flush_m_w,

    output logic  [`PC_BUS]                 o_pc_next,
    output logic  [`PC_BUS]                 o_pc_predict


);

    logic load_use_hazard_raw_e;
    logic load_use_hazard_raw_f;
    logic load_use_hazard_hold_d;
    logic load_use_hazard_hold_f;
    logic load_use_hazard;

    assign load_use_hazard_raw_e = i_mem_read_e && i_reg_write_e && (i_rd_addr_e != '0) &&
                                   ((i_rd_addr_e == i_rs1_addr_d) || (i_rd_addr_e == i_rs2_addr_d));
    assign load_use_hazard_raw_f = i_mem_read_e && i_reg_write_e && (i_rd_addr_e != '0) &&
                                   ((i_rd_addr_e == i_rs1_addr_f) || (i_rd_addr_e == i_rs2_addr_f));
    assign load_use_hazard = load_use_hazard_raw_e || load_use_hazard_hold_d || load_use_hazard_hold_f;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            load_use_hazard_hold_d <= 1'b0;
            load_use_hazard_hold_f <= 1'b0;
        end else if (i_error) begin
            load_use_hazard_hold_d <= 1'b0;
            load_use_hazard_hold_f <= 1'b0;
        end else begin
            load_use_hazard_hold_d <= load_use_hazard_raw_e;
            load_use_hazard_hold_f <= load_use_hazard_raw_f && !load_use_hazard_raw_e;
        end
    end

    always_comb begin

        o_stall_p_f = load_use_hazard;
        o_stall_f_d = load_use_hazard;
        o_stall_d_e = 1'b0;
        o_stall_e_m = 1'b0;
        o_stall_m_w = 1'b0;

        o_flush_p_f = i_error;
        o_flush_f_d = i_error;
        o_flush_d_e = i_error || load_use_hazard;
        // Redirect is reported from EX/M1, so the current EX instruction is
        // already a younger wrong-path instruction and must be squashed.
        o_flush_e_m = i_error;
        o_flush_m_w = 1'b0;

        o_pc_predict = i_predict_taken ? i_predict_target : (i_pc_cur + 32'd4);

        if (i_error) begin
            o_pc_next = i_right_pc;
        end else if (load_use_hazard) begin
            o_pc_next = i_pc_cur;
        end else begin
            o_pc_next = o_pc_predict;
        end
    end
endmodule
