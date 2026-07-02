#include "sim_display.h"

namespace sim {

uint8_t seg7_encode(uint8_t digit) {
    static const uint8_t table[16] = {
        0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07,
        0x7f, 0x6f, 0x77, 0x7c, 0x39, 0x5e, 0x79, 0x71
    };
    return table[digit & 0xfu];
}

int seg7_decode(uint8_t encoded) {
    for (int i = 0; i < 16; ++i) {
        if (seg7_encode(static_cast<uint8_t>(i)) == (encoded & 0x7fu)) {
            return i;
        }
    }
    return -1;
}

uint64_t virtual_seg_encode(uint32_t seg_wdata, uint64_t cycle) {
    bool high_phase = ((cycle >> 4) & 1u) == 0;
    uint8_t digits[4];
    uint8_t ans = high_phase ? 0xaa : 0x55;
    if (high_phase) {
        digits[0] = (seg_wdata >> 4) & 0xfu;
        digits[1] = (seg_wdata >> 12) & 0xfu;
        digits[2] = (seg_wdata >> 20) & 0xfu;
        digits[3] = (seg_wdata >> 28) & 0xfu;
    } else {
        digits[0] = seg_wdata & 0xfu;
        digits[1] = (seg_wdata >> 8) & 0xfu;
        digits[2] = (seg_wdata >> 16) & 0xfu;
        digits[3] = (seg_wdata >> 24) & 0xfu;
    }

    uint64_t out = 0;
    out |= uint64_t(seg7_encode(digits[0])) << 0;
    out |= uint64_t((ans >> 0) & 0x3u) << 8;
    out |= uint64_t(seg7_encode(digits[1])) << 10;
    out |= uint64_t((ans >> 2) & 0x3u) << 18;
    out |= uint64_t(seg7_encode(digits[2])) << 20;
    out |= uint64_t((ans >> 4) & 0x3u) << 28;
    out |= uint64_t(seg7_encode(digits[3])) << 30;
    out |= uint64_t((ans >> 6) & 0x3u) << 38;
    return out;
}

bool VirtualSegDecoder::observe(uint64_t encoded, uint32_t expected_wdata) {
    uint8_t ans = 0;
    ans |= uint8_t((encoded >> 8) & 0x3u) << 0;
    ans |= uint8_t((encoded >> 18) & 0x3u) << 2;
    ans |= uint8_t((encoded >> 28) & 0x3u) << 4;
    ans |= uint8_t((encoded >> 38) & 0x3u) << 6;

    int d0 = seg7_decode((encoded >> 0) & 0x7fu);
    int d1 = seg7_decode((encoded >> 10) & 0x7fu);
    int d2 = seg7_decode((encoded >> 20) & 0x7fu);
    int d3 = seg7_decode((encoded >> 30) & 0x7fu);
    if (d0 < 0 || d1 < 0 || d2 < 0 || d3 < 0) return false;

    if (ans == 0xaa) {
        even_nibbles_ = (uint32_t(d0) << 4) | (uint32_t(d1) << 12) |
                        (uint32_t(d2) << 20) | (uint32_t(d3) << 28);
        have_even_ = true;
    } else if (ans == 0x55) {
        odd_nibbles_ = uint32_t(d0) | (uint32_t(d1) << 8) |
                       (uint32_t(d2) << 16) | (uint32_t(d3) << 24);
        have_odd_ = true;
    } else {
        return false;
    }

    return have_even_ && have_odd_ && ((even_nibbles_ | odd_nibbles_) == expected_wdata);
}

bool bcd_seg_matches(uint32_t seg_wdata, uint32_t counter_ms) {
    if (((seg_wdata >> 28) & 0xfu) != 3u) return false;
    if (((seg_wdata >> 24) & 0xfu) != 7u) return false;

    uint32_t value = 0;
    for (int nib = 5; nib >= 0; --nib) {
        uint32_t digit = (seg_wdata >> (nib * 4)) & 0xfu;
        if (digit > 9u) return false;
        value = value * 10u + digit;
    }
    return value == (counter_ms % 1000000u);
}

}  // namespace sim
