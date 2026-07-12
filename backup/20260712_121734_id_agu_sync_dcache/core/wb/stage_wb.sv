//==============================================================================
// 模块: stage_wb
// 功能概述：
//   在 M2/WB 流水边界之前，根据 i_wb_src 选择最终写回数据。选择结果随后
//   由 reg_m2_wb 锁存，使 WB 写寄存器和 WB->EX 前递均直接使用寄存器输出。
// 接口/协作审查（供采纳）：
//   - i_wb_src 编码需与 ID 控制单元 o_wb_src 一致（0/1 含义文档化）。
//==============================================================================
`include "cpu_defines.svh"

module stage_wb(
    input  logic [`DATA_BUS]             i_alu_res,
    input  logic [`DATA_BUS]             i_mem_data,
    input  logic                         i_wb_src,

    output logic [`DATA_BUS]             o_wb_data
);

    always_comb begin
        o_wb_data = (i_wb_src == `WB_SRC_MEM) ? i_mem_data : i_alu_res;
    end
endmodule
