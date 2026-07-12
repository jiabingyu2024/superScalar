import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreROB #(
    parameter int ALLOC_WIDTH = DISPATCH_WIDTH,
    parameter int COMPLETE_WIDTH = ISSUE_WIDTH,
    parameter int RETIRE_W = RETIRE_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  logic [ALLOC_WIDTH-1:0] alloc_valid_i,
    input  CoreRenamedUop [ALLOC_WIDTH-1:0] alloc_uop_i,
    output logic [ALLOC_WIDTH-1:0] alloc_ready_o,
    output RobIndexPath [ALLOC_WIDTH-1:0] alloc_idx_o,

    input  logic [COMPLETE_WIDTH-1:0] complete_valid_i,
    input  RobIndexPath [COMPLETE_WIDTH-1:0] complete_idx_i,
    input  DataPath [COMPLETE_WIDTH-1:0] complete_result_i,
    input  logic [COMPLETE_WIDTH-1:0] complete_exception_i,
    input  logic [COMPLETE_WIDTH-1:0][31:0] complete_exception_cause_i,
    input  logic [COMPLETE_WIDTH-1:0] complete_branch_miss_i,
    input  PcPath [COMPLETE_WIDTH-1:0] complete_redirect_pc_i,
    input  logic [COMPLETE_WIDTH-1:0] complete_csr_write_i,
    input  logic [COMPLETE_WIDTH-1:0][11:0] complete_csr_addr_i,
    input  DataPath [COMPLETE_WIDTH-1:0] complete_csr_wdata_i,

    input  logic store_complete_valid_i,
    input  RobIndexPath store_complete_idx_i,
    input  AddrPath store_complete_addr_i,

    input  logic [RETIRE_W-1:0] retire_ready_i,
    output logic [RETIRE_W-1:0] retire_valid_o,
    output CoreRobEntry [RETIRE_W-1:0] retire_entry_o,

    output logic empty_o,
    output logic full_o
);
    localparam int PTR_WIDTH = $bits(RobIndexPath);
    localparam int COUNT_WIDTH =
        $clog2(ROB_DEPTH + ALLOC_WIDTH + RETIRE_W + 1);
    localparam logic [COUNT_WIDTH-1:0] ROB_DEPTH_COUNT =
        COUNT_WIDTH'(ROB_DEPTH);

    // Fields written only at allocation are isolated from the four completion
    // ports. This prevents completion index decode from touching PC/inst/PRD
    // and old-PRD payload bits.
    typedef struct packed {
        RobIndexPath rob_idx;
        CoreDecodeUop uop;
        PhyRegNumPath prd;
        PhyRegNumPath old_prd;
        logic alloc_prd;
    } rob_alloc_payload_t;

    // Fields written only by execution/store completion form a separate cold
    // array. valid/done stay in narrow hot vectors below.
    typedef struct packed {
        DataPath result;
        logic exception;
        logic [31:0] exception_cause;
        logic branch_miss;
        PcPath redirect_pc;
        logic csr_write;
        logic [11:0] csr_addr;
        DataPath csr_wdata;
    } rob_completion_payload_t;

    rob_alloc_payload_t alloc_payload_q [ROB_DEPTH-1:0];
    rob_completion_payload_t completion_payload_q [ROB_DEPTH-1:0];
    logic [ROB_DEPTH-1:0] valid_q;
    logic [ROB_DEPTH-1:0] done_q;

    CoreRobEntry retire_stage_entry_q [RETIRE_W-1:0];
    CoreRobEntry retire_stage_next_entry [RETIRE_W-1:0];
    CoreRobEntry retire_candidate [RETIRE_W-1:0];
    logic [RETIRE_W-1:0] retire_stage_valid_q;
    logic [RETIRE_W-1:0] retire_stage_next_valid;

    RobIndexPath head_q;
    RobIndexPath tail_q;
    logic [COUNT_WIDTH-1:0] count_q;

    logic [ALLOC_WIDTH-1:0] alloc_fire;
    logic [RETIRE_W-1:0] retire_fire;
    logic [RETIRE_W-1:0] retire_stage_fill_fire;
    logic [COUNT_WIDTH-1:0] alloc_count;
    logic [COUNT_WIDTH-1:0] retire_stage_fill_count;
    logic [COUNT_WIDTH-1:0] retire_stage_survivor_count;
    logic [COUNT_WIDTH-1:0] alloc_offset [ALLOC_WIDTH-1:0];
    logic [COUNT_WIDTH-1:0] alloc_req_prefix [ALLOC_WIDTH:0];
    logic retire_prefix_valid;
    logic retire_stage_fill_prefix;

    function automatic RobIndexPath wrap_add(
        input RobIndexPath base,
        input logic [COUNT_WIDTH-1:0] inc
    );
        logic [COUNT_WIDTH-1:0] sum;
        begin
            sum = COUNT_WIDTH'(base) + inc;
            if (sum >= ROB_DEPTH_COUNT) begin
                sum = sum - ROB_DEPTH_COUNT;
            end
            if (sum >= ROB_DEPTH_COUNT) begin
                sum = sum - ROB_DEPTH_COUNT;
            end
            wrap_add = sum[PTR_WIDTH-1:0];
        end
    endfunction

    function automatic CoreRobEntry assemble_entry(input RobIndexPath idx);
        CoreRobEntry entry;
        begin
            entry = '0;
            entry.valid = valid_q[idx];
            entry.done = done_q[idx];
            entry.rob_idx = alloc_payload_q[idx].rob_idx;
            entry.uop = alloc_payload_q[idx].uop;
            entry.prd = alloc_payload_q[idx].prd;
            entry.old_prd = alloc_payload_q[idx].old_prd;
            entry.alloc_prd = alloc_payload_q[idx].alloc_prd;
            entry.result = completion_payload_q[idx].result;
            entry.exception = completion_payload_q[idx].exception;
            entry.exception_cause =
                completion_payload_q[idx].exception_cause;
            entry.branch_miss = completion_payload_q[idx].branch_miss;
            entry.redirect_pc = completion_payload_q[idx].redirect_pc;
            entry.csr_write = completion_payload_q[idx].csr_write;
            entry.csr_addr = completion_payload_q[idx].csr_addr;
            entry.csr_wdata = completion_payload_q[idx].csr_wdata;
            assemble_entry = entry;
        end
    endfunction

    always_comb begin
        alloc_req_prefix[0] = '0;
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_req_prefix[i + 1] = alloc_req_prefix[i] +
                                      COUNT_WIDTH'(alloc_valid_i[i]);
        end
    end

    generate
        for (genvar g = 0; g < ALLOC_WIDTH; g = g + 1) begin : gen_alloc_ready
            if (g == 0) begin : gen_first_lane
                assign alloc_ready_o[g] = (count_q < ROB_DEPTH_COUNT);
            end else begin : gen_later_lane
                logic [COUNT_WIDTH-1:0] prior_req_count;

                always_comb begin
                    prior_req_count = '0;
                    for (int p = 0; p < g; p = p + 1) begin
                        prior_req_count = prior_req_count +
                                          COUNT_WIDTH'(alloc_valid_i[p]);
                    end
                end

                assign alloc_ready_o[g] =
                    ((count_q + prior_req_count) < ROB_DEPTH_COUNT);
            end
        end
    endgenerate

    always_comb begin
        alloc_count = '0;
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_offset[i] = alloc_req_prefix[i];
            alloc_fire[i] = alloc_valid_i[i] && alloc_ready_o[i];
            alloc_idx_o[i] = wrap_add(tail_q, alloc_req_prefix[i]);
            if (alloc_fire[i]) begin
                alloc_count = alloc_count + 1'b1;
            end
        end
    end

    // Commit observes only the registered retire stage.
    always_comb begin
        retire_prefix_valid = 1'b1;
        for (int r = 0; r < RETIRE_W; r = r + 1) begin
            retire_entry_o[r] = retire_stage_entry_q[r];
            retire_valid_o[r] = retire_stage_valid_q[r] &&
                                retire_prefix_valid;
            retire_fire[r] = retire_valid_o[r] && retire_ready_i[r] &&
                             retire_prefix_valid;
            retire_prefix_valid = retire_prefix_valid && retire_fire[r];
        end
    end

    always_comb begin
        for (int f = 0; f < RETIRE_W; f = f + 1) begin
            retire_candidate[f] = assemble_entry(
                wrap_add(head_q, COUNT_WIDTH'(f))
            );
        end
    end

    // Pop accepted stage entries, compact at most two local entries, and refill
    // from the done ROB prefix. This is the only wide mux fed by head_q.
    always_comb begin
        retire_stage_next_valid = '0;
        retire_stage_fill_fire = '0;
        retire_stage_survivor_count = '0;
        retire_stage_fill_count = '0;
        retire_stage_fill_prefix = 1'b1;

        for (int r = 0; r < RETIRE_W; r = r + 1) begin
            retire_stage_next_entry[r] = '0;
            if (retire_stage_valid_q[r] && !retire_fire[r]) begin
                retire_stage_next_entry[retire_stage_survivor_count] =
                    retire_stage_entry_q[r];
                retire_stage_next_valid[retire_stage_survivor_count] = 1'b1;
                retire_stage_survivor_count =
                    retire_stage_survivor_count + 1'b1;
            end
        end

        for (int f = 0; f < RETIRE_W; f = f + 1) begin
            if (retire_stage_fill_prefix &&
                ((retire_stage_survivor_count + COUNT_WIDTH'(f)) <
                 COUNT_WIDTH'(RETIRE_W)) &&
                (count_q > COUNT_WIDTH'(f)) &&
                retire_candidate[f].valid && retire_candidate[f].done) begin
                retire_stage_next_entry[
                    retire_stage_survivor_count + COUNT_WIDTH'(f)] =
                    retire_candidate[f];
                retire_stage_next_valid[
                    retire_stage_survivor_count + COUNT_WIDTH'(f)] = 1'b1;
                retire_stage_fill_fire[f] = 1'b1;
                retire_stage_fill_count = retire_stage_fill_count + 1'b1;
            end else begin
                retire_stage_fill_prefix = 1'b0;
            end
        end
    end

    assign empty_o = (count_q == '0) && !(|retire_stage_valid_q);
    assign full_o = (count_q == ROB_DEPTH_COUNT);

    // Narrow ownership/control state is the only state reset by recovery.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            valid_q <= '0;
            done_q <= '0;
            retire_stage_valid_q <= '0;
        end else if (clear_i) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            valid_q <= '0;
            done_q <= '0;
            retire_stage_valid_q <= '0;
        end else begin
            head_q <= wrap_add(head_q, retire_stage_fill_count);
            tail_q <= wrap_add(tail_q, alloc_count);
            count_q <= count_q + alloc_count - retire_stage_fill_count;
            retire_stage_valid_q <= retire_stage_next_valid;

            for (int f = 0; f < RETIRE_W; f = f + 1) begin
                if (retire_stage_fill_fire[f]) begin
                    valid_q[wrap_add(head_q, COUNT_WIDTH'(f))] <= 1'b0;
                    done_q[wrap_add(head_q, COUNT_WIDTH'(f))] <= 1'b0;
                end
            end
            for (int a = 0; a < ALLOC_WIDTH; a = a + 1) begin
                if (alloc_fire[a]) begin
                    valid_q[wrap_add(tail_q, alloc_offset[a])] <= 1'b1;
                    done_q[wrap_add(tail_q, alloc_offset[a])] <= 1'b0;
                end
            end
            for (int c = 0; c < COMPLETE_WIDTH; c = c + 1) begin
                if (complete_valid_i[c]) begin
                    done_q[complete_idx_i[c]] <= 1'b1;
                end
            end
            if (store_complete_valid_i) begin
                done_q[store_complete_idx_i] <= 1'b1;
            end
        end
    end

    // Retire payload is always updated; retire_stage_valid_q owns visibility.
    // Recovery therefore has no path to the wide stage CE.
    always_ff @(posedge clk) begin
        for (int r = 0; r < RETIRE_W; r = r + 1) begin
            retire_stage_entry_q[r] <= retire_stage_next_entry[r];
        end
    end

    // Allocation-only cold payload: two write ports, no completion decode and
    // no reset/recovery CE.
    always_ff @(posedge clk) begin
        for (int a = 0; a < ALLOC_WIDTH; a = a + 1) begin
            if (alloc_fire[a]) begin
                alloc_payload_q[wrap_add(tail_q, alloc_offset[a])].rob_idx <=
                    wrap_add(tail_q, alloc_offset[a]);
                alloc_payload_q[wrap_add(tail_q, alloc_offset[a])].uop <=
                    alloc_uop_i[a].uop;
                alloc_payload_q[wrap_add(tail_q, alloc_offset[a])].prd <=
                    alloc_uop_i[a].prd;
                alloc_payload_q[wrap_add(tail_q, alloc_offset[a])].old_prd <=
                    alloc_uop_i[a].old_prd;
                alloc_payload_q[wrap_add(tail_q, alloc_offset[a])].alloc_prd <=
                    alloc_uop_i[a].alloc_prd;
            end
        end
    end

    // Completion-only cold payload. Dynamic completion index no longer fans
    // into allocation fields, valid bits, or retire-stage payload registers.
    always_ff @(posedge clk) begin
        for (int c = 0; c < COMPLETE_WIDTH; c = c + 1) begin
            if (complete_valid_i[c]) begin
                completion_payload_q[complete_idx_i[c]].result <=
                    complete_result_i[c];
                completion_payload_q[complete_idx_i[c]].exception <=
                    complete_exception_i[c];
                completion_payload_q[complete_idx_i[c]].exception_cause <=
                    complete_exception_cause_i[c];
                completion_payload_q[complete_idx_i[c]].branch_miss <=
                    complete_branch_miss_i[c];
                completion_payload_q[complete_idx_i[c]].redirect_pc <=
                    complete_redirect_pc_i[c];
                completion_payload_q[complete_idx_i[c]].csr_write <=
                    complete_csr_write_i[c];
                completion_payload_q[complete_idx_i[c]].csr_addr <=
                    complete_csr_addr_i[c];
                completion_payload_q[complete_idx_i[c]].csr_wdata <=
                    complete_csr_wdata_i[c];
            end
        end

        if (store_complete_valid_i) begin
            completion_payload_q[store_complete_idx_i].result <=
                store_complete_addr_i;
            completion_payload_q[store_complete_idx_i].exception <= 1'b0;
            completion_payload_q[store_complete_idx_i].exception_cause <= '0;
            completion_payload_q[store_complete_idx_i].branch_miss <= 1'b0;
            completion_payload_q[store_complete_idx_i].redirect_pc <= '0;
            completion_payload_q[store_complete_idx_i].csr_write <= 1'b0;
            completion_payload_q[store_complete_idx_i].csr_addr <= '0;
            completion_payload_q[store_complete_idx_i].csr_wdata <= '0;
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            for (int c = 0; c < COMPLETE_WIDTH; c = c + 1) begin
                if (complete_valid_i[c]) begin
                    assert (valid_q[complete_idx_i[c]])
                        else $error("completion targeted an unowned ROB entry");
                end
            end
            if (store_complete_valid_i) begin
                assert (valid_q[store_complete_idx_i])
                    else $error("store completion targeted an unowned ROB entry");
                assert (alloc_payload_q[store_complete_idx_i].uop.is_store)
                    else $error("store completion targeted a non-store ROB entry");
                assert (!done_q[store_complete_idx_i])
                    else $error("store completion was reported more than once");
            end
            assert (!(retire_stage_fill_fire[1] &&
                      !retire_stage_fill_fire[0]))
                else $error("ROB retire staging violated lane prefix");
            assert (!(retire_fire[1] && !retire_fire[0]))
                else $error("ROB commit handshake violated lane prefix");
        end
    end
`endif
endmodule : CoreROB
