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
    return sample;
}

}  // namespace sim
