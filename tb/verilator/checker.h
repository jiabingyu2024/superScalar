#ifndef TB_VERILATOR_CHECKER_H
#define TB_VERILATOR_CHECKER_H

#include "sim_common.h"
#include "sim_memory.h"

#include <memory>
#include <string>

namespace sim {

class Checker {
public:
    virtual ~Checker() = default;
    virtual std::string kind() const = 0;
    virtual void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                          SimResult& result) = 0;
    virtual void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                           SimResult& result) = 0;
    virtual bool done() const = 0;
};

std::unique_ptr<Checker> make_checker(const Options& opt);

}  // namespace sim

#endif  // TB_VERILATOR_CHECKER_H
