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
    always_comb begin
        ctrl.isStageEmpty = 1'b1;
        ctrl.isStallReq = 1'b0;

        for (int i = 0; i < WAY_NUM; i++) begin
            issueQueue.IssuePopReq[i].valid = !ctrl.isPipe.stall && !ctrl.isPipe.flush;
            payload.PayloadPopReq[i].valid = issueQueue.IssuePopRes[i].done;
            payload.PayloadPopReq[i].payloadIndex = issueQueue.IssuePopRes[i].entry.payloadIndex;

            self.nextStage[i] = '0;
            self.nextStage[i].valid = issueQueue.IssuePopRes[i].done &&
                                      payload.PayloadPopRes[i].valid &&
                                      !ctrl.isPipe.flush;
            self.nextStage[i].pc = payload.PayloadPopRes[i].entry.pc;
            self.nextStage[i].predInfo = payload.PayloadPopRes[i].entry.predInfo;
            self.nextStage[i].csrAddr = payload.PayloadPopRes[i].entry.csrAddr;
            self.nextStage[i].SubType = payload.PayloadPopRes[i].entry.SubType;
            self.nextStage[i].opTypeA = payload.PayloadPopRes[i].entry.opTypeA;
            self.nextStage[i].opTypeB = payload.PayloadPopRes[i].entry.opTypeB;
            self.nextStage[i].imm = payload.PayloadPopRes[i].entry.imm;
            self.nextStage[i].tubeType = issueQueue.IssuePopRes[i].entry.tubeType;
            self.nextStage[i].srcA = issueQueue.IssuePopRes[i].entry.srcA;
            self.nextStage[i].srcB = issueQueue.IssuePopRes[i].entry.srcB;
            self.nextStage[i].dst = issueQueue.IssuePopRes[i].entry.dst;
            self.nextStage[i].writeDst = issueQueue.IssuePopRes[i].entry.writeDst;
            self.nextStage[i].robIndex = issueQueue.IssuePopRes[i].entry.robIndex;
            self.nextStage[i].storeBufferIndexValid = payload.PayloadPopRes[i].entry.storeBufferIndexValid;
            self.nextStage[i].storeBufferIndex = payload.PayloadPopRes[i].entry.storeBufferIndex;

            ctrl.isStageEmpty &= !self.nextStage[i].valid;
        end
    end
endmodule
