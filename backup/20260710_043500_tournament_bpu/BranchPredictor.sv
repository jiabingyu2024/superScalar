import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBranchPredictor (
    input  logic  clk,
    input  logic  rst,
    input  PcPath pc_i,
    output logic  pred_valid_o,
    output logic  pred_taken_o,
    output PcPath pred_target_o,
    input  logic  update_valid_i,
    input  PcPath update_pc_i,
    input  logic  update_taken_i,
    input  PcPath update_target_i
);
    localparam int GHR_BITS = 5;
    localparam int BHT_INDEX_BITS = $clog2(BHT_ENTRIES);
    localparam int BTB_INDEX_BITS = $clog2(BTB_ENTRIES);
    localparam int BTB_TAG_BITS = PC_WIDTH - BTB_INDEX_BITS - 2;

    logic [GHR_BITS-1:0] ghr_q;
    logic [1:0] bht_q [BHT_ENTRIES-1:0];
    logic btb_valid_q [BTB_ENTRIES-1:0];
    logic [BTB_TAG_BITS-1:0] btb_tag_q [BTB_ENTRIES-1:0];
    PcPath btb_target_q [BTB_ENTRIES-1:0];

    logic [BHT_INDEX_BITS-1:0] pred_bht_idx;
    logic [BTB_INDEX_BITS-1:0] pred_btb_idx;
    logic [BTB_TAG_BITS-1:0] pred_btb_tag;
    logic pred_bht_taken;
    logic pred_btb_hit;

    logic [BHT_INDEX_BITS-1:0] update_bht_idx;
    logic [BTB_INDEX_BITS-1:0] update_btb_idx;
    logic [BTB_TAG_BITS-1:0] update_btb_tag;

    assign pred_bht_idx = pc_i[BHT_INDEX_BITS+1:2] ^ BHT_INDEX_BITS'(ghr_q);
    assign pred_btb_idx = pc_i[BTB_INDEX_BITS+1:2];
    assign pred_btb_tag = pc_i[PC_WIDTH-1:BTB_INDEX_BITS+2];
    assign pred_bht_taken = bht_q[pred_bht_idx][1];
    assign pred_btb_hit = btb_valid_q[pred_btb_idx] &&
                          (btb_tag_q[pred_btb_idx] == pred_btb_tag);

    assign update_bht_idx = update_pc_i[BHT_INDEX_BITS+1:2] ^ BHT_INDEX_BITS'(ghr_q);
    assign update_btb_idx = update_pc_i[BTB_INDEX_BITS+1:2];
    assign update_btb_tag = update_pc_i[PC_WIDTH-1:BTB_INDEX_BITS+2];

    always_comb begin
        pred_taken_o  = pred_bht_taken && pred_btb_hit;
        pred_valid_o  = pred_taken_o;
        pred_target_o = pred_taken_o ? btb_target_q[pred_btb_idx] :
                                       (pc_i[2] ? pc_i + 32'd4 : pc_i + 32'd8);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ghr_q <= '0;
            for (int i = 0; i < BHT_ENTRIES; i = i + 1) begin
                bht_q[i] <= 2'b01;
            end
            for (int b = 0; b < BTB_ENTRIES; b = b + 1) begin
                btb_valid_q[b] <= 1'b0;
                btb_tag_q[b] <= '0;
                btb_target_q[b] <= '0;
            end
        end else if (update_valid_i) begin
            if (update_taken_i) begin
                if (bht_q[update_bht_idx] != 2'b11) begin
                    bht_q[update_bht_idx] <= bht_q[update_bht_idx] + 2'b01;
                end
                btb_valid_q[update_btb_idx] <= 1'b1;
                btb_tag_q[update_btb_idx] <= update_btb_tag;
                btb_target_q[update_btb_idx] <= update_target_i;
            end else if (bht_q[update_bht_idx] != 2'b00) begin
                bht_q[update_bht_idx] <= bht_q[update_bht_idx] - 2'b01;
            end
            ghr_q <= {ghr_q[GHR_BITS-2:0], update_taken_i};
        end
    end
endmodule : CoreBranchPredictor
