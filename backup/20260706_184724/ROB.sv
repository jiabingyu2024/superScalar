import BasicTypes::*;
import ROBTypes::*;

module ROB(ROBIF.ROB self);
    RobEntryPath entries [ROB_DEPTH];
    RobIndexPath head;
    RobIndexPath tail;
    logic headPos;
    logic tailPos;
    logic [ROB_DEPTH_WIDTH:0] count;

    integer i;

    always_comb begin
        for (i = 0; i < WAY_NUM; i++) begin
            RobIndexPath idx;
            idx = tail + RobIndexPath'(i);
            self.RobPushRes[i].valid = (count + i < ROB_DEPTH);
            self.RobPushRes[i].robIndex = idx;
            self.RobPushRes[i].position = tailPos ^ (idx < tail);

            idx = head + RobIndexPath'(i);
            self.RobPopRes[i].valid = (count > i) && entries[idx].valid;
            self.RobPopRes[i].entry = entries[idx];
        end
        self.RobFreeCount = RobFreeCountPath'(ROB_DEPTH - count);
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            head <= '0;
            tail <= '0;
            headPos <= 1'b0;
            tailPos <= 1'b0;
            count <= '0;
            for (i = 0; i < ROB_DEPTH; i++) begin
                entries[i] <= '0;
            end
        end else if (self.RobFlush) begin
            head <= '0;
            tail <= '0;
            headPos <= 1'b0;
            tailPos <= 1'b0;
            count <= '0;
            for (i = 0; i < ROB_DEPTH; i++) begin
                entries[i] <= '0;
            end
        end else begin
            int pushCnt;
            int popCnt;
            pushCnt = 0;
            popCnt = 0;

            for (i = 0; i < WAY_NUM * 5; i++) begin
                if (self.RobDoneReq[i].valid &&
                    entries[self.RobDoneReq[i].robIndex].valid) begin
                    entries[self.RobDoneReq[i].robIndex].done <= 1'b1;
                    entries[self.RobDoneReq[i].robIndex].exception <= self.RobDoneReq[i].exception;
                    entries[self.RobDoneReq[i].robIndex].isSerial <= self.RobDoneReq[i].isSerial;
                    entries[self.RobDoneReq[i].robIndex].truePc <= self.RobDoneReq[i].trueTargetPc;
                    entries[self.RobDoneReq[i].robIndex].takenActual <= self.RobDoneReq[i].taken;
                    entries[self.RobDoneReq[i].robIndex].isMiss <=
                        entries[self.RobDoneReq[i].robIndex].isBranch &&
                        ((entries[self.RobDoneReq[i].robIndex].takenPred != self.RobDoneReq[i].taken) ||
                         (self.RobDoneReq[i].taken &&
                          entries[self.RobDoneReq[i].robIndex].predPc != self.RobDoneReq[i].trueTargetPc));
                end
            end

            for (i = 0; i < WAY_NUM; i++) begin
                if (self.RobPopReq[i].req && count > popCnt) begin
                    entries[head + RobIndexPath'(popCnt)].valid <= 1'b0;
                    popCnt++;
                end
            end

            for (i = 0; i < WAY_NUM; i++) begin
                if (self.RobPushReq[i].req && count - popCnt + pushCnt < ROB_DEPTH) begin
                    entries[tail + RobIndexPath'(pushCnt)] <= self.RobPushReq[i].entry;
                    entries[tail + RobIndexPath'(pushCnt)].valid <= 1'b1;
                    pushCnt++;
                end
            end

            {headPos, head} <= {headPos, head} + popCnt[ROB_DEPTH_WIDTH:0];
            {tailPos, tail} <= {tailPos, tail} + pushCnt[ROB_DEPTH_WIDTH:0];
            count <= count + pushCnt - popCnt;
        end
    end
endmodule
