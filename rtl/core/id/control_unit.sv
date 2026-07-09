//==============================================================================
// 模块: control_unit
// 功能概述：
//   纯组合（或带小寄存器，视实现而定）控制译码单元。输入 32 位指令字，输出访存/写回/ALU 类型、
//   是否用立即数作 ALU 第二操作数、分支标志、func3、alu_ctrl、inst_spec 等，不含寄存器堆读写。
// 接口/协作审查（供采纳）：
//   - 与 stage_id 中控制信号应对齐；注释掉的 o_alu1_src/o_alu2_src 若后续启用，需同步流水线寄存器位宽。
//   - o_inst_spec 为 4 位自定义编码，建议文档化与 RISC-V opcode/funct 的对应关系，便于 EX/前递/分支共用。
//==============================================================================
`include "cpu_defines.svh"

module control_unit(
    input  logic  [`INST_BUS]               i_instr,

    output logic                            o_mem_read,
    output logic                            o_mem_write,
    output logic                            o_reg_write,
    output logic                            o_wb_src,
    // output logic                            o_alu1_src,
    // output logic                            o_alu2_src,
    output logic                            o_is_rs2_imm,
    output logic  [3:0]                     o_inst_spec,

    output logic  [3:0]                     o_alu_ctrl,
    output logic  [2:0]                     o_func3,

    output logic                            o_is_branch,
    output logic  [3:0]                     o_mem_mask,
    output logic                            o_load_unsigned
    // output logic                            o_is_jtype,
    // output logic                            o_is_lui,
    
);

    logic [6:0] opcode;
    logic [2:0] func3;
    logic [6:0] func7;

    assign opcode = i_instr[6:0];
    assign func3  = i_instr[14:12];
    assign func7  = i_instr[31:25];

    always_comb begin
        o_mem_read      = 1'b0;
        o_mem_write     = 1'b0;
        o_reg_write     = 1'b0;
        o_wb_src        = `WB_SRC_ALU;
        o_is_rs2_imm    = 1'b0;
        o_inst_spec     = '0;
        o_alu_ctrl      = `ALU_ADD;
        o_func3         = func3;
        o_is_branch     = 1'b0;
        o_mem_mask      = `MASK_WORD;
        o_load_unsigned = 1'b0;

        unique case (opcode)
            `OP_R_TYPE: begin
                o_reg_write = 1'b1;
                unique case (func3)
                    `FUNC3_ADD_SUB: o_alu_ctrl = (func7 == `FUNC7_SUB) ? `ALU_SUB : `ALU_ADD;
                    `FUNC3_SLT:     o_alu_ctrl = `ALU_LT;
                    `FUNC3_SLTU:    o_alu_ctrl = `ALU_LTU;
                    `FUNC3_AND:     o_alu_ctrl = `ALU_AND;
                    `FUNC3_OR:      o_alu_ctrl = `ALU_OR;
                    `FUNC3_XOR:     o_alu_ctrl = `ALU_XOR;
                    `FUNC3_SLL:     o_alu_ctrl = `ALU_SL;
                    `FUNC3_SRL_SRA: o_alu_ctrl = (func7 == `FUNC7_SRA) ? `ALU_SRA : `ALU_SRL;
                    default:        o_alu_ctrl = `ALU_ADD;
                endcase
            end

            `OP_I_TYPE: begin
                o_reg_write  = 1'b1;
                o_is_rs2_imm = 1'b1;
                unique case (func3)
                    `FUNC3_ADD_SUB: o_alu_ctrl = `ALU_ADD;
                    `FUNC3_SLT:     o_alu_ctrl = `ALU_LT;
                    `FUNC3_SLTU:    o_alu_ctrl = `ALU_LTU;
                    `FUNC3_AND:     o_alu_ctrl = `ALU_AND;
                    `FUNC3_OR:      o_alu_ctrl = `ALU_OR;
                    `FUNC3_XOR:     o_alu_ctrl = `ALU_XOR;
                    `FUNC3_SLL:     o_alu_ctrl = `ALU_SL;
                    `FUNC3_SRL_SRA: o_alu_ctrl = i_instr[30] ? `ALU_SRA : `ALU_SRL;
                    default:        o_alu_ctrl = `ALU_ADD;
                endcase
            end

            `OP_L_TYPE: begin
                o_mem_read      = 1'b1;
                o_reg_write     = 1'b1;
                o_wb_src        = `WB_SRC_MEM;
                o_is_rs2_imm    = 1'b1;
                o_alu_ctrl      = `ALU_ADD;
                o_load_unsigned = func3[2];
                unique case (func3)
                    `FUNC3_LB, `FUNC3_LBU: o_mem_mask = `MASK_BYTE;
                    `FUNC3_LH, `FUNC3_LHU: o_mem_mask = `MASK_HALF;
                    default:               o_mem_mask = `MASK_WORD;
                endcase
            end

            `OP_S_TYPE: begin
                o_mem_write  = 1'b1;
                o_is_rs2_imm = 1'b1;
                o_alu_ctrl   = `ALU_ADD;
                unique case (func3)
                    `FUNC3_SB: o_mem_mask = `MASK_BYTE;
                    `FUNC3_SH: o_mem_mask = `MASK_HALF;
                    default:   o_mem_mask = `MASK_WORD;
                endcase
            end

            `OP_B_TYPE: begin
                o_is_branch = 1'b1;
            end

            `OP_JAL: begin
                o_reg_write = 1'b1;
                o_inst_spec = `EX_JAL;
            end

            `OP_JALR: begin
                o_reg_write  = 1'b1;
                o_is_rs2_imm = 1'b1;
                o_inst_spec  = `EX_JALR;
                o_alu_ctrl   = `ALU_ADD;
            end

            `OP_LUI: begin
                o_reg_write  = 1'b1;
                o_is_rs2_imm = 1'b1;
                o_inst_spec  = `EX_LUI;
            end

            `OP_AUIPC: begin
                o_reg_write  = 1'b1;
                o_is_rs2_imm = 1'b1;
                o_inst_spec  = `EX_AUIPC;
                o_alu_ctrl   = `ALU_ADD;
            end

            default: begin
            end
        endcase
    end
endmodule
