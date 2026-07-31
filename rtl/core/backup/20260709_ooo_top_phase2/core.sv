import CoreConfigPkg::*;
import CoreTypesPkg::*;

module core(
    input logic clk,
    input logic rst,

    IromAccessIF.core iromAccess,
    DramAccessIF      dromAccess,
    DebugIF.core      debug,
    PerfIF.core       perf
);
    typedef enum logic [2:0] {
        ST_FETCH_REQ,
        ST_FETCH_WAIT,
        ST_EXEC,
        ST_MEM_REQ,
        ST_MEM_WAIT,
        ST_MEM_RESP,
        ST_STORE_COMMIT,
        ST_DIV
    } core_state_t;

    localparam logic [1:0] PRIV_U = 2'd0;
    localparam logic [1:0] PRIV_M = 2'd3;

    localparam logic [6:0] OPC_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_MISC   = 7'b0001111;
    localparam logic [6:0] OPC_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPC_STORE  = 7'b0100011;
    localparam logic [6:0] OPC_OP     = 7'b0110011;
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_BRANCH = 7'b1100011;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_SYSTEM = 7'b1110011;

    logic [31:0] regs_q [31:0];
    core_state_t state_q;
    PcPath pc_q;
    PcPath inst_pc_q;
    InstPath inst_q;

    logic [1:0] priv_mode_q;
    logic [31:0] mstatus_q;
    logic [31:0] mtvec_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;
    logic [31:0] mscratch_q;
    logic [31:0] mie_q;
    logic [31:0] medeleg_q;
    logic [31:0] mideleg_q;
    logic [31:0] mcounteren_q;
    logic [31:0] scounteren_q;
    logic [31:0] satp_q;
    logic [31:0] stvec_q;
    logic [31:0] pmpcfg0_q;
    logic [31:0] pmpaddr0_q;

    logic [31:0] mem_addr_q;
    logic [31:0] mem_wdata_q;
    logic [3:0]  mem_wmask_q;
    logic [2:0]  mem_funct3_q;
    logic [4:0]  mem_rd_q;

    logic [4:0]  div_rd_q;
    logic [2:0]  div_funct3_q;
    logic [31:0] div_lhs_q;
    logic [31:0] div_rhs_q;
    logic [31:0] div_dividend_q;
    logic [31:0] div_divisor_q;
    logic [31:0] div_quotient_q;
    logic [32:0] div_remainder_q;
    logic [5:0]  div_count_q;
    logic        div_neg_quot_q;
    logic        div_neg_rem_q;
    logic        div_by_zero_q;
    logic        div_overflow_q;

    function automatic logic [31:0] abs32(input logic [31:0] value);
        abs32 = value[31] ? (~value + 32'd1) : value;
    endfunction

    function automatic logic [31:0] load_extend(
        input logic [31:0] raw,
        input logic [2:0] funct3
    );
        unique case (funct3)
            3'b000: load_extend = {{24{raw[7]}}, raw[7:0]};
            3'b001: load_extend = {{16{raw[15]}}, raw[15:0]};
            3'b010: load_extend = raw;
            3'b100: load_extend = {24'b0, raw[7:0]};
            3'b101: load_extend = {16'b0, raw[15:0]};
            default: load_extend = raw;
        endcase
    endfunction

    function automatic logic [31:0] store_data(
        input logic [31:0] raw,
        input logic [2:0] funct3
    );
        unique case (funct3)
            3'b000: store_data = {24'b0, raw[7:0]};
            3'b001: store_data = {16'b0, raw[15:0]};
            default: store_data = raw;
        endcase
    endfunction

    function automatic logic [3:0] store_mask(input logic [2:0] funct3);
        unique case (funct3)
            3'b000: store_mask = 4'b0001;
            3'b001: store_mask = 4'b0011;
            3'b010: store_mask = 4'b1111;
            default: store_mask = 4'b0000;
        endcase
    endfunction

    function automatic logic [31:0] csr_read(input logic [11:0] csr_addr);
        unique case (csr_addr)
            12'h100: csr_read = 32'b0;
            12'h105: csr_read = stvec_q;
            12'h106: csr_read = scounteren_q;
            12'h180: csr_read = satp_q;
            12'h300: csr_read = mstatus_q;
            12'h301: csr_read = 32'h4010_1100;
            12'h302: csr_read = medeleg_q;
            12'h303: csr_read = mideleg_q;
            12'h304: csr_read = mie_q;
            12'h305: csr_read = mtvec_q;
            12'h306: csr_read = mcounteren_q;
            12'h340: csr_read = mscratch_q;
            12'h341: csr_read = mepc_q;
            12'h342: csr_read = mcause_q;
            12'h343: csr_read = mtval_q;
            12'h3a0: csr_read = pmpcfg0_q;
            12'h3b0: csr_read = pmpaddr0_q;
            12'hc00: csr_read = perf.cycle[31:0];
            12'hc01: csr_read = perf.cycle[31:0];
            12'hc02: csr_read = perf.commitCnt[31:0];
            12'hc80: csr_read = perf.cycle[63:32];
            12'hc81: csr_read = perf.cycle[63:32];
            12'hc82: csr_read = perf.commitCnt[63:32];
            12'hf14: csr_read = 32'b0;
            default: csr_read = 32'b0;
        endcase
    endfunction

    function automatic logic csr_write_readonly(input logic [11:0] csr_addr);
        csr_write_readonly = (csr_addr[11:10] == 2'b11);
    endfunction

    function automatic logic csr_priv_fault(input logic [11:0] csr_addr);
        csr_priv_fault = (priv_mode_q < csr_addr[9:8]);
    endfunction

    task automatic write_gpr(input logic [4:0] rd, input logic [31:0] value);
        if (rd != 5'd0) begin
            regs_q[rd] <= value;
        end
    endtask

    task automatic write_csr(input logic [11:0] csr_addr, input logic [31:0] value);
        unique case (csr_addr)
            12'h100: begin end
            12'h105: stvec_q <= value;
            12'h106: scounteren_q <= value;
            12'h180: satp_q <= value;
            12'h300: mstatus_q <= value;
            12'h302: medeleg_q <= value;
            12'h303: mideleg_q <= value;
            12'h304: mie_q <= value;
            12'h305: mtvec_q <= value;
            12'h306: mcounteren_q <= value;
            12'h340: mscratch_q <= value;
            12'h341: mepc_q <= value;
            12'h342: mcause_q <= value;
            12'h343: mtval_q <= value;
            12'h3a0: pmpcfg0_q <= value;
            12'h3b0: pmpaddr0_q <= value;
            default: begin end
        endcase
    endtask

    task automatic take_trap(input logic [31:0] cause, input logic [31:0] tval);
        mepc_q <= inst_pc_q;
        mcause_q <= cause;
        mtval_q <= tval;
        mstatus_q[12:11] <= priv_mode_q;
        priv_mode_q <= PRIV_M;
        pc_q <= {mtvec_q[31:2], 2'b00};
        state_q <= ST_FETCH_REQ;
        perf.recoveryCycles <= perf.recoveryCycles + 64'd1;
    endtask

    wire logic [6:0] opcode = inst_q[6:0];
    wire logic [4:0] rd     = inst_q[11:7];
    wire logic [2:0] funct3 = inst_q[14:12];
    wire logic [4:0] rs1    = inst_q[19:15];
    wire logic [4:0] rs2    = inst_q[24:20];
    wire logic [6:0] funct7 = inst_q[31:25];

    wire logic [31:0] rs1_val = (rs1 == 5'd0) ? 32'b0 : regs_q[rs1];
    wire logic [31:0] rs2_val = (rs2 == 5'd0) ? 32'b0 : regs_q[rs2];
    wire logic [31:0] imm_i = {{20{inst_q[31]}}, inst_q[31:20]};
    wire logic [31:0] imm_s = {{20{inst_q[31]}}, inst_q[31:25], inst_q[11:7]};
    wire logic [31:0] imm_b = {{19{inst_q[31]}}, inst_q[31], inst_q[7],
                               inst_q[30:25], inst_q[11:8], 1'b0};
    wire logic [31:0] imm_u = {inst_q[31:12], 12'b0};
    wire logic [31:0] imm_j = {{11{inst_q[31]}}, inst_q[31], inst_q[19:12],
                               inst_q[20], inst_q[30:21], 1'b0};

    logic exec_prefetch_valid;
    PcPath exec_prefetch_addr;

    CoreFetchPacket shadow_fetch_pkt;
    logic [FETCH_WIDTH-1:0] shadow_fetch_push_valid;
    CoreFetchPacket [FETCH_WIDTH-1:0] shadow_fetch_push_pkt;
    logic [FETCH_WIDTH-1:0] shadow_fetch_push_ready;
    logic [DECODE_WIDTH-1:0] shadow_fetch_pop_valid;
    CoreFetchPacket [DECODE_WIDTH-1:0] shadow_fetch_pop_pkt;
    logic [DECODE_WIDTH-1:0] shadow_fetch_pop_ready;
    logic [DECODE_WIDTH-1:0] shadow_decode_valid;
    CoreDecodeUop [DECODE_WIDTH-1:0] shadow_decode_uop_vec;
    logic [DECODE_WIDTH-1:0] shadow_decode_ready;
    logic shadow_backend_recover_valid;
    logic shadow_backend_recover_q;
    PcPath shadow_backend_recover_pc;
    logic [RETIRE_WIDTH-1:0] shadow_commit_valid;
    CoreRobEntry [RETIRE_WIDTH-1:0] shadow_commit_entry;
    logic [63:0] shadow_commit_count_q;
    logic [63:0] shadow_recover_count_q;
    logic shadow_commit_rd_seen_q;
    logic [63:0] shadow_stream_match_count_q;
    logic [63:0] shadow_stream_mismatch_count_q;
    PcPath shadow_last_mismatch_pc_q;
    InstPath shadow_last_mismatch_inst_q;
    logic shadow_result_trust_q;
    logic [63:0] shadow_result_match_count_q;
    logic [63:0] shadow_result_mismatch_count_q;
    PcPath shadow_last_result_mismatch_pc_q;
    InstPath shadow_last_result_mismatch_inst_q;
    DataPath shadow_last_result_expected_q;
    DataPath shadow_last_result_actual_q;

    always_comb begin
        shadow_fetch_pkt = '0;
        shadow_fetch_pkt.valid = (state_q == ST_EXEC) && (inst_q[1:0] == 2'b11);
        shadow_fetch_pkt.pc = inst_pc_q;
        shadow_fetch_pkt.inst = inst_q;
        shadow_fetch_pkt.pred_taken = 1'b0;
        shadow_fetch_pkt.pred_target = inst_pc_q + 32'd4;

        shadow_fetch_push_valid = '0;
        shadow_fetch_push_valid[0] = shadow_fetch_pkt.valid;
        shadow_fetch_push_pkt = '0;
        shadow_fetch_push_pkt[0] = shadow_fetch_pkt;

        shadow_fetch_pop_ready = '1;
        shadow_decode_valid = shadow_fetch_pop_valid;
    end

    logic [RETIRE_WIDTH-1:0] shadow_commit_real;
    logic [2:0] shadow_commit_inc;
    logic shadow_commit_rd_nonzero;
    logic seq_commit_valid;
    logic seq_commit_writes_rd;
    logic seq_commit_result_supported;
    DataPath seq_commit_expected_result;
    logic [63:0] seq_mul_u;
    logic signed [63:0] seq_mul_s;
    logic signed [63:0] seq_mul_hsu;
    logic shadow_stream_check_valid;
    logic shadow_stream_match;
    logic shadow_result_check_valid;
    logic shadow_result_match;

    always_comb begin
        shadow_commit_real = shadow_commit_valid;
        shadow_commit_inc = 3'b0;
        shadow_commit_rd_nonzero = 1'b0;
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            if (shadow_commit_valid[i]) begin
                shadow_commit_inc = shadow_commit_inc + 3'd1;
            end
            if (shadow_commit_valid[i] && shadow_commit_entry[i].uop.writes_rd &&
                (shadow_commit_entry[i].uop.rd != 5'd0)) begin
                shadow_commit_rd_nonzero = 1'b1;
            end
        end

        seq_commit_valid = (state_q == ST_EXEC) &&
                           (inst_q[1:0] == 2'b11) &&
                           !((opcode == OPC_LOAD) ||
                             (opcode == OPC_STORE) ||
                             (opcode == OPC_SYSTEM) ||
                             ((opcode == OPC_OP) && (funct7 == 7'b0000001) &&
                              (funct3 inside {3'b100, 3'b101, 3'b110, 3'b111})));
        seq_commit_writes_rd = ((opcode == OPC_LUI) ||
                                (opcode == OPC_AUIPC) ||
                                (opcode == OPC_JAL) ||
                                (opcode == OPC_JALR) ||
                                (opcode == OPC_OP_IMM) ||
                                (opcode == OPC_OP)) &&
                               (rd != 5'd0);
        seq_mul_u = {32'b0, rs1_val} * {32'b0, rs2_val};
        seq_mul_s = $signed(rs1_val) * $signed(rs2_val);
        seq_mul_hsu = $signed({{32{rs1_val[31]}}, rs1_val}) * $signed({32'b0, rs2_val});

        seq_commit_result_supported = 1'b0;
        seq_commit_expected_result = 32'b0;
        unique case (opcode)
            OPC_LUI: begin
                seq_commit_result_supported = 1'b1;
                seq_commit_expected_result = imm_u;
            end
            OPC_AUIPC: begin
                seq_commit_result_supported = 1'b1;
                seq_commit_expected_result = inst_pc_q + imm_u;
            end
            OPC_OP_IMM: begin
                seq_commit_result_supported =
                    !((funct3 == 3'b001 && funct7 != 7'b0000000) ||
                      (funct3 == 3'b101 && !(funct7 inside {7'b0000000, 7'b0100000})));
                unique case (funct3)
                    3'b000: seq_commit_expected_result = rs1_val + imm_i;
                    3'b010: seq_commit_expected_result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0;
                    3'b011: seq_commit_expected_result = (rs1_val < imm_i) ? 32'd1 : 32'd0;
                    3'b100: seq_commit_expected_result = rs1_val ^ imm_i;
                    3'b110: seq_commit_expected_result = rs1_val | imm_i;
                    3'b111: seq_commit_expected_result = rs1_val & imm_i;
                    3'b001: seq_commit_expected_result = rs1_val << inst_q[24:20];
                    3'b101: begin
                        if (funct7 == 7'b0100000) begin
                            seq_commit_expected_result = $signed(rs1_val) >>> inst_q[24:20];
                        end else begin
                            seq_commit_expected_result = rs1_val >> inst_q[24:20];
                        end
                    end
                    default: seq_commit_expected_result = 32'b0;
                endcase
            end
            OPC_OP: begin
                if (funct7 == 7'b0000001) begin
                    seq_commit_result_supported = (funct3 inside {3'b000, 3'b001, 3'b010, 3'b011});
                    unique case (funct3)
                        3'b000: seq_commit_expected_result = seq_mul_u[31:0];
                        3'b001: seq_commit_expected_result = seq_mul_s[63:32];
                        3'b010: seq_commit_expected_result = seq_mul_hsu[63:32];
                        3'b011: seq_commit_expected_result = seq_mul_u[63:32];
                        default: seq_commit_expected_result = 32'b0;
                    endcase
                end else begin
                    seq_commit_result_supported = ({funct7, funct3} inside {
                        {7'b0000000, 3'b000}, {7'b0100000, 3'b000},
                        {7'b0000000, 3'b001}, {7'b0000000, 3'b010},
                        {7'b0000000, 3'b011}, {7'b0000000, 3'b100},
                        {7'b0000000, 3'b101}, {7'b0100000, 3'b101},
                        {7'b0000000, 3'b110}, {7'b0000000, 3'b111}});
                    unique case ({funct7, funct3})
                        {7'b0000000, 3'b000}: seq_commit_expected_result = rs1_val + rs2_val;
                        {7'b0100000, 3'b000}: seq_commit_expected_result = rs1_val - rs2_val;
                        {7'b0000000, 3'b001}: seq_commit_expected_result = rs1_val << rs2_val[4:0];
                        {7'b0000000, 3'b010}: seq_commit_expected_result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                        {7'b0000000, 3'b011}: seq_commit_expected_result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                        {7'b0000000, 3'b100}: seq_commit_expected_result = rs1_val ^ rs2_val;
                        {7'b0000000, 3'b101}: seq_commit_expected_result = rs1_val >> rs2_val[4:0];
                        {7'b0100000, 3'b101}: seq_commit_expected_result = $signed(rs1_val) >>> rs2_val[4:0];
                        {7'b0000000, 3'b110}: seq_commit_expected_result = rs1_val | rs2_val;
                        {7'b0000000, 3'b111}: seq_commit_expected_result = rs1_val & rs2_val;
                        default: seq_commit_expected_result = 32'b0;
                    endcase
                end
            end
            default: begin
                seq_commit_result_supported = 1'b0;
                seq_commit_expected_result = 32'b0;
            end
        endcase

        shadow_stream_check_valid = seq_commit_valid && shadow_commit_valid[0] &&
                                    !shadow_commit_entry[0].exception;
        shadow_stream_match = shadow_stream_check_valid &&
                              (shadow_commit_entry[0].uop.pc == inst_pc_q) &&
                              (shadow_commit_entry[0].uop.inst == inst_q) &&
                              (shadow_commit_entry[0].uop.rd == rd) &&
                              (shadow_commit_entry[0].uop.writes_rd == seq_commit_writes_rd);
        shadow_result_check_valid = shadow_stream_match &&
                                    shadow_result_trust_q &&
                                    seq_commit_result_supported &&
                                    seq_commit_writes_rd;
        shadow_result_match = shadow_result_check_valid &&
                              (shadow_commit_entry[0].result == seq_commit_expected_result);
    end

    CoreFetchBuffer u_shadow_fetch_buffer (
        .clk(clk),
        .rst(rst),
        .clear_i(shadow_backend_recover_q),
        .push_valid_i(shadow_fetch_push_valid),
        .push_pkt_i(shadow_fetch_push_pkt),
        .push_ready_o(shadow_fetch_push_ready),
        .pop_ready_i(shadow_fetch_pop_ready),
        .pop_valid_o(shadow_fetch_pop_valid),
        .pop_pkt_o(shadow_fetch_pop_pkt)
    );

    CoreRv32Decoder u_shadow_decoder0 (
        .fetch_i(shadow_fetch_pop_pkt[0]),
        .uop_o(shadow_decode_uop_vec[0])
    );

    CoreRv32Decoder u_shadow_decoder1 (
        .fetch_i(shadow_fetch_pop_pkt[1]),
        .uop_o(shadow_decode_uop_vec[1])
    );

    CoreBackend u_shadow_backend (
        .clk(clk),
        .rst(rst),
        .clear_i(1'b0),
        .recover_i(shadow_backend_recover_q),
        .decode_valid_i(shadow_decode_valid),
        .decode_uop_i(shadow_decode_uop_vec),
        .decode_ready_o(shadow_decode_ready),
        .recover_valid_o(shadow_backend_recover_valid),
        .recover_pc_o(shadow_backend_recover_pc),
        .commit_valid_o(shadow_commit_valid),
        .commit_entry_o(shadow_commit_entry)
    );

    always_comb begin
        exec_prefetch_valid = 1'b0;
        exec_prefetch_addr = inst_pc_q + 32'd4;

        if (state_q == ST_EXEC && inst_q[1:0] == 2'b11) begin
            unique case (opcode)
                OPC_LUI, OPC_AUIPC, OPC_MISC: begin
                    exec_prefetch_valid = 1'b1;
                    exec_prefetch_addr = inst_pc_q + 32'd4;
                end
                OPC_JAL: begin
                    exec_prefetch_valid = 1'b1;
                    exec_prefetch_addr = inst_pc_q + imm_j;
                end
                OPC_JALR: begin
                    exec_prefetch_valid = 1'b1;
                    exec_prefetch_addr = (rs1_val + imm_i) & 32'hffff_fffe;
                end
                OPC_BRANCH: begin
                    if (funct3 inside {3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111}) begin
                        logic taken;
                        unique case (funct3)
                            3'b000: taken = (rs1_val == rs2_val);
                            3'b001: taken = (rs1_val != rs2_val);
                            3'b100: taken = ($signed(rs1_val) < $signed(rs2_val));
                            3'b101: taken = ($signed(rs1_val) >= $signed(rs2_val));
                            3'b110: taken = (rs1_val < rs2_val);
                            default: taken = (rs1_val >= rs2_val);
                        endcase
                        exec_prefetch_valid = 1'b1;
                        exec_prefetch_addr = taken ? (inst_pc_q + imm_b) : (inst_pc_q + 32'd4);
                    end
                end
                OPC_OP_IMM: begin
                    exec_prefetch_valid =
                        !((funct3 == 3'b001 && funct7 != 7'b0000000) ||
                          (funct3 == 3'b101 && !(funct7 inside {7'b0000000, 7'b0100000})));
                    exec_prefetch_addr = inst_pc_q + 32'd4;
                end
                OPC_OP: begin
                    if (funct7 == 7'b0000001) begin
                        exec_prefetch_valid = (funct3 inside {3'b000, 3'b001, 3'b010, 3'b011});
                    end else begin
                        exec_prefetch_valid = ({funct7, funct3} inside {
                            {7'b0000000, 3'b000}, {7'b0100000, 3'b000},
                            {7'b0000000, 3'b001}, {7'b0000000, 3'b010},
                            {7'b0000000, 3'b011}, {7'b0000000, 3'b100},
                            {7'b0000000, 3'b101}, {7'b0100000, 3'b101},
                            {7'b0000000, 3'b110}, {7'b0000000, 3'b111}});
                    end
                    exec_prefetch_addr = inst_pc_q + 32'd4;
                end
                default: begin
                    exec_prefetch_valid = 1'b0;
                    exec_prefetch_addr = inst_pc_q + 32'd4;
                end
            endcase
        end

        iromAccess.ena = (state_q == ST_FETCH_REQ) ||
                         exec_prefetch_valid ||
                         (state_q == ST_MEM_RESP) ||
                         (state_q == ST_STORE_COMMIT) ||
                         (state_q == ST_DIV &&
                          (div_by_zero_q || div_overflow_q || div_count_q == 6'd31));
        if (exec_prefetch_valid) begin
            iromAccess.iromAddr = exec_prefetch_addr;
        end else begin
            iromAccess.iromAddr = pc_q;
        end

        dromAccess.exReadEn = (state_q == ST_MEM_REQ);
        dromAccess.exReadAddr = mem_addr_q;
        dromAccess.storeWriteEn = (state_q == ST_STORE_COMMIT);
        dromAccess.storeWriteAddr = mem_addr_q;
        dromAccess.storeWriteData = mem_wdata_q;
        dromAccess.storeWriteMask = mem_wmask_q;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= ST_FETCH_REQ;
            pc_q <= 32'h8000_0000;
            inst_pc_q <= 32'b0;
            inst_q <= 32'b0;
            priv_mode_q <= PRIV_M;
            mstatus_q <= 32'b0;
            mtvec_q <= 32'b0;
            mepc_q <= 32'b0;
            mcause_q <= 32'b0;
            mtval_q <= 32'b0;
            mscratch_q <= 32'b0;
            mie_q <= 32'b0;
            medeleg_q <= 32'b0;
            mideleg_q <= 32'b0;
            mcounteren_q <= 32'b0;
            scounteren_q <= 32'b0;
            satp_q <= 32'b0;
            stvec_q <= 32'b0;
            pmpcfg0_q <= 32'b0;
            pmpaddr0_q <= 32'b0;
            mem_addr_q <= 32'b0;
            mem_wdata_q <= 32'b0;
            mem_wmask_q <= 4'b0;
            mem_funct3_q <= 3'b0;
            mem_rd_q <= 5'b0;
            div_rd_q <= 5'b0;
            div_funct3_q <= 3'b0;
            div_lhs_q <= 32'b0;
            div_rhs_q <= 32'b0;
            div_dividend_q <= 32'b0;
            div_divisor_q <= 32'b0;
            div_quotient_q <= 32'b0;
            div_remainder_q <= 33'b0;
            div_count_q <= 6'b0;
            div_neg_quot_q <= 1'b0;
            div_neg_rem_q <= 1'b0;
            div_by_zero_q <= 1'b0;
            div_overflow_q <= 1'b0;
            shadow_backend_recover_q <= 1'b0;
            shadow_commit_count_q <= 64'b0;
            shadow_recover_count_q <= 64'b0;
            shadow_commit_rd_seen_q <= 1'b0;
            shadow_stream_match_count_q <= 64'b0;
            shadow_stream_mismatch_count_q <= 64'b0;
            shadow_last_mismatch_pc_q <= 32'b0;
            shadow_last_mismatch_inst_q <= 32'b0;
            shadow_result_trust_q <= 1'b1;
            shadow_result_match_count_q <= 64'b0;
            shadow_result_mismatch_count_q <= 64'b0;
            shadow_last_result_mismatch_pc_q <= 32'b0;
            shadow_last_result_mismatch_inst_q <= 32'b0;
            shadow_last_result_expected_q <= 32'b0;
            shadow_last_result_actual_q <= 32'b0;
            for (int i = 0; i < 32; i++) begin
                regs_q[i] <= 32'b0;
            end

            perf.cycle <= 64'b0;
            perf.commitCnt <= 64'b0;
            perf.branchCnt <= 64'b0;
            perf.branchMissCnt <= 64'b0;
            perf.condBranchCnt <= 64'b0;
            perf.condBranchMissCnt <= 64'b0;
            perf.jalCnt <= 64'b0;
            perf.jalMissCnt <= 64'b0;
            perf.jalrCnt <= 64'b0;
            perf.jalrMissCnt <= 64'b0;
            perf.frontendStallCycles <= 64'b0;
            perf.idStallCycles <= 64'b0;
            perf.rnStallCycles <= 64'b0;
            perf.dsStallCycles <= 64'b0;
            perf.isStallCycles <= 64'b0;
            perf.rrStallCycles <= 64'b0;
            perf.exStallCycles <= 64'b0;
            perf.wbStallCycles <= 64'b0;
            perf.robFullCycles <= 64'b0;
            perf.issueQueueFullCycles <= 64'b0;
            perf.intIssueQueueFullCycles <= 64'b0;
            perf.memIssueQueueFullCycles <= 64'b0;
            perf.mulIssueQueueFullCycles <= 64'b0;
            perf.robHeadNotDoneCycles <= 64'b0;
            perf.robHeadNotDoneIntCycles <= 64'b0;
            perf.robHeadNotDoneMemCycles <= 64'b0;
            perf.robHeadNotDoneMulCycles <= 64'b0;
            perf.robHeadNotDoneOtherCycles <= 64'b0;
            perf.robHeadStoreCommitWaitCycles <= 64'b0;
            perf.freeListEmptyCycles <= 64'b0;
            perf.storeBufferFullCycles <= 64'b0;
            perf.serialBlockCycles <= 64'b0;
            perf.memLoadReturnBlockCycles <= 64'b0;
            perf.memLoadAccessBlockCycles <= 64'b0;
            perf.storeCommitBlockedByLoadCycles <= 64'b0;
            perf.recoveryCycles <= 64'b0;
            perf.dispatchWidth0Cycles <= 64'b0;
            perf.dispatchWidth1Cycles <= 64'b0;
            perf.dispatchWidth2Cycles <= 64'b0;
            perf.issueWidth0Cycles <= 64'b0;
            perf.issueWidth1Cycles <= 64'b0;
            perf.issueWidth2Cycles <= 64'b0;
            perf.commitWidth0Cycles <= 64'b0;
            perf.commitWidth1Cycles <= 64'b0;
            perf.commitWidth2Cycles <= 64'b0;
            perf.intIssueCount <= 64'b0;
            perf.memIssueCount <= 64'b0;
            perf.mulIssueCount <= 64'b0;
        end else begin
            logic [31:0] alu_result;
            logic [31:0] next_pc;
            logic [31:0] csr_old;
            logic [31:0] csr_new;
            logic [31:0] csr_operand;
            logic        csr_do_write;
            logic        csr_illegal;
            logic        branch_taken;
            logic [63:0] mul_result;
            logic [32:0] div_rem_shift;
            logic [31:0] div_quot_next;
            logic [32:0] div_rem_next;
            logic [31:0] div_result;

            perf.cycle <= perf.cycle + 64'd1;
            regs_q[0] <= 32'b0;
            shadow_backend_recover_q <= shadow_backend_recover_valid;
            shadow_commit_count_q <= shadow_commit_count_q + {61'b0, shadow_commit_inc};
            shadow_commit_rd_seen_q <= shadow_commit_rd_seen_q | shadow_commit_rd_nonzero;
            if (shadow_backend_recover_valid) begin
                shadow_recover_count_q <= shadow_recover_count_q + 64'd1;
            end
            if (shadow_stream_check_valid) begin
                if (shadow_stream_match) begin
                    shadow_stream_match_count_q <= shadow_stream_match_count_q + 64'd1;
                end else begin
                    shadow_stream_mismatch_count_q <= shadow_stream_mismatch_count_q + 64'd1;
                    shadow_last_mismatch_pc_q <= inst_pc_q;
                    shadow_last_mismatch_inst_q <= inst_q;
                    shadow_result_trust_q <= 1'b0;
                end
            end
            if (seq_commit_valid && seq_commit_writes_rd && !seq_commit_result_supported) begin
                shadow_result_trust_q <= 1'b0;
            end
            if (shadow_result_check_valid) begin
                if (shadow_result_match) begin
                    shadow_result_match_count_q <= shadow_result_match_count_q + 64'd1;
                end else begin
                    shadow_result_mismatch_count_q <= shadow_result_mismatch_count_q + 64'd1;
                    shadow_last_result_mismatch_pc_q <= inst_pc_q;
                    shadow_last_result_mismatch_inst_q <= inst_q;
                    shadow_last_result_expected_q <= seq_commit_expected_result;
                    shadow_last_result_actual_q <= shadow_commit_entry[0].result;
                    shadow_result_trust_q <= 1'b0;
                end
            end

            unique case (state_q)
                ST_FETCH_REQ: begin
                    if (!debug.halt) begin
                        state_q <= ST_FETCH_WAIT;
                    end
                end

                ST_FETCH_WAIT: begin
                    inst_q <= iromAccess.inst[0];
                    inst_pc_q <= pc_q;
                    state_q <= ST_EXEC;
                end

                ST_EXEC: begin
                    next_pc = inst_pc_q + 32'd4;
                    alu_result = 32'b0;
                    branch_taken = 1'b0;
                    perf.commitCnt <= perf.commitCnt + 64'd1;
                    perf.commitWidth1Cycles <= perf.commitWidth1Cycles + 64'd1;
                    perf.issueWidth1Cycles <= perf.issueWidth1Cycles + 64'd1;
                    perf.dispatchWidth1Cycles <= perf.dispatchWidth1Cycles + 64'd1;

                    if (inst_q[1:0] != 2'b11) begin
                        take_trap(32'd2, inst_q);
                    end else begin
                        unique case (opcode)
                            OPC_LUI: begin
                                write_gpr(rd, imm_u);
                                pc_q <= next_pc;
                                state_q <= ST_FETCH_WAIT;
                                perf.intIssueCount <= perf.intIssueCount + 64'd1;
                            end

                            OPC_AUIPC: begin
                                write_gpr(rd, inst_pc_q + imm_u);
                                pc_q <= next_pc;
                                state_q <= ST_FETCH_WAIT;
                                perf.intIssueCount <= perf.intIssueCount + 64'd1;
                            end

                            OPC_JAL: begin
                                write_gpr(rd, inst_pc_q + 32'd4);
                                pc_q <= inst_pc_q + imm_j;
                                state_q <= ST_FETCH_WAIT;
                                perf.branchCnt <= perf.branchCnt + 64'd1;
                                perf.branchMissCnt <= perf.branchMissCnt + 64'd1;
                                perf.jalCnt <= perf.jalCnt + 64'd1;
                                perf.jalMissCnt <= perf.jalMissCnt + 64'd1;
                            end

                            OPC_JALR: begin
                                write_gpr(rd, inst_pc_q + 32'd4);
                                pc_q <= (rs1_val + imm_i) & 32'hffff_fffe;
                                state_q <= ST_FETCH_WAIT;
                                perf.branchCnt <= perf.branchCnt + 64'd1;
                                perf.branchMissCnt <= perf.branchMissCnt + 64'd1;
                                perf.jalrCnt <= perf.jalrCnt + 64'd1;
                                perf.jalrMissCnt <= perf.jalrMissCnt + 64'd1;
                            end

                            OPC_BRANCH: begin
                                unique case (funct3)
                                    3'b000: branch_taken = (rs1_val == rs2_val);
                                    3'b001: branch_taken = (rs1_val != rs2_val);
                                    3'b100: branch_taken = ($signed(rs1_val) < $signed(rs2_val));
                                    3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val));
                                    3'b110: branch_taken = (rs1_val < rs2_val);
                                    3'b111: branch_taken = (rs1_val >= rs2_val);
                                    default: branch_taken = 1'b0;
                                endcase
                                if (funct3 inside {3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111}) begin
                                    pc_q <= branch_taken ? (inst_pc_q + imm_b) : next_pc;
                                    state_q <= ST_FETCH_WAIT;
                                    perf.branchCnt <= perf.branchCnt + 64'd1;
                                    perf.condBranchCnt <= perf.condBranchCnt + 64'd1;
                                    if (branch_taken) begin
                                        perf.branchMissCnt <= perf.branchMissCnt + 64'd1;
                                        perf.condBranchMissCnt <= perf.condBranchMissCnt + 64'd1;
                                    end
                                end else begin
                                    take_trap(32'd2, inst_q);
                                end
                            end

                            OPC_LOAD: begin
                                if (funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101}) begin
                                    mem_addr_q <= rs1_val + imm_i;
                                    mem_funct3_q <= funct3;
                                    mem_rd_q <= rd;
                                    pc_q <= next_pc;
                                    state_q <= ST_MEM_REQ;
                                    perf.memIssueCount <= perf.memIssueCount + 64'd1;
                                end else begin
                                    take_trap(32'd2, inst_q);
                                end
                            end

                            OPC_STORE: begin
                                if (funct3 inside {3'b000, 3'b001, 3'b010}) begin
                                    mem_addr_q <= rs1_val + imm_s;
                                    mem_wdata_q <= store_data(rs2_val, funct3);
                                    mem_wmask_q <= store_mask(funct3);
                                    pc_q <= next_pc;
                                    state_q <= ST_STORE_COMMIT;
                                    perf.memIssueCount <= perf.memIssueCount + 64'd1;
                                end else begin
                                    take_trap(32'd2, inst_q);
                                end
                            end

                            OPC_OP_IMM: begin
                                unique case (funct3)
                                    3'b000: alu_result = rs1_val + imm_i;
                                    3'b010: alu_result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0;
                                    3'b011: alu_result = (rs1_val < imm_i) ? 32'd1 : 32'd0;
                                    3'b100: alu_result = rs1_val ^ imm_i;
                                    3'b110: alu_result = rs1_val | imm_i;
                                    3'b111: alu_result = rs1_val & imm_i;
                                    3'b001: alu_result = rs1_val << inst_q[24:20];
                                    3'b101: begin
                                        if (funct7 == 7'b0100000) begin
                                            alu_result = $signed(rs1_val) >>> inst_q[24:20];
                                        end else begin
                                            alu_result = rs1_val >> inst_q[24:20];
                                        end
                                    end
                                    default: alu_result = 32'b0;
                                endcase
                                if ((funct3 == 3'b001 && funct7 != 7'b0000000) ||
                                    (funct3 == 3'b101 && !(funct7 inside {7'b0000000, 7'b0100000}))) begin
                                    take_trap(32'd2, inst_q);
                                end else begin
                                    write_gpr(rd, alu_result);
                                    pc_q <= next_pc;
                                    state_q <= ST_FETCH_WAIT;
                                    perf.intIssueCount <= perf.intIssueCount + 64'd1;
                                end
                            end

                            OPC_OP: begin
                                if (funct7 == 7'b0000001) begin
                                    unique case (funct3)
                                        3'b000: begin
                                            mul_result = $signed(rs1_val) * $signed(rs2_val);
                                            write_gpr(rd, mul_result[31:0]);
                                            pc_q <= next_pc;
                                            state_q <= ST_FETCH_WAIT;
                                            perf.mulIssueCount <= perf.mulIssueCount + 64'd1;
                                        end
                                        3'b001: begin
                                            mul_result = $signed(rs1_val) * $signed(rs2_val);
                                            write_gpr(rd, mul_result[63:32]);
                                            pc_q <= next_pc;
                                            state_q <= ST_FETCH_WAIT;
                                            perf.mulIssueCount <= perf.mulIssueCount + 64'd1;
                                        end
                                        3'b010: begin
                                            mul_result = $signed({{32{rs1_val[31]}}, rs1_val}) *
                                                         $signed({32'b0, rs2_val});
                                            write_gpr(rd, mul_result[63:32]);
                                            pc_q <= next_pc;
                                            state_q <= ST_FETCH_WAIT;
                                            perf.mulIssueCount <= perf.mulIssueCount + 64'd1;
                                        end
                                        3'b011: begin
                                            mul_result = {32'b0, rs1_val} * {32'b0, rs2_val};
                                            write_gpr(rd, mul_result[63:32]);
                                            pc_q <= next_pc;
                                            state_q <= ST_FETCH_WAIT;
                                            perf.mulIssueCount <= perf.mulIssueCount + 64'd1;
                                        end
                                        3'b100, 3'b101, 3'b110, 3'b111: begin
                                            div_rd_q <= rd;
                                            div_funct3_q <= funct3;
                                            div_lhs_q <= rs1_val;
                                            div_rhs_q <= rs2_val;
                                            div_by_zero_q <= (rs2_val == 32'b0);
                                            div_overflow_q <= (funct3 inside {3'b100, 3'b110}) &&
                                                              (rs1_val == 32'h8000_0000) &&
                                                              (rs2_val == 32'hffff_ffff);
                                            div_neg_quot_q <= (funct3 == 3'b100) && (rs1_val[31] ^ rs2_val[31]);
                                            div_neg_rem_q <= (funct3 == 3'b110) && rs1_val[31];
                                            div_dividend_q <= (funct3 inside {3'b100, 3'b110}) ? abs32(rs1_val) : rs1_val;
                                            div_divisor_q <= (funct3 inside {3'b100, 3'b110}) ? abs32(rs2_val) : rs2_val;
                                            div_quotient_q <= 32'b0;
                                            div_remainder_q <= 33'b0;
                                            div_count_q <= 6'b0;
                                            pc_q <= next_pc;
                                            state_q <= ST_DIV;
                                            perf.mulIssueCount <= perf.mulIssueCount + 64'd1;
                                        end
                                        default: begin
                                            take_trap(32'd2, inst_q);
                                        end
                                    endcase
                                end else begin
                                    unique case ({funct7, funct3})
                                        {7'b0000000, 3'b000}: alu_result = rs1_val + rs2_val;
                                        {7'b0100000, 3'b000}: alu_result = rs1_val - rs2_val;
                                        {7'b0000000, 3'b001}: alu_result = rs1_val << rs2_val[4:0];
                                        {7'b0000000, 3'b010}: alu_result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                                        {7'b0000000, 3'b011}: alu_result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                                        {7'b0000000, 3'b100}: alu_result = rs1_val ^ rs2_val;
                                        {7'b0000000, 3'b101}: alu_result = rs1_val >> rs2_val[4:0];
                                        {7'b0100000, 3'b101}: alu_result = $signed(rs1_val) >>> rs2_val[4:0];
                                        {7'b0000000, 3'b110}: alu_result = rs1_val | rs2_val;
                                        {7'b0000000, 3'b111}: alu_result = rs1_val & rs2_val;
                                        default: alu_result = 32'b0;
                                    endcase
                                    if (!({funct7, funct3} inside {
                                        {7'b0000000, 3'b000}, {7'b0100000, 3'b000},
                                        {7'b0000000, 3'b001}, {7'b0000000, 3'b010},
                                        {7'b0000000, 3'b011}, {7'b0000000, 3'b100},
                                        {7'b0000000, 3'b101}, {7'b0100000, 3'b101},
                                        {7'b0000000, 3'b110}, {7'b0000000, 3'b111}})) begin
                                        take_trap(32'd2, inst_q);
                                    end else begin
                                        write_gpr(rd, alu_result);
                                        pc_q <= next_pc;
                                        state_q <= ST_FETCH_WAIT;
                                        perf.intIssueCount <= perf.intIssueCount + 64'd1;
                                    end
                                end
                            end

                            OPC_MISC: begin
                                pc_q <= next_pc;
                                state_q <= ST_FETCH_WAIT;
                                perf.intIssueCount <= perf.intIssueCount + 64'd1;
                            end

                            OPC_SYSTEM: begin
                                if (funct3 == 3'b000) begin
                                    unique case (inst_q[31:20])
                                        12'h000: begin
                                            take_trap((priv_mode_q == PRIV_M) ? 32'd11 : 32'd8, 32'b0);
                                        end
                                        12'h001: begin
                                            take_trap(32'd3, 32'b0);
                                        end
                                        12'h302: begin
                                            if (priv_mode_q != PRIV_M) begin
                                                take_trap(32'd2, inst_q);
                                            end else begin
                                                priv_mode_q <= mstatus_q[12:11];
                                                mstatus_q[12:11] <= PRIV_U;
                                                pc_q <= mepc_q;
                                                state_q <= ST_FETCH_REQ;
                                            end
                                        end
                                        default: begin
                                            take_trap(32'd2, inst_q);
                                        end
                                    endcase
                                end else begin
                                    csr_old = csr_read(inst_q[31:20]);
                                    csr_operand = (funct3[2]) ? {27'b0, rs1} : rs1_val;
                                    csr_do_write = (funct3 == 3'b001) || (funct3 == 3'b101) ||
                                                   ((funct3 inside {3'b010, 3'b011}) && (rs1 != 5'd0)) ||
                                                   ((funct3 inside {3'b110, 3'b111}) && (rs1 != 5'd0));
                                    unique case (funct3)
                                        3'b001, 3'b101: csr_new = csr_operand;
                                        3'b010, 3'b110: csr_new = csr_old | csr_operand;
                                        3'b011, 3'b111: csr_new = csr_old & ~csr_operand;
                                        default: csr_new = csr_old;
                                    endcase
                                    csr_illegal = csr_priv_fault(inst_q[31:20]) ||
                                                  (csr_do_write && csr_write_readonly(inst_q[31:20])) ||
                                                  !(funct3 inside {3'b001, 3'b010, 3'b011,
                                                                   3'b101, 3'b110, 3'b111});
                                    if (csr_illegal) begin
                                        take_trap(32'd2, inst_q);
                                    end else begin
                                        write_gpr(rd, csr_old);
                                        if (csr_do_write) begin
                                            write_csr(inst_q[31:20], csr_new);
                                        end
                                        pc_q <= next_pc;
                                        state_q <= ST_FETCH_REQ;
                                        perf.intIssueCount <= perf.intIssueCount + 64'd1;
                                    end
                                end
                            end

                            default: begin
                                take_trap(32'd2, inst_q);
                            end
                        endcase
                    end
                end

                ST_MEM_REQ: begin
                    state_q <= ST_MEM_WAIT;
                end

                ST_MEM_WAIT: begin
                    state_q <= ST_MEM_RESP;
                end

                ST_MEM_RESP: begin
                    write_gpr(mem_rd_q, load_extend(dromAccess.exReadData, mem_funct3_q));
                    state_q <= ST_FETCH_WAIT;
                end

                ST_STORE_COMMIT: begin
                    state_q <= ST_FETCH_WAIT;
                end

                ST_DIV: begin
                    if (div_by_zero_q) begin
                        div_result = (div_funct3_q inside {3'b100, 3'b101}) ? 32'hffff_ffff : div_lhs_q;
                        write_gpr(div_rd_q, div_result);
                        state_q <= ST_FETCH_WAIT;
                    end else if (div_overflow_q) begin
                        div_result = (div_funct3_q == 3'b100) ? div_lhs_q : 32'b0;
                        write_gpr(div_rd_q, div_result);
                        state_q <= ST_FETCH_WAIT;
                    end else begin
                        div_rem_shift = {div_remainder_q[31:0], div_dividend_q[31]};
                        if (div_rem_shift >= {1'b0, div_divisor_q}) begin
                            div_rem_next = div_rem_shift - {1'b0, div_divisor_q};
                            div_quot_next = {div_quotient_q[30:0], 1'b1};
                        end else begin
                            div_rem_next = div_rem_shift;
                            div_quot_next = {div_quotient_q[30:0], 1'b0};
                        end
                        div_dividend_q <= {div_dividend_q[30:0], 1'b0};
                        div_remainder_q <= div_rem_next;
                        div_quotient_q <= div_quot_next;
                        div_count_q <= div_count_q + 6'd1;
                        if (div_count_q == 6'd31) begin
                            unique case (div_funct3_q)
                                3'b100, 3'b101: begin
                                    div_result = div_neg_quot_q ? (~div_quot_next + 32'd1) : div_quot_next;
                                end
                                default: begin
                                    div_result = div_neg_rem_q ? (~div_rem_next[31:0] + 32'd1) :
                                                                 div_rem_next[31:0];
                                end
                            endcase
                            write_gpr(div_rd_q, div_result);
                            state_q <= ST_FETCH_WAIT;
                        end
                    end
                end

                default: begin
                    state_q <= ST_FETCH_REQ;
                end
            endcase
        end
    end
endmodule
