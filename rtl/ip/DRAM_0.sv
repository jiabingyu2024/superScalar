`timescale 1ns / 1ps

/**
 * @module DRAM
 * @description 32-bit data RAM, depth 65536 words.
 *              Port names match the generated BRAM IP used by the FPGA build.
 *              Single-port RAM with byte write enable and an independently
 *              enabled primitive-output register. ENA updates the memory
 *              output latch; REGCEA transfers that latch to DOUTA.
 *              Address alignment and byte lane shifting are handled by the SoC
 *              adapter, so `addra` is already a word address.
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
    input  logic                    regcea,
    input  logic [DATA_WIDTH/8-1:0] wea,
    output logic [DATA_WIDTH-1:0]   douta
);
    localparam int unsigned BYTE_COUNT = DATA_WIDTH / 8;
    localparam int unsigned DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] read_data_d1;

    initial begin
        string runtime_init_file;

        if ($value$plusargs("dram_hex=%s", runtime_init_file)) begin
            $readmemh(runtime_init_file, mem);
        end else if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_ff @(posedge clka) begin
        if (ena) begin
            // READ_FIRST: capture the pre-write word in the memory latch.
            read_data_d1 <= mem[addra];
            for (int idx = 0; idx < BYTE_COUNT; idx++) begin
                if (wea[idx]) begin
                    mem[addra][idx*8 +: 8] <= dina[idx*8 +: 8];
                end
            end
        end
        if (regcea) begin
            douta <= read_data_d1;
        end
    end

endmodule
