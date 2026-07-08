`timescale 1ns / 1ps

module DramBramAdapter #(
    parameter int unsigned ADDR_WIDTH = 16
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,

    output logic        resp_valid,
    output logic [31:0] resp_rdata
);
    logic [ADDR_WIDTH-1:0] dram_addr;
    logic [31:0]           dram_wdata;
    logic [31:0]           dram_rdata_raw;
    logic [3:0]            dram_we;
    logic [1:0]            read_offset_q;

    assign req_ready = 1'b1;
    assign dram_addr = req_addr[ADDR_WIDTH+1:2];
    assign dram_wdata = req_wdata << {req_addr[1:0], 3'b000};
    assign dram_we = (req_valid && req_write) ? ((req_wstrb << req_addr[1:0]) & 4'hf) : 4'h0;

    DRAM_0 dram (
        .addra(dram_addr),
        .clka (clk),
        .dina (dram_wdata),
        .ena  (req_valid),
        .wea  (dram_we),
        .douta(dram_rdata_raw)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            resp_valid   <= 1'b0;
            read_offset_q <= 2'd0;
        end else begin
            resp_valid <= req_valid && !req_write;
            if (req_valid && !req_write) begin
                read_offset_q <= req_addr[1:0];
            end
        end
    end

    assign resp_rdata = dram_rdata_raw >> {read_offset_q, 3'b000};
endmodule
