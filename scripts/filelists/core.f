# RV32 in-order single-issue, out-of-order-complete core.
# Paths are relative to repository root; packages must be first.
rtl/core/pkg/core_config_pkg.sv
rtl/core/pkg/core_types_pkg.sv
rtl/core/decode/decoder.sv
rtl/core/frontend/fetch_queue.sv
rtl/core/frontend/branch_predictor.sv
rtl/core/frontend/frontend.sv
rtl/core/issue/regfile.sv
rtl/core/commit/csr_file.sv
rtl/core/control/recovery_ctrl.sv
rtl/core/perf/perf_counters.sv
rtl/core/execute/fixed_execute.sv
rtl/core/execute/bitmanip_unit.sv
rtl/core/execute/muldiv_unit.sv
rtl/core/memory/dcache_tag_bank.sv
rtl/core/memory/dcache_data_bank.sv
rtl/core/memory/dmem_regslice.sv
rtl/core/memory/dcache.sv
rtl/core/core_top.sv
rtl/core/myCPU.sv
