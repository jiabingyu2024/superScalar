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
        logic        writes_rd;
        logic        is_load;
        logic        is_store;
        logic        is_branch;
        logic        is_jal;
        logic        is_jalr;
        logic        is_system;
        logic        illegal;
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
        CoreDecodeUop uop;
        PhyRegNumPath prd;
        PhyRegNumPath old_prd;
        logic        alloc_prd;
        DataPath     result;
        logic        exception;
        logic [31:0] exception_cause;
        logic        branch_miss;
        PcPath       redirect_pc;
    } CoreRobEntry;
endpackage : CoreTypesPkg
