#include "checker_rv32.h"

namespace sim {

void Rv32Checker::pre_tick(uint64_t cycle, const Request& req, const MemoryModel&,
                           SimResult& result) {
    if (!req.perip_wen || req.perip_addr != opt_.tohost_addr) return;

    uint32_t value = req.perip_wdata;
    result.fail_code = value;
    result.cycles = cycle;
    if (value == 1u) {
        result.status = "PASS";
        result.reason = "tohost wrote 1";
        done_ = true;
    } else if (value != 0u) {
        result.status = "FAIL";
        result.reason = "tohost wrote non-pass value " + hex32(value);
        done_ = true;
    }
}

void Rv32Checker::post_tick(uint64_t, const Request&, const MemoryModel&,
                            SimResult&) {}

}  // namespace sim
