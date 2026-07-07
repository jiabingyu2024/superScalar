#ifndef TB_VERILATOR_PERF_STATS_H
#define TB_VERILATOR_PERF_STATS_H

#include "sim_common.h"

#include <cstdint>
#include <iosfwd>

namespace sim {

class PerfStats {
public:
    void set_cpu_freq_mhz(double mhz);
    void observe_request(uint64_t cycle, const Request& req);
    void observe_state(uint64_t cycle, uint32_t counter_ms);
    void observe_core(uint64_t cycle, const CorePerfSample& sample);
    void write_json_fields(std::ostream& out) const;

    uint64_t cycles = 0;
    double cpu_freq_mhz = DEFAULT_CPU_FREQ_MHZ;
    uint64_t core_cycle = 0;
    uint64_t commit_count = 0;
    uint64_t branch_count = 0;
    uint64_t branch_miss_count = 0;
    uint64_t cond_branch_count = 0;
    uint64_t cond_branch_miss_count = 0;
    uint64_t jal_count = 0;
    uint64_t jal_miss_count = 0;
    uint64_t jalr_count = 0;
    uint64_t jalr_miss_count = 0;
    uint64_t frontend_stall_cycles = 0;
    uint64_t id_stall_cycles = 0;
    uint64_t rn_stall_cycles = 0;
    uint64_t ds_stall_cycles = 0;
    uint64_t is_stall_cycles = 0;
    uint64_t rr_stall_cycles = 0;
    uint64_t ex_stall_cycles = 0;
    uint64_t wb_stall_cycles = 0;
    uint64_t rob_full_cycles = 0;
    uint64_t issue_queue_full_cycles = 0;
    uint64_t free_list_empty_cycles = 0;
    uint64_t store_buffer_full_cycles = 0;
    uint64_t serial_block_cycles = 0;
    uint64_t mem_load_return_block_cycles = 0;
    uint64_t mem_load_access_block_cycles = 0;
    uint64_t store_commit_blocked_by_load_cycles = 0;
    uint64_t recovery_cycles = 0;
    uint64_t dispatch_width0_cycles = 0;
    uint64_t dispatch_width1_cycles = 0;
    uint64_t dispatch_width2_cycles = 0;
    uint64_t issue_width0_cycles = 0;
    uint64_t issue_width1_cycles = 0;
    uint64_t issue_width2_cycles = 0;
    uint64_t commit_width0_cycles = 0;
    uint64_t commit_width1_cycles = 0;
    uint64_t commit_width2_cycles = 0;
    uint64_t mmio_read_count = 0;
    uint64_t mmio_write_count = 0;
    uint64_t dram_read_count = 0;
    uint64_t dram_write_count = 0;
    uint64_t counter_start_cycle = 0;
    uint64_t counter_stop_cycle = 0;
    uint32_t final_counter_ms = 0;
    bool saw_counter_start = false;
    bool saw_counter_stop = false;
    bool saw_first_led = false;
    bool saw_first_seg = false;
    bool saw_nonzero_seg = false;
    uint64_t first_led_cycle = 0;
    uint64_t last_led_cycle = 0;
    uint64_t first_seg_cycle = 0;
    uint64_t last_seg_cycle = 0;
    uint64_t last_nonzero_seg_cycle = 0;
    uint32_t first_led_write = 0;
    uint32_t last_led_write = 0;
    uint32_t first_seg_write = 0;
    uint32_t last_seg_write = 0;
    uint32_t last_nonzero_seg_write = 0;
    uint32_t seg_at_last_led_write = 0;
};

}  // namespace sim

#endif  // TB_VERILATOR_PERF_STATS_H
