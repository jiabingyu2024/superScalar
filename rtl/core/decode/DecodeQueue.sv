import CoreTypesPkg::*;

module CoreDecodeQueue (
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
    localparam int UOP_WIDTH = $bits(CoreDecodeUop);
    logic [UOP_WIDTH-1:0] pop_data;

    assign pop_uop_o = pop_data;

    logic full;
    logic empty;

    CoreSyncFifo #(
        .WIDTH(UOP_WIDTH),
        .DEPTH(8)
    ) u_fifo (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_i(push_valid_i && push_ready_o),
        .push_data_i(push_uop_i),
        .full_o(full),
        .pop_i(pop_ready_i && pop_valid_o),
        .pop_data_o(pop_data),
        .empty_o(empty),
        .count_o()
    );

    assign push_ready_o = !full;
    assign pop_valid_o = !empty;
endmodule : CoreDecodeQueue
