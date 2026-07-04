#ifndef TB_VERILATOR_DUT_MYCPU_IO_H
#define TB_VERILATOR_DUT_MYCPU_IO_H

#include "sim_common.h"
#include "sim_memory.h"

class VmyCPU;

namespace sim {

void drive_mycpu_inputs(VmyCPU& top, const MemoryModel& mem);
Request capture_mycpu_request(const VmyCPU& top);
CorePerfSample capture_mycpu_perf(const VmyCPU& top);

}  // namespace sim

#endif  // TB_VERILATOR_DUT_MYCPU_IO_H
