//------------------------------------------------------------------------------
// IssueQueueIF.sv
// 作用：定义 IssueQueue 的派发写入、发射读出和调度控制接口。
// 微架构定位：Dispatch 将 uop 的调度相关信息 push 进 IssueQueue；IssueStage 从
// ready entry 中 pop/issue。IssueQueue 只保存唤醒/选择所需的轻量信息，较大的
// 执行 payload 由 PayloadIF 管理。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;
import IssueTypes::*;


interface IssueQueueIF( input logic clk, rst );
    
    IssuePushReqPath        IssuePushReq[WAY_NUM];
    IssuePushResPath        IssuePushRes[WAY_NUM];

    IssuePopReqPath         IssuePopReq[WAY_NUM];
    IssuePopResPath         IssuePopRes[WAY_NUM];

    IssueFreeCountPath      IssueFreeCount;

    IssueCtrlPath           IssueCtrl;
    IssueWakeupPath         IssueWakeup[ISSUE_WAKEUP_PORT_NUM];

    // IssueCtrlPath           IssueCtrl;


    modport IssueQueue(
    input
        clk,
        rst,
        IssuePushReq,
        IssuePopReq,
        IssueWakeup,
        IssueCtrl,
    output
        IssuePushRes,
        IssuePopRes,
        IssueFreeCount 
    );


    modport DispatchStage(
    input
        IssuePushRes,
        IssueFreeCount,
    output
        IssuePushReq,
        IssueCtrl
    );

    modport IssueStage(

    input
        IssuePopRes,
    output
        IssuePopReq
    );

    modport WriteBackStage(
    output
        IssueWakeup
    );


endinterface : IssueQueueIF
