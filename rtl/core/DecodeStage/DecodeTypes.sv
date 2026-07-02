//------------------------------------------------------------------------------
// DecodeTypes.sv
// 作用：定义 RISC-V 指令译码常量和译码辅助函数。
// 微架构定位：Decode 只负责把原始指令转换成后端可消费的控制信息，包括执行
// 管线类型、子类型、操作数来源、逻辑寄存器需求、CSR 地址和 serial 标记。
// 它不分配物理寄存器、不访问 ROB，也不做恢复决策。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;

package DecodeTypes;

    localparam OP_LUI      = 7'b0110111;
    localparam OP_AUIPC    = 7'b0010111;
    localparam OP_JAL      = 7'b1101111;
    localparam OP_JALR     = 7'b1100111;
    localparam OP_BRANCH   = 7'b1100011;
    localparam OP_LOAD     = 7'b0000011;
    localparam OP_STORE    = 7'b0100011;
    localparam OP_OP_IMM   = 7'b0010011;
    localparam OP_OP       = 7'b0110011;
    localparam OP_MISC_MEM = 7'b0001111;
    localparam OP_SYSTEM   = 7'b1110011;

    localparam logic [2:0] F3_BEQ_B  = 3'b000;
    localparam logic [2:0] F3_BNE_H  = 3'b001;
    localparam logic [2:0] F3_LW     = 3'b010;
    localparam logic [2:0] F3_BLT    = 3'b100;
    localparam logic [2:0] F3_BGE    = 3'b101;
    localparam logic [2:0] F3_BLTU   = 3'b110;
    localparam logic [2:0] F3_BGEU   = 3'b111;

    localparam logic [2:0] F3_ADD    = 3'b000;
    localparam logic [2:0] F3_SLL    = 3'b001;
    localparam logic [2:0] F3_SLT    = 3'b010;
    localparam logic [2:0] F3_SLTU   = 3'b011;
    localparam logic [2:0] F3_XOR    = 3'b100;
    localparam logic [2:0] F3_SRX    = 3'b101;
    localparam logic [2:0] F3_OR     = 3'b110;
    localparam logic [2:0] F3_AND    = 3'b111;

    localparam logic [6:0] F7_BASE   = 7'b0000000;
    localparam logic [6:0] F7_SUBSRA = 7'b0100000;
    localparam logic [6:0] F7_MULDIV = 7'b0000001;

    function automatic void SetInvalidDecode(
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo,
        output CsrAddrPath     csrAddr
    );
        instInfo.valid       = FALSE;
        instInfo.isSerial    = FALSE;
        instInfo.writeReg    = FALSE;
        instInfo.tubeType    = TUBE_TYPE_ALU;
        instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
        instInfo.opTypeA     = OP_TYPE_NONE;
        instInfo.opTypeB     = OP_TYPE_NONE;

        lgcRegInfo.lgcRegNumSrcAValid = FALSE;
        lgcRegInfo.lgcRegNumSrcBValid = FALSE;
        lgcRegInfo.lgcRegNumDstValid  = FALSE;
        lgcRegInfo.lgcRegNumSrcA      = '0;
        lgcRegInfo.lgcRegNumSrcB      = '0;
        lgcRegInfo.lgcRegNumDst       = '0;

        csrAddr.valid   = FALSE;
        csrAddr.csrAddr = '0;
    endfunction

    function automatic void DecodeLUI(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_ALU;
        instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
        instInfo.opTypeA     = OP_TYPE_IMM;
        instInfo.opTypeB     = OP_TYPE_NONE;

        lgcRegInfo.lgcRegNumDstValid = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst      = inst[11:7];
    endfunction

    function automatic void DecodeAUIPC(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_ALU;
        instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
        instInfo.opTypeA     = OP_TYPE_PC;
        instInfo.opTypeB     = OP_TYPE_IMM;

        lgcRegInfo.lgcRegNumDstValid = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst      = inst[11:7];
    endfunction

    function automatic void DecodeJAL(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_BRC;
        instInfo.SubType.brcSubType = BRC_SUBTYPE_JAL;
        instInfo.opTypeA     = OP_TYPE_PC;
        instInfo.opTypeB     = OP_TYPE_IMM;

        lgcRegInfo.lgcRegNumDstValid = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst      = inst[11:7];
    endfunction

    function automatic void DecodeJALR(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = (inst[14:12] == 3'b000);
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_BRC;
        instInfo.SubType.brcSubType = BRC_SUBTYPE_JALR;
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_IMM;

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumDstValid  = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst       = inst[11:7];
    endfunction

    function automatic void DecodeBRANCH(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = FALSE;
        instInfo.tubeType    = TUBE_TYPE_BRC;
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_REG;

        unique case (inst[14:12])
            3'b000:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BEQ;
            3'b001:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BNE;
            3'b100:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BLT;
            3'b101:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BGE;
            3'b110:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BLTU;
            3'b111:  instInfo.SubType.brcSubType = BRC_SUBTYPE_BGEU;
            default: begin
                instInfo.valid = FALSE;
                instInfo.SubType.brcSubType = BRC_SUBTYPE_BEQ;
            end
        endcase

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumSrcBValid = TRUE;
        lgcRegInfo.lgcRegNumSrcB      = inst[24:20];
    endfunction

    function automatic void DecodeLOAD(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_MEM;
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_IMM;

        unique case (inst[14:12])
            3'b000:  instInfo.SubType.memSubType = MEM_SUBTYPE_LB;
            3'b001:  instInfo.SubType.memSubType = MEM_SUBTYPE_LH;
            3'b010:  instInfo.SubType.memSubType = MEM_SUBTYPE_LW;
            3'b100:  instInfo.SubType.memSubType = MEM_SUBTYPE_LBU;
            3'b101:  instInfo.SubType.memSubType = MEM_SUBTYPE_LHU;
            default: begin
                instInfo.valid = FALSE;
                instInfo.SubType.memSubType = MEM_SUBTYPE_LW;
            end
        endcase

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumDstValid  = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst       = inst[11:7];
    endfunction

    function automatic void DecodeSTORE(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = FALSE;
        instInfo.tubeType    = TUBE_TYPE_MEM;
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_IMM;

        unique case (inst[14:12])
            3'b000:  instInfo.SubType.memSubType = MEM_SUBTYPE_SB;
            3'b001:  instInfo.SubType.memSubType = MEM_SUBTYPE_SH;
            3'b010:  instInfo.SubType.memSubType = MEM_SUBTYPE_SW;
            default: begin
                instInfo.valid = FALSE;
                instInfo.SubType.memSubType = MEM_SUBTYPE_SW;
            end
        endcase

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumSrcBValid = TRUE;
        lgcRegInfo.lgcRegNumSrcB      = inst[24:20];
    endfunction

    function automatic void DecodeOPIMM(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.tubeType    = TUBE_TYPE_ALU;
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_IMM;

        unique case (inst[14:12])
            F3_ADD:  instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
            F3_SLL:  begin
                instInfo.valid = (inst[31:25] == F7_BASE);
                instInfo.SubType.aluSubType = ALU_SUBTYPE_SLL;
            end
            F3_SLT:  instInfo.SubType.aluSubType = ALU_SUBTYPE_SLT;
            F3_SLTU: instInfo.SubType.aluSubType = ALU_SUBTYPE_SLTU;
            F3_XOR:  instInfo.SubType.aluSubType = ALU_SUBTYPE_XOR;
            F3_SRX:  begin
                instInfo.valid = (inst[31:25] == F7_BASE) || (inst[31:25] == F7_SUBSRA);
                instInfo.SubType.aluSubType = (inst[31:25] == F7_SUBSRA) ? ALU_SUBTYPE_SRA : ALU_SUBTYPE_SRL;
            end
            F3_OR:   instInfo.SubType.aluSubType = ALU_SUBTYPE_OR;
            F3_AND:  instInfo.SubType.aluSubType = ALU_SUBTYPE_AND;
            default: begin
                instInfo.valid = FALSE;
                instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
            end
        endcase

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumDstValid  = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst       = inst[11:7];
    endfunction

    function automatic void DecodeOP(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = TRUE;
        instInfo.writeReg    = (inst[11:7] != '0);
        instInfo.opTypeA     = OP_TYPE_REG;
        instInfo.opTypeB     = OP_TYPE_REG;

        if (inst[31:25] == F7_MULDIV) begin
            instInfo.tubeType = TUBE_TYPE_MUL;
            unique case (inst[14:12])
                3'b000:  instInfo.SubType.mulSubType = MUL_SUBTYPE_MUL;
                3'b001:  instInfo.SubType.mulSubType = MUL_SUBTYPE_MULH;
                3'b010:  instInfo.SubType.mulSubType = MUL_SUBTYPE_MULHSU;
                3'b011:  instInfo.SubType.mulSubType = MUL_SUBTYPE_MULHU;
                3'b100:  instInfo.SubType.mulSubType = MUL_SUBTYPE_DIV;
                3'b101:  instInfo.SubType.mulSubType = MUL_SUBTYPE_DIVU;
                3'b110:  instInfo.SubType.mulSubType = MUL_SUBTYPE_REM;
                3'b111:  instInfo.SubType.mulSubType = MUL_SUBTYPE_REMU;
                default: begin
                    instInfo.valid = FALSE;
                    instInfo.SubType.mulSubType = MUL_SUBTYPE_MUL;
                end
            endcase
        end else begin
            instInfo.tubeType = TUBE_TYPE_ALU;
            unique case (inst[14:12])
                F3_ADD: begin
                    instInfo.valid = (inst[31:25] == F7_BASE) || (inst[31:25] == F7_SUBSRA);
                    instInfo.SubType.aluSubType = (inst[31:25] == F7_SUBSRA) ? ALU_SUBTYPE_SUB : ALU_SUBTYPE_ADD;
                end
                F3_SLL: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_SLL;
                end
                F3_SLT: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_SLT;
                end
                F3_SLTU: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_SLTU;
                end
                F3_XOR: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_XOR;
                end
                F3_SRX: begin
                    instInfo.valid = (inst[31:25] == F7_BASE) || (inst[31:25] == F7_SUBSRA);
                    instInfo.SubType.aluSubType = (inst[31:25] == F7_SUBSRA) ? ALU_SUBTYPE_SRA : ALU_SUBTYPE_SRL;
                end
                F3_OR: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_OR;
                end
                F3_AND: begin
                    instInfo.valid = (inst[31:25] == F7_BASE);
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_AND;
                end
                default: begin
                    instInfo.valid = FALSE;
                    instInfo.SubType.aluSubType = ALU_SUBTYPE_ADD;
                end
            endcase
        end

        lgcRegInfo.lgcRegNumSrcAValid = TRUE;
        lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
        lgcRegInfo.lgcRegNumSrcBValid = TRUE;
        lgcRegInfo.lgcRegNumSrcB      = inst[24:20];
        lgcRegInfo.lgcRegNumDstValid  = (inst[11:7] != '0);
        lgcRegInfo.lgcRegNumDst       = inst[11:7];
    endfunction

    function automatic void DecodeMISCMEM(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo
    );
        CsrAddrPath unusedCsrAddr;

        SetInvalidDecode(instInfo, lgcRegInfo, unusedCsrAddr);
        instInfo.valid       = (inst[14:12] == 3'b000) || (inst[14:12] == 3'b001);
        instInfo.isSerial    = TRUE;
        instInfo.writeReg    = FALSE;
        instInfo.tubeType    = TUBE_TYPE_SYS;
        instInfo.SubType.sysSubType = SYS_SUBTYPE_EBREAK;
        instInfo.opTypeA     = OP_TYPE_NONE;
        instInfo.opTypeB     = OP_TYPE_NONE;
    endfunction

    function automatic void DecodeSYSTEM(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo,
        output CsrAddrPath     csrAddr
    );
        SetInvalidDecode(instInfo, lgcRegInfo, csrAddr);
        instInfo.valid       = TRUE;
        instInfo.isSerial    = TRUE;
        instInfo.tubeType    = TUBE_TYPE_SYS;
        instInfo.opTypeB     = OP_TYPE_NONE;

        if (inst[14:12] == 3'b000) begin
            instInfo.writeReg = FALSE;
            instInfo.opTypeA  = OP_TYPE_NONE;
            unique case (inst[31:20])
                12'h000:  instInfo.SubType.sysSubType = SYS_SUBTYPE_ECALL;
                12'h001:  instInfo.SubType.sysSubType = SYS_SUBTYPE_EBREAK;
                12'h302: begin
                    instInfo.SubType.sysSubType = SYS_SUBTYPE_EBREAK;
                    csrAddr.valid = TRUE;
                    csrAddr.csrAddr = 12'h302;
                end
                default: begin
                    instInfo.valid = FALSE;
                    instInfo.SubType.sysSubType = SYS_SUBTYPE_ECALL;
                end
            endcase
        end else begin
            csrAddr.valid   = TRUE;
            csrAddr.csrAddr = inst[31:20];

            instInfo.writeReg = (inst[11:7] != '0);
            instInfo.opTypeA  = (inst[14]) ? OP_TYPE_IMM : OP_TYPE_REG;

            lgcRegInfo.lgcRegNumDstValid = (inst[11:7] != '0);
            lgcRegInfo.lgcRegNumDst      = inst[11:7];

            if (!inst[14]) begin
                lgcRegInfo.lgcRegNumSrcAValid = (inst[19:15] != '0);
                lgcRegInfo.lgcRegNumSrcA      = inst[19:15];
            end

            unique case (inst[14:12])
                3'b001:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRW;
                3'b010:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRS;
                3'b011:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRC;
                3'b101:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRWI;
                3'b110:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRSI;
                3'b111:  instInfo.SubType.sysSubType = SYS_SUBTYPE_CSRRCI;
                default: begin
                    instInfo.valid = FALSE;
                    instInfo.SubType.sysSubType = SYS_SUBTYPE_ECALL;
                end
            endcase
        end
    endfunction

    function automatic void DecodeInst(
        input  InstPath        inst,
        output InstInfoPath    instInfo,
        output LgcRegInfoPath  lgcRegInfo,
        output CsrAddrPath     csrAddr
    );
        SetInvalidDecode(instInfo, lgcRegInfo, csrAddr);

        unique case (inst[6:0])
            OP_LUI:      DecodeLUI(inst, instInfo, lgcRegInfo);
            OP_AUIPC:    DecodeAUIPC(inst, instInfo, lgcRegInfo);
            OP_JAL:      DecodeJAL(inst, instInfo, lgcRegInfo);
            OP_JALR:     DecodeJALR(inst, instInfo, lgcRegInfo);
            OP_BRANCH:   DecodeBRANCH(inst, instInfo, lgcRegInfo);
            OP_LOAD:     DecodeLOAD(inst, instInfo, lgcRegInfo);
            OP_STORE:    DecodeSTORE(inst, instInfo, lgcRegInfo);
            OP_OP_IMM:   DecodeOPIMM(inst, instInfo, lgcRegInfo);
            OP_OP:       DecodeOP(inst, instInfo, lgcRegInfo);
            OP_MISC_MEM: DecodeMISCMEM(inst, instInfo, lgcRegInfo);
            OP_SYSTEM:   DecodeSYSTEM(inst, instInfo, lgcRegInfo, csrAddr);
            default:     SetInvalidDecode(instInfo, lgcRegInfo, csrAddr);
        endcase
    endfunction


    function automatic void ImmGen(
        input  InstPath    inst,
        output DataPath    imm
    );
        unique case (inst[6:0])
            OP_LUI, OP_AUIPC: imm = {inst[31:12], 12'b0};
            OP_JAL:           imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            OP_JALR, OP_LOAD, OP_OP_IMM: imm = {{20{inst[31]}}, inst[31:20]};
            OP_BRANCH:        imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            OP_STORE:         imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            OP_SYSTEM:        imm = {27'b0, inst[19:15]};
            default:          imm = '0;
        endcase
    endfunction
endpackage
