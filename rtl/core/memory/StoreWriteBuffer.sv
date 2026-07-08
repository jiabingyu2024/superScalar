`timescale 1ns / 1ps

module StoreWriteBuffer #(
    parameter int unsigned DEPTH = 4
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        push_valid,
    output logic        push_ready,
    input  logic [31:0] push_addr,
    input  logic [31:0] push_wdata,
    input  logic [3:0]  push_wstrb,

    output logic        pop_valid,
    input  logic        pop_ready,
    output logic [31:0] pop_addr,
    output logic [31:0] pop_wdata,
    output logic [3:0]  pop_wstrb,

    input  logic        conflict_valid,
    input  logic [31:0] conflict_addr,
    output logic        conflict_hit,

    output logic        empty,
    output logic        full
);
    localparam int unsigned PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam int unsigned CNT_W = $clog2(DEPTH + 1);
    localparam logic [CNT_W-1:0] DEPTH_COUNT = DEPTH;

    logic [31:0] addr_q [0:DEPTH-1];
    logic [31:0] wdata_q [0:DEPTH-1];
    logic [3:0]  wstrb_q [0:DEPTH-1];
    logic [PTR_W-1:0] head_q;
    logic [PTR_W-1:0] tail_q;
    logic [CNT_W-1:0] count_q;

    logic push_fire;
    logic pop_fire;

    assign empty = (count_q == '0);
    assign full = (count_q == DEPTH_COUNT);
    assign push_ready = !full;
    assign pop_valid = !empty;
    assign pop_addr = addr_q[head_q];
    assign pop_wdata = wdata_q[head_q];
    assign pop_wstrb = wstrb_q[head_q];
    assign push_fire = push_valid && push_ready;
    assign pop_fire = pop_valid && pop_ready;

    always_comb begin
        conflict_hit = 1'b0;
        if (conflict_valid) begin
            for (int idx = 0; idx < DEPTH; idx++) begin
                if (idx < count_q) begin
                    logic [PTR_W-1:0] ptr;
                    ptr = head_q + PTR_W'(idx);
                    if (addr_q[ptr][31:2] == conflict_addr[31:2]) begin
                        conflict_hit = 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
        end else begin
            if (push_fire) begin
                addr_q[tail_q] <= push_addr;
                wdata_q[tail_q] <= push_wdata;
                wstrb_q[tail_q] <= push_wstrb;
                tail_q <= tail_q + {{(PTR_W-1){1'b0}}, 1'b1};
            end

            if (pop_fire) begin
                head_q <= head_q + {{(PTR_W-1){1'b0}}, 1'b1};
            end

            unique case ({push_fire, pop_fire})
                2'b10: count_q <= count_q + {{(CNT_W-1){1'b0}}, 1'b1};
                2'b01: count_q <= count_q - {{(CNT_W-1){1'b0}}, 1'b1};
                default: begin
                end
            endcase
        end
    end
endmodule
