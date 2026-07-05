`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8,
    parameter logic [31:0]              P_DRAM_ADDR_START   = 32'h8010_0000,
    parameter logic [31:0]              P_DRAM_ADDR_END     = 32'h8014_0000
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg
`ifdef VERILATOR_TB
    ,
    output logic [31:0]                         dbg_perip_addr ,
    output logic [31:0]                         dbg_perip_wdata,
    output logic [3:0]                          dbg_perip_mask ,
    output logic                                dbg_perip_wen,
    output logic [63:0]                         dbg_perf_cycle,
    output logic [63:0]                         dbg_perf_commit,
    output logic [63:0]                         dbg_perf_branch,
    output logic [63:0]                         dbg_perf_branch_miss
`endif
);

    // IROM
    logic [31:0] irom_addrA;
    logic [31:0] irom_addrB;
    logic [11:0] inst_addrA;
    logic [11:0] inst_addrB;
    logic [31:0] instructionA;
    logic [31:0] instructionB;
    logic irom_enaA;
    logic irom_enaB;

    // perip
    logic [31:0] perip_addr, perip_wdata, perip_rdata;
    logic perip_wen;
    logic [3:0] perip_mask;
`ifdef VERILATOR_TB
    logic [63:0] perf_cycle;
    logic [63:0] perf_commit;
    logic [63:0] perf_branch;
    logic [63:0] perf_branch_miss;
`endif

    // 16KB = 2^12 * 32bit
    assign inst_addrA = irom_addrA[13:2];
    assign inst_addrB = irom_addrB[13:2];

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


`ifdef CORE_NEW
    myCPU_core_new Core_cpu (
`else
    myCPU Core_cpu (
`endif
        .cpu_rst            (w_clk_rst),
        .cpu_clk            (w_cpu_clk),

        // Interface to IROM
        .irom_addrA         (irom_addrA),
        .irom_dataA         (instructionA),
        .irom_enaA          (irom_enaA),
        .irom_addrB         (irom_addrB),
        .irom_dataB         (instructionB),
        .irom_enaB          (irom_enaB),

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),     
        .perip_wen          (perip_wen),     
        .perip_mask         (perip_mask),   
        .perip_wdata        (perip_wdata),    
        .perip_rdata        (perip_rdata)
`ifdef VERILATOR_TB
        ,
        .dbg_perf_cycle      (perf_cycle),
        .dbg_perf_commit     (perf_commit),
        .dbg_perf_branch     (perf_branch),
        .dbg_perf_branch_miss(perf_branch_miss)
`endif
    );

    IROM_0 Mem_IROM (
        .addra      (inst_addrA),
        .clka       (w_cpu_clk),
        .ena        (irom_enaA),
        .douta      (instructionA),
        .addrb      (inst_addrB),
        .clkb       (w_cpu_clk),
        .enb        (irom_enaB),
        .doutb      (instructionB)
    );
    
    perip_bridge #(
        .P_DRAM_ADDR_START(P_DRAM_ADDR_START),
        .P_DRAM_ADDR_END  (P_DRAM_ADDR_END)
    ) bridge_inst (
        .clk				(w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr			(perip_addr),
        .perip_wdata		(perip_wdata),
        .perip_wen			(perip_wen),
        .perip_mask			(perip_mask),
        .perip_rdata		(perip_rdata),
        .virtual_sw_input   (virtual_sw_cpu_d2),
        .virtual_key_input  (virtual_key_cpu_d2),
        .virtual_seg_output	(virtual_seg),
        .virtual_led_output (virtual_led)
    );

`ifdef VERILATOR_TB
    assign dbg_perip_addr  = perip_addr;
    assign dbg_perip_wdata = perip_wdata;
    assign dbg_perip_mask  = perip_mask;
    assign dbg_perip_wen   = perip_wen;
    assign dbg_perf_cycle = perf_cycle;
    assign dbg_perf_commit = perf_commit;
    assign dbg_perf_branch = perf_branch;
    assign dbg_perf_branch_miss = perf_branch_miss;
`endif

endmodule
