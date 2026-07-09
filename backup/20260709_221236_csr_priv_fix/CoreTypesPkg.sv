package CoreTypesPkg;
    import CoreConfigPkg::*;

    localparam logic TRUE  = 1'b1;
    localparam logic FALSE = 1'b0;

    typedef logic [BYTE_WIDTH-1:0] BytePath;
    typedef logic [INST_WIDTH-1:0] InstPath;
    typedef logic [ADDR_WIDTH-1:0] AddrPath;
    typedef logic [DATA_WIDTH-1:0] DataPath;
    typedef logic [PC_WIDTH-1:0]   PcPath;

    typedef logic [$clog2(LOGIC_REG_NUM)-1:0] LgcRegNumPath;
    typedef logic [$clog2(PHY_REG_NUM)-1:0]   PhyRegNumPath;
    typedef logic [$clog2(FETCH_WIDTH)-1:0]   WayNumPath;
    typedef logic [$clog2(ROB_DEPTH)-1:0]     RobIndexPath;

    typedef enum logic [2:0] {
        TUBE_TYPE_ALU = 3'b000,
        TUBE_TYPE_MEM = 3'b001,
        TUBE_TYPE_BRC = 3'b010,
        TUBE_TYPE_MUL = 3'b011,
        TUBE_TYPE_SYS = 3'b100
    } TubeTypePath;

    typedef enum logic [2:0] {
        FU_TYPE_INT    = 3'b000,
        FU_TYPE_BRU    = 3'b001,
        FU_TYPE_LSU    = 3'b010,
        FU_TYPE_MULDIV = 3'b011,
        FU_TYPE_CSR    = 3'b100,
        FU_TYPE_SYSTEM = 3'b101
    } CoreFuType;

    typedef enum logic [4:0] {
        ALU_OP_ADD   = 5'd0,
        ALU_OP_SUB   = 5'd1,
        ALU_OP_SLL   = 5'd2,
        ALU_OP_SLT   = 5'd3,
        ALU_OP_SLTU  = 5'd4,
        ALU_OP_XOR   = 5'd5,
        ALU_OP_SRL   = 5'd6,
        ALU_OP_SRA   = 5'd7,
        ALU_OP_OR    = 5'd8,
        ALU_OP_AND   = 5'd9,
        ALU_OP_COPY_B = 5'd10
    } CoreAluOp;

    typedef enum logic [3:0] {
        BR_OP_NONE = 4'd0,
        BR_OP_BEQ  = 4'd1,
        BR_OP_BNE  = 4'd2,
        BR_OP_BLT  = 4'd3,
        BR_OP_BGE  = 4'd4,
        BR_OP_BLTU = 4'd5,
        BR_OP_BGEU = 4'd6,
        BR_OP_JAL  = 4'd7,
        BR_OP_JALR = 4'd8
    } CoreBranchOp;

    typedef enum logic [2:0] {
        LSU_OP_NONE  = 3'd0,
        LSU_OP_LOAD  = 3'd1,
        LSU_OP_STORE = 3'd2
    } CoreLsuOp;

    typedef enum logic [3:0] {
        MULDIV_OP_NONE   = 4'd0,
        MULDIV_OP_MUL    = 4'd1,
        MULDIV_OP_MULH   = 4'd2,
        MULDIV_OP_MULHSU = 4'd3,
        MULDIV_OP_MULHU  = 4'd4,
        MULDIV_OP_DIV    = 4'd5,
        MULDIV_OP_DIVU   = 4'd6,
        MULDIV_OP_REM    = 4'd7,
        MULDIV_OP_REMU   = 4'd8
    } CoreMulDivOp;

    typedef enum logic [2:0] {
        CSR_OP_NONE = 3'd0,
        CSR_OP_RW   = 3'd1,
        CSR_OP_RS   = 3'd2,
        CSR_OP_RC   = 3'd3
    } CoreCsrOp;

    typedef enum logic [2:0] {
        SYS_OP_NONE   = 3'd0,
        SYS_OP_ECALL  = 3'd1,
        SYS_OP_EBREAK = 3'd2,
        SYS_OP_MRET   = 3'd3,
        SYS_OP_FENCE  = 3'd4
    } CoreSystemOp;

    localparam logic [31:0] EXC_CAUSE_INST_MISALIGNED = 32'd0;
    localparam logic [31:0] EXC_CAUSE_ILLEGAL_INST    = 32'd2;
    localparam logic [31:0] EXC_CAUSE_BREAKPOINT      = 32'd3;
    localparam logic [31:0] EXC_CAUSE_ECALL_M         = 32'd11;

    typedef struct packed {
        logic btbhit;
        logic taken;
        PcPath target;
    } BpuPrdPath;

    typedef struct packed {
        PcPath pcPred;
        logic  isPred;
    } PredInfoPath;

    typedef struct packed {
        logic [11:0] csrAddr;
        logic        valid;
    } CsrAddrPath;

    typedef struct packed {
        logic        valid;
        PcPath       pc;
        InstPath     inst;
        logic        pred_taken;
        PcPath       pred_target;
    } CoreFetchPacket;

    typedef struct packed {
        logic        valid;
        PcPath       pc;
        InstPath     inst;
        logic [6:0]  opcode;
        logic [4:0]  rd;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
        logic [31:0] imm_i;
        logic [31:0] imm_s;
        logic [31:0] imm_b;
        logic [31:0] imm_u;
        logic [31:0] imm_j;
        TubeTypePath tube;
        CoreFuType   fu_type;
        CoreAluOp    alu_op;
        CoreBranchOp branch_op;
        CoreLsuOp    lsu_op;
        logic [1:0]  mem_size;
        logic        mem_signed;
        CoreMulDivOp muldiv_op;
        CoreCsrOp    csr_op;
        CoreSystemOp system_op;
        logic [11:0] csr_addr;
        logic [4:0]  csr_zimm;
        logic        csr_imm;
        logic        writes_rd;
        logic        has_rd;
        logic        is_load;
        logic        is_store;
        logic        is_branch;
        logic        is_jump;
        logic        is_jal;
        logic        is_jalr;
        logic        is_csr;
        logic        is_system;
        logic        is_fence;
        logic        is_trap;
        logic        is_ecall;
        logic        is_ebreak;
        logic        is_mret;
        logic        is_muldiv;
        logic        is_serial;
        logic        illegal;
        logic        exception;
        logic [31:0] exception_cause;
        logic        pred_taken;
        PcPath       pred_target;
    } CoreDecodeUop;

    typedef struct packed {
        logic        valid;
        CoreDecodeUop uop;
        RobIndexPath rob_idx;
        PhyRegNumPath prs1;
        PhyRegNumPath prs2;
        PhyRegNumPath prd;
        PhyRegNumPath old_prd;
        logic        alloc_prd;
        logic        src1_ready;
        logic        src2_ready;
    } CoreRenamedUop;

    typedef struct packed {
        logic        valid;
        logic        done;
        RobIndexPath rob_idx;
        CoreDecodeUop uop;
        PhyRegNumPath prd;
        PhyRegNumPath old_prd;
        logic        alloc_prd;
        DataPath     result;
        logic        exception;
        logic [31:0] exception_cause;
        logic        branch_miss;
        PcPath       redirect_pc;
        logic        csr_write;
        logic [11:0] csr_addr;
        DataPath     csr_wdata;
    } CoreRobEntry;
endpackage : CoreTypesPkg
