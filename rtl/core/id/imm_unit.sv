//==============================================================================
// 模块: imm_unit
// 功能概述：
//   立即数扩展。根据指令格式（I/S/B/U/J）从指令位域拼接并符号扩展为 32 位 o_imm。
// 接口/协作审查（供采纳）：
//   - 端口名为 i_instr 更贴切；当前为 `DATA_BUS` 与指令位宽相同，语义上建议类型为 `INST_BUS` 以增强可读性（可选优化）。
//   - 若仅使用低 32 位，实现时仍应对齐 RISC-V 各型立即数位域。
//==============================================================================
`include "cpu_defines.svh"

module imm_unit(
    input wire [`INST_BUS]          i_instr,
    output wire [`DATA_BUS]         o_imm
);

    logic [6:0] opcode;

    assign opcode = i_instr[6:0];

    assign o_imm = ({32{opcode == `OP_I_TYPE || opcode == `OP_L_TYPE || opcode == `OP_JALR}} &
                    {{20{i_instr[31]}}, i_instr[31:20]}) |
                   ({32{opcode == `OP_S_TYPE}} &
                    {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]}) |
                   ({32{opcode == `OP_B_TYPE}} &
                    {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0}) |
                   ({32{opcode == `OP_LUI || opcode == `OP_AUIPC}} &
                    {i_instr[31:12], 12'b0}) |
                   ({32{opcode == `OP_JAL}} &
                    {{11{i_instr[31]}}, i_instr[31], i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0});
endmodule
