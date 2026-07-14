# final_v5 250 MHz MUL-result register-FIFO snapshot

Date: 2026-07-14

Branch: `dev-7-final-improve`

RTL/archive commit: this commit
(`final_v5 250MHz -0.988 ns -1258 ns 459M cycles`)

Parent: `becafc2` (`final_v4 250MHz -1.141 ns -1981 ns 459M cycles`)

## Selected change

`final_v5` keeps the final_v4 in-order pipeline, 128-entry BTB, 256-entry
gshare PHT, 16-entry RAS, LUTRAM register file, blocking 8 KiB DCache and
three-cycle four-DSP multiplier. The only selected RTL change is the physical
implementation of the four-entry MUL-result FIFO in `rtl/core/core.sv`.

The old FIFO used a circular array with dynamic head/tail indices. Vivado
inferred its asynchronous read as distributed RAM, so late MUL forwarding
started at `mul_fifo_head`, crossed a `RAMD32`, selected the architectural WB
value, performed EX address/ALU work and then entered the DCache probe cone in
one cycle. In final_v4 this family supplied 257 of the exported 500 worst
setup paths.

The selected FIFO is a fixed-head register shift queue:

1. dequeue shifts the remaining registered entries toward entry zero;
2. enqueue writes the slot selected by the registered count;
3. simultaneous dequeue/enqueue shifts and appends without changing count;
4. empty-FIFO same-cycle completion still uses the existing direct MUL-result
   bypass, preserving the original producer/consumer alignment.

The final synthesis mapping no longer contains a `mul_result_fifo` RAMD32
entry. FIFO capacity, ordering, throughput, empty-bypass behavior and the MUL
latency contract are unchanged.

## Golden timing contract and branch prediction

`docs/fpga/ip_timing_alignment.md` was treated as immutable and its SHA-256
remains
`596CB9EEF0D5085F207E58800493CCD7F8A284E880C1D23B49B6BF8F177E0BAA`.
The selected RTL does not change:

- IROM one-cycle behavior;
- DRAM `ENA`/`REGCEA`, registered primitive output or request/response phase;
- MUL 33x33 signed width, three-stage latency, DSP construction or metadata
  depth;
- DIV fixed 34-cycle latency;
- PLL, CDC grouping, reset synchronization or the 250 MHz target;
- BTB/PHT/RAS size, indexing, training, update timing or recovery policy.

The profile still exposes zero branch counters, so no hit rate is fabricated.
General prediction quality is protected structurally by leaving the complete
BPU unchanged and functionally by rerunning every RV32 branch/JAL/JALR test.

## WSL verification and cycles impact

Both Verilator targets were rebuilt in Ubuntu WSL from the selected final_v5
RTL. Final regression results:

- RV32I: 40/40 PASS;
- RV32M: 8/8 PASS;
- RV32MI: 4/4 PASS;
- `srcSmoke`: PASS;
- `srcWithMext`, 500,000,000-cycle limit: PASS at **459,864,062 cycles**.

The remaining failures in `sim-rv32-all` are the pre-existing unsupported
Zba/Zbb/Zbc/Zb* suites, not regressions.

| Counter | final_v4 | final_v5 | Delta |
| --- | ---: | ---: | ---: |
| Cycles | 459,864,062 | **459,864,062** | 0 |
| DCache access | 132,057,221 | **132,057,221** | 0 |
| DCache miss | 3,520,473 | **3,520,473** | 0 |
| Load-access stall | 44,805,312 | **44,805,312** | 0 |
| Final SEG | `0x37809197` | **`0x37809197`** | unchanged |

At 250 MHz the projected cycle time is **1.839456248 s**, 10.54 ms below the
1.85 s reference. This is a cycle/frequency projection; board measurement is
still required for a measured-speed claim.

## Final 250 MHz implementation

Vivado 2023.2 regenerated a clean project and all IP, with CPU target fixed at
250.000 MHz (4.000 ns) and strategy
`Performance_ExplorePostRoutePhysOpt`.

| Metric | final_v4 | final_v5 | Delta |
| --- | ---: | ---: | ---: |
| WNS | -1.141031 ns | **-0.988 ns** | +0.153031 ns |
| TNS | -1981.117798 ns | **-1258.184 ns** | +722.933798 ns |
| Setup failing endpoints | 4,725 | **3,259** | -1,466 |
| WHS | +0.044032 ns | **+0.059 ns** | +0.014968 ns |
| THS / hold endpoints | 0 / 0 | **0 / 0** | unchanged |
| Slice LUTs | 8,765 | **8,826** | +61 |
| Slice registers | 7,568 | **7,727** | +159 |
| BRAM tiles | 68 | **68** | unchanged |
| DSP blocks | 4 | **4** | unchanged |

The routed design reached `-1.047/-1259.806 ns`; post-route physical
optimization completed successfully and improved it to
`-0.988/-1258.184 ns`. All 14,209 routable nets are fully routed with zero
routing errors. Hold timing is clean.

Vivado formally reports setup failure at 250 MHz. The result is nevertheless
well inside the user-provided empirical board envelope of WNS magnitude below
3 ns and TNS magnitude below 15,000 ns, and is strictly better than final_v4
on WNS, TNS and failing endpoints.

## Remaining critical paths

The final worst path starts at the registered MUL/DSP result, passes through
the late WB forward mux and EX address generation, and ends at
`u_dcache/probe_pending_data_q_reg[6]`:

- slack: `-0.988 ns`;
- data path: 4.826 ns;
- route: 3.570 ns (73.977%);
- logic: 11 levels.

Among the exported 500 worst setup paths, 224 now start in the direct MUL
result/opcode family, only one remains in the old MUL FIFO family, 21 start in
other DCache state and 39 at reset. Destinations include 128 DCache endpoints,
62 EX/M1 endpoints and 61 DRAM endpoints. The optimization therefore removed
the intended dynamic FIFO-read bottleneck rather than merely moving its
pointer logic.

The next broad limit is the direct three-cycle MUL completion late-forwarded
into EX/DCache, followed by ordinary EX/branch and DRAM routing. Changing MUL
latency to address it would require changing the golden IP contract and was not
selected.

## Rejected iterations

1. DCache valid metadata in LUTRAM removed the wide resettable valid mux but
   added a 512-cycle reset scrub. It passed at 459,864,559 cycles (+497), while
   routed timing worsened to `-1.369/-2555.674 ns`; post-route physopt also
   crashed, so it was rejected.
2. Holding every MUL RAW consumer through M1 removed late MUL forwarding but
   increased the workload to 470,488,092 cycles (+10,624,030), or about
   1.882 s at 250 MHz; it was rejected before implementation.
3. A MUL-to-memory-address-only guard kept cycles unchanged, but its added
   address cone produced `-0.994/-1671.491 ns` and 4,247 failing endpoints.
   WNS was slightly worse and TNS/endpoints materially worse than the selected
   register FIFO, so it was rejected.

## Maximum-frequency interpretation

The strict single-build STA estimate is `4.000 + 0.988 = 4.988 ns`, or
**200.481 MHz**. At that formal frequency the workload projection is about
**2.293802 s**. This is the only formal maximum-frequency estimate from this
implementation.

If the user's empirical WNS allowance of -3 ns is extrapolated linearly from
this fixed placement, the WNS-only mathematical ceiling is about 503 MHz.
That is not an operating recommendation: TNS growth, re-placement, PLL/device
limits, voltage, temperature and board integrity are nonlinear. A separate
300-333 MHz implementation and staged board test would be the prudent next
experiment. The archived final_v5 artifact itself remains strictly 250 MHz.

## DRC, power and archived artifacts

Checkpoint DRC reports six warnings and no error: one existing `CFGBVS-1`, two
`DPOP-1` and three `DPOP-2`. The DSP pipelining suggestions do not authorize a
MUL latency change under the golden contract. Estimated vectorless on-chip
power is 0.728 W.

- Bitstream:
  `D:/jichuang_database/bitstream/final_v5_srcWithMext_250MHz.bit`
- Bitstream SHA-256:
  `35177A554E0E5D1BB5E1DA2C73B9BA73BB4560ECCF5E6FB32BEA27D1912F25EF`
- Checkpoint:
  `D:/jichuang_database/checkpoint/final_v5_srcWithMext_250MHz_postroute_physopt.dcp`
- Checkpoint SHA-256:
  `5F3796EB35E623A73328A69A8DF83540EA80FFEE6B878E4AD58EB049C74456DB`
- Summary CSV:
  `D:/jichuang_database/report/final_v5_srcWithMext_summary.csv`
- Timing summary, 500 setup paths, hold paths, hierarchical utilization, DRC,
  methodology, route status, power and clock reports use the prefix
  `D:/jichuang_database/report/final_v5_srcWithMext_250MHz_`.
- WSL simulation JSON:
  `D:/jichuang_database/report/final_v5_srcWithMext_sim_result.json`
- Rejected-iteration reports and bitstreams remain under
  `D:/jichuang_database/{report,bitstream}/final_v5_work/`.
