`timescale 1ns / 1ps

import BasicTypes::*;

module myCPU (
    input  logic        cpu_rst,
    input  logic        cpu_clk,

    // Interface to IROM
    output logic [31:0] irom_addrA,
    input  logic [31:0] irom_dataA,
    output logic        irom_enaA,
    output logic [31:0] irom_addrB,
    input  logic [31:0] irom_dataB,
    output logic        irom_enaB,


    // Interface to DRAM & peripheral bridge
    output logic [31:0] perip_addr,
    output logic        perip_wen,
    output logic [3:0]  perip_mask,
    output logic [31:0] perip_wdata,
    input  logic [31:0] perip_rdata
`ifdef VERILATOR_TB
    ,
    output logic [63:0] dbg_perf_cycle,
    output logic [63:0] dbg_perf_commit,
    output logic [63:0] dbg_perf_branch,
    output logic [63:0] dbg_perf_branch_miss
`endif
);

    IromAccessIF iromAccess(cpu_clk, cpu_rst);
    DramAccessIF dromAccess(cpu_clk, cpu_rst);
    DebugIF      debugIF(cpu_clk, cpu_rst);
    PerfIF       perfIF(cpu_clk, cpu_rst);

    assign debugIF.halt = 1'b0;

    always_comb begin
        irom_addrA = iromAccess.iromAddr;
        irom_addrB = iromAccess.iromAddr + 32'd4;
        irom_enaA = iromAccess.ena;
        irom_enaB = iromAccess.ena;

        iromAccess.inst[0] = irom_dataA;
        iromAccess.inst[1] = irom_dataB;
    end

    always_comb begin
        perip_addr = (dromAccess.readEn || dromAccess.writeEn) ? dromAccess.accessAddr : '0;
        perip_wen = dromAccess.writeEn;
        perip_mask = dromAccess.writeEn ? dromAccess.writeMask : '0;
        perip_wdata = dromAccess.writeData;

        dromAccess.readData = perip_rdata;
        dromAccess.accessReady = 1'b1;
    end

`ifdef VERILATOR_TB
    assign dbg_perf_cycle = perfIF.cycle;
    assign dbg_perf_commit = perfIF.commitCnt;
    assign dbg_perf_branch = perfIF.branchCnt;
    assign dbg_perf_branch_miss = perfIF.branchMissCnt;
`endif

    core u_core (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .iromAccess (iromAccess),
        .dromAccess (dromAccess),
        .debug      (debugIF),
        .perf       (perfIF)
    );

endmodule
