#include "perf_stats.h"

#include "sim_common.h"

#include <algorithm>
#include <iterator>
#include <ostream>
#include <vector>

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
    load_count = sample.load_count;
    store_count = sample.store_count;
    dcache_access = sample.dcache_access;
    dcache_miss = sample.dcache_miss;
    aggregate_mem_stall_cycles = sample.stall_mem;
    aggregate_muldiv_stall_cycles = sample.stall_muldiv;
    aggregate_load_use_stall_cycles = sample.stall_load_use;
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
    int_issue_queue_full_cycles = sample.int_issue_queue_full_cycles;
    mem_issue_queue_full_cycles = sample.mem_issue_queue_full_cycles;
    mul_issue_queue_full_cycles = sample.mul_issue_queue_full_cycles;
    rob_head_not_done_cycles = sample.rob_head_not_done_cycles;
    rob_head_not_done_int_cycles = sample.rob_head_not_done_int_cycles;
    rob_head_not_done_mem_cycles = sample.rob_head_not_done_mem_cycles;
    rob_head_not_done_mul_cycles = sample.rob_head_not_done_mul_cycles;
    rob_head_not_done_other_cycles = sample.rob_head_not_done_other_cycles;
    rob_head_store_commit_wait_cycles = sample.rob_head_store_commit_wait_cycles;
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
    int_issue_count = sample.int_issue_count;
    mem_issue_count = sample.mem_issue_count;
    mul_issue_count = sample.mul_issue_count;
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
    uint64_t dcache_hit =
        dcache_access >= dcache_miss ? dcache_access - dcache_miss : 0;
    double dcache_hit_rate =
        dcache_access == 0 ? 0.0 : static_cast<double>(dcache_hit) /
                                  static_cast<double>(dcache_access);
    double dcache_miss_rate =
        dcache_access == 0 ? 0.0 : static_cast<double>(dcache_miss) /
                                  static_cast<double>(dcache_access);
    double elapsed_ms = cpu_freq_mhz <= 0.0 ? 0.0 :
        static_cast<double>(cycles) / (cpu_freq_mhz * 1000.0);
    auto miss_rate = [](uint64_t miss, uint64_t total) {
        return total == 0 ? 0.0 : static_cast<double>(miss) /
                                static_cast<double>(total);
    };
    auto ratio = [](uint64_t value, uint64_t total) {
        return total == 0 ? 0.0 : static_cast<double>(value) /
                                static_cast<double>(total);
    };
    auto average_width = [](uint64_t w1, uint64_t w2, uint64_t total) {
        return total == 0 ? 0.0 :
            static_cast<double>(w1 + 2 * w2) / static_cast<double>(total);
    };
    const uint64_t measured_cycles = core_cycle == 0 ? cycles : core_cycle;
    const uint64_t dispatch_width_cycles = dispatch_width0_cycles +
        dispatch_width1_cycles + dispatch_width2_cycles;
    const uint64_t issue_width_cycles = issue_width0_cycles +
        issue_width1_cycles + issue_width2_cycles;
    const uint64_t commit_width_cycles = commit_width0_cycles +
        commit_width1_cycles + commit_width2_cycles;
    const bool rename_input_width_available =
        issue_width_cycles >= measured_cycles - (measured_cycles != 0);
    const bool commit_width_available =
        commit_width_cycles >= measured_cycles - (measured_cycles != 0);
    const bool dispatch_width_available =
        dispatch_width_cycles >= measured_cycles - (measured_cycles != 0);
    const bool branch_breakdown_available =
        cond_branch_count + jal_count + jalr_count == branch_count;
    const bool detailed_pipeline_counters_available =
        dispatch_width_available;

    struct Bottleneck {
        const char* name;
        const char* domain;
        uint64_t cycles;
        const char* hint;
    };
    std::vector<Bottleneck> bottlenecks{
        {"frontend_stall", "frontend", frontend_stall_cycles,
         "Inspect fetch supply, prediction recovery, and fetch-buffer backpressure."},
        {"recovery", "control", recovery_cycles,
         "Inspect branch-miss rate and recovery latency."},
        {"aggregate_memory_stall", "memory", aggregate_mem_stall_cycles,
         "Inspect DCache stalls and the LSU access/return path."},
        {"aggregate_muldiv_stall", "execute", aggregate_muldiv_stall_cycles,
         "Inspect MulDiv occupancy and dependent instruction pressure."},
        {"aggregate_load_use_stall", "execute", aggregate_load_use_stall_cycles,
         "Inspect load-use wakeup and forwarding latency."},
    };
    if (detailed_pipeline_counters_available) {
        const Bottleneck detailed[] = {
            {"decode_stall", "frontend", id_stall_cycles,
             "Inspect decode queue occupancy and downstream rename readiness."},
            {"rename_stall", "rename", rn_stall_cycles,
             "Inspect free-list allocation, ROB allocation, and rename output backpressure."},
            {"dispatch_stall", "dispatch", ds_stall_cycles,
             "Inspect ROB and issue-queue admission pressure."},
            {"issue_stall", "issue", is_stall_cycles,
             "Inspect operand readiness, issue selection, and execution-unit availability."},
            {"register_read_stall", "execute", rr_stall_cycles,
             "Inspect PRF read bandwidth and dependent wakeup timing."},
            {"execute_stall", "execute", ex_stall_cycles,
             "Inspect LSU and MulDiv occupancy plus execution backpressure."},
            {"writeback_stall", "writeback", wb_stall_cycles,
             "Inspect completion bandwidth and ROB writeback arbitration."},
            {"rob_full", "resource", rob_full_cycles,
             "Inspect retirement blockage before increasing ROB depth."},
            {"issue_queue_full", "resource", issue_queue_full_cycles,
             "Use the per-queue breakdown to identify the saturated issue class."},
            {"rob_head_not_done", "retire", rob_head_not_done_cycles,
             "Use the ROB-head type breakdown to identify the long-latency producer."},
            {"store_commit_wait", "memory", rob_head_store_commit_wait_cycles,
             "Inspect store retirement and StoreBuffer drain bandwidth."},
            {"free_list_empty", "rename", free_list_empty_cycles,
             "Inspect physical-register pressure and reclaim latency."},
            {"store_buffer_full", "memory", store_buffer_full_cycles,
             "Inspect StoreBuffer depth and memory write drain throughput."},
            {"serial_block", "retire", serial_block_cycles,
             "Inspect CSR, trap, fence, and other serializing operations."},
            {"load_return_block", "memory", mem_load_return_block_cycles,
             "Inspect outstanding-load completion and return-path serialization."},
            {"load_access_block", "memory", mem_load_access_block_cycles,
             "Inspect load admission, StoreBuffer ordering, and DCache request readiness."},
            {"store_blocked_by_load", "memory", store_commit_blocked_by_load_cycles,
             "Inspect read/write arbitration and pending-load policy."},
        };
        bottlenecks.insert(bottlenecks.end(), std::begin(detailed),
                           std::end(detailed));
    }
    std::stable_sort(bottlenecks.begin(), bottlenecks.end(),
                     [](const Bottleneck& lhs, const Bottleneck& rhs) {
                         return lhs.cycles > rhs.cycles;
                     });
    bottlenecks.erase(
        std::remove_if(bottlenecks.begin(), bottlenecks.end(),
                       [](const Bottleneck& item) { return item.cycles == 0; }),
        bottlenecks.end());

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
    out << "      \"load_count\": " << load_count << ",\n";
    out << "      \"store_count\": " << store_count << ",\n";
    out << "      \"mmio_read_count\": " << mmio_read_count << ",\n";
    out << "      \"mmio_write_count\": " << mmio_write_count << "\n";
    out << "    },\n";
    out << "    \"dcache\": {\n";
    out << "      \"access\": " << dcache_access << ",\n";
    out << "      \"hit\": " << dcache_hit << ",\n";
    out << "      \"miss\": " << dcache_miss << ",\n";
    out << "      \"hit_rate\": " << dcache_hit_rate << ",\n";
    out << "      \"miss_rate\": " << dcache_miss_rate << "\n";
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
    out << "      \"issue_queue_full_breakdown\": {\n";
    out << "        \"int_cycles\": " << int_issue_queue_full_cycles << ",\n";
    out << "        \"mem_cycles\": " << mem_issue_queue_full_cycles << ",\n";
    out << "        \"mul_cycles\": " << mul_issue_queue_full_cycles << "\n";
    out << "      },\n";
    out << "      \"rob_head_block\": {\n";
    out << "        \"not_done_cycles\": " << rob_head_not_done_cycles << ",\n";
    out << "        \"not_done_int_cycles\": " << rob_head_not_done_int_cycles << ",\n";
    out << "        \"not_done_mem_cycles\": " << rob_head_not_done_mem_cycles << ",\n";
    out << "        \"not_done_mul_cycles\": " << rob_head_not_done_mul_cycles << ",\n";
    out << "        \"not_done_other_cycles\": " << rob_head_not_done_other_cycles << ",\n";
    out << "        \"store_commit_wait_cycles\": "
        << rob_head_store_commit_wait_cycles << "\n";
    out << "      },\n";
    out << "      \"free_list_empty_cycles\": " << free_list_empty_cycles << ",\n";
    out << "      \"store_buffer_full_cycles\": " << store_buffer_full_cycles << ",\n";
    out << "      \"serial_block_cycles\": " << serial_block_cycles << "\n";
    out << "    },\n";
    out << "    \"mem_stalls\": {\n";
    out << "      \"aggregate_cycles\": " << aggregate_mem_stall_cycles << ",\n";
    out << "      \"aggregate_muldiv_cycles\": "
        << aggregate_muldiv_stall_cycles << ",\n";
    out << "      \"aggregate_load_use_cycles\": "
        << aggregate_load_use_stall_cycles << ",\n";
    out << "      \"load_return_block_cycles\": " << mem_load_return_block_cycles << ",\n";
    out << "      \"load_access_block_cycles\": " << mem_load_access_block_cycles << ",\n";
    out << "      \"store_commit_blocked_by_load_cycles\": "
        << store_commit_blocked_by_load_cycles << "\n";
    out << "    },\n";
    out << "    \"width\": {\n";
    out << "      \"issue_mix\": {\n";
    out << "        \"int_uops\": " << int_issue_count << ",\n";
    out << "        \"mem_uops\": " << mem_issue_count << ",\n";
    out << "        \"mul_uops\": " << mul_issue_count << "\n";
    out << "      },\n";
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
    out << "    \"bottleneck_analysis\": {\n";
    out << "      \"counter_coverage\": {\n";
    out << "        \"branch_breakdown\": "
        << (branch_breakdown_available ? "true" : "false") << ",\n";
    out << "        \"frontend_stall\": true,\n";
    out << "        \"recovery\": true,\n";
    out << "        \"aggregate_memory_stall\": true,\n";
    out << "        \"rename_input_width\": "
        << (rename_input_width_available ? "true" : "false") << ",\n";
    out << "        \"commit_width\": "
        << (commit_width_available ? "true" : "false") << ",\n";
    out << "        \"dispatch_and_resource_detail\": "
        << (detailed_pipeline_counters_available ? "true" : "false") << "\n";
    out << "      },\n";
    out << "      \"measured_cycles\": " << measured_cycles << ",\n";
    out << "      \"estimated_mips\": " << ipc * cpu_freq_mhz << ",\n";
    out << "      \"average_width\": {\n";
    out << "        \"rename_input\": "
        << average_width(issue_width1_cycles, issue_width2_cycles,
                         issue_width_cycles) << ",\n";
    out << "        \"commit\": "
        << average_width(commit_width1_cycles, commit_width2_cycles,
                         commit_width_cycles) << "\n";
    out << "      },\n";
    out << "      \"dual_width_cycle_ratio\": {\n";
    out << "        \"rename_input\": "
        << ratio(issue_width2_cycles, issue_width_cycles) << ",\n";
    out << "        \"commit\": "
        << ratio(commit_width2_cycles, commit_width_cycles) << "\n";
    out << "      },\n";
    out << "      \"event_pressure_per_1000_commits\": {\n";
    out << "        \"branch_miss\": "
        << 1000.0 * ratio(branch_miss_count, commit_count) << ",\n";
    out << "        \"dcache_miss\": "
        << 1000.0 * ratio(dcache_miss, commit_count) << "\n";
    out << "      },\n";
    out << "      \"counter_semantics\": "
        << "\"Raw width.issue currently measures decode/rename acceptance, not execution issue.\",\n";
    out << "      \"ranking_note\": "
        << "\"Cycle indicators can overlap and must not be summed as lost cycles.\",\n";
    out << "      \"top_cycle_bottlenecks\": [\n";
    const size_t bottleneck_limit = std::min<size_t>(8, bottlenecks.size());
    for (size_t i = 0; i < bottleneck_limit; ++i) {
        const Bottleneck& item = bottlenecks[i];
        out << "        {\"rank\": " << i + 1
            << ", \"name\": \"" << item.name
            << "\", \"domain\": \"" << item.domain
            << "\", \"cycles\": " << item.cycles
            << ", \"cycle_ratio\": " << ratio(item.cycles, measured_cycles)
            << ", \"hint\": \"" << item.hint << "\"}";
        out << (i + 1 == bottleneck_limit ? "\n" : ",\n");
    }
    out << "      ]\n";
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
