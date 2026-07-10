import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreFreeList #(
    parameter int ALLOC_WIDTH = RENAME_WIDTH,
    parameter int FREE_WIDTH  = RETIRE_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic recover_i,
    input  PhyRegNumPath [LOGIC_REG_NUM-1:0] recover_map_i,
    input  PhyRegNumPath [LOGIC_REG_NUM-1:0] live_map_i,

    input  logic [ALLOC_WIDTH-1:0] alloc_req_i,
    input  logic [ALLOC_WIDTH-1:0] alloc_accept_i,
    output logic [ALLOC_WIDTH-1:0] alloc_valid_o,
    output PhyRegNumPath [ALLOC_WIDTH-1:0] alloc_phy_o,

    input  logic [FREE_WIDTH-1:0] free_valid_i,
    input  PhyRegNumPath [FREE_WIDTH-1:0] free_phy_i,
    output logic [FREE_WIDTH-1:0] free_ready_o,

    output logic empty_o,
    output logic full_o
);
    localparam int COUNT_WIDTH = $clog2(PHY_REG_NUM + 1);
    localparam logic [COUNT_WIDTH-1:0] FREE_DEPTH_COUNT =
        COUNT_WIDTH'(PHY_REG_NUM - LOGIC_REG_NUM);

    logic [ALLOC_WIDTH-1:0] alloc_fire;
    logic [ALLOC_WIDTH-1:0] alloc_found;
    PhyRegNumPath [ALLOC_WIDTH-1:0] alloc_candidate;
    logic [FREE_WIDTH-1:0] free_pre_fire;
    logic [FREE_WIDTH-1:0] free_fire;
    logic [PHY_REG_NUM-1:0] free_q;
    logic [PHY_REG_NUM-1:0] live_mask;
    logic [PHY_REG_NUM-1:0] recover_live_mask;
    logic [PHY_REG_NUM-1:0] alloc_taken_mask;
    logic [COUNT_WIDTH-1:0] free_count;

    always_comb begin
        live_mask = '0;
        recover_live_mask = '0;
        live_mask[0] = 1'b1;
        recover_live_mask[0] = 1'b1;
        for (int r = 1; r < LOGIC_REG_NUM; r = r + 1) begin
            live_mask[live_map_i[r]] = 1'b1;
            recover_live_mask[recover_map_i[r]] = 1'b1;
        end

    end

    // Candidate generation deliberately has no dependency on alloc_accept_i.
    // Rename can therefore determine the current-cycle resources without a
    // ready/valid feedback path through the FreeList.
    always_comb begin
        alloc_taken_mask = '0;
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_found[i] = 1'b0;
            alloc_candidate[i] = '0;
            alloc_valid_o[i] = 1'b0;
            alloc_phy_o[i] = '0;
        end

        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            for (int p = 1; p < PHY_REG_NUM; p = p + 1) begin
                if (!alloc_found[i] &&
                    free_q[p] &&
                    !live_mask[p] &&
                    !alloc_taken_mask[p]) begin
                    alloc_found[i] = 1'b1;
                    alloc_candidate[i] = PhyRegNumPath'(p);
                end
            end
            // Availability is independent of the requesting stage's ready path.
            // This prevents an allocation request/response combinational loop.
            alloc_valid_o[i] = alloc_found[i];
            alloc_phy_o[i] = alloc_candidate[i];
            if (alloc_req_i[i] && alloc_valid_o[i]) begin
                alloc_taken_mask[alloc_candidate[i]] = 1'b1;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_fire[i] = alloc_req_i[i] && alloc_valid_o[i] && alloc_accept_i[i];
        end

        free_pre_fire = '0;
        for (int j = 0; j < FREE_WIDTH; j = j + 1) begin
            logic allocated_same_cycle;

            allocated_same_cycle = 1'b0;
            for (int a = 0; a < ALLOC_WIDTH; a = a + 1) begin
                if (alloc_req_i[a] && alloc_valid_o[a] &&
                    (alloc_candidate[a] == free_phy_i[j])) begin
                    allocated_same_cycle = 1'b1;
                end
            end

            free_ready_o[j] = 1'b1;
            free_pre_fire[j] = free_valid_i[j] &&
                               (free_phy_i[j] != '0) &&
                               !live_mask[free_phy_i[j]] &&
                               !allocated_same_cycle;
        end
        free_fire = free_pre_fire;

        for (int j = 0; j < FREE_WIDTH; j = j + 1) begin
            for (int k = 0; k < j; k = k + 1) begin
                if (free_pre_fire[k] && (free_phy_i[k] == free_phy_i[j])) begin
                    free_fire[j] = 1'b0;
                end
            end
        end

        free_count = '0;
        for (int p = 1; p < PHY_REG_NUM; p = p + 1) begin
            if (free_q[p] && !live_mask[p]) begin
                free_count = free_count + 1'b1;
            end
        end
    end

    assign empty_o = (free_count == '0);
    assign full_o = (free_count == FREE_DEPTH_COUNT);

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            for (int p = 0; p < PHY_REG_NUM; p = p + 1) begin
                free_q[p] <= (p >= LOGIC_REG_NUM);
            end
        end else if (recover_i) begin
            for (int p = 0; p < PHY_REG_NUM; p = p + 1) begin
                free_q[p] <= !recover_live_mask[p];
            end
            free_q[0] <= 1'b0;
        end else begin
            for (int p = 0; p < PHY_REG_NUM; p = p + 1) begin
                free_q[p] <= free_q[p];
            end
            for (int a = 0; a < ALLOC_WIDTH; a = a + 1) begin
                if (alloc_fire[a]) begin
                    free_q[alloc_candidate[a]] <= 1'b0;
                end
            end
            for (int j = 0; j < FREE_WIDTH; j = j + 1) begin
                if (free_fire[j]) begin
                    free_q[free_phy_i[j]] <= 1'b1;
                end
            end
            free_q[0] <= 1'b0;
        end
    end
endmodule : CoreFreeList
