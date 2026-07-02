import BasicTypes::*;
import PipelineTypes::*;
import ROBTypes::*;
import RenameTypes::*;
import RecoveryTypes::*;
import StoreBufferTypes::*;

module CommitStage(
    CommitStageIF.CommitStage self,
    RecoveryManagerIF.CommitStage recovery,
    CtrlIF.CommitStage ctrl,
    ArchRATIF.CommitStage archRAT,
    SpecRATIF.CommitStage specRAT,
    FreeListIF.CommitStage freeList,
    StoreBufferIF.CommitStage storeBuffer,
    ROBIF.CommitStage rob
);
    task automatic clear_outputs();
        recovery.commitRecoveryReq = '0;
        recovery.commitBranchUpdateValid = 1'b0;
        recovery.commitBranchPc = '0;
        recovery.commitBranchTaken = 1'b0;
        recovery.commitBranchTarget = '0;
        ctrl.serialBlock = 1'b0;
        storeBuffer.StoreBufferCommitReq = '0;
        storeBuffer.flush = 1'b0;
        rob.RobFlush = 1'b0;

        for (int i = 0; i < WAY_NUM; i++) begin
            rob.RobPopReq[i].req = 1'b0;
            archRAT.archRATUpdate[i] = '0;
            freeList.freeListFree[i] = '0;
            self.commitValid[i] = 1'b0;
            self.commitPc[i] = '0;
        end
        specRAT.specRATChkptFree = '0;
        freeList.freeListChkptFree = '0;
        self.commitException = 1'b0;
        self.commitBranchMiss = 1'b0;
    endtask

    task automatic commit_dst(
        input int lane,
        input RobEntryPath entry
    );
        archRAT.archRATUpdate[lane].UpdateEn = entry.DstValid;
        archRAT.archRATUpdate[lane].UpdateLgcRegNum = entry.lgcRegNum;
        archRAT.archRATUpdate[lane].UpdatePhyRegNum = entry.phyRegNum;
        freeList.freeListFree[lane].freeReq = entry.DstValid;
        freeList.freeListFree[lane].freePhyRegNum = entry.phyPrevRegNum;
    endtask

    task automatic commit_pop(
        input int lane
    );
        rob.RobPopReq[lane].req = 1'b1;
        self.commitValid[lane] = 1'b1;
    endtask

    task automatic update_branch_predictor(
        input RobEntryPath entry
    );
        recovery.commitBranchUpdateValid = 1'b1;
        recovery.commitBranchPc = entry.pc;
        recovery.commitBranchTaken = entry.takenActual;
        recovery.commitBranchTarget = entry.truePc;
    endtask

    task automatic free_checkpoint(
        input RobEntryPath entry
    );
        specRAT.specRATChkptFree.ChkptFreeEn = entry.chkptValid;
        specRAT.specRATChkptFree.ChkptFreeIndex = entry.specRATChkptIndex;
        freeList.freeListChkptFree.ChkptFreeEn = entry.chkptValid;
        freeList.freeListChkptFree.ChkptFreeIndex = entry.freeListChkptIndex;
    endtask

    task automatic request_exception_recovery(
        input RobEntryPath entry
    );
        self.commitException = 1'b1;
        recovery.commitRecoveryReq.valid = 1'b1;
        recovery.commitRecoveryReq.cause = REC_EXCEPTION;
        recovery.commitRecoveryReq.recoverPc = entry.truePc;
        recovery.commitRecoveryReq.specRATChkptIndex = entry.specRATChkptIndex;
        recovery.commitRecoveryReq.freeListChkptIndex = entry.freeListChkptIndex;
        recovery.commitRecoveryReq.chkptRecoverEn = entry.chkptValid;
        recovery.commitRecoveryReq.recoverFreeEn = entry.DstValid;
        recovery.commitRecoveryReq.recoverFreePhyRegNum = entry.phyRegNum;
        recovery.commitRecoveryReq.frontendFlush = 1'b1;
        recovery.commitRecoveryReq.backendFlush = 1'b1;
        rob.RobFlush = 1'b1;
        storeBuffer.flush = 1'b1;
    endtask

    task automatic request_branch_recovery(
        input RobEntryPath entry
    );
        self.commitBranchMiss = 1'b1;
        recovery.commitRecoveryReq.valid = 1'b1;
        recovery.commitRecoveryReq.cause = REC_BRANCH_MISS;
        recovery.commitRecoveryReq.recoverPc = entry.truePc;
        recovery.commitRecoveryReq.specRATChkptIndex = entry.specRATChkptIndex;
        recovery.commitRecoveryReq.freeListChkptIndex = entry.freeListChkptIndex;
        recovery.commitRecoveryReq.chkptRecoverEn = entry.chkptValid;
        recovery.commitRecoveryReq.recoverFreeEn = entry.DstValid;
        recovery.commitRecoveryReq.recoverFreePhyRegNum = entry.phyPrevRegNum;
        recovery.commitRecoveryReq.frontendFlush = 1'b1;
        recovery.commitRecoveryReq.backendFlush = 1'b1;
        rob.RobFlush = 1'b1;
        storeBuffer.flush = 1'b1;
    endtask

    always_comb begin
        logic stopCommit;

        clear_outputs();
        stopCommit = 1'b0;

        for (int i = 0; i < WAY_NUM; i++) begin
            if (!stopCommit && rob.RobPopRes[i].valid) begin
                RobEntryPath entry;

                entry = rob.RobPopRes[i].entry;
                if (!entry.done) begin
                    stopCommit = 1'b1;
                    if (entry.isSerial) begin
                        ctrl.serialBlock = 1'b1;
                    end
                end else begin
                    self.commitPc[i] = entry.pc;

                    if (entry.exception) begin
                        request_exception_recovery(entry);
                        stopCommit = 1'b1;
                    end else if (entry.isBranch) begin
                        update_branch_predictor(entry);
                        self.commitValid[i] = 1'b1;
                        commit_dst(i, entry);
                        if (entry.isMiss) begin
                            request_branch_recovery(entry);
                        end else begin
                            rob.RobPopReq[i].req = 1'b1;
                            free_checkpoint(entry);
                        end
                        stopCommit = 1'b1;
                    end else if (entry.isStore) begin
                        if (storeBuffer.StoreBufferCommit.valid &&
                            storeBuffer.StoreBufferCommit.index == entry.storeBufferIndex) begin
                            storeBuffer.StoreBufferCommitReq.valid = 1'b1;
                            storeBuffer.StoreBufferCommitReq.index = entry.storeBufferIndex;
                        end
                        if (storeBuffer.StoreBufferCommitReady) begin
                            commit_pop(i);
                            free_checkpoint(entry);
                        end
                        stopCommit = 1'b1;
                    end else begin
                        commit_pop(i);
                        commit_dst(i, entry);
                        free_checkpoint(entry);
                    end
                end
            end
        end
    end
endmodule
