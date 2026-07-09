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
    logic [FETCH_WIDTH-1:0][PKT_WIDTH-1:0] push_data;
    logic [DECODE_WIDTH-1:0][PKT_WIDTH-1:0] pop_data;

    always_comb begin
        for (int i = 0; i < FETCH_WIDTH; i = i + 1) begin
            push_data[i] = push_pkt_i[i];
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
        .push_valid_i(push_valid_i),
        .push_data_i(push_data),
        .push_ready_o(push_ready_o),
        .pop_ready_i(pop_ready_i),
        .pop_valid_o(pop_valid_o),
        .pop_data_o(pop_data),
        .count_o()
    );
endmodule : CoreFetchBuffer
