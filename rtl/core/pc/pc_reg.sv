//==============================================================================
// 模块: pc_reg
// 功能概述：
//   程序计数器寄存器。在时钟上升沿（配合同步复位策略）将 i_pc_next 打一拍输出为 o_pc_cur，
//   作为当前取指地址（或经组合逻辑再送 ROM，依顶层连接而定）。
// 接口/协作审查（供采纳）：
//   - 端口语义清晰；若需与 stall/flush 配合，通常在顶层用多路或使能控制 i_pc_next，本模块保持最简寄存器即可。
//==============================================================================
`include "cpu_defines.svh"

module pc_reg(
    input  logic                     i_clk,
    input  logic                     i_rst_n,
    input  logic   [`PC_BUS]         i_pc_next,    
    output logic   [`PC_BUS]         o_pc_cur         // 输出当前指令地址
);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_pc_cur <= 32'h8000_0000;
        end else begin
            o_pc_cur <= i_pc_next;
        end
    end
endmodule