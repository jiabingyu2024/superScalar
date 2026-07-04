#include "Vstudent_top.h"

#include "checker.h"
#include "dut_student_top_io.h"
#include "perf_stats.h"
#include "sim_common.h"
#include "sim_config.h"
#include "sim_memory.h"
#include "sim_result.h"
#include "sim_trace.h"

#include "verilated.h"

#include <exception>
#include <iostream>
#include <memory>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        sim::Options opt = sim::parse_args(argc, argv);
        if (opt.mode != "src") {
            throw std::runtime_error("student_top harness only supports --mode=src");
        }
        if (opt.counter_cycles_per_ms != sim::DEFAULT_COUNTER_CYCLES_PER_MS) {
            throw std::runtime_error(
                "student_top uses rtl/soc/counter.sv fixed 50000 cycles/ms");
        }

        sim::MemoryModel mirror;
        Vstudent_top top;
        sim::init_student_top_inputs(top);

        sim::Trace trace;
        trace.open_if_enabled(top, opt.trace, opt.wave_path);
        std::unique_ptr<sim::Checker> checker = sim::make_checker(opt);
        sim::PerfStats perf;
        sim::SimResult result;

        uint64_t main_time = 0;
        top.eval();
        trace.dump(main_time);

        auto half_tick = [&](int clk) {
            top.w_cpu_clk = clk;
            top.w_clk_50Mhz = clk;
            top.eval();
            main_time += 5;
            trace.dump(main_time);
        };

        for (int i = 0; i < 8; ++i) {
            half_tick(0);
            half_tick(1);
        }
        top.w_clk_rst = 0;

        for (uint64_t cycle = 0; cycle < opt.max_cycles && !Verilated::gotFinish(); ++cycle) {
            uint64_t now = cycle + 1;
            half_tick(0);
            sim::Request req = sim::capture_student_top_request(top);
            half_tick(1);

            sim::log_interesting_request(now, opt, req);
            perf.observe_request(now, req);
            checker->pre_tick(now, req, mirror, result);
            mirror.tick_posedge(req, sim::DEFAULT_COUNTER_CYCLES_PER_MS);
            checker->post_tick(now, req, mirror, result);
            perf.observe_state(now, mirror.counter_ms);

            if (checker->done()) {
                trace.close();
                return sim::finish(opt, result, perf, *checker, now);
            }
        }

        result.status = "TIMEOUT";
        result.reason = "max cycles reached";
        result.cycles = opt.max_cycles;
        result.counter_ms = mirror.counter_ms;
        trace.close();
        return sim::finish(opt, result, perf, *checker, opt.max_cycles);
    } catch (const std::exception& ex) {
        std::cerr << "tb error: " << ex.what() << "\n";
        return 2;
    }
}
