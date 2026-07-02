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
    } LoadMetaPath;

    LoadMetaPath loadMetaPipe0;
    LoadMetaPath loadMetaPipe1;
    LoadMetaPath loadIssueMeta;

    function automatic logic is_store(input MemSubType st);
        return st inside {MEM_SUBTYPE_SB, MEM_SUBTYPE_SH, MEM_SUBTYPE_SW};
    endfunction

    function automatic logic [3:0] store_wstrb(input MemSubType st, input AddrPath addr);
        unique case (st)
            MEM_SUBTYPE_SB: store_wstrb = 4'b0001 << addr[1:0];
            MEM_SUBTYPE_SH: store_wstrb = addr[1] ? 4'b1100 : 4'b0011;
            default:        store_wstrb = 4'b1111;
        endcase
    endfunction

    function automatic DataPath align_store_data(input MemSubType st, input AddrPath addr, input DataPath data);
        unique case (st)
            MEM_SUBTYPE_SB: align_store_data = data << (addr[1:0] * 8);
            MEM_SUBTYPE_SH: align_store_data = data << (addr[1] * 16);
            default:        align_store_data = data;
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

    function automatic DataPath align_load_data(input MemSubType st, input AddrPath addr, input DataPath data);
        unique case (st)
            MEM_SUBTYPE_LB,
            MEM_SUBTYPE_LBU: align_load_data = data >> (addr[1:0] * 8);
            MEM_SUBTYPE_LH,
            MEM_SUBTYPE_LHU: align_load_data = data >> (addr[1] * 16);
            default:         align_load_data = data;
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

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
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

    always_comb begin
        logic currentLoadSelected;
        logic currentMemValid;
        logic loadReturnBlocked;
        logic loadAccessBlocked;

        dram.exReadEn = 1'b0;
        dram.exReadAddr = '0;
        storeBuffer.StoreBufferMatchIn = '0;
        storeBuffer.StoreBufferPushReq = '0;
        loadIssueMeta = '0;
        currentLoadSelected = 1'b0;
        currentMemValid = 1'b0;
        loadReturnBlocked = 1'b0;
        loadAccessBlocked = 1'b0;

        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.memReadReq[i] = '0;
        for (int i = 0; i < WAY_NUM; i++) begin
            self.nextMemToStage[i] = '0;
            currentMemValid |= pipeReg[i].valid && !ctrl.exPipe.flush;
        end

        loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
        ctrl.memStageEmpty = !loadMetaPipe0.valid && !loadMetaPipe1.valid;

        if (loadMetaPipe1.valid) begin
            self.nextMemToStage[0] = loadMetaPipe1.wb;
            self.nextMemToStage[0].data =
                extend_load_data(loadMetaPipe1.memSubType,
                                 align_load_data(loadMetaPipe1.memSubType,
                                                 loadMetaPipe1.addr,
                                                 dram.exReadData));
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

            if (pipeReg[i].valid && !ctrl.exPipe.flush && !loadReturnBlocked) begin
                if (is_store(pipeReg[i].subType.memSubType)) begin
                    storeBuffer.StoreBufferPushReq.valid = pipeReg[i].storeBufferIndexValid;
                    storeBuffer.StoreBufferPushReq.index = pipeReg[i].storeBufferIndex;
                    storeBuffer.StoreBufferPushReq.addr = effAddr;
                    storeBuffer.StoreBufferPushReq.data =
                        align_store_data(pipeReg[i].subType.memSubType, effAddr, dataB);
                    storeBuffer.StoreBufferPushReq.wstrb =
                        store_wstrb(pipeReg[i].subType.memSubType, effAddr);

                    self.nextMemToStage[i].valid = 1'b1;
                    self.nextMemToStage[i].Rd = pipeReg[i].Rd;
                    self.nextMemToStage[i].writeRd = 1'b0;
                    self.nextMemToStage[i].robIndex = pipeReg[i].robIndex;
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

                    if (storeBuffer.StoreBufferMatchOut.hit) begin
                        self.nextMemToStage[loadMetaPipe1.valid ? 1 : 0].valid = 1'b1;
                        self.nextMemToStage[loadMetaPipe1.valid ? 1 : 0].Rd = loadIssueMeta.wb.Rd;
                        self.nextMemToStage[loadMetaPipe1.valid ? 1 : 0].writeRd = loadIssueMeta.wb.writeRd;
                        self.nextMemToStage[loadMetaPipe1.valid ? 1 : 0].robIndex = loadIssueMeta.wb.robIndex;
                        self.nextMemToStage[loadMetaPipe1.valid ? 1 : 0].data =
                            extend_load_data(pipeReg[i].subType.memSubType,
                                             align_load_data(pipeReg[i].subType.memSubType,
                                                             effAddr,
                                                             storeBuffer.StoreBufferMatchOut.data));
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

        ctrl.exStallReq = loadReturnBlocked || loadAccessBlocked;
    end
endmodule
