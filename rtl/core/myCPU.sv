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

    logic        dcache_mem_req_valid;
    logic        dcache_mem_req_ready;
    logic        dcache_mem_req_write;
    logic [31:0] dcache_mem_req_addr;
    logic [31:0] dcache_mem_req_wdata;
    logic [3:0]  dcache_mem_req_wstrb;
    logic        dcache_mem_req_uncached;
    logic        mem_req_slot_ready;
    logic        mem_req_valid_q;
    logic        mem_req_write_q;
    logic [31:0] mem_req_addr_q;
    logic [31:0] mem_req_wdata_q;
    logic [3:0]  mem_req_wstrb_q;
    logic        mem_req_uncached_q;
    logic        mem_resp_valid_q;
    logic [31:0] mem_resp_rdata_q;

    logic [63:0] perf_cycle_q;
    logic [63:0] perf_dcache_access;
    logic [63:0] perf_dcache_miss;
    logic [63:0] perf_stall_mem;
`ifdef VERILATOR_TB
    logic [63:0] core_perf_commit;
    logic [63:0] core_perf_branch;
    logic [63:0] core_perf_branch_miss;
    logic [63:0] core_perf_load;
    logic [63:0] core_perf_store;
    logic [63:0] core_perf_stall_front;
    logic [63:0] core_perf_stall_muldiv;
    logic [63:0] core_perf_stall_load_use;
`endif

    assign rst_n_int = ~cpu_rst;

    // One elastic request slot cuts the DCache/LS combinational path before
    // SoC decode and the high-fanout external BRAM controls. The downstream
    // bridge is normally always ready, so this still accepts one request/cycle.
    assign mem_req_slot_ready = !mem_req_valid_q || dmem_req_ready;
    assign dcache_mem_req_ready = mem_req_slot_ready;
    assign dmem_req_valid    = mem_req_valid_q;
    assign dmem_req_write    = mem_req_write_q;
    assign dmem_req_addr     = mem_req_addr_q;
    assign dmem_req_wdata    = mem_req_wdata_q;
    assign dmem_req_wstrb    = mem_req_wstrb_q;
    assign dmem_req_uncached = mem_req_uncached_q;

    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) begin
            mem_req_valid_q  <= 1'b0;
            mem_resp_valid_q <= 1'b0;
        end else begin
            if (mem_req_slot_ready) begin
                mem_req_valid_q <= dcache_mem_req_valid;
                if (dcache_mem_req_valid) begin
                    mem_req_write_q    <= dcache_mem_req_write;
                    mem_req_addr_q     <= dcache_mem_req_addr;
                    mem_req_wdata_q    <= dcache_mem_req_wdata;
                    mem_req_wstrb_q    <= dcache_mem_req_wstrb;
                    mem_req_uncached_q <= dcache_mem_req_uncached;
                end
            end

            mem_resp_valid_q <= dmem_resp_valid;
            if (dmem_resp_valid) begin
                mem_resp_rdata_q <= dmem_resp_rdata;
            end
        end
    end

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
        .dram_req_ready(dcache_cpu_ready),
        .dram_wen      (core_dram_wen),
        .dram_ren      (core_dram_ren),
        .dram_addr     (core_dram_addr),
        .dram_wdata    (core_dram_wdata),
        .dram_mask     (core_dram_mask)
`ifdef VERILATOR_TB
        ,
        .dbg_perf_commit         (core_perf_commit),
        .dbg_perf_branch         (core_perf_branch),
        .dbg_perf_branch_miss    (core_perf_branch_miss),
        .dbg_perf_load           (core_perf_load),
        .dbg_perf_store          (core_perf_store),
        .dbg_perf_stall_front    (core_perf_stall_front),
        .dbg_perf_stall_muldiv   (core_perf_stall_muldiv),
        .dbg_perf_stall_load_use (core_perf_stall_load_use)
`endif
    );

    DCache #(
        .LINE_COUNT      (256),
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
        .mem_req_valid     (dcache_mem_req_valid),
        .mem_req_ready     (dcache_mem_req_ready),
        .mem_req_write     (dcache_mem_req_write),
        .mem_req_addr      (dcache_mem_req_addr),
        .mem_req_wdata     (dcache_mem_req_wdata),
        .mem_req_wstrb     (dcache_mem_req_wstrb),
        .mem_req_uncached  (dcache_mem_req_uncached),
        .mem_resp_valid    (mem_resp_valid_q),
        .mem_resp_rdata    (mem_resp_rdata_q),
        .perf_dcache_access(perf_dcache_access),
        .perf_dcache_miss  (perf_dcache_miss),
        .perf_stall_mem    (perf_stall_mem)
    );

`ifdef VERILATOR_TB
    assign dbg_perf_cycle          = perf_cycle_q;
    assign dbg_perf_commit         = core_perf_commit;
    assign dbg_perf_branch         = core_perf_branch;
    assign dbg_perf_branch_miss    = core_perf_branch_miss;
    assign dbg_perf_load           = core_perf_load;
    assign dbg_perf_store          = core_perf_store;
    assign dbg_perf_dcache_access  = perf_dcache_access;
    assign dbg_perf_dcache_miss    = perf_dcache_miss;
    assign dbg_perf_stall_front    = core_perf_stall_front;
    assign dbg_perf_stall_mem      = perf_stall_mem;
    assign dbg_perf_stall_muldiv   = core_perf_stall_muldiv;
    assign dbg_perf_stall_load_use = core_perf_stall_load_use;
`endif

    logic unused_dcache_cpu_resp_valid;
    always_comb begin
        unused_dcache_cpu_resp_valid = dcache_cpu_resp_valid;
    end

endmodule
