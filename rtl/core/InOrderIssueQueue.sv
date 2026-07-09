`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderIssueQueue #(
    parameter int DEPTH = 6
) (
    input logic clk,
    input logic rst,
    input logic flush,

    input logic enqueue,
    input logic [1:0] enqueueCount,
    input Uop enqueueUop[2],
    output logic canAccept,

    input logic issueAllow,
    output logic issueValid,
    output Uop issueUop[2]
);
    Uop queue[DEPTH];
    Uop nextQueue[DEPTH];
    logic [$clog2(DEPTH+1)-1:0] count;
    logic [$clog2(DEPTH+1)-1:0] nextCount;
    logic [1:0] popCount;
    logic issuePair;

    assign canAccept = (count <= DEPTH - 2);
    assign issueValid = (count != '0);
    assign issuePair = (count >= 2) && can_pair(queue[0].inst, queue[1].inst);
    assign popCount = issueAllow && issueValid ? (issuePair ? 2'd2 : 2'd1) : 2'd0;

    always_comb begin
        issueUop[0] = '0;
        issueUop[1] = '0;

        if (issueValid) begin
            issueUop[0] = queue[0];
            issueUop[0].valid = 1'b1;
        end

        if (issuePair) begin
            issueUop[1] = queue[1];
            issueUop[1].valid = 1'b1;
        end
    end

    always_comb begin
        nextCount = count;
        for (int i = 0; i < DEPTH; i++) begin
            nextQueue[i] = queue[i];
        end

        if (popCount != 0) begin
            for (int i = 0; i < DEPTH; i++) begin
                if (i + popCount < DEPTH) begin
                    nextQueue[i] = queue[i + popCount];
                end else begin
                    nextQueue[i] = '0;
                end
            end
            nextCount = count - popCount;
        end

        if (enqueue) begin
            for (int i = 0; i < 2; i++) begin
                if (i < enqueueCount) begin
                    nextQueue[nextCount + i] = enqueueUop[i];
                end
            end
            nextCount = nextCount + enqueueCount;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= '0;
            for (int i = 0; i < DEPTH; i++) queue[i] <= '0;
        end else if (flush) begin
            count <= '0;
            for (int i = 0; i < DEPTH; i++) queue[i] <= '0;
        end else begin
            count <= nextCount;
            for (int i = 0; i < DEPTH; i++) queue[i] <= nextQueue[i];
        end
    end
endmodule
