#include "dut_student_top_io.h"

#include "Vstudent_top.h"

namespace sim {

void init_student_top_inputs(Vstudent_top& top) {
    top.w_cpu_clk = 0;
    top.w_clk_50Mhz = 0;
    top.w_clk_rst = 1;
    top.virtual_key = 0;
    top.virtual_sw = 0;
}

Request capture_student_top_request(const Vstudent_top& top) {
    Request req;
    req.perip_addr = top.dbg_perip_addr;
    req.perip_wdata = top.dbg_perip_wdata;
    req.perip_mask = top.dbg_perip_mask & 0xfu;
    req.perip_wen = top.dbg_perip_wen;
    return req;
}

CorePerfSample capture_student_top_perf(const Vstudent_top& top) {
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
    return sample;
}

}  // namespace sim
