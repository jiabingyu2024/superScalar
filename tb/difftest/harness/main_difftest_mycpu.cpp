#include "VmyCPU.h"

#include "../adapter/difftest_adapter.h"
#include "../adapter/dut_commit_io.h"
#include "../../verilator/checker.h"
#include "../../verilator/dut_mycpu_io.h"
#include "../../verilator/perf_stats.h"
#include "../../verilator/sim_config.h"
#include "../../verilator/sim_control.h"
#include "../../verilator/sim_memory.h"
#include "../../verilator/sim_result.h"
#include "../../verilator/sim_trace.h"

#include "verilated.h"

#include <exception>
#include <iostream>
#include <memory>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        sim::install_signal_handlers();
        sim::Options opt = sim::parse_args(argc, argv);
        if (opt.mode != "rv32") {
            throw std::runtime_error("myCPU difftest harness only supports --mode=rv32");
        }

        sim::MemoryModel mem;
        mem.load_irom(opt.irom_hex);
        mem.load_sparse_words(opt.irom_hex, sim::IROM_BASE);

        VmyCPU top;
        sim::Trace trace;
        trace.open_if_enabled(top, opt.trace, opt.wave_path);
        std::unique_ptr<sim::Checker> checker = sim::make_checker(opt);
        difftest::Adapter difftest(opt);
        sim::PerfStats perf;
        perf.set_cpu_freq_mhz(opt.cpu_freq_mhz);
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

        uint64_t last_cycle = 0;
        for (uint64_t cycle = 0; cycle < opt.max_cycles && !Verilated::gotFinish() &&
                               !sim::stop_requested(); ++cycle) {
            uint64_t now = cycle + 1;
            last_cycle = now;
            half_tick(0);
            sim::Request req = sim::capture_mycpu_request(top);
            half_tick(1);

            sim::log_interesting_request(now, opt, req);
            perf.observe_request(now, req);
            perf.observe_core(now, sim::capture_mycpu_perf(top));
            checker->pre_tick(now, req, mem, result);
            mem.tick_posedge(req, opt.counter_cycles_per_ms);
            difftest.observe(now, difftest::capture_commit(top), result);
            checker->post_tick(now, req, mem, result);
            perf.observe_state(now, mem.counter_ms);

            if (difftest.failed() || checker->done()) {
                trace.close();
                difftest.populate_result(result);
                if (checker->done() && !difftest.failed()) {
                    result.reason += "; difftest " + difftest.summary();
                }
                return sim::finish(opt, result, perf, *checker, now);
            }
        }

        if (sim::stop_requested()) {
            result.status = "INTERRUPTED";
            result.reason = sim::stop_reason();
            result.cycles = last_cycle;
        } else {
            result.status = "TIMEOUT";
            result.reason = "max cycles reached; difftest " + difftest.summary();
            result.cycles = opt.max_cycles;
        }
        result.counter_ms = mem.counter_ms;
        difftest.populate_result(result);
        trace.close();
        return sim::finish(opt, result, perf, *checker, result.cycles);
    } catch (const std::exception& ex) {
        std::cerr << "tb error: " << ex.what() << "\n";
        return 2;
    }
}
