//------------------------------------------------------------------------------
// BasicTypes.sv
// 作用：定义全核共享的基础宽度、通用索引和指令分类枚举。
// 微架构定位：这是所有 stage/type/interface 的最底层依赖，只放不会归属到
// 某个具体硬件队列或流水级的全局概念，例如 PC、物理寄存器号、ROB 索引、
// checkpoint 索引、执行管线类型和操作数来源。具体 ROB entry、恢复请求、
// StoreBuffer 协议不放在这里，避免基础类型层被上层模块污染。
//------------------------------------------------------------------------------

// 规定一些基本的类型，供整个CPU使用

package BasicTypes;

    
    localparam TRUE  = 1'b1;
    localparam FALSE = 1'b0;

    localparam BYTE_WIDTH = 8; 
    localparam INST_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;

    typedef logic [BYTE_WIDTH-1:0] BytePath;
    typedef logic [INST_WIDTH-1:0] InstPath;
    typedef logic [ADDR_WIDTH-1:0] AddrPath;
    typedef logic [DATA_WIDTH-1:0] DataPath;

    //PC
    localparam PC_WIDTH = 32;
    typedef logic [PC_WIDTH-1:0] PcPath;

    //逻辑寄存器和物理寄存器的数量

    localparam LOGICREG_NUM = 32;
    localparam PHYREG_NUM   = 64;

    typedef logic [$clog2(LOGICREG_NUM)-1:0] LgcRegNumPath;
    typedef logic [$clog2(PHYREG_NUM)-1:0]   PhyRegNumPath;

    // 同时取指的指令数量
    localparam WAY_NUM  =  2;
    typedef logic [$clog2(WAY_NUM)-1:0] WayNumPath;
    localparam PC_STEP = WAY_NUM * 4; // 每次取指的PC递增量

    // Backend global indexes. Keep these here so pipeline/recovery/rename
    // types do not depend on one concrete module package.
    localparam ROB_DEPTH = 16;
    localparam ROB_DEPTH_WIDTH = $clog2(ROB_DEPTH);
    typedef logic [ROB_DEPTH_WIDTH-1:0] RobIndexPath;

    localparam CHECKPOINT_NUM = 8;
    localparam CHECKPOINT_WIDTH = $clog2(CHECKPOINT_NUM);
    typedef logic [CHECKPOINT_WIDTH-1:0] ChkptIndexPath;


    // 操作数来源于寄存器堆的索引
    typedef struct packed {
        PhyRegNumPath phyRegNumA;
        PhyRegNumPath phyRegNumB;
    } OpSrcPath;

    typedef struct packed {
        PhyRegNumPath phyRegNumA;
        PhyRegNumPath phyRegNumB;
    } DstSrcPath;


    
    //给PreFetch的分支预测结果
    typedef struct packed {
        logic btbhit;
        logic taken;
        PcPath target;
    } BpuPrdPath;



    // used in Decode



    typedef struct packed {
        logic [11:0] csrAddr;
        logic       valid;
    } CsrAddrPath;

    typedef enum logic [2:0]
    {
        TUBE_TYPE_ALU = 3'b000,
        TUBE_TYPE_MEM = 3'b001,
        TUBE_TYPE_BRC = 3'b010,
        TUBE_TYPE_MUL = 3'b011,
        TUBE_TYPE_SYS = 3'b100
    } TubeTypePath;
    
    typedef enum logic [3:0]
    {
        ALU_SUBTYPE_ADD  = 4'b0000,
        ALU_SUBTYPE_SUB  = 4'b0001,
        ALU_SUBTYPE_SLL  = 4'b0010,
        ALU_SUBTYPE_SRL  = 4'b0011,
        ALU_SUBTYPE_SRA  = 4'b0100,
        ALU_SUBTYPE_XOR  = 4'b0101,
        ALU_SUBTYPE_OR   = 4'b0110,
        ALU_SUBTYPE_AND  = 4'b0111,
        ALU_SUBTYPE_SLT  = 4'b1000,
        ALU_SUBTYPE_SLTU = 4'b1001
    } AluSubType;

    typedef enum logic [3:0]
    {
        MEM_SUBTYPE_LB  = 4'b0000,
        MEM_SUBTYPE_LH  = 4'b0001,
        MEM_SUBTYPE_LW  = 4'b0010,
        MEM_SUBTYPE_LBU = 4'b0011,
        MEM_SUBTYPE_LHU = 4'b0100,
        MEM_SUBTYPE_SB  = 4'b0101,
        MEM_SUBTYPE_SH  = 4'b0110,
        MEM_SUBTYPE_SW  = 4'b0111
    } MemSubType;

    typedef enum logic [3:0]
    {
        BRC_SUBTYPE_BEQ  = 4'b0000,
        BRC_SUBTYPE_BNE  = 4'b0001,
        BRC_SUBTYPE_BLT  = 4'b0010,
        BRC_SUBTYPE_BGE  = 4'b0011,
        BRC_SUBTYPE_BLTU = 4'b0100,
        BRC_SUBTYPE_BGEU = 4'b0101,
        BRC_SUBTYPE_JAL  = 4'b0110,
        BRC_SUBTYPE_JALR = 4'b0111
    } BrcSubType;

    typedef enum logic [3:0]
    {
        MUL_SUBTYPE_MUL   = 4'b0000,
        MUL_SUBTYPE_MULH  = 4'b0001,
        MUL_SUBTYPE_MULHSU= 4'b0010,
        MUL_SUBTYPE_MULHU = 4'b0011,
        MUL_SUBTYPE_DIV   = 4'b0100,
        MUL_SUBTYPE_DIVU  = 4'b0101,
        MUL_SUBTYPE_REM   = 4'b0110,
        MUL_SUBTYPE_REMU  = 4'b0111
    } MulSubType;

    typedef enum logic [3:0]
    {
        SYS_SUBTYPE_ECALL = 4'b0000,
        SYS_SUBTYPE_EBREAK = 4'b0001,
        SYS_SUBTYPE_CSRRW  = 4'b0010,
        SYS_SUBTYPE_CSRRS  = 4'b0011,
        SYS_SUBTYPE_CSRRC  = 4'b0100,
        SYS_SUBTYPE_CSRRWI = 4'b0101,
        SYS_SUBTYPE_CSRRSI = 4'b0110,
        SYS_SUBTYPE_CSRRCI = 4'b0111
    } SysSubType;

    typedef union packed {
        AluSubType aluSubType;
        MemSubType memSubType;
        BrcSubType brcSubType;
        MulSubType mulSubType;
        SysSubType sysSubType;
    } SubTypePath;

    typedef enum logic [1:0]
    {
        OP_TYPE_REG = 2'b00,
        OP_TYPE_IMM = 2'b01,
        OP_TYPE_PC  = 2'b10,
        OP_TYPE_NONE= 2'b11
    } OperandTypePath;

endpackage 
