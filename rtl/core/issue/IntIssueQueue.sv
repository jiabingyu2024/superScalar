import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreIntIssueQueue #(
    parameter int COLD_DEPTH = 4
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic [DISPATCH_WIDTH-1:0] push_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] push_uop_i,
    output logic [DISPATCH_WIDTH-1:0] push_ready_o,
    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,
    input  logic [INT_ISSUE_WIDTH-1:0] issue_ready_i,
    output logic [INT_ISSUE_WIDTH-1:0] issue_valid_o,
    output CoreRenamedUop [INT_ISSUE_WIDTH-1:0] issue_uop_o
);
    localparam int COLD_COUNT_WIDTH =
        $clog2(COLD_DEPTH + DISPATCH_WIDTH + 2);
    logic [DISPATCH_WIDTH-1:0] active_push_valid;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] active_push_uop;
    logic [DISPATCH_WIDTH-1:0] active_push_ready;
    logic [DISPATCH_WIDTH-1:0] cold_push_valid;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] cold_push_uop;
    logic [DISPATCH_WIDTH-1:0] cold_push_ready;

    logic cold_issue_valid;
    CoreRenamedUop cold_issue_uop;
    logic cold_issue_ready;
    logic cold_reinject_offer;
    logic cold_push_allowed;
    logic [COLD_COUNT_WIDTH-1:0] cold_count;
    logic [DISPATCH_WIDTH-1:0] route_active;
    logic [DISPATCH_WIDTH-1:0] route_cold;
    logic [$clog2(DISPATCH_WIDTH)-1:0] route_active_slot [DISPATCH_WIDTH-1:0];
    logic [$clog2(DISPATCH_WIDTH)-1:0] route_cold_slot [DISPATCH_WIDTH-1:0];
    integer active_reserve;
    integer cold_reserve;

    // The 8-entry active queue remains the only hot oldest-ready selection
    // window.  The cold queue is an overflow parking lot: it absorbs waiting
    // uops only when the active queue is under pressure and reinjects at most
    // one ready entry per cycle through the normal active push interface.
    always_comb begin
        push_ready_o = '0;
        route_active = '0;
        route_cold = '0;
        route_active_slot = '{default:'0};
        route_cold_slot = '{default:'0};

        active_reserve = 0;
        cold_reserve = 0;
        if (cold_reinject_offer) begin
            active_reserve = 1;
        end

        for (int d = 0; d < DISPATCH_WIDTH; d++) begin
            logic placed;
            placed = 1'b0;

            if ((active_reserve < DISPATCH_WIDTH) &&
                active_push_ready[active_reserve] &&
                ((cold_count == '0) ||
                 ((active_reserve == 0) &&
                  active_push_ready[DISPATCH_WIDTH-1]))) begin
                push_ready_o[d] = 1'b1;
                route_active[d] = 1'b1;
                route_active_slot[d] =
                    $clog2(DISPATCH_WIDTH)'(active_reserve);
                active_reserve = active_reserve + 1;
                placed = 1'b1;
            end

            if (!placed && cold_push_allowed &&
                (cold_reserve < DISPATCH_WIDTH) &&
                cold_push_ready[cold_reserve]) begin
                push_ready_o[d] = 1'b1;
                route_cold[d] = 1'b1;
                route_cold_slot[d] = $clog2(DISPATCH_WIDTH)'(cold_reserve);
                cold_reserve = cold_reserve + 1;
            end
        end
    end

    // Keep valid/payload out of the ready cone.  Dispatch valid must never
    // feed back through queue next-state logic into rename ready.
    always_comb begin
        active_push_valid = '0;
        active_push_uop = '0;
        cold_push_valid = '0;
        cold_push_uop = '0;
        if (cold_reinject_offer) begin
            active_push_valid[0] = 1'b1;
            active_push_uop[0] = cold_issue_uop;
        end
        for (int d = 0; d < DISPATCH_WIDTH; d++) begin
            if (route_active[d]) begin
                active_push_valid[route_active_slot[d]] = push_valid_i[d];
                active_push_uop[route_active_slot[d]] = push_uop_i[d];
            end
            if (route_cold[d]) begin
                cold_push_valid[route_cold_slot[d]] = push_valid_i[d];
                cold_push_uop[route_cold_slot[d]] = push_uop_i[d];
            end
        end
    end

    // A non-empty cold queue always owns an escape slot in active.  Any ready
    // cold entry may consume it: the reinjected ready uop becomes an active
    // issue candidate on the following cycle and releases capacity again.
    assign cold_reinject_offer = cold_issue_valid;
    assign cold_issue_ready = cold_reinject_offer && active_push_ready[0];
    assign cold_push_allowed = 1'b1;

    CoreCompressedQueue #(
        .DEPTH(INT_IQ_DEPTH),
        .ISSUE_PORTS(INT_ISSUE_WIDTH),
        .HEAD_ONLY(1'b0)
    ) u_active_queue (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_valid_i(active_push_valid),
        .push_uop_i(active_push_uop),
        .push_ready_o(active_push_ready),
        .wakeup_valid_i(wakeup_valid_i),
        .wakeup_phy_i(wakeup_phy_i),
        .issue_ready_i(issue_ready_i),
        .issue_valid_o(issue_valid_o),
        .issue_uop_o(issue_uop_o),
        .empty_o(),
        .full_o(),
        .count_o(),
        .head_not_ready_o(),
        .younger_ready_behind_head_o()
    );

    CoreCompressedQueue #(
        .DEPTH(COLD_DEPTH),
        .ISSUE_PORTS(1),
        .HEAD_ONLY(1'b0)
    ) u_cold_queue (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_valid_i(cold_push_valid),
        .push_uop_i(cold_push_uop),
        .push_ready_o(cold_push_ready),
        .wakeup_valid_i(wakeup_valid_i),
        .wakeup_phy_i(wakeup_phy_i),
        .issue_ready_i(cold_issue_ready),
        .issue_valid_o(cold_issue_valid),
        .issue_uop_o(cold_issue_uop),
        .empty_o(),
        .full_o(),
        .count_o(cold_count),
        .head_not_ready_o(),
        .younger_ready_behind_head_o()
    );

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            for (int d = 0; d < DISPATCH_WIDTH; d++) begin
                assert (!(route_active[d] && route_cold[d]))
                    else $error("INT dispatch uop acquired two queue owners");
                if (push_valid_i[d] && push_ready_o[d]) begin
                    assert (route_active[d] || route_cold[d])
                        else $error("accepted INT dispatch has no queue owner");
                end
            end
            if (cold_issue_valid && cold_issue_ready) begin
                assert (active_push_valid[0] && active_push_ready[0] &&
                        (active_push_uop[0].rob_idx == cold_issue_uop.rob_idx))
                    else $error("cold INT entry removed without active owner");
            end
        end
    end
`endif
endmodule : CoreIntIssueQueue
