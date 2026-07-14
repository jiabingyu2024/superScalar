`timescale 1ns / 1ps

module store_buffer #(
    parameter int unsigned DEPTH = core_config_pkg::STORE_BUFFER_DEPTH,
    parameter int unsigned CNT_W = $clog2(DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic enqueue_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] enqueue_trans_id_i,
    input  logic [31:0] enqueue_addr_i,
    input  logic [31:0] enqueue_wdata_i,
    input  core_types_pkg::mem_size_e enqueue_size_i,
    input  logic enqueue_uncached_i,

    input  logic commit_i,
    input  logic [core_config_pkg::STORE_ID_W-1:0] commit_slot_i,
    input  logic drain_i,

    output core_types_pkg::store_entry_t entries_o [0:DEPTH-1],
    output logic [DEPTH-1:0] committed_o,
    output logic [core_config_pkg::STORE_ID_W-1:0] head_o,
    output logic [core_config_pkg::STORE_ID_W-1:0] tail_o,
    output logic [CNT_W-1:0] count_o,
    output logic [7:0] next_sequence_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    integer i;
    integer committed_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            head_o <= '0;
            tail_o <= '0;
            count_o <= '0;
            committed_o <= '0;
            next_sequence_o <= '0;
            for (i = 0; i < DEPTH; i = i + 1) entries_o[i].valid <= 1'b0;
        end else if (flush_i) begin
            committed_count = 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                if (entries_o[i].valid && committed_o[i]) begin
                    committed_count = committed_count + 1;
                end else begin
                    entries_o[i].valid <= 1'b0;
                    committed_o[i] <= 1'b0;
                end
            end
            count_o <= CNT_W'(committed_count);
            tail_o <= head_o + STORE_ID_W'(committed_count);
        end else begin
            // Keep commit -> enqueue -> drain ordering identical to core_top.
            if (commit_i) committed_o[commit_slot_i] <= 1'b1;

            if (enqueue_i) begin
                entries_o[tail_o].valid <= 1'b1;
                committed_o[tail_o] <= 1'b0;
                entries_o[tail_o].trans_id <= enqueue_trans_id_i;
                entries_o[tail_o].store_seq <= next_sequence_o;
                entries_o[tail_o].addr <= enqueue_addr_i;
                entries_o[tail_o].wdata <= enqueue_wdata_i;
                unique case (enqueue_size_i)
                    MEM_BYTE: entries_o[tail_o].wstrb <= 4'b0001;
                    MEM_HALF: entries_o[tail_o].wstrb <= 4'b0011;
                    default: entries_o[tail_o].wstrb <= 4'b1111;
                endcase
                entries_o[tail_o].uncached <= enqueue_uncached_i;
                tail_o <= tail_o + 1'b1;
                next_sequence_o <= next_sequence_o + 1'b1;
            end

            if (drain_i) begin
                entries_o[head_o].valid <= 1'b0;
                committed_o[head_o] <= 1'b0;
                head_o <= head_o + 1'b1;
            end

            unique case ({enqueue_i, drain_i})
                2'b10: count_o <= count_o + 1'b1;
                2'b01: count_o <= count_o - 1'b1;
                default: begin end
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!rst) assert (count_o <= CNT_W'(DEPTH));
    end
`endif
endmodule
