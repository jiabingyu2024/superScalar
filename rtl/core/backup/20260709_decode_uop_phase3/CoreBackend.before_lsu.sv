import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBackend (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic recover_i,

    input  logic [DECODE_WIDTH-1:0] decode_valid_i,
    input  CoreDecodeUop [DECODE_WIDTH-1:0] decode_uop_i,
    output logic [DECODE_WIDTH-1:0] decode_ready_o,

    output logic recover_valid_o,
    output PcPath recover_pc_o,

    output logic [RETIRE_WIDTH-1:0] commit_valid_o,
    output CoreRobEntry [RETIRE_WIDTH-1:0] commit_entry_o
);
    logic [RENAME_WIDTH-1:0] free_alloc_req;
    logic [RENAME_WIDTH-1:0] free_alloc_accept;
    logic [RENAME_WIDTH-1:0] free_alloc_valid;
    PhyRegNumPath [RENAME_WIDTH-1:0] free_alloc_phy;
    logic [RETIRE_WIDTH-1:0] free_old_valid;
    PhyRegNumPath [RETIRE_WIDTH-1:0] free_old_prd;

    logic [RENAME_WIDTH-1:0] rename_valid;
    logic [RENAME_WIDTH-1:0] rename_ready;
    CoreRenamedUop [RENAME_WIDTH-1:0] rename_uop;
    logic [RENAME_WIDTH-1:0] rob_alloc_valid;
    logic [RENAME_WIDTH-1:0] rob_alloc_ready;
    RobIndexPath [RENAME_WIDTH-1:0] rob_alloc_idx;

    PhyRegNumPath [RENAME_WIDTH-1:0] busy_src1_phy;
    PhyRegNumPath [RENAME_WIDTH-1:0] busy_src2_phy;
    logic [RENAME_WIDTH-1:0] busy_src1_ready;
    logic [RENAME_WIDTH-1:0] busy_src2_ready;

    logic [DISPATCH_WIDTH-1:0] int_push_valid;
    logic [DISPATCH_WIDTH-1:0] mem_push_valid;
    logic [DISPATCH_WIDTH-1:0] mul_push_valid;
    logic [DISPATCH_WIDTH-1:0] int_push_ready;
    logic [DISPATCH_WIDTH-1:0] mem_push_ready;
    logic [DISPATCH_WIDTH-1:0] mul_push_ready;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] int_push_uop;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] mem_push_uop;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] mul_push_uop;

    logic [INT_ISSUE_WIDTH-1:0] int_issue_ready;
    logic [INT_ISSUE_WIDTH-1:0] int_issue_valid;
    CoreRenamedUop [INT_ISSUE_WIDTH-1:0] int_issue_uop;
    logic [MEM_ISSUE_WIDTH-1:0] mem_issue_ready;
    logic [MEM_ISSUE_WIDTH-1:0] mem_issue_valid;
    CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] mem_issue_uop;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_ready;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_valid;
    CoreRenamedUop [MULDIV_ISSUE_WIDTH-1:0] mul_issue_uop;

    logic [ISSUE_WIDTH-1:0] complete_valid;
    RobIndexPath [ISSUE_WIDTH-1:0] complete_rob_idx;
    PhyRegNumPath [ISSUE_WIDTH-1:0] complete_prd;
    DataPath [ISSUE_WIDTH-1:0] complete_result;
    logic [ISSUE_WIDTH-1:0] complete_exception;
    logic [ISSUE_WIDTH-1:0][31:0] complete_exception_cause;
    logic [ISSUE_WIDTH-1:0] complete_branch_miss;
    PcPath [ISSUE_WIDTH-1:0] complete_redirect_pc;

    logic [ISSUE_WIDTH-1:0] exec_complete_valid;
    RobIndexPath [ISSUE_WIDTH-1:0] exec_complete_rob_idx;
    PhyRegNumPath [ISSUE_WIDTH-1:0] exec_complete_prd;
    DataPath [ISSUE_WIDTH-1:0] exec_complete_result;
    logic [ISSUE_WIDTH-1:0] exec_complete_exception;
    logic [ISSUE_WIDTH-1:0][31:0] exec_complete_exception_cause;
    logic [ISSUE_WIDTH-1:0] exec_complete_branch_miss;
    PcPath [ISSUE_WIDTH-1:0] exec_complete_redirect_pc;

    logic [RETIRE_WIDTH-1:0] retire_valid;
    logic [RETIRE_WIDTH-1:0] retire_ready;
    CoreRobEntry [RETIRE_WIDTH-1:0] retire_entry;
    logic [RETIRE_WIDTH-1:0] commit_valid;
    LgcRegNumPath [RETIRE_WIDTH-1:0] commit_arch;
    PhyRegNumPath [RETIRE_WIDTH-1:0] commit_prd;

    CoreFreeList u_free_list (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .alloc_req_i(free_alloc_req),
        .alloc_accept_i(free_alloc_accept),
        .alloc_valid_o(free_alloc_valid),
        .alloc_phy_o(free_alloc_phy),
        .free_valid_i(free_old_valid),
        .free_phy_i(free_old_prd),
        .free_ready_o(),
        .empty_o(),
        .full_o()
    );

    CoreRenameUnit u_rename (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .recover_i(recover_i),
        .in_valid_i(decode_valid_i),
        .in_uop_i(decode_uop_i),
        .in_ready_o(decode_ready_o),
        .free_alloc_req_o(free_alloc_req),
        .free_alloc_accept_o(free_alloc_accept),
        .free_alloc_valid_i(free_alloc_valid),
        .free_alloc_phy_i(free_alloc_phy),
        .rob_alloc_valid_o(rob_alloc_valid),
        .rob_alloc_ready_i(rob_alloc_ready),
        .rob_alloc_idx_i(rob_alloc_idx),
        .busy_query_src1_o(busy_src1_phy),
        .busy_query_src1_ready_i(busy_src1_ready),
        .busy_query_src2_o(busy_src2_phy),
        .busy_query_src2_ready_i(busy_src2_ready),
        .out_valid_o(rename_valid),
        .out_uop_o(rename_uop),
        .out_ready_i(rename_ready),
        .commit_valid_i(commit_valid),
        .commit_arch_i(commit_arch),
        .commit_prd_i(commit_prd)
    );

    CoreBusyTable u_busy (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .query_src1_i(busy_src1_phy),
        .query_src1_ready_o(busy_src1_ready),
        .query_src2_i(busy_src2_phy),
        .query_src2_ready_o(busy_src2_ready),
        .mark_busy_i(free_alloc_accept),
        .mark_busy_phy_i(free_alloc_phy),
        .mark_ready_i(complete_valid),
        .mark_ready_phy_i(complete_prd)
    );

    CoreROB u_rob (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .alloc_valid_i(rob_alloc_valid),
        .alloc_uop_i(rename_uop),
        .alloc_ready_o(rob_alloc_ready),
        .alloc_idx_o(rob_alloc_idx),
        .complete_valid_i(complete_valid),
        .complete_idx_i(complete_rob_idx),
        .complete_result_i(complete_result),
        .complete_exception_i(complete_exception),
        .complete_exception_cause_i(complete_exception_cause),
        .complete_branch_miss_i(complete_branch_miss),
        .complete_redirect_pc_i(complete_redirect_pc),
        .retire_ready_i(retire_ready),
        .retire_valid_o(retire_valid),
        .retire_entry_o(retire_entry),
        .empty_o(),
        .full_o()
    );

    CoreDispatchUnit u_dispatch (
        .in_valid_i(rename_valid),
        .in_uop_i(rename_uop),
        .in_ready_o(rename_ready),
        .int_valid_o(int_push_valid),
        .mem_valid_o(mem_push_valid),
        .mul_valid_o(mul_push_valid),
        .int_uop_o(int_push_uop),
        .mem_uop_o(mem_push_uop),
        .mul_uop_o(mul_push_uop),
        .int_ready_i(int_push_ready),
        .mem_ready_i(mem_push_ready),
        .mul_ready_i(mul_push_ready)
    );

    CoreIntIssueQueue u_int_iq (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(int_push_valid),
        .push_uop_i(int_push_uop),
        .push_ready_o(int_push_ready),
        .wakeup_valid_i(complete_valid),
        .wakeup_phy_i(complete_prd),
        .issue_ready_i(int_issue_ready),
        .issue_valid_o(int_issue_valid),
        .issue_uop_o(int_issue_uop)
    );

    CoreMemIssueQueue u_mem_iq (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(mem_push_valid),
        .push_uop_i(mem_push_uop),
        .push_ready_o(mem_push_ready),
        .wakeup_valid_i(complete_valid),
        .wakeup_phy_i(complete_prd),
        .issue_ready_i(mem_issue_ready),
        .issue_valid_o(mem_issue_valid),
        .issue_uop_o(mem_issue_uop)
    );

    CoreMulDivIssueQueue u_mul_iq (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(mul_push_valid),
        .push_uop_i(mul_push_uop),
        .push_ready_o(mul_push_ready),
        .wakeup_valid_i(complete_valid),
        .wakeup_phy_i(complete_prd),
        .issue_ready_i(mul_issue_ready),
        .issue_valid_o(mul_issue_valid),
        .issue_uop_o(mul_issue_uop)
    );

    CoreExecuteCluster u_execute (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .int_issue_ready_o(int_issue_ready),
        .int_issue_valid_i(int_issue_valid),
        .int_issue_uop_i(int_issue_uop),
        .mem_issue_ready_o(mem_issue_ready),
        .mem_issue_valid_i(mem_issue_valid),
        .mem_issue_uop_i(mem_issue_uop),
        .mul_issue_ready_o(mul_issue_ready),
        .mul_issue_valid_i(mul_issue_valid),
        .mul_issue_uop_i(mul_issue_uop),
        .complete_valid_o(exec_complete_valid),
        .complete_rob_idx_o(exec_complete_rob_idx),
        .complete_prd_o(exec_complete_prd),
        .complete_result_o(exec_complete_result),
        .complete_exception_o(exec_complete_exception),
        .complete_exception_cause_o(exec_complete_exception_cause),
        .complete_branch_miss_o(exec_complete_branch_miss),
        .complete_redirect_pc_o(exec_complete_redirect_pc)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i || recover_i) begin
            complete_valid <= '0;
            complete_rob_idx <= '0;
            complete_prd <= '0;
            complete_result <= '0;
            complete_exception <= '0;
            complete_exception_cause <= '0;
            complete_branch_miss <= '0;
            complete_redirect_pc <= '0;
        end else begin
            complete_valid <= exec_complete_valid;
            complete_rob_idx <= exec_complete_rob_idx;
            complete_prd <= exec_complete_prd;
            complete_result <= exec_complete_result;
            complete_exception <= exec_complete_exception;
            complete_exception_cause <= exec_complete_exception_cause;
            complete_branch_miss <= exec_complete_branch_miss;
            complete_redirect_pc <= exec_complete_redirect_pc;
        end
    end

    CoreCommitUnit u_commit (
        .rob_valid_i(retire_valid),
        .rob_ready_o(retire_ready),
        .rob_entry_i(retire_entry),
        .commit_valid_o(commit_valid),
        .commit_arch_o(commit_arch),
        .commit_prd_o(commit_prd),
        .free_old_prd_o(free_old_prd),
        .free_old_valid_o(free_old_valid),
        .recover_valid_o(recover_valid_o),
        .recover_pc_o(recover_pc_o)
    );

    assign commit_valid_o = commit_valid;
    assign commit_entry_o = retire_entry;
endmodule : CoreBackend
