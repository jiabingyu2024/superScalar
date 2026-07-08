package CoreTypes;
    localparam logic [31:0] RESET_PC = 32'h8000_0000;

    typedef enum logic [1:0] {
        MEM_SIZE_BYTE = 2'd0,
        MEM_SIZE_HALF = 2'd1,
        MEM_SIZE_WORD = 2'd2
    } mem_size_e;
endpackage
