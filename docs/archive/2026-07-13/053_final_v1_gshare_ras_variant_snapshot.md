# final_v1 gshare + RAS 200 MHz variant snapshot

Date: 2026-07-13

Branch: `dev-7-final-improve`

Parent baseline: `55182b2 final_v01 -0.590 ns -1470 ns 460M cycles`

## Snapshot scope

This is a `final_v1` predictor variant built on the `final_v01` LW fast-path
snapshot. The predictor is changed from the baseline per-BTB-entry two-bit
counter to:

- a 128-entry direct-mapped BTB;
- an 8-bit global history register;
- a 256-entry two-bit gshare pattern history table;
- a 16-entry return-address stack.

The design was synthesized and implemented only at **200 MHz** with the
`Performance_ExplorePostRoutePhysOpt` strategy.

The external DRAM/SoC/IP timing contract is unchanged and continues to follow
`docs/fpga/ip_timing_alignment.md`:

- no change to DRAM `ENA`/`REGCEA` behavior;
- no change to valid/data/offset alignment;
- no change to the registered Vivado DRAM return contract.

## Predictor implementation

The fetch-time gshare index is carried through the pipeline and used at branch
resolution, so training does not recompute the index from a newer GHR value.
The BTB stores the resolved branch target even when a conditional branch is not
taken.

The RAS stores the complete 32-bit `PC + 4`. It is updated only for resolved
calls and returns, avoiding wrong-path push/pop and checkpoint/rollback state.
Calls are `JAL`/`JALR` writing `x1` or `x5`; returns are
`JALR x0, 0(x1/x5)`.

Vivado inferred the BTB, PHT and RAS payloads as distributed RAM rather than
large flip-flop arrays.

## WSL verification and predictor comparison

- Verilator `student_top` build: PASS
- Verilator `myCPU` build: PASS
- `srcSmoke`: PASS
- directed `jal`, `jalr`, `beq`, `bne`, `blt` and `bge`: PASS
- `srcWithMext`, limit 500,000,000: PASS

| Predictor | `srcWithMext` cycles | `srcSmoke` cycles |
|---|---:|---:|
| final_v01 baseline | 460,527,872 | not rerun in this comparison |
| gshare + RAS | **459,864,062** | **40,227,035** |
| gshare, no RAS | 459,864,162 | 40,227,075 |
| bimodal PHT + RAS | 459,863,592 | 41,346,035 |

The selected gshare + RAS variant saves **663,810 cycles (0.1441%)** versus
`final_v01`. At 200 MHz, the estimated workload time changes from about
2.302639 s to **2.299320 s**, a gain of about 3.319 ms.

RAS contributes only about 100 cycles on the full workload. Gshare and bimodal
are nearly tied on `srcWithMext`, but gshare is about 1.119 million cycles faster
on the more branch/call-sensitive `srcSmoke`, so gshare + RAS is retained as the
requested general-purpose variant.

## 200 MHz Vivado result

Profile: `srcWithMext`

Strategy: `Performance_ExplorePostRoutePhysOpt`

| Metric | final_v01 baseline | gshare + RAS variant | Delta |
|---|---:|---:|---:|
| WNS | -0.590 ns | **-0.839 ns** | -0.249 ns |
| TNS | -1469.804 ns | **-3521.268 ns** | -2051.464 ns |
| Setup failing endpoints | 8,253 | **13,434** | +5,181 |
| WHS | +0.059 ns | **+0.065 ns** | +0.006 ns |
| Slice LUTs | 9,721 | **10,248** | +527 |
| Slice registers | 8,635 | **9,013** | +378 |
| BRAM tiles | 68 | **68** | 0 |

The strict STA period estimate is `5.000 + 0.839 = 5.839 ns`, corresponding to
about **171.3 MHz**. The implementation remains inside the project-specific
empirical acceptance envelope of WNS above -3 ns and TNS above -15000 ns at
200 MHz, but its timing margin is worse than `final_v01`.

The worst paths are not the gshare/RAS prediction lookup. They are primarily:

1. M1 cache tag/index control to DCache distributed-RAM write enable;
2. M1 forwarding control through the normal EX ALU;
3. DCache fast-word paths.

The worst path has 5.117 ns data delay and approximately 85% routing delay.
Among the 500 reported worst setup paths, 65 terminate in the new PHT-valid
registers. These are high-fanout synchronous-reset paths, around -0.699 ns, and
are a significant reason TNS and failing endpoints grow. The predictor itself
uses 879 LUTs and 401 registers versus 409 LUTs and 128 registers in the
baseline.

## Evaluation

This experiment validates the functional gshare + RAS architecture and gives a
small cycle-count improvement, but the 0.1441% runtime gain does not compensate
for the larger WNS/TNS and resource cost. Therefore this snapshot is retained
as a `final_v1` variant and **does not replace `final_v01` as the preferred
200 MHz implementation**.

## Archived artifacts

- Bitstream: `D:/jichuang_database/bitstream/final_v1_gshare_ras_459M_srcWithMext_200MHz.bit`
- Summary: `D:/jichuang_database/report/final_v1_gshare_ras_459M_srcWithMext_summary.csv`
- Timing summary: `D:/jichuang_database/report/final_v1_gshare_ras_459M_srcWithMext_200MHz_timing_summary.rpt`
- Failing setup paths: `D:/jichuang_database/report/final_v1_gshare_ras_459M_srcWithMext_200MHz_failing_paths_setup.rpt`
- Hierarchical utilization: `D:/jichuang_database/report/final_v1_gshare_ras_459M_srcWithMext_200MHz_utilization_hier.rpt`
- Synthesis and implementation logs use the same
  `final_v1_gshare_ras_459M_srcWithMext_200MHz` prefix in the report directory.

No further optimization is included after this snapshot.
