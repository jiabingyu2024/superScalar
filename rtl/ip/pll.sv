`timescale 1ns / 1ps

/**
 * @module pll
 * @description IP-compatible soft PLL replacement.
 *              Uses differential clock positive pin as source and generates
 *              two divided clocks plus a delayed `locked` signal.
 *              This module is intended for simulation/portable synthesis fallback.
 */
module pll #(
    parameter int unsigned DIV_OUT1 = 2,
    parameter int unsigned DIV_OUT2 = 4,
    parameter int unsigned LOCK_CYCLES = 32
) (
    input  logic clk_in1_p,
    input  logic clk_in1_n,
    output logic clk_out1,
    output logic clk_out2,
    output logic locked
);
    logic src_clk;
    int unsigned div1_cnt;
    int unsigned div2_cnt;
    int unsigned lock_cnt;

    // Keep interface-compatible with differential input; use p-side in soft model.
    assign src_clk = clk_in1_p;
    logic unused_clk_in1_n;
    assign unused_clk_in1_n = clk_in1_n;

    initial begin
        clk_out1 = 1'b0;
        clk_out2 = 1'b0;
        div1_cnt = 0;
        div2_cnt = 0;
        lock_cnt = 0;
        locked = 1'b0;
    end

    always_ff @(posedge src_clk) begin
        if (div1_cnt == (DIV_OUT1/2 - 1)) begin
            div1_cnt  <= 0;
            clk_out1  <= ~clk_out1;
        end else begin
            div1_cnt <= div1_cnt + 1;
        end

        if (div2_cnt == (DIV_OUT2/2 - 1)) begin
            div2_cnt  <= 0;
            clk_out2  <= ~clk_out2;
        end else begin
            div2_cnt <= div2_cnt + 1;
        end

        if (lock_cnt < LOCK_CYCLES) begin
            lock_cnt <= lock_cnt + 1;
            locked   <= 1'b0;
        end else begin
            locked   <= 1'b1;
        end
    end

endmodule
