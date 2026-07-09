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
    logic [ 1:0] offset_q;
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
        .wea        (dram_we),
        .douta      (dram_rdata_raw)
    );

    always_ff @(posedge clk) begin
        if (dram_ena) begin
            offset_q <= offset;
        end
    end

    always_comb begin
        dout = dram_rdata_raw >> {offset_q, 3'b000};
    end

    always_comb begin
        dram_data = perip_wdata << {offset, 3'b000};
        dram_we   = dram_wen ? (perip_mask << offset) : 4'b0000;
    end
endmodule
