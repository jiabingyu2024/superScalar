#include "sim_result.h"

#include <array>
#include <fstream>
#include <iostream>
#include <stdexcept>

namespace sim {

namespace {

struct LampDesc {
    int index;
    uint32_t mask;
    const char* name;
};

constexpr std::array<LampDesc, 8> kSrcLampDescs{{
    {1, 0x00000001u, "lamp1_rv32i_or_base"},
    {2, 0x00000002u, "lamp2"},
    {3, 0x00000100u, "lamp3_perf_or_matrix"},
    {4, 0x00000200u, "lamp4"},
    {5, 0x00010000u, "lamp5"},
    {6, 0x00020000u, "lamp6_csr_or_trap"},
    {7, 0x01000000u, "lamp7"},
    {8, 0x02000000u, "lamp8"},
}};

bool src_marker_matches(uint32_t value, bool has_marker, uint32_t marker,
                        bool has_mask, uint32_t mask) {
    if (!has_marker) return false;
    if (has_mask) return (value & ~mask) == marker;
    return value == marker;
}

uint32_t encode_bcd_digits(uint32_t value, int digits) {
    uint32_t encoded = 0;
    for (int i = 0; i < digits; ++i) {
        encoded |= (value % 10u) << (i * 4);
        value /= 10u;
    }
    return encoded;
}

uint32_t decode_bcd_digits(uint32_t value, int digits) {
    uint32_t decoded = 0;
    for (int i = digits - 1; i >= 0; --i) {
        uint32_t digit = (value >> (i * 4)) & 0xfu;
        if (digit > 9u) return 0xffffffffu;
        decoded = decoded * 10u + digit;
    }
    return decoded;
}

const char* final_symbol_ascii(bool pass_match, bool fail_match) {
    if (pass_match) return "check";
    if (fail_match) return "cross";
    return "unknown";
}

const char* final_symbol_cn(bool pass_match, bool fail_match) {
    if (pass_match) return "对号";
    if (fail_match) return "错号";
    return "未知";
}

void write_bool(std::ostream& out, bool value) {
    out << (value ? "true" : "false");
}

}  // namespace

void write_result_json(const Options& opt, const SimResult& result,
                       const PerfStats& perf, const Checker& checker) {
    if (opt.result_path.empty()) return;
    std::ofstream out(opt.result_path);
    if (!out) {
        throw std::runtime_error("cannot write result file: " + opt.result_path);
    }
    out << "{\n";
    out << "  \"test\": \"" << json_escape(opt.test_name) << "\",\n";
    out << "  \"mode\": \"" << json_escape(opt.mode) << "\",\n";
    out << "  \"checker\": \"" << json_escape(checker.kind()) << "\",\n";
    out << "  \"status\": \"" << result.status << "\",\n";
    out << "  \"reason\": \"" << json_escape(result.reason) << "\",\n";
    out << "  \"cycles\": " << result.cycles << ",\n";
    out << "  \"max_cycles\": " << opt.max_cycles << ",\n";
    out << "  \"correctness\": {\n";
    if (opt.mode == "rv32") {
        out << "    \"tohost_addr\": \"" << hex32(opt.tohost_addr) << "\",\n";
        out << "    \"tohost_value\": \"" << hex32(result.fail_code) << "\"\n";
    } else {
        uint32_t final_led = perf.last_led_write;
        bool pass_match = opt.has_src_pass_marker ?
            src_marker_matches(final_led, true, opt.src_pass_marker,
                               opt.has_src_test_mask, opt.src_test_mask) :
            final_led == opt.src_led_pass;
        bool fail_match = opt.has_src_fail_marker ?
            src_marker_matches(final_led, true, opt.src_fail_marker,
                               opt.has_src_test_mask, opt.src_test_mask) :
            final_led == opt.src_led_fail;
        uint32_t lamp_value = opt.has_src_test_mask ?
            (final_led & opt.src_test_mask) : result.last_src_test_lamps;
        bool all_lamps_on = opt.has_src_test_mask &&
                            lamp_value == opt.src_test_mask;

        uint32_t expected_rv32i =
            opt.has_expected_rv32i_count ? opt.expected_rv32i_count :
            (opt.has_expected_pass_count ? opt.expected_pass_count : 0);
        bool has_expected_rv32i =
            opt.has_expected_rv32i_count || opt.has_expected_pass_count;
        uint32_t expected_high = 0;
        uint32_t high_mask = 0;
        uint32_t low_mask = opt.has_expected_mext_count ? 0x000fffffu : 0x00ffffffu;
        if (has_expected_rv32i) {
            expected_high |= (encode_bcd_digits(expected_rv32i, 2) & 0xffu) << 24;
            high_mask |= 0xff000000u;
        }
        if (opt.has_expected_mext_count) {
            expected_high |= (encode_bcd_digits(opt.expected_mext_count, 1) & 0xfu) << 20;
            high_mask |= 0x00f00000u;
        }
        uint32_t expected_counter_low = encode_bcd6(perf.final_counter_ms) & low_mask;
        uint32_t display_value = perf.last_nonzero_seg_write;
        uint32_t rv32i_from_seg =
            decode_bcd_digits((display_value >> 24) & 0xffu, 2);
        uint32_t mext_from_seg =
            decode_bcd_digits((display_value >> 20) & 0xfu, 1);
        if (rv32i_from_seg == 0xffffffffu) rv32i_from_seg = result.last_rv32i_count;
        if (mext_from_seg == 0xffffffffu) mext_from_seg = result.last_mext_count;
        bool seg_count_matches = high_mask != 0 &&
                                 (display_value & high_mask) == expected_high;
        bool seg_counter_matches = (display_value & low_mask) == expected_counter_low;

        out << "    \"summary\": {\n";
        out << "      \"final_symbol\": \"" << final_symbol_ascii(pass_match, fail_match) << "\",\n";
        out << "      \"final_symbol_cn\": \"" << final_symbol_cn(pass_match, fail_match) << "\",\n";
        out << "      \"right_8_lamps_all_on\": ";
        write_bool(out, all_lamps_on);
        out << ",\n";
        out << "      \"right_8_lamps_value\": \"" << hex32(lamp_value) << "\",\n";
        out << "      \"rv32i_pass_counter\": " << result.last_pass_counter << ",\n";
        out << "      \"rv32i_fail_counter\": " << result.last_fail_counter << ",\n";
        out << "      \"rv32i_count_from_seg\": " << rv32i_from_seg << ",\n";
        out << "      \"mext_count_from_seg\": " << mext_from_seg << "\n";
        out << "    },\n";

        out << "    \"led_readable\": {\n";
        out << "      \"last_raw\": \"" << hex32(final_led) << "\",\n";
        out << "      \"first_raw\": \"" << hex32(perf.first_led_write) << "\",\n";
        out << "      \"final_symbol\": \"" << final_symbol_ascii(pass_match, fail_match) << "\",\n";
        out << "      \"final_symbol_cn\": \"" << final_symbol_cn(pass_match, fail_match) << "\",\n";
        out << "      \"pass_marker_matched\": ";
        write_bool(out, pass_match);
        out << ",\n";
        out << "      \"fail_marker_matched\": ";
        write_bool(out, fail_match);
        out << ",\n";
        out << "      \"pass_cycle\": " << result.led_pass_cycle << "\n";
        out << "    },\n";

        out << "    \"right_lamps\": {\n";
        out << "      \"available\": ";
        write_bool(out, opt.has_src_test_mask);
        out << ",\n";
        out << "      \"mask\": \"" << hex32(opt.has_src_test_mask ? opt.src_test_mask : 0) << "\",\n";
        out << "      \"value\": \"" << hex32(lamp_value) << "\",\n";
        out << "      \"all_on\": ";
        write_bool(out, all_lamps_on);
        out << ",\n";
        out << "      \"lamps\": [\n";
        for (size_t i = 0; i < kSrcLampDescs.size(); ++i) {
            const auto& lamp = kSrcLampDescs[i];
            out << "        {\"index\": " << lamp.index
                << ", \"name\": \"" << lamp.name
                << "\", \"mask\": \"" << hex32(lamp.mask)
                << "\", \"on\": ";
            write_bool(out, (lamp_value & lamp.mask) != 0);
            out << "}";
            if (i + 1 != kSrcLampDescs.size()) out << ",";
            out << "\n";
        }
        out << "      ]\n";
        out << "    },\n";

        out << "    \"seg_readable\": {\n";
        out << "      \"last_raw\": \"" << hex32(perf.last_seg_write) << "\",\n";
        out << "      \"last_nonzero_raw\": \"" << hex32(display_value) << "\",\n";
        out << "      \"value_at_last_led_raw\": \"" << hex32(perf.seg_at_last_led_write) << "\",\n";
        out << "      \"test_count_high_matches_expected\": ";
        write_bool(out, seg_count_matches);
        out << ",\n";
        out << "      \"counter_low_matches_counter_ms\": ";
        write_bool(out, seg_counter_matches);
        out << ",\n";
        out << "      \"expected_high_mask\": \"" << hex32(high_mask) << "\",\n";
        out << "      \"expected_high_value\": \"" << hex32(expected_high) << "\",\n";
        out << "      \"expected_counter_low_mask\": \"" << hex32(low_mask) << "\",\n";
        out << "      \"expected_counter_low_value\": \"" << hex32(expected_counter_low) << "\"\n";
        out << "    },\n";

        out << "    \"counters\": {\n";
        out << "      \"rv32i_pass_counter_seen\": ";
        write_bool(out, result.saw_pass_counter);
        out << ",\n";
        out << "      \"rv32i_pass_counter_last\": " << result.last_pass_counter << ",\n";
        out << "      \"rv32i_pass_counter_expected\": "
            << (opt.has_expected_pass_count ? opt.expected_pass_count : expected_rv32i) << ",\n";
        out << "      \"rv32i_fail_counter_seen\": ";
        write_bool(out, result.saw_fail_counter);
        out << ",\n";
        out << "      \"rv32i_fail_counter_last\": " << result.last_fail_counter << ",\n";
        out << "      \"counter_ms\": " << perf.final_counter_ms << ",\n";
        out << "      \"counter_start_cycle\": " << perf.counter_start_cycle << ",\n";
        out << "      \"counter_stop_cycle\": " << perf.counter_stop_cycle << "\n";
        out << "    }\n";
    }
    out << "  },\n";
    perf.write_json_fields(out);
    out << "}\n";
}

int finish(const Options& opt, SimResult& result, const PerfStats& perf,
           const Checker& checker, uint64_t cycles) {
    result.cycles = cycles;
    write_result_json(opt, result, perf, checker);
    std::cout << opt.test_name << " " << result.status << " after " << cycles
              << " cycles: " << result.reason << "\n";
    return result.status == "PASS" ? 0 : 1;
}

void log_interesting_request(uint64_t cycle, const Options& opt, const Request& req) {
    if (!req.perip_wen) return;
    if (req.perip_addr != opt.tohost_addr && req.perip_addr != LED_ADDR &&
        req.perip_addr != SEG_ADDR && req.perip_addr != CNT_ADDR &&
        !(opt.has_pass_counter_addr &&
          (req.perip_addr & ~uint32_t{3}) == (opt.pass_counter_addr & ~uint32_t{3})) &&
        !(opt.has_fail_counter_addr &&
          (req.perip_addr & ~uint32_t{3}) == (opt.fail_counter_addr & ~uint32_t{3}))) {
        return;
    }
    std::cout << "cycle " << cycle
              << " write addr=" << hex32(req.perip_addr)
              << " data=" << hex32(req.perip_wdata)
              << " mask=0x" << std::hex << unsigned(req.perip_mask)
              << std::dec << "\n";
}

}  // namespace sim
