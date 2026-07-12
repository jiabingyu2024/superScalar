import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreMemIssueQueue (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic [DISPATCH_WIDTH-1:0] push_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] push_uop_i,
    output logic [DISPATCH_WIDTH-1:0] push_ready_o,
    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,
    input  logic [MEM_ISSUE_WIDTH-1:0] issue_ready_i,
    output logic [MEM_ISSUE_WIDTH-1:0] issue_valid_o,
    output CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] issue_uop_o,
    output logic issue_lookahead_o,
    output logic [$clog2(MEM_IQ_DEPTH)-1:0] issue_slot_o,
    output logic [$clog2(MEM_IQ_DEPTH)-1:0] issue_age_o,
    input  logic probe_resolve_valid_i,
    input  logic probe_resolve_accept_i,
    input  logic [$clog2(MEM_IQ_DEPTH)-1:0] probe_resolve_slot_i,
    input  logic [$clog2(MEM_IQ_DEPTH)-1:0] probe_resolve_age_i,
    input  RobIndexPath probe_resolve_rob_idx_i,
    output logic head_not_ready_o,
    output logic younger_ready_behind_head_o,
    output logic [$clog2(MEM_IQ_DEPTH+1)-1:0] occupancy_o,
    output logic probe_launch_o,
    output logic probe_accept_o,
    output logic probe_reject_o
);
    localparam int SLOT_WIDTH = $clog2(MEM_IQ_DEPTH);
    localparam int COUNT_WIDTH = $clog2(MEM_IQ_DEPTH + 1);

    CoreRenamedUop entry_q [MEM_IQ_DEPTH-1:0];
    logic [MEM_IQ_DEPTH-1:0] valid_q;
    logic [SLOT_WIDTH-1:0] age_q [MEM_IQ_DEPTH-1:0];
    logic [COUNT_WIDTH-1:0] count_q;

    logic probe_pending_q;
    logic [SLOT_WIDTH-1:0] probe_slot_q;
    logic [SLOT_WIDTH-1:0] probe_age_q;
    RobIndexPath probe_rob_idx_q;
    logic [MEM_IQ_DEPTH-1:0] denied_q;

    logic [MEM_IQ_DEPTH-1:0] ready_now;
    logic [MEM_IQ_DEPTH-1:0] src1_ready_now;
    logic [MEM_IQ_DEPTH-1:0] src2_ready_now;
    logic [MEM_IQ_DEPTH-1:0] older_all_load;
    logic [MEM_IQ_DEPTH-1:0] remove_mask;
    logic [MEM_IQ_DEPTH-1:0] free_mask;
    logic [DISPATCH_WIDTH-1:0] push_fire;
    logic [SLOT_WIDTH-1:0] push_slot [DISPATCH_WIDTH-1:0];
    logic [COUNT_WIDTH-1:0] push_rank [DISPATCH_WIDTH-1:0];
    logic [COUNT_WIDTH-1:0] push_count;
    logic remove_valid;
    logic [SLOT_WIDTH-1:0] remove_age;
    logic issue_fire;

    function automatic logic src_ready_after_wakeup(
        input PhyRegNumPath src,
        input logic src_ready
    );
        logic hit;
        begin
            hit = (src == '0) || src_ready;
            for (int w = 0; w < ISSUE_WIDTH; w++) begin
                if (wakeup_valid_i[w] && (wakeup_phy_i[w] == src)) begin
                    hit = 1'b1;
                end
            end
            src_ready_after_wakeup = hit;
        end
    endfunction

    always_comb begin
        for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
            src1_ready_now[e] = src_ready_after_wakeup(
                entry_q[e].prs1, entry_q[e].src1_ready
            );
            src2_ready_now[e] = src_ready_after_wakeup(
                entry_q[e].prs2, entry_q[e].src2_ready
            );
            // A store may establish its ordered StoreBuffer shell as soon as
            // the address source is ready.  Store data retains a separate PRD
            // owner and is captured later if src2 is still pending.
            ready_now[e] = valid_q[e] && src1_ready_now[e] &&
                           (entry_q[e].uop.is_store || src2_ready_now[e]);
        end
    end

    always_comb begin
        older_all_load = '1;
        for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
            for (int o = 0; o < MEM_IQ_DEPTH; o++) begin
                if (valid_q[o] && (age_q[o] < age_q[e]) &&
                    !entry_q[o].uop.is_load) begin
                    older_all_load[e] = 1'b0;
                end
            end
        end
    end

    // Stable-slot selection. Age zero always has priority. A
    // younger candidate is only a load and every older inspected entry must
    // also be a load; its address/cacheability is proven by the registered
    // probe in ExecuteCluster before this queue removes it. When the previous
    // probe resolves, a new younger candidate may replace it on the same edge,
    // giving the address-probe stage an initiation interval of one cycle.
    always_comb begin
        issue_valid_o = '0;
        issue_uop_o = '0;
        issue_lookahead_o = 1'b0;
        issue_slot_o = '0;
        issue_age_o = '0;
        if (!probe_pending_q || probe_resolve_valid_i) begin
            for (int wanted_age = 0;
                 wanted_age < MEM_IQ_DEPTH;
                 wanted_age++) begin
                for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
                    if (!issue_valid_o[0] && valid_q[e] &&
                        (age_q[e] == SLOT_WIDTH'(wanted_age)) &&
                        ready_now[e] &&
                        // A resolving probe may only be replaced by another
                        // lookahead. Direct head issue and old-probe removal
                        // cannot both consume IQ ownership in this cycle.
                        (!probe_pending_q || (wanted_age != 0)) &&
                        !(probe_pending_q &&
                          (SLOT_WIDTH'(e) == probe_slot_q)) &&
                        ((wanted_age == 0) ||
                         (entry_q[e].uop.is_load &&
                          !denied_q[e]))) begin
                        if ((wanted_age == 0) || older_all_load[e]) begin
                            issue_valid_o[0] = 1'b1;
                            issue_uop_o[0] = entry_q[e];
                            issue_uop_o[0].src1_ready = src1_ready_now[e];
                            issue_uop_o[0].src2_ready = src2_ready_now[e];
                            issue_lookahead_o = (wanted_age != 0);
                            issue_slot_o = SLOT_WIDTH'(e);
                            issue_age_o = age_q[e];
                        end
                    end
                end
            end
        end

        // An accepted old probe compacts the age ranks on this edge. Capture
        // the replacement candidate's post-remove age so its later resolve
        // still matches the stable slot identity.
        if (issue_valid_o[0] && issue_lookahead_o && probe_pending_q &&
            probe_resolve_valid_i && probe_resolve_accept_i &&
            (issue_age_o > probe_age_q)) begin
            issue_age_o = issue_age_o - 1'b1;
        end
    end

    assign issue_fire = issue_valid_o[0] && issue_ready_i[0];
    assign probe_launch_o = issue_fire && issue_lookahead_o;
    assign probe_accept_o = probe_resolve_valid_i && probe_resolve_accept_i;
    assign probe_reject_o = probe_resolve_valid_i && !probe_resolve_accept_i;

    always_comb begin
        remove_mask = '0;
        remove_valid = 1'b0;
        remove_age = '0;
        if (issue_fire && !issue_lookahead_o) begin
            remove_mask[issue_slot_o] = 1'b1;
            remove_valid = 1'b1;
            remove_age = issue_age_o;
        end else if (probe_resolve_valid_i && probe_resolve_accept_i &&
                     probe_pending_q &&
                     (probe_resolve_slot_i == probe_slot_q) &&
                     (probe_resolve_age_i == probe_age_q) &&
                     (probe_resolve_rob_idx_i == probe_rob_idx_q) &&
                     valid_q[probe_slot_q] &&
                     (age_q[probe_slot_q] == probe_age_q) &&
                     (entry_q[probe_slot_q].rob_idx == probe_rob_idx_q)) begin
            remove_mask[probe_slot_q] = 1'b1;
            remove_valid = 1'b1;
            remove_age = probe_age_q;
        end
    end

    // Allocate pushes into holes left by an arbitrary removal.  Only valid and
    // compact age ranks move; the wide payload never changes physical slot.
    always_comb begin
        free_mask = ~valid_q | remove_mask;
        push_ready_o = '0;
        push_slot = '{default:'0};
        for (int p = 0; p < DISPATCH_WIDTH; p++) begin
            for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
                if (!push_ready_o[p] && free_mask[e]) begin
                    push_ready_o[p] = 1'b1;
                    push_slot[p] = SLOT_WIDTH'(e);
                    free_mask[e] = 1'b0;
                end
            end
        end
    end

    // Valid affects only the state update/rank of accepted pushes, never the
    // externally visible ready decision above.
    always_comb begin
        push_fire = '0;
        push_rank = '{default:'0};
        push_count = '0;
        for (int p = 0; p < DISPATCH_WIDTH; p++) begin
            push_fire[p] = push_valid_i[p] && push_ready_o[p];
            push_rank[p] = push_count;
            if (push_fire[p]) begin
                push_count = push_count + 1'b1;
            end
        end
    end

    assign occupancy_o = count_q;
    always_comb begin
        head_not_ready_o = 1'b0;
        younger_ready_behind_head_o = 1'b0;
        for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
            if (valid_q[e] && (age_q[e] == '0)) begin
                head_not_ready_o = !ready_now[e];
            end
            if (valid_q[e] && (age_q[e] != '0) && ready_now[e]) begin
                younger_ready_behind_head_o = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q <= '0;
            count_q <= '0;
            probe_pending_q <= 1'b0;
            denied_q <= '0;
        end else if (clear_i) begin
            valid_q <= '0;
            count_q <= '0;
            probe_pending_q <= 1'b0;
            denied_q <= '0;
        end else begin
            valid_q <= valid_q & ~remove_mask;
            count_q <= count_q - COUNT_WIDTH'(remove_valid) + push_count;
            denied_q <= denied_q & ~remove_mask;
            if (remove_valid) begin
                for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
                    if (valid_q[e] && !remove_mask[e] &&
                        (age_q[e] > remove_age)) begin
                        age_q[e] <= age_q[e] - 1'b1;
                    end
                end
            end

            for (int p = 0; p < DISPATCH_WIDTH; p++) begin
                if (push_fire[p]) begin
                    valid_q[push_slot[p]] <= 1'b1;
                    denied_q[push_slot[p]] <= 1'b0;
                    age_q[push_slot[p]] <= SLOT_WIDTH'(
                        count_q - COUNT_WIDTH'(remove_valid) + push_rank[p]);
                end
            end

            if (probe_resolve_valid_i && !probe_resolve_accept_i &&
                probe_pending_q &&
                (probe_resolve_slot_i == probe_slot_q) &&
                (probe_resolve_age_i == probe_age_q) &&
                (probe_resolve_rob_idx_i == probe_rob_idx_q)) begin
                denied_q[probe_resolve_slot_i] <= 1'b1;
            end

            if (probe_launch_o) begin
                probe_pending_q <= 1'b1;
                probe_slot_q <= issue_slot_o;
                probe_age_q <= issue_age_o;
                probe_rob_idx_q <= issue_uop_o[0].rob_idx;
            end else if (probe_resolve_valid_i) begin
                probe_pending_q <= 1'b0;
            end
        end
    end

    // valid_q owns every physical slot. Recovery may update stale ready bits or
    // payload, but it cannot make them visible and therefore does not belong on
    // the wide entry array's clock enable.
    always_ff @(posedge clk) begin
        for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
            if (valid_q[e]) begin
                entry_q[e].src1_ready <=
                    src_ready_after_wakeup(entry_q[e].prs1,
                                           entry_q[e].src1_ready);
                entry_q[e].src2_ready <=
                    src_ready_after_wakeup(entry_q[e].prs2,
                                           entry_q[e].src2_ready);
            end
        end
        for (int p = 0; p < DISPATCH_WIDTH; p++) begin
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
            assert (count_q <= COUNT_WIDTH'(MEM_IQ_DEPTH))
                else $error("MEM IQ occupancy overflow");
            if (probe_resolve_valid_i && probe_resolve_accept_i) begin
                assert (probe_pending_q && valid_q[probe_resolve_slot_i] &&
                        (age_q[probe_resolve_slot_i] == probe_resolve_age_i) &&
                        (entry_q[probe_resolve_slot_i].rob_idx ==
                         probe_resolve_rob_idx_i))
                    else $error("MEM probe accepted stale/reused slot");
            end
            if (issue_fire && issue_lookahead_o) begin
                assert (issue_uop_o[0].uop.is_load)
                    else $error("MEM lookahead selected non-load");
                for (int e = 0; e < MEM_IQ_DEPTH; e++) begin
                    assert (!(valid_q[e] && (age_q[e] < issue_age_o) &&
                              !entry_q[e].uop.is_load))
                        else $error("MEM lookahead crossed store/fence/serial");
                end
            end
        end
    end
`endif
endmodule : CoreMemIssueQueue
