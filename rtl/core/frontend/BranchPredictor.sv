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
    localparam int BHT_INDEX_BITS = $clog2(BHT_ENTRIES);
    localparam int BTB_INDEX_BITS = $clog2(BTB_ENTRIES);
    localparam int BTB_TAG_BITS = PC_WIDTH - BTB_INDEX_BITS - 2;
    localparam int GHR_BITS = BHT_INDEX_BITS;
    localparam int RAS_DEPTH = 8;
    localparam int RAS_PTR_WIDTH = $clog2(RAS_DEPTH);

    logic [GHR_BITS-1:0] ghr_q;
    logic [1:0] direction_pht_q [BHT_ENTRIES-1:0];
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
    logic [BHT_INDEX_BITS-1:0] pred_direction_idx [FETCH_WIDTH-1:0];
    logic [BTB_INDEX_BITS-1:0] pred_btb_idx [FETCH_WIDTH-1:0];
    logic [BTB_TAG_BITS-1:0] pred_btb_tag [FETCH_WIDTH-1:0];
    logic [FETCH_WIDTH-1:0] pred_direction_taken;
    logic [FETCH_WIDTH-1:0] pred_btb_hit;
    logic [FETCH_WIDTH-1:0] pred_return;

    // Commit-to-BPU input boundary. Retirement produces at most one update in
    // a cycle, so this stage preserves full update throughput.
    logic update_valid_q;
    PcPath update_pc_q;
    logic update_taken_q;
    PcPath update_target_q;
    logic update_uncond_q;
    logic update_is_call_q;
    logic update_is_return_q;
    PcPath update_return_pc_q;

    logic [BHT_INDEX_BITS-1:0] update_base_idx;
    logic [BHT_INDEX_BITS-1:0] update_direction_idx;
    logic [BTB_INDEX_BITS-1:0] update_btb_idx;
    logic [BTB_TAG_BITS-1:0] update_btb_tag;
    logic [1:0] update_direction_counter_current;
    logic [1:0] update_direction_counter_next;

    // Registered table-write bundle. PHT/BTB array write address, enable and
    // data are driven only from this stage, cutting update_pc_q from every
    // table endpoint. Same-index forwarding preserves consecutive updates.
    logic table_update_valid_q;
    logic table_update_direction_we_q;
    logic [BHT_INDEX_BITS-1:0] table_update_direction_idx_q;
    logic [1:0] table_update_direction_counter_q;
    logic [BTB_INDEX_BITS-1:0] table_update_btb_idx_q;
    logic [BTB_TAG_BITS-1:0] table_update_btb_tag_q;
    logic table_update_taken_q;
    PcPath table_update_target_q;
    logic table_update_uncond_q;
    logic table_update_is_return_q;

    function automatic logic [1:0] sat_counter_update(
        input logic [1:0] counter,
        input logic taken
    );
        begin
            if (taken) begin
                sat_counter_update = (counter == 2'b11) ?
                                     counter : counter + 2'b01;
            end else begin
                sat_counter_update = (counter == 2'b00) ?
                                     counter : counter - 2'b01;
            end
        end
    endfunction

    // A single gshare direction lookup replaces the serial
    // local-history/local-PHT/choice-PHT tournament cone. BTB and RAS behavior
    // remains unchanged, but the PC feedback path loses two dependent table
    // reads and the choice mux.
    for (genvar lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin : gen_predict_lane
        assign pred_base_idx[lane] = pc_i[lane][BHT_INDEX_BITS+1:2];
        assign pred_direction_idx[lane] =
            pred_base_idx[lane] ^ BHT_INDEX_BITS'(ghr_q);
        assign pred_btb_idx[lane] = pc_i[lane][BTB_INDEX_BITS+1:2];
        assign pred_btb_tag[lane] =
            pc_i[lane][PC_WIDTH-1:BTB_INDEX_BITS+2];
        assign pred_direction_taken[lane] =
            direction_pht_q[pred_direction_idx[lane]][1];
        assign pred_btb_hit[lane] =
            btb_valid_q[pred_btb_idx[lane]] &&
            (btb_tag_q[pred_btb_idx[lane]] == pred_btb_tag[lane]);
    end

    assign ras_top_valid = (ras_count_q != '0);
    assign ras_top_pc = ras_q[(ras_count_q == '0) ? '0 :
                              ras_count_q[RAS_PTR_WIDTH-1:0] - 1'b1];

    for (genvar lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin : gen_return_lane
        assign pred_return[lane] = pred_btb_hit[lane] &&
                                   btb_return_q[pred_btb_idx[lane]] &&
                                   ras_top_valid;
    end

    always_comb begin
        for (int lane = 0; lane < FETCH_WIDTH; lane = lane + 1) begin
            pred_taken_o[lane] = pred_return[lane] ||
                                 (pred_btb_hit[lane] &&
                                  (btb_uncond_q[pred_btb_idx[lane]] ||
                                   pred_direction_taken[lane]));
            pred_valid_o[lane] = pred_taken_o[lane];
            pred_target_o[lane] = pred_return[lane] ? ras_top_pc :
                                  pred_taken_o[lane] ?
                                  btb_target_q[pred_btb_idx[lane]] :
                                  pc_i[lane] + 32'd4;
        end
    end

    assign update_base_idx = update_pc_q[BHT_INDEX_BITS+1:2];
    assign update_direction_idx =
        update_base_idx ^ BHT_INDEX_BITS'(ghr_q);
    assign update_btb_idx = update_pc_q[BTB_INDEX_BITS+1:2];
    assign update_btb_tag =
        update_pc_q[PC_WIDTH-1:BTB_INDEX_BITS+2];

    always_comb begin
        update_direction_counter_current =
            direction_pht_q[update_direction_idx];
        if (table_update_valid_q && table_update_direction_we_q &&
            (table_update_direction_idx_q == update_direction_idx)) begin
            update_direction_counter_current =
                table_update_direction_counter_q;
        end
        update_direction_counter_next = sat_counter_update(
            update_direction_counter_current, update_taken_q
        );
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            update_valid_q <= 1'b0;
            table_update_valid_q <= 1'b0;
        end else begin
            update_valid_q <= update_valid_i;
            table_update_valid_q <= update_valid_q;
        end
    end

    // Wide pipeline payloads are valid-owned and intentionally reset-free.
    always_ff @(posedge clk) begin
        update_pc_q <= update_pc_i;
        update_taken_q <= update_taken_i;
        update_target_q <= update_target_i;
        update_uncond_q <= update_uncond_i;
        update_is_call_q <= update_is_call_i;
        update_is_return_q <= update_is_return_i;
        update_return_pc_q <= update_return_pc_i;

        table_update_direction_we_q <= !update_uncond_q;
        table_update_direction_idx_q <= update_direction_idx;
        table_update_direction_counter_q <= update_direction_counter_next;
        table_update_btb_idx_q <= update_btb_idx;
        table_update_btb_tag_q <= update_btb_tag;
        table_update_taken_q <= update_taken_q;
        table_update_target_q <= update_target_q;
        table_update_uncond_q <= update_uncond_q;
        table_update_is_return_q <= update_is_return_q;
    end

    // GHR and RAS state advance in the first update stage. This is required
    // for back-to-back retired branches: the following update must form its
    // gshare index from the preceding branch outcome even though the PHT write
    // itself is one stage later.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ghr_q <= '0;
            ras_count_q <= '0;
            for (int i = 0; i < BHT_ENTRIES; i = i + 1) begin
                direction_pht_q[i] <= 2'b01;
            end
            for (int b = 0; b < BTB_ENTRIES; b = b + 1) begin
                btb_valid_q[b] <= 1'b0;
            end
        end else begin
            if (update_valid_q) begin
                if (!update_uncond_q) begin
                    ghr_q <= {ghr_q[GHR_BITS-2:0], update_taken_q};
                end

                if (update_is_return_q && (ras_count_q != '0)) begin
                    ras_count_q <= ras_count_q - 1'b1;
                end else if (update_is_call_q &&
                             (ras_count_q <
                              (RAS_PTR_WIDTH+1)'(RAS_DEPTH))) begin
                    ras_count_q <= ras_count_q + 1'b1;
                end
            end

            if (table_update_valid_q) begin
                if (table_update_direction_we_q) begin
                    direction_pht_q[table_update_direction_idx_q] <=
                        table_update_direction_counter_q;
                end
                if (table_update_taken_q) begin
                    btb_valid_q[table_update_btb_idx_q] <= 1'b1;
                end
            end
        end
    end

    // BTB/RAS payload arrays have separate valid/count ownership and therefore
    // do not inherit the asynchronous reset control set.
    always_ff @(posedge clk) begin
        if (!rst && table_update_valid_q && table_update_taken_q) begin
            btb_uncond_q[table_update_btb_idx_q] <= table_update_uncond_q;
            btb_return_q[table_update_btb_idx_q] <=
                table_update_is_return_q;
            btb_tag_q[table_update_btb_idx_q] <= table_update_btb_tag_q;
            btb_target_q[table_update_btb_idx_q] <= table_update_target_q;
        end
        if (!rst && update_valid_q && update_is_call_q &&
            !update_is_return_q &&
            (ras_count_q < (RAS_PTR_WIDTH+1)'(RAS_DEPTH))) begin
            ras_q[ras_count_q[RAS_PTR_WIDTH-1:0]] <= update_return_pc_q;
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && update_valid_q && !update_uncond_q &&
            table_update_valid_q && table_update_direction_we_q &&
            (table_update_direction_idx_q == update_direction_idx)) begin
            assert (update_direction_counter_current ==
                    table_update_direction_counter_q)
                else $error("BPU consecutive PHT update bypass failed");
        end
    end
`endif
endmodule : CoreBranchPredictor
