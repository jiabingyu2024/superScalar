#include "dut_commit_io.h"

#include "Vstudent_top.h"
#include "../../verilator/sim_common.h"

namespace difftest {

std::array<CommitTrace, kCommitWidth> capture_commits(const Vstudent_top& top) {
    std::array<CommitTrace, kCommitWidth> commits{};
    CommitTrace& c = commits[0];
    c.valid = top.dbg_commit_valid;
    c.pc = top.dbg_commit_pc;
    c.inst = top.dbg_commit_inst;
    c.wen = top.dbg_commit_wen;
    c.rd = static_cast<uint8_t>(top.dbg_commit_rd);
    c.wdata = top.dbg_commit_wdata;
    c.is_load = top.dbg_commit_is_load;
    c.is_store = top.dbg_commit_is_store;
    c.mem_addr = top.dbg_commit_mem_addr;
    c.mem_wdata = top.dbg_commit_mem_wdata;
    c.mem_wstrb = static_cast<uint8_t>(top.dbg_commit_mem_wstrb);
    c.is_mmio = sim::is_known_mmio_addr(c.mem_addr);
    c.is_trap = top.dbg_commit_is_trap;
    c.cause = top.dbg_commit_cause;
    c.next_pc = top.dbg_commit_next_pc;
    return commits;
}

}  // namespace difftest
