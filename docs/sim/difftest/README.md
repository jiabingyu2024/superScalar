# DiffTest usage

The current DiffTest uses the pinned `OpenXiangShan/difftest` submodule for its
generated `DiffExt*` RTL probes, DPI-C entry points and `DiffStateBuffer` packet
transport. The packet then feeds the independent RV32 reference executor in
`tb/difftest/adapter/reference_model.cpp`. It replaces the `dev-v1.2`
commit-trace self-check that reported `reference_enabled=false`.

## Build

```bash
git submodule update --init tb/difftest/upstream
make difftest-prepare
make difftest-build BUILD_JOBS=4 BUILD_CXX=g++
make difftest-build-src BUILD_JOBS=4 BUILD_CXX=g++
```

The normal and DiffTest binaries are separate:

```text
build/verilator/mycpu/sim_mycpu
build/verilator/mycpu_difftest/sim_mycpu_difftest
build/verilator/student_top/sim_student_top
build/verilator/student_top_difftest/sim_student_top_difftest
```

## Debug commands

```bash
make sim-rv32-difftest TEST=rv32ui-p-lw NO_BUILD=1 DIFFTRACE=1
make sim-rv32-difftest TEST=rv32um-p-div NO_BUILD=1 DIFFTRACE=1
make sim-rv32-difftest SUITE=rv32mi NO_BUILD=1

make sim-src-difftest TEST=srcSmoke MAX_CYCLES=500000 NO_BUILD=1 DIFFTRACE=1
make sim-src-difftest TEST=srcWithMext MAX_CYCLES=500000 NO_BUILD=1 DIFFTRACE=1
```

`FAIL` with reason `difftest mismatch` means the first architectural divergence
was found. A bounded src run may end as `TIMEOUT`; inspect the result's
`difftest.commit_count`. A timeout with no mismatch still proves that every
reported commit in that window matched, but it is not an application-level
PASS.

## ISA configuration

`scripts/run_difftest.py` reads the six `CFG_ZB*` values from
`rtl/core/pkg/core_config_pkg.sv` at build time and compiles the reference model
with the same extension set. Rebuild the DiffTest binary after changing any Zb
configuration.

## Upstream boundary

The profile is `tb/difftest/profiles/rv32_single_commit.json`. The prepare step
uses the submodule's Mill generator and produces ignored build artifacts under
`tb/difftest/generated/build/rtl` and
`tb/difftest/upstream/build/generated-src`. A clean checkout therefore needs
the initialized submodule and network access for the first Mill bootstrap.

The upstream default reference integration targets a 64-bit NEMU state. The
current RV32 CPU deliberately keeps the standard upstream probe/DPI transport
but uses the repository's RV32 reference backend for architectural execution.

## Synthesis isolation

Commit probes and their per-transaction metadata arrays are under
`VERILATOR_TB`. They are absent from the Vivado elaboration and do not add FPGA
ports, state, fanout or timing paths.
