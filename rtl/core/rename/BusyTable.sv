import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBusyTable #(
    parameter int QUERY_WIDTH = RENAME_WIDTH,
    parameter int MARK_BUSY_WIDTH = RENAME_WIDTH,
    parameter int MARK_READY_WIDTH = ISSUE_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  PhyRegNumPath [QUERY_WIDTH-1:0] query_src1_i,
    output logic [QUERY_WIDTH-1:0] query_src1_ready_o,
    input  PhyRegNumPath [QUERY_WIDTH-1:0] query_src2_i,
    output logic [QUERY_WIDTH-1:0] query_src2_ready_o,

    input  logic [MARK_BUSY_WIDTH-1:0] mark_busy_i,
    input  PhyRegNumPath [MARK_BUSY_WIDTH-1:0] mark_busy_phy_i,

    input  logic [MARK_READY_WIDTH-1:0] mark_ready_i,
    input  PhyRegNumPath [MARK_READY_WIDTH-1:0] mark_ready_phy_i
);
    logic ready_q [PHY_REG_NUM-1:0];

    function automatic logic ready_with_forward(input PhyRegNumPath phy);
        logic ready;
        begin
            ready = (phy == '0) || ready_q[phy];
            for (int w = 0; w < MARK_READY_WIDTH; w = w + 1) begin
                if (mark_ready_i[w] && (mark_ready_phy_i[w] == phy)) begin
                    ready = 1'b1;
                end
            end
            for (int b = 0; b < MARK_BUSY_WIDTH; b = b + 1) begin
                if (mark_busy_i[b] && (mark_busy_phy_i[b] == phy) && (phy != '0)) begin
                    ready = 1'b0;
                end
            end
            ready_with_forward = ready;
        end
    endfunction

    always_comb begin
        for (int q = 0; q < QUERY_WIDTH; q = q + 1) begin
            query_src1_ready_o[q] = ready_with_forward(query_src1_i[q]);
            query_src2_ready_o[q] = ready_with_forward(query_src2_i[q]);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            for (int i = 0; i < PHY_REG_NUM; i = i + 1) begin
                ready_q[i] <= (i < LOGIC_REG_NUM);
            end
        end else begin
            for (int b = 0; b < MARK_BUSY_WIDTH; b = b + 1) begin
                if (mark_busy_i[b] && (mark_busy_phy_i[b] != '0)) begin
                    ready_q[mark_busy_phy_i[b]] <= 1'b0;
                end
            end
            for (int w = 0; w < MARK_READY_WIDTH; w = w + 1) begin
                if (mark_ready_i[w]) begin
                    ready_q[mark_ready_phy_i[w]] <= 1'b1;
                end
            end
            ready_q[0] <= 1'b1;
        end
    end
endmodule : CoreBusyTable
