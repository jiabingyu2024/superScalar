#include "VmyCPU.h"

#include "checker.h"
#include "perf_stats.h"
#include "sim_common.h"
#include "sim_config.h"
#include "sim_memory.h"
#include "sim_trace.h"

#include "verilated.h"

#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>

namespace sim {
namespace {

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

}  // namespace
}  // namespace sim

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        sim::Options opt = sim::parse_args(argc, argv);

        sim::MemoryModel mem;
        mem.load_irom(opt.irom_hex);
        if (opt.mode == "src") {
            if (!opt.dram_hex.empty()) mem.load_sparse_words(opt.dram_hex, sim::SRC_DRAM_BASE);
        } else {
            mem.load_sparse_words(opt.irom_hex, sim::IROM_BASE);
        }

        VmyCPU top;
        sim::Trace trace;
        trace.open_if_enabled(top, opt.trace, opt.wave_path);
        std::unique_ptr<sim::Checker> checker = sim::make_checker(opt);
        sim::PerfStats perf;
        sim::SimResult result;

        uint64_t main_time = 0;
        top.cpu_clk = 0;
        top.cpu_rst = 1;
        sim::drive_inputs(top, mem);
        top.eval();
        trace.dump(main_time);

        auto half_tick = [&](int clk) {
            top.cpu_clk = clk;
            sim::drive_inputs(top, mem);
            top.eval();
            main_time += 5;
            trace.dump(main_time);
        };

        for (int i = 0; i < 8; ++i) {
            half_tick(0);
            sim::Request req = sim::capture_request(top);
            half_tick(1);
            mem.tick_posedge(req, opt.counter_cycles_per_ms);
        }
        top.cpu_rst = 0;

        for (uint64_t cycle = 0; cycle < opt.max_cycles && !Verilated::gotFinish(); ++cycle) {
            uint64_t now = cycle + 1;
            half_tick(0);
            sim::Request req = sim::capture_request(top);
            half_tick(1);

            sim::log_interesting_request(now, opt, req);
            perf.observe_request(now, req);
            checker->pre_tick(now, req, mem, result);
            mem.tick_posedge(req, opt.counter_cycles_per_ms);
            checker->post_tick(now, req, mem, result);
            perf.observe_state(now, mem.counter_ms);

            if (checker->done()) {
                trace.close();
                return sim::finish(opt, result, perf, *checker, now);
            }
        }

        result.status = "TIMEOUT";
        result.reason = "max cycles reached";
        result.cycles = opt.max_cycles;
        result.counter_ms = mem.counter_ms;
        trace.close();
        return sim::finish(opt, result, perf, *checker, opt.max_cycles);
    } catch (const std::exception& ex) {
        std::cerr << "tb error: " << ex.what() << "\n";
        return 2;
    }
}
