#include "difftest_adapter.h"

#include "difftest-state.h"

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

Adapter::Adapter(const sim::Options& opt)
    : reference_(opt), trace_enabled_(env_enabled("DIFFTRACE")) {
    diffstate_buffer_init();
    if (const char* value = std::getenv("DIFFTEST_FAULT_INJECT_COMMIT"))
        fault_inject_commit_ = std::strtoull(value, nullptr, 0);
}

Adapter::~Adapter() {
    diffstate_buffer_free();
}

CommitTrace Adapter::consume_upstream_packet(const CommitTrace& sideband,
                                             uint64_t cycle,
                                             sim::SimResult& result) {
    DiffTestState* state = diffstate_buffer[0]->get(0, 0);
    const DifftestInstrCommit& packet = state->commit[0];
    const DifftestCommitData& data = state->commit_data[0];
    if (!packet.valid || !data.valid) {
        fail(cycle, "OpenXiangShan DPIC commit packet missing", result);
        return sideband;
    }

    CommitTrace commit = sideband;
    commit.valid = packet.valid;
    commit.pc = static_cast<uint32_t>(packet.pc);
    commit.inst = packet.instr;
    commit.wen = packet.rfwen;
    commit.rd = packet.wdest & 0x1f;
    commit.wdata = static_cast<uint32_t>(data.data);
    commit.is_load = packet.isLoad;
    commit.is_store = packet.isStore;
    commit.is_trap = state->trap.hasTrap;
    commit.cause = static_cast<uint32_t>(state->trap.code);

    state->commit[0] = {};
    state->commit_data[0] = {};
    state->event = {};
    state->trap = {};
    return commit;
}

void Adapter::observe(uint64_t cycle, const CommitTrace& commit, sim::SimResult& result) {
    if (failed_ || !commit.valid) return;

    ++commit_count_;
    CommitTrace observed = consume_upstream_packet(commit, cycle, result);
    if (failed_) return;
    if (observed.pc != commit.pc || observed.inst != commit.inst ||
        observed.wen != commit.wen || observed.rd != commit.rd ||
        observed.wdata != commit.wdata || observed.is_load != commit.is_load ||
        observed.is_store != commit.is_store || observed.is_trap != commit.is_trap ||
        (observed.is_trap && observed.cause != commit.cause)) {
        fail(cycle, "OpenXiangShan DPIC packet disagrees with retirement sideband", result);
        return;
    }
    if (fault_inject_commit_ == commit_count_) observed.wdata ^= 1u;
    last_commit_pc_ = observed.pc;
    trace(cycle, observed);

    if (observed.wen && observed.rd == 0) {
        fail(cycle, "commit writes x0 with wen=1", result);
        return;
    }

    const ReferenceStep ref = reference_.step(cycle, observed);
    if (!ref.error.empty()) {
        fail(cycle, "reference error: " + ref.error, result);
        return;
    }
    if (ref.nondeterministic) ++mmio_skip_count_;
    const std::string difference = mismatch(observed, ref.commit);
    if (!difference.empty()) fail(cycle, difference, result);
}

void Adapter::populate_result(sim::SimResult& result) const {
    result.has_difftest = true;
    result.difftest_reference_enabled = true;
    result.difftest_mode = "openxiangshan_dpic_rv32_reference";
    result.difftest_commit_count = commit_count_;
    result.difftest_mmio_skip_count = mmio_skip_count_;
    result.difftest_last_commit_pc = last_commit_pc_;
}

void Adapter::fail(uint64_t cycle, const std::string& reason, sim::SimResult& result) {
    failed_ = true;
    result.status = "FAIL";
    result.reason = "difftest mismatch at cycle " +
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
    if (commit.is_load || commit.is_store) std::cout << " addr=" << hex32(commit.mem_addr);
    if (commit.is_store) std::cout << " data=" << hex32(commit.mem_wdata)
                                   << " strb=0x" << std::hex << unsigned(commit.mem_wstrb)
                                   << std::dec;
    if (commit.is_trap) std::cout << " trap cause=" << hex32(commit.cause);
    if (commit.is_mmio) std::cout << " mmio-skip";
    std::cout << "\n";
}

std::string Adapter::mismatch(const CommitTrace& dut, const CommitTrace& ref) const {
    auto diff32 = [&](const char* name, uint32_t got, uint32_t expected) {
        std::ostringstream os;
        os << name << " DUT=" << hex32(got) << " REF=" << hex32(expected)
           << " at commit#" << commit_count_;
        return os.str();
    };
    auto diff1 = [&](const char* name, bool got, bool expected) {
        std::ostringstream os;
        os << name << " DUT=" << got << " REF=" << expected
           << " at pc=" << hex32(dut.pc) << " inst=" << hex32(dut.inst)
           << " commit#" << commit_count_;
        return os.str();
    };

    if (dut.pc != ref.pc) return diff32("pc", dut.pc, ref.pc);
    if (dut.inst != ref.inst) return diff32("inst", dut.inst, ref.inst);
    if (dut.is_trap != ref.is_trap) return diff1("trap", dut.is_trap, ref.is_trap);
    if (dut.is_trap && dut.cause != ref.cause) return diff32("cause", dut.cause, ref.cause);
    if (dut.next_pc != ref.next_pc) return diff32("next_pc", dut.next_pc, ref.next_pc);
    if (dut.is_load != ref.is_load) return diff1("is_load", dut.is_load, ref.is_load);
    if (dut.is_store != ref.is_store) return diff1("is_store", dut.is_store, ref.is_store);
    if ((ref.is_load || ref.is_store) && dut.mem_addr != ref.mem_addr)
        return diff32("mem_addr", dut.mem_addr, ref.mem_addr);
    if (ref.is_store && dut.mem_wdata != ref.mem_wdata)
        return diff32("store_data", dut.mem_wdata, ref.mem_wdata);
    if (ref.is_store && dut.mem_wstrb != ref.mem_wstrb)
        return diff32("store_strb", dut.mem_wstrb, ref.mem_wstrb);
    if (dut.wen != ref.wen) return diff1("wen", dut.wen, ref.wen);
    if (ref.wen && dut.rd != ref.rd) return diff32("rd", dut.rd, ref.rd);
    if (ref.wen && dut.wdata != ref.wdata) return diff32("wdata", dut.wdata, ref.wdata);
    return {};
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
    out << "    \"mode\": \"openxiangshan_dpic_rv32_reference\",\n";
    out << "    \"reference_enabled\": true,\n";
    out << "    \"commit_count\": " << adapter.commit_count() << ",\n";
    out << "    \"mmio_skip_count\": " << adapter.mmio_skip_count() << ",\n";
    out << "    \"last_commit_pc\": \"" << hex32(adapter.last_commit_pc()) << "\"\n";
    out << "  }\n";
}

}  // namespace difftest
