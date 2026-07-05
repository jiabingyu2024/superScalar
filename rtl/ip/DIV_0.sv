`timescale 1ns / 1ps

/**
 * @module DIV_0
 * @description Behavioral replacement for the Vivado div_gen IP used by FPGA.
 *              Unsigned 32/32 divider with remainder output and fixed 34-cycle
 *              registered latency. The output packing follows Divider Generator
 *              remainder mode for 32-bit operands:
 *              m_axis_dout_tdata[31:0]  = quotient
 *              m_axis_dout_tdata[63:32] = remainder
 */
module DIV_0 (
    input  logic        aclk,
    input  logic        s_axis_dividend_tvalid,
    output logic        s_axis_dividend_tready,
    input  logic [31:0] s_axis_dividend_tdata,
    input  logic        s_axis_divisor_tvalid,
    output logic        s_axis_divisor_tready,
    input  logic [31:0] s_axis_divisor_tdata,
    output logic        m_axis_dout_tvalid,
    output logic [63:0] m_axis_dout_tdata
);
    localparam int DIV_LATENCY = 34;

    logic [63:0] dataPipe [0:DIV_LATENCY-1];
    logic        validPipe [0:DIV_LATENCY-1];
    logic        fire;
    logic [31:0] quotient;
    logic [31:0] remainder;

    assign s_axis_dividend_tready = 1'b1;
    assign s_axis_divisor_tready = 1'b1;
    assign fire = s_axis_dividend_tvalid && s_axis_divisor_tvalid;

    always_comb begin
        if (s_axis_divisor_tdata == 32'd0) begin
            quotient = '0;
            remainder = '0;
        end else begin
            quotient = s_axis_dividend_tdata / s_axis_divisor_tdata;
            remainder = s_axis_dividend_tdata % s_axis_divisor_tdata;
        end
    end

    always_ff @(posedge aclk) begin
        dataPipe[0] <= {remainder, quotient};
        validPipe[0] <= fire;
        for (int i = 1; i < DIV_LATENCY; i++) begin
            dataPipe[i] <= dataPipe[i-1];
            validPipe[i] <= validPipe[i-1];
        end

        m_axis_dout_tdata <= dataPipe[DIV_LATENCY-1];
        m_axis_dout_tvalid <= validPipe[DIV_LATENCY-1];
    end

endmodule
