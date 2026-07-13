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
    input  logic                            i_mem_read_d,
    input  logic                            i_mem_write_d,
    input  logic                            i_is_branch_d,
    input  logic                            i_is_m_ext_d,
    input  logic                            i_is_rs2_imm_d,
    input  logic  [3:0]                     i_inst_spec_d,
    input  logic  [`RF_BUS]                 i_rd_addr_e,
    input  logic                            i_mem_read_e,
    input  logic                            i_reg_write_e,//load_use
    input  logic                            i_is_mul_e,
    input  logic  [`RF_BUS]                 i_rd_addr_ex2,
    input  logic                            i_mem_read_ex2,
    input  logic                            i_reg_write_ex2,
    input  logic                            i_is_mul_ex2,

    input  logic                            i_predict_taken,
    input  logic  [`PC_BUS]                 i_predict_target,

    input  logic                            i_error,
    input  logic  [`PC_BUS]                 i_right_pc,

    input  logic                            i_m_busy,
    input  logic                            i_mem_busy,

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
    logic load_use_hazard;
    logic timing_isolated_consumer_d;
    logic load_dep_rs1_d;
    logic load_dep_rs2_d;
    logic mul_use_hazard;
    logic data_hazard;

    // Keep zero-bubble forwarding for short integer consumers, but insert one
    // bubble before consumers whose EX2 path expands the asynchronous DCache
    // result into control, CSR, M-extension, or another cache access network.
    // This breaks the broad timing cones without paying the cost on every
    // load-use pair. Immediate-form CSR instructions do not consume rs1.
    assign timing_isolated_consumer_d =
        i_mem_read_d || i_mem_write_d || i_is_branch_d || i_is_m_ext_d ||
        (i_inst_spec_d == `EX_JALR) ||
        ((i_inst_spec_d == `EX_CSR) && !i_is_rs2_imm_d);
    assign load_dep_rs1_d = (i_rd_addr_e == i_rs1_addr_d);
    assign load_dep_rs2_d = (i_rd_addr_e == i_rs2_addr_d) &&
                            (i_is_branch_d || i_mem_write_d || i_is_m_ext_d);
    assign load_use_hazard_raw_e =
        i_mem_read_e && i_reg_write_e && (i_rd_addr_e != '0) &&
        timing_isolated_consumer_d && (load_dep_rs1_d || load_dep_rs2_d);
    assign load_use_hazard = load_use_hazard_raw_e;
    assign mul_use_hazard =
        (i_is_mul_e && i_reg_write_e && (i_rd_addr_e != '0) &&
         ((i_rd_addr_e == i_rs1_addr_d) || (i_rd_addr_e == i_rs2_addr_d))) ||
        (i_is_mul_ex2 && i_reg_write_ex2 && (i_rd_addr_ex2 != '0) &&
         ((i_rd_addr_ex2 == i_rs1_addr_d) || (i_rd_addr_ex2 == i_rs2_addr_d)));
    assign data_hazard = load_use_hazard || mul_use_hazard;

    always_comb begin

        o_stall_p_f = data_hazard || i_m_busy || i_mem_busy;
        o_stall_f_d = data_hazard || i_m_busy || i_mem_busy;
        o_stall_d_e = i_m_busy || i_mem_busy;
        // When EX is busy with MUL/DIV, let the older M1 instruction drain once
        // and inject bubbles into EX/M. Holding EX/M would replay the same M1
        // load/store every busy cycle on this ready-valid DCache port.
        o_stall_e_m = i_mem_busy;
        // A DCache miss stalls the M1 request, but the older instruction already
        // in M2 must still drain to WB.  While M1 is held, M2 is turned into a
        // bubble via o_flush_m_w below; stalling M2/WB would pair the eventual
        // miss return data with stale M2 metadata on the release cycle.
        o_stall_m_w = 1'b0;

        o_flush_p_f = i_error;
        o_flush_f_d = i_error;
        o_flush_d_e = i_error || (data_hazard && !i_m_busy && !i_mem_busy);
        // Redirect is reported from EX/M1, so the current EX instruction is
        // already a younger wrong-path instruction and must be squashed.
        o_flush_e_m = i_error || (i_m_busy && !i_mem_busy);
        o_flush_m_w = i_mem_busy;

        o_pc_predict = i_predict_taken ? i_predict_target : (i_pc_cur + 32'd4);

        if (i_error) begin
            o_pc_next = i_right_pc;
        end else if (data_hazard || i_m_busy || i_mem_busy) begin
            o_pc_next = i_pc_cur;
        end else begin
            o_pc_next = o_pc_predict;
        end
    end
endmodule
