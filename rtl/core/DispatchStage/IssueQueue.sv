import BasicTypes::*;
import IssueTypes::*;

module IssueQueue(IssueQueueIF.IssueQueue self);
    IssueEntryPath entries [ISSUE_QUEUE_DEPTH];
    logic [31:0] entryAge [ISSUE_QUEUE_DEPTH];
    logic [31:0] ageCounter;
    logic valid [ISSUE_QUEUE_DEPTH];

    function automatic logic older_index(input int a, input int b);
        older_index = entryAge[a] < entryAge[b];
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
        logic [ISSUE_QUEUE_DEPTH-1:0] memBlockedByOlder;
        logic memSelected;
        logic mulSelected;
        int freeCnt;
        selected = '0;
        memBlockedByOlder = '0;
        memSelected = 1'b0;
        mulSelected = 1'b0;
        freeCnt = 0;
        for (int k = 0; k < ISSUE_QUEUE_DEPTH; k++) begin
            allocMask[k] = valid[k];
        end

        for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
            if (valid[j] && !entries[j].issued &&
                entries[j].tubeType == TUBE_TYPE_MEM) begin
                for (int m = 0; m < ISSUE_QUEUE_DEPTH; m++) begin
                    if (valid[m] && !entries[m].issued &&
                        entries[m].tubeType == TUBE_TYPE_MEM &&
                        older_index(m, j)) begin
                        memBlockedByOlder[j] = 1'b1;
                    end
                end
            end
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
            int selectedIdx;

            selectedIdx = 0;
            self.IssuePopRes[i].done = 1'b0;
            self.IssuePopRes[i].entry = '0;
            for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
                if (valid[j] && !selected[j] && !entries[j].issued &&
                    entries[j].srcARdy && (entries[j].srcBRdy || entries[j].srcBIsImm) &&
                    !has_same_cycle_raw(entries[j], selected) &&
                    !memBlockedByOlder[j] &&
                    !(memSelected && entries[j].tubeType == TUBE_TYPE_MEM) &&
                    !(mulSelected && entries[j].tubeType == TUBE_TYPE_MUL) &&
                    !(i != 0 && entries[j].tubeType == TUBE_TYPE_MUL)) begin
                    if (!self.IssuePopRes[i].done ||
                        older_index(j, selectedIdx)) begin
                        self.IssuePopRes[i].done = 1'b1;
                        self.IssuePopRes[i].entry = entries[j];
                        selectedIdx = j;
                    end
                end
            end
            if (self.IssuePopRes[i].done) begin
                selected[self.IssuePopRes[i].entry.payloadIndex] = 1'b1;
                if (self.IssuePopRes[i].entry.tubeType == TUBE_TYPE_MEM) begin
                    memSelected = 1'b1;
                end
                if (self.IssuePopRes[i].entry.tubeType == TUBE_TYPE_MUL) begin
                    mulSelected = 1'b1;
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
                entryAge[i] <= '0;
            end
            ageCounter <= '0;
        end else if (self.IssueCtrl.flush) begin
            for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
                entryAge[i] <= '0;
            end
            ageCounter <= '0;
        end else begin
            int pushCnt;

            pushCnt = 0;
            for (int i = 0; i < ISSUE_QUEUE_DEPTH; i++) begin
                if (valid[i]) begin
                    if (entries[i].srcAMatched && !entries[i].srcARdy) begin
                        if (entries[i].srcAShift == ShiftType'(1)) begin
                            entries[i].srcARdy <= 1'b1;
                            entries[i].srcAMatched <= 1'b0;
                            entries[i].srcAShift <= '0;
                        end else if (entries[i].srcAShift != '0) begin
                            entries[i].srcAShift <= {1'b0, entries[i].srcAShift[SHIFT_WIDTH-1:1]};
                        end
                    end
                    if (entries[i].srcBMatched && !entries[i].srcBRdy) begin
                        if (entries[i].srcBShift == ShiftType'(1)) begin
                            entries[i].srcBRdy <= 1'b1;
                            entries[i].srcBMatched <= 1'b0;
                            entries[i].srcBShift <= '0;
                        end else if (entries[i].srcBShift != '0) begin
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
                    entryAge[self.IssuePushRes[i].payloadIndex] <= ageCounter + 32'(pushCnt);
                    valid[self.IssuePushRes[i].payloadIndex] <= 1'b1;
                    pushCnt++;
                end
            end
            ageCounter <= ageCounter + 32'(pushCnt);

            for (int i = 0; i < WAY_NUM; i++) begin
                if (self.IssuePopReq[i].valid && self.IssuePopRes[i].done) begin
                    for (int j = 0; j < ISSUE_QUEUE_DEPTH; j++) begin
                        if (valid[j] && entries[j].payloadIndex == self.IssuePopRes[i].entry.payloadIndex) begin
                            entries[j].issued <= 1'b1;
                            valid[j] <= 1'b0;
                        end
                        if (valid[j] && self.IssuePopRes[i].entry.writeDst) begin
                            if (entries[j].srcA == self.IssuePopRes[i].entry.dst && !entries[j].srcARdy) begin
                                if (self.IssuePopRes[i].entry.delay == ShiftType'(1)) begin
                                    entries[j].srcAMatched <= 1'b1;
                                    entries[j].srcAShift <= self.IssuePopRes[i].entry.delay;
                                end
                            end
                            if (entries[j].srcB == self.IssuePopRes[i].entry.dst && !entries[j].srcBRdy) begin
                                if (self.IssuePopRes[i].entry.delay == ShiftType'(1)) begin
                                    entries[j].srcBMatched <= 1'b1;
                                    entries[j].srcBShift <= self.IssuePopRes[i].entry.delay;
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
