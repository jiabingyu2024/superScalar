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
    output logic [63:0] dbg_perf_mul_issue_count
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
        dmem_req_valid = dromAccess.readEn || dromAccess.writeEn;
        dmem_req_write = dromAccess.writeEn;
        dmem_req_addr = dmem_req_valid ? dromAccess.accessAddr : '0;
        dmem_req_wdata = dromAccess.writeData;
        dmem_req_wstrb = dromAccess.writeEn ? dromAccess.writeMask : '0;
        dmem_req_uncached = 1'b1;

        dromAccess.readData = dmem_resp_rdata;
        dromAccess.accessReady = dromAccess.writeEn ? dmem_req_ready : dmem_resp_valid;
    end

`ifdef VERILATOR_TB
    assign dbg_perf_cycle = perfIF.cycle;
    assign dbg_perf_commit = perfIF.commitCnt;
    assign dbg_perf_branch = perfIF.branchCnt;
    assign dbg_perf_branch_miss = perfIF.branchMissCnt;
    assign dbg_perf_load = 64'd0;
    assign dbg_perf_store = 64'd0;
    assign dbg_perf_dcache_access = 64'd0;
    assign dbg_perf_dcache_miss = 64'd0;
    assign dbg_perf_stall_front = perfIF.frontendStallCycles;
    assign dbg_perf_stall_mem = perfIF.memLoadAccessBlockCycles + perfIF.memLoadReturnBlockCycles;
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
