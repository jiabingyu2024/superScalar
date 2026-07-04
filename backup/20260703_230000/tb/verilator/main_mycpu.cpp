#include "VmyCPU.h"

#include "checker.h"
#include "dut_mycpu_io.h"
#include "perf_stats.h"
#include "sim_config.h"
#include "sim_memory.h"
#include "sim_result.h"
#include "sim_trace.h"

#include "verilated.h"

#include <exception>
#include <iostream>
#include <memory>

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
        sim::drive_mycpu_inputs(top, mem);
        top.eval();
        trace.dump(main_time);

        auto half_tick = [&](int clk) {
            top.cpu_clk = clk;
            sim::drive_mycpu_inputs(top, mem);
            top.eval();
            main_time += 5;
            trace.dump(main_time);
        };

        for (int i = 0; i < 8; ++i) {
            half_tick(0);
            sim::Request req = sim::capture_mycpu_request(top);
            half_tick(1);
            mem.tick_posedge(req, opt.counter_cycles_per_ms);
        }
        top.cpu_rst = 0;

        for (uint64_t cycle = 0; cycle < opt.max_cycles && !Verilated::gotFinish(); ++cycle) {
            uint64_t now = cycle + 1;
            half_tick(0);
            sim::Request req = sim::capture_mycpu_request(top);
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
