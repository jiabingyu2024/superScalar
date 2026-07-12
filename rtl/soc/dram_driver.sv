`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 11:42:01 AM
// Design Name: 
// Module Name: dram_driver
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module dram_driver(
    input  logic         clk				,

    input  logic [17:0]  perip_addr			,
    input  logic [31:0]  perip_wdata		,
	input  logic [3:0]	 perip_mask			,
    input  logic         dram_ena           ,
    input  logic         dram_wen           ,
    output logic [31:0]  perip_rdata		
);
    logic [15:0] dram_addr;
    logic [ 1:0] offset;
    logic [ 1:0] offset_d1;
    logic [ 1:0] offset_d2;
    logic         read_enable_d1;
    logic [31:0] dram_data, dram_rdata_raw, dout;
    logic [ 3:0] dram_we;

    assign dram_addr = perip_addr[17:2];
    assign offset = perip_addr[1:0];
    assign perip_rdata = dout;

    DRAM_0 Mem_DRAM (
        .addra      (dram_addr),
        .clka       (clk),
        .dina       (dram_data),
        .ena        (dram_ena),
        .regcea     (read_enable_d1),
        .wea        (dram_we),
        .douta      (dram_rdata_raw)
    );

    always_ff @(posedge clk) begin
        read_enable_d1 <= dram_ena && !dram_wen;
        if (dram_ena && !dram_wen) begin
            offset_d1 <= offset;
        end
        offset_d2 <= offset_d1;
    end

    always_comb begin
        dout = dram_rdata_raw >> {offset_d2, 3'b000};
    end

    always_comb begin
        // Core provides raw store data/mask. The SoC boundary owns byte-lane
        // alignment according to the low address bits.
        dram_data = perip_wdata << {offset, 3'b000};
        dram_we   = dram_wen ? (perip_mask << offset) : 4'b0000;
    end
endmodule
