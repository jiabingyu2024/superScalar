import CoreTypesPkg::*;

module CoreCompressedFifo (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic push_valid_i,
    input  CoreDecodeUop push_uop_i,
    output logic push_ready_o,
    input  logic pop_ready_i,
    output logic pop_valid_o,
    output CoreDecodeUop pop_uop_o
);
    CoreDecodeQueue u_queue (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_valid_i(push_valid_i),
        .push_uop_i(push_uop_i),
        .push_ready_o(push_ready_o),
        .pop_ready_i(pop_ready_i),
        .pop_valid_o(pop_valid_o),
        .pop_uop_o(pop_uop_o)
    );
endmodule : CoreCompressedFifo
