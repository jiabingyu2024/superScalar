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
    localparam int LOCAL_HISTORY_BITS = 5;

    logic [GHR_BITS-1:0] ghr_q;
    logic [1:0] global_pht_q [BHT_ENTRIES-1:0];
    logic [LOCAL_HISTORY_BITS-1:0] local_hist_q [BHT_ENTRIES-1:0];
    logic [1:0] local_pht_q [BHT_ENTRIES-1:0];
    logic [1:0] choice_pht_q [BHT_ENTRIES-1:0];
    logic btb_valid_q [BTB_ENTRIES-1:0];
    logic [BTB_TAG_BITS-1:0] btb_tag_q [BTB_ENTRIES-1:0];
    PcPath btb_target_q [BTB_ENTRIES-1:0];

    logic [BHT_INDEX_BITS-1:0] pred_base_idx;
    logic [BHT_INDEX_BITS-1:0] pred_global_idx;
    logic [BHT_INDEX_BITS-1:0] pred_local_idx;
    logic [BTB_INDEX_BITS-1:0] pred_btb_idx;
    logic [BTB_TAG_BITS-1:0] pred_btb_tag;
    logic pred_global_taken;
    logic pred_local_taken;
    logic pred_choose_local;
    logic pred_btb_hit;
    logic pred_direction_taken;

    logic [BHT_INDEX_BITS-1:0] update_base_idx;
    logic [BHT_INDEX_BITS-1:0] update_global_idx;
    logic [BHT_INDEX_BITS-1:0] update_local_idx;
    logic [BTB_INDEX_BITS-1:0] update_btb_idx;
    logic [BTB_TAG_BITS-1:0] update_btb_tag;
    logic update_global_taken;
    logic update_local_taken;

    assign pred_base_idx = pc_i[BHT_INDEX_BITS+1:2];
    assign pred_global_idx = pred_base_idx ^ BHT_INDEX_BITS'(ghr_q);
    assign pred_local_idx = BHT_INDEX_BITS'(local_hist_q[pred_base_idx]) ^ pred_base_idx;
    assign pred_btb_idx = pc_i[BTB_INDEX_BITS+1:2];
    assign pred_btb_tag = pc_i[PC_WIDTH-1:BTB_INDEX_BITS+2];
    assign pred_global_taken = global_pht_q[pred_global_idx][1];
    assign pred_local_taken = local_pht_q[pred_local_idx][1];
    assign pred_choose_local = choice_pht_q[pred_base_idx][1];
    assign pred_direction_taken = pred_choose_local ? pred_local_taken : pred_global_taken;
    assign pred_btb_hit = btb_valid_q[pred_btb_idx] &&
                          (btb_tag_q[pred_btb_idx] == pred_btb_tag);

    assign update_base_idx = update_pc_i[BHT_INDEX_BITS+1:2];
    assign update_global_idx = update_base_idx ^ BHT_INDEX_BITS'(ghr_q);
    assign update_local_idx = BHT_INDEX_BITS'(local_hist_q[update_base_idx]) ^ update_base_idx;
    assign update_btb_idx = update_pc_i[BTB_INDEX_BITS+1:2];
    assign update_btb_tag = update_pc_i[PC_WIDTH-1:BTB_INDEX_BITS+2];
    assign update_global_taken = global_pht_q[update_global_idx][1];
    assign update_local_taken = local_pht_q[update_local_idx][1];

    always_comb begin
        pred_taken_o  = pred_direction_taken && pred_btb_hit;
        pred_valid_o  = pred_taken_o;
        pred_target_o = pred_taken_o ? btb_target_q[pred_btb_idx] :
                                       (pc_i[2] ? pc_i + 32'd4 : pc_i + 32'd8);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ghr_q <= '0;
            for (int i = 0; i < BHT_ENTRIES; i = i + 1) begin
                global_pht_q[i] <= 2'b01;
                local_hist_q[i] <= '0;
                local_pht_q[i] <= 2'b01;
                choice_pht_q[i] <= 2'b01;
            end
            for (int b = 0; b < BTB_ENTRIES; b = b + 1) begin
                btb_valid_q[b] <= 1'b0;
                btb_tag_q[b] <= '0;
                btb_target_q[b] <= '0;
            end
        end else if (update_valid_i) begin
            if (update_taken_i) begin
                if (global_pht_q[update_global_idx] != 2'b11) begin
                    global_pht_q[update_global_idx] <= global_pht_q[update_global_idx] + 2'b01;
                end
                if (local_pht_q[update_local_idx] != 2'b11) begin
                    local_pht_q[update_local_idx] <= local_pht_q[update_local_idx] + 2'b01;
                end
                btb_valid_q[update_btb_idx] <= 1'b1;
                btb_tag_q[update_btb_idx] <= update_btb_tag;
                btb_target_q[update_btb_idx] <= update_target_i;
            end else begin
                if (global_pht_q[update_global_idx] != 2'b00) begin
                    global_pht_q[update_global_idx] <= global_pht_q[update_global_idx] - 2'b01;
                end
                if (local_pht_q[update_local_idx] != 2'b00) begin
                    local_pht_q[update_local_idx] <= local_pht_q[update_local_idx] - 2'b01;
                end
            end

            if (update_global_taken != update_local_taken) begin
                if (update_local_taken == update_taken_i) begin
                    if (choice_pht_q[update_base_idx] != 2'b11) begin
                        choice_pht_q[update_base_idx] <= choice_pht_q[update_base_idx] + 2'b01;
                    end
                end else if (choice_pht_q[update_base_idx] != 2'b00) begin
                    choice_pht_q[update_base_idx] <= choice_pht_q[update_base_idx] - 2'b01;
                end
            end

            local_hist_q[update_base_idx] <= {local_hist_q[update_base_idx][LOCAL_HISTORY_BITS-2:0],
                                              update_taken_i};
            ghr_q <= {ghr_q[GHR_BITS-2:0], update_taken_i};
        end
    end
endmodule : CoreBranchPredictor
