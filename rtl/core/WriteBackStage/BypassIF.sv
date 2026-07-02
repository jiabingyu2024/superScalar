//------------------------------------------------------------------------------
// BypassIF.sv
// 作用：定义 WB-only 前递网络接口。
// 微架构定位：RegReadStage 先把 PRF 读出的操作数写入 RR/EX 流水寄存器；各
// ExecuteStage 在执行前用源物理寄存器号查询 bypass，Bypass 只从 WriteBackStage
// 提供的 wbForward 中匹配最新结果并返回 hit/data。该接口不从 EX stage 直接前递。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

interface BypassIF(input logic clk, rst);

    BypassReadReqPath aluReadReq [BYPASS_READ_PORT_NUM];
    BypassReadReqPath memReadReq [BYPASS_READ_PORT_NUM];
    BypassReadReqPath mulReadReq [BYPASS_READ_PORT_NUM];
    BypassReadReqPath brcReadReq [BYPASS_READ_PORT_NUM];
    BypassReadReqPath sysReadReq [BYPASS_READ_PORT_NUM];

    BypassReadResPath aluReadRes [BYPASS_READ_PORT_NUM];
    BypassReadResPath memReadRes [BYPASS_READ_PORT_NUM];
    BypassReadResPath mulReadRes [BYPASS_READ_PORT_NUM];
    BypassReadResPath brcReadRes [BYPASS_READ_PORT_NUM];
    BypassReadResPath sysReadRes [BYPASS_READ_PORT_NUM];

    BypassWritePath wbForward  [BYPASS_WB_PORT_NUM];

    modport Bypass(
        input
            clk,
            rst,
            aluReadReq,
            memReadReq,
            mulReadReq,
            brcReadReq,
            sysReadReq,
            wbForward,
        output
            aluReadRes,
            memReadRes,
            mulReadRes,
            brcReadRes,
            sysReadRes
    );

    modport ExecuteAluStage(
        input
            aluReadRes,
        output
            aluReadReq
    );

    modport ExecuteMemStage(
        input
            memReadRes,
        output
            memReadReq
    );

    modport ExecuteMulStage(
        input
            mulReadRes,
        output
            mulReadReq
    );

    modport ExecuteBrcStage(
        input
            brcReadRes,
        output
            brcReadReq
    );

    modport ExecuteSysStage(
        input
            sysReadRes,
        output
            sysReadReq
    );

    modport WriteBackStage(
        output
            wbForward
    );

endinterface : BypassIF
