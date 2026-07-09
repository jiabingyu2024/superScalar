`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module InOrderDecodeStage(
    input FetchPacket ifPkt,

    output logic decodeValid,
    output logic [1:0] decodeCount,
    output Uop decodeUop[2]
);
    always_comb begin
        decodeValid = ifPkt.valid;
        decodeCount = '0;

        decodeUop[0] = '0;
        decodeUop[0].valid = ifPkt.valid;
        decodeUop[0].pc = ifPkt.pc;
        decodeUop[0].inst = ifPkt.inst0;
        decodeUop[0].predTaken = ifPkt.predTaken;
        decodeUop[0].predTarget = ifPkt.predTarget;

        decodeUop[1] = '0;
        decodeUop[1].valid = 1'b0;
        decodeUop[1].pc = ifPkt.pc + 32'd4;
        decodeUop[1].inst = ifPkt.inst1;
        decodeUop[1].predTaken = 1'b0;
        decodeUop[1].predTarget = ifPkt.pc + 32'd4;

        if (decodeUop[0].valid) decodeCount++;
        if (decodeUop[1].valid) decodeCount++;
    end
endmodule
