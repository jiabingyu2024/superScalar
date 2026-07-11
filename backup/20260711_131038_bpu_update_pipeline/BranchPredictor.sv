import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBranchPredictor (
    input  logic  clk,
    input  logic  rst,
    input  PcPath [FETCH_WIDTH-1:0] pc_i,
    output logic [FETCH_WIDTH-1:0]  pred_valid_o,
    output logic [FETCH_WIDTH-1:0]  pred_taken_o,
    output PcPath [FETCH_WIDTH-1:0] pred_target_o,
    input  logic  update_valid_i,
    input  PcPath update_pc_i,
    input  logic  update_taken_i,
    input  PcPath update_target_i,
    input  logic  update_uncond_i,
    input  logic  update_is_call_i,
    input  logic  update_is_return_i,
    input  PcPath update_return_pc_i
);
    localparam int GHR_BITS = 5;
    localparam int BHT_INDEX_BITS = $clog2(BHT_ENTRIES);
    localparam int BTB_INDEX_BITS = $clog2(BTB_ENTRIES);
    localparam int BTB_TAG_BITS = PC_WIDTH - BTB_INDEX_BITS - 2;
    localparam int LOCAL_HISTORY_BITS = 5;
    localparam int RAS_DEPTH = 8;
    localparam int RAS_PTR_WIDTH = $clog2(RAS_DEPTH);

    logic [GHR_BITS-1:0] ghr_q;
    logic [1:0] global_pht_q [BHT_ENTRIES-1:0];
    logic [LOCAL_HISTORY_BITS-1:0] local_hist_q [BHT_ENTRIES-1:0];
    logic [1:0] local_pht_q [BHT_ENTRIES-1:0];
    logic [1:0] choice_pht_q [BHT_ENTRIES-1:0];
    logic btb_valid_q [BTB_ENTRIES-1:0];
    logic btb_uncond_q [BTB_ENTRIES-1:0];
    logic btb_return_q [BTB_ENTRIES-1:0];
    logic [BTB_TAG_BITS-1:0] btb_tag_q [BTB_ENTRIES-1:0];
    PcPath btb_target_q [BTB_ENTRIES-1:0];
    PcPath ras_q [RAS_DEPTH-1:0];
    logic [RAS_PTR_WIDTH:0] ras_count_q;
    logic ras_top_valid;
    PcPath ras_top_pc;

    logic [BHT_INDEX_BITS-1:0] pred_base_idx [FETCH_WIDTH-1:0];
    logic [BHT_INDEX_BITS-1:0] pred_global_idx [FETCH_WIDTH-1:0];
    logic [BHT_INDEX_BITS-1:0] pred_local_idx [FETCH_WIDTH-1:0];
    logic [BTB_INDEX_BITS-1:0] pred_btb_idx [FETCH_WIDTH-1:0];
    logic [BTB_TAG_BITS-1:0] pred_btb_tag [FETCH_WIDTH-1:0];
    logic [FETCH_WIDTH-1:0] pred_global_taken;
    logic [FETCH_WIDTH-1:0] pred_local_taken;
    logic [FETCH_WIDTH-1:0] pred_choose_local;
    logic [FETCH_WIDTH-1:0] pred_btb_hit;
    logic [FETCH_WIDTH-1:0] pred_direction_taken;
    logic [FETCH_WIDTH-1:0] pred_return;

    logic [BHT_INDEX_BITS-1:0] update_base_idx;
    logic [BHT_INDEX_BITS-1:0] update_global_idx;
    logic [BHT_INDEX_BITS-1:0] update_local_idx;
    logic [BTB_INDEX_BITS-1:0] update_btb_idx;
    logic [BTB_TAG_BITS-1:0] update_btb_tag;
    logic update_global_taken;
    logic update_local_taken;

    for (genvar lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin : gen_predict_lane
        assign pred_base_idx[lane] = pc_i[lane][BHT_INDEX_BITS+1:2];
        assign pred_global_idx[lane] = pred_base_idx[lane] ^ BHT_INDEX_BITS'(ghr_q);
        assign pred_local_idx[lane] = BHT_INDEX_BITS'(local_hist_q[pred_base_idx[lane]]) ^
                                      pred_base_idx[lane];
        assign pred_btb_idx[lane] = pc_i[lane][BTB_INDEX_BITS+1:2];
        assign pred_btb_tag[lane] = pc_i[lane][PC_WIDTH-1:BTB_INDEX_BITS+2];
        assign pred_global_taken[lane] = global_pht_q[pred_global_idx[lane]][1];
        assign pred_local_taken[lane] = local_pht_q[pred_local_idx[lane]][1];
        assign pred_choose_local[lane] = choice_pht_q[pred_base_idx[lane]][1];
        assign pred_direction_taken[lane] = pred_choose_local[lane] ?
                                            pred_local_taken[lane] :
                                            pred_global_taken[lane];
        assign pred_btb_hit[lane] = btb_valid_q[pred_btb_idx[lane]] &&
                                    (btb_tag_q[pred_btb_idx[lane]] == pred_btb_tag[lane]);
    end
    assign ras_top_valid = (ras_count_q != '0);
    assign ras_top_pc = ras_q[(ras_count_q == '0) ? '0 : ras_count_q[RAS_PTR_WIDTH-1:0] - 1'b1];
    for (genvar lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin : gen_return_lane
        assign pred_return[lane] = pred_btb_hit[lane] &&
                                   btb_return_q[pred_btb_idx[lane]] && ras_top_valid;
    end

    assign update_base_idx = update_pc_i[BHT_INDEX_BITS+1:2];
    assign update_global_idx = update_base_idx ^ BHT_INDEX_BITS'(ghr_q);
    assign update_local_idx = BHT_INDEX_BITS'(local_hist_q[update_base_idx]) ^ update_base_idx;
    assign update_btb_idx = update_pc_i[BTB_INDEX_BITS+1:2];
    assign update_btb_tag = update_pc_i[PC_WIDTH-1:BTB_INDEX_BITS+2];
    assign update_global_taken = global_pht_q[update_global_idx][1];
    assign update_local_taken = local_pht_q[update_local_idx][1];

    always_comb begin
        for (int lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin
            pred_taken_o[lane] = pred_return[lane] ||
                                 (pred_btb_hit[lane] &&
                                  (btb_uncond_q[pred_btb_idx[lane]] ||
                                   pred_direction_taken[lane]));
            pred_valid_o[lane] = pred_taken_o[lane];
            pred_target_o[lane] = pred_return[lane] ? ras_top_pc :
                                  pred_taken_o[lane] ? btb_target_q[pred_btb_idx[lane]] :
                                                       pc_i[lane] + 32'd4;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ghr_q <= '0;
            ras_count_q <= '0;
            for (int i = 0; i < BHT_ENTRIES; i = i + 1) begin
                global_pht_q[i] <= 2'b01;
                local_hist_q[i] <= '0;
                local_pht_q[i] <= 2'b01;
                choice_pht_q[i] <= 2'b01;
            end
            for (int b = 0; b < BTB_ENTRIES; b = b + 1) begin
                btb_valid_q[b] <= 1'b0;
            end
        end else if (update_valid_i) begin
            if (update_taken_i) begin
                btb_valid_q[update_btb_idx] <= 1'b1;
            end

            // Direct and indirect jumps are always taken once their BTB entry
            // exists.  Keep them out of the conditional direction tables.
            if (!update_uncond_i) begin
                if (update_taken_i) begin
                    if (global_pht_q[update_global_idx] != 2'b11) begin
                        global_pht_q[update_global_idx] <= global_pht_q[update_global_idx] + 2'b01;
                    end
                    if (local_pht_q[update_local_idx] != 2'b11) begin
                        local_pht_q[update_local_idx] <= local_pht_q[update_local_idx] + 2'b01;
                    end
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

                local_hist_q[update_base_idx] <= {
                    local_hist_q[update_base_idx][LOCAL_HISTORY_BITS-2:0], update_taken_i};
                ghr_q <= {ghr_q[GHR_BITS-2:0], update_taken_i};
            end

            if (update_is_return_i && (ras_count_q != '0)) begin
                ras_count_q <= ras_count_q - 1'b1;
            end else if (update_is_call_i) begin
                if (ras_count_q < (RAS_PTR_WIDTH+1)'(RAS_DEPTH)) begin
                    ras_count_q <= ras_count_q + 1'b1;
                end
            end
        end
    end

    // Keep payload arrays out of the asynchronous-reset process. Their
    // ownership is carried by btb_valid_q and ras_count_q, so invalid payload
    // is never consumed. This also avoids Vivado Synth 8-7137 ambiguity.
    always_ff @(posedge clk) begin
        if (!rst && update_valid_i && update_taken_i) begin
            btb_uncond_q[update_btb_idx] <= update_uncond_i;
            btb_return_q[update_btb_idx] <= update_is_return_i;
            btb_tag_q[update_btb_idx] <= update_btb_tag;
            btb_target_q[update_btb_idx] <= update_target_i;
        end
        if (!rst && update_valid_i && update_is_call_i &&
            !update_is_return_i &&
            (ras_count_q < (RAS_PTR_WIDTH+1)'(RAS_DEPTH))) begin
            ras_q[ras_count_q[RAS_PTR_WIDTH-1:0]] <= update_return_pc_i;
        end
    end
endmodule : CoreBranchPredictor
