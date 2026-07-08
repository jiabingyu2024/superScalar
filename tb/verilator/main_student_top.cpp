#include "Vstudent_top.h"

#include "checker.h"
#include "dut_student_top_io.h"
#include "perf_stats.h"
#include "sim_common.h"
#include "sim_config.h"
#include "sim_control.h"
#include "sim_memory.h"
#include "sim_result.h"
#include "sim_trace.h"

#include "verilated.h"

#include <algorithm>
#include <exception>
#include <cmath>
#include <iostream>
#include <memory>
#include <stdexcept>

int main(int argc, char** argv) {
    try {
        Verilated::commandArgs(argc, argv);
        sim::install_signal_handlers();
        sim::Options opt = sim::parse_args(argc, argv);
        if (opt.mode != "src") {
            throw std::runtime_error("student_top harness only supports --mode=src");
        }

        sim::MemoryModel mirror;
        Vstudent_top top;
        sim::init_student_top_inputs(top);

        sim::Trace trace;
        trace.open_if_enabled(top, opt.trace, opt.wave_path);
        std::unique_ptr<sim::Checker> checker = sim::make_checker(opt);
        sim::PerfStats perf;
        perf.set_cpu_freq_mhz(opt.cpu_freq_mhz);
        sim::SimResult result;

        double sim_time_ps = 0.0;
        uint64_t trace_time = 0;
        const double cpu_half_period_ps = 500000.0 / opt.cpu_freq_mhz;
        const double soc_half_period_ps = 500000.0 / sim::DEFAULT_SOC_FREQ_MHZ;
        double next_cpu_toggle_ps = cpu_half_period_ps;
        double next_soc_toggle_ps = soc_half_period_ps;
        top.eval();
        trace.dump(trace_time);

        auto dump_at_current_time = [&]() {
            uint64_t rounded = static_cast<uint64_t>(std::llround(sim_time_ps));
            if (rounded <= trace_time && sim_time_ps > 0.0) {
                rounded = trace_time + 1;
            }
            trace_time = rounded;
            top.eval();
            trace.dump(trace_time);
        };

        auto due = [](double a, double b) {
            return std::fabs(a - b) < 1e-6;
        };

        auto advance_to_next_cpu_posedge = [&]() {
            while (true) {
                double next_time = std::min(next_cpu_toggle_ps, next_soc_toggle_ps);
                bool cpu_due = due(next_cpu_toggle_ps, next_time);
                bool soc_due = due(next_soc_toggle_ps, next_time);
                bool cpu_rising = cpu_due && top.w_cpu_clk == 0;

                if (cpu_rising) {
                    sim::Request req = sim::capture_student_top_request(top);
                    sim_time_ps = next_time;
                    top.w_cpu_clk = 1;
                    next_cpu_toggle_ps += cpu_half_period_ps;
                    if (soc_due) {
                        top.w_clk_50Mhz = !top.w_clk_50Mhz;
                        next_soc_toggle_ps += soc_half_period_ps;
                    }
                    dump_at_current_time();
                    if (soc_due && top.w_clk_50Mhz) {
                        mirror.tick_counter_clock(opt.counter_cycles_per_ms);
                    }
                    return req;
                }

                sim_time_ps = next_time;
                if (cpu_due) {
                    top.w_cpu_clk = !top.w_cpu_clk;
                    next_cpu_toggle_ps += cpu_half_period_ps;
                }
                if (soc_due) {
                    top.w_clk_50Mhz = !top.w_clk_50Mhz;
                    next_soc_toggle_ps += soc_half_period_ps;
                }
                dump_at_current_time();
                if (soc_due && top.w_clk_50Mhz) {
                    mirror.tick_counter_clock(opt.counter_cycles_per_ms);
                }
            }
        };

        for (int i = 0; i < 8; ++i) {
            sim::Request req = advance_to_next_cpu_posedge();
            mirror.tick_request(req, false, opt.counter_cycles_per_ms);
        }
        top.w_clk_rst = 0;
        dump_at_current_time();

        uint64_t last_cycle = 0;
        for (uint64_t cycle = 0; cycle < opt.max_cycles && !Verilated::gotFinish() &&
                               !sim::stop_requested(); ++cycle) {
            uint64_t now = cycle + 1;
            last_cycle = now;
            sim::Request req = advance_to_next_cpu_posedge();

            sim::log_interesting_request(now, opt, req);
            perf.observe_request(now, req);
            perf.observe_core(now, sim::capture_student_top_perf(top));
            checker->pre_tick(now, req, mirror, result);
            mirror.tick_request(req, false, opt.counter_cycles_per_ms);
            checker->post_tick(now, req, mirror, result);
            perf.observe_state(now, mirror.counter_ms);

            if (checker->done()) {
                trace.close();
                return sim::finish(opt, result, perf, *checker, now);
            }
        }

        if (sim::stop_requested()) {
            result.status = "INTERRUPTED";
            result.reason = sim::stop_reason();
            result.cycles = last_cycle;
        } else {
            result.status = "TIMEOUT";
            result.reason = "max cycles reached";
            result.cycles = opt.max_cycles;
        }
        result.counter_ms = mirror.counter_ms;
        trace.close();
        return sim::finish(opt, result, perf, *checker, result.cycles);
    } catch (const std::exception& ex) {
        std::cerr << "tb error: " << ex.what() << "\n";
        return 2;
    }
}
