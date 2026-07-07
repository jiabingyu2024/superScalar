import BasicTypes::*;
import RenameTypes::*;

module FreeList(FreeListIF.FreeList self);
    logic [PHYREG_NUM-1:0] freeMask;
    logic [PHYREG_NUM-1:0] chkptMask [CHECKPOINT_NUM];
    logic                  chkptValid[CHECKPOINT_NUM];

    integer i;
    integer j;
    integer count;

    always_comb begin
        logic [PHYREG_NUM-1:0] usedMask;
        usedMask = freeMask;
        usedMask[0] = 1'b0;

        for (i = 0; i < WAY_NUM; i++) begin
            self.freeListAlloc[i].allocValid = 1'b0;
            self.freeListAlloc[i].allocPhyRegNum = '0;
            if (self.freeListAllocReq[i]) begin
                for (j = 1; j < PHYREG_NUM; j++) begin
                    if (usedMask[j] && !self.freeListAlloc[i].allocValid) begin
                        self.freeListAlloc[i].allocValid = 1'b1;
                        self.freeListAlloc[i].allocPhyRegNum = PhyRegNumPath'(j);
                        usedMask[j] = 1'b0;
                    end
                end
            end
        end

        count = 0;
        for (i = 1; i < PHYREG_NUM; i++) begin
            if (freeMask[i]) count++;
        end
        self.freeListCount = FreeListCountPath'(count);

        self.freeListChkptCreate.ChkptIndexValid = 1'b0;
        self.freeListChkptCreate.ChkptCreateIndex = '0;
        for (i = 0; i < CHECKPOINT_NUM; i++) begin
            if (!chkptValid[i] && !self.freeListChkptCreate.ChkptIndexValid) begin
                self.freeListChkptCreate.ChkptIndexValid = 1'b1;
                self.freeListChkptCreate.ChkptCreateIndex = ChkptIndexPath'(i);
            end
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (i = 0; i < PHYREG_NUM; i++) begin
                freeMask[i] <= (i >= LOGICREG_NUM);
            end
            freeMask[0] <= 1'b0;
            for (i = 0; i < CHECKPOINT_NUM; i++) begin
                chkptValid[i] <= 1'b0;
            end
        end else if (self.freeListChkptRecover.ChkptRecoverEn) begin
            logic [PHYREG_NUM-1:0] recoverMask;
            recoverMask = chkptMask[self.freeListChkptRecover.ChkptRecoverIndex];
            if (self.freeListChkptRecover.RecoverFreeEn &&
                self.freeListChkptRecover.RecoverFreePhyRegNum != '0) begin
                recoverMask[self.freeListChkptRecover.RecoverFreePhyRegNum] = 1'b1;
            end
            for (i = 0; i < WAY_NUM; i++) begin
                if (self.freeListFree[i].freeReq && self.freeListFree[i].freePhyRegNum != '0) begin
                    recoverMask[self.freeListFree[i].freePhyRegNum] = 1'b1;
                end
            end
            recoverMask[0] = 1'b0;
            freeMask <= recoverMask;
            for (i = 0; i < CHECKPOINT_NUM; i++) begin
                chkptValid[i] <= 1'b0;
            end
        end else begin
            logic [PHYREG_NUM-1:0] nextMask;
            logic [PHYREG_NUM-1:0] chkptNextMask;
            nextMask = freeMask;
            chkptNextMask = freeMask;
            nextMask[0] = 1'b0;
            chkptNextMask[0] = 1'b0;

            for (i = 0; i < WAY_NUM; i++) begin
                if (self.freeListAllocReq[i] && self.freeListAlloc[i].allocValid) begin
                    nextMask[self.freeListAlloc[i].allocPhyRegNum] = 1'b0;
                    if (WayNumPath'(i) <= self.freeListChkptBranchWay) begin
                        chkptNextMask[self.freeListAlloc[i].allocPhyRegNum] = 1'b0;
                    end
                end
                if (self.freeListFree[i].freeReq && self.freeListFree[i].freePhyRegNum != '0) begin
                    nextMask[self.freeListFree[i].freePhyRegNum] = 1'b1;
                    chkptNextMask[self.freeListFree[i].freePhyRegNum] = 1'b1;
                end
            end
            nextMask[0] = 1'b0;
            chkptNextMask[0] = 1'b0;

            freeMask <= nextMask;

            for (i = 0; i < CHECKPOINT_NUM; i++) begin
                if (chkptValid[i]) begin
                    for (j = 0; j < WAY_NUM; j++) begin
                        if (self.freeListFree[j].freeReq && self.freeListFree[j].freePhyRegNum != '0) begin
                            chkptMask[i][self.freeListFree[j].freePhyRegNum] <= 1'b1;
                        end
                    end
                    chkptMask[i][0] <= 1'b0;
                end
            end

            if (self.freeListChkptCreateEn && self.freeListChkptCreate.ChkptIndexValid) begin
                chkptValid[self.freeListChkptCreate.ChkptCreateIndex] <= 1'b1;
                chkptMask[self.freeListChkptCreate.ChkptCreateIndex] <= chkptNextMask;
            end
            if (self.freeListChkptFree.ChkptFreeEn) begin
                chkptValid[self.freeListChkptFree.ChkptFreeIndex] <= 1'b0;
            end
        end
    end
endmodule
