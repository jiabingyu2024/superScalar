import BasicTypes::*;
import RecoveryTypes::*;
import RenameTypes::*;

module RecoveryManager(
    RecoveryManagerIF.RecoveryManager self,
    CtrlIF.CtrlUnit ctrl,
    SpecRATIF.RecoveryManager specRAT,
    FreeListIF.RecoveryManager freeList
);
    typedef enum logic {
        RM_IDLE,
        RM_EMIT
    } RecoveryStatePath;

    RecoveryStatePath state;
    RecoveryReqPath recoveryReg;

    logic  branchUpdateValidReg;
    PcPath branchPcReg;
    logic  branchTakenReg;
    PcPath branchTargetReg;

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            state <= RM_IDLE;
            recoveryReg <= '0;
            branchUpdateValidReg <= 1'b0;
            branchPcReg <= '0;
            branchTakenReg <= 1'b0;
            branchTargetReg <= '0;
        end else begin
            branchUpdateValidReg <= self.commitBranchUpdateValid;
            branchPcReg <= self.commitBranchPc;
            branchTakenReg <= self.commitBranchTaken;
            branchTargetReg <= self.commitBranchTarget;

            case (state)
                RM_IDLE: begin
                    recoveryReg <= '0;
                    if (self.commitRecoveryReq.valid) begin
                        recoveryReg <= self.commitRecoveryReq;
                        state <= RM_EMIT;
                    end else if (self.writeBackRecoveryReq.valid) begin
                        recoveryReg <= self.writeBackRecoveryReq;
                        state <= RM_EMIT;
                    end
                end
                RM_EMIT: begin
                    if (self.commitRecoveryReq.valid) begin
                        recoveryReg <= self.commitRecoveryReq;
                        state <= RM_EMIT;
                    end else if (self.writeBackRecoveryReq.valid) begin
                        recoveryReg <= self.writeBackRecoveryReq;
                        state <= RM_EMIT;
                    end else begin
                        recoveryReg <= '0;
                        state <= RM_IDLE;
                    end
                end
            endcase
        end
    end

    always_comb begin
        self.recoveryInfo = recoveryReg;

        self.pcUpdateEn = self.recoveryInfo.valid;
        self.pcUpdate = self.recoveryInfo.recoverPc;

        self.branchUpdateValid = branchUpdateValidReg;
        self.branchPc = branchPcReg;
        self.branchTaken = branchTakenReg;
        self.branchTarget = branchTargetReg;
        self.branchMiss = self.recoveryInfo.valid &&
                          self.recoveryInfo.cause == REC_BRANCH_MISS;

        specRAT.specRATChkptRecover.ChkptRecoverEn = self.recoveryInfo.valid &&
                                                     self.recoveryInfo.chkptRecoverEn;
        specRAT.specRATChkptRecover.ChkptRecoverIndex = self.recoveryInfo.specRATChkptIndex;
        specRAT.specRATChkptRecover.RecoverFreeEn = 1'b0;
        specRAT.specRATChkptRecover.RecoverFreePhyRegNum = '0;

        freeList.freeListChkptRecover.ChkptRecoverEn = self.recoveryInfo.valid &&
                                                       self.recoveryInfo.chkptRecoverEn;
        freeList.freeListChkptRecover.ChkptRecoverIndex = self.recoveryInfo.freeListChkptIndex;
        freeList.freeListChkptRecover.RecoverFreeEn = self.recoveryInfo.valid &&
                                                      self.recoveryInfo.recoverFreeEn;
        freeList.freeListChkptRecover.RecoverFreePhyRegNum = self.recoveryInfo.recoverFreePhyRegNum;
    end
endmodule
