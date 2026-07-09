`timescale 1ns / 1ps

/**
 * @module DRAM
 * @description 32-bit data RAM, depth 65536 words.
 *              Port names match the generated BRAM IP used by the FPGA build.
 *              Address alignment and byte lane shifting are handled by
 *              `dram_driver`, so `addra` is already a word address.
 */
module DRAM_0 #(
    parameter int unsigned ADDR_WIDTH = 16,
    parameter int unsigned DATA_WIDTH = 32,
    parameter string INIT_FILE = ""
) (
    input  logic [ADDR_WIDTH-1:0]   addra,
    input  logic                    clka,
    input  logic [DATA_WIDTH-1:0]   dina,
    input  logic                    ena,
    input  logic [DATA_WIDTH/8-1:0] wea,
    output logic [DATA_WIDTH-1:0]   douta
);
    localparam int unsigned BYTE_COUNT = DATA_WIDTH / 8;
    localparam int unsigned DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] addr_q;

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_ff @(posedge clka) begin
        if (ena) begin
            addr_q <= addra;
            for (int idx = 0; idx < BYTE_COUNT; idx++) begin
                if (wea[idx]) begin
                    mem[addra][idx*8 +: 8] <= dina[idx*8 +: 8];
                end
            end
        end
    end

    assign douta = mem[addr_q];

endmodule
