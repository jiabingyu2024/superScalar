`timescale 1ns / 1ps

import CoreTypes::*;

module riscv_cpu (
    input  logic        clk,
    input  logic        rst,

    output logic [31:0] irom_addr,
    input  logic [31:0] irom_data,
    output logic        irom_ena,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    output logic        dmem_req_uncached,
    input  logic        dmem_resp_valid,
    input  logic [31:0] dmem_resp_rdata,

    output logic [63:0] perf_cycle,
    output logic [63:0] perf_commit,
    output logic [63:0] perf_branch,
    output logic [63:0] perf_branch_miss,
    output logic [63:0] perf_load,
    output logic [63:0] perf_store,
    output logic [63:0] perf_dcache_access,
    output logic [63:0] perf_dcache_miss,
    output logic [63:0] perf_stall_front,
    output logic [63:0] perf_stall_mem,
    output logic [63:0] perf_stall_muldiv,
    output logic [63:0] perf_stall_load_use
);
    typedef enum logic [2:0] {
        ST_FETCH,
        ST_DECODE,
        ST_EXEC,
        ST_WAIT_MEM,
        ST_WAIT_MULDIV
    } state_e;

    state_e state_q;
    logic [31:0] pc_q;
    logic [31:0] inst_q;
    logic [31:0] inst_pc_q;
    logic [31:0] regs_q [0:31];

    logic [4:0]  load_rd_q;
    logic [2:0]  load_funct3_q;
    logic [31:0] load_addr_q;
    logic [4:0]  muldiv_rd_q;

    logic [31:0] csr_mstatus_q;
    logic [31:0] csr_mtvec_q;
    logic [31:0] csr_mscratch_q;
    logic [31:0] csr_mepc_q;
    logic [31:0] csr_mcause_q;
    logic        btb_valid_q [0:63];
    logic [23:0] btb_tag_q [0:63];
    logic [31:0] btb_target_q [0:63];

    logic        mem_req_valid_c;
    logic        mem_req_write_c;
    logic [31:0] mem_req_addr_c;
    logic [31:0] mem_req_wdata_c;
    logic [3:0]  mem_req_wstrb_c;
    logic        mem_req_uncached_c;
    logic        cache_req_ready;
    logic        cache_resp_valid;
    logic [31:0] cache_resp_rdata;
    logic [31:0] exec_inst_c;
    logic [5:0]  btb_index_c;
    logic [23:0] btb_tag_c;
    logic        btb_hit_c;
    logic [31:0] pred_next_pc_c;
    logic        muldiv_start_c;
    logic [2:0]  muldiv_funct3_c;
    logic [31:0] muldiv_lhs_c;
    logic [31:0] muldiv_rhs_c;
    logic        muldiv_busy;
    logic        muldiv_done;
    logic [31:0] muldiv_result;

    assign exec_inst_c = (state_q == ST_EXEC) ? irom_data : inst_q;
    assign btb_index_c = pc_q[7:2];
    assign btb_tag_c = pc_q[31:8];
    assign btb_hit_c = btb_valid_q[btb_index_c] && (btb_tag_q[btb_index_c] == btb_tag_c);
    assign pred_next_pc_c = btb_hit_c ? btb_target_q[btb_index_c] : (pc_q + 32'd4);

    assign irom_addr = ((state_q == ST_EXEC) || (state_q == ST_WAIT_MEM) ||
                        (state_q == ST_WAIT_MULDIV)) ? pred_next_pc_c : pc_q;
    assign irom_ena  = (state_q == ST_FETCH) || (state_q == ST_EXEC) ||
                       (state_q == ST_WAIT_MEM) || (state_q == ST_WAIT_MULDIV);

    DCache dcache (
        .clk               (clk),
        .rst               (rst),
        .cpu_req_valid     (mem_req_valid_c),
        .cpu_req_ready     (cache_req_ready),
        .cpu_req_write     (mem_req_write_c),
        .cpu_req_addr      (mem_req_addr_c),
        .cpu_req_wdata     (mem_req_wdata_c),
        .cpu_req_wstrb     (mem_req_wstrb_c),
        .cpu_req_uncached  (mem_req_uncached_c),
        .cpu_resp_valid    (cache_resp_valid),
        .cpu_resp_rdata    (cache_resp_rdata),
        .mem_req_valid     (dmem_req_valid),
        .mem_req_ready     (dmem_req_ready),
        .mem_req_write     (dmem_req_write),
        .mem_req_addr      (dmem_req_addr),
        .mem_req_wdata     (dmem_req_wdata),
        .mem_req_wstrb     (dmem_req_wstrb),
        .mem_req_uncached  (dmem_req_uncached),
        .mem_resp_valid    (dmem_resp_valid),
        .mem_resp_rdata    (dmem_resp_rdata),
        .perf_dcache_access(perf_dcache_access),
        .perf_dcache_miss  (perf_dcache_miss),
        .perf_stall_mem    (perf_stall_mem)
    );

    MulDivUnit muldiv (
        .clk   (clk),
        .rst   (rst),
        .start (muldiv_start_c),
        .funct3(muldiv_funct3_c),
        .lhs   (muldiv_lhs_c),
        .rhs   (muldiv_rhs_c),
        .busy  (muldiv_busy),
        .done  (muldiv_done),
        .result(muldiv_result)
    );

    function automatic logic [31:0] sext(input logic [31:0] value, input int unsigned bits);
        logic [31:0] mask;
        begin
            mask = 32'hffff_ffff << bits;
            sext = value[bits-1] ? (value | mask) : (value & ~mask);
        end
    endfunction

    function automatic logic [31:0] imm_i(input logic [31:0] inst);
        imm_i = {{20{inst[31]}}, inst[31:20]};
    endfunction

    function automatic logic [31:0] imm_s(input logic [31:0] inst);
        imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    endfunction

    function automatic logic [31:0] imm_b(input logic [31:0] inst);
        imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    endfunction

    function automatic logic [31:0] imm_u(input logic [31:0] inst);
        imm_u = {inst[31:12], 12'd0};
    endfunction

    function automatic logic [31:0] imm_j(input logic [31:0] inst);
        imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
    endfunction

    function automatic logic [31:0] load_extend(
        input logic [31:0] rdata,
        input logic [2:0]  funct3
    );
        begin
            unique case (funct3)
                3'b000: load_extend = {{24{rdata[7]}}, rdata[7:0]};
                3'b001: load_extend = {{16{rdata[15]}}, rdata[15:0]};
                3'b010: load_extend = rdata;
                3'b100: load_extend = {24'd0, rdata[7:0]};
                3'b101: load_extend = {16'd0, rdata[15:0]};
                default: load_extend = rdata;
            endcase
        end
    endfunction

    function automatic logic [31:0] csr_read(input logic [11:0] csr);
        begin
            unique case (csr)
                12'h300: csr_read = csr_mstatus_q;
                12'h305: csr_read = csr_mtvec_q;
                12'h340: csr_read = csr_mscratch_q;
                12'h341: csr_read = csr_mepc_q;
                12'h342: csr_read = csr_mcause_q;
                12'h301: csr_read = 32'd0;
                default: csr_read = 32'd0;
            endcase
        end
    endfunction

    task automatic csr_write(input logic [11:0] csr, input logic [31:0] value);
        begin
            unique case (csr)
                12'h300: csr_mstatus_q  <= value;
                12'h305: csr_mtvec_q    <= {value[31:2], 2'b00};
                12'h340: csr_mscratch_q <= value;
                12'h341: csr_mepc_q     <= value;
                12'h342: csr_mcause_q   <= value;
                default: begin
                end
            endcase
        end
    endtask

    task automatic write_gpr(input logic [4:0] rd, input logic [31:0] value);
        begin
            if (rd != 5'd0) begin
                regs_q[rd] <= value;
            end
        end
    endtask

    function automatic logic [31:0] div_result(
        input logic [31:0] lhs,
        input logic [31:0] rhs,
        input logic [2:0]  funct3
    );
        logic signed [31:0] slhs;
        logic signed [31:0] srhs;
        begin
            slhs = lhs;
            srhs = rhs;
            unique case (funct3)
                3'b100: begin
                    if (rhs == 32'd0) div_result = 32'hffff_ffff;
                    else if (lhs == 32'h8000_0000 && rhs == 32'hffff_ffff) div_result = 32'h8000_0000;
                    else div_result = slhs / srhs;
                end
                3'b101: div_result = (rhs == 32'd0) ? 32'hffff_ffff : (lhs / rhs);
                3'b110: begin
                    if (rhs == 32'd0) div_result = lhs;
                    else if (lhs == 32'h8000_0000 && rhs == 32'hffff_ffff) div_result = 32'd0;
                    else div_result = slhs % srhs;
                end
                3'b111: div_result = (rhs == 32'd0) ? lhs : (lhs % rhs);
                default: div_result = 32'd0;
            endcase
        end
    endfunction

    always_comb begin
        mem_req_valid_c = 1'b0;
        mem_req_write_c = 1'b0;
        mem_req_addr_c  = 32'd0;
        mem_req_wdata_c = 32'd0;
        mem_req_wstrb_c = 4'b0000;
        mem_req_uncached_c = 1'b0;
        muldiv_start_c = 1'b0;
        muldiv_funct3_c = 3'd0;
        muldiv_lhs_c = 32'd0;
        muldiv_rhs_c = 32'd0;

        if (state_q == ST_EXEC && exec_inst_c[6:0] == 7'b0000011) begin
            mem_req_valid_c = 1'b1;
            mem_req_write_c = 1'b0;
            mem_req_addr_c  = regs_q[exec_inst_c[19:15]] + imm_i(exec_inst_c);
            mem_req_uncached_c = 1'b0;
        end else if (state_q == ST_EXEC && exec_inst_c[6:0] == 7'b0100011) begin
            mem_req_valid_c = 1'b1;
            mem_req_write_c = 1'b1;
            mem_req_addr_c  = regs_q[exec_inst_c[19:15]] + imm_s(exec_inst_c);
            mem_req_uncached_c = 1'b0;
            unique case (exec_inst_c[14:12])
                3'b000: begin
                    mem_req_wdata_c = {24'd0, regs_q[exec_inst_c[24:20]][7:0]};
                    mem_req_wstrb_c = 4'b0001;
                end
                3'b001: begin
                    mem_req_wdata_c = {16'd0, regs_q[exec_inst_c[24:20]][15:0]};
                    mem_req_wstrb_c = 4'b0011;
                end
                3'b010: begin
                    mem_req_wdata_c = regs_q[exec_inst_c[24:20]];
                    mem_req_wstrb_c = 4'b1111;
                end
                default: begin
                    mem_req_wdata_c = regs_q[exec_inst_c[24:20]];
                    mem_req_wstrb_c = 4'b0000;
                end
            endcase
        end

        if (state_q == ST_EXEC &&
            exec_inst_c[6:0] == 7'b0110011 &&
            exec_inst_c[31:25] == 7'b0000001 &&
            !muldiv_busy) begin
            muldiv_start_c = 1'b1;
            muldiv_funct3_c = exec_inst_c[14:12];
            muldiv_lhs_c = regs_q[exec_inst_c[19:15]];
            muldiv_rhs_c = regs_q[exec_inst_c[24:20]];
        end
    end

    integer idx;
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= ST_FETCH;
            pc_q <= RESET_PC;
            inst_q <= 32'd0;
            inst_pc_q <= 32'd0;
            load_rd_q <= 5'd0;
            load_funct3_q <= 3'd0;
            load_addr_q <= 32'd0;
            muldiv_rd_q <= 5'd0;
            csr_mstatus_q <= 32'd0;
            csr_mtvec_q <= 32'd0;
            csr_mscratch_q <= 32'd0;
            csr_mepc_q <= 32'd0;
            csr_mcause_q <= 32'd0;
            perf_cycle <= 64'd0;
            perf_commit <= 64'd0;
            perf_branch <= 64'd0;
            perf_branch_miss <= 64'd0;
            perf_load <= 64'd0;
            perf_store <= 64'd0;
            perf_stall_front <= 64'd0;
            perf_stall_muldiv <= 64'd0;
            perf_stall_load_use <= 64'd0;
            for (idx = 0; idx < 32; idx++) begin
                regs_q[idx] <= 32'd0;
            end
            for (idx = 0; idx < 64; idx++) begin
                btb_valid_q[idx] <= 1'b0;
                btb_tag_q[idx] <= 24'd0;
                btb_target_q[idx] <= 32'd0;
            end
        end else begin
            perf_cycle <= perf_cycle + 64'd1;
            regs_q[0] <= 32'd0;
            if (state_q == ST_FETCH) begin
                perf_stall_front <= perf_stall_front + 64'd1;
            end
            if (state_q == ST_WAIT_MULDIV) begin
                perf_stall_muldiv <= perf_stall_muldiv + 64'd1;
            end

            unique case (state_q)
                ST_FETCH: begin
                    state_q <= ST_EXEC;
                end

                ST_DECODE: begin
                    state_q <= ST_EXEC;
                end

                ST_EXEC: begin
                    logic [6:0] opcode;
                    logic [2:0] funct3;
                    logic [6:0] funct7;
                    logic [4:0] rd;
                    logic [4:0] rs1;
                    logic [4:0] rs2;
                    logic [31:0] lhs;
                    logic [31:0] rhs;
                    logic [31:0] next_pc;
                    logic        commit;
                    logic        redirect;
                    logic        is_ctrl;
                    logic        btb_update_valid;
                    logic        btb_update_taken;

                    opcode = exec_inst_c[6:0];
                    funct3 = exec_inst_c[14:12];
                    funct7 = exec_inst_c[31:25];
                    rd = exec_inst_c[11:7];
                    rs1 = exec_inst_c[19:15];
                    rs2 = exec_inst_c[24:20];
                    lhs = regs_q[rs1];
                    rhs = regs_q[rs2];
                    next_pc = pc_q + 32'd4;
                    commit = 1'b1;
                    redirect = 1'b0;
                    is_ctrl = 1'b0;
                    btb_update_valid = 1'b0;
                    btb_update_taken = 1'b0;

                    unique case (opcode)
                        7'b0110111: write_gpr(rd, imm_u(exec_inst_c)); // LUI
                        7'b0010111: write_gpr(rd, pc_q + imm_u(exec_inst_c)); // AUIPC
                        7'b1101111: begin // JAL
                            write_gpr(rd, pc_q + 32'd4);
                            next_pc = pc_q + imm_j(exec_inst_c);
                            is_ctrl = 1'b1;
                            btb_update_valid = 1'b1;
                            btb_update_taken = 1'b1;
                            perf_branch <= perf_branch + 64'd1;
                        end
                        7'b1100111: begin // JALR
                            write_gpr(rd, pc_q + 32'd4);
                            next_pc = (lhs + imm_i(exec_inst_c)) & ~32'd1;
                            is_ctrl = 1'b1;
                            btb_update_valid = 1'b1;
                            btb_update_taken = 1'b1;
                            perf_branch <= perf_branch + 64'd1;
                        end
                        7'b1100011: begin // BRANCH
                            logic taken;
                            unique case (funct3)
                                3'b000: taken = (lhs == rhs);
                                3'b001: taken = (lhs != rhs);
                                3'b100: taken = ($signed(lhs) < $signed(rhs));
                                3'b101: taken = ($signed(lhs) >= $signed(rhs));
                                3'b110: taken = (lhs < rhs);
                                3'b111: taken = (lhs >= rhs);
                                default: taken = 1'b0;
                            endcase
                            if (taken) begin
                                next_pc = pc_q + imm_b(exec_inst_c);
                                btb_update_taken = 1'b1;
                            end
                            is_ctrl = 1'b1;
                            btb_update_valid = 1'b1;
                            perf_branch <= perf_branch + 64'd1;
                        end
                        7'b0000011: begin // LOAD
                            if (cache_req_ready) begin
                                load_rd_q <= rd;
                                load_funct3_q <= funct3;
                                load_addr_q <= mem_req_addr_c;
                                state_q <= ST_WAIT_MEM;
                                commit = 1'b0;
                            end else begin
                                commit = 1'b0;
                            end
                        end
                        7'b0100011: begin // STORE
                            if (cache_req_ready) begin
                                perf_store <= perf_store + 64'd1;
                            end else begin
                                commit = 1'b0;
                            end
                        end
                        7'b0010011: begin // OP-IMM
                            unique case (funct3)
                                3'b000: write_gpr(rd, lhs + imm_i(exec_inst_c));
                                3'b010: write_gpr(rd, ($signed(lhs) < $signed(imm_i(exec_inst_c))) ? 32'd1 : 32'd0);
                                3'b011: write_gpr(rd, (lhs < imm_i(exec_inst_c)) ? 32'd1 : 32'd0);
                                3'b100: write_gpr(rd, lhs ^ imm_i(exec_inst_c));
                                3'b110: write_gpr(rd, lhs | imm_i(exec_inst_c));
                                3'b111: write_gpr(rd, lhs & imm_i(exec_inst_c));
                                3'b001: write_gpr(rd, lhs << exec_inst_c[24:20]);
                                3'b101: begin
                                    if (exec_inst_c[30]) write_gpr(rd, $signed(lhs) >>> exec_inst_c[24:20]);
                                    else write_gpr(rd, lhs >> exec_inst_c[24:20]);
                                end
                                default: begin
                                end
                            endcase
                        end
                        7'b0110011: begin // OP / M
                            if (funct7 == 7'b0000001) begin
                                if (!muldiv_busy) begin
                                    muldiv_rd_q <= rd;
                                    state_q <= ST_WAIT_MULDIV;
                                end
                                commit = 1'b0;
                            end else begin
                                unique case ({funct7[5], funct3})
                                    4'b0000: write_gpr(rd, lhs + rhs);
                                    4'b1000: write_gpr(rd, lhs - rhs);
                                    4'b0001: write_gpr(rd, lhs << rhs[4:0]);
                                    4'b0010: write_gpr(rd, ($signed(lhs) < $signed(rhs)) ? 32'd1 : 32'd0);
                                    4'b0011: write_gpr(rd, (lhs < rhs) ? 32'd1 : 32'd0);
                                    4'b0100: write_gpr(rd, lhs ^ rhs);
                                    4'b0101: write_gpr(rd, lhs >> rhs[4:0]);
                                    4'b1101: write_gpr(rd, $signed(lhs) >>> rhs[4:0]);
                                    4'b0110: write_gpr(rd, lhs | rhs);
                                    4'b0111: write_gpr(rd, lhs & rhs);
                                    default: begin
                                    end
                                endcase
                            end
                        end
                        7'b0001111: begin // FENCE/FENCE.I as serial NOP
                        end
                        7'b1110011: begin // SYSTEM/CSR
                            if (exec_inst_c == 32'h0000_0073) begin // ECALL
                                csr_mepc_q <= pc_q;
                                csr_mcause_q <= 32'd11;
                                next_pc = csr_mtvec_q;
                                is_ctrl = 1'b1;
                            end else if (exec_inst_c == 32'h0010_0073) begin // EBREAK
                                csr_mepc_q <= pc_q;
                                csr_mcause_q <= 32'd3;
                                next_pc = csr_mtvec_q;
                                is_ctrl = 1'b1;
                            end else if (exec_inst_c == 32'h3020_0073) begin // MRET
                                next_pc = csr_mepc_q;
                                is_ctrl = 1'b1;
                            end else begin
                                logic [11:0] csr;
                                logic [31:0] old_csr;
                                logic [31:0] csr_operand;
                                logic [31:0] new_csr;
                                csr = exec_inst_c[31:20];
                                old_csr = csr_read(csr);
                                csr_operand = funct3[2] ? {27'd0, rs1} : lhs;
                                new_csr = old_csr;
                                unique case (funct3)
                                    3'b001, 3'b101: new_csr = csr_operand;
                                    3'b010, 3'b110: new_csr = old_csr | csr_operand;
                                    3'b011, 3'b111: new_csr = old_csr & ~csr_operand;
                                    default: begin
                                    end
                                endcase
                                if (funct3 != 3'b000) begin
                                    write_gpr(rd, old_csr);
                                    if (!(funct3[1] && csr_operand == 32'd0)) begin
                                        csr_write(csr, new_csr);
                                    end
                                end
                            end
                        end
                        default: begin
                        end
                    endcase

                    if (commit) begin
                        redirect = (next_pc != pred_next_pc_c);
                        if (is_ctrl && redirect) begin
                            perf_branch_miss <= perf_branch_miss + 64'd1;
                        end
                        if (btb_update_valid) begin
                            if (btb_update_taken) begin
                                btb_valid_q[btb_index_c] <= 1'b1;
                                btb_tag_q[btb_index_c] <= btb_tag_c;
                                btb_target_q[btb_index_c] <= next_pc;
                            end else if (btb_hit_c) begin
                                btb_valid_q[btb_index_c] <= 1'b0;
                            end
                        end
                        pc_q <= next_pc;
                        perf_commit <= perf_commit + 64'd1;
                        state_q <= redirect ? ST_FETCH : ST_EXEC;
                    end
                end

                ST_WAIT_MEM: begin
                    if (cache_resp_valid) begin
                        write_gpr(load_rd_q, load_extend(cache_resp_rdata, load_funct3_q));
                        pc_q <= pc_q + 32'd4;
                        perf_commit <= perf_commit + 64'd1;
                        perf_load <= perf_load + 64'd1;
                        state_q <= ST_EXEC;
                    end
                end

                ST_WAIT_MULDIV: begin
                    if (muldiv_done) begin
                        write_gpr(muldiv_rd_q, muldiv_result);
                        pc_q <= pc_q + 32'd4;
                        perf_commit <= perf_commit + 64'd1;
                        state_q <= ST_EXEC;
                    end
                end

                default: state_q <= ST_FETCH;
            endcase
        end
    end

    logic unused_load_addr;
    always_comb begin
        unused_load_addr = ^load_addr_q;
    end
endmodule
