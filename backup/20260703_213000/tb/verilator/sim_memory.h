#ifndef TB_VERILATOR_SIM_MEMORY_H
#define TB_VERILATOR_SIM_MEMORY_H

#include "sim_common.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

class VmyCPU;

namespace sim {

class MemoryModel {
public:
    void load_irom(const std::string& path);
    void load_sparse_words(const std::string& path, uint32_t base);

    uint32_t irom_data_a() const;
    uint32_t irom_data_b() const;
    uint32_t current_perip_rdata() const;
    void tick_posedge(const Request& req, uint64_t cycles_per_ms);

    uint32_t read_aligned_word(uint32_t addr) const;
    uint32_t read_shifted_word(uint32_t addr) const;
    void write_word_masked(uint32_t addr, uint32_t data, uint8_t mask);

    uint32_t sw0 = 0;
    uint32_t sw1 = 0;
    uint32_t key = 0;
    uint32_t led = 0;
    uint32_t seg_wdata = 0;
    bool counter_enabled = false;
    uint64_t counter_subcycle = 0;
    uint32_t counter_ms = 0;

private:
    void tick_counter(uint64_t cycles_per_ms);

    std::vector<uint32_t> irom_;
    std::map<uint32_t, uint32_t> mem_;
    uint32_t irom_addr_a_q_ = 0;
    uint32_t irom_addr_b_q_ = 0;
    uint32_t read_addr_pipe0_ = 0;
    uint32_t read_addr_pipe1_ = 0;
    bool read_valid_pipe0_ = false;
    bool read_valid_pipe1_ = false;
    bool mmio_sel_q_ = false;
    bool cnt_sel_q_ = false;
    uint32_t mmio_addr_q_ = 0;
};

std::vector<uint32_t> load_words(const std::string& path);
void drive_inputs(VmyCPU& top, const MemoryModel& mem);
Request capture_request(const VmyCPU& top);

}  // namespace sim

#endif  // TB_VERILATOR_SIM_MEMORY_H
