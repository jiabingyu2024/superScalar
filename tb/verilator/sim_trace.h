#ifndef TB_VERILATOR_SIM_TRACE_H
#define TB_VERILATOR_SIM_TRACE_H

#include <cstdint>
#include <string>

class VerilatedFstC;

namespace sim {

class Trace {
public:
    Trace() = default;
    ~Trace();
    Trace(const Trace&) = delete;
    Trace& operator=(const Trace&) = delete;

    template <typename Top>
    void open_if_enabled(Top& top, bool enabled, const std::string& path);
    void dump(uint64_t time);
    void close();
    bool enabled() const { return tfp_ != nullptr; }

private:
    VerilatedFstC* tfp_ = nullptr;
};

}  // namespace sim

#include "verilated.h"
#include "verilated_fst_c.h"

namespace sim {

template <typename Top>
void Trace::open_if_enabled(Top& top, bool enabled, const std::string& path) {
    if (!enabled) return;
    Verilated::traceEverOn(true);
    tfp_ = new VerilatedFstC;
    top.trace(tfp_, 99);
    std::string wave = path.empty() ? "wave.fst" : path;
    tfp_->open(wave.c_str());
}

}  // namespace sim

#endif  // TB_VERILATOR_SIM_TRACE_H
