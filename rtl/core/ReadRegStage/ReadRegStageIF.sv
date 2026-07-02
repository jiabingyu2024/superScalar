//------------------------------------------------------------------------------
// ReadRegStageIF.sv
// 作用：定义 RR->EX 各执行管线的操作数 payload 接口。
// 微架构定位：ReadRegStage 根据 Issue 结果读取物理寄存器堆，并按 ALU/MEM/MUL/
// BRC/SYS 五类执行管线拆分输出到 RR/EX 流水寄存器。WB-only bypass 不在 RR 级
// 最终选择，而是在 EX 执行前由各 ExecuteStage 查询 BypassIF 完成。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;


interface ReadRegStageIF( input logic clk, rst );

    RrToExAluPath nextToAluStage [WAY_NUM];
    RrToExMemPath nextToMemStage [WAY_NUM];
    RrToExMulPath nextToMulStage [WAY_NUM];
    RrToExBrcPath nextToBrcStage [WAY_NUM];
    RrToExSysPath nextToSysStage [WAY_NUM];


    modport ReadRegStage(
        input
            clk,
            rst,
        output
            nextToAluStage,
            nextToMemStage,
            nextToMulStage,
            nextToBrcStage,
            nextToSysStage
    );

    modport ExecuteAluStage(
        input
            nextToAluStage
    );

    modport ExecuteMemStage(
        
        input
            nextToMemStage
    );

    modport ExecuteMulStage(
        input
            nextToMulStage
    );

    modport ExecuteBrcStage(
        input
            nextToBrcStage
    );

    modport ExecuteSysStage(
        input
            nextToSysStage  
    );

    


endinterface
