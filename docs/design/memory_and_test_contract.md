# Memory And Test Contract

## Primary Simulation DUT

The primary Verilator DUT is `myCPU`, not `core` and not `student_top`.

Reasons:

1. `core` exposes SystemVerilog interfaces and bypasses the real competition-facing CPU adapter.
2. `student_top` includes SoC wrapper logic, FPGA IP models, display/counter/peripheral glue, and is too broad for first-line core debug.
3. `myCPU` has stable flattened ports and covers the important core-to-system adapter behavior.

## DUT Layers

| Layer | DUT | Purpose |
| --- | --- | --- |
| L1 | `myCPU` | Main rv32 correctness and src performance simulation. |
| L2 | `student_top` | SoC wrapper smoke tests after L1 is stable. |
| L3 | `top` | FPGA/Vivado entry. |

## IROM Contract

`myCPU` exposes two instruction ports:

```text
irom_addrA = fetch address
irom_addrB = fetch address + 4
irom_enaA/B = instruction read enable
irom_dataA/B = returned instruction words
```

The simulation memory model must match the effective timing expected by the RTL and the SoC/IP model. Do not replace it with an unrealistic zero-latency model unless the RTL is explicitly adapted for that mode.

## DRAM/MMIO Contract

`DramAccessIF` separates accepted access from valid read data:

```text
accessReady: address/command accepted
readData: fixed-latency read return data
```

`ExecuteMemStage` aligns load metadata using internal load metadata pipeline registers. A future Verilator memory model must preserve this latency relationship, otherwise rv32 simulation can pass while FPGA behavior fails.

## rv32 Pass/Fail Contract

Use strict `tohost` checking:

| Condition | Result |
| --- | --- |
| Store/write `tohost == 1` | PASS |
| Store/write `tohost != 0 && tohost != 1` | FAIL |
| Timeout | TIMEOUT and fail |
| Missing/unsupported `tohost` | UNSUPPORTED, not pass |

Current riscv-tests examples place `tohost` at `0x80001000`. The testbench should obtain the address from ELF symbols when possible instead of hard-coding it globally.

## src Contract

src tests have their own pass logic and performance rules. Keep the framework ready for:

1. User-provided src pass/fail logic.
2. Competition counter/MMIO behavior.
3. Internal `PerfIF`-style microarchitectural counters if accessible without changing `myCPU` ports.

