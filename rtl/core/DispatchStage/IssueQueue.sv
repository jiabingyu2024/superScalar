import BasicTypes::*;
import IssueTypes::*;

module IssueQueue(IssueQueueIF.IssueQueue self);
    IssueEntryPath entries [ISSUE_QUEUE_DEPTH];
    logic valid [ISSUE_QUEUE_DEPTH];

    function automatic logic older_than(
        input IssueEntryPath a,
        input IssueEntryPath b
    );
        if (a.robIndexPosition != b.robIndexPosition) begin
            older_than = a.robIndexPosition < b.robIndexPosition;
        end else begin
            older_than = a.robIndex < b.robIndex;
        end
    endfunction

    function automatic logic wakeup_match(input PhyRegNumPath phyRegNum);
        wakeup_match = 1'b0;
        for (int w = 0; w < ISSUE_WAKEUP_PORT_NUM; w++) begin
            if (self.IssueWakeup[w].valid &&
                self.IssueWakeup[w].phyRegNum != '0 &&
                self.IssueWakeup[w].phyRegNum == phyRegNum) begin
                wakeup_match = 1'b1;
            end
        end
    endfunction

    always_comb begin
        logic [ISSUE_QUEUE_DEPTH-1:0] selected;
        logic [ISSUE_QUEUE_DEPTH-1:0] allocMask;
        logic memSelected;
        int freeCnt;
        selected = '0;
        memSelected = 1'b0;
        freeCnt = 0;
        for (int k = 0; k < ISSUE_QUEUE_DEPTH; k++) begin
            allocMask[k] = valid[k];
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            self.IssuePushRes[i].done = 1'b0;
            self.IssuePushRes[i].payloadIndex = '0;
            for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
                if (!allocMask[j] && !self.IssuePushRes[i].done) begin
                    self.IssuePushRes[i].done = 1'b1;
                    self.IssuePushRes[i].payloadIndex = IssueIndexPath'(j);
                    allocMask[j] = 1'b1;
                end
            end
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            self.IssuePopRes[i].done = 1'b0;
            self.IssuePopRes[i].entry = '0;
            for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
                if (valid[j] && !selected[j] && !entries[j].issued &&
                    entries[j].srcARdy && (entries[j].srcBRdy || entries[j].srcBIsImm) &&
                    !has_same_cycle_raw(entries[j], selected) &&
                    !(memSelected && entries[j].tubeType == TUBE_TYPE_MEM)) begin
                    if (!self.IssuePopRes[i].done ||
                        older_than(entries[j], self.IssuePopRes[i].entry)) begin
                        self.IssuePopRes[i].done = 1'b1;
                        self.IssuePopRes[i].entry = entries[j];
                    end
                end
            end
            if (self.IssuePopRes[i].done) begin
                selected[self.IssuePopRes[i].entry.payloadIndex] = 1'b1;
                if (self.IssuePopRes[i].entry.tubeType == TUBE_TYPE_MEM) begin
                    memSelected = 1'b1;
                end
            end
        end

        for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
            if (!valid[i]) freeCnt++;
        end
        self.IssueFreeCount = IssueFreeCountPath'(freeCnt);
    end

    function automatic logic has_same_cycle_raw(
        input IssueEntryPath candidate,
        input logic [ISSUE_QUEUE_DEPTH-1:0] selectedMask
    );
        has_same_cycle_raw = 1'b0;
        for (int s = 0; s < ISSUE_QUEUE_DEPTH; s++) begin
            if (selectedMask[s] && entries[s].writeDst && entries[s].dst != '0) begin
                if ((candidate.srcA == entries[s].dst) ||
                    (!candidate.srcBIsImm && candidate.srcB == entries[s].dst)) begin
                    has_same_cycle_raw = 1'b1;
                end
            end
        end
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else if (self.IssueCtrl.flush) begin
            for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else begin
            for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                if (valid[i]) begin
                    if (entries[i].srcAMatched && !entries[i].srcARdy) begin
                        if (entries[i].srcAShift != '0) begin
                            entries[i].srcAShift <= {1'b0, entries[i].srcAShift[SHIFT_WIDTH-1:1]};
                        end
                    end
                    if (entries[i].srcBMatched && !entries[i].srcBRdy) begin
                        if (entries[i].srcBShift != '0) begin
                            entries[i].srcBShift <= {1'b0, entries[i].srcBShift[SHIFT_WIDTH-1:1]};
                        end
                    end
                    if (!entries[i].srcARdy && wakeup_match(entries[i].srcA)) begin
                        entries[i].srcARdy <= 1'b1;
                        entries[i].srcAMatched <= 1'b0;
                        entries[i].srcAShift <= '0;
                    end
                    if (!entries[i].srcBRdy && wakeup_match(entries[i].srcB)) begin
                        entries[i].srcBRdy <= 1'b1;
                        entries[i].srcBMatched <= 1'b0;
                        entries[i].srcBShift <= '0;
                    end
                end
            end

            for (int i = 0; i < WAY_NUM; i++) begin
                if (self.IssuePushReq[i].valid && self.IssuePushRes[i].done) begin
                    IssueEntryPath pushEntry;

                    pushEntry = self.IssuePushReq[i].entry;
                    pushEntry.payloadIndex = self.IssuePushRes[i].payloadIndex;
                    if (!pushEntry.srcARdy && wakeup_match(pushEntry.srcA)) begin
                        pushEntry.srcARdy = 1'b1;
                        pushEntry.srcAMatched = 1'b0;
                        pushEntry.srcAShift = '0;
                    end
                    if (!pushEntry.srcBRdy && wakeup_match(pushEntry.srcB)) begin
                        pushEntry.srcBRdy = 1'b1;
                        pushEntry.srcBMatched = 1'b0;
                        pushEntry.srcBShift = '0;
                    end

                    entries[self.IssuePushRes[i].payloadIndex] <= pushEntry;
                    valid[self.IssuePushRes[i].payloadIndex] <= 1'b1;
                end
            end

            for (int i = 0; i < WAY_NUM; i++) begin
                if (self.IssuePopReq[i].valid && self.IssuePopRes[i].done) begin
                    for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
                        if (valid[j] && entries[j].payloadIndex == self.IssuePopRes[i].entry.payloadIndex) begin
                            entries[j].issued <= 1'b1;
                            valid[j] <= 1'b0;
                        end
                        if (valid[j] && self.IssuePopRes[i].entry.writeDst) begin
                            if (entries[j].srcA == self.IssuePopRes[i].entry.dst && !entries[j].srcARdy) begin
                                entries[j].srcAMatched <= 1'b1;
                                entries[j].srcAShift <= self.IssuePopRes[i].entry.delay;
                            end
                            if (entries[j].srcB == self.IssuePopRes[i].entry.dst && !entries[j].srcBRdy) begin
                                entries[j].srcBMatched <= 1'b1;
                                entries[j].srcBShift <= self.IssuePopRes[i].entry.delay;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
