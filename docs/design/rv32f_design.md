# RV32F design

## Scope

The core implements the RV32F architectural register state, decode, hazards,
`FLW`/`FSW`, `fcsr`/`frm`/`fflags`, comparisons, conversions and arithmetic
operations exercised by `data/rv32uf`.  The same core RTL is used by Verilator
and Vivado; there is no simulation/synthesis switch in the execution path.

## Simulation and FPGA IP adaptation

`rv32f_unit` directly instantiates `FP_FMA_0`, `FP_DIV_0` and `FP_SQRT_0`.

- Verilator includes the same-name behavioural modules in `rtl/ip` through
  `scripts/filelists/ip_verilator.f`.  Only these simulation IP models call the
  small numerical DPI backend in `tb/verilator/rv32f_dpi.cpp`.
- Vivado excludes `rtl/ip` and creates same-name Floating-Point Operator v7.1
  instances in `fpga/create_vivado_project.tcl`.

This is the same adaptation mechanism already used by RV32M's `MUL_0` and
`DIV_0`: the CPU hierarchy and interfaces do not change between builds.

## Datapath

- `fregfile` adds 32 single-precision architectural registers and a third read
  port for FMA `rs3`.  It has one WB write port and does not widen the integer
  register file.
- `FLW` and `FSW` reuse integer address generation and the existing DCache.
  Only store-data selection and the WB destination tag are extended.
- One FMA IP is shared by FADD, FSUB, FMUL and the four fused operations.
  Operand constants and sign changes select the requested operation before the
  registered IP boundary.  FDIV and FSQRT have dedicated IPs.
- FSGNJ, FMIN/FMAX, comparisons, FCLASS, FMV and signed/unsigned conversions
  use local RTL.  Conversion logic implements RNE, RTZ, RDN, RUP and RMM.
- Arithmetic exception flags are generated in RTL.  Exact binary equivalence
  checks supply NX because Floating-Point Operator v7.1 does not expose an
  inexact status output; NV, DZ, OF and UF are derived from operands/results.
- A flushed outstanding IP transaction is drained and discarded before a new
  operation uses that IP, preventing a stale result from being mistaken for a
  younger instruction.

## Rounding contract

The generated FMA, divide and square-root IPs are configured for the Xilinx
single-precision round-to-nearest/even implementation.  The current RV32UF
arithmetic tests use RNE; their explicit/dynamic conversion rounding modes are
handled in RTL.  Full hardware support for non-RNE arithmetic would require a
result-correction stage (or multiple differently configured IPs) and is not
included because of its area and timing cost.

## Timing intent

- Floating-point arithmetic is behind registered AXI-stream request/result
  boundaries and cannot enter integer ALU, branch, forwarding or DCache cones.
- All three FPOs use non-blocking flow control, so no IP `TREADY` path feeds the
  execute-stage stall logic.
- FMA uses 19 stages and DIV/SQRT use 28 stages.  These maximum-latency settings
  prioritize WNS/TNS; only an instruction actually waiting for an FP result
  pays those cycles.
- A single shared FMA limits DSP/LUT placement pressure compared with separate
  add, multiply and fused IPs.
- The conservative F-register interlock is an OR tree rather than a 3-by-5
  address scoreboard, trading independent-FP throughput for a shorter ID/PC
  control path.

## Verification

Run in WSL from the repository root:

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32uf NO_BUILD=1 OBJCACHE=
```

Zb-family and source-profile suites are outside this change's requested test
scope.
