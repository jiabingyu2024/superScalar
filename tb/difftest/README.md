# DiffTest harness

This directory keeps the DiffTest flow isolated from the normal Verilator
regression under `tb/verilator`.

Current status:

- `scripts/run_difftest.py` builds separate `*_difftest` binaries.
- The first implementation records and self-checks DUT commit traces.
- OpenXiangShan DiffTest upstream is cloned at:
  `f65181bf3be2a444669e1a3f83f784e532a92154`.
- The upstream RV32 single-commit profile is:
  `tb/difftest/profiles/rv32_single_commit.json`.
- Upstream interface generation is not yet runnable in this environment because
  the `mill` executable is missing.

Upstream location:

```text
tb/difftest/upstream
```

The architectural DUT is `myCPU` / internal `riscv_cpu`. For `src` tests,
the Verilator top is `student_top`, but commit probes are still collected
from the internal `Core_cpu`.

Useful commands:

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2

make -C tb/difftest/upstream \
  PROFILE=/home/jiabingyu/prj/26_jcs/superScalar/tb/difftest/profiles/rv32_single_commit.json \
  DESIGN_DIR=/home/jiabingyu/prj/26_jcs/superScalar/tb/difftest/generated
```

The last command requires `mill` and the normal Scala/Chisel dependency
download path to be available.
