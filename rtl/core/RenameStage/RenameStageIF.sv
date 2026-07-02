//------------------------------------------------------------------------------
// RenameStageIF.sv
// 作用：定义 RN->DS 的重命名后 payload 接口。
// 微架构定位：RenameStage 将逻辑寄存器映射为物理寄存器，申请新目的物理寄存器，
// 对分支创建 checkpoint，并把带物理寄存器号的 uop 送往 Dispatch。该接口只传
// 重命名结果，不直接写 ROB/IssueQueue。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;

interface RenameStageIF( input logic clk, rst );
    
    
    RnToDsPath nextStage [WAY_NUM];


    modport RenameStage(
    input
        clk,
        rst,
    output
        nextStage
    );

    modport DispatchStage(
    input
        nextStage
    );



endinterface : RenameStageIF
