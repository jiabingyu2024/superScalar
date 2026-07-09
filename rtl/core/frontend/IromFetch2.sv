import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreIromFetch2 (
    input  logic clk,
    input  logic rst,
    input  logic req_valid_i,
    input  PcPath req_pc_i,
    output logic req_ready_o,
    IromAccessIF.frontend irom,
    output logic [FETCH_WIDTH-1:0] fetch_valid_o,
    output CoreFetchPacket [FETCH_WIDTH-1:0] fetch_pkt_o
);
    PcPath pc_q;
    logic valid_q;

    assign req_ready_o = !valid_q;

    always_comb begin
        irom.ena = req_valid_i && req_ready_o;
        irom.iromAddr = req_pc_i;
        for (int i = 0; i < FETCH_WIDTH; i = i + 1) begin
            fetch_valid_o[i] = valid_q;
            fetch_pkt_o[i].valid = valid_q;
            fetch_pkt_o[i].pc = pc_q + (i * 32'd4);
            fetch_pkt_o[i].inst = irom.inst[i];
            fetch_pkt_o[i].pred_taken = 1'b0;
            fetch_pkt_o[i].pred_target = pc_q + 32'd8;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q <= 1'b0;
            pc_q <= '0;
        end else begin
            valid_q <= req_valid_i && req_ready_o;
            if (req_valid_i && req_ready_o) begin
                pc_q <= req_pc_i;
            end
        end
    end
endmodule : CoreIromFetch2
