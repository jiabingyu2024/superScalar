import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;
import ROBTypes::*;
import RecoveryTypes::*;

module WriteBackStage(
    ExecuteStageIF.WriteBackStage prev,
    WriteBackStageIF.WriteBackStage self,
    CtrlIF.WriteBackStage ctrl,
    RecoveryManagerIF.WriteBackStage recovery,
    BypassIF.WriteBackStage bypass,
    RegFileIF.WriteBackStage regFile,
    ROBIF.WriteBackStage rob,
    ReadyTableIF.WriteBackStage readyTable,
    IssueQueueIF.WriteBackStage issueQueue
);
    ExAluToWbPath aluPipeReg [INT_ISSUE_WIDTH];
    ExMemToWbPath memPipeReg [MEM_WB_WIDTH];
    ExMulToWbPath mulPipeReg [MUL_WB_WIDTH];
    ExBrcToWbPath brcPipeReg [INT_ISSUE_WIDTH];
    ExSysToWbPath sysPipeReg [INT_ISSUE_WIDTH];

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                aluPipeReg[i] <= '0;
                brcPipeReg[i] <= '0;
                sysPipeReg[i] <= '0;
            end
            for (int i = 0; i < MEM_WB_WIDTH; i++) begin
                memPipeReg[i] <= '0;
            end
            for (int i = 0; i < MUL_WB_WIDTH; i++) begin
                mulPipeReg[i] <= '0;
            end
        end else if (ctrl.wbPipe.flush) begin
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                aluPipeReg[i] <= '0;
                brcPipeReg[i] <= '0;
                sysPipeReg[i] <= '0;
            end
            for (int i = 0; i < MEM_WB_WIDTH; i++) begin
                memPipeReg[i] <= '0;
            end
            for (int i = 0; i < MUL_WB_WIDTH; i++) begin
                mulPipeReg[i] <= '0;
            end
        end else if (!ctrl.wbPipe.stall) begin
            aluPipeReg <= prev.nextAluToStage;
            memPipeReg <= prev.nextMemToStage;
            mulPipeReg <= prev.nextMulToStage;
            brcPipeReg <= prev.nextBrcToStage;
            sysPipeReg <= prev.nextSysToStage;
        end
    end

    always_comb begin
        ctrl.wbStallReq = 1'b0;
        ctrl.wbStageEmpty = 1'b1;
        recovery.writeBackRecoveryReq = '0;
        for (int i = 0; i < WB_PORT_NUM; i++) begin
            rob.RobDoneReq[i] = '0;
            bypass.wbForward[i] = '0;
            regFile.regFileWriteReq[i] = '0;
            readyTable.markReady[i] = '0;
            issueQueue.IssueWakeup[i] = '0;
        end
        begin
            int intPort;
            int memMulPort;

            intPort = 0;
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (aluPipeReg[i].valid && intPort < INT_ISSUE_WIDTH) begin
                    fill_port(intPort, 1'b1, aluPipeReg[i].Rd,
                          aluPipeReg[i].writeRd, aluPipeReg[i].data,
                          aluPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
                    intPort++;
                end
            end
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (brcPipeReg[i].valid && intPort < INT_ISSUE_WIDTH) begin
                    fill_port(intPort, 1'b1, brcPipeReg[i].Rd,
                          brcPipeReg[i].writeRd, brcPipeReg[i].data,
                          brcPipeReg[i].robIndex, 1'b0, 1'b0,
                          brcPipeReg[i].trueTargetPc, brcPipeReg[i].taken);
                    intPort++;
                end
            end
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (sysPipeReg[i].valid && intPort < INT_ISSUE_WIDTH) begin
                    fill_port(intPort, 1'b1, sysPipeReg[i].Rd,
                          sysPipeReg[i].writeRd, sysPipeReg[i].data,
                          sysPipeReg[i].robIndex, sysPipeReg[i].isSerial,
                          sysPipeReg[i].exception, sysPipeReg[i].trueTargetPc,
                          1'b0);
                    intPort++;
                end
            end

            memMulPort = INT_ISSUE_WIDTH;
            for (int i = 0; i < MEM_WB_WIDTH; i++) begin
                fill_port(memMulPort, memPipeReg[i].valid, memPipeReg[i].Rd,
                      memPipeReg[i].writeRd, memPipeReg[i].data,
                      memPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
                memMulPort++;
            end
            for (int i = 0; i < MUL_WB_WIDTH; i++) begin
                fill_port(memMulPort, mulPipeReg[i].valid, mulPipeReg[i].Rd,
                      mulPipeReg[i].writeRd, mulPipeReg[i].data,
                      mulPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
                memMulPort++;
            end
        end
    end

    task automatic fill_port(
        input int port,
        input logic valid,
        input PhyRegNumPath rd,
        input logic writeRd,
        input DataPath data,
        input RobIndexPath robIndex,
        input logic isSerial,
        input logic exception,
        input PcPath trueTargetPc,
        input logic taken
    );
        logic fire;

        fire = valid && !ctrl.wbPipe.flush && !ctrl.wbPipe.stall;

        rob.RobDoneReq[port].valid = fire;
        rob.RobDoneReq[port].robIndex = robIndex;
        rob.RobDoneReq[port].isSerial = isSerial;
        rob.RobDoneReq[port].exception = exception;
        rob.RobDoneReq[port].trueTargetPc = trueTargetPc;
        rob.RobDoneReq[port].taken = taken;

        bypass.wbForward[port].valid = fire && writeRd;
        bypass.wbForward[port].writeRd = writeRd;
        bypass.wbForward[port].rd = rd;
        bypass.wbForward[port].data = data;
        bypass.wbForward[port].robIndex = robIndex;

        regFile.regFileWriteReq[port].enaWrite = fire && writeRd;
        regFile.regFileWriteReq[port].regIndex = rd;
        regFile.regFileWriteReq[port].data = data;
        readyTable.markReady[port].valid = fire && writeRd && rd != '0;
        readyTable.markReady[port].phyRegNum = rd;
        issueQueue.IssueWakeup[port].valid = fire && writeRd && rd != '0;
        issueQueue.IssueWakeup[port].phyRegNum = rd;

        ctrl.wbStageEmpty &= !fire;
    endtask
endmodule
