# final_v3 250 MHz timing trial archive

Date: 2026-07-14

Branch: `dev-7-final-improve`

RTL commit: `42a7a2412fa32580bef48d3fd5c655f9216a0d30` (`final_v3 -0.452 ns -244 ns 459M cycles`)

Archive role: frequency trial only. The signed-off project baseline and bitstream
remain the final_v3 200 MHz artifacts recorded in
`055_final_v3_200mhz_lutram_dsp_snapshot.md`.

## Run identity

The user launched synthesis and implementation from:

`D:/jichuang_new/fpga/build/digital_twin_srcWithMext/digital_twin.xpr`

The CPU clock was fixed at 250 MHz (4.000 ns) and implementation used
`Performance_ExplorePostRoutePhysOpt`. The final implementation checkpoint was
`top_postroute_physopt.dcp`, produced at 2026-07-14 13:27:17 by Vivado 2023.2.
Post-route physical optimization completed successfully.

No synthesis, implementation or bitstream generation was rerun during archival.
The archive reports were regenerated read-only by opening that checkpoint.

## Final timing and utilization

| Metric | final_v3 200 MHz | final_v3 250 MHz trial | Change at 250 MHz |
| --- | ---: | ---: | ---: |
| Period | 5.000 ns | **4.000 ns** | -1.000 ns |
| WNS | -0.452 ns | **-1.513 ns** | -1.061 ns |
| TNS | -243.591 ns | **-3742.260 ns** | -3498.669 ns |
| Setup failing endpoints | 1,658 | **5,196** | +3,538 |
| WHS | +0.050 ns | **+0.048 ns** | -0.002 ns, still clean |
| THS / hold endpoints | 0 / 0 | **0 / 0** | unchanged |
| Slice LUTs | 8,594 | **8,580** | -14 |
| Slice registers | 7,533 | **7,309** | -224 |
| BRAM tiles | 68 | **68** | unchanged |
| DSP blocks | 4 | **4** | unchanged |

The routed checkpoint was at WNS/TNS `-1.640/-3741.669 ns`. Post-route physical
optimization improved WNS by 0.127 ns to `-1.513 ns`; TNS changed by only
-0.591 ns and one additional endpoint. The final design is fully routed with
zero routing errors. Hold timing is clean.

Vivado formally reports that setup constraints are not met. The result is,
however, inside the user's empirical board-test envelope of WNS above -3 ns and
TNS above -15000 ns. That makes it a useful board-test candidate, not a formal
250 MHz timing sign-off.

## Critical path reading

The worst setup path is:

- source: `u_reg_ex_m1/o_cache_tag_indices_reg[27]_replica/C`;
- destination: `u_reg_ex_m1/o_cache_data_indices_reg[10]_replica_3/R`;
- slack: `-1.513 ns`;
- data path: 5.205 ns, of which 4.413 ns (84.785%) is routing;
- logic: 9 levels (`RAMD64E`, six LUT/MUX levels and the final LUT2).

It passes through DCache tag lookup, `cpu_req_ready`, hazard/flush control and a
high-fanout pipeline-register reset net. The next paths combine the same cache
lookup/ready cone with the zero-bubble load-to-ALU path. A separate leading
family drives DRAM BRAM write enable and is 87.8% routing delay. MUL FIFO result
selection is also present among the leading paths, but it is not the worst
family.

The exported 500 worst setup paths principally terminate in `u_reg_id_ex` (182
paths), `u_reg_ex_m1` (96), `u_reg_pc_if` (37), `u_reg_if_id` (28), DRAM BRAM
write control (25), and DCache state (21). This is consistent with a distributed
ready/flush/control and routing limit rather than a new multiplier, register-file
or memory-latency alignment problem.

## Cycles and runtime interpretation

The RTL and architectural latency contracts are unchanged from the 200 MHz
final_v3 snapshot. Therefore the verified `srcWithMext` result remains
**459,864,062 cycles**, below the 500,000,000-cycle limit; no new cycle count is
invented from the implementation run.

- Ideal runtime at a physically successful 250 MHz is about **1.839456 s**.
- The same cycles at 200 MHz take about **2.299320 s**.
- A strict one-build STA estimate is `4.000 + 1.513 = 5.513 ns`, or about
  **181.389 MHz** and **2.535231 s**.

The 1.839 s figure is the relevant projected board runtime only if the design
actually operates at 250 MHz. The strict estimate is intentionally conservative
and demonstrates why negative WNS must not be represented as formal closure.

Branch predictor RTL is unchanged, so the generally useful prediction behavior
protected by final_v3 is not traded away in this frequency-only trial.

## Golden timing contract and DRC

No RTL, XCI, Tcl project-generation source, constraint source, or file under
`docs/fpga/` was changed for this archive. In particular,
`docs/fpga/ip_timing_alignment.md` remains untouched and all IROM, DRAM, MUL,
DIV, PLL and CDC latency/enable contracts remain those verified for final_v3.

Checkpoint DRC found six warnings and no routing error: one existing
`CFGBVS-1`, two `DPOP-1`, and three `DPOP-2`. The DSP pipelining suggestions do
not authorize a latency change because that would require corresponding golden
contract and consumer-alignment work. Estimated vectorless on-chip power is
0.740 W.

## Archived artifacts

- Checkpoint: `D:/jichuang_database/checkpoint/final_v3_srcWithMext_250MHz_postroute_physopt.dcp`
- Checkpoint SHA-256: `993CD2FE10BE03DF4D9CA21AD4EE655141520DCFE3870F3C3AF6FB733B63E232`
- Summary CSV: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_summary.csv`
- Timing summary: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_timing_summary.rpt`
- 500 setup paths: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_failing_paths_setup.rpt`
- Hold paths: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_failing_paths_hold.rpt`
- Hierarchical utilization: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_utilization_hier.rpt`
- Routed timing: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_vivado_routed_timing.rpt`
- Post-route phys-opt timing: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_vivado_postroute_physopt_timing.rpt`
- Placed utilization: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_vivado_utilization_placed.rpt`
- Synth/implementation logs: `D:/jichuang_database/report/final_v3_srcWithMext_250MHz_{synth,impl}_runme.log`
- DRC, methodology, route status, power, clock utilization and clock interaction
  reports use the same `final_v3_srcWithMext_250MHz_` prefix.
- Read-only export script: `D:/jichuang_database/report/archive_final_v3_250MHz_checkpoint.tcl`

No `.bit` file existed in the completed project run, so no 250 MHz bitstream is
claimed or archived. The 200 MHz final_v3 bitstream is not modified.
