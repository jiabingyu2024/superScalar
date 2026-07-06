import BasicTypes::*;
import PipelineTypes::*;
import IssueTypes::*;

module IssueStage(
    DispatchStageIF.IssueStage prev,
    IssueStageIF.IssueStage self,
    CtrlIF.IssueStage ctrl,
    IssueQueueIF.IssueStage issueQueue,
    PayloadIF.IssueStage payload
);
    task automatic fill_next_stage(
        input int slot,
        input IssuePopResPath popRes
    );
        logic issueFire;

        issueFire = popRes.done;
        payload.PayloadPopReq[slot].valid = issueFire;
        payload.PayloadPopReq[slot].payloadIndex = popRes.entry.payloadIndex;

        self.nextStage[slot] = '0;
        self.nextStage[slot].valid = issueFire &&
                                     payload.PayloadPopRes[slot].valid &&
                                     !ctrl.isPipe.flush;
        self.nextStage[slot].pc = payload.PayloadPopRes[slot].entry.pc;
        self.nextStage[slot].predInfo = payload.PayloadPopRes[slot].entry.predInfo;
        self.nextStage[slot].csrAddr = payload.PayloadPopRes[slot].entry.csrAddr;
        self.nextStage[slot].SubType = payload.PayloadPopRes[slot].entry.SubType;
        self.nextStage[slot].opTypeA = payload.PayloadPopRes[slot].entry.opTypeA;
        self.nextStage[slot].opTypeB = payload.PayloadPopRes[slot].entry.opTypeB;
        self.nextStage[slot].imm = payload.PayloadPopRes[slot].entry.imm;
        self.nextStage[slot].tubeType = popRes.entry.tubeType;
        self.nextStage[slot].srcA = popRes.entry.srcA;
        self.nextStage[slot].srcB = popRes.entry.srcB;
        self.nextStage[slot].dst = popRes.entry.dst;
        self.nextStage[slot].writeDst = popRes.entry.writeDst;
        self.nextStage[slot].robIndex = popRes.entry.robIndex;
        self.nextStage[slot].storeBufferIndexValid =
            payload.PayloadPopRes[slot].entry.storeBufferIndexValid;
        self.nextStage[slot].storeBufferIndex =
            payload.PayloadPopRes[slot].entry.storeBufferIndex;
    endtask

    always_comb begin
        logic popEnable;

        popEnable = !ctrl.isPipe.stall && !ctrl.isPipe.flush;
        ctrl.isStageEmpty = 1'b1;
        ctrl.isStallReq = 1'b0;

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            issueQueue.IntIssuePopReq[i].valid = popEnable;
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            issueQueue.MemIssuePopReq[i].valid = popEnable;
        end
        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            issueQueue.MulIssuePopReq[i].valid = popEnable;
        end

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            payload.PayloadPopReq[i] = '0;
            self.nextStage[i] = '0;
        end

        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            fill_next_stage(i, issueQueue.IntIssuePopRes[i]);
        end
        for (int i = 0; i < MEM_ISSUE_WIDTH; i++) begin
            fill_next_stage(INT_ISSUE_WIDTH + i, issueQueue.MemIssuePopRes[i]);
        end
        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            fill_next_stage(INT_ISSUE_WIDTH + MEM_ISSUE_WIDTH + i,
                            issueQueue.MulIssuePopRes[i]);
        end

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            ctrl.isStageEmpty &= !self.nextStage[i].valid;
        end
    end
endmodule
