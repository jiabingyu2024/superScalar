#ifndef TB_VERILATOR_CHECKER_RV32_H
#define TB_VERILATOR_CHECKER_RV32_H

#include "checker.h"

namespace sim {

class Rv32Checker : public Checker {
public:
    explicit Rv32Checker(const Options& opt) : opt_(opt) {}
    std::string kind() const override { return "rv32_tohost"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                   SimResult& result) override;
    bool done() const override { return done_; }

private:
    const Options& opt_;
    bool done_ = false;
};

}  // namespace sim

#endif  // TB_VERILATOR_CHECKER_RV32_H
