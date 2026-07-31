#ifndef TB_VERILATOR_SIM_COMMON_H
#define TB_VERILATOR_SIM_COMMON_H

#include <cstdint>
#include <iosfwd>
#include <string>
#include <vector>

namespace sim {

constexpr uint32_t IROM_BASE = 0x80000000u;
constexpr uint32_t SRC_DRAM_BASE = 0x80100000u;
constexpr uint32_t SW0_ADDR = 0x80200000u;
constexpr uint32_t SW1_ADDR = 0x80200004u;
constexpr uint32_t KEY_ADDR = 0x80200010u;
constexpr uint32_t SEG_ADDR = 0x80200020u;
constexpr uint32_t LED_ADDR = 0x80200040u;
constexpr uint32_t CNT_ADDR = 0x80200050u;
constexpr uint32_t RTT_STATUS_ADDR = 0x80200064u;
constexpr uint32_t COREMARK_TICKS_LO_ADDR = 0x80200068u;
constexpr uint32_t COREMARK_TICKS_HI_ADDR = 0x8020006cu;
constexpr uint32_t COREMARK_ITERATIONS_ADDR = 0x80200070u;
constexpr uint32_t COREMARK_CRC_LM_ADDR = 0x80200074u;
constexpr uint32_t COREMARK_CRC_SF_ADDR = 0x80200078u;
constexpr uint32_t COREMARK_FLAGS_ADDR = 0x8020007cu;
constexpr uint32_t RTT_LIVE_READY = 0x4c495600u;
constexpr uint32_t RTT_LIVE_PASS = 0x4c500000u;
constexpr uint32_t RTT_LIVE_FAIL = 0x4c460000u;
constexpr uint32_t CNT_START_CMD = 0x80000000u;
constexpr uint32_t CNT_STOP_CMD = 0xffffffffu;
constexpr uint32_t MTIMECMP_LO_ADDR = 0x02004000u;
constexpr uint32_t MTIMECMP_HI_ADDR = 0x02004004u;
constexpr uint32_t MTIME_LO_ADDR = 0x0200bff8u;
constexpr uint32_t MTIME_HI_ADDR = 0x0200bffcu;

constexpr uint32_t DEFAULT_SRC_LED_FAIL = 0x24181824u;
constexpr uint32_t DEFAULT_SRC_LED_PASS = 0x01221c08u;
constexpr uint64_t DEFAULT_MAX_CYCLES = 2000000ull;
constexpr uint64_t DEFAULT_SRC_MAX_CYCLES = 100000000ull;
constexpr uint64_t DEFAULT_SRC_SEG_GRACE = 512ull;
constexpr uint64_t DEFAULT_COUNTER_CYCLES_PER_MS = 50000ull;
constexpr double DEFAULT_CPU_FREQ_MHZ = 50.0;
constexpr double DEFAULT_SOC_FREQ_MHZ = 50.0;

struct Options {
    std::string mode = "rv32";
    std::string test_name = "unknown";
    std::string irom_hex;
    std::string dram_hex;
    std::string result_path;
    std::string wave_path;
    uint32_t tohost_addr = 0x80001000u;
    uint64_t max_cycles = DEFAULT_MAX_CYCLES;
    uint64_t src_seg_grace = DEFAULT_SRC_SEG_GRACE;
    uint64_t counter_cycles_per_ms = DEFAULT_COUNTER_CYCLES_PER_MS;
    double cpu_freq_mhz = DEFAULT_CPU_FREQ_MHZ;
    bool trace = false;

    std::string src_checker = "ledseg";
    uint32_t src_led_pass = DEFAULT_SRC_LED_PASS;
    uint32_t src_led_fail = DEFAULT_SRC_LED_FAIL;
    bool has_pass_counter_addr = false;
    bool has_fail_counter_addr = false;
    bool has_expected_pass_count = false;
    bool has_src_test_mask = false;
    bool has_src_pass_marker = false;
    bool has_src_fail_marker = false;
    bool has_expected_rv32i_count = false;
    bool has_expected_mext_count = false;
    uint32_t pass_counter_addr = 0;
    uint32_t fail_counter_addr = 0;
    uint32_t expected_pass_count = 0;
    uint32_t src_test_mask = 0;
    uint32_t src_pass_marker = 0;
    uint32_t src_fail_marker = 0;
    uint32_t expected_rv32i_count = 0;
    uint32_t expected_mext_count = 0;
};

struct Request {
    uint32_t irom_addr_a = 0;
    uint32_t irom_addr_b = 0;
    bool irom_ena_a = false;
    bool irom_ena_b = false;
    uint32_t perip_addr = 0;
    uint32_t perip_wdata = 0;
    uint8_t perip_mask = 0;
    bool perip_wen = false;
};

struct CorePerfSample {
    uint64_t cycle = 0;
    uint64_t commit_count = 0;
    uint64_t branch_count = 0;
    uint64_t branch_miss_count = 0;
    uint64_t load_count = 0;
    uint64_t store_count = 0;
    uint64_t dcache_access = 0;
    uint64_t dcache_miss = 0;
    uint64_t stall_front = 0;
    uint64_t stall_mem = 0;
    uint64_t stall_muldiv = 0;
    uint64_t stall_load_use = 0;
    uint64_t cond_branch_count = 0;
    uint64_t cond_branch_miss_count = 0;
    uint64_t jal_count = 0;
    uint64_t jal_miss_count = 0;
    uint64_t jalr_count = 0;
    uint64_t jalr_miss_count = 0;
    uint64_t frontend_stall_cycles = 0;
    uint64_t id_stall_cycles = 0;
    uint64_t rn_stall_cycles = 0;
    uint64_t ds_stall_cycles = 0;
    uint64_t is_stall_cycles = 0;
    uint64_t rr_stall_cycles = 0;
    uint64_t ex_stall_cycles = 0;
    uint64_t wb_stall_cycles = 0;
    uint64_t rob_full_cycles = 0;
    uint64_t issue_queue_full_cycles = 0;
    uint64_t int_issue_queue_full_cycles = 0;
    uint64_t mem_issue_queue_full_cycles = 0;
    uint64_t mul_issue_queue_full_cycles = 0;
    uint64_t rob_head_not_done_cycles = 0;
    uint64_t rob_head_not_done_int_cycles = 0;
    uint64_t rob_head_not_done_mem_cycles = 0;
    uint64_t rob_head_not_done_mul_cycles = 0;
    uint64_t rob_head_not_done_other_cycles = 0;
    uint64_t rob_head_store_commit_wait_cycles = 0;
    uint64_t free_list_empty_cycles = 0;
    uint64_t store_buffer_full_cycles = 0;
    uint64_t serial_block_cycles = 0;
    uint64_t mem_load_return_block_cycles = 0;
    uint64_t mem_load_access_block_cycles = 0;
    uint64_t store_commit_blocked_by_load_cycles = 0;
    uint64_t recovery_cycles = 0;
    uint64_t dispatch_width0_cycles = 0;
    uint64_t dispatch_width1_cycles = 0;
    uint64_t dispatch_width2_cycles = 0;
    uint64_t issue_width0_cycles = 0;
    uint64_t issue_width1_cycles = 0;
    uint64_t issue_width2_cycles = 0;
    uint64_t commit_width0_cycles = 0;
    uint64_t commit_width1_cycles = 0;
    uint64_t commit_width2_cycles = 0;
    uint64_t int_issue_count = 0;
    uint64_t mem_issue_count = 0;
    uint64_t mul_issue_count = 0;
    uint64_t mem_req_valid_cycles = 0;
    uint64_t mem_partial_alias_cycles = 0;
    uint64_t mem_no_alias_cycles = 0;
    uint64_t mem_forward_cycles = 0;
    uint64_t mem_iq_head_not_ready_cycles = 0;
    uint64_t mem_iq_younger_ready_cycles = 0;
    uint64_t mem_iq_occupancy_sum = 0;
    uint64_t mem_iq_probe_launch_count = 0;
    uint64_t mem_iq_probe_accept_count = 0;
    uint64_t mem_iq_probe_reject_count = 0;
    uint64_t mul_op_count = 0;
    uint64_t div_op_count = 0;
    uint64_t rem_op_count = 0;
    uint64_t muldiv_busy_cycles = 0;
};

struct SimResult {
    std::string status = "TIMEOUT";
    std::string reason = "max cycles reached";
    uint64_t cycles = 0;
    uint32_t fail_code = 0;

    bool saw_led_pass = false;
    bool saw_seg_match = false;
    bool saw_virtual_seg_match = false;
    uint64_t led_pass_cycle = 0;
    uint64_t seg_match_cycle = 0;
    uint64_t virtual_seg_match_cycle = 0;
    uint32_t last_led = 0;
    uint32_t last_seg_wdata = 0;
    uint32_t counter_ms = 0;

    bool saw_pass_counter = false;
    bool saw_fail_counter = false;
    uint32_t last_pass_counter = 0;
    uint32_t last_fail_counter = 0;

    bool saw_src_pass_marker = false;
    bool saw_src_fail_marker = false;
    uint32_t last_src_test_lamps = 0;
    uint32_t last_rv32i_count = 0;
    uint32_t last_mext_count = 0;

    uint64_t coremark_ticks = 0;
    uint32_t coremark_iterations = 0;
    uint16_t coremark_crclist = 0;
    uint16_t coremark_crcmatrix = 0;
    uint16_t coremark_crcstate = 0;
    uint16_t coremark_crcfinal = 0;
    uint32_t coremark_flags = 0;

    bool has_difftest = false;
    bool difftest_reference_enabled = false;
    std::string difftest_mode;
    uint64_t difftest_commit_count = 0;
    uint64_t difftest_mmio_skip_count = 0;
    uint32_t difftest_last_commit_pc = 0;
};

std::string hex32(uint32_t value);
std::string json_escape(const std::string& value);
uint32_t encode_bcd6(uint32_t value);
uint32_t src_expected_seg_value(uint32_t counter_ms);
bool parse_u64(const std::string& text, uint64_t& out);
bool parse_u32(const std::string& text, uint32_t& out);
bool is_known_mmio_addr(uint32_t addr);
void write_json_string_field(std::ostream& out, const std::string& key,
                             const std::string& value, bool comma);
std::vector<uint32_t> rtthread_live_commands(const std::string& test_name);

}  // namespace sim

#endif  // TB_VERILATOR_SIM_COMMON_H
