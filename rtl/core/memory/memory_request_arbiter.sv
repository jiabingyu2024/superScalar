`timescale 1ns / 1ps

module memory_request_arbiter #(
    parameter int unsigned STORE_DEPTH = core_config_pkg::STORE_BUFFER_DEPTH,
    parameter int unsigned STORE_CNT_W = $clog2(STORE_DEPTH + 1),
    parameter int unsigned LOAD_CNT_W = $clog2(core_config_pkg::LOAD_QUEUE_DEPTH + 1)
) (
    input  logic flush_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] commit_trans_id_i,
    input  core_types_pkg::store_entry_t store_entries_i [0:STORE_DEPTH-1],
    input  logic [STORE_DEPTH-1:0] store_committed_i,
    input  logic [core_config_pkg::STORE_ID_W-1:0] store_head_i,
    input  logic [STORE_CNT_W-1:0] store_count_i,
    input  logic [7:0] next_store_sequence_i,
    input  core_types_pkg::load_entry_t load_head_i,
    input  logic [LOAD_CNT_W-1:0] load_count_i,
    input  logic load_forward_complete_i,
    input  logic exec_load_valid_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] exec_trans_id_i,
    input  logic [31:0] exec_addr_i,

    output logic request_valid_o,
    output logic request_write_o,
    output logic [31:0] request_addr_o,
    output logic [31:0] request_wdata_o,
    output logic [3:0] request_wstrb_o,
    output logic request_uncached_o,
    output logic load_direct_candidate_o,
    output logic older_store_pending_o,
    output logic direct_older_store_pending_o
);
    import core_config_pkg::*;

    integer i;

    function automatic logic store_is_older(
        input logic [7:0] cutoff,
        input logic [7:0] seq_value
    );
        logic [7:0] delta;
        begin
            delta = cutoff - seq_value;
            store_is_older = delta != 0 && !delta[7];
        end
    endfunction

    function automatic logic addr_is_dram(input logic [31:0] addr);
        addr_is_dram = addr[31:18] == DRAM_START[31:18];
    endfunction

    always_comb begin
        older_store_pending_o = 1'b0;
        direct_older_store_pending_o = 1'b0;
        request_valid_o = 1'b0;
        request_write_o = 1'b0;
        request_addr_o = 32'd0;
        request_wdata_o = 32'd0;
        request_wstrb_o = 4'd0;
        request_uncached_o = 1'b0;

        if (load_count_i != 0) begin
            for (i = 0; i < STORE_DEPTH; i = i + 1) begin
                if (store_entries_i[i].valid &&
                    store_is_older(load_head_i.store_seq_cutoff,
                                   store_entries_i[i].store_seq))
                    older_store_pending_o = 1'b1;
            end
        end
        if (exec_load_valid_i) begin
            for (i = 0; i < STORE_DEPTH; i = i + 1) begin
                if (store_entries_i[i].valid &&
                    store_is_older(next_store_sequence_i,
                                   store_entries_i[i].store_seq))
                    direct_older_store_pending_o = 1'b1;
            end
        end

        load_direct_candidate_o = !flush_i && exec_load_valid_i && load_count_i == 0 &&
            (addr_is_dram(exec_addr_i) ||
             (!direct_older_store_pending_o && exec_trans_id_i == commit_trans_id_i));

        if (store_count_i != 0 && store_entries_i[store_head_i].valid &&
            store_committed_i[store_head_i]) begin
            request_valid_o = 1'b1;
            request_write_o = 1'b1;
            request_addr_o = store_entries_i[store_head_i].addr;
            request_wdata_o = store_entries_i[store_head_i].wdata;
            request_wstrb_o = store_entries_i[store_head_i].wstrb;
            request_uncached_o = store_entries_i[store_head_i].uncached;
        end else if (load_direct_candidate_o) begin
            request_valid_o = 1'b1;
            request_addr_o = exec_addr_i;
            request_uncached_o = !addr_is_dram(exec_addr_i);
        end else if (!flush_i && load_count_i != 0 && !load_forward_complete_i &&
                     (addr_is_dram(load_head_i.addr) ||
                      (!older_store_pending_o &&
                       load_head_i.trans_id == commit_trans_id_i))) begin
            request_valid_o = 1'b1;
            request_addr_o = load_head_i.addr;
            request_uncached_o = !addr_is_dram(load_head_i.addr);
        end
    end
endmodule
