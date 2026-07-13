//==============================================================================
// 模块: stage_if
// 功能概述：
//  纯组合逻辑。valid 为 1 时输出已对齐的 PC、IROM instruction 和预测 PC，否则输出 0。
//==============================================================================
`include "cpu_defines.svh"

module stage_if(
    input  logic  [`PC_BUS]         i_pc,
    input  logic  [`INST_BUS]       i_inst,
    input  logic  [`PC_BUS]         i_pc_predict,

    input  logic                    i_valid,

    output logic  [`PC_BUS]         o_pc,
    output logic  [`INST_BUS]       o_inst,
    output logic  [`PC_BUS]         o_pc_predict

);

    always_comb begin
        if (i_valid) begin
            o_pc         = i_pc;
            o_inst       = i_inst;
            o_pc_predict = i_pc_predict;
        end else begin
            o_pc         = '0;
            o_inst       = '0;
            o_pc_predict = '0;
        end
    end

endmodule
