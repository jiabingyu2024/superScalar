#ifndef TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H
#define TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H

#include "commit_trace.h"

class VmyCPU;
class Vstudent_top;

namespace difftest {

CommitTrace capture_commit(const VmyCPU& top);
CommitTrace capture_commit(const Vstudent_top& top);

}  // namespace difftest

#endif  // TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H

