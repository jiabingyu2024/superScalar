//==============================================================================
// 模块: stage_id
// 功能概述：
//   译码（ID）级顶层。整合控制译码、立即数、寄存器读等子模块：根据 IF/ID 寄存器输出的 PC、指令，
//   以及写回侧写使能/地址/数据，产生 EX 所需控制、立即数、rs1/rs2 数据与地址、rd 等。
// 接口/协作审查（供采纳）：
//   - 文件头曾误写为 control_unit.v，应以本模块名为准。
//   - i_pc_predict：与取指/BPU 一致的预测信息，供分支/相关逻辑使用；需与 reg_if_id 输出对齐。
//   - o_wb_src/o_inst_spec/o_alu_ctrl 等语义需在团队内固定编码表；o_is_rs2_imm 与 forward 的 i_is_rs2_imm 应对应。
//   - rs1/rs2/rd 地址用 [4:0] 与 `RF_BUS` 等价，建议统一改用宏以减少混用。
//==============================================================================
`include "cpu_defines.svh"

module stage_id(
    input  logic                            i_clk,
    input  logic                            i_rst_n,
    input  logic  [`PC_BUS]                 i_pc_f_d,
    input  logic  [`INST_BUS]               i_inst_f_d,
    input  logic  [`PC_BUS]                 i_pc_predict,

    input  logic                            i_we,
    input  logic  [`RF_BUS]                 i_w_addr,
    input  logic  [`DATA_BUS]               i_w_data,

    output logic                            o_mem_read,   // from control
    output logic                            o_mem_write,
    output logic                            o_reg_write,
    output logic                            o_wb_src,
    // output logic                            o_alu1_src,
    // output logic                            o_alu2_src,
    output logic                            o_is_rs2_imm,
    output logic  [3:0]                     o_inst_spec,

    output logic  [3:0]                     o_alu_ctrl,
    output logic  [2:0]                     o_func3,
    output logic  [3:0]                     o_mem_mask,
    output logic                            o_load_unsigned,

    output logic                            o_is_branch,
    // output logic                            o_is_jtype,
    // output logic                            o_is_lui,
    // output logic                            o_bcmp1_src,

    output logic  [`DATA_BUS]               o_imm,
    output logic  [`DATA_BUS]               o_rs1_data,
    output logic  [`RF_BUS]                 o_rs1_addr,
    output logic  [`DATA_BUS]               o_rs2_data,
    output logic  [`RF_BUS]                 o_rs2_addr,
    output logic  [`RF_BUS]                 o_rd_addr
);

    logic [`DATA_BUS] rs1_data;
    logic [`DATA_BUS] rs2_data;

    assign o_rs1_addr = i_inst_f_d[19:15];
    assign o_rs2_addr = i_inst_f_d[24:20];
    assign o_rd_addr  = i_inst_f_d[11:7];
    assign o_rs1_data = rs1_data;
    assign o_rs2_data = rs2_data;

    control_unit u_control_unit (
        .i_instr         (i_inst_f_d),
        .o_mem_read      (o_mem_read),
        .o_mem_write     (o_mem_write),
        .o_reg_write     (o_reg_write),
        .o_wb_src        (o_wb_src),
        .o_is_rs2_imm    (o_is_rs2_imm),
        .o_inst_spec     (o_inst_spec),
        .o_alu_ctrl      (o_alu_ctrl),
        .o_func3         (o_func3),
        .o_is_branch     (o_is_branch),
        .o_mem_mask      (o_mem_mask),
        .o_load_unsigned (o_load_unsigned)
    );

    imm_unit u_imm_unit (
        .i_instr (i_inst_f_d),
        .o_imm   (o_imm)
    );

    regfile u_regfile (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_we       (i_we),
        .i_rs1_addr (o_rs1_addr),
        .i_rs2_addr (o_rs2_addr),
        .i_w_addr   (i_w_addr),
        .i_w_data   (i_w_data),
        .o_rs1_data (rs1_data),
        .o_rs2_data (rs2_data)
    );
endmodule