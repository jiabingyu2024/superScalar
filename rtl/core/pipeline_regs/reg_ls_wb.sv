`include "cpu_defines.svh"

// Metadata register for a load accepted by the cache request slot.
module reg_ls_wb (
    input  logic           i_clk,
    input  logic           i_rst_n,
    input  logic           i_valid,
    input  logic [`RF_BUS] i_rd_addr,
    input  logic [3:0]     i_mem_mask,
    input  logic           i_load_unsigned,
    output logic           o_valid,
    output logic [`RF_BUS] o_rd_addr,
    output logic [3:0]     o_mem_mask,
    output logic           o_load_unsigned
);
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_valid         <= 1'b0;
        end else begin
            o_valid         <= i_valid;
            o_rd_addr       <= i_rd_addr;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
        end
    end
endmodule
