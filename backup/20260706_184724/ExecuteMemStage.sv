import BasicTypes::*;
import PipelineTypes::*;
import StoreBufferTypes::*;
import ReadRegTypes::*;

module ExecuteMemStage(
    ReadRegStageIF.ExecuteMemStage prev,
    ExecuteStageIF.ExecuteMemStage self,
    CtrlIF.ExecuteStage ctrl,
    DramAccessIF.ExecuteMemStage dram,
    StoreBufferIF.ExecuteMemStage storeBuffer,
    BypassIF.ExecuteMemStage bypass
);
    RrToExMemPath pipeReg [WAY_NUM];

    typedef struct packed {
        logic         valid;
        ExMemToWbPath wb;
        MemSubType    memSubType;
        AddrPath      addr;
        DataPath      forwardData;
        logic [3:0]   forwardMask;
    } LoadMetaPath;

    LoadMetaPath loadMetaPipe0;
    LoadMetaPath loadMetaPipe1;
    LoadMetaPath loadIssueMeta;
    ExMemToWbPath memResultBuf;
    logic         memResultBufValid;
    logic         memResultBufPop;
    logic         memResultBufPush;
    ExMemToWbPath memResultBufPushData;

    function automatic logic is_store(input MemSubType st);
        return st inside {MEM_SUBTYPE_SB, MEM_SUBTYPE_SH, MEM_SUBTYPE_SW};
    endfunction

    function automatic logic [3:0] store_wstrb(input MemSubType st);
        unique case (st)
            // Store data/mask are raw at the core boundary. dram_driver/TB
            // performs the final addr[1:0]-based lane alignment.
            MEM_SUBTYPE_SB: store_wstrb = 4'b0001;
            MEM_SUBTYPE_SH: store_wstrb = 4'b0011;
            default:        store_wstrb = 4'b1111;
        endcase
    endfunction

    function automatic logic [3:0] load_rstrb(input MemSubType st, input AddrPath addr);
        unique case (st)
            MEM_SUBTYPE_LB,
            MEM_SUBTYPE_LBU: load_rstrb = 4'b0001 << addr[1:0];
            MEM_SUBTYPE_LH,
            MEM_SUBTYPE_LHU: load_rstrb = addr[1] ? 4'b1100 : 4'b0011;
            default:         load_rstrb = 4'b1111;
        endcase
    endfunction

    function automatic DataPath extend_load_data(input MemSubType st, input DataPath data);
        unique case (st)
            MEM_SUBTYPE_LB:  extend_load_data = {{24{data[7]}}, data[7:0]};
            MEM_SUBTYPE_LH:  extend_load_data = {{16{data[15]}}, data[15:0]};
            MEM_SUBTYPE_LBU: extend_load_data = {24'b0, data[7:0]};
            MEM_SUBTYPE_LHU: extend_load_data = {16'b0, data[15:0]};
            default:         extend_load_data = data;
        endcase
    endfunction

    function automatic DataPath merge_forward_data(
        input DataPath    memData,
        input DataPath    forwardData,
        input logic [3:0] forwardMask
    );
        DataPath merged;

        merged = memData;
        for (int b = 0; b < 4; b++) begin
            if (forwardMask[b]) begin
                merged[b*8 +: 8] = forwardData[b*8 +: 8];
            end
        end
        return merged;
    endfunction

    function automatic ExMemToWbPath build_load_wb(input LoadMetaPath meta, input DataPath readData);
        DataPath mergedLoadData;

        mergedLoadData = merge_forward_data(readData, meta.forwardData, meta.forwardMask);
        build_load_wb = meta.wb;
        build_load_wb.data = extend_load_data(meta.memSubType, mergedLoadData);
    endfunction

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToMemStage;
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            loadMetaPipe0 <= '0;
            loadMetaPipe1 <= '0;
        end else if (ctrl.exPipe.flush) begin
            loadMetaPipe0 <= '0;
            loadMetaPipe1 <= '0;
        end else begin
            loadMetaPipe1 <= loadMetaPipe0;
            loadMetaPipe0 <= '0;
            if (dram.exReadEn && dram.exReadReady) begin
                loadMetaPipe0 <= loadIssueMeta;
            end
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            memResultBuf <= '0;
            memResultBufValid <= 1'b0;
        end else if (ctrl.exPipe.flush) begin
            memResultBuf <= '0;
            memResultBufValid <= 1'b0;
        end else begin
            if (memResultBufPop) begin
                memResultBufValid <= 1'b0;
            end
            if (memResultBufPush) begin
                memResultBuf <= memResultBufPushData;
                memResultBufValid <= 1'b1;
            end
        end
    end

    always_comb begin
        logic currentLoadSelected;
        logic loadReturnBlocked;
        logic loadAccessBlocked;
        logic currentOutputBlocked;
        logic [WAY_NUM-1:0] memWbSlotUsed;
        ExMemToWbPath loadReturnWb;

        dram.exReadEn = 1'b0;
        dram.exReadAddr = '0;
        storeBuffer.StoreBufferMatchIn = '0;
        storeBuffer.StoreBufferPushReq = '0;
        loadIssueMeta = '0;
        currentLoadSelected = 1'b0;
        loadReturnBlocked = 1'b0;
        loadAccessBlocked = 1'b0;
        currentOutputBlocked = 1'b0;
        memWbSlotUsed = '0;
        loadReturnWb = '0;
        memResultBufPop = 1'b0;
        memResultBufPush = 1'b0;
        memResultBufPushData = '0;
        ctrl.memLoadReturnBlockReq = 1'b0;
        ctrl.memLoadAccessBlockReq = 1'b0;

        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.memReadReq[i] = '0;
        for (int i = 0; i < WAY_NUM; i++) begin
            self.nextMemToStage[i] = '0;
        end

        ctrl.memStageEmpty = !loadMetaPipe0.valid && !loadMetaPipe1.valid &&
                             !memResultBufValid;

        if (memResultBufValid) begin
            self.nextMemToStage[0] = memResultBuf;
            memWbSlotUsed[0] = 1'b1;
            memResultBufPop = 1'b1;
        end

        if (loadMetaPipe1.valid) begin
            loadReturnWb = build_load_wb(loadMetaPipe1, dram.exReadData);
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            DataPath base;
            DataPath dataB;
            AddrPath effAddr;

            base = pipeReg[i].dataA;
            dataB = pipeReg[i].dataB;
            bypass.memReadReq[i*2+0].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.memReadReq[i*2+0].phyRegNum = pipeReg[i].Rs1;
            bypass.memReadReq[i*2+1].valid = pipeReg[i].valid && pipeReg[i].srcBIsRs2;
            bypass.memReadReq[i*2+1].phyRegNum = pipeReg[i].Rs2;
            if (bypass.memReadRes[i*2+0].hit) base = bypass.memReadRes[i*2+0].data;
            if (bypass.memReadRes[i*2+1].hit) dataB = bypass.memReadRes[i*2+1].data;

            effAddr = base + pipeReg[i].imm;

            if (pipeReg[i].valid && !ctrl.exPipe.flush && !currentOutputBlocked) begin
                if (is_store(pipeReg[i].subType.memSubType)) begin
                    ExMemToWbPath storeWb;

                    storeWb = '0;
                    storeWb.valid = 1'b1;
                    storeWb.Rd = pipeReg[i].Rd;
                    storeWb.writeRd = 1'b0;
                    storeWb.robIndex = pipeReg[i].robIndex;

                    if (!memWbSlotUsed[0]) begin
                        storeBuffer.StoreBufferPushReq.valid = pipeReg[i].storeBufferIndexValid;
                        storeBuffer.StoreBufferPushReq.index = pipeReg[i].storeBufferIndex;
                        storeBuffer.StoreBufferPushReq.addr = effAddr;
                        storeBuffer.StoreBufferPushReq.data = dataB;
                        storeBuffer.StoreBufferPushReq.wstrb =
                            store_wstrb(pipeReg[i].subType.memSubType);
                        self.nextMemToStage[0] = storeWb;
                        memWbSlotUsed[0] = 1'b1;
                    end else if (!memWbSlotUsed[1]) begin
                        storeBuffer.StoreBufferPushReq.valid = pipeReg[i].storeBufferIndexValid;
                        storeBuffer.StoreBufferPushReq.index = pipeReg[i].storeBufferIndex;
                        storeBuffer.StoreBufferPushReq.addr = effAddr;
                        storeBuffer.StoreBufferPushReq.data = dataB;
                        storeBuffer.StoreBufferPushReq.wstrb =
                            store_wstrb(pipeReg[i].subType.memSubType);
                        self.nextMemToStage[1] = storeWb;
                        memWbSlotUsed[1] = 1'b1;
                    end else begin
                        currentOutputBlocked = 1'b1;
                    end
                end else if (!currentLoadSelected) begin
                    storeBuffer.StoreBufferMatchIn.valid = 1'b1;
                    storeBuffer.StoreBufferMatchIn.addr = effAddr;
                    storeBuffer.StoreBufferMatchIn.rstrb =
                        load_rstrb(pipeReg[i].subType.memSubType, effAddr);

                    loadIssueMeta.valid = 1'b1;
                    loadIssueMeta.memSubType = pipeReg[i].subType.memSubType;
                    loadIssueMeta.addr = effAddr;
                    loadIssueMeta.wb.valid = 1'b1;
                    loadIssueMeta.wb.Rd = pipeReg[i].Rd;
                    loadIssueMeta.wb.writeRd = pipeReg[i].writeRd;
                    loadIssueMeta.wb.robIndex = pipeReg[i].robIndex;
                    loadIssueMeta.forwardData = storeBuffer.StoreBufferMatchOut.data;
                    loadIssueMeta.forwardMask = storeBuffer.StoreBufferMatchOut.mask;

                    if (storeBuffer.StoreBufferMatchOut.hit) begin
                        ExMemToWbPath forwardWb;

                        forwardWb = loadIssueMeta.wb;
                        forwardWb.data = extend_load_data(pipeReg[i].subType.memSubType,
                                                           storeBuffer.StoreBufferMatchOut.data);
                        if (!memWbSlotUsed[0]) begin
                            self.nextMemToStage[0] = forwardWb;
                            memWbSlotUsed[0] = 1'b1;
                        end else if (!memWbSlotUsed[1]) begin
                            self.nextMemToStage[1] = forwardWb;
                            memWbSlotUsed[1] = 1'b1;
                        end else begin
                            currentOutputBlocked = 1'b1;
                        end
                    end else if (storeBuffer.StoreBufferMatchOut.block) begin
                        loadAccessBlocked = 1'b1;
                    end else begin
                        dram.exReadEn = 1'b1;
                        dram.exReadAddr = effAddr;
                        loadAccessBlocked = !dram.exReadReady;
                    end
                    currentLoadSelected = 1'b1;
                end
            end
            ctrl.memStageEmpty &= !(pipeReg[i].valid && !ctrl.exPipe.flush);
        end

        if (loadMetaPipe1.valid) begin
            if (!memWbSlotUsed[0]) begin
                self.nextMemToStage[0] = loadReturnWb;
                memWbSlotUsed[0] = 1'b1;
            end else if (!memWbSlotUsed[1]) begin
                self.nextMemToStage[1] = loadReturnWb;
                memWbSlotUsed[1] = 1'b1;
            end else if (!memResultBufValid || memResultBufPop) begin
                memResultBufPush = 1'b1;
                memResultBufPushData = loadReturnWb;
            end else begin
                loadReturnBlocked = 1'b1;
            end
        end

        ctrl.memLoadReturnBlockReq = loadReturnBlocked;
        ctrl.memLoadAccessBlockReq = loadAccessBlocked;
        ctrl.exStallReq = loadReturnBlocked || loadAccessBlocked || currentOutputBlocked;
    end
endmodule
