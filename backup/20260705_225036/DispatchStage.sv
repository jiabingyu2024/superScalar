import BasicTypes::*;
import PipelineTypes::*;
import IssueTypes::*;
import ROBTypes::*;
import StoreBufferTypes::*;

module DispatchStage(
    RenameStageIF.DispatchStage prev,
    DispatchStageIF.DispatchStage self,
    IssueQueueIF.DispatchStage issueQueue,
    PayloadIF.DispatchStage payload,
    CtrlIF.DispatchStage ctrl,
    ROBIF.DispatchStage rob,
    StoreBufferIF.DispatchStage storeBuffer
);
    RnToDsPath pipeReg [WAY_NUM];

    logic dispatchFire[WAY_NUM];

    function automatic logic is_store_uop(input RnToDsPath uop);
        is_store_uop = uop.instInfo.tubeType == TUBE_TYPE_MEM &&
                       (uop.instInfo.SubType.memSubType inside
                         {MEM_SUBTYPE_SB, MEM_SUBTYPE_SH, MEM_SUBTYPE_SW});
    endfunction

    function automatic logic wakeup_match(
        input logic valid,
        input PhyRegNumPath phyRegNum
    );
        wakeup_match = 1'b0;
        if (valid && phyRegNum != '0) begin
            for (int w = 0; w < ISSUE_WAKEUP_PORT_NUM; w++) begin
                if (issueQueue.IssueWakeup[w].valid &&
                    issueQueue.IssueWakeup[w].phyRegNum == phyRegNum) begin
                    wakeup_match = 1'b1;
                end
            end
        end
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.dsPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.dsPipe.stall) begin
            pipeReg <= prev.nextStage;
        end else begin
            for (int i = 0; i < WAY_NUM; i++) begin
                if (wakeup_match(pipeReg[i].phyRegInfo.PhyRegNumSrcAValid,
                                 pipeReg[i].phyRegInfo.PhyRegNumSrcA)) begin
                    pipeReg[i].phyRegInfo.PhyRegNumSrcAReady <= 1'b1;
                end
                if (wakeup_match(pipeReg[i].phyRegInfo.PhyRegNumSrcBValid,
                                 pipeReg[i].phyRegInfo.PhyRegNumSrcB)) begin
                    pipeReg[i].phyRegInfo.PhyRegNumSrcBReady <= 1'b1;
                end
            end
        end
    end

    always_comb begin
        int validCount;
        int storeCount;
        logic packetValid;
        logic resourceReady;
        logic dispatchEn;

        ctrl.dsStageEmpty = 1'b1;
        ctrl.dsStallReq = 1'b0;
        ctrl.robFull = 1'b0;
        ctrl.issueQueueFull = 1'b0;

        storeBuffer.allocReq = 1'b0;
        issueQueue.IssueCtrl.flush = ctrl.dsPipe.flush;
        payload.flush = ctrl.dsPipe.flush;

        validCount = 0;
        storeCount = 0;
        packetValid = 1'b0;
        resourceReady = 1'b1;
        dispatchEn = 1'b0;

        for (int i = 0; i < WAY_NUM; i++) begin
            dispatchFire[i] = 1'b0;
            self.nextStage[i] = '0;

            rob.RobPushReq[i] = '0;
            issueQueue.IssuePushReq[i] = '0;
            payload.PayloadPushReq[i] = '0;

            if (pipeReg[i].valid) begin
                validCount++;
                packetValid = 1'b1;
                if (is_store_uop(pipeReg[i])) begin
                    storeCount++;
                end
            end
            ctrl.dsStageEmpty &= !pipeReg[i].valid;
        end

        ctrl.robFull = packetValid && (int'(rob.RobFreeCount) < validCount);
        ctrl.issueQueueFull = packetValid && (int'(issueQueue.IssueFreeCount) < validCount);

        resourceReady = !ctrl.robFull &&
                        !ctrl.issueQueueFull &&
                        (storeCount == 0 || (storeCount == 1 && storeBuffer.allocRdy));

        for (int i = 0; i < WAY_NUM; i++) begin
            logic isStore;
            isStore = is_store_uop(pipeReg[i]);

            resourceReady &= !pipeReg[i].valid ||
                             (rob.RobPushRes[i].valid && issueQueue.IssuePushRes[i].done);

            rob.RobPushReq[i].entry.done = 1'b0;
            rob.RobPushReq[i].entry.pc = pipeReg[i].pc;
            rob.RobPushReq[i].entry.DstValid = pipeReg[i].phyRegInfo.PhyRegNumDstValid;
            rob.RobPushReq[i].entry.lgcRegNum = pipeReg[i].lgcRegInfo.lgcRegNumDst;
            rob.RobPushReq[i].entry.phyRegNum = pipeReg[i].phyRegInfo.PhyRegNumDst;
            rob.RobPushReq[i].entry.phyPrevRegNum = pipeReg[i].phyPrevDst;
            rob.RobPushReq[i].entry.isBranch = pipeReg[i].instInfo.tubeType == TUBE_TYPE_BRC;
            rob.RobPushReq[i].entry.brcSubType = pipeReg[i].instInfo.SubType.brcSubType;
            rob.RobPushReq[i].entry.takenPred = pipeReg[i].predInfo.isPred;
            rob.RobPushReq[i].entry.takenActual = 1'b0;
            rob.RobPushReq[i].entry.predPc = pipeReg[i].predInfo.pcPred;
            rob.RobPushReq[i].entry.truePc = pipeReg[i].predInfo.pcPred;
            rob.RobPushReq[i].entry.chkptValid = pipeReg[i].chkptValid;
            rob.RobPushReq[i].entry.specRATChkptIndex = pipeReg[i].specRATChkptIndex;
            rob.RobPushReq[i].entry.freeListChkptIndex = pipeReg[i].freeListChkptIndex;
            rob.RobPushReq[i].entry.isStore = isStore;
            rob.RobPushReq[i].entry.storeBufferIndex = storeBuffer.allocIndex;
            rob.RobPushReq[i].entry.isSerial = pipeReg[i].instInfo.isSerial;
            rob.RobPushReq[i].entry.exception = 1'b0;

            issueQueue.IssuePushReq[i].entry.tubeType = pipeReg[i].instInfo.tubeType;
            issueQueue.IssuePushReq[i].entry.srcA = pipeReg[i].phyRegInfo.PhyRegNumSrcA;
            issueQueue.IssuePushReq[i].entry.srcB = pipeReg[i].phyRegInfo.PhyRegNumSrcB;
            issueQueue.IssuePushReq[i].entry.srcARdy =
                !pipeReg[i].phyRegInfo.PhyRegNumSrcAValid ||
                pipeReg[i].phyRegInfo.PhyRegNumSrcAReady ||
                wakeup_match(pipeReg[i].phyRegInfo.PhyRegNumSrcAValid,
                             pipeReg[i].phyRegInfo.PhyRegNumSrcA);
            issueQueue.IssuePushReq[i].entry.srcBRdy =
                !pipeReg[i].phyRegInfo.PhyRegNumSrcBValid ||
                pipeReg[i].phyRegInfo.PhyRegNumSrcBReady ||
                wakeup_match(pipeReg[i].phyRegInfo.PhyRegNumSrcBValid,
                             pipeReg[i].phyRegInfo.PhyRegNumSrcB);
            issueQueue.IssuePushReq[i].entry.srcBIsImm = pipeReg[i].instInfo.opTypeB == OP_TYPE_IMM ||
                                                         pipeReg[i].instInfo.opTypeB == OP_TYPE_NONE;
            issueQueue.IssuePushReq[i].entry.dst = pipeReg[i].phyRegInfo.PhyRegNumDst;
            issueQueue.IssuePushReq[i].entry.writeDst = pipeReg[i].phyRegInfo.PhyRegNumDstValid;
            issueQueue.IssuePushReq[i].entry.delay = delay_for(pipeReg[i].instInfo.tubeType,
                                                               pipeReg[i].instInfo.SubType);
            issueQueue.IssuePushReq[i].entry.robIndex = rob.RobPushRes[i].robIndex;
            issueQueue.IssuePushReq[i].entry.robIndexPosition = rob.RobPushRes[i].position;

            payload.PayloadPushReq[i].payloadIndex = issueQueue.IssuePushRes[i].payloadIndex;
            payload.PayloadPushReq[i].entry.pc = pipeReg[i].pc;
            payload.PayloadPushReq[i].entry.predInfo = pipeReg[i].predInfo;
            payload.PayloadPushReq[i].entry.csrAddr = pipeReg[i].csrAddr;
            payload.PayloadPushReq[i].entry.SubType = pipeReg[i].instInfo.SubType;
            payload.PayloadPushReq[i].entry.opTypeA = pipeReg[i].instInfo.opTypeA;
            payload.PayloadPushReq[i].entry.opTypeB = pipeReg[i].instInfo.opTypeB;
            payload.PayloadPushReq[i].entry.imm = pipeReg[i].imm;
            payload.PayloadPushReq[i].entry.storeBufferIndexValid = isStore;
            payload.PayloadPushReq[i].entry.storeBufferIndex = storeBuffer.allocIndex;
        end

        ctrl.dsStallReq = packetValid && !ctrl.dsPipe.flush && !resourceReady;
        dispatchEn = packetValid && !ctrl.dsPipe.flush && !ctrl.dsPipe.stall && resourceReady;
        storeBuffer.allocReq = dispatchEn && (storeCount != 0);

        for (int i = 0; i < WAY_NUM; i++) begin
            dispatchFire[i] = pipeReg[i].valid && dispatchEn;
            self.nextStage[i].valid = dispatchFire[i];
            rob.RobPushReq[i].req = dispatchFire[i];
            rob.RobPushReq[i].entry.valid = dispatchFire[i];
            issueQueue.IssuePushReq[i].valid = dispatchFire[i];
            payload.PayloadPushReq[i].valid = dispatchFire[i];
        end
    end

    function automatic ShiftType delay_for(input TubeTypePath tube, input SubTypePath subtype);
        int cycles;
        cycles = 1;
        unique case (tube)
            TUBE_TYPE_MUL: cycles = (subtype.mulSubType inside {MUL_SUBTYPE_DIV, MUL_SUBTYPE_DIVU,
                                                                 MUL_SUBTYPE_REM, MUL_SUBTYPE_REMU}) ? 34 : 3;
            TUBE_TYPE_MEM: cycles = 3;
            default:       cycles = 1;
        endcase
        delay_for = ShiftType'(1) << (cycles - 1);
    endfunction
endmodule
