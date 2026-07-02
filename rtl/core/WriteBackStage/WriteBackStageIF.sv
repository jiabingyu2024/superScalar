//------------------------------------------------------------------------------
// WriteBackStageIF.sv
// 作用：定义 WriteBackStage 自身时钟复位 modport。
// 微架构定位：WriteBackStage 的真实副作用端口直接通过 ROBIF、RegFileIF 和
// BypassIF 输出；本接口不再重复保存 RobDoneReq，避免形成未消费的冗余信号。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;


interface WriteBackStageIF( input logic clk, rst );

    modport WriteBackStage(
        input
            clk,
            rst
    );

endinterface
