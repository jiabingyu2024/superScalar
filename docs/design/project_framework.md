# Project Framework

## Repository Positioning

This repository is a full-flow simple superscalar processor project:

1. RTL design for a fixed RV32 core with M extension support.
2. Verilator simulation for correctness and performance bring-up.
3. FPGA integration using the competition SoC wrapper.

The current priority is to build a stable engineering/debug framework before fixing core RTL bugs.

## Directory Contract

| Path | Contract |
| --- | --- |
| `rtl/core/` | CPU bare core and the `myCPU` competition-facing CPU adapter. Core RTL must not depend on FPGA IP implementation details. |
| `rtl/soc/` | Competition SoC wrapper, peripheral bridge, UART/display glue, and FPGA top-level integration logic. |
| `rtl/ip/` | Behavioral models of generated FPGA IP for Verilator/simulation use. These files may be edited, but their external IP-compatible behavior must remain consistent with FPGA IP. |
| `data/` | Test inputs. Missing generated artifacts such as `.hex` and `.dump` are completed in-place under the original test directory. |
| `tb/` | Future Verilator testbench sources. Main correctness DUT should be `myCPU`; `student_top` is reserved for SoC smoke tests. |
| `scripts/` | Build helper scripts and stable filelists. Makefile remains the user-facing entrypoint later. |
| `build/` | Generated build outputs, logs, waves, and result summaries. Ignored by git. |
| `docs/design/` | Current design and project contracts. Keep this updated when design facts change. |
| `docs/sim/` | Simulation usage, test data rules, and debug workflow. |
| `docs/fpga/` | FPGA build and Vivado flow notes. |
| `docs/debug/` | Bug-specific debug records. |
| `docs/archive/` | Chronological change records for project modifications. |
| `fpga/` | FPGA scripts and constraints. The Tcl flow must adapt to the current repository layout instead of forcing file relocation. |

## Protected Files

`rtl/soc/counter.sv` is competition-evaluation logic and must not be modified unless the user explicitly overrides this rule.

## Future Action Rules

1. Keep `myCPU` as the primary Verilator correctness/performance DUT.
2. Use `student_top` only for SoC-level smoke/regression after `myCPU` simulation is under control.
3. Do not change `myCPU.sv` ports unless the user explicitly approves it.
4. Keep Makefile as the user-facing command surface; scripts may implement complex discovery, batching, and reporting behind it.
5. Update `docs/archive/` for each meaningful project modification.
6. Update `docs/design/` or `docs/sim/` when the current project contract changes.
7. Treat timeout as a failure, not as a pass condition.

## Planned Command Shape

These commands are the intended interface once the simulation harness is implemented:

```sh
make sim-rv32 TEST=rv32ui-p-add
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=src0
make sim-src-all
make fpga-project TEST=src0
```

