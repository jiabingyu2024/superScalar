//------------------------------------------------------------------------------
// ExecuteStageIF.sv
// 作用：定义各 Execute pipe 到统一 WriteBackStage 的结果接口。
// 微架构定位：ALU/MEM/MUL/BRC/SYS 分别产生写回目的寄存器、ROB index、分支真实
// 结果或系统异常信息。WriteBackStage 汇总这些结果，写 PRF/旁路网络并通知 ROB
// done；恢复请求可由 WB/Commit 统一进入 RecoveryManager。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;


interface ExecuteStageIF( input logic clk, rst );

    ExAluToWbPath nextAluToStage [WAY_NUM];
    ExMemToWbPath nextMemToStage [WAY_NUM];
    ExMulToWbPath nextMulToStage [WAY_NUM];
    ExBrcToWbPath nextBrcToStage [WAY_NUM];
    ExSysToWbPath nextSysToStage [WAY_NUM];


    modport ExecuteAluStage(
        input
            clk,
            rst,
        output
            nextAluToStage
    );

    modport ExecuteMemStage(
        input
            clk,
            rst,
        output
            nextMemToStage
    );

    modport ExecuteMulStage(
        input
            clk,
            rst,
        output
            nextMulToStage
    );

    modport ExecuteBrcStage(
        input
            clk,
            rst,
        output
            nextBrcToStage
    );

    modport ExecuteSysStage(
        input
            clk,
            rst,
        output
            nextSysToStage
    );

    modport WriteBackStage(
        input
            nextAluToStage,
            nextMemToStage,
            nextMulToStage,
            nextBrcToStage,
            nextSysToStage
    );
    


endinterface
