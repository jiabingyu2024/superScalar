//------------------------------------------------------------------------------
// RegFileIF.sv
// 作用：定义物理寄存器堆 PRF 的读写端口。
// 微架构定位：ReadRegStage 通过多读端口读取源物理寄存器；WriteBackStage/执行
// 结果通过多写端口写回目的物理寄存器。PRF 只保存物理寄存器值，不处理 rename、
// 提交释放或异常恢复。
//------------------------------------------------------------------------------

import  BasicTypes::*;
import  PipelineTypes::*;
import  ReadRegTypes::*;

interface   RegFileIF( input logic clk, rst );

    RegFileReadResPath regFileReadRes [REGFILE_READ_PORT_NUM];
    RegFileWriteReqPath regFileWriteReq [REGFILE_WRITE_PORT_NUM];

    RegFileReadReqPath regFileReadReq [REGFILE_READ_PORT_NUM];

    modport RegFile(
        input
            clk,
            rst,
            regFileReadReq,
            regFileWriteReq,
        output
            regFileReadRes
    );

    modport ReadRegStage(
        input
            regFileReadRes,
        output
            regFileReadReq
    );

    modport WriteBackStage(
        output
            regFileWriteReq
    );


endinterface
