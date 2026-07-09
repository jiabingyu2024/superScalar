`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderMulDivUnit (
    input  logic     clk,
    input  logic     rst,

    input  logic     start,
    input  MulDivInfo req,

    output logic     done,
    output WbEntry   wb
);
    logic        md_done;
    logic [31:0] md_result;
    logic [4:0]  rd_q;
    MulDivInfo   active_req_q;
    MulDivInfo   md_req;

    assign md_req = (start && req.valid) ? req : active_req_q;

    MulDivUnit u_muldiv_ip (
        .clk    (clk),
        .rst    (rst),
        .start  (start && req.valid),
        .funct3 (md_req.funct3),
        .lhs    (md_req.a),
        .rhs    (md_req.b),
        .busy   (),
        .done   (md_done),
        .result (md_result)
    );

    always_comb begin
        done = md_done;
        wb.valid = md_done && rd_q != 5'd0;
        wb.rd = rd_q;
        wb.data = md_result;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_q <= 5'd0;
            active_req_q <= '0;
        end else if (start && req.valid) begin
            rd_q <= req.rd;
            active_req_q <= req;
        end
    end
endmodule
