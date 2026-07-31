import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreMemIssueQueue (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic [DISPATCH_WIDTH-1:0] push_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] push_uop_i,
    output logic [DISPATCH_WIDTH-1:0] push_ready_o,
    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,
    input  logic [MEM_ISSUE_WIDTH-1:0] issue_ready_i,
    output logic [MEM_ISSUE_WIDTH-1:0] issue_valid_o,
    output CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] issue_uop_o,
    output logic head_not_ready_o,
    output logic younger_ready_behind_head_o
);
    CoreCompressedQueue #(
        .DEPTH(MEM_IQ_DEPTH),
        .ISSUE_PORTS(MEM_ISSUE_WIDTH),
        .HEAD_ONLY(1'b1)
    ) u_queue (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .push_valid_i(push_valid_i),
        .push_uop_i(push_uop_i),
        .push_ready_o(push_ready_o),
        .wakeup_valid_i(wakeup_valid_i),
        .wakeup_phy_i(wakeup_phy_i),
        .issue_ready_i(issue_ready_i),
        .issue_valid_o(issue_valid_o),
        .issue_uop_o(issue_uop_o),
        .empty_o(),
        .full_o(),
        .head_not_ready_o(head_not_ready_o),
        .younger_ready_behind_head_o(younger_ready_behind_head_o)
    );
endmodule : CoreMemIssueQueue
