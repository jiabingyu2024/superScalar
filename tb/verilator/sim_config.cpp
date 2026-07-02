#include "sim_config.h"

#include <stdexcept>
#include <string>

namespace sim {

Options parse_args(int argc, char** argv) {
    Options opt;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        auto take_value = [&](const std::string& key, std::string& dst) {
            if (arg == key && i + 1 < argc) {
                dst = argv[++i];
                return true;
            }
            std::string prefix = key + "=";
            if (arg.rfind(prefix, 0) == 0) {
                dst = arg.substr(prefix.size());
                return true;
            }
            return false;
        };

        std::string value;
        if (take_value("--mode", opt.mode) ||
            take_value("--test-name", opt.test_name) ||
            take_value("--irom-hex", opt.irom_hex) ||
            take_value("--dram-hex", opt.dram_hex) ||
            take_value("--result", opt.result_path) ||
            take_value("--wave", opt.wave_path) ||
            take_value("--src-checker", opt.src_checker)) {
            continue;
        }
        if (take_value("--tohost", value)) {
            if (!parse_u32(value, opt.tohost_addr)) {
                throw std::runtime_error("bad --tohost value: " + value);
            }
            continue;
        }
        if (take_value("--max-cycles", value)) {
            if (!parse_u64(value, opt.max_cycles)) {
                throw std::runtime_error("bad --max-cycles value: " + value);
            }
            continue;
        }
        if (take_value("--src-seg-grace", value)) {
            if (!parse_u64(value, opt.src_seg_grace)) {
                throw std::runtime_error("bad --src-seg-grace value: " + value);
            }
            continue;
        }
        if (take_value("--counter-cycles-per-ms", value)) {
            if (!parse_u64(value, opt.counter_cycles_per_ms) ||
                opt.counter_cycles_per_ms == 0) {
                throw std::runtime_error("bad --counter-cycles-per-ms value: " + value);
            }
            continue;
        }
        if (take_value("--src-led-pass", value)) {
            if (!parse_u32(value, opt.src_led_pass)) {
                throw std::runtime_error("bad --src-led-pass value: " + value);
            }
            continue;
        }
        if (take_value("--src-led-fail", value)) {
            if (!parse_u32(value, opt.src_led_fail)) {
                throw std::runtime_error("bad --src-led-fail value: " + value);
            }
            continue;
        }
        if (take_value("--pass-counter-addr", value)) {
            if (!parse_u32(value, opt.pass_counter_addr)) {
                throw std::runtime_error("bad --pass-counter-addr value: " + value);
            }
            opt.has_pass_counter_addr = true;
            continue;
        }
        if (take_value("--fail-counter-addr", value)) {
            if (!parse_u32(value, opt.fail_counter_addr)) {
                throw std::runtime_error("bad --fail-counter-addr value: " + value);
            }
            opt.has_fail_counter_addr = true;
            continue;
        }
        if (take_value("--expected-pass-count", value)) {
            if (!parse_u32(value, opt.expected_pass_count)) {
                throw std::runtime_error("bad --expected-pass-count value: " + value);
            }
            opt.has_expected_pass_count = true;
            continue;
        }
        if (take_value("--src-test-mask", value)) {
            if (!parse_u32(value, opt.src_test_mask)) {
                throw std::runtime_error("bad --src-test-mask value: " + value);
            }
            opt.has_src_test_mask = true;
            continue;
        }
        if (take_value("--src-pass-marker", value)) {
            if (!parse_u32(value, opt.src_pass_marker)) {
                throw std::runtime_error("bad --src-pass-marker value: " + value);
            }
            opt.has_src_pass_marker = true;
            continue;
        }
        if (take_value("--src-fail-marker", value)) {
            if (!parse_u32(value, opt.src_fail_marker)) {
                throw std::runtime_error("bad --src-fail-marker value: " + value);
            }
            opt.has_src_fail_marker = true;
            continue;
        }
        if (take_value("--expected-rv32i-count", value)) {
            if (!parse_u32(value, opt.expected_rv32i_count)) {
                throw std::runtime_error("bad --expected-rv32i-count value: " + value);
            }
            opt.has_expected_rv32i_count = true;
            continue;
        }
        if (take_value("--expected-mext-count", value)) {
            if (!parse_u32(value, opt.expected_mext_count)) {
                throw std::runtime_error("bad --expected-mext-count value: " + value);
            }
            opt.has_expected_mext_count = true;
            continue;
        }
        if (arg == "--trace") {
            opt.trace = true;
            continue;
        }
        throw std::runtime_error("unknown argument: " + arg);
    }

    if (opt.irom_hex.empty()) {
        throw std::runtime_error("--irom-hex is required");
    }
    if (opt.mode == "src" && opt.max_cycles == DEFAULT_MAX_CYCLES) {
        opt.max_cycles = DEFAULT_SRC_MAX_CYCLES;
    }
    return opt;
}

}  // namespace sim
