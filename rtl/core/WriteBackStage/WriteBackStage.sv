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
    ExAluToWbPath aluPipeReg [WAY_NUM];
    ExMemToWbPath memPipeReg [WAY_NUM];
    ExMulToWbPath mulPipeReg [WAY_NUM];
    ExBrcToWbPath brcPipeReg [WAY_NUM];
    ExSysToWbPath sysPipeReg [WAY_NUM];

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                aluPipeReg[i] <= '0;
                memPipeReg[i] <= '0;
                mulPipeReg[i] <= '0;
                brcPipeReg[i] <= '0;
                sysPipeReg[i] <= '0;
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
        for (int i = 0; i < WAY_NUM * 5; i++) begin
            rob.RobDoneReq[i] = '0;
            bypass.wbForward[i] = '0;
            regFile.regFileWriteReq[i] = '0;
            readyTable.markReady[i] = '0;
            issueQueue.IssueWakeup[i] = '0;
        end
        for (int i = 0; i < WAY_NUM; i++) begin
            int base;
            base = i * 5;
            fill_port(base + 0, aluPipeReg[i].valid, aluPipeReg[i].Rd,
                      aluPipeReg[i].writeRd, aluPipeReg[i].data,
                      aluPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
            fill_port(base + 1, memPipeReg[i].valid, memPipeReg[i].Rd,
                      memPipeReg[i].writeRd, memPipeReg[i].data,
                      memPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
            fill_port(base + 2, mulPipeReg[i].valid, mulPipeReg[i].Rd,
                      mulPipeReg[i].writeRd, mulPipeReg[i].data,
                      mulPipeReg[i].robIndex, 1'b0, 1'b0, '0, 1'b0);
            fill_port(base + 3, brcPipeReg[i].valid, brcPipeReg[i].Rd,
                      brcPipeReg[i].writeRd, brcPipeReg[i].data,
                      brcPipeReg[i].robIndex, 1'b0, 1'b0,
                      brcPipeReg[i].trueTargetPc, brcPipeReg[i].taken);
            fill_port(base + 4, sysPipeReg[i].valid, sysPipeReg[i].Rd,
                      sysPipeReg[i].writeRd, sysPipeReg[i].data,
                      sysPipeReg[i].robIndex, sysPipeReg[i].isSerial,
                      sysPipeReg[i].exception, sysPipeReg[i].trueTargetPc,
                      1'b0);
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
