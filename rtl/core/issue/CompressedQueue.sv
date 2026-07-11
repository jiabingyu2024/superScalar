import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreCompressedQueue #(
    parameter int DEPTH = INT_IQ_DEPTH,
    parameter int ISSUE_PORTS = 1,
    parameter bit HEAD_ONLY = 1'b0,
    parameter int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int COUNT_WIDTH = $clog2(DEPTH + DISPATCH_WIDTH + ISSUE_PORTS + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  logic [DISPATCH_WIDTH-1:0] push_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] push_uop_i,
    output logic [DISPATCH_WIDTH-1:0] push_ready_o,

    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,

    input  logic [ISSUE_PORTS-1:0] issue_ready_i,
    output logic [ISSUE_PORTS-1:0] issue_valid_o,
    output CoreRenamedUop [ISSUE_PORTS-1:0] issue_uop_o,

    output logic empty_o,
    output logic full_o,
    output logic head_not_ready_o,
    output logic younger_ready_behind_head_o
);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);

    CoreRenamedUop entry_q [DEPTH-1:0];
    CoreRenamedUop ready_entry [DEPTH-1:0];
    CoreRenamedUop next_entry [DEPTH-1:0];
    logic [DEPTH-1:0] valid_q;
    logic [DEPTH-1:0] next_valid;
    logic [DEPTH-1:0] selected_mask;
    logic [ISSUE_PORTS-1:0][DEPTH-1:0] port_selected_mask;
    logic [DEPTH-1:0] issue_remove;

    logic [COUNT_WIDTH-1:0] count_q;
    logic [COUNT_WIDTH-1:0] issue_count;
    logic [COUNT_WIDTH-1:0] next_count;
    logic [DISPATCH_WIDTH-1:0] push_fire;
    logic [ISSUE_PORTS-1:0] issue_fire;

    function automatic logic src_ready_after_wakeup(
        input PhyRegNumPath src,
        input logic src_ready
    );
        logic hit;
        begin
            hit = (src == '0) || src_ready;
            for (int w = 0; w < ISSUE_WIDTH; w = w + 1) begin
                if (wakeup_valid_i[w] && (wakeup_phy_i[w] == src)) begin
                    hit = 1'b1;
                end
            end
            src_ready_after_wakeup = hit;
        end
    endfunction

    // Wakeup and age-based selection are independent of the consumer ready
    // signals.  Keeping the valid side of the interface independent avoids a
    // ready-to-valid feedback path through the execution cluster.
    always_comb begin
        for (int e = 0; e < DEPTH; e = e + 1) begin
            ready_entry[e] = entry_q[e];
            ready_entry[e].src1_ready = src_ready_after_wakeup(entry_q[e].prs1, entry_q[e].src1_ready);
            ready_entry[e].src2_ready = src_ready_after_wakeup(entry_q[e].prs2, entry_q[e].src2_ready);
        end

        selected_mask = '0;
        port_selected_mask = '0;
        for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
            issue_valid_o[p] = 1'b0;
            issue_uop_o[p] = '0;
            if (HEAD_ONLY) begin
                if ((p == 0) && valid_q[0] && ready_entry[0].src1_ready && ready_entry[0].src2_ready) begin
                    issue_valid_o[p] = 1'b1;
                    issue_uop_o[p] = ready_entry[0];
                    selected_mask[0] = 1'b1;
                    port_selected_mask[p][0] = 1'b1;
                end
            end else begin
                for (int e = 0; e < DEPTH; e = e + 1) begin
                    if (!issue_valid_o[p] &&
                        valid_q[e] &&
                        !selected_mask[e] &&
                        ready_entry[e].src1_ready &&
                        ready_entry[e].src2_ready) begin
                        issue_valid_o[p] = 1'b1;
                        issue_uop_o[p] = ready_entry[e];
                        selected_mask[e] = 1'b1;
                        port_selected_mask[p][e] = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        issue_count = '0;
        for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
            issue_fire[p] = issue_valid_o[p] && issue_ready_i[p];
            if (issue_fire[p]) begin
                issue_count = issue_count + 1'b1;
            end
        end

        for (int e = 0; e < DEPTH; e = e + 1) begin
            issue_remove[e] = 1'b0;
            for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
                if (issue_fire[p] && port_selected_mask[p][e]) begin
                    issue_remove[e] = 1'b1;
                end
            end
        end
    end

    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            push_ready_o[i] = ((count_q - issue_count + COUNT_WIDTH'(i)) < DEPTH_COUNT);
            push_fire[i] = push_valid_i[i] && push_ready_o[i];
        end
    end

    always_comb begin
        next_valid = '0;
        for (int n = 0; n < DEPTH; n = n + 1) begin
            next_entry[n] = '0;
        end
        next_count = '0;
        for (int e = 0; e < DEPTH; e = e + 1) begin
            if (valid_q[e] && !issue_remove[e]) begin
                next_entry[next_count[PTR_WIDTH-1:0]] = ready_entry[e];
                next_valid[next_count[PTR_WIDTH-1:0]] = 1'b1;
                next_count = next_count + 1'b1;
            end
        end
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            if (push_fire[i]) begin
                next_entry[next_count[PTR_WIDTH-1:0]] = push_uop_i[i];
                next_entry[next_count[PTR_WIDTH-1:0]].valid = 1'b1;
                next_entry[next_count[PTR_WIDTH-1:0]].src1_ready =
                    src_ready_after_wakeup(push_uop_i[i].prs1, push_uop_i[i].src1_ready);
                next_entry[next_count[PTR_WIDTH-1:0]].src2_ready =
                    src_ready_after_wakeup(push_uop_i[i].prs2, push_uop_i[i].src2_ready);
                next_valid[next_count[PTR_WIDTH-1:0]] = 1'b1;
                next_count = next_count + 1'b1;
            end
        end
    end

    assign empty_o = (count_q == '0);
    assign full_o = (count_q == DEPTH_COUNT);

    always_comb begin
        head_not_ready_o = valid_q[0] &&
                           !(ready_entry[0].src1_ready && ready_entry[0].src2_ready);
        younger_ready_behind_head_o = 1'b0;
        for (int e = 1; e < DEPTH; e = e + 1) begin
            if (valid_q[e] && ready_entry[e].src1_ready && ready_entry[e].src2_ready) begin
                younger_ready_behind_head_o = 1'b1;
            end
        end
    end

    // valid_q/count_q gate every read of entry_q. A push overwrites the full
    // uop, so clearing the payload array is unnecessary reset fanout on FPGA.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q <= '0;
            count_q <= '0;
        end else if (clear_i) begin
            valid_q <= '0;
            count_q <= '0;
        end else begin
            valid_q <= next_valid;
            count_q <= next_count;
            for (int i = 0; i < DEPTH; i = i + 1) begin
                entry_q[i] <= next_entry[i];
            end
        end
    end
endmodule : CoreCompressedQueue
