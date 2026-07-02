//------------------------------------------------------------------------------
// CommitStageIf.sv
// 作用：定义 CommitStage 对外观测/性能统计用的提交事件接口。
// 微架构定位：真正的提交动作通过 ROBIF、ArchRATIF、SpecRATIF、FreeListIF、
// StoreBufferIF 和 RecoveryManagerIF 完成；本接口只记录每周期提交有效、提交 PC、
// 异常和分支错误等 trace/perf 信息，避免和恢复请求接口重复。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;


interface CommitStageIF( input logic clk, rst );

    logic  commitValid [WAY_NUM];
    PcPath commitPc    [WAY_NUM];
    logic  commitException;
    logic  commitBranchMiss;


    modport CommitStage(
    input
        clk,
        rst,
    output 
        commitValid,
        commitPc,
        commitException,
        commitBranchMiss
    );

    modport Perf(
    input
        commitValid,
        commitPc,
        commitException,
        commitBranchMiss
    );
    
endinterface
