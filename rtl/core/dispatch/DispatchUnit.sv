import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreDispatchUnit #(
    parameter int MEM_BUFFER_DEPTH = 4,
    parameter int INDEX_BITS = (MEM_BUFFER_DEPTH <= 1) ?
                               1 : $clog2(MEM_BUFFER_DEPTH),
    parameter int COUNT_BITS = $clog2(MEM_BUFFER_DEPTH + 1)
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  logic [DISPATCH_WIDTH-1:0] in_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] in_uop_i,
    input  TubeTypePath [DISPATCH_WIDTH-1:0] in_tube_i,
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
    localparam logic [COUNT_BITS-1:0] MEM_BUFFER_DEPTH_COUNT =
        COUNT_BITS'(MEM_BUFFER_DEPTH);

    CoreRenamedUop mem_entry_q [MEM_BUFFER_DEPTH-1:0];
    CoreRenamedUop mem_ready_entry [MEM_BUFFER_DEPTH-1:0];
    CoreRenamedUop mem_next_entry [MEM_BUFFER_DEPTH-1:0];
    logic [COUNT_BITS-1:0] mem_count_q;
    logic [COUNT_BITS-1:0] mem_next_count;
    logic [COUNT_BITS-1:0] mem_pop_count;
    logic [COUNT_BITS-1:0] mem_push_reserve;
    logic [DISPATCH_WIDTH-1:0] lane_ready;
    logic [DISPATCH_WIDTH-1:0] lane_fire;
    logic [DISPATCH_WIDTH-1:0] mem_push_fire;
    logic [DISPATCH_WIDTH-1:0] mem_pop_fire;
    logic input_prefix_open;
    logic mem_pop_prefix_open;

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

    // Routed evidence points at rename -> MEM-IQ, while INT/branch staging
    // loses IPC. Therefore only MEM uops cross an allocated register boundary;
    // INT and MUL retain their original same-cycle dispatch contract.
    always_comb begin
        mem_push_reserve = '0;
        input_prefix_open = 1'b1;
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            in_ready_o[i] = 1'b0;
            lane_ready[i] = 1'b0;

            unique case (in_tube_i[i])
                TUBE_TYPE_MEM: begin
                    lane_ready[i] =
                        ((mem_count_q + mem_push_reserve) <
                         MEM_BUFFER_DEPTH_COUNT);
                end
                TUBE_TYPE_MUL: lane_ready[i] = mul_ready_i[i];
                default:       lane_ready[i] = int_ready_i[i];
            endcase

            in_ready_o[i] = !clear_i && input_prefix_open && lane_ready[i];
            // Capacity reservation for a younger lane is deliberately based
            // only on ready/tube so rename valid can never feed back into
            // rename ready.
            if ((in_tube_i[i] == TUBE_TYPE_MEM) && in_ready_o[i]) begin
                mem_push_reserve = mem_push_reserve + 1'b1;
            end
            input_prefix_open = input_prefix_open && in_ready_o[i];
        end
    end

    // Keep valid/data generation in a separate cone from ready. This is more
    // than coding style: combining the packed renamed payload and ready in one
    // process makes synthesis conservatively reconstruct a ready/valid loop.
    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            lane_fire[i] = in_valid_i[i] && in_ready_o[i];
            mem_push_fire[i] = 1'b0;
            int_valid_o[i] = 1'b0;
            mul_valid_o[i] = 1'b0;
            int_uop_o[i] = in_uop_i[i];
            mul_uop_o[i] = in_uop_i[i];

            if (!clear_i && in_valid_i[i]) begin
                unique case (in_tube_i[i])
                    TUBE_TYPE_MEM: mem_push_fire[i] = lane_fire[i];
                    TUBE_TYPE_MUL: mul_valid_o[i] = 1'b1;
                    default:       int_valid_o[i] = 1'b1;
                endcase
            end
        end
    end

    // Accumulate completions while a MEM uop waits for MEM-IQ capacity.
    always_comb begin
        for (int e = 0; e < MEM_BUFFER_DEPTH; e = e + 1) begin
            mem_ready_entry[e] = mem_entry_q[e];
            mem_ready_entry[e].src1_ready = src_ready_after_wakeup(
                mem_entry_q[e].prs1, mem_entry_q[e].src1_ready
            );
            mem_ready_entry[e].src2_ready = src_ready_after_wakeup(
                mem_entry_q[e].prs2, mem_entry_q[e].src2_ready
            );
        end
    end

    // MEM entries remain ordered. The second buffered entry is offered only
    // when the first one is accepted, matching the queue's lane-prefix rule.
    always_comb begin
        mem_pop_count = '0;
        mem_pop_prefix_open = 1'b1;
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            mem_valid_o[i] = !clear_i && mem_pop_prefix_open &&
                             (mem_count_q > COUNT_BITS'(i));
            mem_uop_o[i] = mem_ready_entry[i];
            mem_pop_fire[i] = mem_valid_o[i] && mem_ready_i[i];
            if (mem_pop_fire[i]) begin
                mem_pop_count = mem_pop_count + 1'b1;
            end
            mem_pop_prefix_open = mem_pop_prefix_open && mem_pop_fire[i];
        end
    end

    always_comb begin
        mem_next_count = '0;
        for (int e = 0; e < MEM_BUFFER_DEPTH; e = e + 1) begin
            mem_next_entry[e] = '0;
        end

        for (int e = 0; e < MEM_BUFFER_DEPTH; e = e + 1) begin
            if ((COUNT_BITS'(e) >= mem_pop_count) &&
                (COUNT_BITS'(e) < mem_count_q)) begin
                mem_next_entry[mem_next_count[INDEX_BITS-1:0]] =
                    mem_ready_entry[e];
                mem_next_count = mem_next_count + 1'b1;
            end
        end

        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            if (mem_push_fire[i]) begin
                mem_next_entry[mem_next_count[INDEX_BITS-1:0]] = in_uop_i[i];
                mem_next_entry[mem_next_count[INDEX_BITS-1:0]].src1_ready =
                    src_ready_after_wakeup(
                        in_uop_i[i].prs1, in_uop_i[i].src1_ready
                    );
                mem_next_entry[mem_next_count[INDEX_BITS-1:0]].src2_ready =
                    src_ready_after_wakeup(
                        in_uop_i[i].prs2, in_uop_i[i].src2_ready
                    );
                mem_next_count = mem_next_count + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_count_q <= '0;
        end else if (clear_i) begin
            mem_count_q <= '0;
        end else begin
            mem_count_q <= mem_next_count;
        end
    end

    // mem_count_q owns payload visibility. The wide uop storage intentionally
    // has no reset/clear control set.
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            for (int e = 0; e < MEM_BUFFER_DEPTH; e = e + 1) begin
                mem_entry_q[e] <= mem_next_entry[e];
            end
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            assert (mem_count_q <= MEM_BUFFER_DEPTH_COUNT)
                else $error("allocated MEM dispatch buffer overflow");
            assert (!(lane_fire[1] && in_valid_i[0] && !lane_fire[0]))
                else $error("dispatch input violated lane prefix");
            assert (!(mem_pop_fire[1] && !mem_pop_fire[0]))
                else $error("MEM dispatch violated lane prefix");
        end
    end
`endif
endmodule : CoreDispatchUnit
