//==============================================================================
// 模块: alu
// 功能概述：
//   算术逻辑单元。根据 i_alu_ctrl（见 `ALU_*` 宏）对 i_alu1、i_alu2 进行加减、移位、比较、逻辑运算等，
//   输出 32 位 o_alu_res；JAL/AUIPC/LUI 等若由 EX 统一处理，也可在 stage_ex 中先选操作数再送入本模块。
// 接口/协作审查（供采纳）：
//   - i_alu_ctrl 宽度 [3:0] 与 `ALU_CTRL_WID` 一致；未使用编码建议 default 安全值以免锁存器/不定态。
//   - 有符号/无符号比较与 RISC-V slt/sltu 对应关系需在实现中与 branch_cmp 分工明确。
//==============================================================================
`include "cpu_defines.svh"

module alu(
    input  logic [`DATA_BUS]                i_alu1,
    input  logic [`DATA_BUS]                i_alu2,
    input  logic [3:0]                      i_alu_ctrl,
    
    output logic [`DATA_BUS]                o_alu_res
);

    always_comb begin
        unique case (i_alu_ctrl)
            `ALU_AND: o_alu_res = i_alu1 & i_alu2;
            `ALU_OR:  o_alu_res = i_alu1 | i_alu2;
            `ALU_XOR: o_alu_res = i_alu1 ^ i_alu2;
            `ALU_ADD: o_alu_res = i_alu1 + i_alu2;
            `ALU_SUB: o_alu_res = i_alu1 - i_alu2;
            `ALU_SL:  o_alu_res = i_alu1 << i_alu2[4:0];
            `ALU_SRL: o_alu_res = i_alu1 >> i_alu2[4:0];
            `ALU_SRA: o_alu_res = $signed(i_alu1) >>> i_alu2[4:0];
            `ALU_LT:  o_alu_res = ($signed(i_alu1) < $signed(i_alu2)) ? 32'd1 : 32'd0;
            `ALU_LTU: o_alu_res = (i_alu1 < i_alu2) ? 32'd1 : 32'd0;
            `ALU_GTE: o_alu_res = ($signed(i_alu1) >= $signed(i_alu2)) ? 32'd1 : 32'd0;
            `ALU_GTEU:o_alu_res = (i_alu1 >= i_alu2) ? 32'd1 : 32'd0;
            `ALU_EQ:  o_alu_res = (i_alu1 == i_alu2) ? 32'd1 : 32'd0;
            `ALU_NEQ: o_alu_res = (i_alu1 != i_alu2) ? 32'd1 : 32'd0;
            default:  o_alu_res = '0;
        endcase
    end
endmodule