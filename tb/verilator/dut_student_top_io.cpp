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
    sample.load_count = top.dbg_perf_load;
    sample.store_count = top.dbg_perf_store;
    sample.dcache_access = top.dbg_perf_dcache_access;
    sample.dcache_miss = top.dbg_perf_dcache_miss;
    sample.stall_front = top.dbg_perf_stall_front;
    sample.stall_mem = top.dbg_perf_stall_mem;
    sample.stall_muldiv = top.dbg_perf_stall_muldiv;
    sample.stall_load_use = top.dbg_perf_stall_load_use;
    return sample;
}

}  // namespace sim
