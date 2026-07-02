interface DebugIF(input logic clk, rst);
    logic halt;

    modport core(
        input halt
    );
endinterface : DebugIF
