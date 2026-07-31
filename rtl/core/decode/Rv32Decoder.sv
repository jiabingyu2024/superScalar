import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreRv32Decoder (
    input  CoreFetchPacket fetch_i,
    output CoreDecodeUop   uop_o
);
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

    logic [31:0] inst;
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    task automatic mark_illegal;
        begin
            uop_o.illegal = 1'b1;
            uop_o.exception = 1'b1;
            uop_o.exception_cause = EXC_CAUSE_ILLEGAL_INST;
        end
    endtask

    // The existing MULDIV queue is the core's back-pressured complex-integer
    // execution path.  Routing Zb operations through it keeps their extra
    // logic out of both ordinary INT-ALU issue lanes.
    task automatic mark_complex_int(input CoreMulDivOp op);
        begin
            uop_o.tube = TUBE_TYPE_MUL;
            uop_o.fu_type = FU_TYPE_MULDIV;
            uop_o.is_muldiv = 1'b1;
            uop_o.muldiv_op = op;
        end
    endtask

    always_comb begin
        inst = fetch_i.inst;
        opcode = inst[6:0];
        funct3 = inst[14:12];
        funct7 = inst[31:25];

        uop_o = '0;
        uop_o.valid = fetch_i.valid;
        uop_o.pc = fetch_i.pc;
        uop_o.inst = inst;
        uop_o.pred_taken = fetch_i.pred_taken;
        uop_o.pred_target = fetch_i.pred_target;
        uop_o.opcode = opcode;
        uop_o.rd = inst[11:7];
        uop_o.funct3 = funct3;
        uop_o.rs1 = inst[19:15];
        uop_o.rs2 = inst[24:20];
        uop_o.funct7 = funct7;
        uop_o.imm_i = {{20{inst[31]}}, inst[31:20]};
        uop_o.imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        uop_o.imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        uop_o.imm_u = {inst[31:12], 12'b0};
        uop_o.imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        uop_o.tube = TUBE_TYPE_ALU;
        uop_o.fu_type = FU_TYPE_INT;
        uop_o.alu_op = ALU_OP_ADD;
        uop_o.branch_op = BR_OP_NONE;
        uop_o.lsu_op = LSU_OP_NONE;
        uop_o.muldiv_op = MULDIV_OP_NONE;
        uop_o.csr_op = CSR_OP_NONE;
        uop_o.system_op = SYS_OP_NONE;
        uop_o.csr_addr = inst[31:20];
        uop_o.csr_zimm = inst[19:15];
        uop_o.mem_size = 2'd2;
        uop_o.mem_signed = 1'b0;

        if (inst[1:0] != 2'b11) begin
            mark_illegal();
        end else begin
            unique case (opcode)
                OPC_LUI: begin
                    uop_o.alu_op = ALU_OP_COPY_B;
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                end
                OPC_AUIPC: begin
                    uop_o.alu_op = ALU_OP_ADD;
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                end
                OPC_JAL: begin
                    uop_o.tube = TUBE_TYPE_BRC;
                    uop_o.fu_type = FU_TYPE_BRU;
                    uop_o.branch_op = BR_OP_JAL;
                    uop_o.is_jump = 1'b1;
                    uop_o.is_jal = 1'b1;
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                end
                OPC_JALR: begin
                    if (funct3 == 3'b000) begin
                        uop_o.tube = TUBE_TYPE_BRC;
                        uop_o.fu_type = FU_TYPE_BRU;
                        uop_o.branch_op = BR_OP_JALR;
                        uop_o.is_jump = 1'b1;
                        uop_o.is_jalr = 1'b1;
                        uop_o.writes_rd = 1'b1;
                        uop_o.has_rd = 1'b1;
                    end else begin
                        mark_illegal();
                    end
                end
                OPC_BRANCH: begin
                    uop_o.tube = TUBE_TYPE_BRC;
                    uop_o.fu_type = FU_TYPE_BRU;
                    uop_o.is_branch = 1'b1;
                    unique case (funct3)
                        3'b000: uop_o.branch_op = BR_OP_BEQ;
                        3'b001: uop_o.branch_op = BR_OP_BNE;
                        3'b100: uop_o.branch_op = BR_OP_BLT;
                        3'b101: uop_o.branch_op = BR_OP_BGE;
                        3'b110: uop_o.branch_op = BR_OP_BLTU;
                        3'b111: uop_o.branch_op = BR_OP_BGEU;
                        default: mark_illegal();
                    endcase
                end
                OPC_LOAD: begin
                    uop_o.tube = TUBE_TYPE_MEM;
                    uop_o.fu_type = FU_TYPE_LSU;
                    uop_o.lsu_op = LSU_OP_LOAD;
                    uop_o.is_load = 1'b1;
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                    unique case (funct3)
                        3'b000: begin uop_o.mem_size = 2'd0; uop_o.mem_signed = 1'b1; end
                        3'b001: begin uop_o.mem_size = 2'd1; uop_o.mem_signed = 1'b1; end
                        3'b010: begin uop_o.mem_size = 2'd2; uop_o.mem_signed = 1'b1; end
                        3'b100: begin uop_o.mem_size = 2'd0; uop_o.mem_signed = 1'b0; end
                        3'b101: begin uop_o.mem_size = 2'd1; uop_o.mem_signed = 1'b0; end
                        default: mark_illegal();
                    endcase
                end
                OPC_STORE: begin
                    uop_o.tube = TUBE_TYPE_MEM;
                    uop_o.fu_type = FU_TYPE_LSU;
                    uop_o.lsu_op = LSU_OP_STORE;
                    uop_o.is_store = 1'b1;
                    unique case (funct3)
                        3'b000: uop_o.mem_size = 2'd0;
                        3'b001: uop_o.mem_size = 2'd1;
                        3'b010: uop_o.mem_size = 2'd2;
                        default: mark_illegal();
                    endcase
                end
                OPC_OP_IMM: begin
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                    unique case (funct3)
                        3'b000: uop_o.alu_op = ALU_OP_ADD;
                        3'b010: uop_o.alu_op = ALU_OP_SLT;
                        3'b011: uop_o.alu_op = ALU_OP_SLTU;
                        3'b100: uop_o.alu_op = ALU_OP_XOR;
                        3'b110: uop_o.alu_op = ALU_OP_OR;
                        3'b111: uop_o.alu_op = ALU_OP_AND;
                        3'b001: begin
                            if (SUPPORT_ZBB && (inst[31:20] == 12'h600)) begin
                                mark_complex_int(MULDIV_OP_CLZ);
                            end else if (SUPPORT_ZBB &&
                                         (inst[31:20] == 12'h601)) begin
                                mark_complex_int(MULDIV_OP_CTZ);
                            end else if (SUPPORT_ZBB &&
                                         (inst[31:20] == 12'h602)) begin
                                mark_complex_int(MULDIV_OP_CPOP);
                            end else if (SUPPORT_ZBB &&
                                         (inst[31:20] == 12'h604)) begin
                                mark_complex_int(MULDIV_OP_SEXT_B);
                            end else if (SUPPORT_ZBB &&
                                         (inst[31:20] == 12'h605)) begin
                                mark_complex_int(MULDIV_OP_SEXT_H);
                            end else if (SUPPORT_ZBKB &&
                                         (inst[31:20] == 12'h08f)) begin
                                mark_complex_int(MULDIV_OP_ZIP);
                            end else if (SUPPORT_ZBS &&
                                         (funct7 == 7'b0010100)) begin
                                mark_complex_int(MULDIV_OP_BSETI);
                            end else if (SUPPORT_ZBS &&
                                         (funct7 == 7'b0100100)) begin
                                mark_complex_int(MULDIV_OP_BCLRI);
                            end else if (SUPPORT_ZBS &&
                                         (funct7 == 7'b0110100)) begin
                                mark_complex_int(MULDIV_OP_BINVI);
                            end else if (funct7 == 7'b0000000) begin
                                uop_o.alu_op = ALU_OP_SLL;
                            end else begin
                                mark_illegal();
                            end
                        end
                        3'b101: begin
                            if (SUPPORT_ZBKB && (inst[31:20] == 12'h687)) begin
                                mark_complex_int(MULDIV_OP_BREV8);
                            end else if (SUPPORT_ZBKB &&
                                         (inst[31:20] == 12'h08f)) begin
                                mark_complex_int(MULDIV_OP_UNZIP);
                            end else if (SUPPORT_ZBB &&
                                         (inst[31:20] == 12'h287)) begin
                                mark_complex_int(MULDIV_OP_ORC_B);
                            end else if ((SUPPORT_ZBB || SUPPORT_ZBKB) &&
                                         (inst[31:20] == 12'h698)) begin
                                mark_complex_int(MULDIV_OP_REV8);
                            end else if ((SUPPORT_ZBB || SUPPORT_ZBKB) &&
                                         (funct7 == 7'b0110000)) begin
                                mark_complex_int(MULDIV_OP_RORI);
                            end else if (SUPPORT_ZBS &&
                                         (funct7 == 7'b0100100)) begin
                                mark_complex_int(MULDIV_OP_BEXTI);
                            end else if (funct7 == 7'b0000000) begin
                                uop_o.alu_op = ALU_OP_SRL;
                            end else if (funct7 == 7'b0100000) begin
                                uop_o.alu_op = ALU_OP_SRA;
                            end else begin
                                mark_illegal();
                            end
                        end
                        default: mark_illegal();
                    endcase
                end
                OPC_OP: begin
                    uop_o.writes_rd = 1'b1;
                    uop_o.has_rd = 1'b1;
                    if (funct7 == 7'b0000001) begin
                        uop_o.tube = TUBE_TYPE_MUL;
                        uop_o.fu_type = FU_TYPE_MULDIV;
                        uop_o.is_muldiv = 1'b1;
                        unique case (funct3)
                            3'b000: uop_o.muldiv_op = MULDIV_OP_MUL;
                            3'b001: uop_o.muldiv_op = MULDIV_OP_MULH;
                            3'b010: uop_o.muldiv_op = MULDIV_OP_MULHSU;
                            3'b011: uop_o.muldiv_op = MULDIV_OP_MULHU;
                            3'b100: uop_o.muldiv_op = MULDIV_OP_DIV;
                            3'b101: uop_o.muldiv_op = MULDIV_OP_DIVU;
                            3'b110: uop_o.muldiv_op = MULDIV_OP_REM;
                            3'b111: uop_o.muldiv_op = MULDIV_OP_REMU;
                            default: mark_illegal();
                        endcase
                    end else if (SUPPORT_ZBA &&
                                 (funct7 == 7'b0010000)) begin
                        unique case (funct3)
                            3'b010: mark_complex_int(MULDIV_OP_SH1ADD);
                            3'b100: mark_complex_int(MULDIV_OP_SH2ADD);
                            3'b110: mark_complex_int(MULDIV_OP_SH3ADD);
                            default: mark_illegal();
                        endcase
                    end else if ((SUPPORT_ZBB || SUPPORT_ZBKB) &&
                                 (funct7 == 7'b0100000) &&
                                 (funct3 inside {3'b100, 3'b110, 3'b111})) begin
                        unique case (funct3)
                            3'b100: mark_complex_int(MULDIV_OP_XNOR);
                            3'b110: mark_complex_int(MULDIV_OP_ORN);
                            3'b111: mark_complex_int(MULDIV_OP_ANDN);
                            default: mark_illegal();
                        endcase
                    end else if (SUPPORT_ZBB &&
                                 (funct7 == 7'b0000101) &&
                                 funct3[2]) begin
                        unique case (funct3)
                            3'b100: mark_complex_int(MULDIV_OP_MIN);
                            3'b101: mark_complex_int(MULDIV_OP_MINU);
                            3'b110: mark_complex_int(MULDIV_OP_MAX);
                            3'b111: mark_complex_int(MULDIV_OP_MAXU);
                            default: mark_illegal();
                        endcase
                    end else if (SUPPORT_ZBC &&
                                 (funct7 == 7'b0000101)) begin
                        unique case (funct3)
                            3'b001: mark_complex_int(MULDIV_OP_CLMUL);
                            3'b010: mark_complex_int(MULDIV_OP_CLMULR);
                            3'b011: mark_complex_int(MULDIV_OP_CLMULH);
                            default: mark_illegal();
                        endcase
                    end else if ((SUPPORT_ZBB || SUPPORT_ZBKB) &&
                                 (funct7 == 7'b0110000) &&
                                 (funct3 inside {3'b001, 3'b101})) begin
                        if (funct3 == 3'b001) begin
                            mark_complex_int(MULDIV_OP_ROL);
                        end else begin
                            mark_complex_int(MULDIV_OP_ROR);
                        end
                    end else if (SUPPORT_ZBKB &&
                                 (funct7 == 7'b0000100) &&
                                 (funct3 inside {3'b100, 3'b111})) begin
                        if (funct3 == 3'b100) begin
                            mark_complex_int(MULDIV_OP_PACK);
                        end else begin
                            mark_complex_int(MULDIV_OP_PACKH);
                        end
                    end else if (SUPPORT_ZBB &&
                                 (funct7 == 7'b0000100) &&
                                 (funct3 == 3'b100) &&
                                 (inst[24:20] == 5'b0)) begin
                        mark_complex_int(MULDIV_OP_ZEXT_H);
                    end else if (SUPPORT_ZBKX &&
                                 (funct7 == 7'b0010100) &&
                                 (funct3 inside {3'b010, 3'b100})) begin
                        if (funct3 == 3'b010) begin
                            mark_complex_int(MULDIV_OP_XPERM4);
                        end else begin
                            mark_complex_int(MULDIV_OP_XPERM8);
                        end
                    end else if (SUPPORT_ZBS &&
                                 (funct3 == 3'b001) &&
                                 (funct7 inside {7'b0010100, 7'b0100100,
                                                 7'b0110100})) begin
                        unique case (funct7)
                            7'b0010100: mark_complex_int(MULDIV_OP_BSET);
                            7'b0100100: mark_complex_int(MULDIV_OP_BCLR);
                            7'b0110100: mark_complex_int(MULDIV_OP_BINV);
                            default: mark_illegal();
                        endcase
                    end else if (SUPPORT_ZBS &&
                                 (funct7 == 7'b0100100) &&
                                 (funct3 == 3'b101)) begin
                        mark_complex_int(MULDIV_OP_BEXT);
                    end else if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                        unique case (funct3)
                            3'b000: uop_o.alu_op = (funct7 == 7'b0100000) ? ALU_OP_SUB : ALU_OP_ADD;
                            3'b001: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_SLL;
                                else mark_illegal();
                            end
                            3'b010: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_SLT;
                                else mark_illegal();
                            end
                            3'b011: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_SLTU;
                                else mark_illegal();
                            end
                            3'b100: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_XOR;
                                else mark_illegal();
                            end
                            3'b101: uop_o.alu_op = (funct7 == 7'b0100000) ? ALU_OP_SRA : ALU_OP_SRL;
                            3'b110: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_OR;
                                else mark_illegal();
                            end
                            3'b111: begin
                                if (funct7 == 7'b0000000) uop_o.alu_op = ALU_OP_AND;
                                else mark_illegal();
                            end
                            default: mark_illegal();
                        endcase
                    end else begin
                        mark_illegal();
                    end
                end
                OPC_MISC: begin
                    if (funct3 == 3'b000) begin
                        uop_o.fu_type = FU_TYPE_SYSTEM;
                        uop_o.tube = TUBE_TYPE_SYS;
                        uop_o.system_op = SYS_OP_FENCE;
                        uop_o.is_system = 1'b1;
                        uop_o.is_fence = 1'b1;
                        uop_o.is_serial = 1'b1;
                    end else begin
                        mark_illegal();
                    end
                end
                OPC_SYSTEM: begin
                    uop_o.fu_type = FU_TYPE_SYSTEM;
                    uop_o.tube = TUBE_TYPE_SYS;
                    uop_o.is_system = 1'b1;
                    uop_o.is_serial = 1'b1;
                    unique case (funct3)
                        3'b000: begin
                            unique case (inst[31:20])
                                12'h000: begin
                                    uop_o.system_op = SYS_OP_ECALL;
                                    uop_o.is_trap = 1'b1;
                                    uop_o.is_ecall = 1'b1;
                                    uop_o.exception = 1'b1;
                                    uop_o.exception_cause = EXC_CAUSE_ECALL_M;
                                end
                                12'h001: begin
                                    uop_o.system_op = SYS_OP_EBREAK;
                                    uop_o.is_trap = 1'b1;
                                    uop_o.is_ebreak = 1'b1;
                                    uop_o.exception = 1'b1;
                                    uop_o.exception_cause = EXC_CAUSE_BREAKPOINT;
                                end
                                12'h302: begin
                                    uop_o.system_op = SYS_OP_MRET;
                                    uop_o.is_mret = 1'b1;
                                end
                                default: mark_illegal();
                            endcase
                        end
                        3'b001, 3'b010, 3'b011, 3'b101, 3'b110, 3'b111: begin
                            uop_o.fu_type = FU_TYPE_CSR;
                            uop_o.is_csr = 1'b1;
                            uop_o.csr_imm = funct3[2];
                            uop_o.writes_rd = 1'b1;
                            uop_o.has_rd = 1'b1;
                            unique case (funct3[1:0])
                                2'b01: uop_o.csr_op = CSR_OP_RW;
                                2'b10: uop_o.csr_op = CSR_OP_RS;
                                2'b11: uop_o.csr_op = CSR_OP_RC;
                                default: mark_illegal();
                            endcase
                        end
                        default: mark_illegal();
                    endcase
                end
                default: mark_illegal();
            endcase
        end
    end
endmodule : CoreRv32Decoder
