//==============================================================================
// 模块: stage_wb
// 功能概述：
//   写回（WB）级数据多路选择。根据 i_wb_src 在 ALU 结果与存储器读数据之间选择最终写回数据 o_wb_data。
// 接口/协作审查（供采纳）：
//   - 与 commit_unit 端口完全一致；团队可二选一作为唯一 WB 多路器，或分层：stage_wb 靠近流水线、commit 做提交语义扩展。
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