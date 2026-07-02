#ifndef TB_VERILATOR_SIM_TRACE_H
#define TB_VERILATOR_SIM_TRACE_H

#include <cstdint>
#include <string>

class VmyCPU;
class VerilatedFstC;

namespace sim {

class Trace {
public:
    Trace() = default;
    ~Trace();
    Trace(const Trace&) = delete;
    Trace& operator=(const Trace&) = delete;

    void open_if_enabled(VmyCPU& top, bool enabled, const std::string& path);
    void dump(uint64_t time);
    void close();
    bool enabled() const { return tfp_ != nullptr; }

private:
    VerilatedFstC* tfp_ = nullptr;
};

}  // namespace sim

#endif  // TB_VERILATOR_SIM_TRACE_H
