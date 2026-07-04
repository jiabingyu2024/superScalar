#ifndef TB_VERILATOR_SIM_RESULT_H
#define TB_VERILATOR_SIM_RESULT_H

#include "checker.h"
#include "perf_stats.h"
#include "sim_common.h"

#include <cstdint>

namespace sim {

void write_result_json(const Options& opt, const SimResult& result,
                       const PerfStats& perf, const Checker& checker);
int finish(const Options& opt, SimResult& result, const PerfStats& perf,
           const Checker& checker, uint64_t cycles);
void log_interesting_request(uint64_t cycle, const Options& opt, const Request& req);

}  // namespace sim

#endif  // TB_VERILATOR_SIM_RESULT_H
