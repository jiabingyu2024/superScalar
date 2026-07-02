// 同时对 WAY_NUM 条指令进行重命名，处理组内相关、FreeList 分配和 branch checkpoint。

import BasicTypes::*;
import PipelineTypes::*;
import RenameTypes::*;

module RenameStage (
    DecodeStageIF.RenameStage    prev,
    RenameStageIF.RenameStage    self,
    CtrlIF.RenameStage           ctrl,
    SpecRATIF.RenameStage        specRAT,
    FreeListIF.RenameStage       freeList,
    ReadyTableIF.RenameStage     readyTable,
    RecoveryManagerIF.RenameStage recovery
);

    IdToRnPath pipeReg [WAY_NUM];
    RnToDsPath nextStage [WAY_NUM];

    function automatic logic needs_dst_alloc(input IdToRnPath uop);
        needs_dst_alloc = uop.valid &&
                          uop.instInfo.writeReg &&
                          uop.lgcRegInfo.lgcRegNumDstValid &&
                          uop.lgcRegInfo.lgcRegNumDst != '0;
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.rnPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.rnPipe.stall) begin
            pipeReg <= prev.nextStage;
        end
    end

    always_comb begin
        int writeNeed;
        int chkptCount;
        logic chkptPresent;
        WayNumPath chkptWay;
        logic serialPresent;
        logic backendDrained;
        logic resourceStall;
        logic chkptStall;
        logic localStall;
        logic canRename;

        writeNeed = 0;
        chkptCount = 0;
        chkptPresent = 1'b0;
        chkptWay = '0;
        serialPresent = 1'b0;
        backendDrained = ctrl.dsStageEmpty && ctrl.isStageEmpty && ctrl.rrStageEmpty &&
                         ctrl.exStageEmpty && ctrl.wbStageEmpty;

        for (int i = 0; i < WAY_NUM; i++) begin
            if (needs_dst_alloc(pipeReg[i])) begin
                writeNeed++;
            end
            if (pipeReg[i].valid && pipeReg[i].instInfo.valid &&
                (pipeReg[i].instInfo.tubeType == TUBE_TYPE_BRC ||
                 pipeReg[i].instInfo.isSerial)) begin
                chkptCount++;
                if (!chkptPresent) begin
                    chkptPresent = 1'b1;
                    chkptWay = WayNumPath'(i);
                end
            end
            if (pipeReg[i].valid && pipeReg[i].instInfo.isSerial) begin
                serialPresent = 1'b1;
            end
        end

        resourceStall = (freeList.freeListCount < FreeListCountPath'(writeNeed));
        chkptStall = chkptPresent && !freeList.freeListChkptCreate.ChkptIndexValid;
        localStall = resourceStall || chkptStall || (serialPresent && !backendDrained) ||
                     (chkptCount > 1);
        canRename = !ctrl.rnPipe.flush && !ctrl.rnPipe.stall && !localStall;

        specRAT.specRATChkptCreateEn = chkptPresent && canRename;
        specRAT.specRATChkptCreateIndex = freeList.freeListChkptCreate.ChkptCreateIndex;
        specRAT.specRATChkptBranchWay = chkptWay;
        freeList.freeListChkptCreateEn = chkptPresent && canRename;
        freeList.freeListChkptBranchWay = chkptWay;

        ctrl.rnStageEmpty = 1'b1;
        ctrl.rnStallReq = localStall;
        ctrl.freeListEmpty = resourceStall;

        for (int i = 0; i < SPECRAT_READ_PORT_NUM; i++) begin
            specRAT.specRATReadIn[i].ReadEn = 1'b0;
            specRAT.specRATReadIn[i].ReadLgcRegNum = '0;
        end
        for (int i = 0; i < SPECRAT_WRITE_PORT_NUM; i++) begin
            specRAT.specRATUpdate[i] = '0;
        end
        for (int i = 0; i < WAY_NUM * 2; i++) begin
            readyTable.readReq[i] = '0;
        end
        for (int i = 0; i < WAY_NUM; i++) begin
            freeList.freeListAllocReq[i] = canRename &&
                                           needs_dst_alloc(pipeReg[i]);
            readyTable.markBusy[i] = '0;
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            int base;
            int readyBase;
            PhyRegNumPath srcA;
            PhyRegNumPath srcB;
            PhyRegNumPath oldDst;
            logic srcAFromGroup;
            logic srcBFromGroup;

            base = i * 3;
            readyBase = i * 2;
            specRAT.specRATReadIn[base + 0].ReadEn = pipeReg[i].valid &&
                                                     pipeReg[i].lgcRegInfo.lgcRegNumSrcAValid;
            specRAT.specRATReadIn[base + 0].ReadLgcRegNum = pipeReg[i].lgcRegInfo.lgcRegNumSrcA;
            specRAT.specRATReadIn[base + 1].ReadEn = pipeReg[i].valid &&
                                                     pipeReg[i].lgcRegInfo.lgcRegNumSrcBValid;
            specRAT.specRATReadIn[base + 1].ReadLgcRegNum = pipeReg[i].lgcRegInfo.lgcRegNumSrcB;
            specRAT.specRATReadIn[base + 2].ReadEn = pipeReg[i].valid &&
                                                     pipeReg[i].lgcRegInfo.lgcRegNumDstValid &&
                                                     pipeReg[i].lgcRegInfo.lgcRegNumDst != '0;
            specRAT.specRATReadIn[base + 2].ReadLgcRegNum = pipeReg[i].lgcRegInfo.lgcRegNumDst;

            srcA = specRAT.specRATReadOut[base + 0];
            srcB = specRAT.specRATReadOut[base + 1];
            oldDst = specRAT.specRATReadOut[base + 2];
            srcAFromGroup = 1'b0;
            srcBFromGroup = 1'b0;

            for (int k = 0; k < i; k++) begin
                if (needs_dst_alloc(pipeReg[k]) && freeList.freeListAlloc[k].allocValid) begin
                    if (needs_dst_alloc(pipeReg[i]) &&
                        pipeReg[i].lgcRegInfo.lgcRegNumDst == pipeReg[k].lgcRegInfo.lgcRegNumDst) begin
                        oldDst = freeList.freeListAlloc[k].allocPhyRegNum;
                    end
                    if (pipeReg[i].lgcRegInfo.lgcRegNumSrcAValid &&
                        pipeReg[i].lgcRegInfo.lgcRegNumSrcA == pipeReg[k].lgcRegInfo.lgcRegNumDst) begin
                        srcA = freeList.freeListAlloc[k].allocPhyRegNum;
                        srcAFromGroup = 1'b1;
                    end
                    if (pipeReg[i].lgcRegInfo.lgcRegNumSrcBValid &&
                        pipeReg[i].lgcRegInfo.lgcRegNumSrcB == pipeReg[k].lgcRegInfo.lgcRegNumDst) begin
                        srcB = freeList.freeListAlloc[k].allocPhyRegNum;
                        srcBFromGroup = 1'b1;
                    end
                end
            end

            readyTable.readReq[readyBase + 0].valid = pipeReg[i].valid &&
                                                      pipeReg[i].lgcRegInfo.lgcRegNumSrcAValid;
            readyTable.readReq[readyBase + 0].phyRegNum = srcA;
            readyTable.readReq[readyBase + 1].valid = pipeReg[i].valid &&
                                                      pipeReg[i].lgcRegInfo.lgcRegNumSrcBValid;
            readyTable.readReq[readyBase + 1].phyRegNum = srcB;

            nextStage[i] = '0;
            nextStage[i].valid = pipeReg[i].valid && canRename;
            nextStage[i].pc = pipeReg[i].pc;
            nextStage[i].predInfo = pipeReg[i].predInfo;
            nextStage[i].lgcRegInfo = pipeReg[i].lgcRegInfo;
            nextStage[i].csrAddr = pipeReg[i].csrAddr;
            nextStage[i].instInfo = pipeReg[i].instInfo;
            nextStage[i].imm = pipeReg[i].imm;

            nextStage[i].phyRegInfo.PhyRegNumSrcAValid = pipeReg[i].lgcRegInfo.lgcRegNumSrcAValid;
            nextStage[i].phyRegInfo.PhyRegNumSrcBValid = pipeReg[i].lgcRegInfo.lgcRegNumSrcBValid;
            nextStage[i].phyRegInfo.PhyRegNumDstValid = freeList.freeListAlloc[i].allocValid;
            nextStage[i].phyRegInfo.PhyRegNumSrcAReady =
                !pipeReg[i].lgcRegInfo.lgcRegNumSrcAValid ||
                (!srcAFromGroup && readyTable.readReady[readyBase + 0]);
            nextStage[i].phyRegInfo.PhyRegNumSrcBReady =
                !pipeReg[i].lgcRegInfo.lgcRegNumSrcBValid ||
                (!srcBFromGroup && readyTable.readReady[readyBase + 1]);
            nextStage[i].phyRegInfo.PhyRegNumSrcA = srcA;
            nextStage[i].phyRegInfo.PhyRegNumSrcB = srcB;
            nextStage[i].phyRegInfo.PhyRegNumDst = freeList.freeListAlloc[i].allocPhyRegNum;
            nextStage[i].phyPrevDst = oldDst;

            nextStage[i].chkptValid = chkptPresent && canRename && (WayNumPath'(i) == chkptWay);
            nextStage[i].specRATChkptIndex = freeList.freeListChkptCreate.ChkptCreateIndex;
            nextStage[i].freeListChkptIndex = freeList.freeListChkptCreate.ChkptCreateIndex;

            specRAT.specRATUpdate[i].UpdateEn = nextStage[i].valid &&
                                                needs_dst_alloc(pipeReg[i]) &&
                                                freeList.freeListAlloc[i].allocValid;
            specRAT.specRATUpdate[i].UpdateLgcRegNum = pipeReg[i].lgcRegInfo.lgcRegNumDst;
            specRAT.specRATUpdate[i].UpdatePhyRegNum = freeList.freeListAlloc[i].allocPhyRegNum;
            readyTable.markBusy[i].valid = specRAT.specRATUpdate[i].UpdateEn;
            readyTable.markBusy[i].phyRegNum = freeList.freeListAlloc[i].allocPhyRegNum;

            ctrl.rnStageEmpty &= !nextStage[i].valid;
        end
    end

    assign self.nextStage = nextStage;

endmodule
