`timescale 1ns / 1ps

package BasicTypes;
    localparam BYTE_WIDTH = 8;
    localparam INST_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam PC_WIDTH   = 32;

    typedef logic [BYTE_WIDTH-1:0] BytePath;
    typedef logic [INST_WIDTH-1:0] InstPath;
    typedef logic [ADDR_WIDTH-1:0] AddrPath;
    typedef logic [DATA_WIDTH-1:0] DataPath;
    typedef logic [PC_WIDTH-1:0]   PcPath;

    localparam WAY_NUM = 2;
    localparam PC_STEP = WAY_NUM * 4;
endpackage
