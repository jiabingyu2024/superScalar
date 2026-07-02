//------------------------------------------------------------------------------
// DispatchStageIF.sv
// 作用：定义 DS->IS 的派发后级间接口。
// 微架构定位：DispatchStage 负责把 rename 后的 uop 分配到 ROB、IssueQueue、
// Payload 和 StoreBuffer 等后端资源；成功派发后通过该接口通知 Issue 侧有新
// 调度窗口入口。资源协议本身分别由 ROBIF/IssueQueueIF/PayloadIF/StoreBufferIF 承担。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;

interface DispatchStageIF( input logic clk,rst);


    DsToIsPath nextStage [WAY_NUM];

    modport DispatchStage(
    input
        clk,
        rst,
    output
        nextStage
        
    );

    modport IssueStage(
    input
        nextStage
    );


endinterface
