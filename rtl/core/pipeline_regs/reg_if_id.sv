//==============================================================================
// 模块: reg_if_id
// 功能概述：
//   IF/ID 流水线寄存器。锁存 PC、指令、以及取指时使用的预测 PC（i_pc_predict），在 stall 时保持、flush 时清或注气泡。
// 接口/协作审查（供采纳）：
//   - 端口列表最后一项 `o_pc_predict` 后带有尾随逗号：部分 Verilog 工具不支持端口尾逗号，若报错可删去逗号。
//   - i_pc_predict 与 BPU/IF 侧在取指拍对齐，供后续分支比较与 hazard 使用。
//==============================================================================
/*

    规范性要求:
        1. 输入输出端口信号均加前缀 "i_" 或 "o_"，以区分输入输出信号。
        2. 信号名全部小写，单词之间用下划线连接。
        3. 注意运用cpu_defines.v中的宏定义，增强可读性
    功能要求:

*/
`include "cpu_defines.svh"

module reg_if_id(
    input logic              i_clk,
    input logic              i_rst_n,
    input logic              i_flush,
    input logic              i_stall,
    
    input logic [`PC_BUS]    i_pc_f_d,
    input logic [`INST_BUS]  i_inst_f_d,
    input logic [`PC_BUS]    i_pc_predict,


    output logic [`PC_BUS]   o_pc_f_d,
    output logic [`INST_BUS] o_inst_f_d,
    output logic [`PC_BUS]   o_pc_predict
);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_pc_f_d     <= '0;
            o_inst_f_d   <= '0;
            o_pc_predict <= '0;
        end else if (i_flush) begin
            o_pc_f_d     <= '0;
            o_inst_f_d   <= '0;
            o_pc_predict <= '0;
        end else if (!i_stall) begin
            o_pc_f_d     <= i_pc_f_d;
            o_inst_f_d   <= i_inst_f_d;
            o_pc_predict <= i_pc_predict;
        end
    end
endmodule