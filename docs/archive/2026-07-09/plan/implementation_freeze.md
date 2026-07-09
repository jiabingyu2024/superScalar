# superScalar implementation freeze

> Date: 2026-07-09
> Scope: final RTL implementation decisions.
> Priority: if older plan text conflicts with this file, this file wins.

## Frozen decisions

- RTL must be synthesizable SystemVerilog and Vivado friendly.
- Keep the current superScalar SoC/MMIO boundary unless a listed interface change requires a narrow adapter edit.
- Target width is 2-way fetch/decode/rename/dispatch/commit.
- Do not add ICache. Use a true dual-port Vivado BRAM ROM for IROM, and keep the Verilator `rtl/ip/IROM_0.sv` model port-compatible with one-cycle read latency.
- Use a parameterized tournament branch predictor:
  - 5-bit global history.
  - 512-entry global/GShare PHT.
  - 512-entry local PHT plus local history path.
  - 512-entry choice PHT.
  - 256-entry BTB.
  - 8-entry RAS.
- Use a 2-way set-associative DCache with 32-byte lines, write-back, and write-allocate.
- Keep cacheable DRAM fixed at `0x8010_0000 <= addr < 0x8014_0000`; MMIO remains uncached.
- Keep `MUL_0` at 3-cycle latency for v1.
- Keep `DIV_0` and adapt its valid-result handshake.
- Implement RV32I, RV32M, RV32MI-relevant machine-mode behavior, `ecall`, `ebreak`, `fence`, and `mret`; do not implement Zb, MMU, or TLB in v1.
- StoreBuffer semantics are mandatory: stores may execute early, but may only write cache/memory/MMIO after commit.
- Do not enable load speculative wakeup in v1.

## Verification target

- Functional target: WSL Verilator `srcWithMext` pass.
- FPGA target: source tree, filelists, and Vivado Tcl are ready for project creation, elaboration, and synthesis. Running Vivado is out of scope for this implementation pass.
