#ifndef TB_DIFFTEST_ADAPTER_REFERENCE_MODEL_H
#define TB_DIFFTEST_ADAPTER_REFERENCE_MODEL_H

#include "commit_trace.h"
#include "../../verilator/sim_common.h"

#include <array>
#include <cstdint>
#include <map>
#include <string>

namespace difftest {

struct ReferenceStep {
    CommitTrace commit;
    bool nondeterministic = false;
    std::string error;
};

class ReferenceModel {
public:
    explicit ReferenceModel(const sim::Options& opt);
    ReferenceStep step(uint64_t cycle, const CommitTrace& dut);

private:
    std::array<uint32_t, 32> gpr_{};
    std::map<uint32_t, uint8_t> memory_;
    uint32_t pc_ = sim::IROM_BASE;
    uint32_t mstatus_ = 0x00001800u;
    uint32_t mtvec_ = 0;
    uint32_t mscratch_ = 0;
    uint32_t mepc_ = 0;
    uint32_t mcause_ = 0;
    uint32_t mtval_ = 0;
    uint64_t instret_ = 0;

    void load_image(const std::string& path, uint32_t base);
    uint8_t read8(uint32_t addr) const;
    uint16_t read16(uint32_t addr) const;
    uint32_t read32(uint32_t addr) const;
    void write8(uint32_t addr, uint8_t value);
    void write16(uint32_t addr, uint16_t value);
    void write32(uint32_t addr, uint32_t value);
    uint32_t read_csr(uint16_t addr, uint64_t cycle, bool& nondeterministic,
                      const CommitTrace& dut) const;
    void write_csr(uint16_t addr, uint32_t value);
};

}  // namespace difftest

#endif
