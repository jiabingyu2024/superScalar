//------------------------------------------------------------------------------
// IssueStageIF.sv
// 作用：定义 IS->RR 的发射结果接口。
// 微架构定位：IssueStage 从 IssueQueue 中选择 ready uop，结合 Payload 存储读取
// 执行所需控制信息，形成送往 ReadRegStage 的 IsToRrPath。Issue 只做选择和发射，
// 不读物理寄存器、不执行功能单元。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;


interface IssueStageIF( input logic clk, rst );

    IsToRrPath nextStage [WAY_NUM];

    modport IssueStage(
    input
        clk,
        rst,
    output
        nextStage
    );

    modport ReadRegStage(
    input
        nextStage
    );

    

endinterface
