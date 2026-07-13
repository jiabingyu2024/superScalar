`include "cpu_defines.svh"

// ID/AGU to cache-request register.  Memory operations use this slot;
// ordinary instructions use reg_id_c1 and the EX path instead.
module reg_id_ls (
    input  logic                  i_clk,
    input  logic                  i_rst_n,
    input  logic                  i_flush,
    input  logic                  i_hold,
    input  logic                  i_valid,
    input  logic [`DATA_BUS]      i_mem_addr,
    input  logic [`DATA_BUS]      i_store_data,
    input  logic [`DATA_BUS]      i_offset,
    input  logic                  i_addr_pending,
    input  logic [`RF_BUS]        i_addr_dep_rd,
    input  logic                  i_data_pending,
    input  logic [`RF_BUS]        i_data_dep_rd,
    input  logic                  i_resolve_addr,
    input  logic [`DATA_BUS]      i_resolved_addr,
    input  logic                  i_resolve_data,
    input  logic [`DATA_BUS]      i_resolved_data,
    input  logic [3:0]            i_mem_mask,
    input  logic                  i_load_unsigned,
    input  logic                  i_mem_read,
    input  logic                  i_mem_write,
    input  logic [`RF_BUS]        i_rd_addr,
    output logic                  o_valid,
    output logic [`DATA_BUS]      o_mem_addr,
    output logic [`DATA_BUS]      o_store_data,
    output logic [`DATA_BUS]      o_offset,
    output logic                  o_addr_pending,
    output logic [`RF_BUS]        o_addr_dep_rd,
    output logic                  o_data_pending,
    output logic [`RF_BUS]        o_data_dep_rd,
    output logic [3:0]            o_mem_mask,
    output logic                  o_load_unsigned,
    output logic                  o_mem_read,
    output logic                  o_mem_write,
    output logic [`RF_BUS]        o_rd_addr
);
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_valid         <= 1'b0;
            o_addr_pending  <= 1'b0;
            o_data_pending  <= 1'b0;
        end else if (i_flush) begin
            o_valid     <= 1'b0;
        end else if (i_hold) begin
            o_valid <= o_valid;
            if (i_resolve_addr) begin
                o_mem_addr     <= i_resolved_addr;
                o_addr_pending <= 1'b0;
            end
            if (i_resolve_data) begin
                o_store_data   <= i_resolved_data;
                o_data_pending <= 1'b0;
            end
        end else begin
            o_valid         <= i_valid;
            o_mem_addr      <= i_mem_addr;
            o_store_data    <= i_store_data;
            o_offset        <= i_offset;
            o_addr_pending  <= i_addr_pending;
            o_addr_dep_rd   <= i_addr_dep_rd;
            o_data_pending  <= i_data_pending;
            o_data_dep_rd   <= i_data_dep_rd;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
            o_mem_read      <= i_mem_read;
            o_mem_write     <= i_mem_write;
            o_rd_addr       <= i_rd_addr;
        end
    end
endmodule
