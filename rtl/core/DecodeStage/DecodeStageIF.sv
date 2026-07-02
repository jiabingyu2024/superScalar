//------------------------------------------------------------------------------
// DecodeStageIF.sv
// 作用：定义 ID->RN 的译码后 payload 接口。
// 微架构定位：DecodeStage 对 WAY_NUM 条指令并行译码，输出逻辑寄存器、立即数、
// CSR、执行管线类型和 serial 标记。RenameStage 后续负责物理寄存器映射、组内
// 相关性处理和 checkpoint 创建；Decode 不拥有投机状态。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;
import  DecodeTypes::*;


interface DecodeStageIF ( input logic clk, rst );

    IdToRnPath nextStage [WAY_NUM];

    // ID Stage
    modport DecodeStage(
        input
            clk,
            rst,
        output
            nextStage
    );
    
    modport RenameStage(
        input
            nextStage
    );

endinterface
