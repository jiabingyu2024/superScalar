`timescale 1ns / 1ps

module myCPU (
    input  logic        cpu_rst,
    input  logic        cpu_clk,

    output logic [31:0] irom_addr,
    input  logic [31:0] irom_data,
    output logic        irom_ena,

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
    logic [63:0] perf_cycle;
    logic [63:0] perf_commit;
    logic [63:0] perf_branch;
    logic [63:0] perf_branch_miss;
    logic [63:0] perf_load;
    logic [63:0] perf_store;
    logic [63:0] perf_dcache_access;
    logic [63:0] perf_dcache_miss;
    logic [63:0] perf_stall_front;
    logic [63:0] perf_stall_mem;
    logic [63:0] perf_stall_muldiv;
    logic [63:0] perf_stall_load_use;

    riscv_cpu cpu (
        .clk              (cpu_clk),
        .rst              (cpu_rst),
        .irom_addr        (irom_addr),
        .irom_data        (irom_data),
        .irom_ena         (irom_ena),
        .dmem_req_valid   (dmem_req_valid),
        .dmem_req_ready   (dmem_req_ready),
        .dmem_req_write   (dmem_req_write),
        .dmem_req_addr    (dmem_req_addr),
        .dmem_req_wdata   (dmem_req_wdata),
        .dmem_req_wstrb   (dmem_req_wstrb),
        .dmem_req_uncached(dmem_req_uncached),
        .dmem_resp_valid  (dmem_resp_valid),
        .dmem_resp_rdata  (dmem_resp_rdata),
        .perf_cycle       (perf_cycle),
        .perf_commit      (perf_commit),
        .perf_branch      (perf_branch),
        .perf_branch_miss (perf_branch_miss),
        .perf_load        (perf_load),
        .perf_store       (perf_store),
        .perf_dcache_access(perf_dcache_access),
        .perf_dcache_miss (perf_dcache_miss),
        .perf_stall_front (perf_stall_front),
        .perf_stall_mem   (perf_stall_mem),
        .perf_stall_muldiv(perf_stall_muldiv),
        .perf_stall_load_use(perf_stall_load_use)
    );

`ifdef VERILATOR_TB
    assign dbg_perf_cycle      = perf_cycle;
    assign dbg_perf_commit     = perf_commit;
    assign dbg_perf_branch     = perf_branch;
    assign dbg_perf_branch_miss = perf_branch_miss;
    assign dbg_perf_load       = perf_load;
    assign dbg_perf_store      = perf_store;
    assign dbg_perf_dcache_access = perf_dcache_access;
    assign dbg_perf_dcache_miss = perf_dcache_miss;
    assign dbg_perf_stall_front = perf_stall_front;
    assign dbg_perf_stall_mem = perf_stall_mem;
    assign dbg_perf_stall_muldiv = perf_stall_muldiv;
    assign dbg_perf_stall_load_use = perf_stall_load_use;
`endif
endmodule
