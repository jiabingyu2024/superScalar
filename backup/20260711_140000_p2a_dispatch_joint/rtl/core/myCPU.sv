`timescale 1ns / 1ps

import CoreConfigPkg::*;
import CoreTypesPkg::*;

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
    output logic [63:0] dbg_perf_stall_load_use,
    output logic [63:0] dbg_perf_cond_branch,
    output logic [63:0] dbg_perf_cond_branch_miss,
    output logic [63:0] dbg_perf_jal,
    output logic [63:0] dbg_perf_jal_miss,
    output logic [63:0] dbg_perf_jalr,
    output logic [63:0] dbg_perf_jalr_miss,
    output logic [63:0] dbg_perf_frontend_stall_cycles,
    output logic [63:0] dbg_perf_id_stall_cycles,
    output logic [63:0] dbg_perf_rn_stall_cycles,
    output logic [63:0] dbg_perf_ds_stall_cycles,
    output logic [63:0] dbg_perf_is_stall_cycles,
    output logic [63:0] dbg_perf_rr_stall_cycles,
    output logic [63:0] dbg_perf_ex_stall_cycles,
    output logic [63:0] dbg_perf_wb_stall_cycles,
    output logic [63:0] dbg_perf_rob_full_cycles,
    output logic [63:0] dbg_perf_issue_queue_full_cycles,
    output logic [63:0] dbg_perf_int_issue_queue_full_cycles,
    output logic [63:0] dbg_perf_mem_issue_queue_full_cycles,
    output logic [63:0] dbg_perf_mul_issue_queue_full_cycles,
    output logic [63:0] dbg_perf_rob_head_not_done_cycles,
    output logic [63:0] dbg_perf_rob_head_not_done_int_cycles,
    output logic [63:0] dbg_perf_rob_head_not_done_mem_cycles,
    output logic [63:0] dbg_perf_rob_head_not_done_mul_cycles,
    output logic [63:0] dbg_perf_rob_head_not_done_other_cycles,
    output logic [63:0] dbg_perf_rob_head_store_commit_wait_cycles,
    output logic [63:0] dbg_perf_free_list_empty_cycles,
    output logic [63:0] dbg_perf_store_buffer_full_cycles,
    output logic [63:0] dbg_perf_serial_block_cycles,
    output logic [63:0] dbg_perf_mem_load_return_block_cycles,
    output logic [63:0] dbg_perf_mem_load_access_block_cycles,
    output logic [63:0] dbg_perf_store_commit_blocked_by_load_cycles,
    output logic [63:0] dbg_perf_recovery_cycles,
    output logic [63:0] dbg_perf_dispatch_width0_cycles,
    output logic [63:0] dbg_perf_dispatch_width1_cycles,
    output logic [63:0] dbg_perf_dispatch_width2_cycles,
    output logic [63:0] dbg_perf_issue_width0_cycles,
    output logic [63:0] dbg_perf_issue_width1_cycles,
    output logic [63:0] dbg_perf_issue_width2_cycles,
    output logic [63:0] dbg_perf_commit_width0_cycles,
    output logic [63:0] dbg_perf_commit_width1_cycles,
    output logic [63:0] dbg_perf_commit_width2_cycles,
    output logic [63:0] dbg_perf_int_issue_count,
    output logic [63:0] dbg_perf_mem_issue_count,
    output logic [63:0] dbg_perf_mul_issue_count,
    output logic [63:0] dbg_perf_mem_req_valid_cycles,
    output logic [63:0] dbg_perf_mem_partial_alias_cycles,
    output logic [63:0] dbg_perf_mem_no_alias_cycles,
    output logic [63:0] dbg_perf_mem_forward_cycles,
    output logic [63:0] dbg_perf_mem_iq_head_not_ready_cycles,
    output logic [63:0] dbg_perf_mem_iq_younger_ready_cycles,
    output logic [63:0] dbg_perf_mul_op_count,
    output logic [63:0] dbg_perf_div_op_count,
    output logic [63:0] dbg_perf_rem_op_count,
    output logic [63:0] dbg_perf_muldiv_busy_cycles,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_valid,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_pc,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_inst,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_wen,
    output logic [RETIRE_WIDTH-1:0][4:0]  dbg_commit_rd,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_wdata,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_load,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_store,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_mmio,
    output logic [RETIRE_WIDTH-1:0]       dbg_commit_is_trap,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_cause,
    output logic [RETIRE_WIDTH-1:0][31:0] dbg_commit_next_pc
`endif
);

    IromAccessIF iromAccess(cpu_clk, cpu_rst);
    DramAccessIF dromAccess(cpu_clk, cpu_rst);
    DebugIF      debugIF(cpu_clk, cpu_rst);
    PerfIF       perfIF(cpu_clk, cpu_rst);
    logic        cache_cpu_req_valid;
    logic        cache_cpu_req_ready;
    logic        cache_cpu_req_write;
    AddrPath     cache_cpu_req_addr;
    DataPath     cache_cpu_req_wdata;
    logic [3:0]  cache_cpu_req_wstrb;
    logic        cache_cpu_resp_valid;
    DataPath     cache_cpu_resp_rdata;
    logic [63:0] dcache_access;
    logic [63:0] dcache_miss;
    logic [63:0] dcache_stall;

    assign debugIF.halt = 1'b0;

    always_comb begin
        irom_addrA = iromAccess.iromAddr;
        irom_addrB = iromAccess.iromAddr + 32'd4;
        irom_enaA = iromAccess.ena;
        irom_enaB = iromAccess.ena;

        iromAccess.inst[0] = irom_dataA;
        iromAccess.inst[1] = irom_dataB;
    end

    assign cache_cpu_req_valid = dromAccess.readEn || dromAccess.writeEn;
    assign cache_cpu_req_write = dromAccess.writeEn;
    assign cache_cpu_req_addr = cache_cpu_req_valid ? dromAccess.accessAddr : '0;
    assign cache_cpu_req_wdata = dromAccess.writeData;
    assign cache_cpu_req_wstrb = dromAccess.writeEn ? dromAccess.writeMask : '0;

    CoreDCache u_dcache (
        .clk             (cpu_clk),
        .rst             (cpu_rst),
        .cpu_req_valid   (cache_cpu_req_valid),
        .cpu_req_ready   (cache_cpu_req_ready),
        .cpu_req_write   (cache_cpu_req_write),
        .cpu_req_addr    (cache_cpu_req_addr),
        .cpu_req_wdata   (cache_cpu_req_wdata),
        .cpu_req_wstrb   (cache_cpu_req_wstrb),
        .cpu_req_uncached(1'b0),
        .cpu_resp_valid  (cache_cpu_resp_valid),
        .cpu_resp_rdata  (cache_cpu_resp_rdata),
        .mem_req_valid   (dmem_req_valid),
        .mem_req_ready   (dmem_req_ready),
        .mem_req_write   (dmem_req_write),
        .mem_req_addr    (dmem_req_addr),
        .mem_req_wdata   (dmem_req_wdata),
        .mem_req_wstrb   (dmem_req_wstrb),
        .mem_req_uncached(dmem_req_uncached),
        .mem_resp_valid  (dmem_resp_valid),
        .mem_resp_rdata  (dmem_resp_rdata),
        .perf_access_o   (dcache_access),
        .perf_miss_o     (dcache_miss),
        .perf_stall_o    (dcache_stall)
    );

    always_comb begin
        dromAccess.readData = cache_cpu_resp_rdata;
        dromAccess.accessReady = dromAccess.writeEn ? cache_cpu_req_ready :
                                 cache_cpu_resp_valid;
    end

`ifdef VERILATOR_TB
    assign dbg_perf_cycle = perfIF.cycle;
    assign dbg_perf_commit = perfIF.commitCnt;
    assign dbg_perf_branch = perfIF.branchCnt;
    assign dbg_perf_branch_miss = perfIF.branchMissCnt;
    assign dbg_perf_load = 64'd0;
    assign dbg_perf_store = 64'd0;
    assign dbg_perf_dcache_access = dcache_access;
    assign dbg_perf_dcache_miss = dcache_miss;
    assign dbg_perf_stall_front = perfIF.frontendStallCycles;
    assign dbg_perf_stall_mem = perfIF.memLoadAccessBlockCycles +
                                perfIF.memLoadReturnBlockCycles +
                                dcache_stall;
    assign dbg_perf_stall_muldiv = 64'd0;
    assign dbg_perf_stall_load_use = 64'd0;
    assign dbg_perf_cond_branch = perfIF.condBranchCnt;
    assign dbg_perf_cond_branch_miss = perfIF.condBranchMissCnt;
    assign dbg_perf_jal = perfIF.jalCnt;
    assign dbg_perf_jal_miss = perfIF.jalMissCnt;
    assign dbg_perf_jalr = perfIF.jalrCnt;
    assign dbg_perf_jalr_miss = perfIF.jalrMissCnt;
    assign dbg_perf_frontend_stall_cycles = perfIF.frontendStallCycles;
    assign dbg_perf_id_stall_cycles = perfIF.idStallCycles;
    assign dbg_perf_rn_stall_cycles = perfIF.rnStallCycles;
    assign dbg_perf_ds_stall_cycles = perfIF.dsStallCycles;
    assign dbg_perf_is_stall_cycles = perfIF.isStallCycles;
    assign dbg_perf_rr_stall_cycles = perfIF.rrStallCycles;
    assign dbg_perf_ex_stall_cycles = perfIF.exStallCycles;
    assign dbg_perf_wb_stall_cycles = perfIF.wbStallCycles;
    assign dbg_perf_rob_full_cycles = perfIF.robFullCycles;
    assign dbg_perf_issue_queue_full_cycles = perfIF.issueQueueFullCycles;
    assign dbg_perf_int_issue_queue_full_cycles = perfIF.intIssueQueueFullCycles;
    assign dbg_perf_mem_issue_queue_full_cycles = perfIF.memIssueQueueFullCycles;
    assign dbg_perf_mul_issue_queue_full_cycles = perfIF.mulIssueQueueFullCycles;
    assign dbg_perf_rob_head_not_done_cycles = perfIF.robHeadNotDoneCycles;
    assign dbg_perf_rob_head_not_done_int_cycles = perfIF.robHeadNotDoneIntCycles;
    assign dbg_perf_rob_head_not_done_mem_cycles = perfIF.robHeadNotDoneMemCycles;
    assign dbg_perf_rob_head_not_done_mul_cycles = perfIF.robHeadNotDoneMulCycles;
    assign dbg_perf_rob_head_not_done_other_cycles = perfIF.robHeadNotDoneOtherCycles;
    assign dbg_perf_rob_head_store_commit_wait_cycles = perfIF.robHeadStoreCommitWaitCycles;
    assign dbg_perf_free_list_empty_cycles = perfIF.freeListEmptyCycles;
    assign dbg_perf_store_buffer_full_cycles = perfIF.storeBufferFullCycles;
    assign dbg_perf_serial_block_cycles = perfIF.serialBlockCycles;
    assign dbg_perf_mem_load_return_block_cycles = perfIF.memLoadReturnBlockCycles;
    assign dbg_perf_mem_load_access_block_cycles = perfIF.memLoadAccessBlockCycles;
    assign dbg_perf_store_commit_blocked_by_load_cycles = perfIF.storeCommitBlockedByLoadCycles;
    assign dbg_perf_recovery_cycles = perfIF.recoveryCycles;
    assign dbg_perf_dispatch_width0_cycles = perfIF.dispatchWidth0Cycles;
    assign dbg_perf_dispatch_width1_cycles = perfIF.dispatchWidth1Cycles;
    assign dbg_perf_dispatch_width2_cycles = perfIF.dispatchWidth2Cycles;
    assign dbg_perf_issue_width0_cycles = perfIF.issueWidth0Cycles;
    assign dbg_perf_issue_width1_cycles = perfIF.issueWidth1Cycles;
    assign dbg_perf_issue_width2_cycles = perfIF.issueWidth2Cycles;
    assign dbg_perf_commit_width0_cycles = perfIF.commitWidth0Cycles;
    assign dbg_perf_commit_width1_cycles = perfIF.commitWidth1Cycles;
    assign dbg_perf_commit_width2_cycles = perfIF.commitWidth2Cycles;
    assign dbg_perf_int_issue_count = perfIF.intIssueCount;
    assign dbg_perf_mem_issue_count = perfIF.memIssueCount;
    assign dbg_perf_mul_issue_count = perfIF.mulIssueCount;
    assign dbg_perf_mem_req_valid_cycles = perfIF.memReqValidCycles;
    assign dbg_perf_mem_partial_alias_cycles = perfIF.memPartialAliasCycles;
    assign dbg_perf_mem_no_alias_cycles = perfIF.memNoAliasCycles;
    assign dbg_perf_mem_forward_cycles = perfIF.memForwardCycles;
    assign dbg_perf_mem_iq_head_not_ready_cycles = perfIF.memIqHeadNotReadyCycles;
    assign dbg_perf_mem_iq_younger_ready_cycles = perfIF.memIqYoungerReadyCycles;
    assign dbg_perf_mul_op_count = perfIF.mulOpCount;
    assign dbg_perf_div_op_count = perfIF.divOpCount;
    assign dbg_perf_rem_op_count = perfIF.remOpCount;
    assign dbg_perf_muldiv_busy_cycles = perfIF.muldivBusyCycles;
`endif

    core u_core (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .iromAccess (iromAccess),
        .dromAccess (dromAccess),
        .debug      (debugIF),
        .perf       (perfIF)
`ifdef VERILATOR_TB
        ,
        .dbg_commit_valid  (dbg_commit_valid),
        .dbg_commit_pc     (dbg_commit_pc),
        .dbg_commit_inst   (dbg_commit_inst),
        .dbg_commit_wen    (dbg_commit_wen),
        .dbg_commit_rd     (dbg_commit_rd),
        .dbg_commit_wdata  (dbg_commit_wdata),
        .dbg_commit_is_load(dbg_commit_is_load),
        .dbg_commit_is_store(dbg_commit_is_store),
        .dbg_commit_is_mmio(dbg_commit_is_mmio),
        .dbg_commit_is_trap(dbg_commit_is_trap),
        .dbg_commit_cause  (dbg_commit_cause),
        .dbg_commit_next_pc(dbg_commit_next_pc)
`endif
    );

endmodule
