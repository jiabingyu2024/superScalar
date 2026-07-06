//------------------------------------------------------------------------------
// PayloadIF.sv
// 作用：定义 Payload 存储的 push/pop 接口。
// 微架构定位：Payload 保存 IssueQueue 不适合重复携带的执行静态信息，例如 PC、
// 预测信息、CSR、立即数、操作类型等。Dispatch 写入 payload，Issue 发射时按
// payloadIndex 读取，与 IssueQueue entry 组合成 IS->RR payload。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;
import  IssueTypes::*;

interface PayloadIF( input logic clk, rst );

    PayloadPopReqPath        PayloadPopReq[WAY_NUM];
    PayloadPopResPath        PayloadPopRes[WAY_NUM];

    PayloadPushReqPath       PayloadPushReq[WAY_NUM];
    PayloadPushResPath       PayloadPushRes[WAY_NUM];
    logic                    flush;

    modport Payload(
        input
            clk,
            rst,
            PayloadPopReq,
            PayloadPushReq,
            flush,
        output
            PayloadPopRes,
            PayloadPushRes
    );

    modport DispatchStage(
        input
            PayloadPushRes,
        output
            PayloadPushReq,
            flush
    );

    modport IssueStage(
        input
            PayloadPopRes,
        output
            PayloadPopReq
    );


endinterface
