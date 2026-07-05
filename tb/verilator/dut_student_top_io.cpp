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
    return sample;
}

}  // namespace sim
