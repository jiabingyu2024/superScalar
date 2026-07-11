import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreExecuteCluster (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    output logic [INT_ISSUE_WIDTH-1:0] int_issue_ready_o,
    input  logic [INT_ISSUE_WIDTH-1:0] int_issue_valid_i,
    input  CoreRenamedUop [INT_ISSUE_WIDTH-1:0] int_issue_uop_i,

    output logic [MEM_ISSUE_WIDTH-1:0] mem_issue_ready_o,
    input  logic [MEM_ISSUE_WIDTH-1:0] mem_issue_valid_i,
    input  CoreRenamedUop [MEM_ISSUE_WIDTH-1:0] mem_issue_uop_i,
    input  logic [ISSUE_WIDTH-1:0] wakeup_valid_i,
    input  PhyRegNumPath [ISSUE_WIDTH-1:0] wakeup_phy_i,
    input  DataPath [ISSUE_WIDTH-1:0] wakeup_result_i,
    input  logic mem_issue_lookahead_i,
    input  logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_slot_i,
    input  logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_issue_age_i,
    output logic mem_probe_resolve_valid_o,
    output logic mem_probe_resolve_accept_o,
    output logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_resolve_slot_o,
    output logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_resolve_age_o,
    output RobIndexPath mem_probe_resolve_rob_idx_o,

    output logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_ready_o,
    input  logic [MULDIV_ISSUE_WIDTH-1:0] mul_issue_valid_i,
    input  CoreRenamedUop [MULDIV_ISSUE_WIDTH-1:0] mul_issue_uop_i,

    output logic [ISSUE_WIDTH-1:0] complete_valid_o,
    output RobIndexPath [ISSUE_WIDTH-1:0] complete_rob_idx_o,
    output PhyRegNumPath [ISSUE_WIDTH-1:0] complete_prd_o,
    output DataPath [ISSUE_WIDTH-1:0] complete_result_o,
    output logic [ISSUE_WIDTH-1:0] complete_exception_o,
    output logic [ISSUE_WIDTH-1:0][31:0] complete_exception_cause_o,
    output logic [ISSUE_WIDTH-1:0] complete_branch_miss_o,
    output PcPath [ISSUE_WIDTH-1:0] complete_redirect_pc_o,
    output logic [ISSUE_WIDTH-1:0] complete_csr_write_o,
    output logic [ISSUE_WIDTH-1:0][11:0] complete_csr_addr_o,
    output DataPath [ISSUE_WIDTH-1:0] complete_csr_wdata_o,

    output logic [ISSUE_WIDTH-1:0][11:0] csr_read_addr_o,
    input  DataPath [ISSUE_WIDTH-1:0] csr_read_data_i,
    input  logic [1:0] csr_priv_mode_i,

    output logic store_push_valid_o,
    output RobIndexPath store_push_rob_idx_o,
    output AddrPath store_push_addr_o,
    output DataPath store_push_data_o,
    output logic [3:0] store_push_mask_o,
    output logic store_push_data_valid_o,
    output PhyRegNumPath store_push_data_prd_o,
    input  logic store_push_ready_i,
    input  logic store_buffer_empty_i,

    output logic load_query_valid_o,
    output AddrPath load_query_addr_o,
    output logic [3:0] load_query_mask_o,
    input  logic load_forward_hit_i,
    input  logic load_forward_full_i,
    input  DataPath load_forward_data_i,

    output logic perf_load_pending_o,
    output logic perf_mem_req_valid_o,
    output logic perf_mem_req_partial_alias_o,
    output logic perf_mem_req_no_alias_o,
    output logic perf_mem_req_forward_o,
    output logic perf_muldiv_busy_o,

    DramAccessIF.ExecuteMemStage dmem
);
    localparam int READ_PORTS = ISSUE_WIDTH * 2;
    localparam int MEM_SLOT = INT_ISSUE_WIDTH;
    localparam int MULDIV_SLOT = INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH;
    localparam AddrPath CACHE_ADDR_START = 32'h8010_0000;
    localparam AddrPath CACHE_ADDR_END = 32'h8014_0000;
    localparam int MEM_REQ_DEPTH = 2;
    localparam int MEM_REQ_COUNT_BITS = $clog2(MEM_REQ_DEPTH + 1);
    localparam int LOAD_META_DEPTH = 2;
    localparam int LOAD_META_COUNT_BITS = $clog2(LOAD_META_DEPTH + 1);

    CoreRenamedUop issue_uop [ISSUE_WIDTH-1:0];
    logic [ISSUE_WIDTH-1:0] issue_valid;
    DataPath src0 [ISSUE_WIDTH-1:0];
    DataPath src1 [ISSUE_WIDTH-1:0];
    DataPath result [ISSUE_WIDTH-1:0];
    logic branch_taken [ISSUE_WIDTH-1:0];
    PcPath branch_target [ISSUE_WIDTH-1:0];
    logic csr_do_write [ISSUE_WIDTH-1:0];
    logic csr_fault [ISSUE_WIDTH-1:0];
    logic mem_align_fault [ISSUE_WIDTH-1:0];
    logic dynamic_exception [ISSUE_WIDTH-1:0];
    DataPath dynamic_exception_cause [ISSUE_WIDTH-1:0];
    DataPath csr_operand [ISSUE_WIDTH-1:0];
    DataPath csr_new_value [ISSUE_WIDTH-1:0];
    logic [ISSUE_WIDTH-1:0] prf_we;
    PhyRegNumPath [ISSUE_WIDTH-1:0] prf_waddr;
    DataPath [ISSUE_WIDTH-1:0] prf_wdata;
    PhyRegNumPath [READ_PORTS-1:0] prf_raddr;
    DataPath [READ_PORTS-1:0] prf_rdata;

    // Fixed-throughput writeback boundary. The execute cone produces wb_*_d;
    // only registered wb_*_q may drive PRF write ports and backend completion.
    // This cuts completion->IQ->PRF->execute from the distributed PRF CE/D
    // decode while keeping completion visible on the same edge as the write.
    logic [ISSUE_WIDTH-1:0] wb_valid_d;
    logic [ISSUE_WIDTH-1:0] wb_valid_q;
    RobIndexPath [ISSUE_WIDTH-1:0] wb_rob_idx_d;
    RobIndexPath [ISSUE_WIDTH-1:0] wb_rob_idx_q;
    PhyRegNumPath [ISSUE_WIDTH-1:0] wb_prd_d;
    PhyRegNumPath [ISSUE_WIDTH-1:0] wb_prd_q;
    DataPath [ISSUE_WIDTH-1:0] wb_result_d;
    DataPath [ISSUE_WIDTH-1:0] wb_result_q;
    logic [ISSUE_WIDTH-1:0] wb_exception_d;
    logic [ISSUE_WIDTH-1:0] wb_exception_q;
    logic [ISSUE_WIDTH-1:0][31:0] wb_exception_cause_d;
    logic [ISSUE_WIDTH-1:0][31:0] wb_exception_cause_q;
    logic [ISSUE_WIDTH-1:0] wb_branch_miss_d;
    logic [ISSUE_WIDTH-1:0] wb_branch_miss_q;
    PcPath [ISSUE_WIDTH-1:0] wb_redirect_pc_d;
    PcPath [ISSUE_WIDTH-1:0] wb_redirect_pc_q;
    logic [ISSUE_WIDTH-1:0] wb_csr_write_d;
    logic [ISSUE_WIDTH-1:0] wb_csr_write_q;
    logic [ISSUE_WIDTH-1:0][11:0] wb_csr_addr_d;
    logic [ISSUE_WIDTH-1:0][11:0] wb_csr_addr_q;
    DataPath [ISSUE_WIDTH-1:0] wb_csr_wdata_d;
    DataPath [ISSUE_WIDTH-1:0] wb_csr_wdata_q;
    logic [ISSUE_WIDTH-1:0] wb_prf_we_d;
    logic [ISSUE_WIDTH-1:0] wb_prf_we_q;

    logic [MEM_REQ_COUNT_BITS-1:0] mem_req_count_q;
    CoreRenamedUop mem_req_uop_q [MEM_REQ_DEPTH-1:0];
    AddrPath mem_req_addr_q [MEM_REQ_DEPTH-1:0];
    DataPath mem_req_store_data_q [MEM_REQ_DEPTH-1:0];
    logic [3:0] mem_req_store_mask_q [MEM_REQ_DEPTH-1:0];
    logic mem_req_store_data_valid_q [MEM_REQ_DEPTH-1:0];
    PhyRegNumPath mem_req_store_data_prd_q [MEM_REQ_DEPTH-1:0];
    logic mem_req_store_data_valid_now [MEM_REQ_DEPTH-1:0];
    DataPath mem_req_store_data_now [MEM_REQ_DEPTH-1:0];
    logic mem_req_valid;
    CoreRenamedUop mem_req_head_uop;
    AddrPath mem_req_head_addr;
    DataPath mem_req_head_store_data;
    logic [3:0] mem_req_head_store_mask;
    logic mem_req_head_store_data_valid;
    PhyRegNumPath mem_req_head_store_data_prd;
    logic mem_issue_fire;
    logic mem_enqueue;
    CoreRenamedUop mem_enqueue_uop;
    AddrPath mem_enqueue_addr;
    DataPath mem_enqueue_store_data;
    logic [3:0] mem_enqueue_store_mask;
    logic mem_enqueue_store_data_valid;
    PhyRegNumPath mem_enqueue_store_data_prd;
    logic mem_probe_valid_q;
    CoreRenamedUop mem_probe_uop_q;
    AddrPath mem_probe_addr_q;
    DataPath mem_probe_store_data_q;
    logic [3:0] mem_probe_store_mask_q;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_slot_q;
    logic [$clog2(MEM_IQ_DEPTH)-1:0] mem_probe_age_q;
    logic mem_probe_cacheable;
    logic mem_probe_misaligned;
    logic mem_req_complete;
    logic mem_req_report_complete;
    logic mem_req_consume;
    logic mem_req_load_send;
    logic mem_req_cacheable;
    logic mem_req_misaligned;
    logic [LOAD_META_COUNT_BITS-1:0] load_meta_count_q;
    CoreRenamedUop load_meta_uop_q [LOAD_META_DEPTH-1:0];
    logic [LOAD_META_DEPTH-1:0] load_meta_killed_q;
    logic load_meta_space;
    logic load_meta_push;
    logic load_meta_pop;
    logic load_resp_complete;
    logic store_drain_pending_q;
    logic muldiv_ready;
    logic muldiv_start;
    logic muldiv_complete_valid;
    CoreRenamedUop muldiv_complete_uop;
    DataPath muldiv_complete_result;

    localparam logic [1:0] PRIV_M = 2'b11;

    function automatic logic csr_exists(input logic [11:0] addr);
        begin
            unique case (addr)
                12'h100,
                12'h105,
                12'h106,
                12'h180,
                12'h300,
                12'h301,
                12'h302,
                12'h303,
                12'h304,
                12'h305,
                12'h306,
                12'h340,
                12'h341,
                12'h342,
                12'h343,
                12'h3a0,
                12'h3b0,
                12'hc00,
                12'hc01,
                12'hc02,
                12'hc80,
                12'hc81,
                12'hc82,
                12'hf14: csr_exists = 1'b1;
                default: csr_exists = 1'b0;
            endcase
        end
    endfunction

    function automatic logic csr_write_readonly(input logic [11:0] addr);
        begin
            csr_write_readonly = (addr[11:10] == 2'b11);
        end
    endfunction

    function automatic logic csr_priv_fault(
        input logic [11:0] addr,
        input logic [1:0]  priv
    );
        begin
            csr_priv_fault = (priv < addr[9:8]);
        end
    endfunction

    function automatic logic csr_writes(
        input CoreDecodeUop uop
    );
        begin
            unique case (uop.csr_op)
                CSR_OP_RW: csr_writes = 1'b1;
                CSR_OP_RS,
                CSR_OP_RC: csr_writes = uop.csr_imm ? (uop.csr_zimm != 5'b0) :
                                                       (uop.rs1 != 5'b0);
                default: csr_writes = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [3:0] store_mask(
        input CoreDecodeUop uop
    );
        begin
            unique case (uop.mem_size)
                2'd0: store_mask = 4'b0001;
                2'd1: store_mask = 4'b0011;
                default: store_mask = 4'b1111;
            endcase
        end
    endfunction

    function automatic logic [3:0] load_mask(
        input CoreDecodeUop uop,
        input AddrPath addr
    );
        logic [3:0] base_mask;
        begin
            unique case (uop.mem_size)
                2'd0: base_mask = 4'b0001;
                2'd1: base_mask = 4'b0011;
                default: base_mask = 4'b1111;
            endcase
            load_mask = (base_mask << addr[1:0]) & 4'hf;
        end
    endfunction

    function automatic DataPath load_extend(
        input CoreDecodeUop uop,
        input DataPath raw
    );
        begin
            unique case (uop.mem_size)
                2'd0: begin
                    load_extend = uop.mem_signed ? {{24{raw[7]}}, raw[7:0]} :
                                                   {24'b0, raw[7:0]};
                end
                2'd1: begin
                    load_extend = uop.mem_signed ? {{16{raw[15]}}, raw[15:0]} :
                                                   {16'b0, raw[15:0]};
                end
                default: begin
                    load_extend = raw;
                end
            endcase
        end
    endfunction

    function automatic logic mem_misaligned(
        input CoreDecodeUop uop,
        input AddrPath addr
    );
        begin
            unique case (uop.mem_size)
                2'd0: mem_misaligned = 1'b0;
                2'd1: mem_misaligned = addr[0];
                default: mem_misaligned = |addr[1:0];
            endcase
        end
    endfunction

    function automatic DataPath alu_result(
        input CoreDecodeUop uop,
        input DataPath a,
        input DataPath b
    );
        DataPath rhs;
        begin
            rhs = (uop.opcode == 7'b0010011) ? uop.imm_i : b;
            if (uop.opcode == 7'b0010111) begin
                alu_result = uop.pc + uop.imm_u;
            end else begin
                unique case (uop.alu_op)
                    ALU_OP_ADD:    alu_result = a + rhs;
                    ALU_OP_SUB:    alu_result = a - b;
                    ALU_OP_SLL:    alu_result = a << rhs[4:0];
                    ALU_OP_SLT:    alu_result = ($signed(a) < $signed(rhs)) ? 32'd1 : 32'd0;
                    ALU_OP_SLTU:   alu_result = (a < rhs) ? 32'd1 : 32'd0;
                    ALU_OP_XOR:    alu_result = a ^ rhs;
                    ALU_OP_SRL:    alu_result = a >> rhs[4:0];
                    ALU_OP_SRA:    alu_result = DataPath'($signed(a) >>> rhs[4:0]);
                    ALU_OP_OR:     alu_result = a | rhs;
                    ALU_OP_AND:    alu_result = a & rhs;
                    ALU_OP_COPY_B: alu_result = uop.imm_u;
                    default:       alu_result = 32'b0;
                endcase
            end
        end
    endfunction

    assign complete_valid_o = wb_valid_q & {ISSUE_WIDTH{!clear_i}};
    assign complete_rob_idx_o = wb_rob_idx_q;
    assign complete_prd_o = wb_prd_q;
    assign complete_result_o = wb_result_q;
    assign complete_exception_o = wb_exception_q;
    assign complete_exception_cause_o = wb_exception_cause_q;
    assign complete_branch_miss_o = wb_branch_miss_q;
    assign complete_redirect_pc_o = wb_redirect_pc_q;
    assign complete_csr_write_o = wb_valid_q & wb_csr_write_q &
                                  {ISSUE_WIDTH{!clear_i}};
    assign complete_csr_addr_o = wb_csr_addr_q;
    assign complete_csr_wdata_o = wb_csr_wdata_q;

    assign prf_we = wb_valid_q & wb_prf_we_q &
                    {ISSUE_WIDTH{!clear_i}};
    assign prf_waddr = wb_prd_q;
    assign prf_wdata = wb_result_q;

    assign mem_req_valid = (mem_req_count_q != '0);
    assign mem_req_head_uop = mem_req_uop_q[0];
    assign mem_req_head_addr = mem_req_addr_q[0];
    assign mem_req_head_store_data = mem_req_store_data_now[0];
    assign mem_req_head_store_mask = mem_req_store_mask_q[0];
    assign mem_req_head_store_data_valid = mem_req_store_data_valid_now[0];
    assign mem_req_head_store_data_prd = mem_req_store_data_prd_q[0];
    assign mem_req_cacheable = (mem_req_head_addr >= CACHE_ADDR_START) &&
                               (mem_req_head_addr < CACHE_ADDR_END);
    assign mem_req_misaligned =
        mem_misaligned(mem_req_head_uop.uop, mem_req_head_addr);
    assign mem_issue_fire = mem_issue_valid_i[0] && mem_issue_ready_o[0];
    assign mem_probe_cacheable =
        (mem_probe_addr_q >= CACHE_ADDR_START) &&
        (mem_probe_addr_q < CACHE_ADDR_END);
    assign mem_probe_misaligned =
        mem_misaligned(mem_probe_uop_q.uop, mem_probe_addr_q);
    assign mem_probe_resolve_valid_o = mem_probe_valid_q && !clear_i;
    assign mem_probe_resolve_accept_o = mem_probe_resolve_valid_o &&
                                        mem_probe_uop_q.uop.is_load &&
                                        mem_probe_cacheable &&
                                        !mem_probe_misaligned &&
                                        (mem_req_count_q <
                                         MEM_REQ_COUNT_BITS'(MEM_REQ_DEPTH));
    assign mem_probe_resolve_slot_o = mem_probe_slot_q;
    assign mem_probe_resolve_age_o = mem_probe_age_q;
    assign mem_probe_resolve_rob_idx_o = mem_probe_uop_q.rob_idx;

    always_comb begin
        for (int e = 0; e < MEM_REQ_DEPTH; e++) begin
            mem_req_store_data_now[e] = mem_req_store_data_q[e];
            mem_req_store_data_valid_now[e] =
                mem_req_store_data_valid_q[e];
            if (!mem_req_store_data_valid_q[e]) begin
                for (int w = 0; w < ISSUE_WIDTH; w++) begin
                    if (wakeup_valid_i[w] && (wakeup_phy_i[w] != '0) &&
                        (wakeup_phy_i[w] == mem_req_store_data_prd_q[e])) begin
                        mem_req_store_data_now[e] = wakeup_result_i[w];
                        mem_req_store_data_valid_now[e] = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        mem_enqueue = (mem_issue_fire && !mem_issue_lookahead_i) ||
                      mem_probe_resolve_accept_o;
        mem_enqueue_uop = mem_issue_uop_i[0];
        mem_enqueue_addr = prf_rdata[2 * MEM_SLOT] +
            (mem_issue_uop_i[0].uop.is_store ?
             mem_issue_uop_i[0].uop.imm_s : mem_issue_uop_i[0].uop.imm_i);
        mem_enqueue_store_data = prf_rdata[2 * MEM_SLOT + 1];
        mem_enqueue_store_mask = store_mask(mem_issue_uop_i[0].uop);
        mem_enqueue_store_data_valid = mem_issue_uop_i[0].src2_ready;
        mem_enqueue_store_data_prd = mem_issue_uop_i[0].prs2;
        if (mem_issue_uop_i[0].uop.is_store &&
            !mem_enqueue_store_data_valid) begin
            for (int w = 0; w < ISSUE_WIDTH; w++) begin
                if (wakeup_valid_i[w] && (wakeup_phy_i[w] != '0) &&
                    (wakeup_phy_i[w] == mem_enqueue_store_data_prd)) begin
                    mem_enqueue_store_data = wakeup_result_i[w];
                    mem_enqueue_store_data_valid = 1'b1;
                end
            end
        end
        if (mem_probe_resolve_accept_o) begin
            mem_enqueue_uop = mem_probe_uop_q;
            mem_enqueue_addr = mem_probe_addr_q;
            mem_enqueue_store_data = mem_probe_store_data_q;
            mem_enqueue_store_mask = mem_probe_store_mask_q;
            mem_enqueue_store_data_valid = 1'b1;
            mem_enqueue_store_data_prd = '0;
        end
    end
    assign load_meta_pop = dmem.exReadReady && (load_meta_count_q != '0);
    assign load_resp_complete = load_meta_pop &&
                                !load_meta_killed_q[0] &&
                                !clear_i;
    // The registered response may retire the metadata head while the next
    // cacheable load is accepted. This replacement path is local to the LSU
    // and never feeds MEM-IQ ready.
    assign load_meta_space =
        (load_meta_count_q < LOAD_META_COUNT_BITS'(LOAD_META_DEPTH)) ||
        load_meta_pop;

    // The ordered request queue owns each payload until the downstream side
    // accepts it. An uncached/device load remains ordered behind all stores;
    // only a cacheable no-alias load may bypass a non-empty StoreBuffer.
    always_comb begin
        mem_req_load_send = !clear_i && mem_req_valid &&
                            load_meta_space &&
                            mem_req_head_uop.uop.is_load &&
                            !mem_req_misaligned &&
                            !load_forward_hit_i &&
                            (mem_req_cacheable ||
                             (store_buffer_empty_i && !store_drain_pending_q));

        mem_req_complete = !clear_i && mem_req_valid &&
                           !load_resp_complete &&
                           (mem_req_misaligned ||
                            (mem_req_head_uop.uop.is_store && store_push_ready_i) ||
                            (mem_req_head_uop.uop.is_load && load_forward_full_i));

        mem_req_consume = mem_req_complete ||
                          (mem_req_load_send && dmem.exReadAccept);
        mem_req_report_complete = mem_req_complete &&
            (!mem_req_head_uop.uop.is_store || mem_req_misaligned ||
             mem_req_head_store_data_valid);
        load_meta_push = mem_req_load_send && dmem.exReadAccept;
    end

    // Arbitration is kept separate from result generation.  MEM ready only
    // observes the request-register valid bit, cutting the former
    // IQ->PRF->AGU->StoreBuffer/DCache ready path.
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            issue_valid[i] = 1'b0;
            issue_uop[i] = '0;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            int_issue_ready_o[i] = !clear_i;
            issue_valid[i] = int_issue_valid_i[i] && int_issue_ready_o[i];
            issue_uop[i] = int_issue_uop_i[i];
        end
        for (int m = 0; m < MEM_ISSUE_WIDTH; m = m + 1) begin
            issue_uop[INT_ISSUE_WIDTH + m] = mem_req_head_uop;
            // Ready is derived only from registered local occupancy. Do not
            // include mem_req_consume here: that would reconnect DCache/SB
            // acceptance into MEM-IQ select in the same cycle.
            mem_issue_ready_o[m] = !clear_i &&
                !mem_probe_valid_q &&
                (mem_req_count_q < MEM_REQ_COUNT_BITS'(MEM_REQ_DEPTH));
            issue_valid[INT_ISSUE_WIDTH + m] = mem_req_report_complete;
        end
        for (int u = 0; u < MULDIV_ISSUE_WIDTH; u = u + 1) begin
            mul_issue_ready_o[u] = !clear_i && (u == 0) && muldiv_ready;
            issue_valid[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_valid_i[u] && mul_issue_ready_o[u];
            issue_uop[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_uop_i[u];
        end
    end

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            if (i == MEM_SLOT) begin
                // The MEM PRF ports belong to the IQ->request-register input,
                // not to the request currently being drained.
                prf_raddr[2*i] = mem_issue_uop_i[0].prs1;
                prf_raddr[2*i + 1] = mem_issue_uop_i[0].prs2;
            end else begin
                prf_raddr[2*i] = issue_uop[i].prs1;
                prf_raddr[2*i + 1] = issue_uop[i].prs2;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            csr_read_addr_o[i] = issue_uop[i].uop.csr_addr;
        end
    end

    // The StoreBuffer CAM is driven only by the registered address.  Its
    // result can stall this local request slot, but cannot feed back into the
    // MEM IQ select/pop path in the same cycle.
    always_comb begin
        load_query_valid_o = 1'b0;
        load_query_addr_o = '0;
        load_query_mask_o = '0;
        if (mem_req_valid && mem_req_head_uop.uop.is_load) begin
            load_query_addr_o = mem_req_head_addr;
            load_query_mask_o =
                load_mask(mem_req_head_uop.uop, mem_req_head_addr);
            load_query_valid_o = !mem_req_misaligned;
        end
    end

    always_comb begin
        dmem.exReadEn = 1'b0;
        dmem.exReadAddr = mem_req_head_addr;
        dmem.exReadCacheable = mem_req_cacheable;
        store_push_valid_o = 1'b0;
        store_push_rob_idx_o = '0;
        store_push_addr_o = '0;
        store_push_data_o = '0;
        store_push_mask_o = '0;
        store_push_data_valid_o = 1'b0;
        store_push_data_prd_o = '0;
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            src0[i] = prf_rdata[2*i];
            src1[i] = prf_rdata[2*i + 1];
            if ((i == MEM_SLOT) && mem_req_valid) begin
                src1[i] = mem_req_head_store_data;
            end

            branch_taken[i] = 1'b0;
            branch_target[i] = issue_uop[i].uop.pc + 32'd4;
            csr_do_write[i] = 1'b0;
            csr_fault[i] = 1'b0;
            mem_align_fault[i] = 1'b0;
            dynamic_exception[i] = 1'b0;
            dynamic_exception_cause[i] = 32'b0;
            csr_operand[i] = issue_uop[i].uop.csr_imm ? {27'b0, issue_uop[i].uop.csr_zimm} : src0[i];
            csr_new_value[i] = csr_read_data_i[i];
            result[i] = 32'b0;

            case (issue_uop[i].uop.tube)
                TUBE_TYPE_BRC: begin
                    unique case (issue_uop[i].uop.branch_op)
                        BR_OP_BEQ:  branch_taken[i] = (src0[i] == src1[i]);
                        BR_OP_BNE:  branch_taken[i] = (src0[i] != src1[i]);
                        BR_OP_BLT:  branch_taken[i] = ($signed(src0[i]) < $signed(src1[i]));
                        BR_OP_BGE:  branch_taken[i] = ($signed(src0[i]) >= $signed(src1[i]));
                        BR_OP_BLTU: branch_taken[i] = (src0[i] < src1[i]);
                        BR_OP_BGEU: branch_taken[i] = (src0[i] >= src1[i]);
                        BR_OP_JAL,
                        BR_OP_JALR: branch_taken[i] = 1'b1;
                        default:    branch_taken[i] = 1'b0;
                    endcase
                    if (issue_uop[i].uop.branch_op == BR_OP_JAL) begin
                        branch_target[i] = issue_uop[i].uop.pc + issue_uop[i].uop.imm_j;
                    end else if (issue_uop[i].uop.branch_op == BR_OP_JALR) begin
                        branch_target[i] = (src0[i] + issue_uop[i].uop.imm_i) & 32'hffff_fffe;
                    end else if (issue_uop[i].uop.is_branch && branch_taken[i]) begin
                        branch_target[i] = issue_uop[i].uop.pc + issue_uop[i].uop.imm_b;
                    end
                    result[i] = issue_uop[i].uop.pc + 32'd4;
                end
                TUBE_TYPE_MUL: begin
                    result[i] = 32'b0;
                end
                TUBE_TYPE_MEM: begin
                    if ((i == MEM_SLOT) && mem_req_valid) begin
                        result[i] = mem_req_head_addr;
                    end else begin
                        result[i] = src0[i] +
                                    (issue_uop[i].uop.is_store ?
                                     issue_uop[i].uop.imm_s : issue_uop[i].uop.imm_i);
                    end
                end
                TUBE_TYPE_SYS: begin
                    result[i] = csr_read_data_i[i];
                    if (issue_uop[i].uop.is_csr) begin
                        csr_do_write[i] = csr_writes(issue_uop[i].uop);
                        unique case (issue_uop[i].uop.csr_op)
                            CSR_OP_RW: begin
                                csr_new_value[i] = csr_operand[i];
                            end
                            CSR_OP_RS: begin
                                csr_new_value[i] = csr_read_data_i[i] | csr_operand[i];
                            end
                            CSR_OP_RC: begin
                                csr_new_value[i] = csr_read_data_i[i] & ~csr_operand[i];
                            end
                            default: begin
                                csr_new_value[i] = csr_read_data_i[i];
                            end
                        endcase
                    end
                end
                default: begin
                    result[i] = alu_result(issue_uop[i].uop, src0[i], src1[i]);
                end
            endcase

            if (issue_uop[i].uop.is_csr) begin
                csr_fault[i] = !csr_exists(issue_uop[i].uop.csr_addr) ||
                               csr_priv_fault(issue_uop[i].uop.csr_addr, csr_priv_mode_i) ||
                               (csr_do_write[i] && csr_write_readonly(issue_uop[i].uop.csr_addr));
                if (csr_fault[i]) begin
                    dynamic_exception[i] = 1'b1;
                    dynamic_exception_cause[i] = EXC_CAUSE_ILLEGAL_INST;
                end
            end

            if ((issue_uop[i].uop.is_load || issue_uop[i].uop.is_store) &&
                mem_misaligned(issue_uop[i].uop, result[i])) begin
                mem_align_fault[i] = 1'b1;
                dynamic_exception[i] = 1'b1;
                dynamic_exception_cause[i] = issue_uop[i].uop.is_load ?
                                             EXC_CAUSE_LOAD_MISALIGNED :
                                             EXC_CAUSE_STORE_MISALIGNED;
            end

            if (issue_uop[i].uop.is_mret && (csr_priv_mode_i != PRIV_M)) begin
                dynamic_exception[i] = 1'b1;
                dynamic_exception_cause[i] = EXC_CAUSE_ILLEGAL_INST;
            end

            if (issue_uop[i].uop.is_ecall) begin
                dynamic_exception[i] = 1'b1;
                dynamic_exception_cause[i] = (csr_priv_mode_i == PRIV_M) ?
                                             EXC_CAUSE_ECALL_M : EXC_CAUSE_ECALL_U;
            end

            wb_valid_d[i] = issue_valid[i];
            wb_rob_idx_d[i] = issue_uop[i].rob_idx;
            wb_prd_d[i] = issue_uop[i].prd;
            wb_result_d[i] = result[i];
            wb_exception_d[i] = issue_uop[i].uop.exception ||
                                dynamic_exception[i];
            wb_exception_cause_d[i] = dynamic_exception[i] ?
                                      dynamic_exception_cause[i] :
                                      issue_uop[i].uop.exception_cause;
            wb_branch_miss_d[i] = issue_valid[i] &&
                                  (issue_uop[i].uop.is_branch ||
                                   issue_uop[i].uop.is_jal ||
                                   issue_uop[i].uop.is_jalr) &&
                                  ((branch_taken[i] !=
                                    issue_uop[i].uop.pred_taken) ||
                                   (branch_taken[i] &&
                                    (branch_target[i] !=
                                     issue_uop[i].uop.pred_target)));
            wb_redirect_pc_d[i] = branch_target[i];
            wb_csr_write_d[i] = issue_valid[i] &&
                                issue_uop[i].uop.is_csr &&
                                csr_do_write[i] && !csr_fault[i];
            wb_csr_addr_d[i] = issue_uop[i].uop.csr_addr;
            wb_csr_wdata_d[i] = csr_new_value[i];

            wb_prf_we_d[i] = issue_valid[i] && issue_uop[i].alloc_prd &&
                             !issue_uop[i].uop.is_store &&
                             !(issue_uop[i].uop.exception ||
                               dynamic_exception[i]);
        end

        if (!clear_i && mem_req_valid && !load_resp_complete &&
            mem_req_head_uop.uop.is_store && !mem_req_misaligned) begin
            store_push_valid_o = 1'b1;
            store_push_rob_idx_o = mem_req_head_uop.rob_idx;
            store_push_addr_o = mem_req_head_addr;
            store_push_data_o = mem_req_head_store_data;
            store_push_mask_o = mem_req_head_store_mask;
            store_push_data_valid_o = mem_req_head_store_data_valid;
            store_push_data_prd_o = mem_req_head_store_data_prd;
        end

        if (mem_req_complete && mem_req_head_uop.uop.is_load &&
            !mem_req_misaligned && load_forward_full_i) begin
                wb_result_d[INT_ISSUE_WIDTH] =
                    load_extend(mem_req_head_uop.uop, load_forward_data_i);
                wb_prf_we_d[INT_ISSUE_WIDTH] =
                    mem_req_head_uop.alloc_prd &&
                    !mem_req_head_uop.uop.exception;
        end

        if (mem_req_load_send) begin
            dmem.exReadEn = 1'b1;
            dmem.exReadAddr = mem_req_head_addr;
        end

        if (load_resp_complete) begin
            wb_valid_d[INT_ISSUE_WIDTH] = 1'b1;
            wb_rob_idx_d[INT_ISSUE_WIDTH] = load_meta_uop_q[0].rob_idx;
            wb_prd_d[INT_ISSUE_WIDTH] = load_meta_uop_q[0].prd;
            wb_result_d[INT_ISSUE_WIDTH] =
                load_extend(load_meta_uop_q[0].uop, dmem.exReadData);
            wb_exception_d[INT_ISSUE_WIDTH] =
                load_meta_uop_q[0].uop.exception;
            wb_exception_cause_d[INT_ISSUE_WIDTH] =
                load_meta_uop_q[0].uop.exception_cause;
            wb_branch_miss_d[INT_ISSUE_WIDTH] = 1'b0;
            wb_redirect_pc_d[INT_ISSUE_WIDTH] = '0;
            wb_csr_write_d[INT_ISSUE_WIDTH] = 1'b0;
            wb_csr_addr_d[INT_ISSUE_WIDTH] = '0;
            wb_csr_wdata_d[INT_ISSUE_WIDTH] = '0;
            wb_prf_we_d[INT_ISSUE_WIDTH] = load_meta_uop_q[0].alloc_prd;
        end

        wb_valid_d[MULDIV_SLOT] = !clear_i && muldiv_complete_valid;
        wb_rob_idx_d[MULDIV_SLOT] = muldiv_complete_uop.rob_idx;
        wb_prd_d[MULDIV_SLOT] = muldiv_complete_uop.prd;
        wb_result_d[MULDIV_SLOT] = muldiv_complete_result;
        wb_exception_d[MULDIV_SLOT] =
            muldiv_complete_uop.uop.exception;
        wb_exception_cause_d[MULDIV_SLOT] =
            muldiv_complete_uop.uop.exception_cause;
        wb_branch_miss_d[MULDIV_SLOT] = 1'b0;
        wb_redirect_pc_d[MULDIV_SLOT] = '0;
        wb_csr_write_d[MULDIV_SLOT] = 1'b0;
        wb_csr_addr_d[MULDIV_SLOT] = '0;
        wb_csr_wdata_d[MULDIV_SLOT] = '0;
        wb_prf_we_d[MULDIV_SLOT] = !clear_i &&
                                   muldiv_complete_valid &&
                                   muldiv_complete_uop.alloc_prd &&
                                   !muldiv_complete_uop.uop.exception;
    end

    // Valid owns reset/flush visibility. Wide payload is captured every cycle
    // without reset or enable so the new boundary does not create another
    // high-fanout control set across the completion bundle.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_valid_q <= '0;
        end else if (clear_i) begin
            wb_valid_q <= '0;
        end else begin
            wb_valid_q <= wb_valid_d;
        end
    end

    always_ff @(posedge clk) begin
        wb_rob_idx_q <= wb_rob_idx_d;
        wb_prd_q <= wb_prd_d;
        wb_result_q <= wb_result_d;
        wb_exception_q <= wb_exception_d;
        wb_exception_cause_q <= wb_exception_cause_d;
        wb_branch_miss_q <= wb_branch_miss_d;
        wb_redirect_pc_q <= wb_redirect_pc_d;
        wb_csr_write_q <= wb_csr_write_d;
        wb_csr_addr_q <= wb_csr_addr_d;
        wb_csr_wdata_q <= wb_csr_wdata_d;
        wb_prf_we_q <= wb_prf_we_d;
    end

    // Present the queue candidate independently of ready.  MulDivPipe forms
    // its own fire from valid_i && ready_o; feeding the already-gated fire
    // back as valid would create a ready/valid combinational loop when ready
    // distinguishes pipelined MUL from non-pipelined DIV/REM.
    assign muldiv_start = mul_issue_valid_i[0];

    CoreMulDivPipe u_muldiv (
        .clk(clk),
        .rst(rst),
        .clear_i(clear_i),
        .ready_o(muldiv_ready),
        .valid_i(muldiv_start),
        .uop_i(issue_uop[MULDIV_SLOT]),
        .src0_i(src0[MULDIV_SLOT]),
        .src1_i(src1[MULDIV_SLOT]),
        .complete_valid_o(muldiv_complete_valid),
        .complete_uop_o(muldiv_complete_uop),
        .complete_result_o(muldiv_complete_result)
    );

    CorePhysRegFile #(
        .READ_PORTS(READ_PORTS),
        .WRITE_PORTS(ISSUE_WIDTH)
    ) u_prf (
        .clk(clk),
        .raddr_i(prf_raddr),
        .rdata_o(prf_rdata),
        .we_i(prf_we),
        .waddr_i(prf_waddr),
        .wdata_i(prf_wdata)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_req_count_q <= '0;
            load_meta_count_q <= '0;
            store_drain_pending_q <= 1'b0;
        end else begin
            if (clear_i) begin
                // Requests not yet accepted by DCache are wrong-path and can
                // be discarded. Accepted reads retain metadata ownership and
                // drain in response order; their killed bits are set below.
                mem_req_count_q <= '0;
                store_drain_pending_q <= 1'b0;
            end else begin
                unique case ({mem_enqueue, mem_req_consume})
                    2'b10: mem_req_count_q <= mem_req_count_q + 1'b1;
                    2'b01: mem_req_count_q <= mem_req_count_q - 1'b1;
                    default: mem_req_count_q <= mem_req_count_q;
                endcase

                if (store_push_valid_o && store_push_ready_i) begin
                    store_drain_pending_q <= 1'b1;
                end else if (store_drain_pending_q && store_buffer_empty_i) begin
                    store_drain_pending_q <= 1'b0;
                end
            end

            // Recovery cannot cancel a read already accepted by DCache.
            // Consume a response that arrives on the recovery edge, then keep
            // all remaining owners until their in-order responses are drained.
            if (clear_i) begin
                if (load_meta_pop) begin
                    load_meta_count_q <= load_meta_count_q - 1'b1;
                end else begin
                    load_meta_count_q <= load_meta_count_q;
                end
            end else begin
                unique case ({load_meta_push, load_meta_pop})
                    2'b10: load_meta_count_q <= load_meta_count_q + 1'b1;
                    2'b01: load_meta_count_q <= load_meta_count_q - 1'b1;
                    default: load_meta_count_q <= load_meta_count_q;
                endcase
            end
        end
    end

    // Queue counts own all wide payload. Keeping request and response metadata
    // in a reset-free process avoids adding uop/address/data bundles to the
    // global asynchronous reset tree.
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (!clear_i) begin
                for (int e = 0; e < MEM_REQ_DEPTH; e++) begin
                    mem_req_store_data_q[e] <= mem_req_store_data_now[e];
                    mem_req_store_data_valid_q[e] <=
                        mem_req_store_data_valid_now[e];
                end
                if (mem_req_consume && (mem_req_count_q > 1)) begin
                    mem_req_uop_q[0] <= mem_req_uop_q[1];
                    mem_req_addr_q[0] <= mem_req_addr_q[1];
                    mem_req_store_data_q[0] <= mem_req_store_data_now[1];
                    mem_req_store_mask_q[0] <= mem_req_store_mask_q[1];
                    mem_req_store_data_valid_q[0] <=
                        mem_req_store_data_valid_now[1];
                    mem_req_store_data_prd_q[0] <=
                        mem_req_store_data_prd_q[1];
                end

                if (mem_enqueue) begin
                    if (mem_req_consume && (mem_req_count_q <= 1)) begin
                        mem_req_uop_q[0] <= mem_enqueue_uop;
                        mem_req_addr_q[0] <= mem_enqueue_addr;
                        mem_req_store_data_q[0] <= mem_enqueue_store_data;
                        mem_req_store_mask_q[0] <= mem_enqueue_store_mask;
                        mem_req_store_data_valid_q[0] <=
                            mem_enqueue_store_data_valid;
                        mem_req_store_data_prd_q[0] <=
                            mem_enqueue_store_data_prd;
                    end else begin
                        mem_req_uop_q[mem_req_count_q[0]] <=
                            mem_enqueue_uop;
                        mem_req_addr_q[mem_req_count_q[0]] <=
                            mem_enqueue_addr;
                        mem_req_store_data_q[mem_req_count_q[0]] <=
                            mem_enqueue_store_data;
                        mem_req_store_mask_q[mem_req_count_q[0]] <=
                            mem_enqueue_store_mask;
                        mem_req_store_data_valid_q[mem_req_count_q[0]] <=
                            mem_enqueue_store_data_valid;
                        mem_req_store_data_prd_q[mem_req_count_q[0]] <=
                            mem_enqueue_store_data_prd;
                    end
                end
            end

            if (clear_i) begin
                load_meta_killed_q <= '1;
                if (load_meta_pop && (load_meta_count_q > 1)) begin
                    load_meta_uop_q[0] <= load_meta_uop_q[1];
                end
            end else begin
                if (load_meta_pop && (load_meta_count_q > 1)) begin
                    load_meta_uop_q[0] <= load_meta_uop_q[1];
                    load_meta_killed_q[0] <= load_meta_killed_q[1];
                end

                if (load_meta_push) begin
                    if (load_meta_pop) begin
                        if (load_meta_count_q > 1) begin
                            load_meta_uop_q[1] <= mem_req_head_uop;
                            load_meta_killed_q[1] <= 1'b0;
                        end else begin
                            load_meta_uop_q[0] <= mem_req_head_uop;
                            load_meta_killed_q[0] <= 1'b0;
                        end
                    end else begin
                        load_meta_uop_q[load_meta_count_q[0]] <=
                            mem_req_head_uop;
                        load_meta_killed_q[load_meta_count_q[0]] <= 1'b0;
                    end
                end
            end
        end
    end

    // A lookahead candidate is only a probe on its launch edge.  This
    // register owns the PRF/AGU result until the following-cycle accept/reject
    // response returns to the stable IQ slot.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_probe_valid_q <= 1'b0;
        end else if (clear_i) begin
            mem_probe_valid_q <= 1'b0;
        end else begin
            mem_probe_valid_q <= mem_issue_fire && mem_issue_lookahead_i;
            if (mem_issue_fire && mem_issue_lookahead_i) begin
                mem_probe_uop_q <= mem_issue_uop_i[0];
                mem_probe_addr_q <= prf_rdata[2 * MEM_SLOT] +
                                    mem_issue_uop_i[0].uop.imm_i;
                mem_probe_store_data_q <= prf_rdata[2 * MEM_SLOT + 1];
                mem_probe_store_mask_q <= store_mask(mem_issue_uop_i[0].uop);
                mem_probe_slot_q <= mem_issue_slot_i;
                mem_probe_age_q <= mem_issue_age_i;
            end
        end
    end

    assign perf_load_pending_o = (load_meta_count_q != '0);
    assign perf_mem_req_valid_o = mem_req_valid;
    assign perf_mem_req_partial_alias_o = mem_req_valid &&
                                          mem_req_head_uop.uop.is_load &&
                                          load_forward_hit_i &&
                                          !load_forward_full_i;
    assign perf_mem_req_no_alias_o = mem_req_valid &&
                                     mem_req_head_uop.uop.is_load &&
                                     !load_forward_hit_i &&
                                     !store_buffer_empty_i;
    assign perf_mem_req_forward_o = mem_req_valid &&
                                    mem_req_head_uop.uop.is_load &&
                                    load_forward_full_i;
    assign perf_muldiv_busy_o = !clear_i && !muldiv_ready;

`ifdef VERILATOR_TB
    logic mem_req_stalled_prev_q;
    CoreRenamedUop mem_req_uop_prev_q;
    AddrPath mem_req_addr_prev_q;
    DataPath mem_req_store_data_prev_q;
    logic [3:0] mem_req_store_mask_prev_q;
    logic mem_req_store_data_valid_prev_q;
    PhyRegNumPath mem_req_store_data_prd_prev_q;

    always_ff @(posedge clk) begin
        if (rst || clear_i) begin
            mem_req_stalled_prev_q <= 1'b0;
        end else begin
            if (mem_req_stalled_prev_q) begin
                assert (mem_req_valid &&
                        (mem_req_head_uop == mem_req_uop_prev_q) &&
                        (mem_req_head_addr == mem_req_addr_prev_q) &&
                        (mem_req_head_store_mask == mem_req_store_mask_prev_q) &&
                        (mem_req_head_store_data_prd ==
                         mem_req_store_data_prd_prev_q))
                    else $error("MEM request payload changed while stalled");
                if (mem_req_store_data_valid_prev_q) begin
                    assert (mem_req_head_store_data_valid &&
                            (mem_req_head_store_data ==
                             mem_req_store_data_prev_q))
                        else $error("ready store data changed while stalled");
                end
            end
            assert (mem_req_count_q <=
                    MEM_REQ_COUNT_BITS'(MEM_REQ_DEPTH))
                else $error("MEM request queue overflow");
            assert (load_meta_count_q <=
                    LOAD_META_COUNT_BITS'(LOAD_META_DEPTH))
                else $error("load metadata queue overflow");
            if (mem_probe_resolve_accept_o) begin
                assert (mem_probe_uop_q.uop.is_load &&
                        mem_probe_cacheable && !mem_probe_misaligned)
                    else $error("MEM lookahead accepted unsafe probe");
            end
            if (dmem.exReadReady) begin
                assert (load_meta_count_q != '0)
                    else $error("load response arrived without metadata owner");
            end
            if (load_meta_push) begin
                assert (load_meta_space)
                    else $error("load metadata pushed while full");
            end
            assert (!(dmem.exReadEn && load_forward_hit_i))
                else $error("load bypassed an older same-word store");
            for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
                if (prf_we[i]) begin
                    assert (complete_valid_o[i] &&
                            (complete_prd_o[i] == prf_waddr[i]) &&
                            (complete_result_o[i] == prf_wdata[i]))
                        else $error("PRF write and completion lost alignment");
                end
                for (int j = i + 1; j < ISSUE_WIDTH; j = j + 1) begin
                    assert (!(prf_we[i] && prf_we[j] &&
                              (prf_waddr[i] != '0) &&
                              (prf_waddr[i] == prf_waddr[j])))
                        else $error("multiple completions wrote the same PRF");
                end
            end
            mem_req_stalled_prev_q <= mem_req_valid && !mem_req_consume;
            mem_req_uop_prev_q <= mem_req_head_uop;
            mem_req_addr_prev_q <= mem_req_head_addr;
            mem_req_store_data_prev_q <= mem_req_head_store_data;
            mem_req_store_mask_prev_q <= mem_req_head_store_mask;
            mem_req_store_data_valid_prev_q <=
                mem_req_head_store_data_valid;
            mem_req_store_data_prd_prev_q <= mem_req_head_store_data_prd;
        end
    end
`endif
endmodule : CoreExecuteCluster
