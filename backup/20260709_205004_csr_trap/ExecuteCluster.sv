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

    output logic store_push_valid_o,
    output RobIndexPath store_push_rob_idx_o,
    output AddrPath store_push_addr_o,
    output DataPath store_push_data_o,
    output logic [3:0] store_push_mask_o,
    input  logic store_push_ready_i,
    input  logic store_buffer_empty_i,

    DramAccessIF.ExecuteMemStage dmem
);
    localparam int READ_PORTS = ISSUE_WIDTH * 2;

    CoreRenamedUop issue_uop [ISSUE_WIDTH-1:0];
    logic [ISSUE_WIDTH-1:0] issue_valid;
    DataPath src0 [ISSUE_WIDTH-1:0];
    DataPath src1 [ISSUE_WIDTH-1:0];
    DataPath result [ISSUE_WIDTH-1:0];
    logic branch_taken [ISSUE_WIDTH-1:0];
    PcPath branch_target [ISSUE_WIDTH-1:0];
    logic [ISSUE_WIDTH-1:0] prf_we;
    PhyRegNumPath [ISSUE_WIDTH-1:0] prf_waddr;
    DataPath [ISSUE_WIDTH-1:0] prf_wdata;
    PhyRegNumPath [READ_PORTS-1:0] prf_raddr;
    DataPath [READ_PORTS-1:0] prf_rdata;
    logic mem_load_pending_q;
    CoreRenamedUop mem_load_uop_q;
    AddrPath mem_load_addr_q;

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

    function automatic DataPath mul_result(
        input CoreDecodeUop uop,
        input DataPath a,
        input DataPath b
    );
        logic [63:0] mul_u;
        logic signed [63:0] mul_s;
        logic signed [63:0] mul_hsu;
        logic signed [31:0] a_s;
        logic signed [31:0] b_s;
        begin
            mul_u = {32'b0, a} * {32'b0, b};
            mul_s = $signed(a) * $signed(b);
            mul_hsu = $signed({{32{a[31]}}, a}) * $signed({32'b0, b});
            a_s = a;
            b_s = b;
            unique case (uop.muldiv_op)
                MULDIV_OP_MUL:    mul_result = mul_u[31:0];
                MULDIV_OP_MULH:   mul_result = mul_s[63:32];
                MULDIV_OP_MULHSU: mul_result = mul_hsu[63:32];
                MULDIV_OP_MULHU:  mul_result = mul_u[63:32];
                MULDIV_OP_DIV: begin
                    if (b == 32'b0) begin
                        mul_result = 32'hffff_ffff;
                    end else if (a == 32'h8000_0000 && b == 32'hffff_ffff) begin
                        mul_result = 32'h8000_0000;
                    end else begin
                        mul_result = DataPath'(a_s / b_s);
                    end
                end
                MULDIV_OP_DIVU: begin
                    mul_result = (b == 32'b0) ? 32'hffff_ffff : (a / b);
                end
                MULDIV_OP_REM: begin
                    if (b == 32'b0) begin
                        mul_result = a;
                    end else if (a == 32'h8000_0000 && b == 32'hffff_ffff) begin
                        mul_result = 32'b0;
                    end else begin
                        mul_result = DataPath'(a_s % b_s);
                    end
                end
                MULDIV_OP_REMU: begin
                    mul_result = (b == 32'b0) ? a : (a % b);
                end
                default: mul_result = 32'b0;
            endcase
        end
    endfunction

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            issue_valid[i] = 1'b0;
            issue_uop[i] = '0;
        end
        dmem.exReadEn = 1'b0;
        dmem.exReadAddr = mem_load_addr_q;
        store_push_valid_o = 1'b0;
        store_push_rob_idx_o = '0;
        store_push_addr_o = '0;
        store_push_data_o = '0;
        store_push_mask_o = '0;

        for (int i = 0; i < INT_ISSUE_WIDTH; i = i + 1) begin
            int_issue_ready_o[i] = !clear_i;
            issue_valid[i] = int_issue_valid_i[i] && int_issue_ready_o[i];
            issue_uop[i] = int_issue_uop_i[i];
        end
        for (int m = 0; m < MEM_ISSUE_WIDTH; m = m + 1) begin
            mem_issue_ready_o[m] = !clear_i && !mem_load_pending_q &&
                                   (!mem_issue_valid_i[m] ||
                                    (mem_issue_uop_i[m].uop.is_store && store_push_ready_i) ||
                                    (mem_issue_uop_i[m].uop.is_load && store_buffer_empty_i));
            issue_valid[INT_ISSUE_WIDTH + m] = mem_issue_valid_i[m] && mem_issue_ready_o[m];
            issue_uop[INT_ISSUE_WIDTH + m] = mem_issue_uop_i[m];
        end
        for (int u = 0; u < MULDIV_ISSUE_WIDTH; u = u + 1) begin
            mul_issue_ready_o[u] = !clear_i;
            issue_valid[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_valid_i[u] && mul_issue_ready_o[u];
            issue_uop[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + u] = mul_issue_uop_i[u];
        end

        for (int i = 0; i < ISSUE_WIDTH; i = i + 1) begin
            prf_raddr[2*i] = issue_uop[i].prs1;
            prf_raddr[2*i + 1] = issue_uop[i].prs2;
            src0[i] = prf_rdata[2*i];
            src1[i] = prf_rdata[2*i + 1];

            branch_taken[i] = 1'b0;
            branch_target[i] = issue_uop[i].uop.pc + 32'd4;
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
                    result[i] = mul_result(issue_uop[i].uop, src0[i], src1[i]);
                end
                TUBE_TYPE_MEM: begin
                    result[i] = src0[i] + (issue_uop[i].uop.is_store ? issue_uop[i].uop.imm_s : issue_uop[i].uop.imm_i);
                end
                default: begin
                    result[i] = alu_result(issue_uop[i].uop, src0[i], src1[i]);
                end
            endcase

            complete_valid_o[i] = issue_valid[i];
            complete_rob_idx_o[i] = issue_uop[i].rob_idx;
            complete_prd_o[i] = issue_uop[i].prd;
            complete_result_o[i] = result[i];
            complete_exception_o[i] = issue_uop[i].uop.exception;
            complete_exception_cause_o[i] = issue_uop[i].uop.exception_cause;
            complete_branch_miss_o[i] = issue_valid[i] &&
                                        (issue_uop[i].uop.is_branch ||
                                         issue_uop[i].uop.is_jal ||
                                         issue_uop[i].uop.is_jalr) &&
                                        ((branch_taken[i] != issue_uop[i].uop.pred_taken) ||
                                         (branch_taken[i] && (branch_target[i] != issue_uop[i].uop.pred_target)));
            complete_redirect_pc_o[i] = branch_target[i];

            prf_we[i] = issue_valid[i] && issue_uop[i].alloc_prd && !issue_uop[i].uop.is_store;
            prf_waddr[i] = issue_uop[i].prd;
            prf_wdata[i] = result[i];
        end

        if (issue_valid[INT_ISSUE_WIDTH] && issue_uop[INT_ISSUE_WIDTH].uop.is_store) begin
            store_push_valid_o = 1'b1;
            store_push_rob_idx_o = issue_uop[INT_ISSUE_WIDTH].rob_idx;
            store_push_addr_o = result[INT_ISSUE_WIDTH];
            store_push_data_o = src1[INT_ISSUE_WIDTH];
            store_push_mask_o = store_mask(issue_uop[INT_ISSUE_WIDTH].uop);
        end

        if (issue_valid[INT_ISSUE_WIDTH] && issue_uop[INT_ISSUE_WIDTH].uop.is_load) begin
            dmem.exReadEn = 1'b1;
            dmem.exReadAddr = result[INT_ISSUE_WIDTH];
            complete_valid_o[INT_ISSUE_WIDTH] = 1'b0;
            prf_we[INT_ISSUE_WIDTH] = 1'b0;
        end

        if (mem_load_pending_q && dmem.exReadReady) begin
            complete_valid_o[INT_ISSUE_WIDTH] = 1'b1;
            complete_rob_idx_o[INT_ISSUE_WIDTH] = mem_load_uop_q.rob_idx;
            complete_prd_o[INT_ISSUE_WIDTH] = mem_load_uop_q.prd;
            complete_result_o[INT_ISSUE_WIDTH] = load_extend(mem_load_uop_q.uop, dmem.exReadData);
            complete_exception_o[INT_ISSUE_WIDTH] = mem_load_uop_q.uop.exception;
            complete_exception_cause_o[INT_ISSUE_WIDTH] = mem_load_uop_q.uop.exception_cause;
            complete_branch_miss_o[INT_ISSUE_WIDTH] = 1'b0;
            complete_redirect_pc_o[INT_ISSUE_WIDTH] = '0;
            prf_we[INT_ISSUE_WIDTH] = mem_load_uop_q.alloc_prd;
            prf_waddr[INT_ISSUE_WIDTH] = mem_load_uop_q.prd;
            prf_wdata[INT_ISSUE_WIDTH] = load_extend(mem_load_uop_q.uop, dmem.exReadData);
        end
    end

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
        end else begin
            unused_seq <= clear_i;
            if (clear_i) begin
                mem_load_pending_q <= 1'b0;
                mem_load_uop_q <= '0;
                mem_load_addr_q <= '0;
            end else if (mem_load_pending_q && dmem.exReadReady) begin
                mem_load_pending_q <= 1'b0;
            end else if (issue_valid[INT_ISSUE_WIDTH] && issue_uop[INT_ISSUE_WIDTH].uop.is_load) begin
                mem_load_pending_q <= 1'b1;
                mem_load_uop_q <= issue_uop[INT_ISSUE_WIDTH];
                mem_load_addr_q <= result[INT_ISSUE_WIDTH];
            end
        end
    end
endmodule : CoreExecuteCluster
