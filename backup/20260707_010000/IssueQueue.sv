import BasicTypes::*;
import IssueTypes::*;

module IssueQueue(IssueQueueIF.IssueQueue self);
    IssuePushReqPath intPushReq [WAY_NUM];
    IssuePushReqPath memPushReq [WAY_NUM];
    IssuePushReqPath mulPushReq [WAY_NUM];
    IssuePushResPath intPushRes [WAY_NUM];
    IssuePushResPath memPushRes [WAY_NUM];
    IssuePushResPath mulPushRes [WAY_NUM];

    IssuePopResPath intCandidate [INT_ISSUE_WIDTH];
    IssuePopResPath memCandidate [MEM_ISSUE_WIDTH];
    IssuePopResPath mulCandidate [MUL_ISSUE_WIDTH];

    IssuePopResPath candidates [ISSUE_WIDTH];
    IssuePopResPath issuedProducers [ISSUE_WIDTH];
    logic grant [ISSUE_WIDTH];
    logic intGrant [INT_ISSUE_WIDTH];
    logic memGrant [MEM_ISSUE_WIDTH];
    logic mulGrant [MUL_ISSUE_WIDTH];

    logic [31:0] ageCounter;

    function automatic logic is_int_tube(input TubeTypePath tubeType);
        return tubeType inside {TUBE_TYPE_ALU, TUBE_TYPE_BRC, TUBE_TYPE_SYS};
    endfunction

    function automatic logic has_same_cycle_raw(
        input IssueEntryPath consumer,
        input IssueEntryPath producer
    );
        has_same_cycle_raw = 1'b0;
        if (producer.writeDst && producer.dst != '0) begin
            if (consumer.srcA == producer.dst) begin
                has_same_cycle_raw = 1'b1;
            end
            if (!consumer.srcBIsImm && consumer.srcB == producer.dst) begin
                has_same_cycle_raw = 1'b1;
            end
        end
    endfunction

    IntIssueQueue intIssueQueue (
        .clk(self.clk),
        .rst(self.rst),
        .flush(self.IssueCtrl.flush),
        .pushReq(intPushReq),
        .pushRes(intPushRes),
        .popReq(self.IntIssuePopReq),
        .popCandidate(intCandidate),
        .popGrant(intGrant),
        .wakeup(self.IssueWakeup),
        .issuedProducers(issuedProducers),
        .freeCount(self.IntIssueFreeCount)
    );

    InOrderIssueQueue #(
        .DEPTH(MEM_ISSUE_QUEUE_DEPTH),
        .PAYLOAD_BASE(MEM_PAYLOAD_BASE)
    ) memIssueQueue (
        .clk(self.clk),
        .rst(self.rst),
        .flush(self.IssueCtrl.flush),
        .pushReq(memPushReq),
        .pushRes(memPushRes),
        .popReq(self.MemIssuePopReq),
        .popCandidate(memCandidate),
        .popGrant(memGrant),
        .wakeup(self.IssueWakeup),
        .issuedProducers(issuedProducers),
        .freeCount(self.MemIssueFreeCount)
    );

    InOrderIssueQueue #(
        .DEPTH(MUL_ISSUE_QUEUE_DEPTH),
        .PAYLOAD_BASE(MUL_PAYLOAD_BASE)
    ) mulIssueQueue (
        .clk(self.clk),
        .rst(self.rst),
        .flush(self.IssueCtrl.flush),
        .pushReq(mulPushReq),
        .pushRes(mulPushRes),
        .popReq(self.MulIssuePopReq),
        .popCandidate(mulCandidate),
        .popGrant(mulGrant),
        .wakeup(self.IssueWakeup),
        .issuedProducers(issuedProducers),
        .freeCount(self.MulIssueFreeCount)
    );

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            ageCounter <= '0;
        end else if (self.IssueCtrl.flush) begin
            ageCounter <= '0;
        end else begin
            int acceptedPushes;

            acceptedPushes = 0;
            for (int i = 0; i < WAY_NUM; i++) begin
                if (self.IssuePushReq[i].valid && self.IssuePushRes[i].done) begin
                    acceptedPushes++;
                end
            end
            ageCounter <= ageCounter + 32'(acceptedPushes);
        end
    end

    always_comb begin
        int pushOrder;

        pushOrder = 0;
        for (int i = 0; i < WAY_NUM; i++) begin
            IssuePushReqPath pushReqWithAge;

            intPushReq[i] = '0;
            memPushReq[i] = '0;
            mulPushReq[i] = '0;
            self.IssuePushRes[i] = '0;

            pushReqWithAge = self.IssuePushReq[i];
            pushReqWithAge.entry.age = ageCounter + 32'(pushOrder);

            if (self.IssuePushReq[i].valid) begin
                if (is_int_tube(self.IssuePushReq[i].entry.tubeType)) begin
                    intPushReq[i] = pushReqWithAge;
                    self.IssuePushRes[i] = intPushRes[i];
                end else if (self.IssuePushReq[i].entry.tubeType == TUBE_TYPE_MEM) begin
                    memPushReq[i] = pushReqWithAge;
                    self.IssuePushRes[i] = memPushRes[i];
                end else begin
                    mulPushReq[i] = pushReqWithAge;
                    self.IssuePushRes[i] = mulPushRes[i];
                end
                if (self.IssuePushRes[i].done) begin
                    pushOrder++;
                end
            end
        end

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            candidates[i] = '0;
            issuedProducers[i] = '0;
            grant[i] = 1'b0;
        end
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            candidates[i] = intCandidate[i];
            intGrant[i] = 1'b0;
            self.IntIssuePopRes[i] = intCandidate[i];
            self.IntIssuePopRes[i].done = 1'b0;
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            candidates[INT_ISSUE_WIDTH + i] = memCandidate[i];
            memGrant[i] = 1'b0;
            self.MemIssuePopRes[i] = memCandidate[i];
            self.MemIssuePopRes[i].done = 1'b0;
        end
        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            candidates[INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + i] = mulCandidate[i];
            mulGrant[i] = 1'b0;
            self.MulIssuePopRes[i] = mulCandidate[i];
            self.MulIssuePopRes[i].done = 1'b0;
        end

        for (int iter = 0; iter < ISSUE_WIDTH; iter++) begin
            int best;
            logic blocked;

            best = -1;
            for (int c = 0; c < ISSUE_WIDTH; c++) begin
                if (candidates[c].done && !grant[c]) begin
                    if (best < 0 ||
                        candidates[c].entry.age < candidates[best].entry.age) begin
                        best = c;
                    end
                end
            end

            if (best >= 0) begin
                blocked = 1'b0;
                for (int g = 0; g < ISSUE_WIDTH; g++) begin
                    if (grant[g] &&
                        has_same_cycle_raw(candidates[best].entry,
                                           candidates[g].entry)) begin
                        blocked = 1'b1;
                    end
                end
                candidates[best].done = 1'b0;
                if (!blocked) begin
                    grant[best] = 1'b1;
                end
            end
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            intGrant[i] = grant[i];
            if (grant[i]) begin
                self.IntIssuePopRes[i] = intCandidate[i];
                issuedProducers[i] = intCandidate[i];
            end
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            int idx;

            idx = INT_ISSUE_WIDTH + i;
            memGrant[i] = grant[idx];
            if (grant[idx]) begin
                self.MemIssuePopRes[i] = memCandidate[i];
                issuedProducers[idx] = memCandidate[i];
            end
        end
        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            int idx;

            idx = INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + i;
            mulGrant[i] = grant[idx];
            if (grant[idx]) begin
                self.MulIssuePopRes[i] = mulCandidate[i];
                issuedProducers[idx] = mulCandidate[i];
            end
        end
    end
endmodule

module IntIssueQueue(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  flush,
    input  IssuePushReqPath       pushReq[WAY_NUM],
    output IssuePushResPath       pushRes[WAY_NUM],
    input  IssuePopReqPath        popReq[INT_ISSUE_WIDTH],
    output IssuePopResPath        popCandidate[INT_ISSUE_WIDTH],
    input  logic                  popGrant[INT_ISSUE_WIDTH],
    input  IssueWakeupPath        wakeup[ISSUE_WAKEUP_PORT_NUM],
    input  IssuePopResPath        issuedProducers[ISSUE_WIDTH],
    output IssueIntFreeCountPath  freeCount
);
    IssueEntryPath entries [INT_ISSUE_QUEUE_DEPTH];
    logic valid [INT_ISSUE_QUEUE_DEPTH];

    function automatic logic ready_entry(input IssueEntryPath entry);
        return entry.srcARdy && (entry.srcBRdy || entry.srcBIsImm);
    endfunction

    function automatic logic wakeup_match(input PhyRegNumPath phyRegNum);
        wakeup_match = 1'b0;
        for (int w = 0; w < ISSUE_WAKEUP_PORT_NUM; w++) begin
            if (wakeup[w].valid &&
                wakeup[w].phyRegNum != '0 &&
                wakeup[w].phyRegNum == phyRegNum) begin
                wakeup_match = 1'b1;
            end
        end
    endfunction

    function automatic logic predict_wakeup_allowed(input IssueEntryPath entry);
        predict_wakeup_allowed =
            (entry.delay == ShiftType'(1)) ||
            (entry.tubeType == TUBE_TYPE_MEM && entry.delay == (ShiftType'(1) << 2)) ||
            (entry.tubeType == TUBE_TYPE_MUL && entry.delay == (ShiftType'(1) << 2));
    endfunction

    always_comb begin
        logic [INT_ISSUE_QUEUE_DEPTH-1:0] allocMask;
        logic [INT_ISSUE_QUEUE_DEPTH-1:0] selected;
        int freeCnt;

        allocMask = '0;
        selected = '0;
        freeCnt = 0;
        for (int i = 0; i < INT_ISSUE_QUEUE_DEPTH; i++) begin
            allocMask[i] = valid[i];
            if (!valid[i]) begin
                freeCnt++;
            end
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            pushRes[i] = '0;
            for (int j = 0; j < INT_ISSUE_QUEUE_DEPTH; j++) begin
                if (pushReq[i].valid && !allocMask[j] && !pushRes[i].done) begin
                    pushRes[i].done = 1'b1;
                    pushRes[i].payloadIndex = IssueIndexPath'(INT_PAYLOAD_BASE + j);
                    allocMask[j] = 1'b1;
                end
            end
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            int selectedIdx;

            selectedIdx = 0;
            popCandidate[i] = '0;
            for (int j = 0; j < INT_ISSUE_QUEUE_DEPTH; j++) begin
                if (popReq[i].valid && valid[j] && !selected[j] &&
                    ready_entry(entries[j])) begin
                    if (!popCandidate[i].done ||
                        entries[j].age < entries[selectedIdx].age) begin
                        popCandidate[i].done = 1'b1;
                        popCandidate[i].entry = entries[j];
                        selectedIdx = j;
                    end
                end
            end
            if (popCandidate[i].done) begin
                selected[selectedIdx] = 1'b1;
            end
        end

        freeCount = IssueIntFreeCountPath'(freeCnt);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < INT_ISSUE_QUEUE_DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else if (flush) begin
            for (int i = 0; i < INT_ISSUE_QUEUE_DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else begin
            for (int i = 0; i < INT_ISSUE_QUEUE_DEPTH; i++) begin
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

                    for (int p = 0; p < ISSUE_WIDTH; p++) begin
                        if (issuedProducers[p].done &&
                            issuedProducers[p].entry.writeDst &&
                            predict_wakeup_allowed(issuedProducers[p].entry)) begin
                            if (!entries[i].srcARdy &&
                                entries[i].srcA == issuedProducers[p].entry.dst) begin
                                entries[i].srcAMatched <= 1'b1;
                                entries[i].srcAShift <= issuedProducers[p].entry.delay;
                            end
                            if (!entries[i].srcBRdy &&
                                entries[i].srcB == issuedProducers[p].entry.dst) begin
                                entries[i].srcBMatched <= 1'b1;
                                entries[i].srcBShift <= issuedProducers[p].entry.delay;
                            end
                        end
                    end
                end
            end

            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (popReq[i].valid && popGrant[i] && popCandidate[i].done) begin
                    for (int j = 0; j < INT_ISSUE_QUEUE_DEPTH; j++) begin
                        if (valid[j] &&
                            entries[j].payloadIndex == popCandidate[i].entry.payloadIndex) begin
                            valid[j] <= 1'b0;
                        end
                    end
                end
            end

            for (int i = 0; i < WAY_NUM; i++) begin
                if (pushReq[i].valid && pushRes[i].done) begin
                    IssueEntryPath pushEntry;
                    int localIndex;

                    pushEntry = pushReq[i].entry;
                    pushEntry.payloadIndex = pushRes[i].payloadIndex;
                    localIndex = int'(pushRes[i].payloadIndex) - INT_PAYLOAD_BASE;
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
                    entries[localIndex] <= pushEntry;
                    valid[localIndex] <= 1'b1;
                end
            end
        end
    end
endmodule

module InOrderIssueQueue #(
    parameter int DEPTH = 4,
    parameter int PAYLOAD_BASE = 0
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  flush,
    input  IssuePushReqPath       pushReq[WAY_NUM],
    output IssuePushResPath       pushRes[WAY_NUM],
    input  IssuePopReqPath        popReq[1],
    output IssuePopResPath        popCandidate[1],
    input  logic                  popGrant[1],
    input  IssueWakeupPath        wakeup[ISSUE_WAKEUP_PORT_NUM],
    input  IssuePopResPath        issuedProducers[ISSUE_WIDTH],
    output logic [$clog2(DEPTH):0] freeCount
);
    localparam int QUEUE_WIDTH = $clog2(DEPTH);
    typedef logic [QUEUE_WIDTH-1:0] QueueIndexPath;

    IssueEntryPath entries [DEPTH];
    logic valid [DEPTH];
    QueueIndexPath head;
    QueueIndexPath tail;
    logic [QUEUE_WIDTH:0] count;

    function automatic logic ready_entry(input IssueEntryPath entry);
        return entry.srcARdy && (entry.srcBRdy || entry.srcBIsImm);
    endfunction

    function automatic logic wakeup_match(input PhyRegNumPath phyRegNum);
        wakeup_match = 1'b0;
        for (int w = 0; w < ISSUE_WAKEUP_PORT_NUM; w++) begin
            if (wakeup[w].valid &&
                wakeup[w].phyRegNum != '0 &&
                wakeup[w].phyRegNum == phyRegNum) begin
                wakeup_match = 1'b1;
            end
        end
    endfunction

    function automatic logic predict_wakeup_allowed(input IssueEntryPath entry);
        predict_wakeup_allowed =
            (entry.delay == ShiftType'(1)) ||
            (entry.tubeType == TUBE_TYPE_MEM && entry.delay == (ShiftType'(1) << 2)) ||
            (entry.tubeType == TUBE_TYPE_MUL && entry.delay == (ShiftType'(1) << 2));
    endfunction

    always_comb begin
        int pushSlots;

        pushSlots = 0;
        for (int i = 0; i < WAY_NUM; i++) begin
            pushRes[i] = '0;
            if (pushReq[i].valid && count + pushSlots < DEPTH) begin
                QueueIndexPath idx;

                idx = tail + QueueIndexPath'(pushSlots);
                pushRes[i].done = 1'b1;
                pushRes[i].payloadIndex = IssueIndexPath'(PAYLOAD_BASE + int'(idx));
                pushSlots++;
            end
        end

        popCandidate[0] = '0;
        if (popReq[0].valid && count != '0 && valid[head] &&
            ready_entry(entries[head])) begin
            popCandidate[0].done = 1'b1;
            popCandidate[0].entry = entries[head];
        end

        freeCount = DEPTH - count;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else if (flush) begin
            head <= '0;
            tail <= '0;
            count <= '0;
            for (int i = 0; i < DEPTH; i++) begin
                valid[i] <= 1'b0;
                entries[i] <= '0;
            end
        end else begin
            int pushCnt;
            int popCnt;

            pushCnt = 0;
            popCnt = (popReq[0].valid && popGrant[0] && popCandidate[0].done) ? 1 : 0;

            for (int i = 0; i < DEPTH; i++) begin
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

                    for (int p = 0; p < ISSUE_WIDTH; p++) begin
                        if (issuedProducers[p].done &&
                            issuedProducers[p].entry.writeDst &&
                            predict_wakeup_allowed(issuedProducers[p].entry)) begin
                            if (!entries[i].srcARdy &&
                                entries[i].srcA == issuedProducers[p].entry.dst) begin
                                entries[i].srcAMatched <= 1'b1;
                                entries[i].srcAShift <= issuedProducers[p].entry.delay;
                            end
                            if (!entries[i].srcBRdy &&
                                entries[i].srcB == issuedProducers[p].entry.dst) begin
                                entries[i].srcBMatched <= 1'b1;
                                entries[i].srcBShift <= issuedProducers[p].entry.delay;
                            end
                        end
                    end
                end
            end

            if (popCnt != 0) begin
                valid[head] <= 1'b0;
                head <= head + QueueIndexPath'(popCnt);
            end

            for (int i = 0; i < WAY_NUM; i++) begin
                if (pushReq[i].valid && pushRes[i].done) begin
                    IssueEntryPath pushEntry;
                    QueueIndexPath idx;

                    idx = tail + QueueIndexPath'(pushCnt);
                    pushEntry = pushReq[i].entry;
                    pushEntry.payloadIndex = pushRes[i].payloadIndex;
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
                    entries[idx] <= pushEntry;
                    valid[idx] <= 1'b1;
                    pushCnt++;
                end
            end

            tail <= tail + QueueIndexPath'(pushCnt);
            count <= count + pushCnt - popCnt;
        end
    end
endmodule
