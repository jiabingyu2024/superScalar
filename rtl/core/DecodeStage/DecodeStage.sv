// 同时对WAY_NUM条指令进行解码，同时进行branch数量判断，和serial判断 ，限制同时送往下一阶段的指令中只能有一条branch,同时传出ctrl 信号请求stall



import BasicTypes::*;
import PipelineTypes::*;
import DecodeTypes::*;

module DecodeStage (
    FetchStageIF.DecodeStage    prev,
    DecodeStageIF.DecodeStage   self,
    CtrlIF.DecodeStage          ctrl
);

    IfToIdPath pipeReg [WAY_NUM];
    IdToRnPath nextStage [WAY_NUM];
    IdToRnPath decodedStage [WAY_NUM];
    IdToRnPath replaySlot;
    logic      replayValid;
    logic      idStallReqReg;
    logic      multiBranch;
    logic      multiStore;
    logic      serialSplit;
    logic      splitPacket;

    function automatic logic is_store_inst(input InstInfoPath instInfo);
        return instInfo.valid &&
               instInfo.tubeType == TUBE_TYPE_MEM &&
               (instInfo.SubType.memSubType inside
                 {MEM_SUBTYPE_SB, MEM_SUBTYPE_SH, MEM_SUBTYPE_SW});
    endfunction

    always_ff @(posedge self.clk) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
            replaySlot <= '0;
            replayValid <= 1'b0;
            idStallReqReg <= 1'b0;
        end else if (ctrl.idPipe.flush) begin
            replaySlot <= '0;
            replayValid <= 1'b0;
            idStallReqReg <= 1'b0;
        end else if (replayValid) begin
            if (!ctrl.rnPipe.stall) begin
                for (int i = 0; i < WAY_NUM; i++) begin
                    pipeReg[i] <= '0;
                end
                replaySlot <= '0;
                replayValid <= 1'b0;
                idStallReqReg <= 1'b0;
            end else begin
                idStallReqReg <= 1'b1;
            end
        end else if (splitPacket && !replayValid) begin
            if (!ctrl.rnPipe.stall) begin
                for (int i = 0; i < WAY_NUM; i++) begin
                    pipeReg[i] <= '0;
                end
                replaySlot <= decodedStage[1];
                replaySlot.valid <= decodedStage[1].valid && !ctrl.idPipe.flush;
                replayValid <= 1'b1;
            end
            idStallReqReg <= 1'b1;
        end 
        else if (!ctrl.idPipe.stall) begin
            pipeReg <= prev.nextStage; 
            replayValid <= 1'b0;
            idStallReqReg <= 1'b0;
        end
    end

    always_comb begin
        int validCount;
        int branchCount;
        int storeCount;
        int serialCount;

        ctrl.idStageEmpty = 1'b1;
        validCount = 0;
        branchCount = 0;
        storeCount = 0;
        serialCount = 0;

        for (int i = 0; i < WAY_NUM; i++) begin
            decodedStage[i] = '0;
            decodedStage[i].pc = pipeReg[i].pc;
            decodedStage[i].inst = pipeReg[i].inst;
            decodedStage[i].predInfo = pipeReg[i].predInfo;
            decodedStage[i].valid = pipeReg[i].valid && !ctrl.idPipe.flush;
            DecodeInst(pipeReg[i].inst, decodedStage[i].instInfo, decodedStage[i].lgcRegInfo, decodedStage[i].csrAddr);
            ImmGen(pipeReg[i].inst, decodedStage[i].imm);
            if (decodedStage[i].valid) begin
                validCount++;
            end
            if (decodedStage[i].valid && decodedStage[i].instInfo.valid &&
                decodedStage[i].instInfo.tubeType == TUBE_TYPE_BRC) begin
                branchCount++;
            end
            if (decodedStage[i].valid && is_store_inst(decodedStage[i].instInfo)) begin
                storeCount++;
            end
            if (decodedStage[i].valid && decodedStage[i].instInfo.isSerial) begin
                serialCount++;
            end
        end

        multiBranch = (branchCount > 1) && !ctrl.idPipe.flush;
        multiStore = (storeCount > 1) && !ctrl.idPipe.flush;
        serialSplit = (serialCount != 0) && (validCount > 1) && !ctrl.idPipe.flush;
        splitPacket = multiBranch || multiStore || serialSplit;
        ctrl.idStallReq = idStallReqReg || replayValid || splitPacket;

        for (int i = 0; i < WAY_NUM; i++) begin
            nextStage[i] = '0;
        end

        if (replayValid) begin
            nextStage[0] = replaySlot;
            nextStage[0].valid = replaySlot.valid && !ctrl.idPipe.flush;
        end else if (splitPacket) begin
            nextStage[0] = decodedStage[0];
            nextStage[0].valid = decodedStage[0].valid && !ctrl.idPipe.flush;
        end else begin
            for (int i = 0; i < WAY_NUM; i++) begin
                nextStage[i] = decodedStage[i];
            end
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            ctrl.idStageEmpty &= !nextStage[i].valid;
        end
    end

    assign self.nextStage = nextStage;


endmodule
