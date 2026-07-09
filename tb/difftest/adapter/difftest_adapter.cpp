#include "difftest_adapter.h"

#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>

namespace difftest {

namespace {

bool env_enabled(const char* name) {
    const char* value = std::getenv(name);
    if (value == nullptr) return false;
    return value[0] != '\0' && value[0] != '0';
}

std::string hex32(uint32_t value) {
    std::ostringstream os;
    os << "0x" << std::hex << std::setw(8) << std::setfill('0') << value;
    return os.str();
}

}  // namespace

Adapter::Adapter(const sim::Options&) : trace_enabled_(env_enabled("DIFFTRACE")) {}

void Adapter::observe(uint64_t cycle, const CommitTrace& commit, sim::SimResult& result) {
    if (failed_ || !commit.valid) return;

    ++commit_count_;
    last_commit_pc_ = commit.pc;
    if (commit.is_mmio) ++mmio_skip_count_;
    trace(cycle, commit);

    if (commit.wen && commit.rd == 0) {
        fail(cycle, "commit writes x0 with wen=1", result);
        return;
    }

    if ((commit.pc & 0x3u) != 0) {
        fail(cycle, "commit pc is not word aligned: " + hex32(commit.pc), result);
        return;
    }

    if ((commit.next_pc & 0x1u) != 0) {
        fail(cycle, "commit next_pc bit0 is set: " + hex32(commit.next_pc), result);
        return;
    }
}

void Adapter::populate_result(sim::SimResult& result) const {
    result.has_difftest = true;
    result.difftest_reference_enabled = false;
    result.difftest_mode = "commit_trace_selfcheck";
    result.difftest_commit_count = commit_count_;
    result.difftest_mmio_skip_count = mmio_skip_count_;
    result.difftest_last_commit_pc = last_commit_pc_;
}

void Adapter::fail(uint64_t cycle, const std::string& reason, sim::SimResult& result) {
    failed_ = true;
    result.status = "FAIL";
    result.reason = "difftest commit self-check failed at cycle " +
                    std::to_string(cycle) + ": " + reason;
    result.cycles = cycle;
}

void Adapter::trace(uint64_t cycle, const CommitTrace& commit) const {
    if (!trace_enabled_) return;
    std::cout << "difftest cycle " << cycle
              << " commit#" << commit_count_
              << " pc=" << hex32(commit.pc)
              << " inst=" << hex32(commit.inst)
              << " rd=x" << unsigned(commit.rd)
              << " wen=" << (commit.wen ? 1 : 0)
              << " wdata=" << hex32(commit.wdata)
              << " next_pc=" << hex32(commit.next_pc);
    if (commit.is_load) std::cout << " load";
    if (commit.is_store) std::cout << " store";
    if (commit.is_trap) std::cout << " trap cause=" << hex32(commit.cause);
    if (commit.is_mmio) std::cout << " mmio-skip";
    std::cout << "\n";
}

std::string Adapter::summary() const {
    std::ostringstream os;
    os << "commits=" << commit_count_
       << " mmio_skip=" << mmio_skip_count_
       << " last_pc=" << hex32(last_commit_pc_);
    return os.str();
}

void write_trace_summary_json(std::ostream& out, const Adapter& adapter) {
    out << "  \"difftest\": {\n";
    out << "    \"mode\": \"commit_trace_selfcheck\",\n";
    out << "    \"reference_enabled\": false,\n";
    out << "    \"commit_count\": " << adapter.commit_count() << ",\n";
    out << "    \"mmio_skip_count\": " << adapter.mmio_skip_count() << ",\n";
    out << "    \"last_commit_pc\": \"" << hex32(adapter.last_commit_pc()) << "\"\n";
    out << "  }\n";
}

}  // namespace difftest
