# Commit-level DiffTest

This directory contains an isolated Verilator DiffTest flow for the current
single-retire core. `upstream/` is the pinned OpenXiangShan DiffTest submodule.
The build generates and instantiates its `DiffExt*` probes and compiles its
official `difftest-dpic.cpp` packet buffer.

At the scoreboard/ROB retirement boundary, the DUT drives the upstream
`DiffExtInstrCommit`, `DiffExtCommitData`, `DiffExtArchEvent` and
`DiffExtTrapEvent` modules. The adapter consumes the resulting official
`DiffStateBuffer` packet; a missing packet is a hard failure. The RV32 backend
in `reference_model.cpp` independently executes RV32I, RV32M, Zicsr and the
configured Zba/Zbb/Zbc/Zbkb/Zbkx/Zbs instructions. Each retirement is checked
for:

- PC and instruction
- trap flag and cause
- architectural next PC
- register write enable, destination and value
- load/store classification, effective address, store data and byte mask

Reference memory is initialized independently from the IROM/DRAM images and is
updated at reference store retirement. MMIO reads and cycle counters are
nondeterministic; their returned data is synchronized from the DUT, while the
instruction, address, destination register and control flow are still checked.

Useful commands:

```bash
git submodule update --init tb/difftest/upstream
make difftest-prepare
make difftest-build BUILD_JOBS=4 BUILD_CXX=g++
make difftest-build-src BUILD_JOBS=4 BUILD_CXX=g++

make sim-rv32-difftest TEST=rv32ui-p-lw NO_BUILD=1
make sim-rv32-difftest SUITE=rv32um NO_BUILD=1
make sim-src-difftest TEST=srcSmoke MAX_CYCLES=500000 NO_BUILD=1
make sim-src-difftest TEST=srcWithMext MAX_CYCLES=500000 NO_BUILD=1
```

Add `DIFFTRACE=1` to print every retirement. Results and logs are under:

```text
build/result/difftest/<mode>/
build/log/difftest/<mode>/
```

To prove that the comparison path is active, inject a one-bit error into a
known register-writing retirement:

```bash
DIFFTEST_FAULT_INJECT_COMMIT=2 \
  make sim-rv32-difftest TEST=rv32ui-p-simple NO_BUILD=1 MAX_CYCLES=1000
```

The run must fail with a DUT/REF `wdata` mismatch. This option only changes the
C++-side observed trace; it never changes RTL.

The upstream project defaults to a 64-bit NEMU reference. This RV32 core uses
the upstream probe/DPI transport with a local RV32 execution backend, avoiding
incorrect RV64 architectural-state assumptions while retaining the standard
OpenXiangShan commit packet path.
