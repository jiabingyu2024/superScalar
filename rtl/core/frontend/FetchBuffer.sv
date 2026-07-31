import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreFetchBuffer (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic [FETCH_WIDTH-1:0] push_valid_i,
    input  CoreFetchPacket [FETCH_WIDTH-1:0] push_pkt_i,
    output logic [FETCH_WIDTH-1:0] push_ready_o,
    input  logic [DECODE_WIDTH-1:0] pop_ready_i,
    output logic [DECODE_WIDTH-1:0] pop_valid_o,
    output CoreFetchPacket [DECODE_WIDTH-1:0] pop_pkt_o
);
    localparam int PKT_WIDTH = $bits(CoreFetchPacket);
    localparam int FIFO_COUNT_WIDTH = $clog2(FETCH_BUF_DEPTH) + 1;
    logic [FETCH_WIDTH-1:0][PKT_WIDTH-1:0] push_data;
    logic [FETCH_WIDTH-1:0] fifo_push_valid;
    logic [FETCH_WIDTH-1:0] fifo_push_ready;
    logic [DECODE_WIDTH-1:0][PKT_WIDTH-1:0] pop_data;
    logic [FIFO_COUNT_WIDTH-1:0] fifo_count;
    logic push_all_ready;

    always_comb begin
        push_all_ready = (fifo_count <= FIFO_COUNT_WIDTH'(FETCH_BUF_DEPTH - FETCH_WIDTH));
        for (int i = 0; i < FETCH_WIDTH; i = i + 1) begin
            push_data[i] = push_pkt_i[i];
            fifo_push_valid[i] = push_valid_i[i] && push_all_ready;
            push_ready_o[i] = push_all_ready;
        end
        for (int j = 0; j < DECODE_WIDTH; j = j + 1) begin
            pop_pkt_o[j] = pop_data[j];
        end
    end

    CoreMultiPushFifo #(
        .WIDTH(PKT_WIDTH),
        .DEPTH(FETCH_BUF_DEPTH),
        .PUSH_WIDTH(FETCH_WIDTH),
        .POP_WIDTH(DECODE_WIDTH)
    ) u_fifo (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_valid_i(fifo_push_valid),
        .push_data_i(push_data),
        .push_ready_o(fifo_push_ready),
        .pop_ready_i(pop_ready_i),
        .pop_valid_o(pop_valid_o),
        .pop_data_o(pop_data),
        .count_o(fifo_count)
    );

    logic unused_fifo_ready;
    assign unused_fifo_ready = |fifo_push_ready;
endmodule : CoreFetchBuffer
