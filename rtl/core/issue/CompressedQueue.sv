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
    output logic [COUNT_WIDTH-1:0] count_o,
    output logic head_not_ready_o,
    output logic younger_ready_behind_head_o
);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);
    localparam int AGE_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    CoreRenamedUop entry_q [DEPTH-1:0];
    CoreRenamedUop ready_entry [DEPTH-1:0];
    logic [DEPTH-1:0] valid_q;
    logic [AGE_WIDTH-1:0] age_q [DEPTH-1:0];
    logic [DEPTH-1:0] selected_mask;
    logic [ISSUE_PORTS-1:0][DEPTH-1:0] port_selected_mask;
    logic [DEPTH-1:0] issue_remove;
    logic [DEPTH-1:0] free_mask;
    logic [AGE_WIDTH-1:0] selected_age [ISSUE_PORTS-1:0];
    logic [AGE_WIDTH-1:0] push_slot [DISPATCH_WIDTH-1:0];
    logic [COUNT_WIDTH-1:0] push_rank [DISPATCH_WIDTH-1:0];

    logic [COUNT_WIDTH-1:0] count_q;
    logic [COUNT_WIDTH-1:0] issue_count;
    logic [COUNT_WIDTH-1:0] push_count;
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

    // Payload remains in a stable physical slot for its whole queue lifetime.
    // Selection compares only valid/ready/age; no wide uop is compacted after
    // an issue. This keeps scheduler activity local to narrow metadata.
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
            selected_age[p] = '1;
            if (HEAD_ONLY) begin
                if (p == 0) begin
                    for (int e = 0; e < DEPTH; e = e + 1) begin
                        if (valid_q[e] && (age_q[e] == '0) &&
                            ready_entry[e].src1_ready &&
                            ready_entry[e].src2_ready) begin
                            issue_valid_o[p] = 1'b1;
                            issue_uop_o[p] = ready_entry[e];
                            selected_age[p] = age_q[e];
                            selected_mask[e] = 1'b1;
                            port_selected_mask[p][e] = 1'b1;
                        end
                    end
                end
            end else begin
                for (int e = 0; e < DEPTH; e = e + 1) begin
                    if (valid_q[e] &&
                        !selected_mask[e] &&
                        ready_entry[e].src1_ready &&
                        ready_entry[e].src2_ready &&
                        (!issue_valid_o[p] ||
                         (age_q[e] < selected_age[p]))) begin
                        issue_valid_o[p] = 1'b1;
                        issue_uop_o[p] = ready_entry[e];
                        selected_age[p] = age_q[e];
                        port_selected_mask[p] = '0;
                        port_selected_mask[p][e] = 1'b1;
                    end
                end
                selected_mask |= port_selected_mask[p];
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

    // Reserve physical holes independently of push valid. This preserves the
    // queue's ready contract and permits same-cycle remove/replacement without
    // feeding dispatch valid back into dispatch ready.
    always_comb begin
        free_mask = ~valid_q | issue_remove;
        push_ready_o = '0;
        push_slot = '{default:'0};
        for (int p = 0; p < DISPATCH_WIDTH; p = p + 1) begin
            for (int e = 0; e < DEPTH; e = e + 1) begin
                if (!push_ready_o[p] && free_mask[e]) begin
                    push_ready_o[p] = 1'b1;
                    push_slot[p] = AGE_WIDTH'(e);
                    free_mask[e] = 1'b0;
                end
            end
        end
    end

    always_comb begin
        push_count = '0;
        push_fire = '0;
        push_rank = '{default:'0};
        for (int p = 0; p < DISPATCH_WIDTH; p = p + 1) begin
            push_fire[p] = push_valid_i[p] && push_ready_o[p];
            push_rank[p] = push_count;
            if (push_fire[p]) begin
                push_count = push_count + 1'b1;
            end
        end
    end

    assign empty_o = (count_q == '0);
    assign full_o = (count_q == DEPTH_COUNT);
    assign count_o = count_q;

    always_comb begin
        head_not_ready_o = 1'b0;
        younger_ready_behind_head_o = 1'b0;
        for (int e = 0; e < DEPTH; e = e + 1) begin
            if (valid_q[e] && (age_q[e] == '0)) begin
                head_not_ready_o = !(ready_entry[e].src1_ready &&
                                     ready_entry[e].src2_ready);
            end
            if (valid_q[e] && (age_q[e] != '0) &&
                ready_entry[e].src1_ready && ready_entry[e].src2_ready) begin
                younger_ready_behind_head_o = 1'b1;
            end
        end
    end

    // valid_q/count_q own reset and visibility. Keep them in the asynchronous
    // reset block, but do not place the wide payload array in that process:
    // an async-reset event with no payload assignment is otherwise synthesized
    // into unnecessary control-set/S-pin logic on FPGA.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q <= '0;
            count_q <= '0;
        end else if (clear_i) begin
            valid_q <= '0;
            count_q <= '0;
        end else begin
            valid_q <= valid_q & ~issue_remove;
            count_q <= count_q - issue_count + push_count;

            for (int e = 0; e < DEPTH; e = e + 1) begin
                if (valid_q[e] && !issue_remove[e]) begin
                    logic [COUNT_WIDTH-1:0] removed_before;
                    removed_before = '0;
                    for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
                        if (issue_fire[p] &&
                            (selected_age[p] < age_q[e])) begin
                            removed_before = removed_before + 1'b1;
                        end
                    end
                    age_q[e] <= age_q[e] - AGE_WIDTH'(removed_before);
                end
            end
            for (int p = 0; p < DISPATCH_WIDTH; p = p + 1) begin
                if (push_fire[p]) begin
                    valid_q[push_slot[p]] <= 1'b1;
                    age_q[push_slot[p]] <= AGE_WIDTH'(
                        count_q - issue_count + push_rank[p]
                    );
                end
            end
        end
    end

    // Wakeups update only two slot-local ready bits. A push overwrites exactly
    // one free physical slot; the wide payload never shifts between entries.
    always_ff @(posedge clk) begin
        for (int e = 0; e < DEPTH; e = e + 1) begin
            if (valid_q[e]) begin
                entry_q[e].src1_ready <= ready_entry[e].src1_ready;
                entry_q[e].src2_ready <= ready_entry[e].src2_ready;
            end
        end
        for (int p = 0; p < DISPATCH_WIDTH; p = p + 1) begin
            if (push_fire[p]) begin
                entry_q[push_slot[p]] <= push_uop_i[p];
                entry_q[push_slot[p]].valid <= 1'b1;
                entry_q[push_slot[p]].src1_ready <=
                    src_ready_after_wakeup(push_uop_i[p].prs1,
                                           push_uop_i[p].src1_ready);
                entry_q[push_slot[p]].src2_ready <=
                    src_ready_after_wakeup(push_uop_i[p].prs2,
                                           push_uop_i[p].src2_ready);
            end
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            assert (count_q <= DEPTH_COUNT)
                else $error("stable issue queue occupancy overflow");
            for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
                for (int q = p + 1; q < ISSUE_PORTS; q = q + 1) begin
                    assert (!(issue_fire[p] && issue_fire[q] &&
                              |(port_selected_mask[p] &
                                port_selected_mask[q])))
                        else $error("two issue ports removed one stable slot");
                end
            end
        end
    end
`endif
endmodule : CoreCompressedQueue
