#include "sim_common.h"

#include <cstdlib>
#include <iomanip>
#include <ostream>
#include <sstream>

namespace sim {

std::string hex32(uint32_t value) {
    std::ostringstream os;
    os << "0x" << std::hex << std::setw(8) << std::setfill('0') << value;
    return os.str();
}

std::string json_escape(const std::string& value) {
    std::ostringstream os;
    for (char ch : value) {
        switch (ch) {
            case '\\': os << "\\\\"; break;
            case '"': os << "\\\""; break;
            case '\n': os << "\\n"; break;
            case '\r': os << "\\r"; break;
            case '\t': os << "\\t"; break;
            default: os << ch; break;
        }
    }
    return os.str();
}

uint32_t encode_bcd6(uint32_t value) {
    value %= 1000000u;
    uint32_t encoded = 0;
    for (int i = 0; i < 6; ++i) {
        encoded |= (value % 10u) << (i * 4);
        value /= 10u;
    }
    return encoded;
}

uint32_t src_expected_seg_value(uint32_t counter_ms) {
    return 0x37000000u | encode_bcd6(counter_ms);
}

bool parse_u64(const std::string& text, uint64_t& out) {
    char* end = nullptr;
    out = std::strtoull(text.c_str(), &end, 0);
    return end && *end == '\0';
}

bool parse_u32(const std::string& text, uint32_t& out) {
    uint64_t value = 0;
    if (!parse_u64(text, value) || value > 0xffffffffull) return false;
    out = static_cast<uint32_t>(value);
    return true;
}

bool is_known_mmio_addr(uint32_t addr) {
    return addr == SW0_ADDR || addr == SW1_ADDR || addr == KEY_ADDR ||
           addr == SEG_ADDR || addr == LED_ADDR || addr == CNT_ADDR;
}

void write_json_string_field(std::ostream& out, const std::string& key,
                             const std::string& value, bool comma) {
    out << "  \"" << key << "\": \"" << json_escape(value) << "\"";
    if (comma) out << ",";
    out << "\n";
}

}  // namespace sim
