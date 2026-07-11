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
    input  logic store_push_ready_i,
    input  logic store_buffer_empty_i,

    output logic load_query_valid_o,
    output AddrPath load_query_addr_o,
    output logic [3:0] load_query_mask_o,
    input  logic load_forward_full_i,
    input  DataPath load_forward_data_i,

    DramAccessIF.ExecuteMemStage dmem
);
    localparam int READ_PORTS = ISSUE_WIDTH * 2;
    localparam int MULDIV_SLOT = INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH;

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
    logic mem_load_pending_q;
    CoreRenamedUop mem_load_uop_q;
    AddrPath mem_load_addr_q;
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

    // Arbitration is kept separate from result generation.  The readiness
    // outputs only depend on registered resource state and StoreBuffer state.
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            issue_valid[i] = 1'b0;
            issue_uop[i] = '0;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            int_issue_ready_o[i] = !clear_i && !mem_load_pending_q;
            issue_valid[i] = int_issue_valid_i[i] && int_issue_ready_o[i];
            issue_uop[i] = int_issue_uop_i[i];
        end
        for (int m = 0; m < MEM_ISSUE_WIDTH; m = m + 1) begin
            issue_uop[INT_ISSUE_WIDTH + m] = mem_issue_uop_i[m];
            mem_issue_ready_o[m] = !clear_i && !mem_load_pending_q &&
                                   (!mem_issue_valid_i[m] ||
                                    (mem_issue_uop_i[m].uop.is_store && store_push_ready_i) ||
                                    (mem_issue_uop_i[m].uop.is_load &&
                                     (load_forward_full_i ||
                                      (store_buffer_empty_i && !store_drain_pending_q))));
            issue_valid[INT_ISSUE_WIDTH + m] = mem_issue_valid_i[m] && mem_issue_ready_o[m];
        end
        for (int u = 0; u < MULDIV_ISSUE_WIDTH; u = u + 1) begin
            mul_issue_ready_o[u] = !clear_i && (u == 0) && muldiv_ready;
            issue_valid[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_valid_i[u] && mul_issue_ready_o[u];
            issue_uop[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_uop_i[u];
        end
    end

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            prf_raddr[2*i] = issue_uop[i].prs1;
            prf_raddr[2*i + 1] = issue_uop[i].prs2;
        end
    end

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            csr_read_addr_o[i] = issue_uop[i].uop.csr_addr;
        end
    end

    // Store forwarding must be visible before the load is admitted.  Generate
    // the query from the selected load and its PRF read address, independently
    // of the result/writeback combinational block below.
    always_comb begin
        load_query_valid_o = 1'b0;
        load_query_addr_o = '0;
        load_query_mask_o = '0;
        if (mem_issue_valid_i[0] && mem_issue_uop_i[0].uop.is_load) begin
            load_query_addr_o = prf_rdata[2 * INT_ISSUE_WIDTH] +
                                mem_issue_uop_i[0].uop.imm_i;
            load_query_mask_o = load_mask(mem_issue_uop_i[0].uop, load_query_addr_o);
            load_query_valid_o = !mem_misaligned(mem_issue_uop_i[0].uop,
                                                  load_query_addr_o);
        end
    end

    always_comb begin
        dmem.exReadEn = 1'b0;
        dmem.exReadAddr = mem_load_addr_q;
        store_push_valid_o = 1'b0;
        store_push_rob_idx_o = '0;
        store_push_addr_o = '0;
        store_push_data_o = '0;
        store_push_mask_o = '0;
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            src0[i] = prf_rdata[2*i];
            src1[i] = prf_rdata[2*i + 1];

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
                    result[i] = src0[i] + (issue_uop[i].uop.is_store ? issue_uop[i].uop.imm_s : issue_uop[i].uop.imm_i);
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

            complete_valid_o[i] = issue_valid[i];
            complete_rob_idx_o[i] = issue_uop[i].rob_idx;
            complete_prd_o[i] = issue_uop[i].prd;
            complete_result_o[i] = result[i];
            complete_exception_o[i] = issue_uop[i].uop.exception || dynamic_exception[i];
            complete_exception_cause_o[i] = dynamic_exception[i] ? dynamic_exception_cause[i] :
                                            issue_uop[i].uop.exception_cause;
            complete_branch_miss_o[i] = issue_valid[i] &&
                                        (issue_uop[i].uop.is_branch ||
                                         issue_uop[i].uop.is_jal ||
                                         issue_uop[i].uop.is_jalr) &&
                                        ((branch_taken[i] != issue_uop[i].uop.pred_taken) ||
                                         (branch_taken[i] && (branch_target[i] != issue_uop[i].uop.pred_target)));
            complete_redirect_pc_o[i] = branch_target[i];
            complete_csr_write_o[i] = issue_valid[i] && issue_uop[i].uop.is_csr &&
                                      csr_do_write[i] && !csr_fault[i];
            complete_csr_addr_o[i] = issue_uop[i].uop.csr_addr;
            complete_csr_wdata_o[i] = csr_new_value[i];

            prf_we[i] = issue_valid[i] && issue_uop[i].alloc_prd &&
                        !issue_uop[i].uop.is_store &&
                        !(issue_uop[i].uop.exception || dynamic_exception[i]);
            prf_waddr[i] = issue_uop[i].prd;
            prf_wdata[i] = result[i];
        end

        if (issue_valid[INT_ISSUE_WIDTH] &&
            issue_uop[INT_ISSUE_WIDTH].uop.is_store &&
            !mem_align_fault[INT_ISSUE_WIDTH]) begin
            store_push_valid_o = 1'b1;
            store_push_rob_idx_o = issue_uop[INT_ISSUE_WIDTH].rob_idx;
            store_push_addr_o = result[INT_ISSUE_WIDTH];
            store_push_data_o = src1[INT_ISSUE_WIDTH];
            store_push_mask_o = store_mask(issue_uop[INT_ISSUE_WIDTH].uop);
        end

        if (issue_valid[INT_ISSUE_WIDTH] &&
            issue_uop[INT_ISSUE_WIDTH].uop.is_load &&
            !mem_align_fault[INT_ISSUE_WIDTH]) begin
            if (load_forward_full_i) begin
                complete_result_o[INT_ISSUE_WIDTH] = load_extend(issue_uop[INT_ISSUE_WIDTH].uop,
                                                                 load_forward_data_i);
                prf_we[INT_ISSUE_WIDTH] = issue_uop[INT_ISSUE_WIDTH].alloc_prd &&
                                          !issue_uop[INT_ISSUE_WIDTH].uop.exception;
                prf_waddr[INT_ISSUE_WIDTH] = issue_uop[INT_ISSUE_WIDTH].prd;
                prf_wdata[INT_ISSUE_WIDTH] = load_extend(issue_uop[INT_ISSUE_WIDTH].uop,
                                                         load_forward_data_i);
            end else begin
                dmem.exReadEn = 1'b1;
                dmem.exReadAddr = result[INT_ISSUE_WIDTH];
                complete_valid_o[INT_ISSUE_WIDTH] = 1'b0;
                prf_we[INT_ISSUE_WIDTH] = 1'b0;
            end
        end

        if (!clear_i && mem_load_pending_q && dmem.exReadReady) begin
            complete_valid_o[INT_ISSUE_WIDTH] = 1'b1;
            complete_rob_idx_o[INT_ISSUE_WIDTH] = mem_load_uop_q.rob_idx;
            complete_prd_o[INT_ISSUE_WIDTH] = mem_load_uop_q.prd;
            complete_result_o[INT_ISSUE_WIDTH] = load_extend(mem_load_uop_q.uop, dmem.exReadData);
            complete_exception_o[INT_ISSUE_WIDTH] = mem_load_uop_q.uop.exception;
            complete_exception_cause_o[INT_ISSUE_WIDTH] = mem_load_uop_q.uop.exception_cause;
            complete_branch_miss_o[INT_ISSUE_WIDTH] = 1'b0;
            complete_redirect_pc_o[INT_ISSUE_WIDTH] = '0;
            complete_csr_write_o[INT_ISSUE_WIDTH] = 1'b0;
            complete_csr_addr_o[INT_ISSUE_WIDTH] = '0;
            complete_csr_wdata_o[INT_ISSUE_WIDTH] = '0;
            prf_we[INT_ISSUE_WIDTH] = mem_load_uop_q.alloc_prd;
            prf_waddr[INT_ISSUE_WIDTH] = mem_load_uop_q.prd;
            prf_wdata[INT_ISSUE_WIDTH] = load_extend(mem_load_uop_q.uop, dmem.exReadData);
        end

        complete_valid_o[MULDIV_SLOT] = !clear_i && muldiv_complete_valid;
        complete_rob_idx_o[MULDIV_SLOT] = muldiv_complete_uop.rob_idx;
        complete_prd_o[MULDIV_SLOT] = muldiv_complete_uop.prd;
        complete_result_o[MULDIV_SLOT] = muldiv_complete_result;
        complete_exception_o[MULDIV_SLOT] = muldiv_complete_uop.uop.exception;
        complete_exception_cause_o[MULDIV_SLOT] = muldiv_complete_uop.uop.exception_cause;
        complete_branch_miss_o[MULDIV_SLOT] = 1'b0;
        complete_redirect_pc_o[MULDIV_SLOT] = '0;
        complete_csr_write_o[MULDIV_SLOT] = 1'b0;
        complete_csr_addr_o[MULDIV_SLOT] = '0;
        complete_csr_wdata_o[MULDIV_SLOT] = '0;
        prf_we[MULDIV_SLOT] = !clear_i &&
                              muldiv_complete_valid &&
                              muldiv_complete_uop.alloc_prd &&
                              !muldiv_complete_uop.uop.exception;
        prf_waddr[MULDIV_SLOT] = muldiv_complete_uop.prd;
        prf_wdata[MULDIV_SLOT] = muldiv_complete_result;
    end

    assign muldiv_start = issue_valid[MULDIV_SLOT];

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

    logic unused_seq;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            unused_seq <= 1'b0;
            mem_load_pending_q <= 1'b0;
            mem_load_uop_q <= '0;
            mem_load_addr_q <= '0;
            store_drain_pending_q <= 1'b0;
        end else begin
            unused_seq <= clear_i;
            if (clear_i) begin
                mem_load_pending_q <= 1'b0;
                mem_load_uop_q <= '0;
                mem_load_addr_q <= '0;
                store_drain_pending_q <= 1'b0;
            end else if (mem_load_pending_q && dmem.exReadReady) begin
                mem_load_pending_q <= 1'b0;
            end else if (issue_valid[INT_ISSUE_WIDTH] &&
                         issue_uop[INT_ISSUE_WIDTH].uop.is_load &&
                         !mem_align_fault[INT_ISSUE_WIDTH] &&
                         !load_forward_full_i) begin
                mem_load_pending_q <= 1'b1;
                mem_load_uop_q <= issue_uop[INT_ISSUE_WIDTH];
                mem_load_addr_q <= result[INT_ISSUE_WIDTH];
            end

            if (store_push_valid_o && store_push_ready_i) begin
                store_drain_pending_q <= 1'b1;
            end else if (store_drain_pending_q && store_buffer_empty_i) begin
                store_drain_pending_q <= 1'b0;
            end
        end
    end
endmodule : CoreExecuteCluster
