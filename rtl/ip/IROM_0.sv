`timescale 1ns / 1ps

/**
 * @module IROM
 * @description 32-bit instruction ROM, depth 16384 words (64 KiB).
 *              Single read port replacement for the Vivado blk_mem_gen
 *              Single_Port_ROM used by the five-stage core.
 */
module IROM_0 #(
    parameter int unsigned ADDR_WIDTH = 14,
    parameter int unsigned DATA_WIDTH = 32,
    parameter string INIT_FILE = ""
) (
    input  logic [ADDR_WIDTH-1:0] addra,
    input  logic                  clka,
    input  logic                  ena,
    output logic [DATA_WIDTH-1:0] douta
);
    localparam int unsigned DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] addra_q;

    initial begin
        string runtime_init_file;

        if ($value$plusargs("irom_hex=%s", runtime_init_file)) begin
            $readmemh(runtime_init_file, mem);
        end else if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_ff @(posedge clka) begin
        if (ena) begin
            addra_q <= addra;
        end
    end

    assign douta = mem[addra_q];

endmodule
