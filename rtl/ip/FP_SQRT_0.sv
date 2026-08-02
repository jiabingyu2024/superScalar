`timescale 1ns / 1ps

// Simulation model for the single-precision square-root Floating-Point Operator.
module FP_SQRT_0 (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        s_axis_a_tvalid,
    input  logic [31:0] s_axis_a_tdata,
    output logic        m_axis_result_tvalid,
    output logic [31:0] m_axis_result_tdata
);
    localparam int LATENCY = 28;

    import "DPI-C" function int unsigned rv32f_dpi_sqrt(
        input int unsigned a
    );

    logic [31:0] data_pipe [0:LATENCY-1];
    logic        valid_pipe [0:LATENCY-1];

    assign m_axis_result_tdata  = data_pipe[LATENCY-1];
    assign m_axis_result_tvalid = valid_pipe[LATENCY-1];

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i < LATENCY; i++) begin
                data_pipe[i]  <= '0;
                valid_pipe[i] <= 1'b0;
            end
        end else begin
            data_pipe[0]  <= rv32f_dpi_sqrt(s_axis_a_tdata);
            valid_pipe[0] <= s_axis_a_tvalid;
            for (int i = 1; i < LATENCY; i++) begin
                data_pipe[i]  <= data_pipe[i-1];
                valid_pipe[i] <= valid_pipe[i-1];
            end
        end
    end
endmodule
