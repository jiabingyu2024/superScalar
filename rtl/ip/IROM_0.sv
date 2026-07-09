`timescale 1ns / 1ps

/**
 * @module IROM
 * @description 32-bit instruction ROM, depth 4096 words (16 KiB).
 *              Registers word address on the rising clock edge and reads by
 *              that registered address.
 *              Initialization uses `$readmemh` with a plain hex `.mem` file.
 */
module IROM_0 #(
    parameter int unsigned ADDR_WIDTH = 12,
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
    logic [ADDR_WIDTH-1:0] addr_q;

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    always_ff @(posedge clka) begin
        if (ena) begin
            addr_q <= addra;
        end
    end

    assign douta = mem[addr_q];

endmodule
