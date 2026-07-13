`timescale 1ns / 1ps
// One 32-bit word bank of the direct-mapped DCache.  The synchronous read and
// byte write enables match the native Xilinx block-RAM interface.
module dcache_data_bank #(
    parameter int unsigned LINE_COUNT = core_config_pkg::DCACHE_LINES
) (
    input  logic clk,
    input  logic read_en_i,
    input  logic [$clog2(LINE_COUNT)-1:0] read_index_i,
    output logic [31:0] read_data_o,
    input  logic write_en_i,
    input  logic [$clog2(LINE_COUNT)-1:0] write_index_i,
    input  logic [31:0] write_data_i,
    input  logic [3:0] write_mask_i
);
    (* ram_style = "block" *) logic [31:0] mem_q [0:LINE_COUNT-1];

    integer lane;
    always_ff @(posedge clk) begin
        if (write_en_i) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (write_mask_i[lane])
                    mem_q[write_index_i][lane*8 +: 8] <= write_data_i[lane*8 +: 8];
            end
        end
        if (read_en_i) read_data_o <= mem_q[read_index_i];
    end
endmodule
