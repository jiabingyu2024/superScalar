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
    out << "  \"checker_kind\": \"" << json_escape(checker.kind()) << "\",\n";
    out << "  \"status\": \"" << result.status << "\",\n";
    out << "  \"reason\": \"" << json_escape(result.reason) << "\",\n";
    out << "  \"cycles\": " << result.cycles << ",\n";
    out << "  \"result_cycle\": " << result.cycles << ",\n";
    out << "  \"fail_code\": " << result.fail_code << ",\n";
    out << "  \"tohost_addr\": \"" << hex32(opt.tohost_addr) << "\",\n";
    out << "  \"last_led\": \"" << hex32(result.last_led) << "\",\n";
    out << "  \"last_seg_wdata\": \"" << hex32(result.last_seg_wdata) << "\",\n";
    out << "  \"counter_ms\": " << result.counter_ms << ",\n";
    out << "  \"saw_led_pass\": " << (result.saw_led_pass ? "true" : "false") << ",\n";
    out << "  \"saw_seg_match\": " << (result.saw_seg_match ? "true" : "false") << ",\n";
    out << "  \"saw_virtual_seg_match\": "
        << (result.saw_virtual_seg_match ? "true" : "false") << ",\n";
    out << "  \"led_pass_cycle\": " << result.led_pass_cycle << ",\n";
    out << "  \"seg_match_cycle\": " << result.seg_match_cycle << ",\n";
    out << "  \"virtual_seg_match_cycle\": "
        << result.virtual_seg_match_cycle << ",\n";
    out << "  \"saw_pass_counter\": "
        << (result.saw_pass_counter ? "true" : "false") << ",\n";
    out << "  \"saw_fail_counter\": "
        << (result.saw_fail_counter ? "true" : "false") << ",\n";
    out << "  \"last_pass_counter\": \""
        << hex32(result.last_pass_counter) << "\",\n";
    out << "  \"last_fail_counter\": \""
        << hex32(result.last_fail_counter) << "\",\n";
    out << "  \"saw_src_pass_marker\": "
        << (result.saw_src_pass_marker ? "true" : "false") << ",\n";
    out << "  \"saw_src_fail_marker\": "
        << (result.saw_src_fail_marker ? "true" : "false") << ",\n";
    out << "  \"last_src_test_lamps\": \""
        << hex32(result.last_src_test_lamps) << "\",\n";
    out << "  \"last_rv32i_count\": " << result.last_rv32i_count << ",\n";
    out << "  \"last_mext_count\": " << result.last_mext_count << ",\n";
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
