import CoreConfigPkg::*;
import CoreTypesPkg::*;

interface IromAccessIF(input logic clk, rst);
    logic ena;
    PcPath iromAddr;
    InstPath inst [FETCH_WIDTH-1:0];

    modport frontend(
        input  inst,
        output ena,
        output iromAddr
    );

    modport core(
        input  inst,
        output ena,
        output iromAddr
    );

    modport IROM(
        input  ena,
        input  iromAddr,
        output inst
    );
endinterface : IromAccessIF
