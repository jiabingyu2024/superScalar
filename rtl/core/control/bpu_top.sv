//==============================================================================
// 模块: bpu_top
// 功能概述：
//   分支预测器顶层（BTB/BHT 等具体结构在内部实现）。根据当前 PC 给出是否预测跳转及目标地址；
//   在分支解析后根据 i_update_en、i_update_taken、i_update_pc、i_update_target 更新表项。
// 接口/协作审查（供采纳）：
//   - **i_pc_cur 当前声明为 1 位 logic，应为 `PC_BUS` 宽度的取指 PC**，否则无法索引 BTB/预测 RAM。
//   - i_update_* 与 branch_cmp/stage_ex 输出对接时序需约定（EX 级更新或 WB 级更新）。
//==============================================================================
/*

    规范性要求:
        1. 输入输出端口信号均加前缀 "i_" 或 "o_"，以区分输入输出信号。
        2. 信号名全部小写，单词之间用下划线连接。
        3. 注意运用cpu_defines.v中的宏定义，增强可读性
    功能要求:

*/
`include "cpu_defines.svh"

module bpu_top (
    input  logic                                    i_clk,
    input  logic                                    i_rst_n,

    input  logic  [`PC_BUS]                         i_pc_cur,

    input  logic                                    i_update_en,
    input  logic                                    i_update_taken,
    input  logic  [`PC_BUS]                         i_update_target,
    input  logic  [`PC_BUS]                         i_update_pc,
    
    output logic                                    o_predict_taken,
    output logic  [`PC_BUS]                         o_predict_target
);

    localparam int BPU_ENTRIES = 128;
    localparam int BPU_IDX_W   = 7;
    localparam int BPU_TAG_W   = `PC_WID - BPU_IDX_W - 2;

    logic [BPU_TAG_W-1:0] tag_mem     [0:BPU_ENTRIES-1];
    logic [`PC_BUS]       target_mem  [0:BPU_ENTRIES-1];
    logic [1:0]           counter_mem [0:BPU_ENTRIES-1];
    logic                 valid_mem   [0:BPU_ENTRIES-1];

    logic [BPU_IDX_W-1:0] rd_idx;
    logic [BPU_TAG_W-1:0] rd_tag;
    logic [BPU_IDX_W-1:0] wr_idx;
    logic [BPU_TAG_W-1:0] wr_tag;
    integer idx;

    assign rd_idx = i_pc_cur[BPU_IDX_W+1:2];
    assign rd_tag = i_pc_cur[`PC_WID-1:BPU_IDX_W+2];
    assign wr_idx = i_update_pc[BPU_IDX_W+1:2];
    assign wr_tag = i_update_pc[`PC_WID-1:BPU_IDX_W+2];

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            for (idx = 0; idx < BPU_ENTRIES; idx = idx + 1) begin
                tag_mem[idx]     <= '0;
                target_mem[idx]  <= '0;
                counter_mem[idx] <= 2'b01;
                valid_mem[idx]   <= 1'b0;
            end
        end else if (i_update_en) begin
            valid_mem[wr_idx]  <= 1'b1;
            tag_mem[wr_idx]    <= wr_tag;
            target_mem[wr_idx] <= i_update_target;

            if (i_update_taken) begin
                if (counter_mem[wr_idx] != 2'b11) begin
                    counter_mem[wr_idx] <= counter_mem[wr_idx] + 2'b01;
                end
            end else if (counter_mem[wr_idx] != 2'b00) begin
                counter_mem[wr_idx] <= counter_mem[wr_idx] - 2'b01;
            end
        end
    end

    always_comb begin
        o_predict_taken  = valid_mem[rd_idx] && (tag_mem[rd_idx] == rd_tag) && counter_mem[rd_idx][1];
        o_predict_target = target_mem[rd_idx];
    end
endmodule