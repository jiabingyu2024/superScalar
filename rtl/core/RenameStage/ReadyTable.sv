import BasicTypes::*;
import ReadRegTypes::*;

module ReadyTable(ReadyTableIF.ReadyTable self);
    localparam int READY_READ_PORT_NUM = WAY_NUM * 2;

    logic [PHYREG_NUM-1:0] readyMask;

    always_comb begin
        for (int i = 0; i < READY_READ_PORT_NUM; i++) begin
            if (!self.readReq[i].valid || self.readReq[i].phyRegNum == '0) begin
                self.readReady[i] = 1'b1;
            end else begin
                self.readReady[i] = readyMask[self.readReq[i].phyRegNum];
            end
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < PHYREG_NUM; i++) begin
                readyMask[i] <= (i < LOGICREG_NUM);
            end
            readyMask[0] <= 1'b1;
        end else if (self.recoverReadyAll) begin
            readyMask <= '1;
            readyMask[0] <= 1'b1;
        end else begin
            for (int i = 0; i < WAY_NUM; i++) begin
                if (self.markBusy[i].valid && self.markBusy[i].phyRegNum != '0) begin
                    readyMask[self.markBusy[i].phyRegNum] <= 1'b0;
                end
            end
            for (int i = 0; i < BYPASS_WB_PORT_NUM; i++) begin
                if (self.markReady[i].valid && self.markReady[i].phyRegNum != '0) begin
                    readyMask[self.markReady[i].phyRegNum] <= 1'b1;
                end
            end
            readyMask[0] <= 1'b1;
        end
    end
endmodule
