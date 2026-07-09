#include "dut_commit_io.h"

#include "Vstudent_top.h"

namespace difftest {

CommitTrace capture_commit(const Vstudent_top& top) {
    CommitTrace c;
    c.valid = top.dbg_commit_valid;
    c.pc = top.dbg_commit_pc;
    c.inst = top.dbg_commit_inst;
    c.wen = top.dbg_commit_wen;
    c.rd = static_cast<uint8_t>(top.dbg_commit_rd);
    c.wdata = top.dbg_commit_wdata;
    c.is_load = top.dbg_commit_is_load;
    c.is_store = top.dbg_commit_is_store;
    c.is_mmio = top.dbg_commit_is_mmio;
    c.is_trap = top.dbg_commit_is_trap;
    c.cause = top.dbg_commit_cause;
    c.next_pc = top.dbg_commit_next_pc;
    return c;
}

}  // namespace difftest
