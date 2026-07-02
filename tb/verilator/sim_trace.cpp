#include "sim_trace.h"

#include "VmyCPU.h"

#include "verilated.h"
#include "verilated_fst_c.h"

namespace sim {

Trace::~Trace() {
    close();
}

void Trace::open_if_enabled(VmyCPU& top, bool enabled, const std::string& path) {
    if (!enabled) return;
    Verilated::traceEverOn(true);
    tfp_ = new VerilatedFstC;
    top.trace(tfp_, 99);
    std::string wave = path.empty() ? "wave.fst" : path;
    tfp_->open(wave.c_str());
}

void Trace::dump(uint64_t time) {
    if (tfp_) tfp_->dump(time);
}

void Trace::close() {
    if (!tfp_) return;
    tfp_->close();
    delete tfp_;
    tfp_ = nullptr;
}

}  // namespace sim
