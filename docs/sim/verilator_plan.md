# Verilator Plan

## User-Facing Entry

Makefile should become the command surface. Python scripts may be used behind Makefile for test discovery, path expansion, batching, and result reporting.

Target command shape:

```sh
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=srcSmoke
make sim-src-all
```

## Test Selection

rv32 tests should support:

| Mode | Example |
| --- | --- |
| Single test | `TEST=rv32ui-p-add` |
| Suite | `SUITE=rv32ui` |
| All suites | `sim-rv32-all` |

src tests should support:

| Mode | Example |
| --- | --- |
| Single profile | `TEST=src0` |
| All profiles | `sim-src-all` |

## Filelists

Stable filelists live under `scripts/filelists/`:

| File | Use |
| --- | --- |
| `core.f` | Core packages, interfaces, modules, `core`, and `myCPU`. |
| `soc.f` | SoC wrapper RTL. |
| `ip_verilator.f` | Behavioral IP models for Verilator only. |
| `verilator_mycpu.f` | Primary `myCPU` simulation filelist. |
| `verilator_student_top.f` | SoC smoke simulation filelist. |

## Generated Outputs

Future simulation output should use:

```text
build/verilator/
build/log/
build/wave/
build/result/
```

`build/` is ignored by git.

## Test Data Preparation

Use:

```sh
scripts/prepare_test_data.py
```

The script fills missing `.hex` and `.dump` artifacts in-place under `data/`.
It is idempotent by default and overwrites only with `--force`.

