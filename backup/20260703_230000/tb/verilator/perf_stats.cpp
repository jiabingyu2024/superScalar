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
                first_led_write = req.perip_wdata;
            }
            last_led_write = req.perip_wdata;
        } else if (req.perip_addr == SEG_ADDR) {
            if (!saw_first_seg) {
                saw_first_seg = true;
                first_seg_write = req.perip_wdata;
            }
            last_seg_write = req.perip_wdata;
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

void PerfStats::write_json_fields(std::ostream& out) const {
    out << "  \"perf\": {\n";
    out << "    \"cycles\": " << cycles << ",\n";
    out << "    \"mmio_read_count\": " << mmio_read_count << ",\n";
    out << "    \"mmio_write_count\": " << mmio_write_count << ",\n";
    out << "    \"dram_read_count\": " << dram_read_count << ",\n";
    out << "    \"dram_write_count\": " << dram_write_count << ",\n";
    out << "    \"counter_start_cycle\": " << counter_start_cycle << ",\n";
    out << "    \"counter_stop_cycle\": " << counter_stop_cycle << ",\n";
    out << "    \"counter_ms\": " << final_counter_ms << ",\n";
    out << "    \"first_led_write\": \"" << hex32(first_led_write) << "\",\n";
    out << "    \"last_led_write\": \"" << hex32(last_led_write) << "\",\n";
    out << "    \"first_seg_write\": \"" << hex32(first_seg_write) << "\",\n";
    out << "    \"last_seg_write\": \"" << hex32(last_seg_write) << "\"\n";
    out << "  }\n";
}

}  // namespace sim
