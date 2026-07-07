#include "perf_stats.h"

#include "sim_common.h"

#include <ostream>

namespace sim {

void PerfStats::set_cpu_freq_mhz(double mhz) {
    cpu_freq_mhz = mhz;
}

void PerfStats::observe_request(uint64_t cycle, const Request& req) {
    cycles = cycle;
    if (req.perip_addr == 0) return;

    if (req.perip_wen) {
        if (is_known_mmio_addr(req.perip_addr)) {
            mmio_write_count++;
        } else {
            dram_write_count++;
        }
        if (req.perip_addr == LED_ADDR) {
            if (!saw_first_led) {
                saw_first_led = true;
                first_led_cycle = cycle;
                first_led_write = req.perip_wdata;
            }
            last_led_cycle = cycle;
            last_led_write = req.perip_wdata;
            seg_at_last_led_write = last_seg_write;
        } else if (req.perip_addr == SEG_ADDR) {
            if (!saw_first_seg) {
                saw_first_seg = true;
                first_seg_cycle = cycle;
                first_seg_write = req.perip_wdata;
            }
            last_seg_cycle = cycle;
            last_seg_write = req.perip_wdata;
            if (req.perip_wdata != 0) {
                saw_nonzero_seg = true;
                last_nonzero_seg_cycle = cycle;
                last_nonzero_seg_write = req.perip_wdata;
            }
        } else if (req.perip_addr == CNT_ADDR) {
            if (req.perip_wdata == CNT_START_CMD && !saw_counter_start) {
                saw_counter_start = true;
                counter_start_cycle = cycle;
            }
            if (req.perip_wdata == CNT_STOP_CMD) {
                saw_counter_stop = true;
                counter_stop_cycle = cycle;
            }
        }
    } else {
        if (is_known_mmio_addr(req.perip_addr)) {
            mmio_read_count++;
        } else {
            dram_read_count++;
        }
    }
}

void PerfStats::observe_state(uint64_t cycle, uint32_t counter_ms) {
    cycles = cycle;
    final_counter_ms = counter_ms;
}

void PerfStats::observe_core(uint64_t cycle, const CorePerfSample& sample) {
    cycles = cycle;
    core_cycle = sample.cycle;
    commit_count = sample.commit_count;
    branch_count = sample.branch_count;
    branch_miss_count = sample.branch_miss_count;
    cond_branch_count = sample.cond_branch_count;
    cond_branch_miss_count = sample.cond_branch_miss_count;
    jal_count = sample.jal_count;
    jal_miss_count = sample.jal_miss_count;
    jalr_count = sample.jalr_count;
    jalr_miss_count = sample.jalr_miss_count;
    frontend_stall_cycles = sample.frontend_stall_cycles;
    id_stall_cycles = sample.id_stall_cycles;
    rn_stall_cycles = sample.rn_stall_cycles;
    ds_stall_cycles = sample.ds_stall_cycles;
    is_stall_cycles = sample.is_stall_cycles;
    rr_stall_cycles = sample.rr_stall_cycles;
    ex_stall_cycles = sample.ex_stall_cycles;
    wb_stall_cycles = sample.wb_stall_cycles;
    rob_full_cycles = sample.rob_full_cycles;
    issue_queue_full_cycles = sample.issue_queue_full_cycles;
    free_list_empty_cycles = sample.free_list_empty_cycles;
    store_buffer_full_cycles = sample.store_buffer_full_cycles;
    serial_block_cycles = sample.serial_block_cycles;
    mem_load_return_block_cycles = sample.mem_load_return_block_cycles;
    mem_load_access_block_cycles = sample.mem_load_access_block_cycles;
    store_commit_blocked_by_load_cycles =
        sample.store_commit_blocked_by_load_cycles;
    recovery_cycles = sample.recovery_cycles;
    dispatch_width0_cycles = sample.dispatch_width0_cycles;
    dispatch_width1_cycles = sample.dispatch_width1_cycles;
    dispatch_width2_cycles = sample.dispatch_width2_cycles;
    issue_width0_cycles = sample.issue_width0_cycles;
    issue_width1_cycles = sample.issue_width1_cycles;
    issue_width2_cycles = sample.issue_width2_cycles;
    commit_width0_cycles = sample.commit_width0_cycles;
    commit_width1_cycles = sample.commit_width1_cycles;
    commit_width2_cycles = sample.commit_width2_cycles;
}

void PerfStats::write_json_fields(std::ostream& out) const {
    uint64_t branch_hit_count =
        branch_count >= branch_miss_count ? branch_count - branch_miss_count : 0;
    double branch_hit_rate =
        branch_count == 0 ? 0.0 : static_cast<double>(branch_hit_count) /
                                  static_cast<double>(branch_count);
    double branch_miss_rate =
        branch_count == 0 ? 0.0 : static_cast<double>(branch_miss_count) /
                                  static_cast<double>(branch_count);
    double ipc = cycles == 0 ? 0.0 : static_cast<double>(commit_count) /
                                  static_cast<double>(cycles);
    double elapsed_ms = cpu_freq_mhz <= 0.0 ? 0.0 :
        static_cast<double>(cycles) / (cpu_freq_mhz * 1000.0);
    auto miss_rate = [](uint64_t miss, uint64_t total) {
        return total == 0 ? 0.0 : static_cast<double>(miss) /
                                static_cast<double>(total);
    };

    out << "  \"perf\": {\n";
    out << "    \"cpu_freq_mhz\": " << cpu_freq_mhz << ",\n";
    out << "    \"elapsed_ms_by_cpu_freq\": " << elapsed_ms << ",\n";
    out << "    \"soc_counter_freq_mhz\": " << DEFAULT_SOC_FREQ_MHZ << ",\n";
    out << "    \"core_cycle\": " << core_cycle << ",\n";
    out << "    \"commit_count\": " << commit_count << ",\n";
    out << "    \"ipc\": " << ipc << ",\n";
    out << "    \"branch_count\": " << branch_count << ",\n";
    out << "    \"branch_hit_count\": " << branch_hit_count << ",\n";
    out << "    \"branch_miss_count\": " << branch_miss_count << ",\n";
    out << "    \"branch_hit_rate\": " << branch_hit_rate << ",\n";
    out << "    \"branch_miss_rate\": " << branch_miss_rate << ",\n";
    out << "    \"branch_breakdown\": {\n";
    out << "      \"conditional\": {\n";
    out << "        \"count\": " << cond_branch_count << ",\n";
    out << "        \"miss_count\": " << cond_branch_miss_count << ",\n";
    out << "        \"miss_rate\": " << miss_rate(cond_branch_miss_count,
                                               cond_branch_count) << "\n";
    out << "      },\n";
    out << "      \"jal\": {\n";
    out << "        \"count\": " << jal_count << ",\n";
    out << "        \"miss_count\": " << jal_miss_count << ",\n";
    out << "        \"miss_rate\": " << miss_rate(jal_miss_count, jal_count) << "\n";
    out << "      },\n";
    out << "      \"jalr\": {\n";
    out << "        \"count\": " << jalr_count << ",\n";
    out << "        \"miss_count\": " << jalr_miss_count << ",\n";
    out << "        \"miss_rate\": " << miss_rate(jalr_miss_count, jalr_count) << "\n";
    out << "      }\n";
    out << "    },\n";
    out << "    \"memory\": {\n";
    out << "      \"dram_read_count\": " << dram_read_count << ",\n";
    out << "      \"dram_write_count\": " << dram_write_count << ",\n";
    out << "      \"mmio_read_count\": " << mmio_read_count << ",\n";
    out << "      \"mmio_write_count\": " << mmio_write_count << "\n";
    out << "    },\n";
    out << "    \"stalls\": {\n";
    out << "      \"frontend_cycles\": " << frontend_stall_cycles << ",\n";
    out << "      \"id_cycles\": " << id_stall_cycles << ",\n";
    out << "      \"rn_cycles\": " << rn_stall_cycles << ",\n";
    out << "      \"ds_cycles\": " << ds_stall_cycles << ",\n";
    out << "      \"is_cycles\": " << is_stall_cycles << ",\n";
    out << "      \"rr_cycles\": " << rr_stall_cycles << ",\n";
    out << "      \"ex_cycles\": " << ex_stall_cycles << ",\n";
    out << "      \"wb_cycles\": " << wb_stall_cycles << ",\n";
    out << "      \"recovery_cycles\": " << recovery_cycles << "\n";
    out << "    },\n";
    out << "    \"resources\": {\n";
    out << "      \"rob_full_cycles\": " << rob_full_cycles << ",\n";
    out << "      \"issue_queue_full_cycles\": " << issue_queue_full_cycles << ",\n";
    out << "      \"free_list_empty_cycles\": " << free_list_empty_cycles << ",\n";
    out << "      \"store_buffer_full_cycles\": " << store_buffer_full_cycles << ",\n";
    out << "      \"serial_block_cycles\": " << serial_block_cycles << "\n";
    out << "    },\n";
    out << "    \"mem_stalls\": {\n";
    out << "      \"load_return_block_cycles\": " << mem_load_return_block_cycles << ",\n";
    out << "      \"load_access_block_cycles\": " << mem_load_access_block_cycles << ",\n";
    out << "      \"store_commit_blocked_by_load_cycles\": "
        << store_commit_blocked_by_load_cycles << "\n";
    out << "    },\n";
    out << "    \"width\": {\n";
    out << "      \"dispatch\": {\n";
    out << "        \"w0_cycles\": " << dispatch_width0_cycles << ",\n";
    out << "        \"w1_cycles\": " << dispatch_width1_cycles << ",\n";
    out << "        \"w2_cycles\": " << dispatch_width2_cycles << "\n";
    out << "      },\n";
    out << "      \"issue\": {\n";
    out << "        \"w0_cycles\": " << issue_width0_cycles << ",\n";
    out << "        \"w1_cycles\": " << issue_width1_cycles << ",\n";
    out << "        \"w2_cycles\": " << issue_width2_cycles << "\n";
    out << "      },\n";
    out << "      \"commit\": {\n";
    out << "        \"w0_cycles\": " << commit_width0_cycles << ",\n";
    out << "        \"w1_cycles\": " << commit_width1_cycles << ",\n";
    out << "        \"w2_cycles\": " << commit_width2_cycles << "\n";
    out << "      }\n";
    out << "    },\n";
    out << "    \"counter\": {\n";
    out << "      \"start_cycle\": " << counter_start_cycle << ",\n";
    out << "      \"stop_cycle\": " << counter_stop_cycle << ",\n";
    out << "      \"ms\": " << final_counter_ms << "\n";
    out << "    },\n";
    out << "    \"led\": {\n";
    out << "      \"first_write_cycle\": " << first_led_cycle << ",\n";
    out << "      \"last_write_cycle\": " << last_led_cycle << ",\n";
    out << "      \"first_write\": \"" << hex32(first_led_write) << "\",\n";
    out << "      \"last_write\": \"" << hex32(last_led_write) << "\"\n";
    out << "    },\n";
    out << "    \"seg\": {\n";
    out << "      \"first_write_cycle\": " << first_seg_cycle << ",\n";
    out << "      \"last_write_cycle\": " << last_seg_cycle << ",\n";
    out << "      \"last_nonzero_write_cycle\": " << last_nonzero_seg_cycle << ",\n";
    out << "      \"first_write\": \"" << hex32(first_seg_write) << "\",\n";
    out << "      \"last_write\": \"" << hex32(last_seg_write) << "\",\n";
    out << "      \"last_nonzero_write\": \"" << hex32(last_nonzero_seg_write) << "\",\n";
    out << "      \"value_at_last_led_write\": \"" << hex32(seg_at_last_led_write) << "\"\n";
    out << "    }\n";
    out << "  }\n";
}

}  // namespace sim
