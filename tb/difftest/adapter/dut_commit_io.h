#ifndef TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H
#define TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H

#include "commit_trace.h"

#include <array>

class VmyCPU;
class Vstudent_top;

namespace difftest {

constexpr int kCommitWidth = 1;

std::array<CommitTrace, kCommitWidth> capture_commits(const VmyCPU& top);
std::array<CommitTrace, kCommitWidth> capture_commits(const Vstudent_top& top);

}  // namespace difftest

#endif  // TB_DIFFTEST_ADAPTER_DUT_COMMIT_IO_H
