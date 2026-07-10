#include "dut_commit_io.h"

#include "Vstudent_top.h"

namespace difftest {

namespace {

uint32_t lane32(uint64_t packed, int lane) {
    return static_cast<uint32_t>(packed >> (lane * 32));
}

}  // namespace

std::array<CommitTrace, kCommitWidth> capture_commits(const Vstudent_top& top) {
    std::array<CommitTrace, kCommitWidth> commits{};
    for (int lane = 0; lane < kCommitWidth; ++lane) {
        CommitTrace& c = commits[lane];
        c.valid = (top.dbg_commit_valid >> lane) & 1u;
        c.pc = lane32(top.dbg_commit_pc, lane);
        c.inst = lane32(top.dbg_commit_inst, lane);
        c.wen = (top.dbg_commit_wen >> lane) & 1u;
        c.rd = static_cast<uint8_t>((top.dbg_commit_rd >> (lane * 5)) & 0x1fu);
        c.wdata = lane32(top.dbg_commit_wdata, lane);
        c.is_load = (top.dbg_commit_is_load >> lane) & 1u;
        c.is_store = (top.dbg_commit_is_store >> lane) & 1u;
        c.is_mmio = (top.dbg_commit_is_mmio >> lane) & 1u;
        c.is_trap = (top.dbg_commit_is_trap >> lane) & 1u;
        c.cause = lane32(top.dbg_commit_cause, lane);
        c.next_pc = lane32(top.dbg_commit_next_pc, lane);
    }
    return commits;
}

}  // namespace difftest
