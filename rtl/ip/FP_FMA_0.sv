`timescale 1ns / 1ps

// Simulation model for the same-name Xilinx Floating-Point Operator generated
// by fpga/create_vivado_project.tcl.  The RTL core only sees this AXI-stream
// contract; this file is never added to Vivado sources.
module FP_FMA_0 (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        s_axis_a_tvalid,
    input  logic [31:0] s_axis_a_tdata,
    input  logic        s_axis_b_tvalid,
    input  logic [31:0] s_axis_b_tdata,
    input  logic        s_axis_c_tvalid,
    input  logic [31:0] s_axis_c_tdata,
    output logic        m_axis_result_tvalid,
    output logic [31:0] m_axis_result_tdata
);
    localparam int LATENCY = 19;

    import "DPI-C" function int unsigned rv32f_dpi_fma(
        input int unsigned a,
        input int unsigned b,
        input int unsigned c
    );

    logic [31:0] data_pipe [0:LATENCY-1];
    logic        valid_pipe [0:LATENCY-1];
    logic        fire;

    assign fire = s_axis_a_tvalid && s_axis_b_tvalid && s_axis_c_tvalid;
    assign m_axis_result_tdata  = data_pipe[LATENCY-1];
    assign m_axis_result_tvalid = valid_pipe[LATENCY-1];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i < LATENCY; i++) begin
                data_pipe[i]  <= '0;
                valid_pipe[i] <= 1'b0;
            end
        end else begin
            data_pipe[0]  <= rv32f_dpi_fma(s_axis_a_tdata,
                                           s_axis_b_tdata,
                                           s_axis_c_tdata);
            valid_pipe[0] <= fire;
            for (int i = 1; i < LATENCY; i++) begin
                data_pipe[i]  <= data_pipe[i-1];
                valid_pipe[i] <= valid_pipe[i-1];
            end
        end
    end
endmodule
