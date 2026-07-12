//==============================================================================
// 模块: hazard_unit
// 功能概述：
//   冒险处理单元。产生 load-use 停顿（stall）与分支预测失败/异常恢复时的流水线 flush；
//   输出下一拍 PC（o_pc_next）供 IF 使用，并与各级流水线寄存器的 i_stall/i_flush 配合。
// 接口/协作审查（供采纳）：
//   - i_predict_taken/i_predict_target：与 BPU 输出对齐，用于与 branch_cmp 的 error/right_pc 仲裁下一地址。
//   - i_rigit_pc 建议视为正确 PC（right_pc 拼写）；与 branch_cmp.o_rigit_pc 对接。
//   - 输出 4 级 stall/flush 需与 reg_* 命名一致；若某级恒不刷，实现时可 tie 0 但端口保留便于扩展。
//==============================================================================
`include "cpu_defines.svh"

module hazard_unit(
    input  logic  [`PC_BUS]                 i_pc_cur,
    input  logic                            i_predict_taken,
    input  logic  [`PC_BUS]                 i_predict_target,
    input  logic                            i_error,
    input  logic  [`PC_BUS]                 i_right_pc,
    input  logic                            i_c1_busy,
    input  logic                            i_front_busy,
    input  logic                            i_addr_dep,
    output logic                            o_stall_front,
    output logic                            o_flush_front,
    output logic                            o_flush_c1,
    output logic                            o_hold_c1,
    output logic                            o_bubble_c1,
    output logic  [`PC_BUS]                 o_pc_next,
    output logic  [`PC_BUS]                 o_pc_predict
);
    always_comb begin
        o_stall_front = i_front_busy || i_addr_dep;
        o_flush_front = i_error;
        o_flush_c1    = i_error;
        o_hold_c1     = i_c1_busy;
        o_bubble_c1   = i_addr_dep && !i_c1_busy;
        o_pc_predict = i_predict_taken ? i_predict_target : (i_pc_cur + 32'd4);
        if (i_error) begin
            o_pc_next = i_right_pc;
        end else if (o_stall_front) begin
            o_pc_next = i_pc_cur;
        end else begin
            o_pc_next = o_pc_predict;
        end
    end
endmodule
