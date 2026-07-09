# srcWithMext frequency/cache optimization pass

Date: 2026-07-09

## Goal

Respond to the reported FPGA timing path rooted at `student_top_inst/Mem_IROM/.../CLKARDCLK` and reduce `srcWithMext` runtime while preserving correctness.

## Changes

1. IROM timing cut:
   - Enabled `IROM_0` primitive output register in `fpga/create_vivado_project.tcl`.
   - Updated `rtl/ip/IROM_0.sv` to model registered ROM output.
   - Added a small fetch FIFO in `rtl/core/riscv_cpu.sv` so execute consumes registered instructions, not raw IROM `douta`.
   - Added empty-FIFO return bypass to reduce frontend bubbles.

2. Verilator memory model alignment:
   - Updated `tb/verilator/sim_memory.*` IROM timing to match registered ROM output for `myCPU` direct tests.
   - Changed direct memory read return to aligned word; CPU remains responsible for byte/half load extraction.

3. DCache locality and miss latency:
   - Cacheable store hit now byte-merges into the cached word instead of invalidating the whole line.
   - Store miss remains no-write-allocate.
   - Miss fill now starts with the requested word and returns it early, then continues filling the rest of the line.
   - DCache default line count tested and left at 512 after target-program cycle improvement.
   - Load hit now returns through a combinational fast path so the CPU can commit a cache-hit load in `ST_EXEC` without entering `ST_WAIT_MEM`.

4. Mul latency:
   - Changed `MUL_0` model and Vivado `mult_gen` pipe stages from 3 to 2.
   - Updated `MulDivUnit` multiply wait count accordingly.

5. Constraints:
   - Added `create_clock -name sys_clk_p -period 5.000 [get_ports i_sys_clk_p]` to `fpga/digital_twin.xdc`.

## Verification

Passing after this pass:

```text
rv32ui:       40/40 PASS
rv32um:        8/8 PASS
rv32mi:        4/4 PASS
srcSmoke:      PASS
srcWithMext:   PASS
```

## srcWithMext progression

| Version point | cycles | IPC | DCache miss | Memory stall counter | Mul/Div wait counter |
|---|---:|---:|---:|---:|---:|
| Previous baseline from docs | 734,122,286 | 0.518094 | 50,080,018 | 200,408,392 | 42,496,500 |
| IROM output reg + fetch FIFO | 734,654,326 | 0.517719 | 50,080,018 | 200,408,392 | 42,496,500 |
| Store-hit cache update | 587,579,377 | 0.647307 | 7,939,159 | 53,333,443 | 42,496,500 |
| Critical-word-first fill | 546,114,071 | 0.696456 | 7,939,159 | 53,333,443 | 42,496,500 |
| 2-stage multiplier | 541,947,639 | 0.701810 | 7,939,159 | 53,333,443 | 31,872,468 |
| 256-line DCache | 536,050,029 | 0.709532 | 5,417,809 | 35,683,993 | 31,872,468 |
| 512-line DCache | 531,368,771 | 0.715782 | 3,520,473 | 22,402,655 | 31,872,468 |
| Load-hit fast return | 423,962,132 | 0.897119 | 3,520,473 | 22,402,655 | 31,872,462 |

Note: after critical-word-first fill, the memory stall counter can overcount effective CPU stall because it still counts DCache background fill busy cycles even when the CPU has already received the target word and is executing non-memory instructions. Use total cycles as the primary runtime metric.

## Current interpretation

At 50 MHz, the final `srcWithMext` run corresponds to about 8.48 s. At 100 MHz it would be about 4.24 s. Reaching about 3 s with this single-issue core now requires roughly 142 MHz, or further cycle reduction below about 300M cycles at 100 MHz.

The load-hit fast return is a high-impact IPC optimization but must be treated as a timing-risk item until Vivado proves Fmax, because it creates a path through register read/address generation, DCache tag/data lookup, load extension, and GPR writeback control in one CPU cycle.

The biggest remaining counted costs are:

```text
Mul/Div wait counter:       31,872,468
Memory stall counter:       22,402,655
Frontend redirect/fill:        798,057
```

Further large gains likely require either:

1. Vivado-proven Fmax improvement above 170 MHz.
2. Faster divider or more M-extension special-case bypasses.
3. A deeper pipeline with load/mul overlap, or a more substantial memory-level parallelism change.
