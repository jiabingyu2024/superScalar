`timescale 1ns / 1ps

/**
 * @module IROM
 * @description 32-bit instruction ROM, depth 16384 words (64 KiB).
 *              True dual-read-port replacement for the Vivado blk_mem_gen
 *              ROM used by the 2-way fetch core. Both ports have one-cycle
 *              address capture and asynchronous model readback from the
 *              captured address, matching the existing one-cycle IROM
 *              consumer contract.
 */
module IROM_0 #(
    parameter int unsigned ADDR_WIDTH = 14,
    parameter int unsigned DATA_WIDTH = 32,
    parameter string INIT_FILE = ""
) (
    input  logic [ADDR_WIDTH-1:0] addra,
    input  logic [ADDR_WIDTH-1:0] addrb,
    input  logic                  clka,
    input  logic                  clkb,
    input  logic                  ena,
    input  logic                  enb,
    output logic [DATA_WIDTH-1:0] douta,
    output logic [DATA_WIDTH-1:0] doutb
);
    localparam int unsigned DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] addra_q;
    logic [ADDR_WIDTH-1:0] addrb_q;

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

    always_ff @(posedge clkb) begin
        if (enb) begin
            addrb_q <= addrb;
        end
    end

    assign douta = mem[addra_q];
    assign doutb = mem[addrb_q];

endmodule
