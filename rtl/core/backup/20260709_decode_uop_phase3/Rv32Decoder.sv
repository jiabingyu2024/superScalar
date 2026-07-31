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

    always_comb begin
        inst = fetch_i.inst;
        uop_o = '0;
        uop_o.valid = fetch_i.valid;
        uop_o.pc = fetch_i.pc;
        uop_o.inst = inst;
        uop_o.pred_taken = fetch_i.pred_taken;
        uop_o.pred_target = fetch_i.pred_target;
        uop_o.opcode = inst[6:0];
        uop_o.rd = inst[11:7];
        uop_o.funct3 = inst[14:12];
        uop_o.rs1 = inst[19:15];
        uop_o.rs2 = inst[24:20];
        uop_o.funct7 = inst[31:25];
        uop_o.imm_i = {{20{inst[31]}}, inst[31:20]};
        uop_o.imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        uop_o.imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        uop_o.imm_u = {inst[31:12], 12'b0};
        uop_o.imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        uop_o.illegal = (inst[1:0] != 2'b11);

        case (inst[6:0])
            OPC_LOAD: begin
                uop_o.tube = TUBE_TYPE_MEM;
                uop_o.is_load = 1'b1;
                uop_o.writes_rd = 1'b1;
            end
            OPC_STORE: begin
                uop_o.tube = TUBE_TYPE_MEM;
                uop_o.is_store = 1'b1;
            end
            OPC_BRANCH: begin
                uop_o.tube = TUBE_TYPE_BRC;
                uop_o.is_branch = 1'b1;
            end
            OPC_JAL: begin
                uop_o.tube = TUBE_TYPE_BRC;
                uop_o.is_jal = 1'b1;
                uop_o.writes_rd = 1'b1;
            end
            OPC_JALR: begin
                uop_o.tube = TUBE_TYPE_BRC;
                uop_o.is_jalr = 1'b1;
                uop_o.writes_rd = 1'b1;
            end
            OPC_OP: begin
                uop_o.tube = (inst[31:25] == 7'b0000001) ? TUBE_TYPE_MUL : TUBE_TYPE_ALU;
                uop_o.writes_rd = 1'b1;
            end
            OPC_SYSTEM: begin
                uop_o.tube = TUBE_TYPE_SYS;
                uop_o.is_system = 1'b1;
                uop_o.writes_rd = (inst[14:12] != 3'b000);
            end
            OPC_LUI, OPC_AUIPC, OPC_OP_IMM, OPC_MISC: begin
                uop_o.tube = TUBE_TYPE_ALU;
                uop_o.writes_rd = (inst[6:0] != OPC_MISC);
            end
            default: begin
                uop_o.illegal = 1'b1;
            end
        endcase
    end
endmodule : CoreRv32Decoder
