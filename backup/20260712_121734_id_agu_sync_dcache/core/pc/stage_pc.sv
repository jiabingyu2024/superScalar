//==============================================================================
// 模块: stage_pc
// 功能概述：
//   PC 级封装模块。内部通常例化 pc_reg ：
//   根据 i_pc_next 更新 PC，输出当前 PC 。
// 接口/协作审查（供采纳）：
//   - i_pc_next 来源：复位初值、顺序 PC+4、分支纠正、BPU 预测目标等由顶层/hazard 汇总后接入。
//==============================================================================
`include "cpu_defines.svh"

module stage_pc(
    input  logic                    i_clk,
    input  logic                    i_rst_n,
    input  logic  [`PC_BUS]         i_pc_next,


    output logic  [`PC_BUS]         o_pc_cur
);

    pc_reg u_pc_reg (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_pc_next (i_pc_next),
        .o_pc_cur  (o_pc_cur)
    );

endmodule