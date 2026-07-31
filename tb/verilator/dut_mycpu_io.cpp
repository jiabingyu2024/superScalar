#include "dut_mycpu_io.h"

#include "VmyCPU.h"

namespace sim {

void drive_mycpu_inputs(VmyCPU& top, const MemoryModel& mem) {
    top.timer_irq = mem.machine_timer_irq();
    top.irom_dataA = mem.irom_data_a();
    top.irom_dataB = mem.irom_data_b();
    top.dmem_req_ready = 1;
    top.dmem_resp_valid = mem.current_dmem_resp_valid();
    top.dmem_resp_rdata = mem.current_perip_rdata();
}

Request capture_mycpu_request(const VmyCPU& top) {
    Request req;
    req.irom_addr_a = top.irom_addrA;
    req.irom_addr_b = top.irom_addrB;
    req.irom_ena_a = top.irom_enaA;
    req.irom_ena_b = top.irom_enaB;
    req.perip_addr = top.dmem_req_valid ? top.dmem_req_addr : 0;
    req.perip_wdata = top.dmem_req_wdata;
    req.perip_mask = top.dmem_req_wstrb & 0xfu;
    req.perip_wen = top.dmem_req_valid && top.dmem_req_write;
    return req;
}

CorePerfSample capture_mycpu_perf(const VmyCPU& top) {
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
    sample.mem_req_valid_cycles = top.dbg_perf_mem_req_valid_cycles;
    sample.mem_partial_alias_cycles = top.dbg_perf_mem_partial_alias_cycles;
    sample.mem_no_alias_cycles = top.dbg_perf_mem_no_alias_cycles;
    sample.mem_forward_cycles = top.dbg_perf_mem_forward_cycles;
    sample.mem_iq_head_not_ready_cycles = top.dbg_perf_mem_iq_head_not_ready_cycles;
    sample.mem_iq_younger_ready_cycles = top.dbg_perf_mem_iq_younger_ready_cycles;
    sample.mem_iq_occupancy_sum = top.dbg_perf_mem_iq_occupancy_sum;
    sample.mem_iq_probe_launch_count = top.dbg_perf_mem_iq_probe_launch_count;
    sample.mem_iq_probe_accept_count = top.dbg_perf_mem_iq_probe_accept_count;
    sample.mem_iq_probe_reject_count = top.dbg_perf_mem_iq_probe_reject_count;
    sample.mul_op_count = top.dbg_perf_mul_op_count;
    sample.div_op_count = top.dbg_perf_div_op_count;
    sample.rem_op_count = top.dbg_perf_rem_op_count;
    sample.muldiv_busy_cycles = top.dbg_perf_muldiv_busy_cycles;
    return sample;
}

}  // namespace sim
