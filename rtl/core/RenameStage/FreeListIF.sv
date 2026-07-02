
//------------------------------------------------------------------------------
// FreeListIF.sv
// 作用：定义物理寄存器 FreeList 的分配、释放和 checkpoint 恢复接口。
// 微架构定位：RenameStage 为目的寄存器分配新物理寄存器；CommitStage 在指令
// 有序退休后释放旧物理寄存器；RecoveryManager 在错误预测/异常时恢复 FreeList
// checkpoint。FreeList 的可用数量会反馈给 Ctrl/前端形成资源阻塞。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;
import RenameTypes::*;

interface FreeListIF( input logic clk, rst );

    //FreeList接口
    FreeListAllocPath   freeListAlloc[WAY_NUM];
    FreeListFreePath    freeListFree[WAY_NUM];
    logic               freeListAllocReq[WAY_NUM];
    FreeListCountPath   freeListCount; //FreeList剩余物理寄存器数量
    ChkptCreatePath     freeListChkptCreate;
    logic               freeListChkptCreateEn;
    WayNumPath          freeListChkptBranchWay;
    ChkptRecoveryPath   freeListChkptRecover;
    ChkptFreePath       freeListChkptFree;

    modport FreeList(
    input
        clk,
        rst,
        freeListAllocReq,
        freeListFree,
        freeListChkptCreateEn,
        freeListChkptBranchWay,
        freeListChkptRecover,
        freeListChkptFree,
    output
        freeListAlloc,
        freeListCount,
        freeListChkptCreate
    );


    modport RenameStage(
    input
        freeListAlloc,
        freeListCount,
        freeListChkptCreate,
    output
        freeListAllocReq,
        freeListChkptCreateEn,
        freeListChkptBranchWay
    );
    
    modport CommitStage(
    output
        freeListFree,
        freeListChkptFree
    );

    modport RecoveryManager(
    output
        freeListChkptRecover
    );
    

endinterface
