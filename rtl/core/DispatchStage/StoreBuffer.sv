import BasicTypes::*;
import StoreBufferTypes::*;

module StoreBuffer(
    StoreBufferIF.StoreBuffer self,
    DramAccessIF.StoreBuffer dram
);
    StoreBufferPushReqPath entries [STORE_BUFFER_DEPTH];
    logic valid [STORE_BUFFER_DEPTH];
    StoreBufferIndexPath head;
    StoreBufferIndexPath tail;
    logic [STORE_BUFFER_WIDTH:0] count;

    integer i;

    always_comb begin
        self.allocRdy = (count < STORE_BUFFER_DEPTH);
        self.allocIndex = tail;
        self.StoreBufferCommit = '0;
        self.StoreBufferCommitReady = 1'b0;
        dram.storeWriteEn = 1'b0;
        dram.storeWriteAddr = '0;
        dram.storeWriteData = '0;
        dram.storeWriteMask = '0;
        if (count != '0 && valid[head] && entries[head].valid) begin
            self.StoreBufferCommit.valid = 1'b1;
            self.StoreBufferCommit.index = head;
            self.StoreBufferCommit.addr = entries[head].addr;
            self.StoreBufferCommit.data = entries[head].data;
            self.StoreBufferCommit.wstrb = entries[head].wstrb;
        end

        if (self.StoreBufferCommitReq.valid &&
            self.StoreBufferCommit.valid &&
            self.StoreBufferCommitReq.index == head) begin
            dram.storeWriteEn = 1'b1;
            dram.storeWriteAddr = self.StoreBufferCommit.addr;
            dram.storeWriteData = self.StoreBufferCommit.data;
            dram.storeWriteMask = self.StoreBufferCommit.wstrb;
            self.StoreBufferCommitReady = dram.storeWriteReady;
        end

        self.StoreBufferMatchOut = '0;
        if (self.StoreBufferMatchIn.valid) begin
            logic [3:0] matchedMask;
            StoreBufferIndexPath idx;

            matchedMask = '0;
            for (i = 0; i < STORE_BUFFER_DEPTH; i++) begin
                idx = head + StoreBufferIndexPath'(i);
                if (i < count && valid[idx] && entries[idx].valid &&
                    entries[idx].addr[ADDR_WIDTH-1:2] == self.StoreBufferMatchIn.addr[ADDR_WIDTH-1:2]) begin
                    for (int b = 0; b < 4; b++) begin
                        if (entries[idx].wstrb[b] && self.StoreBufferMatchIn.rstrb[b]) begin
                            self.StoreBufferMatchOut.data[b*8 +: 8] = entries[idx].data[b*8 +: 8];
                            matchedMask[b] = 1'b1;
                        end
                    end
                end
            end
            if ((matchedMask & self.StoreBufferMatchIn.rstrb) == self.StoreBufferMatchIn.rstrb) begin
                self.StoreBufferMatchOut.hit = 1'b1;
            end else begin
                for (i = 0; i < STORE_BUFFER_DEPTH; i++) begin
                    idx = head + StoreBufferIndexPath'(i);
                    if (i < count && valid[idx] && entries[idx].valid &&
                        entries[idx].addr[ADDR_WIDTH-1:2] == self.StoreBufferMatchIn.addr[ADDR_WIDTH-1:2] &&
                        ((entries[idx].wstrb & self.StoreBufferMatchIn.rstrb) != '0)) begin
                        self.StoreBufferMatchOut.block = 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            for (i = 0; i < STORE_BUFFER_DEPTH; i++) begin
                entries[i] <= '0;
                valid[i] <= 1'b0;
            end
        end else if (self.flush) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            for (i = 0; i < STORE_BUFFER_DEPTH; i++) begin
                entries[i] <= '0;
                valid[i] <= 1'b0;
            end
        end else begin
            logic doAlloc;
            logic doHeadCommit;
            doAlloc = self.allocReq && self.allocRdy;
            doHeadCommit = self.StoreBufferCommitReady && count != '0;

            if (doAlloc) begin
                valid[tail] <= 1'b1;
                entries[tail] <= '0;
                tail <= tail + 1'b1;
            end
            if (self.StoreBufferPushReq.valid) begin
                entries[self.StoreBufferPushReq.index] <= self.StoreBufferPushReq;
                valid[self.StoreBufferPushReq.index] <= 1'b1;
            end
            if (doHeadCommit) begin
                valid[head] <= 1'b0;
                head <= head + 1'b1;
            end
            count <= count + doAlloc - doHeadCommit;
        end
    end
endmodule
