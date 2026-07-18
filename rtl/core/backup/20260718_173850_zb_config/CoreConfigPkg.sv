package CoreConfigPkg;
    localparam int BYTE_WIDTH = 8;
    localparam int INST_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int PC_WIDTH   = 32;

    localparam int LOGIC_REG_NUM = 32;
    localparam int PHY_REG_NUM   = 64;

    localparam int FETCH_WIDTH   = 2;
    localparam int DECODE_WIDTH  = 2;
    localparam int RENAME_WIDTH  = 2;
    localparam int DISPATCH_WIDTH = 2;
    localparam int RETIRE_WIDTH  = 2;

    localparam int INT_ISSUE_WIDTH    = 2;
    localparam int MEM_ISSUE_WIDTH    = 1;
    localparam int MULDIV_ISSUE_WIDTH = 1;
    localparam int ISSUE_WIDTH = INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + MULDIV_ISSUE_WIDTH;

    localparam int ROB_DEPTH       = 32;
    localparam int INT_IQ_DEPTH    = 8;
    localparam int MEM_IQ_DEPTH    = 5;
    localparam int MULDIV_IQ_DEPTH = 4;
    localparam int STORE_BUF_DEPTH = 8;
    localparam int FETCH_BUF_DEPTH = 8;

    localparam int BTB_ENTRIES = 256;
    localparam int BHT_ENTRIES = 512;

    localparam int PC_STEP = FETCH_WIDTH * 4;
endpackage : CoreConfigPkg
