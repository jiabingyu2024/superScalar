# Framework And Bringup Rules

## Context

The project is currently structurally assembled, but core RTL is known to have bugs. The immediate goal is to establish a maintainable framework before starting correctness debug.

## Decisions

1. Keep the current repository layout.
2. Complete generated test data in-place under `data/`.
3. Adapt FPGA Tcl to the current file layout later; do not move FPGA/data directories to satisfy the old Tcl.
4. Use `myCPU` as the primary Verilator DUT.
5. Use `student_top` only as a later SoC smoke DUT.
6. Keep `myCPU.sv` ports unchanged.
7. Keep `rtl/soc/counter.sv` protected from modification.
8. Use strict rv32 `tohost` pass/fail semantics.
9. Add stable filelists under `scripts/filelists/`.
10. Keep Makefile as the future user-facing command surface.

## Files Added

| File | Purpose |
| --- | --- |
| `.gitignore` | Ignore build, waveform, Vivado, and Verilator generated outputs. |
| `scripts/filelists/core.f` | Stable core RTL compile list. |
| `scripts/filelists/soc.f` | Stable SoC RTL compile list. |
| `scripts/filelists/ip_verilator.f` | Simulation-only IP behavior models. |
| `scripts/filelists/verilator_mycpu.f` | Primary DUT filelist. |
| `scripts/filelists/verilator_student_top.f` | SoC smoke DUT filelist. |
| `scripts/prepare_test_data.py` | In-place `.hex/.dump` preparation tool. |
| `docs/design/project_framework.md` | Repository and future-action rules. |
| `docs/design/memory_and_test_contract.md` | DUT, memory, and pass/fail contracts. |
| `docs/sim/verilator_plan.md` | Planned Verilator command and filelist structure. |

## Not Done Yet

1. Verilator C++ testbench implementation.
2. Makefile command surface.
3. Tcl adaptation for `data/<profile>/*.coe` and `fpga/digital_twin.xdc`.
4. Core RTL bug fixing.

