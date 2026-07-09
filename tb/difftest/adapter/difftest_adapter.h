#ifndef TB_DIFFTEST_ADAPTER_DIFFTEST_ADAPTER_H
#define TB_DIFFTEST_ADAPTER_DIFFTEST_ADAPTER_H

#include "commit_trace.h"
#include "../../verilator/sim_common.h"

#include <cstdint>
#include <iosfwd>
#include <string>

namespace difftest {

class Adapter {
public:
    explicit Adapter(const sim::Options& opt);

    void observe(uint64_t cycle, const CommitTrace& commit, sim::SimResult& result);
    void populate_result(sim::SimResult& result) const;
    bool failed() const { return failed_; }
    uint64_t commit_count() const { return commit_count_; }
    uint64_t mmio_skip_count() const { return mmio_skip_count_; }
    uint32_t last_commit_pc() const { return last_commit_pc_; }
    std::string summary() const;

private:
    bool trace_enabled_ = false;
    bool failed_ = false;
    uint64_t commit_count_ = 0;
    uint64_t mmio_skip_count_ = 0;
    uint32_t last_commit_pc_ = 0;

    void fail(uint64_t cycle, const std::string& reason, sim::SimResult& result);
    void trace(uint64_t cycle, const CommitTrace& commit) const;
};

void write_trace_summary_json(std::ostream& out, const Adapter& adapter);

}  // namespace difftest

#endif  // TB_DIFFTEST_ADAPTER_DIFFTEST_ADAPTER_H
