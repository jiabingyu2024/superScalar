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
    output CoreRobEntry [RETIRE_WIDTH-1:0] commit_entry_o,

    DramAccessIF dmem
`ifdef VERILATOR_TB
    ,
    output logic [2:0] perf_dispatch_count_o,
    output logic [2:0] perf_issue_count_o,
    output logic [2:0] perf_int_issue_count_o,
    output logic [2:0] perf_mem_issue_count_o,
    output logic [2:0] perf_mul_issue_count_o,
    output logic perf_dispatch_block_o,
    output logic perf_issue_block_o,
    output logic perf_rob_full_o,
    output logic perf_int_iq_block_o,
    output logic perf_mem_iq_block_o,
    output logic perf_mul_iq_block_o,
    output logic perf_rob_head_not_done_o,
    output logic perf_rob_head_int_o,
    output logic perf_rob_head_mem_o,
    output logic perf_rob_head_mul_o,
    output logic perf_rob_head_other_o,
    output logic perf_free_list_empty_o,
    output logic perf_store_buffer_block_o,
    output logic perf_serial_block_o,
    output logic perf_load_pending_o,
    output logic perf_mem_issue_block_o,
    output logic perf_int_blocked_by_load_o,
    output logic perf_mem_req_valid_o,
    output logic perf_mem_partial_alias_o,
    output logic perf_mem_no_alias_o,
    output logic perf_mem_forward_o,
    output logic perf_mem_iq_head_not_ready_o,
    output logic perf_mem_iq_younger_ready_o,
    output logic perf_mul_op_o,
    output logic perf_div_op_o,
    output logic perf_rem_op_o,
    output logic perf_muldiv_busy_o
`endif
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
    TubeTypePath [DISPATCH_WIDTH-1:0] dispatch_tube;

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
    logic [ISSUE_WIDTH-1:0] complete_csr_write;
    logic [ISSUE_WIDTH-1:0][11:0] complete_csr_addr;
    DataPath [ISSUE_WIDTH-1:0] complete_csr_wdata;

    logic [ISSUE_WIDTH-1:0] exec_complete_valid;
    RobIndexPath [ISSUE_WIDTH-1:0] exec_complete_rob_idx;
    PhyRegNumPath [ISSUE_WIDTH-1:0] exec_complete_prd;
    DataPath [ISSUE_WIDTH-1:0] exec_complete_result;
    logic [ISSUE_WIDTH-1:0] exec_complete_exception;
    logic [ISSUE_WIDTH-1:0][31:0] exec_complete_exception_cause;
    logic [ISSUE_WIDTH-1:0] exec_complete_branch_miss;
    PcPath [ISSUE_WIDTH-1:0] exec_complete_redirect_pc;
    logic [ISSUE_WIDTH-1:0] exec_complete_csr_write;
    logic [ISSUE_WIDTH-1:0][11:0] exec_complete_csr_addr;
    DataPath [ISSUE_WIDTH-1:0] exec_complete_csr_wdata;
    logic [ISSUE_WIDTH-1:0][11:0] csr_read_addr;
    DataPath [ISSUE_WIDTH-1:0] csr_read_data;
    logic [1:0] csr_priv_mode;

    logic [RETIRE_WIDTH-1:0] retire_valid;
    logic [RETIRE_WIDTH-1:0] retire_ready;
    CoreRobEntry [RETIRE_WIDTH-1:0] retire_entry;
    logic [RETIRE_WIDTH-1:0] commit_valid;
    LgcRegNumPath [RETIRE_WIDTH-1:0] commit_arch;
    PhyRegNumPath [RETIRE_WIDTH-1:0] commit_prd;
    RobIndexPath [RETIRE_WIDTH-1:0] commit_rob_idx;
    logic store_push_valid;
    RobIndexPath store_push_rob_idx;
    AddrPath store_push_addr;
    DataPath store_push_data;
    logic [3:0] store_push_mask;
    logic store_push_ready;
    logic store_buffer_empty;
    logic load_query_valid;
    AddrPath load_query_addr;
    logic [3:0] load_query_mask;
    logic load_forward_hit;
    logic load_forward_full;
    DataPath load_forward_data;
    logic execute_load_pending;
    logic execute_mem_req_valid;
    logic execute_mem_partial_alias;
    logic execute_mem_no_alias;
    logic execute_mem_forward;
    logic execute_muldiv_busy;
    logic mem_iq_head_not_ready;
    logic mem_iq_younger_ready;
    logic rob_empty;
    logic rob_full;
    logic free_list_empty;
    logic serial_inflight_q;
    logic serial_alloc;
    logic serial_retire;
    logic serial_block;
    logic [DECODE_WIDTH-1:0] decode_valid_to_rename;
    logic [DECODE_WIDTH-1:0] decode_ready_from_rename;
    PhyRegNumPath [LOGIC_REG_NUM-1:0] srat_map;
    PhyRegNumPath [LOGIC_REG_NUM-1:0] arat_map;

    always_comb begin
        serial_block = serial_inflight_q;
        serial_alloc = 1'b0;
        serial_retire = 1'b0;
        decode_valid_to_rename = decode_valid_i;
        decode_ready_o = decode_ready_from_rename;

        for (int i = 0; i < DECODE_WIDTH; i = i + 1) begin
            dispatch_tube[i] = decode_uop_i[i].tube;
            if (serial_block) begin
                decode_valid_to_rename[i] = 1'b0;
                decode_ready_o[i] = 1'b0;
            end
            if (decode_valid_i[i] && decode_uop_i[i].is_serial) begin
                if (serial_block || !rob_empty || (i != 0)) begin
                    decode_valid_to_rename[i] = 1'b0;
                    decode_ready_o[i] = 1'b0;
                end
                if (i == 0) begin
                    for (int y = 1; y < DECODE_WIDTH; y = y + 1) begin
                        decode_valid_to_rename[y] = 1'b0;
                        decode_ready_o[y] = 1'b0;
                    end
                end
            end
            if (rob_alloc_valid[i] && rename_uop[i].uop.is_serial) begin
                serial_alloc = 1'b1;
            end
        end

        for (int c = 0; c < RETIRE_WIDTH; c = c + 1) begin
            if (commit_valid[c] && retire_entry[c].uop.is_serial) begin
                serial_retire = 1'b1;
            end
        end
    end

    CoreFreeList u_free_list (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .recover_i(recover_i),
        .recover_map_i(arat_map),
        .live_map_i(srat_map),
        .alloc_req_i(free_alloc_req),
        .alloc_accept_i(free_alloc_accept),
        .alloc_valid_o(free_alloc_valid),
        .alloc_phy_o(free_alloc_phy),
        .free_valid_i(free_old_valid),
        .free_phy_i(free_old_prd),
        .free_ready_o(),
        .empty_o(free_list_empty),
        .full_o()
    );

    CoreRenameUnit u_rename (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .recover_i(recover_i),
        .in_valid_i(decode_valid_to_rename),
        .in_uop_i(decode_uop_i),
        .in_ready_o(decode_ready_from_rename),
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
        .commit_prd_i(commit_prd),
        .srat_map_o(srat_map),
        .arat_map_o(arat_map)
    );

    CoreBusyTable u_busy (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .recover_i(recover_i),
        .recover_map_i(arat_map),
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
        .complete_csr_write_i(complete_csr_write),
        .complete_csr_addr_i(complete_csr_addr),
        .complete_csr_wdata_i(complete_csr_wdata),
        .retire_ready_i(retire_ready),
        .retire_valid_o(retire_valid),
        .retire_entry_o(retire_entry),
        .empty_o(rob_empty),
        .full_o(rob_full)
    );

    CoreDispatchUnit u_dispatch (
        .in_valid_i(rename_valid),
        .in_uop_i(rename_uop),
        .in_tube_i(dispatch_tube),
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
        .issue_uop_o(mem_issue_uop),
        .head_not_ready_o(mem_iq_head_not_ready),
        .younger_ready_behind_head_o(mem_iq_younger_ready)
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
        .complete_redirect_pc_o(exec_complete_redirect_pc),
        .complete_csr_write_o(exec_complete_csr_write),
        .complete_csr_addr_o(exec_complete_csr_addr),
        .complete_csr_wdata_o(exec_complete_csr_wdata),
        .csr_read_addr_o(csr_read_addr),
        .csr_read_data_i(csr_read_data),
        .csr_priv_mode_i(csr_priv_mode),
        .store_push_valid_o(store_push_valid),
        .store_push_rob_idx_o(store_push_rob_idx),
        .store_push_addr_o(store_push_addr),
        .store_push_data_o(store_push_data),
        .store_push_mask_o(store_push_mask),
        .store_push_ready_i(store_push_ready),
        .store_buffer_empty_i(store_buffer_empty),
        .load_query_valid_o(load_query_valid),
        .load_query_addr_o(load_query_addr),
        .load_query_mask_o(load_query_mask),
        .load_forward_hit_i(load_forward_hit),
        .load_forward_full_i(load_forward_full),
        .load_forward_data_i(load_forward_data),
        .perf_load_pending_o(execute_load_pending),
        .perf_mem_req_valid_o(execute_mem_req_valid),
        .perf_mem_req_partial_alias_o(execute_mem_partial_alias),
        .perf_mem_req_no_alias_o(execute_mem_no_alias),
        .perf_mem_req_forward_o(execute_mem_forward),
        .perf_muldiv_busy_o(execute_muldiv_busy),
        .dmem(dmem)
    );

    CoreStoreBuffer u_store_buffer (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(store_push_valid),
        .push_rob_idx_i(store_push_rob_idx),
        .push_addr_i(store_push_addr),
        .push_data_i(store_push_data),
        .push_mask_i(store_push_mask),
        .push_ready_o(store_push_ready),
        .commit_valid_i(commit_valid),
        .commit_rob_idx_i(commit_rob_idx),
        .load_query_valid_i(load_query_valid),
        .load_query_addr_i(load_query_addr),
        .load_query_mask_i(load_query_mask),
        .load_forward_hit_o(load_forward_hit),
        .load_forward_full_o(load_forward_full),
        .load_forward_data_o(load_forward_data),
        .empty_o(store_buffer_empty),
        .dmem(dmem)
    );

    // Only valid carries reset/flush state. Completion payload is ignored while
    // valid is low and is overwritten on the next active cycle. Keeping the
    // wide payload off reset reduces FPGA control-set and reset-fanout cost.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            complete_valid <= '0;
        end else if (clear_i || recover_i) begin
            complete_valid <= '0;
        end else begin
            complete_valid <= exec_complete_valid;
            complete_rob_idx <= exec_complete_rob_idx;
            complete_prd <= exec_complete_prd;
            complete_result <= exec_complete_result;
            complete_exception <= exec_complete_exception;
            complete_exception_cause <= exec_complete_exception_cause;
            complete_branch_miss <= exec_complete_branch_miss;
            complete_redirect_pc <= exec_complete_redirect_pc;
            complete_csr_write <= exec_complete_csr_write;
            complete_csr_addr <= exec_complete_csr_addr;
            complete_csr_wdata <= exec_complete_csr_wdata;
        end
    end

    CoreCommitUnit u_commit (
        .clk(clk),
        .rst(rst),
        .rob_valid_i(retire_valid),
        .rob_ready_o(retire_ready),
        .rob_entry_i(retire_entry),
        .csr_read_addr_i(csr_read_addr),
        .csr_read_data_o(csr_read_data),
        .csr_priv_mode_o(csr_priv_mode),
        .commit_valid_o(commit_valid),
        .commit_arch_o(commit_arch),
        .commit_prd_o(commit_prd),
        .free_old_prd_o(free_old_prd),
        .free_old_valid_o(free_old_valid),
        .recover_valid_o(recover_valid_o),
        .recover_pc_o(recover_pc_o)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            serial_inflight_q <= 1'b0;
        end else if (clear_i || recover_i) begin
            serial_inflight_q <= 1'b0;
        end else begin
            serial_inflight_q <= (serial_inflight_q || serial_alloc) && !serial_retire;
        end
    end

    always_comb begin
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            commit_rob_idx[i] = retire_entry[i].rob_idx;
        end
    end

`ifdef VERILATOR_TB
    always_comb begin
        perf_dispatch_count_o = '0;
        perf_issue_count_o = '0;
        perf_int_issue_count_o = '0;
        perf_mem_issue_count_o = '0;
        perf_mul_issue_count_o = '0;
        perf_int_iq_block_o = |(int_push_valid & ~int_push_ready);
        perf_mem_iq_block_o = |(mem_push_valid & ~mem_push_ready);
        perf_mul_iq_block_o = |(mul_push_valid & ~mul_push_ready);
        perf_dispatch_block_o = (|decode_valid_i) &&
                                (rob_full || free_list_empty || serial_block ||
                                 perf_int_iq_block_o || perf_mem_iq_block_o ||
                                 perf_mul_iq_block_o);
        perf_issue_block_o = |(int_issue_valid & ~int_issue_ready) ||
                             |(mem_issue_valid & ~mem_issue_ready) ||
                             |(mul_issue_valid & ~mul_issue_ready);
        perf_rob_full_o = rob_full;
        perf_rob_head_not_done_o = !rob_empty && !retire_valid[0];
        perf_rob_head_int_o = 1'b0;
        perf_rob_head_mem_o = 1'b0;
        perf_rob_head_mul_o = 1'b0;
        perf_rob_head_other_o = 1'b0;
        perf_free_list_empty_o = free_list_empty;
        perf_store_buffer_block_o = mem_issue_valid[0] &&
                                    mem_issue_uop[0].uop.is_store &&
                                    !store_push_ready;
        perf_serial_block_o = serial_block;
        perf_load_pending_o = execute_load_pending;
        perf_mem_issue_block_o = |(mem_issue_valid & ~mem_issue_ready);
        perf_int_blocked_by_load_o = perf_load_pending_o &&
                                     |(int_issue_valid & ~int_issue_ready);
        perf_mem_req_valid_o = execute_mem_req_valid;
        perf_mem_partial_alias_o = execute_mem_partial_alias;
        perf_mem_no_alias_o = execute_mem_no_alias;
        perf_mem_forward_o = execute_mem_forward;
        perf_mem_iq_head_not_ready_o = mem_iq_head_not_ready;
        perf_mem_iq_younger_ready_o = mem_iq_head_not_ready && mem_iq_younger_ready;
        perf_mul_op_o = mul_issue_valid[0] && mul_issue_ready[0] &&
                        (mul_issue_uop[0].uop.muldiv_op <= MULDIV_OP_MULHU);
        perf_div_op_o = mul_issue_valid[0] && mul_issue_ready[0] &&
                        ((mul_issue_uop[0].uop.muldiv_op == MULDIV_OP_DIV) ||
                         (mul_issue_uop[0].uop.muldiv_op == MULDIV_OP_DIVU));
        perf_rem_op_o = mul_issue_valid[0] && mul_issue_ready[0] &&
                        ((mul_issue_uop[0].uop.muldiv_op == MULDIV_OP_REM) ||
                         (mul_issue_uop[0].uop.muldiv_op == MULDIV_OP_REMU));
        perf_muldiv_busy_o = execute_muldiv_busy;

        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            if (rob_alloc_valid[i]) begin
                perf_dispatch_count_o = perf_dispatch_count_o + 1'b1;
            end
        end
        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            if (int_issue_valid[i] && int_issue_ready[i]) begin
                perf_int_issue_count_o = perf_int_issue_count_o + 1'b1;
                perf_issue_count_o = perf_issue_count_o + 1'b1;
            end
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i = i + 1) begin
            if (mem_issue_valid[i] && mem_issue_ready[i]) begin
                perf_mem_issue_count_o = perf_mem_issue_count_o + 1'b1;
                perf_issue_count_o = perf_issue_count_o + 1'b1;
            end
        end
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i = i + 1) begin
            if (mul_issue_valid[i] && mul_issue_ready[i]) begin
                perf_mul_issue_count_o = perf_mul_issue_count_o + 1'b1;
                perf_issue_count_o = perf_issue_count_o + 1'b1;
            end
        end

        if (perf_rob_head_not_done_o) begin
            if (retire_entry[0].uop.is_load || retire_entry[0].uop.is_store) begin
                perf_rob_head_mem_o = 1'b1;
            end else if (retire_entry[0].uop.tube == TUBE_TYPE_MUL) begin
                perf_rob_head_mul_o = 1'b1;
            end else if ((retire_entry[0].uop.tube == TUBE_TYPE_ALU) ||
                         (retire_entry[0].uop.tube == TUBE_TYPE_BRC)) begin
                perf_rob_head_int_o = 1'b1;
            end else begin
                perf_rob_head_other_o = 1'b1;
            end
        end
    end
`endif

    assign commit_valid_o = commit_valid;
    assign commit_entry_o = retire_entry;
endmodule : CoreBackend
