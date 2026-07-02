//------------------------------------------------------------------------------
// FetchStageIF.sv
// 作用：定义 IF->ID 的取指结果接口。
// 微架构定位：FetchStage 接收 PF 送来的 PC/预测信息和 IROM 返回的指令，打一拍
// 形成 IfToIdPath。它不做译码、不改 PC，也不直接处理恢复；flush/stall 由 CtrlIF
// 作用在 IF 级流水寄存器 valid 上。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;


interface FetchStageIF (
    input logic clk,
    input logic rst
);
    // 
    PcPath pc;  //
    InstPath inst [WAY_NUM]; // 从指令缓存中取出的指令
    IfToIdPath nextStage [WAY_NUM];

    modport FetchStage(
        input
            clk,
            rst,
            inst,
        output
            nextStage
    );

    modport IromAccess(
        output
            inst
    );

    modport DecodeStage(
        input
            nextStage
    );


endinterface
