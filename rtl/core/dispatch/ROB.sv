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

    input  logic [RETIRE_W-1:0] retire_ready_i,
    output logic [RETIRE_W-1:0] retire_valid_o,
    output CoreRobEntry [RETIRE_W-1:0] retire_entry_o,

    output logic empty_o,
    output logic full_o
);
    localparam int PTR_WIDTH = $bits(RobIndexPath);
    localparam int COUNT_WIDTH = $clog2(ROB_DEPTH + ALLOC_WIDTH + RETIRE_W + 1);
    localparam logic [COUNT_WIDTH-1:0] ROB_DEPTH_COUNT = COUNT_WIDTH'(ROB_DEPTH);

    CoreRobEntry entry_q [ROB_DEPTH-1:0];
    RobIndexPath head_q;
    RobIndexPath tail_q;
    logic [COUNT_WIDTH-1:0] count_q;

    logic [ALLOC_WIDTH-1:0] alloc_fire;
    logic [RETIRE_W-1:0] retire_fire;
    logic [COUNT_WIDTH-1:0] alloc_count;
    logic [COUNT_WIDTH-1:0] retire_count;
    logic [COUNT_WIDTH-1:0] retire_offer_count;
    logic [COUNT_WIDTH-1:0] alloc_offset [ALLOC_WIDTH-1:0];
    logic [COUNT_WIDTH-1:0] alloc_req_prefix [ALLOC_WIDTH:0];
    logic [COUNT_WIDTH-1:0] retire_offset [RETIRE_W-1:0];
    logic retire_prefix_valid;

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

    always_comb begin
        alloc_req_prefix[0] = '0;
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_req_prefix[i + 1] = alloc_req_prefix[i] + COUNT_WIDTH'(alloc_valid_i[i]);
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
                        prior_req_count = prior_req_count + COUNT_WIDTH'(alloc_valid_i[p]);
                    end
                end

                assign alloc_ready_o[g] =
                    ((count_q + prior_req_count) < ROB_DEPTH_COUNT);
            end
        end
    endgenerate

    // Ready for a lane depends only on the registered occupancy and requests
    // from older lanes.  It must not feed back through alloc_fire.
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

    always_comb begin
        retire_offer_count = '0;
        retire_prefix_valid = 1'b1;
        for (int r = 0; r < RETIRE_W; r = r + 1) begin
            retire_offset[r] = retire_offer_count;
            retire_entry_o[r] = entry_q[wrap_add(head_q, retire_offer_count)];
            retire_valid_o[r] = (count_q > retire_offer_count) &&
                                retire_entry_o[r].valid &&
                                retire_entry_o[r].done &&
                                retire_prefix_valid;

            if (retire_valid_o[r]) begin
                retire_offer_count = retire_offer_count + 1'b1;
            end
            retire_prefix_valid = retire_prefix_valid && retire_valid_o[r];
        end
    end

    always_comb begin
        retire_count = '0;
        for (int r = 0; r < RETIRE_W; r = r + 1) begin
            retire_fire[r] = retire_valid_o[r] && retire_ready_i[r];
            if (retire_fire[r]) begin
                retire_count = retire_count + 1'b1;
            end
        end
    end

    assign empty_o = (count_q == '0);
    assign full_o = (count_q == ROB_DEPTH_COUNT);

    // head/tail/count define ownership of entry_q. Empty entries are never
    // offered for retirement, and allocation overwrites every payload field,
    // so resetting the wide ROB array only adds a large FPGA reset network.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
        end else if (clear_i) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
        end else begin
            for (int a = 0; a < ALLOC_WIDTH; a = a + 1) begin
                if (alloc_fire[a]) begin
                    entry_q[wrap_add(tail_q, alloc_offset[a])].valid <= 1'b1;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].done <= 1'b0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].rob_idx <= wrap_add(tail_q, alloc_offset[a]);
                    entry_q[wrap_add(tail_q, alloc_offset[a])].uop <= alloc_uop_i[a].uop;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].prd <= alloc_uop_i[a].prd;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].old_prd <= alloc_uop_i[a].old_prd;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].alloc_prd <= alloc_uop_i[a].alloc_prd;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].result <= '0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].exception <= 1'b0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].exception_cause <= '0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].branch_miss <= 1'b0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].redirect_pc <= '0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].csr_write <= 1'b0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].csr_addr <= '0;
                    entry_q[wrap_add(tail_q, alloc_offset[a])].csr_wdata <= '0;
                end
            end

            for (int c = 0; c < COMPLETE_WIDTH; c = c + 1) begin
                if (complete_valid_i[c]) begin
                    entry_q[complete_idx_i[c]].done <= 1'b1;
                    entry_q[complete_idx_i[c]].result <= complete_result_i[c];
                    entry_q[complete_idx_i[c]].exception <= complete_exception_i[c];
                    entry_q[complete_idx_i[c]].exception_cause <= complete_exception_cause_i[c];
                    entry_q[complete_idx_i[c]].branch_miss <= complete_branch_miss_i[c];
                    entry_q[complete_idx_i[c]].redirect_pc <= complete_redirect_pc_i[c];
                    entry_q[complete_idx_i[c]].csr_write <= complete_csr_write_i[c];
                    entry_q[complete_idx_i[c]].csr_addr <= complete_csr_addr_i[c];
                    entry_q[complete_idx_i[c]].csr_wdata <= complete_csr_wdata_i[c];
                end
            end

            for (int r = 0; r < RETIRE_W; r = r + 1) begin
                if (retire_fire[r]) begin
                    entry_q[wrap_add(head_q, retire_offset[r])].valid <= 1'b0;
                    entry_q[wrap_add(head_q, retire_offset[r])].done <= 1'b0;
                end
            end

            head_q <= wrap_add(head_q, retire_count);
            tail_q <= wrap_add(tail_q, alloc_count);
            count_q <= count_q + alloc_count - retire_count;
        end
    end
endmodule : CoreROB
