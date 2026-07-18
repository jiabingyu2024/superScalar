#include "reference_model.h"

#include "../../verilator/sim_memory.h"

#include <climits>
#include <cstdint>

#ifndef REF_ZBA
#define REF_ZBA 0
#define REF_ZBB 0
#define REF_ZBC 0
#define REF_ZBKB 0
#define REF_ZBKX 0
#define REF_ZBS 0
#endif

namespace difftest {
namespace {

uint32_t sext(uint32_t value, unsigned bits) {
    const uint32_t sign = uint32_t{1} << (bits - 1);
    return (value ^ sign) - sign;
}

uint32_t rotl32(uint32_t value, unsigned shamt) {
    shamt &= 31u;
    return (value << shamt) | (value >> ((32u - shamt) & 31u));
}

uint32_t rotr32(uint32_t value, unsigned shamt) {
    shamt &= 31u;
    return (value >> shamt) | (value << ((32u - shamt) & 31u));
}

uint64_t clmul64(uint32_t a, uint32_t b) {
    uint64_t result = 0;
    for (unsigned i = 0; i < 32; ++i) {
        if ((b >> i) & 1u) result ^= uint64_t{a} << i;
    }
    return result;
}

uint32_t zip32(uint32_t value) {
    uint32_t result = 0;
    for (unsigned i = 0; i < 16; ++i) {
        result |= ((value >> i) & 1u) << (2 * i);
        result |= ((value >> (i + 16)) & 1u) << (2 * i + 1);
    }
    return result;
}

uint32_t unzip32(uint32_t value) {
    uint32_t result = 0;
    for (unsigned i = 0; i < 16; ++i) {
        result |= ((value >> (2 * i)) & 1u) << i;
        result |= ((value >> (2 * i + 1)) & 1u) << (i + 16);
    }
    return result;
}

bool execute_bitmanip(uint32_t inst, uint32_t a, uint32_t b, uint32_t& result) {
    const uint32_t opcode = inst & 0x7fu;
    const uint32_t funct3 = (inst >> 12) & 7u;
    const uint32_t funct7 = inst >> 25;
    const uint32_t imm12 = inst >> 20;
    const uint32_t shamt = (opcode == 0x13u) ? ((inst >> 20) & 31u) : (b & 31u);

    if (opcode == 0x13u) {
        if (REF_ZBB && funct3 == 1 && imm12 >= 0x600 && imm12 <= 0x605) {
            switch (imm12) {
                case 0x600: result = a ? static_cast<uint32_t>(__builtin_clz(a)) : 32; return true;
                case 0x601: result = a ? static_cast<uint32_t>(__builtin_ctz(a)) : 32; return true;
                case 0x602: result = static_cast<uint32_t>(__builtin_popcount(a)); return true;
                case 0x604: result = sext(a & 0xffu, 8); return true;
                case 0x605: result = sext(a & 0xffffu, 16); return true;
                default: break;
            }
        }
        if (REF_ZBB && funct3 == 5 && imm12 == 0x287) {
            result = 0;
            for (unsigned i = 0; i < 4; ++i)
                if ((a & (0xffu << (8 * i))) != 0) result |= 0xffu << (8 * i);
            return true;
        }
        if (REF_ZBB && funct3 == 5 && imm12 == 0x698) {
            result = __builtin_bswap32(a); return true;
        }
        if (REF_ZBKB && funct3 == 5 && imm12 == 0x687) {
            result = 0;
            for (unsigned byte = 0; byte < 4; ++byte)
                for (unsigned bit = 0; bit < 8; ++bit)
                    result |= ((a >> (byte * 8 + bit)) & 1u) << (byte * 8 + 7 - bit);
            return true;
        }
        if (REF_ZBKB && imm12 == 0x08f && funct3 == 1) { result = zip32(a); return true; }
        if (REF_ZBKB && imm12 == 0x08f && funct3 == 5) { result = unzip32(a); return true; }
        if ((REF_ZBB || REF_ZBKB) && funct3 == 5 && funct7 == 0x30) {
            result = rotr32(a, shamt); return true;
        }
        if (REF_ZBS && funct7 == 0x24 && funct3 == 1) { result = a & ~(1u << shamt); return true; }
        if (REF_ZBS && funct7 == 0x24 && funct3 == 5) { result = (a >> shamt) & 1u; return true; }
        if (REF_ZBS && funct7 == 0x34 && funct3 == 1) { result = a ^ (1u << shamt); return true; }
        if (REF_ZBS && funct7 == 0x14 && funct3 == 1) { result = a | (1u << shamt); return true; }
        return false;
    }

    if (opcode != 0x33u) return false;
    const uint32_t key = (funct7 << 3) | funct3;
    switch (key) {
        case (0x10u << 3) | 2u: if (REF_ZBA) { result = (a << 1) + b; return true; } break;
        case (0x10u << 3) | 4u: if (REF_ZBA) { result = (a << 2) + b; return true; } break;
        case (0x10u << 3) | 6u: if (REF_ZBA) { result = (a << 3) + b; return true; } break;
        case (0x20u << 3) | 7u: if (REF_ZBB || REF_ZBKB) { result = a & ~b; return true; } break;
        case (0x20u << 3) | 6u: if (REF_ZBB || REF_ZBKB) { result = a | ~b; return true; } break;
        case (0x20u << 3) | 4u: if (REF_ZBB || REF_ZBKB) { result = ~(a ^ b); return true; } break;
        case (0x30u << 3) | 1u: if (REF_ZBB || REF_ZBKB) { result = rotl32(a, b); return true; } break;
        case (0x30u << 3) | 5u: if (REF_ZBB || REF_ZBKB) { result = rotr32(a, b); return true; } break;
        case (0x05u << 3) | 4u: if (REF_ZBB) { result = static_cast<int32_t>(a) < static_cast<int32_t>(b) ? a : b; return true; } break;
        case (0x05u << 3) | 5u: if (REF_ZBB) { result = a < b ? a : b; return true; } break;
        case (0x05u << 3) | 6u: if (REF_ZBB) { result = static_cast<int32_t>(a) < static_cast<int32_t>(b) ? b : a; return true; } break;
        case (0x05u << 3) | 7u: if (REF_ZBB) { result = a < b ? b : a; return true; } break;
        case (0x04u << 3) | 4u:
            if (REF_ZBKB) { result = (b << 16) | (a & 0xffffu); return true; }
            if (REF_ZBB && ((inst >> 20) & 31u) == 0) { result = a & 0xffffu; return true; }
            break;
        case (0x04u << 3) | 7u: if (REF_ZBKB) { result = ((b & 0xffu) << 8) | (a & 0xffu); return true; } break;
        case (0x05u << 3) | 1u: if (REF_ZBC) { result = static_cast<uint32_t>(clmul64(a, b)); return true; } break;
        case (0x05u << 3) | 3u: if (REF_ZBC) { result = static_cast<uint32_t>(clmul64(a, b) >> 32); return true; } break;
        case (0x05u << 3) | 2u: if (REF_ZBC) { result = static_cast<uint32_t>(clmul64(a, b) >> 31); return true; } break;
        case (0x14u << 3) | 2u:
            if (REF_ZBKX) {
                result = 0; for (unsigned i = 0; i < 8; ++i) { unsigned idx = (b >> (4 * i)) & 0xfu; if (idx < 8) result |= ((a >> (4 * idx)) & 0xfu) << (4 * i); } return true;
            } break;
        case (0x14u << 3) | 4u:
            if (REF_ZBKX) {
                result = 0; for (unsigned i = 0; i < 4; ++i) { unsigned idx = (b >> (8 * i)) & 0xffu; if (idx < 4) result |= ((a >> (8 * idx)) & 0xffu) << (8 * i); } return true;
            } break;
        case (0x24u << 3) | 1u: if (REF_ZBS) { result = a & ~(1u << (b & 31u)); return true; } break;
        case (0x24u << 3) | 5u: if (REF_ZBS) { result = (a >> (b & 31u)) & 1u; return true; } break;
        case (0x34u << 3) | 1u: if (REF_ZBS) { result = a ^ (1u << (b & 31u)); return true; } break;
        case (0x14u << 3) | 1u: if (REF_ZBS) { result = a | (1u << (b & 31u)); return true; } break;
        default: break;
    }
    return false;
}

}  // namespace

ReferenceModel::ReferenceModel(const sim::Options& opt) {
    load_image(opt.irom_hex, sim::IROM_BASE);
    if (!opt.dram_hex.empty()) load_image(opt.dram_hex, sim::SRC_DRAM_BASE);
}

void ReferenceModel::load_image(const std::string& path, uint32_t base) {
    const auto words = sim::load_words(path);
    for (size_t i = 0; i < words.size(); ++i) write32(base + static_cast<uint32_t>(i * 4), words[i]);
}

uint8_t ReferenceModel::read8(uint32_t addr) const {
    const auto it = memory_.find(addr);
    return it == memory_.end() ? 0 : it->second;
}
uint16_t ReferenceModel::read16(uint32_t addr) const { return uint16_t(read8(addr)) | (uint16_t(read8(addr + 1)) << 8); }
uint32_t ReferenceModel::read32(uint32_t addr) const { return uint32_t(read16(addr)) | (uint32_t(read16(addr + 2)) << 16); }
void ReferenceModel::write8(uint32_t addr, uint8_t value) { memory_[addr] = value; }
void ReferenceModel::write16(uint32_t addr, uint16_t value) { write8(addr, value); write8(addr + 1, value >> 8); }
void ReferenceModel::write32(uint32_t addr, uint32_t value) { write16(addr, value); write16(addr + 2, value >> 16); }

uint32_t ReferenceModel::read_csr(uint16_t addr, uint64_t cycle, bool& nondeterministic,
                                  const CommitTrace& dut) const {
    switch (addr) {
        case 0x300: return mstatus_;
        case 0x301: return 0x40001100u;
        case 0x305: return mtvec_;
        case 0x340: return mscratch_;
        case 0x341: return mepc_;
        case 0x342: return mcause_;
        case 0x343: return mtval_;
        case 0xc00: case 0xc80:
            (void)cycle; nondeterministic = true; return dut.wdata;
        case 0xc02: return static_cast<uint32_t>(instret_);
        case 0xc82: return static_cast<uint32_t>(instret_ >> 32);
        case 0xf14: return 0;
        default: return 0;
    }
}

void ReferenceModel::write_csr(uint16_t addr, uint32_t value) {
    switch (addr) {
        case 0x300: mstatus_ = value; break;
        case 0x305: mtvec_ = value & ~3u; break;
        case 0x340: mscratch_ = value; break;
        case 0x341: mepc_ = value & ~3u; break;
        case 0x342: mcause_ = value; break;
        case 0x343: mtval_ = value; break;
        default: break;
    }
}

ReferenceStep ReferenceModel::step(uint64_t cycle, const CommitTrace& dut) {
    ReferenceStep out;
    CommitTrace& exp = out.commit;
    exp.valid = true;
    exp.pc = pc_;
    exp.inst = read32(pc_);
    exp.next_pc = pc_ + 4;

    const uint32_t inst = exp.inst;
    const uint32_t opcode = inst & 0x7fu;
    const uint32_t rd = (inst >> 7) & 31u;
    const uint32_t funct3 = (inst >> 12) & 7u;
    const uint32_t rs1 = (inst >> 15) & 31u;
    const uint32_t rs2 = (inst >> 20) & 31u;
    const uint32_t funct7 = inst >> 25;
    const uint32_t a = gpr_[rs1];
    const uint32_t b = gpr_[rs2];
    bool legal = true;
    bool trap = false;
    uint32_t trap_cause = 2;
    uint32_t trap_tval = inst;
    bool write_rd = false;
    uint32_t result = 0;

    auto set_rd = [&](uint32_t value) { write_rd = true; result = value; };
    auto set_trap = [&](uint32_t cause, uint32_t tval) { trap = true; trap_cause = cause; trap_tval = tval; };

    switch (opcode) {
        case 0x37: set_rd(inst & 0xfffff000u); break;
        case 0x17: set_rd(pc_ + (inst & 0xfffff000u)); break;
        case 0x6f: {
            uint32_t imm = sext(((inst >> 31) << 20) | (((inst >> 12) & 0xffu) << 12) |
                                (((inst >> 20) & 1u) << 11) | (((inst >> 21) & 0x3ffu) << 1), 21);
            uint32_t target = pc_ + imm;
            if (target & 3u) set_trap(0, target); else { set_rd(pc_ + 4); exp.next_pc = target; }
            break;
        }
        case 0x67: {
            if (funct3 != 0) { legal = false; break; }
            uint32_t target = (a + sext(inst >> 20, 12)) & ~1u;
            if (target & 3u) set_trap(0, target); else { set_rd(pc_ + 4); exp.next_pc = target; }
            break;
        }
        case 0x63: {
            uint32_t imm = sext(((inst >> 31) << 12) | (((inst >> 7) & 1u) << 11) |
                                (((inst >> 25) & 0x3fu) << 5) | (((inst >> 8) & 0xfu) << 1), 13);
            bool taken = false;
            switch (funct3) {
                case 0: taken = a == b; break; case 1: taken = a != b; break;
                case 4: taken = static_cast<int32_t>(a) < static_cast<int32_t>(b); break;
                case 5: taken = static_cast<int32_t>(a) >= static_cast<int32_t>(b); break;
                case 6: taken = a < b; break; case 7: taken = a >= b; break;
                default: legal = false; break;
            }
            if (legal && taken) { uint32_t target = pc_ + imm; if (target & 3u) set_trap(0, target); else exp.next_pc = target; }
            break;
        }
        case 0x03: {
            exp.is_load = true; exp.mem_addr = a + sext(inst >> 20, 12);
            exp.is_mmio = sim::is_known_mmio_addr(exp.mem_addr);
            const bool misaligned = ((funct3 == 1 || funct3 == 5) && (exp.mem_addr & 1u)) ||
                                    (funct3 == 2 && (exp.mem_addr & 3u));
            if (misaligned) { set_trap(4, exp.mem_addr); break; }
            if (exp.is_mmio) { out.nondeterministic = true; set_rd(dut.wdata); break; }
            switch (funct3) {
                case 0: set_rd(sext(read8(exp.mem_addr), 8)); break;
                case 1: set_rd(sext(read16(exp.mem_addr), 16)); break;
                case 2: set_rd(read32(exp.mem_addr)); break;
                case 4: set_rd(read8(exp.mem_addr)); break;
                case 5: set_rd(read16(exp.mem_addr)); break;
                default: legal = false; break;
            }
            break;
        }
        case 0x23: {
            exp.is_store = true;
            uint32_t imm = sext(((inst >> 25) << 5) | ((inst >> 7) & 31u), 12);
            exp.mem_addr = a + imm; exp.is_mmio = sim::is_known_mmio_addr(exp.mem_addr);
            const bool misaligned = (funct3 == 1 && (exp.mem_addr & 1u)) || (funct3 == 2 && (exp.mem_addr & 3u));
            if (misaligned) { set_trap(6, exp.mem_addr); break; }
            exp.mem_wdata = b;
            exp.mem_wstrb = funct3 == 0 ? 0x1u : funct3 == 1 ? 0x3u : 0xfu;
            if (exp.is_mmio) { out.nondeterministic = true; break; }
            if (funct3 == 0) write8(exp.mem_addr, b);
            else if (funct3 == 1) write16(exp.mem_addr, b);
            else if (funct3 == 2) write32(exp.mem_addr, b);
            else legal = false;
            break;
        }
        case 0x13: {
            if (execute_bitmanip(inst, a, b, result)) { write_rd = true; break; }
            uint32_t imm = sext(inst >> 20, 12);
            switch (funct3) {
                case 0: set_rd(a + imm); break;
                case 2: set_rd(static_cast<int32_t>(a) < static_cast<int32_t>(imm)); break;
                case 3: set_rd(a < imm); break;
                case 4: set_rd(a ^ imm); break; case 6: set_rd(a | imm); break; case 7: set_rd(a & imm); break;
                case 1: if (funct7 == 0) set_rd(a << (rs2 & 31u)); else legal = false; break;
                case 5: if (funct7 == 0) set_rd(a >> (rs2 & 31u)); else if (funct7 == 0x20) set_rd(static_cast<uint32_t>(static_cast<int32_t>(a) >> (rs2 & 31u))); else legal = false; break;
                default: legal = false; break;
            }
            break;
        }
        case 0x33: {
            if (funct7 == 1) {
                switch (funct3) {
                    case 0: set_rd(static_cast<uint32_t>(uint64_t(a) * uint64_t(b))); break;
                    case 1: set_rd(static_cast<uint32_t>((int64_t(static_cast<int32_t>(a)) * int64_t(static_cast<int32_t>(b))) >> 32)); break;
                    case 2: set_rd(static_cast<uint32_t>((int64_t(static_cast<int32_t>(a)) * int64_t(uint64_t(b))) >> 32)); break;
                    case 3: set_rd(static_cast<uint32_t>((uint64_t(a) * uint64_t(b)) >> 32)); break;
                    case 4: if (b == 0) set_rd(0xffffffffu); else if (a == 0x80000000u && b == 0xffffffffu) set_rd(a); else set_rd(static_cast<uint32_t>(static_cast<int32_t>(a) / static_cast<int32_t>(b))); break;
                    case 5: set_rd(b == 0 ? 0xffffffffu : a / b); break;
                    case 6: if (b == 0) set_rd(a); else if (a == 0x80000000u && b == 0xffffffffu) set_rd(0); else set_rd(static_cast<uint32_t>(static_cast<int32_t>(a) % static_cast<int32_t>(b))); break;
                    case 7: set_rd(b == 0 ? a : a % b); break;
                }
                break;
            }
            if (execute_bitmanip(inst, a, b, result)) { write_rd = true; break; }
            switch (funct3) {
                case 0: if (funct7 == 0) set_rd(a + b); else if (funct7 == 0x20) set_rd(a - b); else legal = false; break;
                case 1: if (funct7 == 0) set_rd(a << (b & 31u)); else legal = false; break;
                case 2: if (funct7 == 0) set_rd(static_cast<int32_t>(a) < static_cast<int32_t>(b)); else legal = false; break;
                case 3: if (funct7 == 0) set_rd(a < b); else legal = false; break;
                case 4: if (funct7 == 0) set_rd(a ^ b); else legal = false; break;
                case 5: if (funct7 == 0) set_rd(a >> (b & 31u)); else if (funct7 == 0x20) set_rd(static_cast<uint32_t>(static_cast<int32_t>(a) >> (b & 31u))); else legal = false; break;
                case 6: if (funct7 == 0) set_rd(a | b); else legal = false; break;
                case 7: if (funct7 == 0) set_rd(a & b); else legal = false; break;
            }
            break;
        }
        case 0x0f: if (funct3 != 0 && funct3 != 1) legal = false; break;
        case 0x73: {
            if (funct3 == 0) {
                uint32_t sys = inst >> 20;
                if (sys == 0) set_trap(11, 0);
                else if (sys == 1) set_trap(3, 0);
                else if (sys == 0x302) {
                    exp.next_pc = mepc_ & ~3u;
                    mstatus_ = (mstatus_ & ~((3u << 11) | (1u << 3) | (1u << 7))) |
                               (((mstatus_ >> 7) & 1u) << 3) | (1u << 7);
                } else legal = false;
            } else if ((funct3 & 3u) != 0) {
                const uint16_t csr = inst >> 20;
                const uint32_t src = (funct3 & 4u) ? rs1 : a;
                bool nondeterministic = false;
                const uint32_t old = read_csr(csr, cycle, nondeterministic, dut);
                out.nondeterministic |= nondeterministic;
                set_rd(old);
                if ((funct3 & 3u) == 1) write_csr(csr, src);
                else if ((funct3 & 3u) == 2 && src != 0) write_csr(csr, old | src);
                else if ((funct3 & 3u) == 3 && src != 0) write_csr(csr, old & ~src);
            } else legal = false;
            break;
        }
        default: legal = false; break;
    }

    if (!legal) set_trap(2, inst);
    if (trap) {
        exp.is_trap = true; exp.cause = trap_cause; exp.next_pc = mtvec_ & ~3u;
        exp.wen = false; exp.rd = static_cast<uint8_t>(rd); exp.wdata = result;
        mepc_ = pc_ & ~3u; mcause_ = trap_cause; mtval_ = trap_tval;
        mstatus_ = (mstatus_ & ~((3u << 11) | (1u << 3) | (1u << 7))) |
                   (((mstatus_ >> 3) & 1u) << 7) | (3u << 11);
    } else {
        exp.wen = write_rd && rd != 0;
        exp.rd = static_cast<uint8_t>(rd);
        exp.wdata = result;
        if (exp.wen) gpr_[rd] = result;
        ++instret_;
    }
    gpr_[0] = 0;
    pc_ = exp.next_pc;
    return out;
}

}  // namespace difftest
