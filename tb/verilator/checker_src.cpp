#include "checker_src.h"

namespace sim {

namespace {

uint32_t decode_bcd_nibbles(uint32_t value, int nibbles) {
    uint32_t decoded = 0;
    for (int i = nibbles - 1; i >= 0; --i) {
        uint32_t digit = (value >> (i * 4)) & 0xfu;
        if (digit > 9u) return 0xffffffffu;
        decoded = decoded * 10u + digit;
    }
    return decoded;
}

bool marker_matches(uint32_t value, bool has_marker, uint32_t marker) {
    return has_marker && (value & marker) == marker;
}

}  // namespace

void SrcLedSegChecker::pre_tick(uint64_t cycle, const Request& req, const MemoryModel&,
                                SimResult& result) {
    if (!req.perip_wen || req.perip_addr != LED_ADDR) return;

    result.last_led = req.perip_wdata;
    if (req.perip_wdata == opt_.src_led_fail) {
        result.status = "FAIL";
        result.reason = "LED wrote fail signature";
        result.cycles = cycle;
        done_ = true;
        return;
    }
    if (req.perip_wdata == opt_.src_led_pass && !result.saw_led_pass) {
        result.saw_led_pass = true;
        result.led_pass_cycle = cycle;
    }
}

void SrcLedSegChecker::post_tick(uint64_t cycle, const Request&, const MemoryModel& mem,
                                 SimResult& result) {
    result.last_seg_wdata = mem.seg_wdata;
    result.counter_ms = mem.counter_ms;
    if (done_ || !result.saw_led_pass) return;

    uint64_t virtual_seg = virtual_seg_encode(mem.seg_wdata, cycle);
    if (!result.saw_seg_match && bcd_seg_matches(mem.seg_wdata, mem.counter_ms)) {
        result.saw_seg_match = true;
        result.seg_match_cycle = cycle;
    }
    if (!result.saw_virtual_seg_match &&
        seg_decoder_.observe(virtual_seg, mem.seg_wdata)) {
        result.saw_virtual_seg_match = true;
        result.virtual_seg_match_cycle = cycle;
    }
    if (result.saw_seg_match && result.saw_virtual_seg_match) {
        result.status = "PASS";
        result.reason = "LED and SEG checks passed";
        result.cycles = cycle;
        done_ = true;
        return;
    }
    if (cycle - result.led_pass_cycle > opt_.src_seg_grace) {
        result.status = "FAIL";
        result.reason = "SEG did not match within grace window";
        result.cycles = cycle;
        done_ = true;
    }
}

void SrcObserveChecker::observe_counter_write(const Request& req, SimResult& result) {
    if (!req.perip_wen) return;
    uint32_t aligned = req.perip_addr & ~uint32_t{3};
    if (opt_.has_pass_counter_addr && aligned == (opt_.pass_counter_addr & ~uint32_t{3})) {
        result.saw_pass_counter = true;
        result.last_pass_counter = req.perip_wdata;
    }
    if (opt_.has_fail_counter_addr && aligned == (opt_.fail_counter_addr & ~uint32_t{3})) {
        result.saw_fail_counter = true;
        result.last_fail_counter = req.perip_wdata;
    }
}

void SrcObserveChecker::pre_tick(uint64_t, const Request& req, const MemoryModel&,
                                 SimResult& result) {
    if (req.perip_wen && req.perip_addr == LED_ADDR) {
        result.last_led = req.perip_wdata;
    }
    observe_counter_write(req, result);
}

void SrcObserveChecker::post_tick(uint64_t, const Request&, const MemoryModel& mem,
                                  SimResult& result) {
    result.last_seg_wdata = mem.seg_wdata;
    result.counter_ms = mem.counter_ms;
}

void SrcMemCntChecker::pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                                SimResult& result) {
    SrcObserveChecker::pre_tick(cycle, req, mem, result);

    if (opt_.has_fail_counter_addr && result.saw_fail_counter &&
        result.last_fail_counter != 0) {
        result.status = "FAIL";
        result.reason = "fail counter wrote non-zero value";
        result.cycles = cycle;
        done_ = true;
        return;
    }
    if (opt_.has_expected_pass_count && result.saw_pass_counter &&
        result.last_pass_counter >= opt_.expected_pass_count &&
        (!result.saw_fail_counter || result.last_fail_counter == 0)) {
        result.status = "PASS";
        result.reason = "pass counter reached expected count";
        result.cycles = cycle;
        done_ = true;
    }
}

void SrcLampSegChecker::pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                                 SimResult& result) {
    SrcObserveChecker::pre_tick(cycle, req, mem, result);
    if (!req.perip_wen || req.perip_addr != LED_ADDR) return;

    uint32_t value = req.perip_wdata;
    if (opt_.has_src_test_mask) {
        result.last_src_test_lamps = value & opt_.src_test_mask;
    }

    if (marker_matches(value, opt_.has_src_fail_marker, opt_.src_fail_marker)) {
        result.saw_src_fail_marker = true;
        result.status = "FAIL";
        result.reason = "SRC final fail lamp marker observed";
        result.cycles = cycle;
        done_ = true;
        return;
    }

    if (marker_matches(value, opt_.has_src_pass_marker, opt_.src_pass_marker)) {
        result.saw_src_pass_marker = true;
        if (opt_.has_src_test_mask && result.last_src_test_lamps != opt_.src_test_mask) {
            result.status = "FAIL";
            result.reason = "SRC pass marker observed but not all test lamps are set";
            result.cycles = cycle;
            done_ = true;
            return;
        }
        if (opt_.has_expected_rv32i_count &&
            result.last_rv32i_count != opt_.expected_rv32i_count) {
            result.status = "FAIL";
            result.reason = "SRC pass marker observed but RV32I count is not expected";
            result.cycles = cycle;
            done_ = true;
            return;
        }
        if (opt_.has_expected_mext_count &&
            result.last_mext_count != opt_.expected_mext_count) {
            result.status = "FAIL";
            result.reason = "SRC pass marker observed but M/Z test count is not expected";
            result.cycles = cycle;
            done_ = true;
            return;
        }
        result.status = "PASS";
        result.reason = "SRC final pass lamp marker and counters observed";
        result.cycles = cycle;
        done_ = true;
    }
}

void SrcLampSegChecker::post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                                  SimResult& result) {
    SrcObserveChecker::post_tick(cycle, req, mem, result);
    uint32_t rv32i_bcd = (mem.seg_wdata >> 24) & 0xffu;
    uint32_t rv32i = decode_bcd_nibbles(rv32i_bcd, 2);
    if (rv32i != 0xffffffffu) {
        result.last_rv32i_count = rv32i;
    }

    uint32_t mext_bcd = (mem.seg_wdata >> 20) & 0xfu;
    uint32_t mext = decode_bcd_nibbles(mext_bcd, 1);
    if (mext != 0xffffffffu) {
        result.last_mext_count = mext;
    }
}

}  // namespace sim
