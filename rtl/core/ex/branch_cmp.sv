//==============================================================================
// 模块: branch_cmp
// 功能概述：
//   分支比较与目标计算。根据 func3 比较 b1/b2（或经前递的操作数），结合 PC、立即数、预测 PC，
//   产生是否采纳分支、BPU 更新使能/目标，以及预测错误指示 o_error 与正确下址 o_rigit_pc（拼写见下）。
// 接口/协作审查（供采纳）：
//   - o_rigit_pc 建议视为 o_right_pc（拼写）；与 hazard_unit 的 i_rigit_pc 成对使用，改名需全设计一致。
//   - o_updata_en 与 BPU i_update_en 对齐；i_t1_data/i_t2_data 为分支目标相关操作数（如 PC+imm、rs1+imm）。
//   - i_is_branch 为 0 时应输出无分支副作用（或由上层屏蔽），避免误 flush。
//==============================================================================
`include "cpu_defines.svh"

module branch_cmp(
    input  logic  [`DATA_BUS]               i_b1_data,
    input  logic  [`DATA_BUS]               i_b2_data,
    input  logic  [2:0]                     i_func3,

    input  logic  [`PC_BUS]                 i_pc_d_e,
    input  logic  [`PC_BUS]                 i_pc_target,
    input  logic  [`PC_BUS]                 i_pc_predict,

    input  logic  [`PC_BUS]                 i_t1_data,
    input  logic  [`PC_BUS]                 i_t2_data,

    input  logic                            i_is_branch,
    // input  logic                            i_is_jtype,
    input  logic  [3:0]                     i_inst_spec,

    output logic                            o_update_taken,  // for BTB BHB
    output logic                            o_update_en,
    output logic  [`PC_BUS]                 o_update_pc,
    output logic  [`PC_BUS]                 o_update_target,

    output logic                            o_error,          // for hazard_unit
    output logic  [`PC_BUS]                 o_right_pc
);

    logic        branch_taken;
    logic [`PC_BUS] branch_target;
    logic [`PC_BUS] pc_plus4;
    logic [`PC_BUS] right_pc;

    always_comb begin
        branch_taken  = 1'b0;
        branch_target = i_pc_target;
        pc_plus4      = i_pc_d_e + 32'd4;

        if (i_is_branch) begin
            unique case (i_func3)
                `FUNC3_BEQ:  branch_taken = (i_b1_data == i_b2_data);
                `FUNC3_BNE:  branch_taken = (i_b1_data != i_b2_data);
                `FUNC3_BLT:  branch_taken = ($signed(i_b1_data) <  $signed(i_b2_data));
                `FUNC3_BGE:  branch_taken = ($signed(i_b1_data) >= $signed(i_b2_data));
                `FUNC3_BLTU: branch_taken = (i_b1_data <  i_b2_data);
                `FUNC3_BGEU: branch_taken = (i_b1_data >= i_b2_data);
                default:     branch_taken = 1'b0;
            endcase
        end else if (i_inst_spec == `EX_JAL) begin
            branch_taken = 1'b1;
        end else if (i_inst_spec == `EX_JALR) begin
            branch_taken  = 1'b1;
            branch_target = (i_t1_data + i_t2_data) & ~32'd1;
        end

        right_pc        = branch_taken ? branch_target : pc_plus4;
        o_update_en     = i_is_branch || (i_inst_spec == `EX_JAL) || (i_inst_spec == `EX_JALR);
        o_update_taken  = branch_taken;
        o_update_pc     = i_pc_d_e;
        o_update_target = right_pc;
        o_right_pc      = right_pc;
        o_error         = o_update_en && (right_pc != i_pc_predict);
    end
endmodule
