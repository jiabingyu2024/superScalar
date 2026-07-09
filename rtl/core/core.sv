//==============================================================================
// 模块: core_top
// 功能概述：
//   SoC/CPU 核顶层。仅例化 IF/ID/EX/MEM/WB、流水线寄存器、前递单元、冒险单元、BPU
//   等子模块并完成信号互连；不包含组合功能逻辑（仲裁、译码等应在下级模块实现）。
// 接口/协作审查（供采纳）：
//   - 当前仅 clk/rst_n；外设、总线、中断等按赛题在顶层或外层 wrapper 扩展。
//   - 命名：子模块例化前缀 u_；流水线相关时钟/复位/控制建议 P/F/D/E/M/W 分级命名便于 debug。
//==============================================================================
`include "cpu_defines.svh"

module core(
    input  logic                                     clk,
    input  logic                                     rst_n,

    input  logic  [`DATA_BUS]                        irom_data,
    output logic  [`PC_BUS]                          irom_addr,
    output logic                                     irom_ena,   // assign irom_ena = stall_p_f;

    input  logic  [`DATA_BUS]                        dram_rdata,
    output logic                                     dram_wen,
    output logic  [`RAM_ADDR_BUS]                    dram_addr,
    output logic  [`DATA_BUS]                        dram_wdata,
    output logic  [3:0]                              dram_mask

);
    logic [`PC_BUS]   pc_next_hz;
    logic [`PC_BUS]   pc_p;
    logic [`PC_BUS]   pc_predict_p;
    logic [`PC_BUS]   pc_pf;
    logic [`PC_BUS]   pc_predict_pf;
    logic             valid_pf;
    logic [`PC_BUS]   pc_predict_f;
    logic [`INST_BUS] inst_f;
    logic [`PC_BUS]   pc_f;
    logic             predict_taken_f;
    logic [`PC_BUS]   predict_target_f;

    logic [`PC_BUS]   pc_d;
    logic [`INST_BUS] inst_d;
    logic [`PC_BUS]   pc_predict_d;

    logic             mem_read_d;
    logic             mem_write_d;
    logic             reg_write_d;
    logic             wb_src_d;
    logic             is_rs2_imm_d;
    logic [3:0]       inst_spec_d;
    logic [3:0]       alu_ctrl_d;
    logic [2:0]       func3_d;
    logic [3:0]       mem_mask_d;
    logic             load_unsigned_d;
    logic             is_branch_d;
    logic [`DATA_BUS] imm_d;
    logic [`DATA_BUS] rs1_data_d;
    logic [`RF_BUS]   rs1_addr_d;
    logic [`DATA_BUS] rs2_data_d;
    logic [`RF_BUS]   rs2_addr_d;
    logic [`RF_BUS]   rd_addr_d;
    logic [`PC_BUS]   pc_target_d;

    logic [`DATA_BUS] rs1_data_e;
    logic [`DATA_BUS] rs2_data_e;
    logic [`RF_BUS]   rd_addr_e;
    logic [`RF_BUS]   rs1_addr_e;
    logic [`RF_BUS]   rs2_addr_e;
    logic [`DATA_BUS] imm_e;
    logic             mem_read_e;
    logic             reg_write_e;
    logic             mem_write_e;
    logic             wb_src_e;
    logic             is_rs2_imm_e;
    logic [3:0]       inst_spec_e;
    logic [3:0]       alu_ctrl_e;
    logic [2:0]       func3_e;
    logic [3:0]       mem_mask_e;
    logic             load_unsigned_e;
    logic             is_branch_e;
    logic [`PC_BUS]   pc_e;
    logic [`PC_BUS]   pc_target_e;
    logic [`PC_BUS]   pc_predict_e;

    logic [1:0]       rs1_fwd_sel_d;
    logic [1:0]       rs2_fwd_sel_d;
    logic [1:0]       rs1_fwd_sel_e;
    logic [1:0]       rs2_fwd_sel_e;

    logic [`DATA_BUS] alu_res_e;
    logic [`DATA_BUS] a2_data_e;
    logic             update_taken_e;
    logic             update_en_e;
    logic [`PC_BUS]   update_pc_e;
    logic [`PC_BUS]   update_target_e;
    logic             error_e;
    logic [`PC_BUS]   right_pc_e;

    logic [`RF_BUS]   rd_addr_m;
    logic [`DATA_BUS] alu_res_m;
    logic [`DATA_BUS] a2_data_m;
    logic             mem_read_m;
    logic             mem_write_m;
    logic             wb_src_m;
    logic             reg_write_m;
    logic [3:0]       mem_mask_m;
    logic             load_unsigned_m;
    logic             update_taken_m;
    logic             update_en_m;
    logic [`PC_BUS]   update_pc_m;
    logic [`PC_BUS]   update_target_m;
    logic             branch_error_m;
    logic [`PC_BUS]   branch_right_pc_m;

    logic [`RF_BUS]   rd_addr_m2;
    logic [`DATA_BUS] alu_res_m2;
    logic             wb_src_m2;
    logic             reg_write_m2;
    logic [3:0]       mem_mask_m2;
    logic             load_unsigned_m2;
    logic [`DATA_BUS] mem_data_m2;
    logic [`DATA_BUS] m1_m2_data;

    logic [`DATA_BUS] alu_res_w;
    logic [`RF_BUS]   rd_addr_w;
    logic [`DATA_BUS] mem_data_w;
    logic             wb_src_w;
    logic             reg_write_w;
    logic [`DATA_BUS] wb_data_w;

    logic             stall_p_f;
    logic             stall_f_d;
    logic             stall_d_e;
    logic             stall_e_m;
    logic             stall_m_w;
    logic             flush_p_f;
    logic             flush_f_d;
    logic             flush_d_e;
    logic             flush_e_m;
    logic             flush_m_w;

    assign irom_addr = pc_p;
    assign irom_ena  = !stall_p_f;
    assign pc_target_d = pc_d + imm_d;

    stage_pc u_stage_pc (
        .i_clk       (clk),
        .i_rst_n     (rst_n),
        .i_pc_next   (pc_next_hz),
        .o_pc_cur    (pc_p)
    );

    reg_pc_if u_reg_pc_if (
        .i_clk        (clk),
        .i_rst_n      (rst_n),
        .i_flush      (flush_p_f),
        .i_stall      (stall_p_f),
        .i_pc         (pc_p),
        .i_pc_predict (pc_predict_p),
        .o_pc         (pc_pf),
        .o_pc_predict (pc_predict_pf),
        .o_valid      (valid_pf)
    );

    stage_if u_stage_if (
        .i_pc         (pc_pf),
        .i_inst       (irom_data),
        .i_pc_predict (pc_predict_pf),
        .i_valid      (valid_pf),
        .o_pc         (pc_f),
        .o_inst       (inst_f),
        .o_pc_predict (pc_predict_f)
    );

    bpu_top u_bpu_top (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc_cur        (pc_p),
        .i_update_en     (update_en_m),
        .i_update_taken  (update_taken_m),
        .i_update_target (update_target_m),
        .i_update_pc     (update_pc_m),
        .o_predict_taken (predict_taken_f),
        .o_predict_target(predict_target_f)
    );

    hazard_unit u_hazard_unit (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc_cur        (pc_p),
        .i_rs1_addr_f    (inst_f[19:15]),
        .i_rs2_addr_f    (inst_f[24:20]),
        .i_rs1_addr_d    (rs1_addr_d),
        .i_rs2_addr_d    (rs2_addr_d),
        .i_rd_addr_e     (rd_addr_e),
        .i_mem_read_e    (mem_read_e),
        .i_reg_write_e   (reg_write_e),
        .i_predict_taken (predict_taken_f),
        .i_predict_target(predict_target_f),
        .i_error         (branch_error_m),
        .i_right_pc      (branch_right_pc_m),
        .o_stall_p_f     (stall_p_f),
        .o_stall_f_d     (stall_f_d),
        .o_stall_d_e     (stall_d_e),
        .o_stall_e_m     (stall_e_m),
        .o_stall_m_w     (stall_m_w),
        .o_flush_p_f     (flush_p_f),
        .o_flush_f_d     (flush_f_d),
        .o_flush_d_e     (flush_d_e),
        .o_flush_e_m     (flush_e_m),
        .o_flush_m_w     (flush_m_w),
        .o_pc_next       (pc_next_hz),
        .o_pc_predict    (pc_predict_p)
    );

    reg_if_id u_reg_if_id (
        .i_clk        (clk),
        .i_rst_n      (rst_n),
        .i_flush      (flush_f_d),
        .i_stall      (stall_f_d),
        .i_pc_f_d     (pc_f),
        .i_inst_f_d   (inst_f),
        .i_pc_predict (pc_predict_f),
        .o_pc_f_d     (pc_d),
        .o_inst_f_d   (inst_d),
        .o_pc_predict (pc_predict_d)
    );

    stage_id u_stage_id (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc_f_d        (pc_d),
        .i_inst_f_d      (inst_d),
        .i_pc_predict    (pc_predict_d),
        .i_we            (reg_write_w),
        .i_w_addr        (rd_addr_w),
        .i_w_data        (wb_data_w),
        .o_mem_read      (mem_read_d),
        .o_mem_write     (mem_write_d),
        .o_reg_write     (reg_write_d),
        .o_wb_src        (wb_src_d),
        .o_is_rs2_imm    (is_rs2_imm_d),
        .o_inst_spec     (inst_spec_d),
        .o_alu_ctrl      (alu_ctrl_d),
        .o_func3         (func3_d),
        .o_mem_mask      (mem_mask_d),
        .o_load_unsigned (load_unsigned_d),
        .o_is_branch     (is_branch_d),
        .o_imm           (imm_d),
        .o_rs1_data      (rs1_data_d),
        .o_rs1_addr      (rs1_addr_d),
        .o_rs2_data      (rs2_data_d),
        .o_rs2_addr      (rs2_addr_d),
        .o_rd_addr       (rd_addr_d)
    );

    forward_unit u_forward_unit (
        .i_rs1_addr      (rs1_addr_d),
        .i_rs2_addr      (rs2_addr_d),
        .i_rd_addr_e     (rd_addr_e),
        .i_rd_addr_m     (rd_addr_m),
        .i_rd_addr_m2    (rd_addr_m2),
        .i_reg_write_e   (reg_write_e),
        .i_reg_write_m   (reg_write_m),
        .i_reg_write_m2  (reg_write_m2),
        .o_rs1_fwd_sel   (rs1_fwd_sel_d),
        .o_rs2_fwd_sel   (rs2_fwd_sel_d)
    );

    reg_id_ex u_reg_id_ex (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (flush_d_e),
        .i_stall         (stall_d_e),
        .i_rs1_data      (rs1_data_d),
        .i_rs1_addr      (rs1_addr_d),
        .i_rs2_data      (rs2_data_d),
        .i_rs2_addr      (rs2_addr_d),
        .i_rd_addr       (rd_addr_d),
        .i_imm           (imm_d),
        .i_mem_read      (mem_read_d),
        .i_reg_write     (reg_write_d),
        .i_mem_write     (mem_write_d),
        .i_wb_src        (wb_src_d),
        .i_is_rs2_imm    (is_rs2_imm_d),
        .i_inst_spec     (inst_spec_d),
        .i_alu_ctrl      (alu_ctrl_d),
        .i_func3         (func3_d),
        .i_mem_mask      (mem_mask_d),
        .i_load_unsigned (load_unsigned_d),
        .i_is_branch     (is_branch_d),
        .i_pc_d_e        (pc_d),
        .i_pc_target     (pc_target_d),
        .i_pc_predict    (pc_predict_d),
        .i_rs1_fwd_sel   (rs1_fwd_sel_d),
        .i_rs2_fwd_sel   (rs2_fwd_sel_d),
        .o_rs1_data      (rs1_data_e),
        .o_rs2_data      (rs2_data_e),
        .o_rd_addr       (rd_addr_e),
        .o_rs1_addr      (rs1_addr_e),
        .o_rs2_addr      (rs2_addr_e),
        .o_imm           (imm_e),
        .o_mem_read      (mem_read_e),
        .o_reg_write     (reg_write_e),
        .o_mem_write     (mem_write_e),
        .o_wb_src        (wb_src_e),
        .o_is_rs2_imm    (is_rs2_imm_e),
        .o_inst_spec     (inst_spec_e),
        .o_alu_ctrl      (alu_ctrl_e),
        .o_func3         (func3_e),
        .o_mem_mask      (mem_mask_e),
        .o_load_unsigned (load_unsigned_e),
        .o_is_branch     (is_branch_e),
        .o_pc_d_e        (pc_e),
        .o_pc_target     (pc_target_e),
        .o_pc_predict    (pc_predict_e),
        .o_rs1_fwd_sel   (rs1_fwd_sel_e),
        .o_rs2_fwd_sel   (rs2_fwd_sel_e)
    );

    stage_ex u_stage_ex (
        .i_rs1_data      (rs1_data_e),
        .i_rs2_data      (rs2_data_e),
        .i_imm           (imm_e),
        .i_pc            (pc_e),
        .i_fwd_e_m       (alu_res_m),
        .i_fwd_m_w       (wb_data_w),
        .i_fwd_m_m       (m1_m2_data),
        .i_pc_d_e        (pc_e),
        .i_pc_target     (pc_target_e),
        .i_pc_predict    (pc_predict_e),
        .i_rs1_fwd_sel   (rs1_fwd_sel_e),
        .i_rs2_fwd_sel   (rs2_fwd_sel_e),
        .i_alu_ctrl      (alu_ctrl_e),
        .i_func3         (func3_e),
        .i_is_branch     (is_branch_e),
        .i_is_rs2_imm    (is_rs2_imm_e),
        .i_inst_spec     (inst_spec_e),
        .o_alu_res       (alu_res_e),
        .o_a2_data       (a2_data_e),
        .o_update_taken  (update_taken_e),
        .o_update_en     (update_en_e),
        .o_update_pc     (update_pc_e),
        .o_update_target (update_target_e),
        .o_error         (error_e),
        .o_right_pc      (right_pc_e)
    );

    reg_ex_m1 u_reg_ex_m1 (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (flush_e_m),
        .i_stall         (stall_e_m),
        .i_rd_addr       (rd_addr_e),
        .i_alu_res       (alu_res_e),
        .i_a2_data       (a2_data_e),
        .i_mem_read      (mem_read_e),
        .i_mem_write     (mem_write_e),
        .i_wb_src        (wb_src_e),
        .i_reg_write     (reg_write_e),
        .i_mem_mask      (mem_mask_e),
        .i_load_unsigned (load_unsigned_e),
        .i_update_taken  (update_taken_e),
        .i_update_en     (update_en_e),
        .i_update_pc     (update_pc_e),
        .i_update_target (update_target_e),
        .i_branch_error  (error_e),
        .i_branch_right_pc(right_pc_e),
        .o_rd_addr       (rd_addr_m),
        .o_alu_res       (alu_res_m),
        .o_a2_data       (a2_data_m),
        .o_mem_read      (mem_read_m),
        .o_mem_write     (mem_write_m),
        .o_wb_src        (wb_src_m),
        .o_reg_write     (reg_write_m),
        .o_mem_mask      (mem_mask_m),
        .o_load_unsigned (load_unsigned_m),
        .o_update_taken  (update_taken_m),
        .o_update_en     (update_en_m),
        .o_update_pc     (update_pc_m),
        .o_update_target (update_target_m),
        .o_branch_error  (branch_error_m),
        .o_branch_right_pc(branch_right_pc_m)
    );

    assign dram_wen   = mem_write_m;
    assign dram_addr  = alu_res_m[`RAM_ADDR_BUS];
    assign dram_wdata = a2_data_m;
    assign dram_mask  = mem_mask_m;

    reg_m1_m2 u_reg_m1_m2 (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (flush_m_w),
        .i_stall         (stall_m_w),
        .i_rd_addr       (rd_addr_m),
        .i_alu_res       (alu_res_m),
        .i_mem_mask      (mem_mask_m),
        .i_wb_src        (wb_src_m),
        .i_reg_write     (reg_write_m),
        .i_load_unsigned (load_unsigned_m),
        .o_rd_addr       (rd_addr_m2),
        .o_alu_res       (alu_res_m2),
        .o_mem_mask      (mem_mask_m2),
        .o_wb_src        (wb_src_m2),
        .o_reg_write     (reg_write_m2),
        .o_load_unsigned (load_unsigned_m2)
    );

    stage_m2 u_stage_m2 (
        .i_mem_mask      (mem_mask_m2),
        .i_load_unsigned (load_unsigned_m2),
        .i_dram_rdata    (dram_rdata),
        .o_mem_rdata     (mem_data_m2)
    );

    assign m1_m2_data = alu_res_m2;

    reg_m2_wb u_reg_m2_wb (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (1'b0),
        .i_stall         (1'b0),
        .i_reg_write     (reg_write_m2),
        .i_wb_src        (wb_src_m2),
        .i_alu_res       (alu_res_m2),
        .i_rd_addr       (rd_addr_m2),
        .i_mem_data      (mem_data_m2),
        .o_alu_res       (alu_res_w),
        .o_rd_addr       (rd_addr_w),
        .o_mem_data      (mem_data_w),
        .o_wb_src        (wb_src_w),
        .o_reg_write     (reg_write_w)
    );

    stage_wb u_stage_wb (
        .i_alu_res       (alu_res_w),
        .i_mem_data      (mem_data_w),
        .i_wb_src        (wb_src_w),
        .o_wb_data       (wb_data_w)
    );
endmodule
