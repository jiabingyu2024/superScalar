# final_v1 200 MHz LW fast-path snapshot

Date: 2026-07-13

Branch: `dev-7-final-improve`

Parent: `3dbbf85`

## Snapshot scope

This snapshot is the exact RTL variant used for the archived 200 MHz Vivado
implementation named `final_v1_lwfast_460M`. Later exploratory changes were
removed before the snapshot.

The design keeps the external DRAM/SoC/IP timing contract unchanged and follows
`docs/fpga/ip_timing_alignment.md`:

- no change to DRAM `ENA`/`REGCEA` behavior;
- no change to valid/data/offset alignment;
- no change to the registered Vivado DRAM return contract.

## RTL strategy

1. Keep the 512-line DCache data array as asynchronous distributed RAM.
2. Export only an aligned 32-bit cache word on the combinational fast path.
3. Restrict zero-bubble late load forwarding to aligned `LW` followed by the
   small integer subset `ADD/SUB/AND/OR/XOR`.
4. Route the fast word through a dedicated small ALU path, keeping shifts,
   comparisons, branches, memory operations, CSR and M-extension operations off
   the DCache-to-EX timing cone.
5. Add exact `uses_rs1`/`uses_rs2` decode so non-source instruction fields do not
   create false load-use stalls. Other immediate load consumers receive one
   bubble and forward registered M2 data.

## WSL verification

- Verilator `student_top` build: PASS
- Verilator `myCPU` build: PASS
- `srcSmoke`: PASS
- `srcWithMext`, limit 500,000,000: PASS
- `srcWithMext` cycles: **460,527,872**
- 200 MHz cycle time estimate: **2.302639 s**
- Directed RV32 load/store and integer tests: PASS
- RV32I/RV32M/RV32MI suites: PASS; pre-existing unimplemented Zb tests remain
  outside this snapshot's regression scope.

The rejected fully synchronous block-RAM DCache experiment reached the
500,000,000-cycle limit without completing and is not part of this snapshot.

## 200 MHz Vivado result

Profile: `srcWithMext`

Strategy: `Performance_ExplorePostRoutePhysOpt`

| Metric | final_v0 | final_v1 snapshot |
|---|---:|---:|
| WNS | -1.771 ns | **-0.590 ns** |
| TNS | -6827.010 ns | **-1469.804 ns** |
| Setup failing endpoints | 16,745 | **8,253** |
| WHS | +0.054 ns | **+0.059 ns** |
| Slice LUTs | 9,489 | **9,721** |
| Slice registers | 8,855 | **8,635** |
| BRAM tiles | 68 | **68** |

Strict STA period is approximately `5.000 + 0.590 = 5.590 ns`, corresponding
to about **178.9 MHz**. The project-specific empirical acceptance rule permits
moderate negative slack at 200 MHz; this snapshot's WNS/TNS are well inside the
given `-3 ns / -15000 ns` envelope.

The worst path moved away from the old DCache-byte-rotate-to-general-ALU cone.
The new worst path is M1 register-address forwarding control through the normal
EX ALU. The DCache fast-word path appears behind it at about -0.580 ns.

## Archived artifacts

- Bitstream: `D:/jichuang_database/bitstream/final_v1_lwfast_460M_srcWithMext_200MHz.bit`
- Summary: `D:/jichuang_database/report/final_v1_lwfast_460M_srcWithMext_summary.csv`
- Timing summary: `D:/jichuang_database/report/final_v1_lwfast_460M_srcWithMext_200MHz_timing_summary.rpt`
- Failing setup paths: `D:/jichuang_database/report/final_v1_lwfast_460M_srcWithMext_200MHz_failing_paths_setup.rpt`
- Hierarchical utilization: `D:/jichuang_database/report/final_v1_lwfast_460M_srcWithMext_200MHz_utilization_hier.rpt`
- Synthesis and implementation logs use the same
  `final_v1_lwfast_460M_srcWithMext_200MHz` prefix in the report directory.

No further optimization is included after this snapshot.
