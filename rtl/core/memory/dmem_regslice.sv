`timescale 1ns / 1ps
// Non-fall-through request/response register slice at the core/SoC boundary.
// External memory traffic is only used for write-through stores, misses and
// uncached accesses, so the extra cycle does not lengthen DCache hit latency.
module dmem_regslice (
    input  logic clk,
    input  logic rst,
    input  logic s_req_valid_i,
    output logic s_req_ready_o,
    input  logic s_req_write_i,
    input  logic [31:0] s_req_addr_i,
    input  logic [31:0] s_req_wdata_i,
    input  logic [3:0] s_req_wstrb_i,
    input  logic s_req_uncached_i,
    output logic s_resp_valid_o,
    output logic [31:0] s_resp_rdata_o,
    output logic m_req_valid_o,
    input  logic m_req_ready_i,
    output logic m_req_write_o,
    output logic [31:0] m_req_addr_o,
    output logic [31:0] m_req_wdata_o,
    output logic [3:0] m_req_wstrb_o,
    output logic m_req_uncached_o,
    input  logic m_resp_valid_i,
    input  logic [31:0] m_resp_rdata_i
);
    logic req_valid_q;
    logic req_write_q;
    logic [31:0] req_addr_q, req_wdata_q;
    logic [3:0] req_wstrb_q;
    logic req_uncached_q;
    logic resp_valid_q;
    logic [31:0] resp_rdata_q;

    assign s_req_ready_o = !req_valid_q;
    assign m_req_valid_o = req_valid_q;
    assign m_req_write_o = req_write_q;
    assign m_req_addr_o = req_addr_q;
    assign m_req_wdata_o = req_wdata_q;
    assign m_req_wstrb_o = req_wstrb_q;
    assign m_req_uncached_o = req_uncached_q;
    assign s_resp_valid_o = resp_valid_q;
    assign s_resp_rdata_o = resp_rdata_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            req_valid_q <= 1'b0;
            req_write_q <= 1'b0;
            req_addr_q <= '0;
            req_wdata_q <= '0;
            req_wstrb_q <= '0;
            req_uncached_q <= 1'b0;
            resp_valid_q <= 1'b0;
            resp_rdata_q <= '0;
        end else begin
            resp_valid_q <= m_resp_valid_i;
            if (m_resp_valid_i) resp_rdata_q <= m_resp_rdata_i;

            if (!req_valid_q) begin
                if (s_req_valid_i) begin
                    req_valid_q <= 1'b1;
                    req_write_q <= s_req_write_i;
                    req_addr_q <= s_req_addr_i;
                    req_wdata_q <= s_req_wdata_i;
                    req_wstrb_q <= s_req_wstrb_i;
                    req_uncached_q <= s_req_uncached_i;
                end
            end else if (m_req_ready_i) begin
                req_valid_q <= 1'b0;
            end
        end
    end
endmodule
