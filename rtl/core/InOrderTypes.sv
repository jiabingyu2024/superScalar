`timescale 1ns / 1ps

import BasicTypes::*;

package InOrderTypes;
    localparam PcPath RESET_PC = 32'h8000_0000;

    localparam logic [6:0] OP_LUI      = 7'b0110111;
    localparam logic [6:0] OP_AUIPC    = 7'b0010111;
    localparam logic [6:0] OP_JAL      = 7'b1101111;
    localparam logic [6:0] OP_JALR     = 7'b1100111;
    localparam logic [6:0] OP_BRANCH   = 7'b1100011;
    localparam logic [6:0] OP_LOAD     = 7'b0000011;
    localparam logic [6:0] OP_STORE    = 7'b0100011;
    localparam logic [6:0] OP_OP_IMM   = 7'b0010011;
    localparam logic [6:0] OP_OP       = 7'b0110011;
    localparam logic [6:0] OP_MISC_MEM = 7'b0001111;
    localparam logic [6:0] OP_SYSTEM   = 7'b1110011;

    localparam logic [11:0] CSR_MSTATUS   = 12'h300;
    localparam logic [11:0] CSR_MTVEC     = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
    localparam logic [11:0] CSR_MEPC      = 12'h341;
    localparam logic [11:0] CSR_MCAUSE    = 12'h342;
    localparam logic [11:0] CSR_MHARTID   = 12'hf14;
    localparam logic [11:0] CSR_CYCLE     = 12'hc00;
    localparam logic [11:0] CSR_INSTRET   = 12'hc02;
    localparam logic [11:0] CSR_CYCLEH    = 12'hc80;
    localparam logic [11:0] CSR_INSTRETH  = 12'hc82;
    localparam logic [11:0] CSR_MCYCLE    = 12'hb00;
    localparam logic [11:0] CSR_MINSTRET  = 12'hb02;
    localparam logic [11:0] CSR_MCYCLEH   = 12'hb80;
    localparam logic [11:0] CSR_MINSTRETH = 12'hb82;

    typedef enum logic [2:0] {
        M_NORMAL,
        M_LOAD_REQ,
        M_LOAD_WAIT0,
        M_LOAD_WAIT1,
        M_STORE_REQ,
        M_MULDIV_WAIT,
        M_MULDIV_WB
    } MemState;

    typedef struct packed {
        logic valid;
        PcPath pc;
        InstPath inst0;
        InstPath inst1;
        logic predTaken;
        PcPath predTarget;
    } FetchPacket;

    typedef struct packed {
        logic valid;
        PcPath pc;
        InstPath inst;
        logic predTaken;
        PcPath predTarget;
    } Uop;

    typedef struct packed {
        logic valid;
        logic [4:0] rd;
        DataPath data;
    } WbEntry;

    typedef struct packed {
        logic valid;
        logic [2:0] funct3;
        logic [4:0] rd;
        DataPath a;
        DataPath b;
    } MulDivInfo;

    typedef struct packed {
        logic valid;
        logic [4:0] rd;
        logic [2:0] funct3;
        AddrPath addr;
    } LoadInfo;

    typedef struct packed {
        logic valid;
        AddrPath addr;
        DataPath data;
        logic [3:0] mask;
    } StoreInfo;

    typedef struct packed {
        DataPath mstatus;
        DataPath mtvec;
        DataPath mscratch;
        DataPath mepc;
        DataPath mcause;
    } CsrState;

    typedef struct packed {
        logic valid;
        CsrState state;
    } CsrUpdate;

    typedef struct packed {
        WbEntry wb;
        logic commit;
        logic branch;
        logic condBranch;
        logic jal;
        logic jalr;
        logic redirect;
        PcPath redirectPc;
        logic branchMiss;
        logic condBranchMiss;
        logic jalMiss;
        logic jalrMiss;
        logic loadReq;
        LoadInfo loadInfo;
        logic storeReq;
        StoreInfo storeInfo;
        logic mulDivReq;
        MulDivInfo mulDivInfo;
        CsrUpdate csrUpdate;
    } ExecuteResult;

    function automatic logic [4:0] rd(input InstPath inst);
        return inst[11:7];
    endfunction

    function automatic logic [4:0] rs1(input InstPath inst);
        return inst[19:15];
    endfunction

    function automatic logic [4:0] rs2(input InstPath inst);
        return inst[24:20];
    endfunction

    function automatic logic writes_rd(input InstPath inst);
        logic [6:0] opc;
        opc = inst[6:0];
        return rd(inst) != 5'd0 &&
               (opc inside {OP_LUI, OP_AUIPC, OP_JAL, OP_JALR, OP_LOAD,
                            OP_OP_IMM, OP_OP, OP_SYSTEM});
    endfunction

    function automatic logic reads_rs1(input InstPath inst);
        logic [6:0] opc;
        opc = inst[6:0];
        if (opc == OP_LUI || opc == OP_AUIPC || opc == OP_JAL ||
            opc == OP_MISC_MEM) begin
            return 1'b0;
        end
        if (opc == OP_SYSTEM && inst[14]) begin
            return 1'b0;
        end
        return opc inside {OP_JALR, OP_BRANCH, OP_LOAD, OP_STORE, OP_OP_IMM,
                           OP_OP, OP_SYSTEM};
    endfunction

    function automatic logic reads_rs2(input InstPath inst);
        return inst[6:0] inside {OP_BRANCH, OP_STORE, OP_OP};
    endfunction

    function automatic logic is_control(input InstPath inst);
        return inst[6:0] inside {OP_JAL, OP_JALR, OP_BRANCH, OP_SYSTEM};
    endfunction

    function automatic logic is_cond_branch(input InstPath inst);
        return inst[6:0] == OP_BRANCH;
    endfunction

    function automatic logic is_memory(input InstPath inst);
        return inst[6:0] inside {OP_LOAD, OP_STORE};
    endfunction

    function automatic logic is_muldiv(input InstPath inst);
        return inst[6:0] == OP_OP && inst[31:25] == 7'b0000001;
    endfunction

    function automatic logic can_pair(input InstPath a, input InstPath b);
        logic waw;

        waw = writes_rd(a) && writes_rd(b) && rd(a) == rd(b);

        return a != 32'b0 && b != 32'b0 &&
               !is_control(a) && !is_control(b) &&
               !is_memory(a) && !is_memory(b) &&
               !is_muldiv(a) && !is_muldiv(b) &&
               !waw;
    endfunction

    function automatic DataPath imm_i(input InstPath inst);
        return {{20{inst[31]}}, inst[31:20]};
    endfunction

    function automatic DataPath imm_s(input InstPath inst);
        return {{20{inst[31]}}, inst[31:25], inst[11:7]};
    endfunction

    function automatic DataPath imm_b(input InstPath inst);
        return {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    endfunction

    function automatic DataPath imm_u(input InstPath inst);
        return {inst[31:12], 12'b0};
    endfunction

    function automatic DataPath imm_j(input InstPath inst);
        return {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
    endfunction

    function automatic DataPath load_extend(input logic [2:0] funct3, input DataPath data);
        unique case (funct3)
            3'b000:  load_extend = {{24{data[7]}}, data[7:0]};
            3'b001:  load_extend = {{16{data[15]}}, data[15:0]};
            3'b100:  load_extend = {24'b0, data[7:0]};
            3'b101:  load_extend = {16'b0, data[15:0]};
            default: load_extend = data;
        endcase
    endfunction

    function automatic logic [3:0] store_wstrb(input logic [2:0] funct3);
        unique case (funct3)
            3'b000:  store_wstrb = 4'b0001;
            3'b001:  store_wstrb = 4'b0011;
            default: store_wstrb = 4'b1111;
        endcase
    endfunction
endpackage
