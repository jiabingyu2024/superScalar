#ifndef TB_VERILATOR_DUT_STUDENT_TOP_IO_H
#define TB_VERILATOR_DUT_STUDENT_TOP_IO_H

#include "sim_common.h"

class Vstudent_top;

namespace sim {

void init_student_top_inputs(Vstudent_top& top);
Request capture_student_top_request(const Vstudent_top& top);
CorePerfSample capture_student_top_perf(const Vstudent_top& top);

}  // namespace sim

#endif  // TB_VERILATOR_DUT_STUDENT_TOP_IO_H
