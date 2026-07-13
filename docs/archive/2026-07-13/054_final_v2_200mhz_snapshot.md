# final_v2 200 MHz timing snapshot

Date: 2026-07-13

Branch: `dev-7-final-improve`

Parent baseline: `b77b458 final_v01-gshare-ras -0.839 ns -3521 ns 459M cycles`

## Snapshot scope

`final_v2` keeps the selected 128-entry BTB, 256-entry gshare PHT and 16-entry
RAS from `final_v1`. Predictor indexing, update metadata, targets and RAS
semantics are unchanged. The version name intentionally has no predictor
suffix, but the implementation still contains gshare + RAS.

The two timing changes are internal to the CPU/cache:

1. DCache store-hit/refill writes are captured as bank-local registered write
   commands. Four word-local address/data/mask copies reduce LUTRAM write
   fanout. A pending-write byte merge preserves immediate store-to-load
   visibility without a bubble.
2. EX late forwarding uses small registered stage selections. WB/M2 register
   address comparisons no longer feed the ALU and branch units directly. A
   separate registered WB selection preserves the special MUL result timing.

Both changes preserve the existing pipeline boundaries and CPU-visible
ready-valid behavior.

## Golden timing contract

`docs/fpga/ip_timing_alignment.md` was treated as the golden rule. This version
does not change:

- IROM latency, enable behavior or port clocks;
- DRAM `ENA`, `REGCEA`, READ_FIRST mode, byte lanes or response alignment;
- MUL pipeline depth or DIV valid/latency contract;
- SoC clock domains, reset release or CDC constraints;
- DCache external request/response timing.

The design was synthesized and implemented only at **200 MHz** (5.000 ns) with
`Performance_ExplorePostRoutePhysOpt`.

## WSL verification

Both Verilator targets were rebuilt in WSL after restoring the final source.

- RV32I: all implemented directed tests PASS.
- RV32M: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU PASS.
- RV32MI: CSR, ECALL, EBREAK and counter tests PASS.
- The only failures in `sim-rv32-all` are the pre-existing unsupported Zb
  extension tests.
- `srcWithMext`, 500,000,000-cycle limit: PASS at **459,864,062 cycles**.

The workload cycles and memory counters are exactly unchanged from final_v1:

| Counter | final_v1 | final_v2 |
|---|---:|---:|
| Cycles | 459,864,062 | 459,864,062 |
| DCache access | 132,057,221 | 132,057,221 |
| DCache miss | 3,520,473 | 3,520,473 |
| Load-access stall | 44,805,312 | 44,805,312 |

At nominal 200 MHz, `cycles / frequency` is about **2.299320 s**. This is a
cycle-based estimate, not an FPGA board measurement. The changes therefore
improve timing robustness but do not claim a runtime reduction from the
previous gshare + RAS version at the same clock.

The current result JSON does not collect branch counters for this profile (the
fields are zero), so no fabricated branch hit-rate comparison is reported.
General predictor quality is protected by leaving the complete gshare + RAS
implementation unchanged and rerunning branch-directed tests.

## 200 MHz Vivado result

| Metric | final_v1 gshare + RAS | final_v2 | Delta |
|---|---:|---:|---:|
| WNS | -0.839 ns | **-0.690 ns** | +0.149 ns |
| TNS | -3521.268 ns | **-532.507 ns** | +2988.761 ns |
| Setup failing endpoints | 13,434 | **2,880** | -10,554 |
| WHS | +0.065 ns | **+0.070 ns** | +0.005 ns |
| Hold failing endpoints | 0 | **0** | 0 |
| Slice LUTs | 10,248 | **10,219** | -29 |
| Slice registers | 9,013 | **9,176** | +163 |
| BRAM tiles | 68 | **68** | 0 |

The valid routed checkpoint reports WNS -0.690 ns and TNS -532.507 ns. Vivado
again crashed in post-route physical optimization, so transient phys-opt WNS
values are not used. The routed checkpoint was reopened successfully, all
reports were generated, and `write_bitstream` completed successfully.

The strict STA period estimate is `5.000 + 0.690 = 5.690 ns`, corresponding to
about **175.7 MHz**. At that strict frequency the cycle-based workload estimate
is about **2.617 s**. The 200 MHz result remains comfortably inside the
project-specific empirical acceptance envelope (WNS magnitude below 3 ns and
TNS magnitude below 15,000 ns), but negative slack is not formal 200 MHz
sign-off.

A WNS-only extrapolation of that empirical -3 ns limit would give an
unrealistic upper bound near 372 MHz. It is not a usable maximum-frequency
claim because TNS, clocking, placement and board behavior do not scale linearly.
With only the requested 200 MHz implementation and no board sweep, the evidence
supports **200 MHz as the practical maximum tested target**; operation above
200 MHz remains unverified.

## Critical-path evaluation and rejected trials

The final worst setup path is DCache asynchronous fast word through the
zero-bubble simple ALU path to EX/M1: 5.591 ns data delay, 16 logic levels and
about 70% routing delay. The next groups include IROM enable/control and branch
update-target routing. The former WB/M2 `rd_addr` comparison paths are no longer
the dominant group.

Two alternatives were rejected:

- Removing the zero-bubble aligned-LW fast path made `srcWithMext` exceed the
  hard 500,000,000-cycle limit. It was restored and never synthesized as a
  final candidate.
- `Performance_NetDelay_high` spent one hour in ExtraNetDelay placement without
  producing a routed checkpoint. It was terminated and is not an archived
  timing candidate.

The selected result balances the slightly placement-sensitive WNS against a
large and structural TNS/failing-endpoint improvement. Relative to the DCache-
only first iteration, it trades 0.034 ns WNS for 174.664 ns better TNS, 257
fewer failing endpoints and 18 fewer LUTs, with identical cycles.

## Archived artifacts

- Bitstream: `D:/jichuang_database/bitstream/final_v2_srcWithMext_200MHz.bit`
- Summary: `D:/jichuang_database/report/final_v2_srcWithMext_summary.csv`
- Timing summary: `D:/jichuang_database/report/final_v2_srcWithMext_200MHz_timing_summary.rpt`
- Failing setup paths: `D:/jichuang_database/report/final_v2_srcWithMext_200MHz_failing_paths_setup.rpt`
- Failing hold paths: `D:/jichuang_database/report/final_v2_srcWithMext_200MHz_failing_paths_hold.rpt`
- Hierarchical utilization: `D:/jichuang_database/report/final_v2_srcWithMext_200MHz_utilization_hier.rpt`
- Synthesis and implementation logs use the same `final_v2_srcWithMext_200MHz`
  prefix in the report directory.
