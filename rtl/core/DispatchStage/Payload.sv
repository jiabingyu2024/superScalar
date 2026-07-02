import BasicTypes::*;
import IssueTypes::*;

module Payload(PayloadIF.Payload self);
    PayloadEntryPath entries [ISSUE_QUEUE_DEPTH];
    logic valid [ISSUE_QUEUE_DEPTH];

    integer i;

    always_comb begin
        for (i = 0; i < WAY_NUM; i++) begin
            self.PayloadPushRes[i].done = self.PayloadPushReq[i].valid;
            self.PayloadPopRes[i].valid = self.PayloadPopReq[i].valid &&
                                          valid[self.PayloadPopReq[i].payloadIndex];
            self.PayloadPopRes[i].entry = entries[self.PayloadPopReq[i].payloadIndex];
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                entries[i] <= '0;
                valid[i] <= 1'b0;
            end
        end else if (self.flush) begin
            for (i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                entries[i] <= '0;
                valid[i] <= 1'b0;
            end
        end else begin
            for (i = 0; i < WAY_NUM; i++) begin
                if (self.PayloadPopReq[i].valid) begin
                    valid[self.PayloadPopReq[i].payloadIndex] <= 1'b0;
                end
            end
            for (i = 0; i < WAY_NUM; i++) begin
                if (self.PayloadPushReq[i].valid) begin
                    entries[self.PayloadPushReq[i].payloadIndex] <= self.PayloadPushReq[i].entry;
                    valid[self.PayloadPushReq[i].payloadIndex] <= 1'b1;
                end
            end
        end
    end
endmodule
