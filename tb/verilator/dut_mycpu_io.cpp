#include "dut_mycpu_io.h"

#include "VmyCPU.h"

namespace sim {

void drive_mycpu_inputs(VmyCPU& top, const MemoryModel& mem) {
    top.irom_dataA = mem.irom_data_a();
    top.irom_dataB = mem.irom_data_b();
    top.perip_rdata = mem.current_perip_rdata();
}

Request capture_mycpu_request(const VmyCPU& top) {
    Request req;
    req.irom_addr_a = top.irom_addrA;
    req.irom_addr_b = top.irom_addrB;
    req.irom_ena_a = top.irom_enaA;
    req.irom_ena_b = top.irom_enaB;
    req.perip_addr = top.perip_addr;
    req.perip_wdata = top.perip_wdata;
    req.perip_mask = top.perip_mask & 0xfu;
    req.perip_wen = top.perip_wen;
    return req;
}

CorePerfSample capture_mycpu_perf(const VmyCPU& top) {
    CorePerfSample sample;
    sample.cycle = top.dbg_perf_cycle;
    sample.commit_count = top.dbg_perf_commit;
    sample.branch_count = top.dbg_perf_branch;
    sample.branch_miss_count = top.dbg_perf_branch_miss;
    sample.cond_branch_count = top.dbg_perf_cond_branch;
    sample.cond_branch_miss_count = top.dbg_perf_cond_branch_miss;
    sample.jal_count = top.dbg_perf_jal;
    sample.jal_miss_count = top.dbg_perf_jal_miss;
    sample.jalr_count = top.dbg_perf_jalr;
    sample.jalr_miss_count = top.dbg_perf_jalr_miss;
    sample.frontend_stall_cycles = top.dbg_perf_frontend_stall_cycles;
    sample.id_stall_cycles = top.dbg_perf_id_stall_cycles;
    sample.rn_stall_cycles = top.dbg_perf_rn_stall_cycles;
    sample.ds_stall_cycles = top.dbg_perf_ds_stall_cycles;
    sample.is_stall_cycles = top.dbg_perf_is_stall_cycles;
    sample.rr_stall_cycles = top.dbg_perf_rr_stall_cycles;
    sample.ex_stall_cycles = top.dbg_perf_ex_stall_cycles;
    sample.wb_stall_cycles = top.dbg_perf_wb_stall_cycles;
    sample.rob_full_cycles = top.dbg_perf_rob_full_cycles;
    sample.issue_queue_full_cycles = top.dbg_perf_issue_queue_full_cycles;
    sample.int_issue_queue_full_cycles = top.dbg_perf_int_issue_queue_full_cycles;
    sample.mem_issue_queue_full_cycles = top.dbg_perf_mem_issue_queue_full_cycles;
    sample.mul_issue_queue_full_cycles = top.dbg_perf_mul_issue_queue_full_cycles;
    sample.rob_head_not_done_cycles = top.dbg_perf_rob_head_not_done_cycles;
    sample.rob_head_not_done_int_cycles = top.dbg_perf_rob_head_not_done_int_cycles;
    sample.rob_head_not_done_mem_cycles = top.dbg_perf_rob_head_not_done_mem_cycles;
    sample.rob_head_not_done_mul_cycles = top.dbg_perf_rob_head_not_done_mul_cycles;
    sample.rob_head_not_done_other_cycles = top.dbg_perf_rob_head_not_done_other_cycles;
    sample.rob_head_store_commit_wait_cycles =
        top.dbg_perf_rob_head_store_commit_wait_cycles;
    sample.free_list_empty_cycles = top.dbg_perf_free_list_empty_cycles;
    sample.store_buffer_full_cycles = top.dbg_perf_store_buffer_full_cycles;
    sample.serial_block_cycles = top.dbg_perf_serial_block_cycles;
    sample.mem_load_return_block_cycles = top.dbg_perf_mem_load_return_block_cycles;
    sample.mem_load_access_block_cycles = top.dbg_perf_mem_load_access_block_cycles;
    sample.store_commit_blocked_by_load_cycles =
        top.dbg_perf_store_commit_blocked_by_load_cycles;
    sample.recovery_cycles = top.dbg_perf_recovery_cycles;
    sample.dispatch_width0_cycles = top.dbg_perf_dispatch_width0_cycles;
    sample.dispatch_width1_cycles = top.dbg_perf_dispatch_width1_cycles;
    sample.dispatch_width2_cycles = top.dbg_perf_dispatch_width2_cycles;
    sample.issue_width0_cycles = top.dbg_perf_issue_width0_cycles;
    sample.issue_width1_cycles = top.dbg_perf_issue_width1_cycles;
    sample.issue_width2_cycles = top.dbg_perf_issue_width2_cycles;
    sample.commit_width0_cycles = top.dbg_perf_commit_width0_cycles;
    sample.commit_width1_cycles = top.dbg_perf_commit_width1_cycles;
    sample.commit_width2_cycles = top.dbg_perf_commit_width2_cycles;
    sample.int_issue_count = top.dbg_perf_int_issue_count;
    sample.mem_issue_count = top.dbg_perf_mem_issue_count;
    sample.mul_issue_count = top.dbg_perf_mul_issue_count;
    return sample;
}

}  // namespace sim
