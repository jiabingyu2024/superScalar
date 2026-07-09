//==============================================================================
// 模块: stage_ex
// 功能概述：
//   执行（EX）级顶层。根据前递选择信号从 rs1/rs2/imm/pc、EX/M、M/W 结果中选择操作数，送 ALU；
//   分支类指令配合 branch_cmp 产生是否更新预测表、正确目标等；输出 ALU 结果供 MEM/WB 使用。
// 接口/协作审查（供采纳）：
//   - i_rs1_data/i_rs2_data 与 i_fwd_e_m/i_fwd_m_w 的分工：实现时需明确是否“原始寄存器值 + 旁路 MUX”在内部合并。
//   - o_updata_en 建议视为 o_update_en（拼写）；与 bpu_top 的 i_update_en 应对接。
//   - i_pc_d_e 与 i_pc：前者多为 ID/EX 寄存器中的 PC，后者为当前 EX 指令 PC，用于 AUIPC/JAL 等，团队需统一连法。
//==============================================================================
`include "cpu_defines.svh"

module stage_ex(
    input  logic  [`DATA_BUS]               i_rs1_data,
    input  logic  [`DATA_BUS]               i_rs2_data,
    input  logic  [`DATA_BUS]               i_imm,
    input  logic  [`PC_BUS]                 i_pc,
    input  logic  [`DATA_BUS]               i_fwd_e_m,
    input  logic  [`DATA_BUS]               i_fwd_m_w,
    input  logic  [`DATA_BUS]               i_fwd_m_m,   //新增一个EX/MEM的前递数据输入

    input  logic  [`PC_BUS]                 i_pc_d_e,
    input  logic  [`PC_BUS]                 i_pc_target,
    input  logic  [`PC_BUS]                 i_pc_predict,

    input  logic  [1:0]                     i_rs1_fwd_sel,
    input  logic  [1:0]                     i_rs2_fwd_sel,

    input  logic  [3:0]                     i_alu_ctrl,
    input  logic  [2:0]                     i_func3,

    input  logic                            i_is_branch,
    // input  logic                            i_is_jtype,
    // input  logic                            i_is_lui,
    input  logic                            i_is_rs2_imm,
    input  logic  [3:0]                     i_inst_spec,

    output logic  [`DATA_BUS]               o_alu_res,
    output logic  [`DATA_BUS]               o_a2_data,

    output logic                            o_update_taken,
    output logic                            o_update_en,
    output logic  [`PC_BUS]                 o_update_pc,
    output logic  [`PC_BUS]                 o_update_target,
    output logic                            o_error,
    output logic  [`PC_BUS]                 o_right_pc
    
);

    logic [`DATA_BUS] a1_data;
    logic [`DATA_BUS] a2_data;
    logic [`DATA_BUS] rs1_exec_data;
    logic [`DATA_BUS] rs2_exec_data;
    logic [`PC_BUS]   t1_data;
    logic [`DATA_BUS] alu_res_raw;

    always_comb begin
        unique case (i_rs1_fwd_sel)
            `FWD_E_M:  rs1_exec_data = i_fwd_e_m;
            `FWD_M_M:  rs1_exec_data = i_fwd_m_m;
            `FWD_M_W:  rs1_exec_data = i_fwd_m_w;
            default:   rs1_exec_data = i_rs1_data;
        endcase

        unique case (i_rs2_fwd_sel)
            `FWD_E_M:  rs2_exec_data = i_fwd_e_m;
            `FWD_M_M:  rs2_exec_data = i_fwd_m_m;
            `FWD_M_W:  rs2_exec_data = i_fwd_m_w;
            default:   rs2_exec_data = i_rs2_data;
        endcase

        t1_data = (i_inst_spec == `EX_JALR) ? rs1_exec_data : i_pc_d_e;
        a1_data = (i_inst_spec == `EX_AUIPC) ? i_pc : rs1_exec_data;
        a2_data = (i_is_rs2_imm || (i_inst_spec == `EX_AUIPC)) ? i_imm : rs2_exec_data;
    end

    alu u_alu (
        .i_alu1     (a1_data),
        .i_alu2     (a2_data),
        .i_alu_ctrl (i_alu_ctrl),
        .o_alu_res  (alu_res_raw)
    );

    branch_cmp u_branch_cmp (
        .i_b1_data       (rs1_exec_data),
        .i_b2_data       (rs2_exec_data),
        .i_func3         (i_func3),
        .i_pc_d_e        (i_pc_d_e),
        .i_pc_target     (i_pc_target),
        .i_pc_predict    (i_pc_predict),
        .i_t1_data       (t1_data),
        .i_t2_data       (i_imm),
        .i_is_branch     (i_is_branch),
        .i_inst_spec     (i_inst_spec),
        .o_update_taken  (o_update_taken),
        .o_update_en     (o_update_en),
        .o_update_pc     (o_update_pc),
        .o_update_target (o_update_target),
        .o_error         (o_error),
        .o_right_pc      (o_right_pc)
    );

    always_comb begin
        o_a2_data = rs2_exec_data;

        unique case (i_inst_spec)
            `EX_LUI:   o_alu_res = i_imm;
            `EX_JAL,
            `EX_JALR:  o_alu_res = i_pc + 32'd4;
            default:     o_alu_res = alu_res_raw;
        endcase
    end
endmodule
