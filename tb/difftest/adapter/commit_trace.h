#ifndef TB_DIFFTEST_ADAPTER_COMMIT_TRACE_H
#define TB_DIFFTEST_ADAPTER_COMMIT_TRACE_H

#include <cstdint>

namespace difftest {

struct CommitTrace {
    bool valid = false;
    uint32_t pc = 0;
    uint32_t inst = 0;
    bool wen = false;
    uint8_t rd = 0;
    uint32_t wdata = 0;
    bool is_load = false;
    bool is_store = false;
    bool is_mmio = false;
    uint32_t mem_addr = 0;
    uint32_t mem_wdata = 0;
    uint8_t mem_wstrb = 0;
    bool is_trap = false;
    uint32_t cause = 0;
    uint32_t next_pc = 0;
};

}  // namespace difftest

#endif  // TB_DIFFTEST_ADAPTER_COMMIT_TRACE_H
