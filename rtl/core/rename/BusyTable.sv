import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBusyTable #(
    parameter int STABLE_QUERY_WIDTH = DISPATCH_WIDTH,
    parameter int MARK_BUSY_WIDTH = RENAME_WIDTH,
    parameter int MARK_READY_WIDTH = ISSUE_WIDTH
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic recover_i,
    input  PhyRegNumPath [LOGIC_REG_NUM-1:0] recover_map_i,

    input  PhyRegNumPath [STABLE_QUERY_WIDTH-1:0] stable_query_src1_i,
    output logic [STABLE_QUERY_WIDTH-1:0] stable_query_src1_ready_o,
    input  PhyRegNumPath [STABLE_QUERY_WIDTH-1:0] stable_query_src2_i,
    output logic [STABLE_QUERY_WIDTH-1:0] stable_query_src2_ready_o,

    input  logic [MARK_BUSY_WIDTH-1:0] mark_busy_i,
    input  PhyRegNumPath [MARK_BUSY_WIDTH-1:0] mark_busy_phy_i,

    input  logic [MARK_READY_WIDTH-1:0] mark_ready_i,
    input  PhyRegNumPath [MARK_READY_WIDTH-1:0] mark_ready_phy_i
);
    logic ready_q [PHY_REG_NUM-1:0];

    // Registered dispatch-buffer owners cannot depend on a younger same-cycle
    // allocation, so their query needs completion forwarding but not the
    // rename mark-busy overlay. Keeping this as a separate cone also avoids a
    // dispatch-pop -> rename-fire -> BusyTable -> dispatch combinational loop.
    function automatic logic stable_ready_with_forward(
        input PhyRegNumPath phy
    );
        logic ready;
        begin
            ready = (phy == '0) || ready_q[phy];
            for (int w = 0; w < MARK_READY_WIDTH; w = w + 1) begin
                if (mark_ready_i[w] && (mark_ready_phy_i[w] == phy)) begin
                    ready = 1'b1;
                end
            end
            stable_ready_with_forward = ready;
        end
    endfunction

    always_comb begin
        for (int q = 0; q < STABLE_QUERY_WIDTH; q = q + 1) begin
            stable_query_src1_ready_o[q] =
                stable_ready_with_forward(stable_query_src1_i[q]);
            stable_query_src2_ready_o[q] =
                stable_ready_with_forward(stable_query_src2_i[q]);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < PHY_REG_NUM; i = i + 1) begin
                ready_q[i] <= (i < LOGIC_REG_NUM);
            end
        end else if (clear_i) begin
            for (int i = 0; i < PHY_REG_NUM; i = i + 1) begin
                ready_q[i] <= (i < LOGIC_REG_NUM);
            end
        end else if (recover_i) begin
            for (int i = 0; i < PHY_REG_NUM; i = i + 1) begin
                ready_q[i] <= 1'b0;
            end
            for (int r = 0; r < LOGIC_REG_NUM; r = r + 1) begin
                ready_q[recover_map_i[r]] <= 1'b1;
            end
            ready_q[0] <= 1'b1;
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
