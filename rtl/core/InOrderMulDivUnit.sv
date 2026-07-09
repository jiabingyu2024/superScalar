`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderMulDivUnit(
    input logic clk,
    input logic rst,

    input logic start,
    input MulDivInfo req,

    output logic done,
    output WbEntry wb
);
    typedef enum logic [1:0] {
        S_IDLE,
        S_MUL,
        S_DIV
    } State;

    State state;
    MulDivInfo activeReq;
    logic [5:0] iterCount;

    logic productNeg;
    logic quotNeg;
    logic remNeg;
    logic divByZero;
    logic overflow;

    logic [63:0] mulAcc;
    logic [63:0] mulMultiplicand;
    logic [31:0] mulMultiplier;

    DataPath origA;
    DataPath dividend;
    DataPath divisor;
    DataPath quotient;
    logic [32:0] remainder;

    function automatic DataPath abs32(input DataPath value);
        return value[31] ? DataPath'(~value + 32'd1) : value;
    endfunction

    function automatic logic is_divrem(input logic [2:0] funct3);
        return funct3[2];
    endfunction

    function automatic DataPath mul_result(
        input logic [2:0] funct3,
        input logic neg,
        input logic [63:0] magnitude
    );
        logic [63:0] product;

        product = neg ? (~magnitude + 64'd1) : magnitude;
        unique case (funct3)
            3'b001,
            3'b010,
            3'b011: mul_result = product[63:32];
            default: mul_result = product[31:0];
        endcase
    endfunction

    function automatic DataPath div_result(
        input logic [2:0] funct3,
        input logic byZero,
        input logic ovf,
        input logic qNeg,
        input logic rNeg,
        input DataPath originalA,
        input DataPath quotMag,
        input logic [31:0] remMag
    );
        DataPath quot;
        DataPath rem;

        quot = qNeg ? DataPath'(~quotMag + 32'd1) : quotMag;
        rem = rNeg ? DataPath'(~remMag + 32'd1) : remMag;

        if (byZero) begin
            div_result = funct3[1] ? originalA : 32'hffff_ffff;
        end else if (ovf) begin
            div_result = funct3[1] ? '0 : 32'h8000_0000;
        end else begin
            div_result = funct3[1] ? rem : quot;
        end
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            activeReq <= '0;
            iterCount <= '0;
            productNeg <= 1'b0;
            quotNeg <= 1'b0;
            remNeg <= 1'b0;
            divByZero <= 1'b0;
            overflow <= 1'b0;
            mulAcc <= '0;
            mulMultiplicand <= '0;
            mulMultiplier <= '0;
            origA <= '0;
            dividend <= '0;
            divisor <= '0;
            quotient <= '0;
            remainder <= '0;
            done <= 1'b0;
            wb <= '0;
        end else begin
            done <= 1'b0;
            wb <= '0;

            unique case (state)
                S_IDLE: begin
                    if (start && req.valid) begin
                        activeReq <= req;
                        iterCount <= '0;

                        if (is_divrem(req.funct3)) begin
                            logic signedOp;

                            signedOp = req.funct3 inside {3'b100, 3'b110};
                            state <= S_DIV;
                            divByZero <= (req.b == '0);
                            overflow <= signedOp &&
                                        (req.a == 32'h8000_0000) &&
                                        (req.b == 32'hffff_ffff);
                            quotNeg <= signedOp && (req.a[31] ^ req.b[31]);
                            remNeg <= signedOp && req.a[31];
                            origA <= req.a;
                            dividend <= signedOp ? abs32(req.a) : req.a;
                            divisor <= signedOp ? abs32(req.b) : req.b;
                            quotient <= '0;
                            remainder <= '0;
                        end else begin
                            logic signedA;
                            logic signedB;
                            DataPath absA;
                            DataPath absB;

                            signedA = req.funct3 inside {3'b001, 3'b010};
                            signedB = req.funct3 == 3'b001;
                            absA = signedA ? abs32(req.a) : req.a;
                            absB = signedB ? abs32(req.b) : req.b;

                            state <= S_MUL;
                            productNeg <= (signedA && req.a[31]) ^ (signedB && req.b[31]);
                            mulAcc <= '0;
                            mulMultiplicand <= {32'b0, absA};
                            mulMultiplier <= absB;
                        end
                    end
                end

                S_MUL: begin
                    logic [63:0] nextAcc;

                    nextAcc = mulAcc;
                    if (mulMultiplier[0]) begin
                        nextAcc = mulAcc + mulMultiplicand;
                    end

                    if (iterCount == 6'd31) begin
                        wb.valid <= activeReq.rd != 5'd0;
                        wb.rd <= activeReq.rd;
                        wb.data <= mul_result(activeReq.funct3, productNeg, nextAcc);
                        done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        mulAcc <= nextAcc;
                        mulMultiplicand <= mulMultiplicand << 1;
                        mulMultiplier <= mulMultiplier >> 1;
                        iterCount <= iterCount + 6'd1;
                    end
                end

                S_DIV: begin
                    if (divByZero || overflow) begin
                        wb.valid <= activeReq.rd != 5'd0;
                        wb.rd <= activeReq.rd;
                        wb.data <= div_result(activeReq.funct3, divByZero, overflow,
                                              quotNeg, remNeg, origA, quotient,
                                              remainder[31:0]);
                        done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        logic [32:0] trial;
                        logic [32:0] divisorExt;
                        DataPath nextDividend;
                        DataPath nextQuotient;
                        logic [32:0] nextRemainder;

                        trial = {remainder[31:0], dividend[31]};
                        divisorExt = {1'b0, divisor};
                        nextDividend = {dividend[30:0], 1'b0};

                        if (trial >= divisorExt) begin
                            nextRemainder = trial - divisorExt;
                            nextQuotient = {quotient[30:0], 1'b1};
                        end else begin
                            nextRemainder = trial;
                            nextQuotient = {quotient[30:0], 1'b0};
                        end

                        if (iterCount == 6'd31) begin
                            wb.valid <= activeReq.rd != 5'd0;
                            wb.rd <= activeReq.rd;
                            wb.data <= div_result(activeReq.funct3, divByZero, overflow,
                                                  quotNeg, remNeg, origA, nextQuotient,
                                                  nextRemainder[31:0]);
                            done <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            dividend <= nextDividend;
                            quotient <= nextQuotient;
                            remainder <= nextRemainder;
                            iterCount <= iterCount + 6'd1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
