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
    output logic [2:0] perf_mem_iq_occupancy_o,
    output logic perf_mem_iq_probe_launch_o,
    output logic perf_mem_iq_probe_accept_o,
    output logic perf_mem_iq_probe_reject_o,
    output logic perf_mul_op_o,
    output logic perf_div_op_o,
    output logic perf_rem_op_o,
    output logic perf_muldiv_busy_o
`endif
);
    localparam int DISPATCH_BUFFER_DEPTH = 4;
    localparam int DISPATCH_BUFFER_COUNT_BITS =
        $clog2(DISPATCH_BUFFER_DEPTH + 1);
    localparam int DISPATCH_BUFFER_PTR_BITS =
        (DISPATCH_BUFFER_DEPTH <= 1) ? 1 : $clog2(DISPATCH_BUFFER_DEPTH);
    localparam logic [DISPATCH_BUFFER_COUNT_BITS-1:0]
        DISPATCH_BUFFER_DEPTH_COUNT =
            DISPATCH_BUFFER_COUNT_BITS'(DISPATCH_BUFFER_DEPTH);

    logic [RENAME_WIDTH-1:0] free_alloc_req;
    logic [RENAME_WIDTH-1:0] free_alloc_accept;
    logic [RENAME_WIDTH-1:0] free_alloc_valid;
    PhyRegNumPath [RENAME_WIDTH-1:0] free_alloc_phy;
    logic [RETIRE_WIDTH-1:0] free_old_valid;
    PhyRegNumPath [RETIRE_WIDTH-1:0] free_old_prd;

    logic [RENAME_WIDTH-1:0] rename_valid;
    logic [RENAME_WIDTH-1:0] rename_ready;
    CoreRenamedUop [RENAME_WIDTH-1:0] rename_uop;
    logic [RENAME_WIDTH-1:0] rename_alloc_valid;
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

    CoreRenamedUop dispatch_buffer_entry_q [DISPATCH_BUFFER_DEPTH-1:0];
    CoreRenamedUop [DISPATCH_WIDTH-1:0] dispatch_buffer_ready_entry;
    CoreRenamedUop [RENAME_WIDTH-1:0] dispatch_buffer_push_uop;
    CoreRenamedUop [DISPATCH_WIDTH-1:0] dispatch_buffer_uop;
    logic [DISPATCH_WIDTH-1:0] dispatch_buffer_valid;
    logic [DISPATCH_WIDTH-1:0] dispatch_buffer_ready;
    logic [DISPATCH_WIDTH-1:0] dispatch_buffer_pop_fire;
    logic [DISPATCH_BUFFER_PTR_BITS-1:0] dispatch_buffer_head_q;
    logic [DISPATCH_BUFFER_PTR_BITS-1:0] dispatch_buffer_tail_q;
    logic [DISPATCH_BUFFER_COUNT_BITS-1:0] dispatch_buffer_count_q;
    logic [DISPATCH_BUFFER_COUNT_BITS-1:0] dispatch_buffer_pop_count;
    logic [DISPATCH_BUFFER_COUNT_BITS-1:0] dispatch_buffer_push_count;
    logic [DISPATCH_BUFFER_COUNT_BITS-1:0]
        dispatch_buffer_push_offset [RENAME_WIDTH-1:0];

    logic [INT_ISSUE_WIDTH-1:0] int_issue_ready;
    logic [INT_ISSUE_WIDTH-1:0] int_issue_valid;
    CoreRenamedUop [INT_ISSUE_WIDTH-1:0] int_issue_uop;
    logic [INT_ISSUE_WIDTH-1:0] int_issue_valid_q;
    CoreRenamedUop [INT_ISSUE_WIDTH-1:0] int_issue_uop_q;
    logic [INT_ISSUE_WIDTH-1:0] int_select_ready;
    logic [INT_ISSUE_WIDTH-1:0] int_select_valid;
    CoreRenamedUop [INT_ISSUE_WIDTH-1:0] int_select_uop;
    logic [INT_ISSUE_WIDTH-1:0] int_stage_slot_available;
    logic [MEM_ISSUE_WIDTH-1:0] mem_issue_ready;
    logic [MEM_ISSUE_WIDTH-1:0] mem_issue_valid;
    CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] mem_issue_uop;
    logic [MEM_ISSUE_WIDTH-1:0] mem_issue_valid_q;
    CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] mem_issue_uop_q;
    logic [MEM_ISSUE_WIDTH-1:0] mem_select_ready;
    logic [MEM_ISSUE_WIDTH-1:0] mem_select_valid;
    CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] mem_select_uop;
    logic [MEM_ISSUE_WIDTH-1:0] mem_stage_slot_available;
    logic mem_issue_lookahead;
    logic mem_issue_lookahead_q;
    logic mem_select_lookahead;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_slot;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_age;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_slot_q;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_age_q;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_select_slot;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_select_age;
    logic mem_probe_resolve_valid;
    logic mem_probe_resolve_accept;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_resolve_slot;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_resolve_age;
    RobIndexPath mem_probe_resolve_rob_idx;
    logic [$clog2(MEM_IQ_DEPTH+1)-1:0] mem_iq_occupancy;
    logic mem_iq_probe_launch;
    logic mem_iq_probe_accept;
    logic mem_iq_probe_reject;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_ready;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_valid;
    CoreRenamedUop [MULDIV_ISSUE_WIDTH-1:0] mul_issue_uop;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_valid_q;
    CoreRenamedUop [MULDIV_ISSUE_WIDTH-1:0] mul_issue_uop_q;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_select_ready;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_select_valid;
    CoreRenamedUop [MULDIV_ISSUE_WIDTH-1:0] mul_select_uop;
    logic [MULDIV_ISSUE_WIDTH-1:0] mul_stage_slot_available;

    logic [ISSUE_WIDTH-1:0] exec_complete_valid;
    RobIndexPath [ISSUE_WIDTH-1:0] exec_complete_rob_idx;
    PhyRegNumPath [ISSUE_WIDTH-1:0] exec_complete_prd;
    logic [INT_ISSUE_WIDTH-1:0] int_early_wakeup_valid;
    PhyRegNumPath [INT_ISSUE_WIDTH-1:0] int_early_wakeup_prd;
    logic [ISSUE_WIDTH-1:0] scheduler_wakeup_valid;
    PhyRegNumPath [ISSUE_WIDTH-1:0] scheduler_wakeup_prd;
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
    logic store_push_data_valid;
    PhyRegNumPath store_push_data_prd;
    logic store_push_ready;
    logic store_complete_valid;
    RobIndexPath store_complete_rob_idx;
    AddrPath store_complete_addr;
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

    function automatic logic [DISPATCH_BUFFER_PTR_BITS-1:0]
        dispatch_buffer_wrap_add(
            input logic [DISPATCH_BUFFER_PTR_BITS-1:0] base,
            input logic [DISPATCH_BUFFER_COUNT_BITS-1:0] offset
        );
        logic [DISPATCH_BUFFER_COUNT_BITS:0] sum;
        begin
            sum = DISPATCH_BUFFER_COUNT_BITS'(base) + offset;
            if (sum >= DISPATCH_BUFFER_DEPTH) begin
                sum = sum - DISPATCH_BUFFER_DEPTH;
            end
            if (sum >= DISPATCH_BUFFER_DEPTH) begin
                sum = sum - DISPATCH_BUFFER_DEPTH;
            end
            dispatch_buffer_wrap_add =
                sum[DISPATCH_BUFFER_PTR_BITS-1:0];
        end
    endfunction

    always_comb begin
        serial_block = serial_inflight_q;
        serial_alloc = 1'b0;
        serial_retire = 1'b0;
        decode_valid_to_rename = decode_valid_i;
        decode_ready_o = decode_ready_from_rename;

        for (int i = 0; i < DECODE_WIDTH; i = i + 1) begin
            if (serial_block) begin
                decode_valid_to_rename[i] = 1'b0;
                decode_ready_o[i] = 1'b0;
            end
            if (decode_valid_i[i] && decode_uop_i[i].is_serial) begin
                if (serial_block || !rob_empty ||
                    (dispatch_buffer_count_q != '0) || (i != 0)) begin
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
            if (rename_alloc_valid[i] && rename_uop[i].uop.is_serial) begin
                serial_alloc = 1'b1;
            end
        end

        for (int c = 0; c < RETIRE_WIDTH; c = c + 1) begin
            if (commit_valid[c] && retire_entry[c].uop.is_serial) begin
                serial_retire = 1'b1;
            end
        end
    end

    // Rename owns the PRD and speculative map when an entry crosses this
    // boundary. ROB ownership is deliberately delayed until the registered
    // entry can also enter Dispatch, so neither ROB nor an IQ sees the sRAT
    // combinational cone.
    always_comb begin
        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            rename_ready[i] = !clear_i && !recover_i &&
                              ((dispatch_buffer_count_q -
                                dispatch_buffer_pop_count +
                                DISPATCH_BUFFER_COUNT_BITS'(i)) <
                               DISPATCH_BUFFER_DEPTH_COUNT);
        end
    end

    // Fixed one-cycle INT producers announce their PRD when Execute accepts
    // the registered issue slot. A dependent IQ entry may then enter its own
    // issue register on the producer's execute edge and consume wb_q bypass on
    // the next cycle. Slots 0/1 overlay the previous completion announcement:
    // that producer was already announced one cycle earlier, while BusyTable
    // still observes the architectural completion stream below.
    always_comb begin
        scheduler_wakeup_valid = exec_complete_valid;
        scheduler_wakeup_prd = exec_complete_prd;
        int_early_wakeup_valid = '0;
        int_early_wakeup_prd = '0;
        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            if (int_issue_valid[i] && int_issue_ready[i] &&
                int_issue_uop[i].alloc_prd &&
                (int_issue_uop[i].prd != '0) &&
                !int_issue_uop[i].uop.exception &&
                ((int_issue_uop[i].uop.tube == TUBE_TYPE_ALU) ||
                 (int_issue_uop[i].uop.tube == TUBE_TYPE_BRC))) begin
                int_early_wakeup_valid[i] = 1'b1;
                int_early_wakeup_prd[i] = int_issue_uop[i].prd;
                scheduler_wakeup_valid[i] = 1'b1;
                scheduler_wakeup_prd[i] = int_issue_uop[i].prd;
            end
        end
    end

    // Stable-slot ring read. Payload never shifts after a pop; head/tail/count
    // alone transfer ownership. Current wakeups are reflected in the offered
    // entry and are also accumulated into the physical slot below.
    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            dispatch_buffer_ready_entry[i] = dispatch_buffer_entry_q[
                dispatch_buffer_wrap_add(
                    dispatch_buffer_head_q,
                    DISPATCH_BUFFER_COUNT_BITS'(i)
                )
            ];
            for (int w = 0; w < ISSUE_WIDTH; w = w + 1) begin
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] ==
                     dispatch_buffer_ready_entry[i].prs1)) begin
                    dispatch_buffer_ready_entry[i].src1_ready = 1'b1;
                end
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] ==
                     dispatch_buffer_ready_entry[i].prs2)) begin
                    dispatch_buffer_ready_entry[i].src2_ready = 1'b1;
                end
            end
        end
    end

    // ROB allocation, Dispatch acceptance, and buffer removal are one atomic
    // event. Lane 1 is not even offered until lane 0 is known to fire, which
    // preserves program order for DispatchUnit outputs that are valid/ready.
    always_comb begin
        dispatch_buffer_valid = '0;
        dispatch_buffer_pop_fire = '0;
        dispatch_buffer_pop_count = '0;

        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            dispatch_buffer_uop[i] = dispatch_buffer_ready_entry[i];
            dispatch_buffer_uop[i].rob_idx = rob_alloc_idx[i];
            dispatch_tube[i] = dispatch_buffer_ready_entry[i].uop.tube;

            dispatch_buffer_valid[i] = !clear_i && !recover_i &&
                                       (dispatch_buffer_count_q >
                                        DISPATCH_BUFFER_COUNT_BITS'(i));
            if (i != 0) begin
                dispatch_buffer_valid[i] = dispatch_buffer_valid[i] &&
                                           dispatch_buffer_pop_fire[i-1];
            end

            dispatch_buffer_valid[i] = dispatch_buffer_valid[i] &&
                                       rob_alloc_ready[i];
            dispatch_buffer_pop_fire[i] = dispatch_buffer_valid[i] &&
                                          dispatch_buffer_ready[i];
            rob_alloc_valid[i] = dispatch_buffer_pop_fire[i];
            if (dispatch_buffer_pop_fire[i]) begin
                dispatch_buffer_pop_count = dispatch_buffer_pop_count + 1'b1;
            end
        end
    end

    // Build fixed tail writes and apply a same-cycle completion before the new
    // owner becomes visible. No existing payload participates in this cone.
    always_comb begin
        dispatch_buffer_push_count = '0;
        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            dispatch_buffer_push_offset[i] = dispatch_buffer_push_count;
            dispatch_buffer_push_uop[i] = rename_uop[i];
            for (int w = 0; w < ISSUE_WIDTH; w = w + 1) begin
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] == rename_uop[i].prs1)) begin
                    dispatch_buffer_push_uop[i].src1_ready = 1'b1;
                end
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] == rename_uop[i].prs2)) begin
                    dispatch_buffer_push_uop[i].src2_ready = 1'b1;
                end
            end
            if (rename_alloc_valid[i]) begin
                dispatch_buffer_push_count =
                    dispatch_buffer_push_count + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dispatch_buffer_head_q <= '0;
            dispatch_buffer_tail_q <= '0;
            dispatch_buffer_count_q <= '0;
        end else if (clear_i || recover_i) begin
            dispatch_buffer_head_q <= '0;
            dispatch_buffer_tail_q <= '0;
            dispatch_buffer_count_q <= '0;
        end else begin
            dispatch_buffer_head_q <= dispatch_buffer_wrap_add(
                dispatch_buffer_head_q, dispatch_buffer_pop_count
            );
            dispatch_buffer_tail_q <= dispatch_buffer_wrap_add(
                dispatch_buffer_tail_q, dispatch_buffer_push_count
            );
            dispatch_buffer_count_q <= dispatch_buffer_count_q +
                                       dispatch_buffer_push_count -
                                       dispatch_buffer_pop_count;
        end
    end

    // Payload has no reset/recovery CE. Stale slots are invisible outside the
    // registered head/count window; wakeups update only two ready bits, while a
    // push writes exactly one stable tail slot.
    always_ff @(posedge clk) begin
        for (int e = 0; e < DISPATCH_BUFFER_DEPTH; e = e + 1) begin
            for (int w = 0; w < ISSUE_WIDTH; w = w + 1) begin
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] ==
                     dispatch_buffer_entry_q[e].prs1)) begin
                    dispatch_buffer_entry_q[e].src1_ready <= 1'b1;
                end
                if (scheduler_wakeup_valid[w] &&
                    (scheduler_wakeup_prd[w] ==
                     dispatch_buffer_entry_q[e].prs2)) begin
                    dispatch_buffer_entry_q[e].src2_ready <= 1'b1;
                end
            end
        end
        for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
            if (rename_alloc_valid[i]) begin
                dispatch_buffer_entry_q[dispatch_buffer_wrap_add(
                    dispatch_buffer_tail_q,
                    dispatch_buffer_push_offset[i]
                )] <= dispatch_buffer_push_uop[i];
            end
        end
    end

    // Elastic issue boundary. Completion/wakeup and oldest-ready selection end
    // at these valid/uop registers; PRF read and execution start from registered
    // issue payload on the following cycle. A consumed entry may be replaced in
    // the same edge, preserving one-uop-per-port-per-cycle steady-state rate.
    always_comb begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            int_stage_slot_available[i] = !int_issue_valid_q[i] ||
                                          int_issue_ready[i];
            int_select_ready[i] = !clear_i && !recover_i &&
                                  int_stage_slot_available[i];
            int_issue_valid[i] = int_issue_valid_q[i];
            int_issue_uop[i] = int_issue_uop_q[i];
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i = i + 1) begin
            mem_stage_slot_available[i] = !mem_issue_valid_q[i] ||
                                          mem_issue_ready[i];
            mem_select_ready[i] = !clear_i && !recover_i &&
                                  mem_stage_slot_available[i];
            mem_issue_valid[i] = mem_issue_valid_q[i];
            mem_issue_uop[i] = mem_issue_uop_q[i];
        end
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i = i + 1) begin
            mul_stage_slot_available[i] = !mul_issue_valid_q[i] ||
                                          mul_issue_ready[i];
            mul_select_ready[i] = !clear_i && !recover_i &&
                                  mul_stage_slot_available[i];
            mul_issue_valid[i] = mul_issue_valid_q[i];
            mul_issue_uop[i] = mul_issue_uop_q[i];
        end
        mem_issue_lookahead = mem_issue_lookahead_q;
        mem_issue_slot = mem_issue_slot_q;
        mem_issue_age = mem_issue_age_q;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            int_issue_valid_q <= '0;
            mem_issue_valid_q <= '0;
            mul_issue_valid_q <= '0;
        end else if (clear_i || recover_i) begin
            int_issue_valid_q <= '0;
            mem_issue_valid_q <= '0;
            mul_issue_valid_q <= '0;
        end else begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
                if (int_stage_slot_available[i]) begin
                    int_issue_valid_q[i] <= int_select_valid[i];
                end
            end
            for (int i = 0; i < MEM_ISSUE_WIDTH; i = i + 1) begin
                if (mem_stage_slot_available[i]) begin
                    mem_issue_valid_q[i] <= mem_select_valid[i];
                end
            end
            for (int i = 0; i < MULDIV_ISSUE_WIDTH; i = i + 1) begin
                if (mul_stage_slot_available[i]) begin
                    mul_issue_valid_q[i] <= mul_select_valid[i];
                end
            end
        end
    end

    // Payload has no recovery/reset control. It changes only when its local
    // elastic slot accepts a new owner; valid_q alone kills wrong-path data.
    always_ff @(posedge clk) begin
        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            if (int_stage_slot_available[i] && int_select_valid[i]) begin
                int_issue_uop_q[i] <= int_select_uop[i];
            end
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i = i + 1) begin
            if (mem_stage_slot_available[i] && mem_select_valid[i]) begin
                mem_issue_uop_q[i] <= mem_select_uop[i];
                mem_issue_lookahead_q <= mem_select_lookahead;
                mem_issue_slot_q <= mem_select_slot;
                mem_issue_age_q <= mem_select_age;
            end
        end
        for (int i = 0; i < MULDIV_ISSUE_WIDTH; i = i + 1) begin
            if (mul_stage_slot_available[i] && mul_select_valid[i]) begin
                mul_issue_uop_q[i] <= mul_select_uop[i];
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
        .rob_alloc_valid_o(rename_alloc_valid),
        .rob_alloc_ready_i(rename_ready),
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
        .mark_ready_i(exec_complete_valid),
        .mark_ready_phy_i(exec_complete_prd)
    );

    CoreROB u_rob (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .alloc_valid_i(rob_alloc_valid),
        .alloc_uop_i(dispatch_buffer_uop),
        .alloc_ready_o(rob_alloc_ready),
        .alloc_idx_o(rob_alloc_idx),
        .complete_valid_i(exec_complete_valid),
        .complete_idx_i(exec_complete_rob_idx),
        .complete_result_i(exec_complete_result),
        .complete_exception_i(exec_complete_exception),
        .complete_exception_cause_i(exec_complete_exception_cause),
        .complete_branch_miss_i(exec_complete_branch_miss),
        .complete_redirect_pc_i(exec_complete_redirect_pc),
        .complete_csr_write_i(exec_complete_csr_write),
        .complete_csr_addr_i(exec_complete_csr_addr),
        .complete_csr_wdata_i(exec_complete_csr_wdata),
        .store_complete_valid_i(store_complete_valid),
        .store_complete_idx_i(store_complete_rob_idx),
        .store_complete_addr_i(store_complete_addr),
        .retire_ready_i(retire_ready),
        .retire_valid_o(retire_valid),
        .retire_entry_o(retire_entry),
        .empty_o(rob_empty),
        .full_o(rob_full)
    );

    CoreDispatchUnit u_dispatch (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .in_valid_i(dispatch_buffer_valid),
        .in_uop_i(dispatch_buffer_uop),
        .in_tube_i(dispatch_tube),
        .in_ready_o(dispatch_buffer_ready),
        .wakeup_valid_i(scheduler_wakeup_valid),
        .wakeup_phy_i(scheduler_wakeup_prd),
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
        .wakeup_valid_i(scheduler_wakeup_valid),
        .wakeup_phy_i(scheduler_wakeup_prd),
        .issue_ready_i(int_select_ready),
        .issue_valid_o(int_select_valid),
        .issue_uop_o(int_select_uop)
    );

    CoreMemIssueQueue u_mem_iq (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(mem_push_valid),
        .push_uop_i(mem_push_uop),
        .push_ready_o(mem_push_ready),
        .wakeup_valid_i(scheduler_wakeup_valid),
        .wakeup_phy_i(scheduler_wakeup_prd),
        .issue_ready_i(mem_select_ready),
        .issue_valid_o(mem_select_valid),
        .issue_uop_o(mem_select_uop),
        .issue_lookahead_o(mem_select_lookahead),
        .issue_slot_o(mem_select_slot),
        .issue_age_o(mem_select_age),
        .probe_resolve_valid_i(mem_probe_resolve_valid),
        .probe_resolve_accept_i(mem_probe_resolve_accept),
        .probe_resolve_slot_i(mem_probe_resolve_slot),
        .probe_resolve_age_i(mem_probe_resolve_age),
        .probe_resolve_rob_idx_i(mem_probe_resolve_rob_idx),
        .head_not_ready_o(mem_iq_head_not_ready),
        .younger_ready_behind_head_o(mem_iq_younger_ready),
        .occupancy_o(mem_iq_occupancy),
        .probe_launch_o(mem_iq_probe_launch),
        .probe_accept_o(mem_iq_probe_accept),
        .probe_reject_o(mem_iq_probe_reject)
    );

    CoreMulDivIssueQueue u_mul_iq (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i || recover_i),
        .push_valid_i(mul_push_valid),
        .push_uop_i(mul_push_uop),
        .push_ready_o(mul_push_ready),
        .wakeup_valid_i(scheduler_wakeup_valid),
        .wakeup_phy_i(scheduler_wakeup_prd),
        .issue_ready_i(mul_select_ready),
        .issue_valid_o(mul_select_valid),
        .issue_uop_o(mul_select_uop)
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
        .wakeup_valid_i(exec_complete_valid),
        .wakeup_phy_i(exec_complete_prd),
        .wakeup_result_i(exec_complete_result),
        .mem_issue_lookahead_i(mem_issue_lookahead),
        .mem_issue_slot_i(mem_issue_slot),
        .mem_issue_age_i(mem_issue_age),
        .mem_probe_resolve_valid_o(mem_probe_resolve_valid),
        .mem_probe_resolve_accept_o(mem_probe_resolve_accept),
        .mem_probe_resolve_slot_o(mem_probe_resolve_slot),
        .mem_probe_resolve_age_o(mem_probe_resolve_age),
        .mem_probe_resolve_rob_idx_o(mem_probe_resolve_rob_idx),
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
        .store_push_data_valid_o(store_push_data_valid),
        .store_push_data_prd_o(store_push_data_prd),
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
        .push_data_valid_i(store_push_data_valid),
        .push_data_prd_i(store_push_data_prd),
        .push_ready_o(store_push_ready),
        .complete_valid_i(exec_complete_valid),
        .complete_prd_i(exec_complete_prd),
        .complete_result_i(exec_complete_result),
        .store_complete_valid_o(store_complete_valid),
        .store_complete_rob_idx_o(store_complete_rob_idx),
        .store_complete_addr_o(store_complete_addr),
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
    logic [INT_ISSUE_WIDTH-1:0] int_early_wakeup_valid_prev_q;
    PhyRegNumPath [INT_ISSUE_WIDTH-1:0] int_early_wakeup_prd_prev_q;

    always_ff @(posedge clk) begin
        if (rst || clear_i || recover_i) begin
            int_early_wakeup_valid_prev_q <= '0;
        end else begin
            assert (dispatch_buffer_count_q <=
                    DISPATCH_BUFFER_DEPTH_COUNT)
                else $error("allocated dispatch buffer overflow");
            assert (!(rename_alloc_valid[1] && !rename_alloc_valid[0]))
                else $error("rename enqueue violated lane prefix");
            assert (!(dispatch_buffer_pop_fire[1] &&
                      !dispatch_buffer_pop_fire[0]))
                else $error("allocated dispatch dequeue violated lane prefix");
            for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
                if (rob_alloc_valid[i]) begin
                    assert (dispatch_buffer_pop_fire[i] &&
                            (dispatch_buffer_uop[i].rob_idx ==
                             rob_alloc_idx[i]))
                        else $error("ROB allocation lost dispatch ownership");
                end
            end
            for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
                if (int_early_wakeup_valid_prev_q[i]) begin
                    assert (exec_complete_valid[i] &&
                            (exec_complete_prd[i] ==
                             int_early_wakeup_prd_prev_q[i]))
                        else $error("early INT wakeup lacked next-cycle completion");
                end
            end
            int_early_wakeup_valid_prev_q <= int_early_wakeup_valid;
            int_early_wakeup_prd_prev_q <= int_early_wakeup_prd;
        end
    end

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
                                 |(rename_valid & ~rename_ready));
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
        perf_mem_iq_occupancy_o = 3'(mem_iq_occupancy);
        perf_mem_iq_probe_launch_o = mem_iq_probe_launch;
        perf_mem_iq_probe_accept_o = mem_iq_probe_accept;
        perf_mem_iq_probe_reject_o = mem_iq_probe_reject;
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
