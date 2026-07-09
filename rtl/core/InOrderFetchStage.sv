`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderFetchStage(
    input logic clk,
    input logic rst,

    IromAccessIF.core iromAccess,

    input logic run,
    input logic stall,
    input logic advance,
    input logic consume,
    input logic flush,
    input PcPath flushPc,

    input logic bpuTrainValid,
    input PcPath bpuTrainPc,
    input logic bpuTrainTaken,
    input PcPath bpuTrainTarget,

    output FetchPacket ifPkt
);
    localparam int BPU_ENTRIES = 64;
    localparam int BPU_INDEX_WIDTH = 6;
    localparam int BPU_TAG_WIDTH = 32 - BPU_INDEX_WIDTH - 2;

    PcPath reqPc;
    PcPath reqPcPipe0;
    logic reqValidPipe0;
    logic reqPredTakenPipe0;
    PcPath reqPredTargetPipe0;

    logic bpuValid[BPU_ENTRIES];
    logic [1:0] bpuCounter[BPU_ENTRIES];
    logic [BPU_TAG_WIDTH-1:0] bpuTag[BPU_ENTRIES];
    PcPath bpuTarget[BPU_ENTRIES];

    logic bpuReqTaken;
    PcPath bpuReqTarget;
    logic [BPU_INDEX_WIDTH-1:0] trainIndex;

    function automatic logic [BPU_INDEX_WIDTH-1:0] bpu_index(input PcPath pc);
        return pc[BPU_INDEX_WIDTH+1:2];
    endfunction

    function automatic logic [BPU_TAG_WIDTH-1:0] bpu_tag(input PcPath pc);
        return pc[31:BPU_INDEX_WIDTH+2];
    endfunction

    assign iromAccess.ena = run && !stall;
    assign iromAccess.iromAddr = reqPc;

    assign bpuReqTaken = bpuValid[bpu_index(reqPc)] &&
                         bpuTag[bpu_index(reqPc)] == bpu_tag(reqPc) &&
                         bpuCounter[bpu_index(reqPc)][1];
    assign bpuReqTarget = bpuReqTaken ? bpuTarget[bpu_index(reqPc)] : (reqPc + 32'd8);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reqPc <= RESET_PC;
            reqPcPipe0 <= '0;
            reqValidPipe0 <= 1'b0;
            reqPredTakenPipe0 <= 1'b0;
            reqPredTargetPipe0 <= '0;
            ifPkt <= '0;
            for (int i = 0; i < BPU_ENTRIES; i++) begin
                bpuValid[i] <= 1'b0;
                bpuCounter[i] <= 2'b01;
                bpuTag[i] <= '0;
                bpuTarget[i] <= '0;
            end
        end else begin
            if (bpuTrainValid) begin
                trainIndex = bpu_index(bpuTrainPc);
                bpuValid[trainIndex] <= 1'b1;
                bpuTag[trainIndex] <= bpu_tag(bpuTrainPc);
                bpuTarget[trainIndex] <= bpuTrainTarget;
                if (bpuTrainTaken) begin
                    if (bpuCounter[trainIndex] != 2'b11) begin
                        bpuCounter[trainIndex] <= bpuCounter[trainIndex] + 2'd1;
                    end
                end else if (bpuCounter[trainIndex] != 2'b00) begin
                    bpuCounter[trainIndex] <= bpuCounter[trainIndex] - 2'd1;
                end
            end

            if (flush) begin
                reqPc <= flushPc;
                reqPcPipe0 <= '0;
                reqValidPipe0 <= 1'b0;
                reqPredTakenPipe0 <= 1'b0;
                reqPredTargetPipe0 <= '0;
                ifPkt <= '0;
            end else if (advance) begin
                ifPkt.valid <= reqValidPipe0;
                ifPkt.pc <= reqPcPipe0;
                ifPkt.inst0 <= iromAccess.inst[0];
                ifPkt.inst1 <= iromAccess.inst[1];
                ifPkt.predTaken <= reqPredTakenPipe0;
                ifPkt.predTarget <= reqPredTargetPipe0;

                reqPcPipe0 <= reqPc;
                reqValidPipe0 <= 1'b1;
                reqPredTakenPipe0 <= bpuReqTaken;
                reqPredTargetPipe0 <= bpuReqTarget;
                reqPc <= bpuReqTarget;
            end else begin
                if (consume) begin
                    ifPkt.valid <= 1'b0;
                end
            end
        end
    end
endmodule
