
//------------------------------------------------------------------------------
// PreFetchStageIF.sv
// 作用：定义 PC 寄存器、分支预测结果和 PF->IF 取指地址 payload 的接口。
// 微架构定位：PreFetchStage 在顺序 PC、BPU 预测 PC、Recovery redirect PC 中选择
// 下一拍 PC，并向 Fetch/IROM 发起取指。PC 子模块只保存 pcOut，BPU 只提供预测
// 结果；真正的全局恢复控制来自 RecoveryManagerIF。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;

interface PreFetchStageIF ( input logic clk, rst );

    // PC
    PcPath pc;
    PcPath pcIn;
    PcPath pcOut;
    PcPath predictPc;

    logic  pcWe;

    // // System
    // PcPath interruptPC; // 中断处理程序入口地址
    // logic  interrupt;   // 中断信号
    
    // branchPredictor 
    BpuPrdPath bpuResult[WAY_NUM];  // 来自分支预测器的预测结果

    //FetchStage 
    PfToIfPath nextStage [WAY_NUM];
    

    // PC
    modport PC(
        input 
            clk, rst, pcWe, pcIn,
        output
            pcOut
    );

    // PreFetchStage
    modport PreFetchStage(
        input
            clk,
            rst,
            pcOut,
            bpuResult,
            // interrupt,
            // interruptPC,
        output
            pcWe,
            pcIn,
            predictPc,
            nextStage
    );

    modport FetchStage(
        input
            nextStage
    );

    modport BPU(
        input
            pcOut,
            nextStage,
        output
            bpuResult
    );
    

endinterface
