`timescale 1ns / 1ps
`include "cpu_defines.svh"

//------------------------------------------------------------------------------
// CPU wrapper
//
// Exposes the existing SoC dmem_req/dmem_resp ready-valid interface and inserts
// a blocking DCache between that port and the current five-stage in-order core.
// The core still sees the historical M1 request / M2 read-data contract; the
// cache's cpu_req_ready freezes M1 and upstream stages on misses or uncached
// reads until the returned data is correctly aligned.
//------------------------------------------------------------------------------
module myCPU (
    input  logic        cpu_rst,
    input  logic        cpu_clk,

    // Instruction ROM interface
    output logic [31:0] irom_addr,
    input  logic [31:0] irom_data,
    output logic        irom_ena,

    // Data memory / peripheral interface
    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    output logic        dmem_req_uncached,
    input  logic        dmem_resp_valid,
    input  logic [31:0] dmem_resp_rdata

`ifdef VERILATOR_TB
    ,
    output logic [63:0] dbg_perf_cycle,
    output logic [63:0] dbg_perf_commit,
    output logic [63:0] dbg_perf_branch,
    output logic [63:0] dbg_perf_branch_miss,
    output logic [63:0] dbg_perf_load,
    output logic [63:0] dbg_perf_store,
    output logic [63:0] dbg_perf_dcache_access,
    output logic [63:0] dbg_perf_dcache_miss,
    output logic [63:0] dbg_perf_stall_front,
    output logic [63:0] dbg_perf_stall_mem,
    output logic [63:0] dbg_perf_stall_muldiv,
    output logic [63:0] dbg_perf_stall_load_use
`endif
);

    logic        rst_n_int;

    logic        core_dram_wen;
    logic        core_dram_ren;
    logic [31:0] core_dram_addr;
    logic [31:0] core_dram_wdata;
    logic [3:0]  core_dram_mask;

    logic        dcache_cpu_ready;
    logic        dcache_cpu_resp_valid;
    logic [31:0] dcache_cpu_rdata;
    logic        dcache_fast_valid;
    logic [31:0] dcache_fast_rdata;

    logic [63:0] perf_cycle_q;
    logic [63:0] perf_dcache_access;
    logic [63:0] perf_dcache_miss;
    logic [63:0] perf_stall_mem;

    assign rst_n_int = ~cpu_rst;

    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            perf_cycle_q <= 64'd0;
        end else begin
            perf_cycle_q <= perf_cycle_q + 64'd1;
        end
    end

    core u_core (
        .clk           (cpu_clk),
        .rst_n         (rst_n_int),
        .irom_data     (irom_data),
        .irom_addr     (irom_addr),
        .irom_ena      (irom_ena),
        .dram_rdata    (dcache_cpu_rdata),
        .dram_fast_valid(dcache_fast_valid),
        .dram_fast_rdata(dcache_fast_rdata),
        .dram_req_ready(dcache_cpu_ready),
        .dram_wen      (core_dram_wen),
        .dram_ren      (core_dram_ren),
        .dram_addr     (core_dram_addr),
        .dram_wdata    (core_dram_wdata),
        .dram_mask     (core_dram_mask)
    );

    DCache #(
        .LINE_COUNT      (512),
        .CACHE_ADDR_START(32'h8010_0000),
        .CACHE_ADDR_END  (32'h8014_0000)
    ) u_dcache (
        .clk               (cpu_clk),
        .rst               (cpu_rst),
        .cpu_req_valid     (core_dram_wen | core_dram_ren),
        .cpu_req_ready     (dcache_cpu_ready),
        .cpu_req_write     (core_dram_wen),
        .cpu_req_addr      (core_dram_addr),
        .cpu_req_wdata     (core_dram_wdata),
        .cpu_req_wstrb     (core_dram_mask),
        .cpu_req_uncached  (1'b0),
        .cpu_resp_valid    (dcache_cpu_resp_valid),
        .cpu_resp_rdata    (dcache_cpu_rdata),
        .cpu_fast_valid    (dcache_fast_valid),
        .cpu_fast_rdata    (dcache_fast_rdata),
        .mem_req_valid     (dmem_req_valid),
        .mem_req_ready     (dmem_req_ready),
        .mem_req_write     (dmem_req_write),
        .mem_req_addr      (dmem_req_addr),
        .mem_req_wdata     (dmem_req_wdata),
        .mem_req_wstrb     (dmem_req_wstrb),
        .mem_req_uncached  (dmem_req_uncached),
        .mem_resp_valid    (dmem_resp_valid),
        .mem_resp_rdata    (dmem_resp_rdata),
        .perf_dcache_access(perf_dcache_access),
        .perf_dcache_miss  (perf_dcache_miss),
        .perf_stall_mem    (perf_stall_mem)
    );

`ifdef VERILATOR_TB
    assign dbg_perf_cycle          = perf_cycle_q;
    assign dbg_perf_commit         = 64'd0;
    assign dbg_perf_branch         = 64'd0;
    assign dbg_perf_branch_miss    = 64'd0;
    assign dbg_perf_load           = 64'd0;
    assign dbg_perf_store          = 64'd0;
    assign dbg_perf_dcache_access  = perf_dcache_access;
    assign dbg_perf_dcache_miss    = perf_dcache_miss;
    assign dbg_perf_stall_front    = 64'd0;
    assign dbg_perf_stall_mem      = perf_stall_mem;
    assign dbg_perf_stall_muldiv   = 64'd0;
    assign dbg_perf_stall_load_use = 64'd0;
`endif

    logic unused_dcache_cpu_resp_valid;
    always_comb begin
        unused_dcache_cpu_resp_valid = dcache_cpu_resp_valid;
    end

endmodule
