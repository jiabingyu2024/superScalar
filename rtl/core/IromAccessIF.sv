//------------------------------------------------------------------------------
// IromAccessIF.sv
// 作用：定义前端到指令存储器的访问接口。
// 微架构定位：PreFetch/Fetch 侧输出取指使能和取指地址，IROM 返回 WAY_NUM 条指令。
// 该接口只描述存储器访问通道，不承载分支预测、译码、flush 或流水级 valid 信息。
//------------------------------------------------------------------------------


import BasicTypes::*;


interface IromAccessIF (input logic clk, rst );

    logic ena;
    PcPath iromAddr;
    InstPath inst [WAY_NUM-1:0];

    modport PreFetchStage(
        input
            inst,
        output
            ena,
            iromAddr
    );

    modport core(
        input
            inst,
        output
            ena,
            iromAddr
    );

    modport IROM(
        input
            ena,
            iromAddr,
        output
            inst
    );


endinterface
