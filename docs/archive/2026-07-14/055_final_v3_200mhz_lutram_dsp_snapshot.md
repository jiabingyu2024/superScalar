# final_v3 200 MHz LUTRAM/DSP timing snapshot

Date: 2026-07-14

Branch: `dev-7-final-improve`

Parent baseline: `b978840 final_v2 -0.690 ns -533 ns 459M cycles`

## Selected changes

`final_v3` keeps the final_v2 pipeline, zero-bubble aligned-load path, 128-entry
BTB, 256-entry gshare PHT and 16-entry RAS. It makes two no-cycle structural
changes:

1. The 32x32 architectural register file now writes on the rising edge, has an
   explicit same-cycle WB write-through bypass and is inferred as replicated
   distributed RAM (`RAM32M`) instead of 1024 resettable flip-flops. FPGA INIT
   and the Verilator model start it at zero; later CPU resets no longer clear
   x1-x31. This is ISA-legal because only x0 has a defined architectural zero.
2. The existing 33x33 signed, three-stage `MUL_0` is explicitly configured as
   `Multiplier_Construction=Use_Mults`. Its latency, ports and result alignment
   are unchanged, but the implementation moves from 1160 LUT / 860 FF to
   0 LUT / 34 FF plus four DSP48 blocks.

No branch-predictor RTL was changed.

## Golden timing contract

`docs/fpga/ip_timing_alignment.md` remains the golden rule and was updated to
describe the already-existing implementation facts that had become stale:

- `MUL_0`: `PipeStages=3`, behavior model `pipe0 -> pipe1 -> P`, consumer
  metadata depth 3 in `stage_ex.sv`;
- `DIV_0`: `Latency=34`, fixed 34-cycle completion count in `m_unit.sv`.

The selected RTL does not change IROM, DRAM, MUL, DIV, PLL or CDC latency and
enable contracts. Synthesis and implementation were fixed at 200 MHz (5.000
ns) with `Performance_ExplorePostRoutePhysOpt`.

## WSL verification and cycles impact

Both Verilator targets were rebuilt in WSL after the selected source changes.

- RV32I: 40/40 PASS.
- RV32M: 8/8 PASS, covering MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU.
- RV32MI: 4/4 PASS.
- `srcSmoke`: PASS.
- `srcWithMext`, 500,000,000-cycle limit: PASS at **459,864,062 cycles**.

The workload counters are bit-for-bit unchanged from final_v2:

| Counter | final_v2 | final_v3 |
| --- | ---: | ---: |
| Cycles | 459,864,062 | **459,864,062** |
| DCache access | 132,057,221 | **132,057,221** |
| DCache miss | 3,520,473 | **3,520,473** |
| Load-access stall | 44,805,312 | **44,805,312** |
| Final SEG | `0x37809197` | **`0x37809197`** |

At nominal 200 MHz, `cycles / frequency` is about **2.299320 s**. The user
reported about 2.2 s on the current board; because cycles and clock are
unchanged, final_v3 is expected to preserve rather than improve that board
runtime. Its benefit is implementation margin and a cleaner path to a later
frequency experiment.

The profile still reports zero branch counters, so no branch hit-rate number is
invented. General predictor quality is protected by leaving all predictor RTL
unchanged and rerunning BEQ/BNE/JAL/JALR directed tests as part of RV32I.

## 200 MHz Vivado result

| Metric | final_v2 | final_v3 | Delta |
| --- | ---: | ---: | ---: |
| WNS | -0.690 ns | **-0.452 ns** | +0.238 ns |
| TNS | -532.507 ns | **-243.591 ns** | +288.916 ns |
| Setup failing endpoints | 2,880 | **1,658** | -1,222 |
| WHS | +0.070 ns | **+0.050 ns** | -0.020 ns, still clean |
| Hold failing endpoints | 0 | **0** | 0 |
| Slice LUTs | 10,219 | **8,594** | -1,625 |
| Slice registers | 9,176 | **7,533** | -1,643 |
| BRAM tiles | 68 | **68** | 0 |
| DSP blocks | 0 | **4** | +4 |

Unlike the final_v2 and iteration-1 runs, post-route physical optimization
completed successfully. The final checkpoint and bitstream therefore include
the valid post-route improvement from routed WNS/TNS -0.523/-244.577 ns to
**-0.452/-243.591 ns**.

The strict STA period estimate is `5.000 + 0.452 = 5.452 ns`, or about
**183.4 MHz**. That is the formal sign-off-style estimate from this one build,
not an assertion that the board fails at 200 MHz. The strict cycle-time estimate
is about 2.507 s. To beat 2.2 s with the same cycles would require at least
**209.0 MHz**, which was not synthesized because this task fixed every run at
200 MHz. A WNS-only extrapolation to the project's empirical -3 ns envelope
would suggest roughly 408 MHz, but that ignores TNS, PLL limits, routing changes
and board behavior and is explicitly rejected as a usable maximum-frequency
claim. The maximum actually tested implementation target remains **200 MHz**.

## Remaining timing limits

The final worst setup path remains the zero-bubble DCache fast-load cone into
EX/M1 ALU result: 5.316 ns data delay, 14 logic levels and 73.852% routing
delay. Other leading families are:

- DCache tag lookup through ready/hazard control into pipeline reset/enable;
- M1 address/control into DRAM BRAM write enable, with about 88% routing delay;
- DCache-ready/hazard control into IROM enable;
- multiply-result FIFO read into the EX result mux.

These are distributed routing/control limits rather than the register file or
LUT multiplier that final_v3 removed. Deleting the fast-load path was already
shown in the final_v2 work to exceed the 500M-cycle hard limit. Increasing MUL
latency to consume additional DSP internal registers was not attempted because
MUL is not the final WNS family and that change would alter both the golden
latency contract and workload cycles.

## Iteration record

1. Rising-edge FF register file plus WB write-through: all WSL tests passed and
   cycles were unchanged, but routed WNS/TNS were -0.775/-557.575 ns. It reduced
   setup endpoints to 2,204 yet was worse than final_v2 on WNS and TNS, so it was
   rejected as a standalone result.
2. Distributed-RAM register file plus explicit DSP multiplier: selected result
   above. The synthesis report explicitly identified `rf_mem_reg` as 32x32
   `RAM32M`, the XCI recorded `Use_Mults`/`PipeStages=3`, and final utilization
   recorded four DSP blocks.
3. `Performance_ExtraTimingOpt` comparison: the first attempt was interrupted
   by an external PC restart before any implementation checkpoint. The clean
   rerun reached post-placement WNS -0.933 ns with an estimated TNS around
   -1287 ns, then spent several minutes in an extra optimization stage without
   a checkpoint. It was terminated because it was materially behind iteration
   2 and repeated the previously observed long-running strategy behavior.

## Archived artifacts

- Bitstream: `D:/jichuang_database/bitstream/final_v3_srcWithMext_200MHz.bit`
- Summary: `D:/jichuang_database/report/final_v3_srcWithMext_summary.csv`
- Timing summary: `D:/jichuang_database/report/final_v3_srcWithMext_200MHz_timing_summary.rpt`
- Failing setup paths: `D:/jichuang_database/report/final_v3_srcWithMext_200MHz_failing_paths_setup.rpt`
- Failing hold paths: `D:/jichuang_database/report/final_v3_srcWithMext_200MHz_failing_paths_hold.rpt`
- Hierarchical utilization: `D:/jichuang_database/report/final_v3_srcWithMext_200MHz_utilization_hier.rpt`
- Vivado post-route phys-opt timing: `D:/jichuang_database/report/final_v3_srcWithMext_200MHz_vivado_postroute_physopt_timing.rpt`
- Iteration work remains under `D:/jichuang_database/report/final_v3_work/` and
  `D:/jichuang_database/bitstream/final_v3_work/`.
