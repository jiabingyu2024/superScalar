#include "sim_memory.h"

#include "VmyCPU.h"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <string>

namespace sim {

namespace {

uint32_t parse_hex_word(const std::string& line) {
    std::string token;
    for (char ch : line) {
        if (std::isxdigit(static_cast<unsigned char>(ch))) {
            token.push_back(ch);
        } else if (!token.empty()) {
            break;
        }
    }
    if (token.empty()) return 0;
    return static_cast<uint32_t>(std::strtoul(token.c_str(), nullptr, 16));
}

}  // namespace

std::vector<uint32_t> load_words(const std::string& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("cannot open hex file: " + path);
    }
    std::vector<uint32_t> words;
    std::string line;
    while (std::getline(in, line)) {
        auto comment = line.find("//");
        if (comment != std::string::npos) line = line.substr(0, comment);
        if (line.find_first_of("0123456789abcdefABCDEF") == std::string::npos) {
            continue;
        }
        words.push_back(parse_hex_word(line));
    }
    return words;
}

void MemoryModel::load_irom(const std::string& path) {
    irom_ = load_words(path);
}

void MemoryModel::load_sparse_words(const std::string& path, uint32_t base) {
    auto words = load_words(path);
    for (size_t i = 0; i < words.size(); ++i) {
        mem_[base + static_cast<uint32_t>(i * 4)] = words[i];
    }
}

uint32_t MemoryModel::irom_data_a() const {
    size_t idx = (irom_addr_a_q_ >> 2) & 0xfffu;
    return idx < irom_.size() ? irom_[idx] : 0;
}

uint32_t MemoryModel::irom_data_b() const {
    size_t idx = (irom_addr_b_q_ >> 2) & 0xfffu;
    return idx < irom_.size() ? irom_[idx] : 0;
}

uint32_t MemoryModel::read_aligned_word(uint32_t addr) const {
    uint32_t aligned = addr & ~uint32_t{3};
    auto it = mem_.find(aligned);
    return it == mem_.end() ? 0 : it->second;
}

uint32_t MemoryModel::read_shifted_word(uint32_t addr) const {
    uint32_t word = read_aligned_word(addr);
    return word >> ((addr & 3u) * 8u);
}

void MemoryModel::write_word_masked(uint32_t addr, uint32_t data, uint8_t mask) {
    uint32_t aligned = addr & ~uint32_t{3};
    uint32_t offset = addr & 3u;
    uint32_t write_data = data << (offset * 8u);
    uint8_t write_mask = (mask << offset) & 0xfu;
    uint32_t old = read_aligned_word(aligned);
    uint32_t next = old;
    for (int i = 0; i < 4; ++i) {
        if (write_mask & (1u << i)) {
            next &= ~(0xffu << (i * 8));
            next |= ((write_data >> (i * 8)) & 0xffu) << (i * 8);
        }
    }
    mem_[aligned] = next;
}

uint32_t MemoryModel::current_perip_rdata() const {
    if (read_valid_pipe1_) {
        return read_shifted_word(read_addr_pipe1_);
    }
    if (mmio_sel_q_) {
        switch (mmio_addr_q_) {
            case SW0_ADDR: return sw0;
            case SW1_ADDR: return sw1;
            case KEY_ADDR: return key & 0xffu;
            case SEG_ADDR: return seg_wdata;
            default: return 0xdeadbeefu;
        }
    }
    if (cnt_sel_q_) {
        return counter_ms;
    }
    return 0;
}

void MemoryModel::tick_counter(uint64_t cycles_per_ms) {
    if (!counter_enabled) {
        counter_subcycle = 0;
        return;
    }
    counter_subcycle++;
    if (counter_subcycle >= cycles_per_ms) {
        counter_subcycle = 0;
        counter_ms++;
    }
}

void MemoryModel::tick_posedge(const Request& req, uint64_t cycles_per_ms) {
    if (req.irom_ena_a) irom_addr_a_q_ = req.irom_addr_a;
    if (req.irom_ena_b) irom_addr_b_q_ = req.irom_addr_b;

    bool is_mmio_read = !req.perip_wen &&
                        (req.perip_addr == SW0_ADDR || req.perip_addr == SW1_ADDR ||
                         req.perip_addr == KEY_ADDR || req.perip_addr == SEG_ADDR);
    bool is_counter_read = !req.perip_wen && req.perip_addr == CNT_ADDR;
    bool is_normal_mem_read = !req.perip_wen && req.perip_addr != 0 &&
                              !is_mmio_read && !is_counter_read;

    read_valid_pipe1_ = read_valid_pipe0_;
    read_addr_pipe1_ = read_addr_pipe0_;
    read_valid_pipe0_ = is_normal_mem_read;
    if (is_normal_mem_read) read_addr_pipe0_ = req.perip_addr;

    mmio_sel_q_ = is_mmio_read;
    cnt_sel_q_ = is_counter_read;
    mmio_addr_q_ = req.perip_addr;

    if (req.perip_wen) {
        if (req.perip_addr == LED_ADDR) {
            led = req.perip_wdata;
        } else if (req.perip_addr == SEG_ADDR) {
            seg_wdata = req.perip_wdata;
        } else if (req.perip_addr == CNT_ADDR) {
            if (req.perip_wdata == CNT_START_CMD) counter_enabled = true;
            if (req.perip_wdata == CNT_STOP_CMD) counter_enabled = false;
        } else {
            write_word_masked(req.perip_addr, req.perip_wdata, req.perip_mask);
        }
    }

    tick_counter(cycles_per_ms);
}

void drive_inputs(VmyCPU& top, const MemoryModel& mem) {
    top.irom_dataA = mem.irom_data_a();
    top.irom_dataB = mem.irom_data_b();
    top.perip_rdata = mem.current_perip_rdata();
}

Request capture_request(const VmyCPU& top) {
    Request req;
    req.irom_addr_a = top.irom_addrA;
    req.irom_addr_b = top.irom_addrB;
    req.irom_ena_a = top.irom_enaA;
    req.irom_ena_b = top.irom_enaB;
    req.perip_addr = top.perip_addr;
    req.perip_wdata = top.perip_wdata;
    req.perip_mask = top.perip_mask & 0xfu;
    req.perip_wen = top.perip_wen;
    return req;
}

}  // namespace sim
