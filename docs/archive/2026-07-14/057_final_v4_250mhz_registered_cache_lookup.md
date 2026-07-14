# final_v4 250 MHz registered-cache-lookup snapshot

Date: 2026-07-14

Branch: `dev-7-final-improve`

RTL/archive commit: this commit
(`final_v4 250MHz -1.141 ns -1981 ns 459M cycles`)

Parent: `e53bd79` (`archive final_v3 250MHz timing trial`)

## Selected 250 MHz changes

`final_v4` keeps the final_v3 in-order pipeline, 128-entry BTB, 256-entry
gshare PHT, 16-entry RAS, LUTRAM register file and four-DSP multiplier. It uses
the existing EX/M1 and M1/M2 boundaries more effectively without adding an
architectural pipeline cycle:

1. DCache lookup starts from the EX2 memory address. Four replicated index
   buses drive the tag and data LUTRAMs, and tag fragments, valid state and all
   four data words are captured on the edge that moves the request into M1.
   M1 hit/ready and fast-load forwarding therefore start from local registers.
2. Store/refill write-collision metadata is captured separately and merged on
   the registered M1 side. This removes the word-select and byte-write mux from
   the LUTRAM capture path while preserving zero-bubble store-to-load behavior.
3. Load byte rotation and sign/zero extension move before the existing M1/M2
   edge. The architectural load value is registered there, cutting the former
   DCache-response-to-M2-to-EX forwarding cone for one-gap consumers.
4. MUL FIFO result selection uses an explicit registered non-empty state rather
   than placing a three-bit count comparison in front of the result mux.
5. Branch resolution is split into equivalent conditional, JAL and JALR error
   cones. Predictor storage, indexing, training, RAS behavior and recovery
   policy are unchanged.

## Golden timing contract

`docs/fpga/ip_timing_alignment.md` was treated as the immutable rule for this
work and was not edited. The selected RTL does not change:

- IROM one-cycle behavior;
- DRAM `ENA`/`REGCEA`, registered primitive output or single-outstanding
  request/response alignment;
- MUL three-stage latency or its consumer metadata depth;
- DIV fixed 34-cycle latency;
- PLL generation, reset synchronizers or CDC clock grouping.

The implementation script checked the three DRAM alignment properties before
launch. Every build used a 250.000 MHz CPU target (4.000 ns) and Vivado 2023.2
strategy `Performance_ExplorePostRoutePhysOpt`.

## WSL verification and cycles impact

Both Verilator targets were rebuilt in WSL after the selected changes.

- RV32I: 40/40 PASS, including all conditional branches, JAL/JALR and all
  byte/half/word load/store directed tests.
- RV32M: 8/8 PASS.
- RV32MI: 4/4 PASS.
- `srcSmoke`: PASS.
- `srcWithMext`, 500,000,000-cycle limit: PASS at **459,864,062 cycles**.

The final `srcWithMext` JSON is field-for-field identical to final_v3:

| Counter | final_v3 | final_v4 |
| --- | ---: | ---: |
| Cycles | 459,864,062 | **459,864,062** |
| DCache access | 132,057,221 | **132,057,221** |
| DCache miss | 3,520,473 | **3,520,473** |
| Load-access stall | 44,805,312 | **44,805,312** |
| Final SEG | `0x37809197` | **`0x37809197`** |

The cycle impact is exactly zero. At 250 MHz the ideal workload time is
**1.839456248 s**, about 10.54 ms below the user's current 1.85 s reference.
This is a projected CPU-cycle time; an actual board measurement is still
required before claiming a measured speedup.

The current profile still reports zero branch counters, so no hit-rate number
is invented. General branch-prediction quality is protected by leaving all BPU
state and policy unchanged and rerunning all branch/jump directed tests.

## Final 250 MHz implementation

| Metric | final_v3 250 MHz | final_v4 250 MHz | Delta |
| --- | ---: | ---: | ---: |
| WNS | -1.513 ns | **-1.141031 ns** | +0.371969 ns |
| TNS | -3742.260 ns | **-1981.117798 ns** | +1761.142202 ns |
| Setup failing endpoints | 5,196 | **4,725** | -471 |
| WHS | +0.048 ns | **+0.044032 ns** | -0.003968 ns, still clean |
| THS / hold endpoints | 0 / 0 | **0 / 0** | unchanged |
| Total LUTs | 8,580 | **8,765** | +185 |
| Registers | 7,309 | **7,568** | +259 |
| BRAM36 | 68 | **68** | unchanged |
| DSP blocks | 4 | **4** | unchanged |

The routed checkpoint reached WNS/TNS `-1.179/-1983.798 ns`. Post-route
physical optimization completed successfully and improved the final result to
`-1.141031/-1981.117798 ns`. All 14,040 routable nets are fully routed with
zero routing errors. Hold timing is clean.

Vivado formally reports that setup constraints are not met. The result is well
inside the user's empirical board-test envelope of WNS above -3 ns and TNS
above -15000 ns, so it is a stronger 250 MHz board candidate than final_v3,
not a formal 250 MHz timing closure.

## Remaining critical paths

The final worst setup path is:

- source: `u_core/mul_fifo_head_reg[1]`;
- destination: `u_dcache/probe_line_valid_q_reg`;
- slack: `-1.141 ns`;
- data path: 5.211 ns, with 3.609 ns routing (69.259%);
- logic: 14 levels, through MUL FIFO selection, forwarded address generation
  and the DCache valid-line selection.

Among the exported 500 worst setup paths, 257 start in the MUL FIFO family, 91
in EX/M1 registers, 44 in DCache, 19 in other EX internals and 79 at the CPU
reset synchronizer. Destinations include 241 DCache endpoints, 89 EX/M1
endpoints, 66 EX endpoints and 62 DRAM BRAM endpoints. The former DCache
response-to-M2 dependent-branch family is no longer the worst path.

The next broad limit is therefore forwarded-result/address routing into DCache
valid lookup, followed by ordinary EX result routing and DRAM BRAM write/control
routing. A proposed third iteration that would change cache-valid reset
implementation was explicitly not run at the user's request; this snapshot is
the selected second iteration.

## Maximum-frequency interpretation

The strict one-build STA estimate is `4.000 + 1.141031 = 5.141031 ns`, or
**194.514 MHz**, with a corresponding conservative workload time of about
**2.364175 s**. This is the only formal timing estimate.

If the user's empirical WNS allowance of -3 ns is extrapolated linearly from
this fixed placement, the WNS-only upper bound is roughly 467 MHz. That number
ignores nonlinear TNS growth, changed placement/routing, PLL limits, voltage,
temperature and board signal integrity, so it is not a usable operating claim.
A prudent next board-test band would be 300-333 MHz after separate synthesis;
the archived bitstream and all results in this snapshot remain strictly
**250 MHz**.

## DRC, power and archived artifacts

Checkpoint DRC reports six warnings and no error: one existing `CFGBVS-1`, two
`DPOP-1` and three `DPOP-2`. The DSP suggestions do not authorize a latency
change because MUL timing alignment is protected by the golden contract.
Estimated vectorless on-chip power is 0.642 W.

- Bitstream: `D:/jichuang_database/bitstream/final_v4_srcWithMext_250MHz.bit`
- Bitstream SHA-256:
  `EACDC47A149E877F7DFE1275E8C1E287356F7ECCD77EA00AE417CD47FC99669B`
- Checkpoint:
  `D:/jichuang_database/checkpoint/final_v4_srcWithMext_250MHz_postroute_physopt.dcp`
- Checkpoint SHA-256:
  `E0186AB3B3428091F2F95BF2FA47CA39D46F017903F21231476B51427B9911C4`
- Summary CSV:
  `D:/jichuang_database/report/final_v4_srcWithMext_250MHz_summary.csv`
- Timing summary, 500 setup paths, hold paths, hierarchical utilization, DRC,
  methodology, route status, power and clock reports use the prefix
  `D:/jichuang_database/report/final_v4_srcWithMext_250MHz_`.
- WSL simulation JSON:
  `D:/jichuang_database/report/final_v4_srcWithMext_sim_result.json`
- Read-only checkpoint export script:
  `D:/jichuang_database/report/archive_final_v4_250MHz_checkpoint.tcl`
- Rejected first-iteration reports, routed checkpoint and bitstream remain under
  `D:/jichuang_database/{report,checkpoint,bitstream}/final_v4_work/`.
