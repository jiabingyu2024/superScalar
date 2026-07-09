`timescale 1ns / 1ps

/**
 * @module MUL_0
 * @description Behavioral replacement for the Vivado mult_gen IP used by FPGA.
 *              Signed 33x33 multiplier with a three-cycle registered latency.
 *              The port names intentionally match the generated IP wrapper.
 */
module MUL_0 (
    input  logic                CLK,
    input  logic signed [32:0]  A,
    input  logic signed [32:0]  B,
    output logic signed [65:0]  P
);
    logic signed [65:0] pipe0;
    logic signed [65:0] pipe1;

    always_ff @(posedge CLK) begin
        pipe0 <= A * B;
        pipe1 <= pipe0;
        P <= pipe1;
    end

endmodule
