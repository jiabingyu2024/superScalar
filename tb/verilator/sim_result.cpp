#include "sim_result.h"

#include <fstream>
#include <iostream>
#include <stdexcept>

namespace sim {

void write_result_json(const Options& opt, const SimResult& result,
                       const PerfStats& perf, const Checker& checker) {
    if (opt.result_path.empty()) return;
    std::ofstream out(opt.result_path);
    if (!out) {
        throw std::runtime_error("cannot write result file: " + opt.result_path);
    }
    out << "{\n";
    out << "  \"test\": \"" << json_escape(opt.test_name) << "\",\n";
    out << "  \"mode\": \"" << json_escape(opt.mode) << "\",\n";
    out << "  \"checker\": \"" << json_escape(checker.kind()) << "\",\n";
    out << "  \"status\": \"" << result.status << "\",\n";
    out << "  \"reason\": \"" << json_escape(result.reason) << "\",\n";
    out << "  \"cycles\": " << result.cycles << ",\n";
    out << "  \"max_cycles\": " << opt.max_cycles << ",\n";
    out << "  \"correctness\": {\n";
    if (opt.mode == "rv32") {
        out << "    \"tohost_addr\": \"" << hex32(opt.tohost_addr) << "\",\n";
        out << "    \"tohost_value\": \"" << hex32(result.fail_code) << "\"\n";
    } else {
        out << "    \"led\": {\n";
        out << "      \"pass_seen\": " << (result.saw_led_pass ? "true" : "false") << ",\n";
        out << "      \"pass_cycle\": " << result.led_pass_cycle << ",\n";
        out << "      \"last_value\": \"" << hex32(perf.last_led_write) << "\"\n";
        out << "    },\n";
        out << "    \"seg\": {\n";
        out << "      \"current_value\": \"" << hex32(perf.last_seg_write) << "\",\n";
        out << "      \"pass_display_value\": \"" << hex32(perf.last_nonzero_seg_write) << "\",\n";
        out << "      \"pass_display_cycle\": " << perf.last_nonzero_seg_cycle << ",\n";
        out << "      \"value_at_last_led_write\": \"" << hex32(perf.seg_at_last_led_write) << "\"\n";
        out << "    },\n";
        out << "    \"counter\": {\n";
        out << "      \"ms\": " << perf.final_counter_ms << ",\n";
        out << "      \"start_cycle\": " << perf.counter_start_cycle << ",\n";
        out << "      \"stop_cycle\": " << perf.counter_stop_cycle << "\n";
        out << "    },\n";
        out << "    \"src_lamps\": {\n";
        out << "      \"pass_marker_seen\": "
            << (result.saw_src_pass_marker ? "true" : "false") << ",\n";
        out << "      \"fail_marker_seen\": "
            << (result.saw_src_fail_marker ? "true" : "false") << ",\n";
        out << "      \"test_lamps\": \"" << hex32(result.last_src_test_lamps) << "\",\n";
        out << "      \"rv32i_count\": " << result.last_rv32i_count << ",\n";
        out << "      \"mext_count\": " << result.last_mext_count << "\n";
        out << "    }\n";
    }
    out << "  },\n";
    perf.write_json_fields(out);
    out << "}\n";
}

int finish(const Options& opt, SimResult& result, const PerfStats& perf,
           const Checker& checker, uint64_t cycles) {
    result.cycles = cycles;
    write_result_json(opt, result, perf, checker);
    std::cout << opt.test_name << " " << result.status << " after " << cycles
              << " cycles: " << result.reason << "\n";
    return result.status == "PASS" ? 0 : 1;
}

void log_interesting_request(uint64_t cycle, const Options& opt, const Request& req) {
    if (!req.perip_wen) return;
    if (req.perip_addr != opt.tohost_addr && req.perip_addr != LED_ADDR &&
        req.perip_addr != SEG_ADDR && req.perip_addr != CNT_ADDR &&
        !(opt.has_pass_counter_addr &&
          (req.perip_addr & ~uint32_t{3}) == (opt.pass_counter_addr & ~uint32_t{3})) &&
        !(opt.has_fail_counter_addr &&
          (req.perip_addr & ~uint32_t{3}) == (opt.fail_counter_addr & ~uint32_t{3}))) {
        return;
    }
    std::cout << "cycle " << cycle
              << " write addr=" << hex32(req.perip_addr)
              << " data=" << hex32(req.perip_wdata)
              << " mask=0x" << std::hex << unsigned(req.perip_mask)
              << std::dec << "\n";
}

}  // namespace sim
