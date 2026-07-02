#ifndef TB_VERILATOR_SIM_DISPLAY_H
#define TB_VERILATOR_SIM_DISPLAY_H

#include <cstdint>

namespace sim {

uint8_t seg7_encode(uint8_t digit);
int seg7_decode(uint8_t encoded);
uint64_t virtual_seg_encode(uint32_t seg_wdata, uint64_t cycle);
bool bcd_seg_matches(uint32_t seg_wdata, uint32_t counter_ms);

class VirtualSegDecoder {
public:
    bool observe(uint64_t encoded, uint32_t expected_wdata);

private:
    bool have_even_ = false;
    bool have_odd_ = false;
    uint32_t even_nibbles_ = 0;
    uint32_t odd_nibbles_ = 0;
};

}  // namespace sim

#endif  // TB_VERILATOR_SIM_DISPLAY_H
