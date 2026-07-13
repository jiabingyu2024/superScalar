`timescale 1ns / 1ps
// DCache tag/valid storage with an inference pattern that maps cleanly to a
// simple dual-port Xilinx block RAM.  Keeping initialization/refill policy in
// dcache.sv and presenting one physical write port here avoids the multi-address
// write cone that previously forced the 2Kx18 array into distributed RAM.
module dcache_tag_bank #(
    parameter int unsigned LINE_COUNT = core_config_pkg::DCACHE_LINES,
    parameter int unsigned TAG_WIDTH  = 18
) (
    input  logic clk,
    input  logic read_en_i,
    input  logic [$clog2(LINE_COUNT)-1:0] read_index_i,
    output logic [TAG_WIDTH-1:0] read_data_o,
    input  logic write_en_i,
    input  logic [$clog2(LINE_COUNT)-1:0] write_index_i,
    input  logic [TAG_WIDTH-1:0] write_data_i
);
    (* ram_style = "block" *) logic [TAG_WIDTH-1:0] mem_q [0:LINE_COUNT-1];

    always_ff @(posedge clk) begin
        if (write_en_i) mem_q[write_index_i] <= write_data_i;
        if (read_en_i) read_data_o <= mem_q[read_index_i];
    end
endmodule
