//------------------------------------------------------------------------------
// ArchRATIF.sv
// 作用：定义架构 RAT 的提交态更新接口。
// 微架构定位：ArchRAT 只在 CommitStage 有序退休时更新逻辑寄存器到物理寄存器的
// 架构映射，用于精确状态和异常恢复边界。RenameStage 不直接写 ArchRAT，避免
// 投机路径污染提交态。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;
import RenameTypes::*;

interface ArchRATIF( input logic clk, rst );

    // ArchRAT接口
    RATUpdatePath       archRATUpdate   [ARCHRAT_WRITE_PORT_NUM];

    
    modport ArchRAT(
        input 
            clk,
            rst,
            archRATUpdate
    );

    modport CommitStage(
        output 
            archRATUpdate 
    );

endinterface
