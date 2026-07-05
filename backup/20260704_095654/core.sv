import BasicTypes::*;
import PipelineTypes::*;
import RenameTypes::*;
import IssueTypes::*;
import ReadRegTypes::*;
import ROBTypes::*;
import StoreBufferTypes::*;
import RecoveryTypes::*;

module core(
    input logic clk,
    input logic rst,

    // irom interface
    IromAccessIF.core iromAccess,

    // dram interface
    DramAccessIF dromAccess,

    //debug interface
    DebugIF.core debug,

    // performance counter interface
    PerfIF.core perf

);
    PreFetchStageIF    pfStageIF(clk, rst);
    FetchStageIF       ifStageIF(clk, rst);
    DecodeStageIF      idStageIF(clk, rst);
    RenameStageIF      rnStageIF(clk, rst);
    DispatchStageIF    dsStageIF(clk, rst);
    IssueStageIF       isStageIF(clk, rst);
    ReadRegStageIF     rrStageIF(clk, rst);
    ExecuteStageIF     exStageIF(clk, rst);
    WriteBackStageIF   wbStageIF(clk, rst);
    CommitStageIF      cmStageIF(clk, rst);
    CtrlIF             ctrlIF(clk, rst);
    RecoveryManagerIF  recoveryManagerIF(clk, rst);
    ROBIF              robIF(clk, rst);
    IssueQueueIF       issueQueueIF(clk, rst);
    PayloadIF          payloadIF(clk, rst);
    StoreBufferIF      storeBufferIF(clk, rst);
    SpecRATIF          specRATIF(clk, rst);
    ArchRATIF          archRATIF(clk, rst);
    FreeListIF         freeListIF(clk, rst);
    ReadyTableIF       readyTableIF(clk, rst);
    RegFileIF          regFileIF(clk, rst);
    BypassIF           bypassIF(clk, rst);

    assign readyTableIF.recoverReadyAll = recoveryManagerIF.recoveryInfo.valid &&
                                          recoveryManagerIF.recoveryInfo.backendFlush;
    //PF
    /*
    更新 PC 的选择逻辑
    */
    PreFetchStage preFetchStage( pfStageIF, iromAccess, ctrlIF, recoveryManagerIF );
        PC pc( pfStageIF);
        // 分支预测部分
        BPU bpu( pfStageIF, ifStageIF, ctrlIF, recoveryManagerIF);
    //IF   接口例化格式：(上一级，本级，控制，其他)
    /*

    */
    FetchStage fetchStage  (pfStageIF, ifStageIF, iromAccess, ctrlIF);
    
    //ID
    DecodeStage decodeStage (ifStageIF, idStageIF, ctrlIF);

    //RN
    // RenameStage 内完成 组内相关性检查  部分预测错误纠正recovery和 分支限制一条出错后的恢复ctrl
    RenameStage renameStage (idStageIF, rnStageIF, ctrlIF, specRATIF, freeListIF, readyTableIF, recoveryManagerIF);
        SpecRAT specRAT(specRATIF);
        ArchRAT archRAT(archRATIF);
        FreeList freeList(freeListIF);
        ReadyTable readyTable(readyTableIF);

    //DS dispatch
    DispatchStage dispatchStage (rnStageIF, dsStageIF, issueQueueIF, payloadIF, ctrlIF, robIF, storeBufferIF);
        ROB rob(robIF);
        IssueQueue issueQueue(issueQueueIF);
        Payload payload(payloadIF);
        StoreBuffer storeBuffer(storeBufferIF, dromAccess);
    //IS issue 
    IssueStage issueStage (dsStageIF, isStageIF, ctrlIF, issueQueueIF, payloadIF);

    //RR
    RegReadStage regReadStage (isStageIF, rrStageIF, regFileIF, ctrlIF);
        RegFile regFile(regFileIF);
    //EX
    //RW
    ExecuteAluStage executeAluStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteBrcStage executeBrcStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteMulStage executeMulStage (rrStageIF, exStageIF, ctrlIF, bypassIF);
    ExecuteMemStage executeMemStage (rrStageIF, exStageIF, ctrlIF, dromAccess, storeBufferIF, bypassIF);
    ExecuteSysStage executeSysStage (rrStageIF, exStageIF, ctrlIF, bypassIF);

    WriteBackStage writeBackStage (exStageIF, wbStageIF, ctrlIF, recoveryManagerIF,
                                   bypassIF, regFileIF, robIF, readyTableIF, issueQueueIF);

    Bypass bypass(bypassIF);
    //CM

    CommitStage cmStage (cmStageIF, recoveryManagerIF, ctrlIF, archRATIF, specRATIF, freeListIF, storeBufferIF, robIF);

    RecoveryManager recoveryManager(recoveryManagerIF,ctrlIF,specRATIF,freeListIF);

    Ctrl ctrl(ctrlIF,recoveryManagerIF);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            perf.cycle <= '0;
            perf.commitCnt <= '0;
            perf.branchCnt <= '0;
            perf.branchMissCnt <= '0;
        end else begin
            int commitThisCycle;
            commitThisCycle = 0;
            perf.cycle <= perf.cycle + 1'b1;
            for (int i = 0; i < WAY_NUM; i++) begin
                if (cmStageIF.commitValid[i]) begin
                    commitThisCycle++;
                end
            end
            perf.commitCnt <= perf.commitCnt + commitThisCycle;
            if (recoveryManagerIF.commitBranchUpdateValid) begin
                perf.branchCnt <= perf.branchCnt + 1'b1;
            end
            if (cmStageIF.commitBranchMiss) begin
                perf.branchMissCnt <= perf.branchMissCnt + 1'b1;
            end
        end
    end

endmodule
