import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreFreeList #(
    parameter int ALLOC_WIDTH = RENAME_WIDTH,
    parameter int FREE_WIDTH  = RETIRE_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

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
    localparam int DEPTH = PHY_REG_NUM - LOGIC_REG_NUM;
    localparam int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + ALLOC_WIDTH + FREE_WIDTH + 1);
    localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH);

    PhyRegNumPath mem_q [DEPTH-1:0];
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [COUNT_WIDTH-1:0] count_q;

    logic [ALLOC_WIDTH-1:0] alloc_fire;
    logic [FREE_WIDTH-1:0] free_fire;
    logic [COUNT_WIDTH-1:0] alloc_offer_count;
    logic [COUNT_WIDTH-1:0] alloc_count;
    logic [COUNT_WIDTH-1:0] free_count;
    logic [COUNT_WIDTH-1:0] free_offset [FREE_WIDTH-1:0];

    function automatic logic [PTR_WIDTH-1:0] wrap_add(
        input logic [PTR_WIDTH-1:0] base,
        input logic [COUNT_WIDTH-1:0] inc
    );
        logic [COUNT_WIDTH-1:0] sum;
        begin
            sum = COUNT_WIDTH'(base) + inc;
            if (sum >= DEPTH_COUNT) begin
                sum = sum - DEPTH_COUNT;
            end
            if (sum >= DEPTH_COUNT) begin
                sum = sum - DEPTH_COUNT;
            end
            wrap_add = sum[PTR_WIDTH-1:0];
        end
    endfunction

    always_comb begin
        alloc_offer_count = '0;
        alloc_count = '0;
        for (int i = 0; i < ALLOC_WIDTH; i = i + 1) begin
            alloc_valid_o[i] = alloc_req_i[i] && (count_q > alloc_offer_count);
            alloc_phy_o[i] = mem_q[wrap_add(rd_ptr_q, alloc_offer_count)];
            alloc_fire[i] = alloc_valid_o[i] && alloc_accept_i[i];
            if (alloc_req_i[i] && alloc_valid_o[i]) begin
                alloc_offer_count = alloc_offer_count + 1'b1;
            end
            if (alloc_fire[i]) begin
                alloc_count = alloc_count + 1'b1;
            end
        end

        free_count = '0;
        for (int j = 0; j < FREE_WIDTH; j = j + 1) begin
            free_offset[j] = free_count;
            free_ready_o[j] = ((count_q - alloc_count + free_count) < DEPTH_COUNT);
            free_fire[j] = free_valid_i[j] && free_ready_o[j] && (free_phy_i[j] != '0);
            if (free_fire[j]) begin
                free_count = free_count + 1'b1;
            end
        end
    end

    assign empty_o = (count_q == '0);
    assign full_o = (count_q == DEPTH_COUNT);

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            count_q <= DEPTH_COUNT;
            for (int i = 0; i < DEPTH; i = i + 1) begin
                mem_q[i] <= PhyRegNumPath'(LOGIC_REG_NUM + i);
            end
        end else begin
            for (int j = 0; j < FREE_WIDTH; j = j + 1) begin
                if (free_fire[j]) begin
                    mem_q[wrap_add(wr_ptr_q, free_offset[j])] <= free_phy_i[j];
                end
            end
            rd_ptr_q <= wrap_add(rd_ptr_q, alloc_count);
            wr_ptr_q <= wrap_add(wr_ptr_q, free_count);
            count_q <= count_q - alloc_count + free_count;
        end
    end
endmodule : CoreFreeList
