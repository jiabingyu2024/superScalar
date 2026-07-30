#include "dut_mycpu_io.h"

#include "VmyCPU.h"

namespace sim {

void drive_mycpu_inputs(VmyCPU& top, const MemoryModel& mem) {
    top.timer_irq       = mem.machine_timer_irq();
    top.irom_data        = mem.irom_data_a();
    top.dmem_req_ready   = 1;
    top.dmem_resp_valid  = mem.current_dmem_resp_valid();
    top.dmem_resp_rdata  = mem.current_perip_rdata();
}

Request capture_mycpu_request(const VmyCPU& top) {
    Request req;
    req.irom_addr_a = top.irom_addr;
    req.irom_addr_b = top.irom_addr + 4u;
    req.irom_ena_a  = top.irom_ena;
    req.irom_ena_b  = false;
    req.perip_addr  = top.dmem_req_valid ? top.dmem_req_addr : 0;
    req.perip_wdata = top.dmem_req_wdata;
    req.perip_mask  = top.dmem_req_wstrb & 0xfu;
    req.perip_wen   = top.dmem_req_valid && top.dmem_req_write;
    return req;
}

CorePerfSample capture_mycpu_perf(const VmyCPU& top) {
    CorePerfSample sample;
    sample.cycle             = top.dbg_perf_cycle;
    sample.commit_count      = top.dbg_perf_commit;
    sample.branch_count      = top.dbg_perf_branch;
    sample.branch_miss_count = top.dbg_perf_branch_miss;
    sample.load_count        = top.dbg_perf_load;
    sample.store_count       = top.dbg_perf_store;
    sample.dcache_access     = top.dbg_perf_dcache_access;
    sample.dcache_miss       = top.dbg_perf_dcache_miss;
    sample.stall_front       = top.dbg_perf_stall_front;
    sample.stall_mem         = top.dbg_perf_stall_mem;
    sample.stall_muldiv      = top.dbg_perf_stall_muldiv;
    sample.stall_load_use    = top.dbg_perf_stall_load_use;
    return sample;
}

}  // namespace sim
