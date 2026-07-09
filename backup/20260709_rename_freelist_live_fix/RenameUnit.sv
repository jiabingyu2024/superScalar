import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreRenameUnit (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic recover_i,

    input  logic [RENAME_WIDTH-1:0] in_valid_i,
    input  CoreDecodeUop [RENAME_WIDTH-1:0] in_uop_i,
    output logic [RENAME_WIDTH-1:0] in_ready_o,

    output logic [RENAME_WIDTH-1:0] free_alloc_req_o,
    output logic [RENAME_WIDTH-1:0] free_alloc_accept_o,
    input  logic [RENAME_WIDTH-1:0] free_alloc_valid_i,
    input  PhyRegNumPath [RENAME_WIDTH-1:0] free_alloc_phy_i,

    output logic [RENAME_WIDTH-1:0] rob_alloc_valid_o,
    input  logic [RENAME_WIDTH-1:0] rob_alloc_ready_i,
    input  RobIndexPath [RENAME_WIDTH-1:0] rob_alloc_idx_i,

    output PhyRegNumPath [RENAME_WIDTH-1:0] busy_query_src1_o,
    input  logic [RENAME_WIDTH-1:0] busy_query_src1_ready_i,
    output PhyRegNumPath [RENAME_WIDTH-1:0] busy_query_src2_o,
    input  logic [RENAME_WIDTH-1:0] busy_query_src2_ready_i,

    output logic [RENAME_WIDTH-1:0] out_valid_o,
    output CoreRenamedUop [RENAME_WIDTH-1:0] out_uop_o,
    input  logic [RENAME_WIDTH-1:0] out_ready_i,

    input  logic [RETIRE_WIDTH-1:0] commit_valid_i,
    input  LgcRegNumPath [RETIRE_WIDTH-1:0] commit_arch_i,
    input  PhyRegNumPath [RETIRE_WIDTH-1:0] commit_prd_i,

    output PhyRegNumPath [LOGIC_REG_NUM-1:0] arat_map_o
);
    PhyRegNumPath srat_q [LOGIC_REG_NUM-1:0];
    PhyRegNumPath arat_q [LOGIC_REG_NUM-1:0];

    logic [RENAME_WIDTH-1:0] needs_prd;
    logic [RENAME_WIDTH-1:0] lane_fire;
    PhyRegNumPath current_map [RENAME_WIDTH-1:0];

    function automatic PhyRegNumPath map_with_older_lane(
        input LgcRegNumPath arch,
        input int lane
    );
        PhyRegNumPath mapped;
        begin
            mapped = srat_q[arch];
            for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
                if ((i < lane) &&
                    lane_fire[i] &&
                    out_uop_o[i].alloc_prd &&
                    (out_uop_o[i].uop.rd == arch) &&
                    (arch != '0)) begin
                    mapped = out_uop_o[i].prd;
                end
            end
            map_with_older_lane = mapped;
        end
    endfunction

    always_comb begin
        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            needs_prd[i] = in_valid_i[i] &&
                           in_uop_i[i].writes_rd &&
                           (in_uop_i[i].rd != '0);
            free_alloc_req_o[i] = needs_prd[i];
            free_alloc_accept_o[i] = 1'b0;
            rob_alloc_valid_o[i] = 1'b0;
            in_ready_o[i] = 1'b0;
            out_valid_o[i] = 1'b0;
            out_uop_o[i] = '0;
            lane_fire[i] = 1'b0;
            current_map[i] = srat_q[in_uop_i[i].rd];
        end
        for (int r = 0; r < LOGIC_REG_NUM; r = r + 1) begin
            arat_map_o[r] = arat_q[r];
            for (int c = 0; c < RETIRE_WIDTH; c = c + 1) begin
                if (commit_valid_i[c] && (commit_arch_i[c] == LgcRegNumPath'(r)) && (r != 0)) begin
                    arat_map_o[r] = commit_prd_i[c];
                end
            end
        end

        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            out_uop_o[i].valid = in_valid_i[i];
            out_uop_o[i].uop = in_uop_i[i];
            out_uop_o[i].rob_idx = rob_alloc_idx_i[i];
            out_uop_o[i].prs1 = map_with_older_lane(in_uop_i[i].rs1, i);
            out_uop_o[i].prs2 = map_with_older_lane(in_uop_i[i].rs2, i);
            busy_query_src1_o[i] = out_uop_o[i].prs1;
            busy_query_src2_o[i] = out_uop_o[i].prs2;
            out_uop_o[i].old_prd = map_with_older_lane(in_uop_i[i].rd, i);
            out_uop_o[i].prd = needs_prd[i] ? free_alloc_phy_i[i] : '0;
            out_uop_o[i].alloc_prd = needs_prd[i];
            out_uop_o[i].src1_ready = busy_query_src1_ready_i[i] || (out_uop_o[i].prs1 == '0);
            out_uop_o[i].src2_ready = busy_query_src2_ready_i[i] || (out_uop_o[i].prs2 == '0);

            out_valid_o[i] = in_valid_i[i] &&
                             rob_alloc_ready_i[i] &&
                             (!needs_prd[i] || free_alloc_valid_i[i]);
            if ((i != 0) && !lane_fire[i-1]) begin
                out_valid_o[i] = 1'b0;
            end
            lane_fire[i] = out_valid_o[i] && out_ready_i[i];
            in_ready_o[i] = lane_fire[i];
            rob_alloc_valid_o[i] = lane_fire[i];
            free_alloc_accept_o[i] = lane_fire[i] && needs_prd[i];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int r = 0; r < LOGIC_REG_NUM; r = r + 1) begin
                srat_q[r] <= PhyRegNumPath'(r);
                arat_q[r] <= PhyRegNumPath'(r);
            end
        end else begin
            if (clear_i || recover_i) begin
                for (int r = 0; r < LOGIC_REG_NUM; r = r + 1) begin
                    srat_q[r] <= arat_map_o[r];
                end
            end else begin
                for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
                    if (lane_fire[i] && out_uop_o[i].alloc_prd) begin
                        srat_q[out_uop_o[i].uop.rd] <= out_uop_o[i].prd;
                    end
                end
            end

            for (int c = 0; c < RETIRE_WIDTH; c = c + 1) begin
                if (commit_valid_i[c] && (commit_arch_i[c] != '0)) begin
                    arat_q[commit_arch_i[c]] <= commit_prd_i[c];
                end
            end
        end
    end
endmodule : CoreRenameUnit
