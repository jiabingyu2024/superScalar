import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreDispatchUnit #(
    parameter int DEPTH = 4,
    parameter int INDEX_BITS = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int COUNT_BITS = $clog2(DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  logic [DISPATCH_WIDTH-1:0] in_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] in_uop_i,
    output logic [DISPATCH_WIDTH-1:0] in_ready_o,

    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,

    output logic [DISPATCH_WIDTH-1:0] int_valid_o,
    output logic [DISPATCH_WIDTH-1:0] mem_valid_o,
    output logic [DISPATCH_WIDTH-1:0] mul_valid_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] int_uop_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] mem_uop_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] mul_uop_o,

    input  logic [DISPATCH_WIDTH-1:0] int_ready_i,
    input  logic [DISPATCH_WIDTH-1:0] mem_ready_i,
    input  logic [DISPATCH_WIDTH-1:0] mul_ready_i
);
    localparam logic [COUNT_BITS-1:0] DEPTH_COUNT = COUNT_BITS'(DEPTH);

    CoreRenamedUop entry_q [DEPTH-1:0];
    CoreRenamedUop ready_entry [DEPTH-1:0];
    CoreRenamedUop next_entry [DEPTH-1:0];
    logic [COUNT_BITS-1:0] count_q;
    logic [COUNT_BITS-1:0] next_count;
    logic [COUNT_BITS-1:0] pop_count;
    logic [DISPATCH_WIDTH-1:0] push_fire;
    logic [DISPATCH_WIDTH-1:0] pop_fire;
    logic [DISPATCH_WIDTH-1:0] lane_ready;
    logic prefix_accepted;

    function automatic logic src_ready_after_wakeup(
        input PhyRegNumPath src,
        input logic src_ready
    );
        logic ready;
        begin
            ready = (src == '0) || src_ready;
            for (int w = 0; w < ISSUE_WIDTH; w = w + 1) begin
                if (wakeup_valid_i[w] && (wakeup_phy_i[w] == src)) begin
                    ready = 1'b1;
                end
            end
            src_ready_after_wakeup = ready;
        end
    endfunction

    // Allocation sees only registered local occupancy. In particular, do not
    // include same-cycle IQ pops in ready: doing so would reconnect IQ ready
    // through dispatch into rename/free-list/ROB allocation.
    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            in_ready_o[i] = !clear_i &&
                ((count_q + COUNT_BITS'(i)) < DEPTH_COUNT);
            push_fire[i] = in_valid_i[i] && in_ready_o[i];
        end
    end

    // Wakeups are accumulated while an allocated uop waits in this buffer.
    // Without this step, a completion that occurs before IQ insertion would
    // be lost and the consumer could remain permanently not-ready.
    always_comb begin
        for (int e = 0; e < DEPTH; e = e + 1) begin
            ready_entry[e] = entry_q[e];
            ready_entry[e].src1_ready = src_ready_after_wakeup(
                entry_q[e].prs1, entry_q[e].src1_ready
            );
            ready_entry[e].src2_ready = src_ready_after_wakeup(
                entry_q[e].prs2, entry_q[e].src2_ready
            );
        end
    end

    // Offer the two oldest uops in order. Lane 1 is visible only after lane 0
    // is accepted, preserving the backend's two-wide prefix contract even
    // when the lanes target different issue queues.
    always_comb begin
        pop_count = '0;
        prefix_accepted = 1'b1;
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            int_valid_o[i] = 1'b0;
            mem_valid_o[i] = 1'b0;
            mul_valid_o[i] = 1'b0;
            int_uop_o[i] = ready_entry[i];
            mem_uop_o[i] = ready_entry[i];
            mul_uop_o[i] = ready_entry[i];

            unique case (ready_entry[i].uop.tube)
                TUBE_TYPE_MEM: lane_ready[i] = mem_ready_i[i];
                TUBE_TYPE_MUL: lane_ready[i] = mul_ready_i[i];
                default:       lane_ready[i] = int_ready_i[i];
            endcase

            pop_fire[i] = !clear_i && prefix_accepted &&
                          (count_q > COUNT_BITS'(i)) && lane_ready[i];
            if (!clear_i && prefix_accepted &&
                (count_q > COUNT_BITS'(i))) begin
                unique case (ready_entry[i].uop.tube)
                    TUBE_TYPE_MEM: mem_valid_o[i] = 1'b1;
                    TUBE_TYPE_MUL: mul_valid_o[i] = 1'b1;
                    default:       int_valid_o[i] = 1'b1;
                endcase
            end

            if (pop_fire[i]) begin
                pop_count = pop_count + 1'b1;
            end
            prefix_accepted = prefix_accepted && pop_fire[i];
        end
    end

    always_comb begin
        next_count = '0;
        for (int e = 0; e < DEPTH; e = e + 1) begin
            next_entry[e] = '0;
        end

        for (int e = 0; e < DEPTH; e = e + 1) begin
            if ((COUNT_BITS'(e) >= pop_count) &&
                (COUNT_BITS'(e) < count_q)) begin
                next_entry[next_count[INDEX_BITS-1:0]] = ready_entry[e];
                next_count = next_count + 1'b1;
            end
        end

        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            if (push_fire[i]) begin
                next_entry[next_count[INDEX_BITS-1:0]] = in_uop_i[i];
                next_entry[next_count[INDEX_BITS-1:0]].src1_ready =
                    src_ready_after_wakeup(
                        in_uop_i[i].prs1, in_uop_i[i].src1_ready
                    );
                next_entry[next_count[INDEX_BITS-1:0]].src2_ready =
                    src_ready_after_wakeup(
                        in_uop_i[i].prs2, in_uop_i[i].src2_ready
                    );
                next_count = next_count + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count_q <= '0;
        end else if (clear_i) begin
            count_q <= '0;
        end else begin
            count_q <= next_count;
        end
    end

    // count_q owns visibility; invalid payload never reaches an IQ. Keeping
    // the wide uop array reset-free avoids a large asynchronous control set.
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            for (int e = 0; e < DEPTH; e = e + 1) begin
                entry_q[e] <= next_entry[e];
            end
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            assert (count_q <= DEPTH_COUNT)
                else $error("allocated dispatch buffer overflow");
            assert (!(pop_fire[1] && !pop_fire[0]))
                else $error("allocated dispatch violated lane prefix");
        end
    end
`endif
endmodule : CoreDispatchUnit
