//==============================================================================
// 128-entry direct-mapped BTB + 8-bit gshare + 16-entry resolved-update RAS.
//
// Predictor payload arrays are not reset. Valid vectors mask uninitialized
// contents, preserving LUTRAM inference and avoiding large reset cones.
// The RAS is updated only by resolved calls/returns, so wrong-path fetches do
// not require checkpoint/rollback state.
//==============================================================================
`include "cpu_defines.svh"

module bpu_top #(
    parameter bit ENABLE_GSHARE = 1'b1,
    parameter bit ENABLE_RAS    = 1'b1
) (
    input  logic                i_clk,
    input  logic                i_rst_n,
    input  logic [`PC_BUS]      i_pc_cur,

    input  logic                i_update_en,
    input  logic                i_update_taken,
    input  logic [`PC_BUS]      i_update_bpu_target,
    input  logic [`PC_BUS]      i_update_pc,
    input  logic [7:0]          i_update_pht_idx,
    input  logic                i_update_is_cond,
    input  logic                i_update_is_call,
    input  logic                i_update_is_return,

    output logic                o_predict_taken,
    output logic [`PC_BUS]      o_predict_target,
    output logic [7:0]          o_predict_pht_idx
);

    localparam int BTB_ENTRIES = 128;
    localparam int BTB_IDX_W   = 7;
    localparam int BTB_TAG_W   = `PC_WID - BTB_IDX_W - 2;
    localparam int PHT_ENTRIES = 256;
    localparam int RAS_DEPTH   = 16;

    localparam logic [1:0] BTB_COND   = 2'b00;
    localparam logic [1:0] BTB_UNCOND = 2'b01;
    localparam logic [1:0] BTB_RETURN = 2'b10;

    (* ram_style = "distributed" *) logic [BTB_TAG_W-1:0] btb_tag_mem
        [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) logic [`PC_BUS] btb_target_mem
        [0:BTB_ENTRIES-1];
    (* ram_style = "distributed" *) logic [1:0] btb_type_mem
        [0:BTB_ENTRIES-1];
    logic [BTB_ENTRIES-1:0] btb_valid_q;

    (* ram_style = "distributed" *) logic [1:0] pht_counter_mem
        [0:PHT_ENTRIES-1];
    logic [PHT_ENTRIES-1:0] pht_valid_q;
    logic [7:0] ghr_q;

    (* ram_style = "distributed" *) logic [`PC_BUS] ras_mem [0:RAS_DEPTH-1];
    logic [3:0] ras_sp_q;
    logic [4:0] ras_count_q;

    logic [BTB_IDX_W-1:0] rd_btb_idx;
    logic [BTB_IDX_W-1:0] wr_btb_idx;
    logic [BTB_TAG_W-1:0] rd_btb_tag;
    logic [BTB_TAG_W-1:0] wr_btb_tag;
    logic [7:0] rd_pht_idx;
    logic btb_hit;
    logic [1:0] rd_btb_type;
    logic [3:0] ras_top_idx;

    assign rd_btb_idx = i_pc_cur[BTB_IDX_W+1:2];
    assign wr_btb_idx = i_update_pc[BTB_IDX_W+1:2];
    assign rd_btb_tag = i_pc_cur[`PC_WID-1:BTB_IDX_W+2];
    assign wr_btb_tag = i_update_pc[`PC_WID-1:BTB_IDX_W+2];
    assign rd_pht_idx = i_pc_cur[9:2] ^
                        (ENABLE_GSHARE ? ghr_q : 8'd0);
    assign o_predict_pht_idx = rd_pht_idx;
    assign btb_hit = btb_valid_q[rd_btb_idx] &&
                     (btb_tag_mem[rd_btb_idx] == rd_btb_tag);
    assign rd_btb_type = btb_type_mem[rd_btb_idx];
    assign ras_top_idx = ras_sp_q - 4'd1;

    always_comb begin
        o_predict_taken = 1'b0;
        o_predict_target = btb_target_mem[rd_btb_idx];

        if (btb_hit) begin
            if (rd_btb_type == BTB_COND) begin
                o_predict_taken = pht_valid_q[rd_pht_idx] &&
                                  pht_counter_mem[rd_pht_idx][1];
            end else begin
                o_predict_taken = 1'b1;
            end

            if (ENABLE_RAS && (rd_btb_type == BTB_RETURN) &&
                (ras_count_q != 0)) begin
                o_predict_target = ras_mem[ras_top_idx];
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            btb_valid_q <= '0;
            pht_valid_q <= '0;
            ghr_q       <= '0;
            ras_sp_q    <= '0;
            ras_count_q <= '0;
        end else if (i_update_en) begin
            btb_valid_q[wr_btb_idx] <= 1'b1;

            if (i_update_is_cond) begin
                pht_valid_q[i_update_pht_idx] <= 1'b1;
                ghr_q <= {ghr_q[6:0], i_update_taken};
            end

            if (ENABLE_RAS && i_update_is_return) begin
                if (ras_count_q != 0) begin
                    ras_sp_q    <= ras_sp_q - 4'd1;
                    ras_count_q <= ras_count_q - 5'd1;
                end
            end else if (ENABLE_RAS && i_update_is_call) begin
                ras_sp_q <= ras_sp_q + 4'd1;
                if (ras_count_q != RAS_DEPTH) begin
                    ras_count_q <= ras_count_q + 5'd1;
                end
            end
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_update_en) begin
            btb_tag_mem[wr_btb_idx]    <= wr_btb_tag;
            btb_target_mem[wr_btb_idx] <= i_update_bpu_target;
            btb_type_mem[wr_btb_idx]   <= i_update_is_cond ? BTB_COND :
                                          (i_update_is_return ? BTB_RETURN :
                                                                BTB_UNCOND);

            if (i_update_is_cond) begin
                if (!pht_valid_q[i_update_pht_idx]) begin
                    pht_counter_mem[i_update_pht_idx] <=
                        i_update_taken ? 2'b10 : 2'b00;
                end else if (i_update_taken) begin
                    if (pht_counter_mem[i_update_pht_idx] != 2'b11) begin
                        pht_counter_mem[i_update_pht_idx] <=
                            pht_counter_mem[i_update_pht_idx] + 2'b01;
                    end
                end else if (pht_counter_mem[i_update_pht_idx] != 2'b00) begin
                    pht_counter_mem[i_update_pht_idx] <=
                        pht_counter_mem[i_update_pht_idx] - 2'b01;
                end
            end

            if (ENABLE_RAS && i_update_is_call) begin
                // Preserve the complete address; never drop the 0x8000_0000
                // region bits as happened in the historical failed RAS trial.
                ras_mem[ras_sp_q] <= i_update_pc + 32'd4;
            end
        end
    end

endmodule
