`timescale 1ns / 1ps
//==============================================================================
// 模块: m_unit
// 功能概述：
//   RV32M 计算单元。例化 MUL_0（3拍，33×33有符号）和 DIV_0（34拍，32位无符号 AXI-Stream）。
//   MUL/MULH/MULHSU/MULHU 按符号扩展规则选择 MUL_0 实例；DIV/REM 通过绝对值预处理后送
//   无符号除法器，结果附加符号修正。有符号溢出（INT_MIN/-1）和除零按 RISC-V 规范处理。
//   倒计时由内部计数器驱动，与 IP 延迟严格对齐：MUL=3拍，DIV=34拍。
//   i_start 单拍脉冲启动；o_busy 期间 hazard_unit 冻结上游；o_done 单拍标记结果可采样。
//==============================================================================
`include "cpu_defines.svh"

module m_unit (
    input  logic                            i_clk,
    input  logic                            i_rst_n,
    input  logic                            i_start,
    input  logic                            i_flush,
    input  logic  [`DATA_BUS]               i_rs1,
    input  logic  [`DATA_BUS]               i_rs2,
    input  logic  [`M_OP_BUS]               i_m_op,

    output logic                            o_busy,
    output logic                            o_done,
    output logic  [`DATA_BUS]               o_res
);

    localparam int DIV_LATENCY = `DIV_LATENCY;     // 34
    localparam int CNT_W       = $clog2(DIV_LATENCY + 1);

    // ------------------------------------------------------------------ //
    // 计数器：倒计时驱动 busy/done                                          //
    // ------------------------------------------------------------------ //
    logic [CNT_W-1:0] cnt;
    logic [`M_OP_BUS] m_op_q;
    logic             start_pulse;
    logic [CNT_W-1:0] init_cnt;
    logic [`DATA_BUS] rs1_q;
    logic [`DATA_BUS] rs2_q;
    logic [`DATA_BUS] rs1_ip;
    logic [`DATA_BUS] rs2_ip;

    assign start_pulse = i_start && !o_busy;
    assign init_cnt    = CNT_W'(DIV_LATENCY);
    // 启动拍把当前 EX 操作数直送 IP，同时锁存；后续 stall 周期使用锁存值，
    // 避免前递源变化导致 MUL/DIV IP 吃到漂移的数据。
    assign rs1_ip      = start_pulse ? i_rs1 : rs1_q;
    assign rs2_ip      = start_pulse ? i_rs2 : rs2_q;

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            cnt    <= '0;
            o_busy <= 1'b0;
            o_done <= 1'b0;
            m_op_q <= '0;
            rs1_q  <= '0;
            rs2_q  <= '0;
        end else if (i_flush) begin
            cnt    <= '0;
            o_busy <= 1'b0;
            o_done <= 1'b0;
            rs1_q  <= '0;
            rs2_q  <= '0;
        end else if (start_pulse) begin
            cnt    <= init_cnt;
            o_busy <= 1'b1;
            o_done <= 1'b0;
            m_op_q <= i_m_op;
            rs1_q  <= i_rs1;
            rs2_q  <= i_rs2;
        end else if (o_busy) begin
            cnt <= cnt - 1'b1;
            if (cnt == CNT_W'(1)) begin
                o_busy <= 1'b0;
                o_done <= 1'b1;
            end
        end else begin
            o_done <= 1'b0;
        end
    end

    // ------------------------------------------------------------------ //
    // MUL 路径（3拍）：3 个 MUL_0 实例分别对应 ss / su / uu 符号组合             //
    // ------------------------------------------------------------------ //
    logic signed [65:0] mul_ss_p;   // signed × signed  → MUL, MULH
    logic signed [65:0] mul_su_p;   // signed × unsigned → MULHSU
    logic signed [65:0] mul_uu_p;   // unsigned × unsigned → MULHU

    MUL_0 u_mul_ss (
        .CLK (i_clk),
        .A   ({rs1_ip[31], rs1_ip}),     // 符号扩展
        .B   ({rs2_ip[31], rs2_ip}),
        .P   (mul_ss_p)
    );

    MUL_0 u_mul_su (
        .CLK (i_clk),
        .A   ({rs1_ip[31], rs1_ip}),     // 符号扩展 rs1
        .B   ({1'b0,       rs2_ip}),     // 零扩展 rs2
        .P   (mul_su_p)
    );

    MUL_0 u_mul_uu (
        .CLK (i_clk),
        .A   ({1'b0, rs1_ip}),          // 零扩展
        .B   ({1'b0, rs2_ip}),
        .P   (mul_uu_p)
    );

    // ------------------------------------------------------------------ //
    // DIV 路径（34拍）：DIV_0 仅支持无符号，需预处理和符号修正                     //
    // ------------------------------------------------------------------ //

    // ---- 特殊情况检测（组合，在 start 拍有效）----
    logic        is_div_signed;
    logic        div_by_zero;
    logic        signed_overflow;  // INT_MIN / -1，仅 DIV/REM

    assign is_div_signed   = (i_m_op == `M_DIV) || (i_m_op == `M_REM);
    assign div_by_zero     = (rs2_ip == 32'h0);
    assign signed_overflow = is_div_signed && (rs1_ip == 32'h8000_0000) && (rs2_ip == 32'hFFFF_FFFF);

    // ---- 绝对值（仅有符号时使用）----
    logic [31:0] rs1_abs, rs2_abs;
    assign rs1_abs = rs1_ip[31] ? (~rs1_ip + 1'b1) : rs1_ip;
    assign rs2_abs = rs2_ip[31] ? (~rs2_ip + 1'b1) : rs2_ip;

    // ---- 送入 DIV_0 的操作数（start 拍组合驱动，仅 start_pulse && is_div 时 valid）----
    logic [31:0] div_in_dividend, div_in_divisor;
    assign div_in_dividend = is_div_signed ? rs1_abs : rs1_ip;
    assign div_in_divisor  = is_div_signed ? rs2_abs : rs2_ip;

    // ---- start 拍的符号/特殊情况状态锁存（供34拍后修正用）----
    logic        sign_rs1_q, sign_rs2_q;
    logic        is_div_signed_q;
    logic        div_by_zero_q;
    logic        signed_overflow_q;
    logic [31:0] orig_rs1_q;        // 用于除零时 REM 返回被除数

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            sign_rs1_q       <= 1'b0;
            sign_rs2_q       <= 1'b0;
            is_div_signed_q  <= 1'b0;
            div_by_zero_q    <= 1'b0;
            signed_overflow_q<= 1'b0;
            orig_rs1_q       <= '0;
        end else if (start_pulse && i_m_op[2]) begin
            sign_rs1_q       <= rs1_ip[31];
            sign_rs2_q       <= rs2_ip[31];
            is_div_signed_q  <= is_div_signed;
            div_by_zero_q    <= div_by_zero;
            signed_overflow_q<= signed_overflow;
            orig_rs1_q       <= rs1_ip;
        end
    end

    // ---- DIV_0 实例（AXI-Stream，34拍，仅在 start_pulse && div 时 valid）----
    logic        div_tvalid;
    logic [63:0] div_raw;    // {quotient[63:32], remainder[31:0]}

    assign div_tvalid = start_pulse && i_m_op[2];

    DIV_0 u_div (
        .aclk                   (i_clk),
        .s_axis_dividend_tvalid (div_tvalid),
        .s_axis_dividend_tready (/* unused */),
        .s_axis_dividend_tdata  (div_in_dividend),
        .s_axis_divisor_tvalid  (div_tvalid),
        .s_axis_divisor_tready  (/* unused */),
        .s_axis_divisor_tdata   (div_in_divisor),
        .m_axis_dout_tvalid     (/* unused */),
        .m_axis_dout_tdata      (div_raw)
    );

    // ---- 符号修正（组合，o_done 拍时 div_raw 稳定）----
    logic [31:0] quot_raw, rem_raw;
    // Restored legacy DIV_0 packs m_axis_dout_tdata as {quotient, remainder}.
    assign quot_raw = div_raw[63:32];
    assign rem_raw  = div_raw[31:0];

    logic [31:0] quot_corrected, rem_corrected;

    always_comb begin
        if (div_by_zero_q) begin
            // 除零：商 = -1(0xFFFF_FFFF)，余数 = 被除数原值
            quot_corrected = 32'hFFFF_FFFF;
            rem_corrected  = orig_rs1_q;
        end else if (signed_overflow_q) begin
            // 有符号溢出（INT_MIN / -1）：商 = INT_MIN，余数 = 0
            quot_corrected = 32'h8000_0000;
            rem_corrected  = 32'h0;
        end else if (is_div_signed_q) begin
            // 普通有符号：若操作数符号不同则商取负；余数符号跟被除数
            quot_corrected = (sign_rs1_q ^ sign_rs2_q) ? (~quot_raw + 1'b1) : quot_raw;
            rem_corrected  = sign_rs1_q                ? (~rem_raw  + 1'b1) : rem_raw;
        end else begin
            // 无符号：直接用原值
            quot_corrected = quot_raw;
            rem_corrected  = rem_raw;
        end
    end

    // ------------------------------------------------------------------ //
    // 结果选择（o_done 拍有效）                                              //
    // ------------------------------------------------------------------ //
    always_comb begin
        unique case (m_op_q)
            `M_DIV   : o_res = quot_corrected;
            `M_DIVU  : o_res = quot_corrected;
            `M_REM   : o_res = rem_corrected;
            `M_REMU  : o_res = rem_corrected;
            default  : o_res = '0;
        endcase
    end

endmodule
