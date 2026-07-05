#include "perf_stats.h"

#include "sim_common.h"

#include <ostream>

namespace sim {

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
    auto miss_rate = [](uint64_t miss, uint64_t total) {
        return total == 0 ? 0.0 : static_cast<double>(miss) /
                                static_cast<double>(total);
    };

    out << "  \"perf\": {\n";
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
