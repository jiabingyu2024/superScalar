`timescale 1ns / 1ps

module load_queue #(
    parameter int unsigned DEPTH = core_config_pkg::LOAD_QUEUE_DEPTH,
    parameter int unsigned CNT_W = $clog2(DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic flush_i,

    input  logic completion_i,
    input  logic forward_completion_i,
    input  logic direct_start_i,
    input  core_types_pkg::load_entry_t direct_meta_i,
    input  logic pop_i,
    input  logic memory_start_i,
    input  logic enqueue_i,
    input  core_types_pkg::load_entry_t enqueue_meta_i,

    output core_types_pkg::load_entry_t head_o,
    output logic [CNT_W-1:0] count_o,
    output logic active_o,
    output core_types_pkg::load_entry_t active_meta_o
);
    import core_types_pkg::*;

    localparam int unsigned INDEX_W = $clog2(DEPTH);
    load_entry_t entries_q [0:DEPTH-1];
    integer i;

    assign head_o = entries_q[0];

    always_ff @(posedge clk) begin
        if (rst) begin
            count_o <= '0;
            active_o <= 1'b0;
            active_meta_o <= '0;
            for (i = 0; i < DEPTH; i = i + 1) entries_q[i].valid <= 1'b0;
        end else if (flush_i) begin
            count_o <= '0;
            active_o <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1) entries_q[i].valid <= 1'b0;
        end else begin
            // A newly accepted request later in this block overrides a
            // completion that clears the previous active transaction.
            if (completion_i && !forward_completion_i) active_o <= 1'b0;

            if (direct_start_i) begin
                active_o <= 1'b1;
                active_meta_o <= direct_meta_i;
            end

            if (pop_i) begin
                if (memory_start_i) begin
                    active_o <= 1'b1;
                    active_meta_o <= entries_q[0];
                end
                for (i = 0; i < DEPTH - 1; i = i + 1)
                    entries_q[i] <= entries_q[i + 1];
                entries_q[DEPTH - 1].valid <= 1'b0;
            end

            if (enqueue_i) begin
                if (pop_i)
                    entries_q[INDEX_W'(count_o - 1'b1)] <= enqueue_meta_i;
                else
                    entries_q[INDEX_W'(count_o)] <= enqueue_meta_i;
            end

            unique case ({enqueue_i, pop_i})
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
