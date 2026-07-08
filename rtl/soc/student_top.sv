`timescale 1ns / 1ps

module student_top #(
    parameter int unsigned              P_SW_CNT          = 64,
    parameter int unsigned              P_LED_CNT         = 32,
    parameter int unsigned              P_SEG_CNT         = 40,
    parameter int unsigned              P_KEY_CNT         = 8,
    parameter logic [31:0]              P_DRAM_ADDR_START = 32'h8010_0000,
    parameter logic [31:0]              P_DRAM_ADDR_END   = 32'h8014_0000
) (
    input  logic                         w_cpu_clk,
    input  logic                         w_clk_50Mhz,
    input  logic                         w_clk_rst,
    input  logic [P_KEY_CNT - 1:0]       virtual_key,
    input  logic [P_SW_CNT  - 1:0]       virtual_sw,

    output logic [P_LED_CNT - 1:0]       virtual_led,
    output logic [P_SEG_CNT - 1:0]       virtual_seg
`ifdef VERILATOR_TB
    ,
    output logic [31:0]                  dbg_perip_addr,
    output logic [31:0]                  dbg_perip_wdata,
    output logic [3:0]                   dbg_perip_mask,
    output logic                         dbg_perip_wen,
    output logic [63:0]                  dbg_perf_cycle,
    output logic [63:0]                  dbg_perf_commit,
    output logic [63:0]                  dbg_perf_branch,
    output logic [63:0]                  dbg_perf_branch_miss,
    output logic [63:0]                  dbg_perf_load,
    output logic [63:0]                  dbg_perf_store,
    output logic [63:0]                  dbg_perf_dcache_access,
    output logic [63:0]                  dbg_perf_dcache_miss,
    output logic [63:0]                  dbg_perf_stall_front,
    output logic [63:0]                  dbg_perf_stall_mem,
    output logic [63:0]                  dbg_perf_stall_muldiv,
    output logic [63:0]                  dbg_perf_stall_load_use
`endif
);
    logic [31:0] irom_addr;
    logic [11:0] irom_word_addr;
    logic [31:0] instruction;
    logic        irom_ena;

    logic        dmem_req_valid;
    logic        dmem_req_ready;
    logic        dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0]  dmem_req_wstrb;
    logic        dmem_req_uncached;
    logic        dmem_resp_valid;
    logic [31:0] dmem_resp_rdata;

    logic [P_SW_CNT-1:0]  virtual_sw_cpu_d1;
    logic [P_SW_CNT-1:0]  virtual_sw_cpu_d2;
    logic [P_KEY_CNT-1:0] virtual_key_cpu_d1;
    logic [P_KEY_CNT-1:0] virtual_key_cpu_d2;

    always_ff @(posedge w_cpu_clk) begin
        if (w_clk_rst) begin
            virtual_sw_cpu_d1  <= '0;
            virtual_sw_cpu_d2  <= '0;
            virtual_key_cpu_d1 <= '0;
            virtual_key_cpu_d2 <= '0;
        end else begin
            virtual_sw_cpu_d1  <= virtual_sw;
            virtual_sw_cpu_d2  <= virtual_sw_cpu_d1;
            virtual_key_cpu_d1 <= virtual_key;
            virtual_key_cpu_d2 <= virtual_key_cpu_d1;
        end
    end

    assign irom_word_addr = irom_addr[13:2];

    myCPU Core_cpu (
        .cpu_rst          (w_clk_rst),
        .cpu_clk          (w_cpu_clk),
        .irom_addr        (irom_addr),
        .irom_data        (instruction),
        .irom_ena         (irom_ena),
        .dmem_req_valid   (dmem_req_valid),
        .dmem_req_ready   (dmem_req_ready),
        .dmem_req_write   (dmem_req_write),
        .dmem_req_addr    (dmem_req_addr),
        .dmem_req_wdata   (dmem_req_wdata),
        .dmem_req_wstrb   (dmem_req_wstrb),
        .dmem_req_uncached(dmem_req_uncached),
        .dmem_resp_valid  (dmem_resp_valid),
        .dmem_resp_rdata  (dmem_resp_rdata)
`ifdef VERILATOR_TB
        ,
        .dbg_perf_cycle      (dbg_perf_cycle),
        .dbg_perf_commit     (dbg_perf_commit),
        .dbg_perf_branch     (dbg_perf_branch),
        .dbg_perf_branch_miss(dbg_perf_branch_miss),
        .dbg_perf_load       (dbg_perf_load),
        .dbg_perf_store      (dbg_perf_store),
        .dbg_perf_dcache_access(dbg_perf_dcache_access),
        .dbg_perf_dcache_miss(dbg_perf_dcache_miss),
        .dbg_perf_stall_front(dbg_perf_stall_front),
        .dbg_perf_stall_mem  (dbg_perf_stall_mem),
        .dbg_perf_stall_muldiv(dbg_perf_stall_muldiv),
        .dbg_perf_stall_load_use(dbg_perf_stall_load_use)
`endif
    );

    IROM_0 Mem_IROM (
        .addra(irom_word_addr),
        .clka (w_cpu_clk),
        .ena  (irom_ena),
        .douta(instruction)
    );

    SocMemBridge #(
        .P_DRAM_ADDR_START(P_DRAM_ADDR_START),
        .P_DRAM_ADDR_END  (P_DRAM_ADDR_END)
    ) mem_bridge (
        .clk               (w_cpu_clk),
        .cnt_clk           (w_clk_50Mhz),
        .rst               (w_clk_rst),
        .req_valid         (dmem_req_valid),
        .req_ready         (dmem_req_ready),
        .req_write         (dmem_req_write),
        .req_addr          (dmem_req_addr),
        .req_wdata         (dmem_req_wdata),
        .req_wstrb         (dmem_req_wstrb),
        .req_uncached      (dmem_req_uncached),
        .resp_valid        (dmem_resp_valid),
        .resp_rdata        (dmem_resp_rdata),
        .virtual_sw_input  (virtual_sw_cpu_d2),
        .virtual_key_input (virtual_key_cpu_d2),
        .virtual_seg_output(virtual_seg),
        .virtual_led_output(virtual_led)
    );

`ifdef VERILATOR_TB
    assign dbg_perip_addr  = dmem_req_valid ? dmem_req_addr : 32'd0;
    assign dbg_perip_wdata = dmem_req_wdata;
    assign dbg_perip_mask  = dmem_req_wstrb;
    assign dbg_perip_wen   = dmem_req_valid && dmem_req_write;
`endif
endmodule
