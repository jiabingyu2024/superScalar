# Recent-store L0 and timing retime

## Accepted changes

Three behavior-preserving timing changes and one memory microarchitecture
change were accepted after the dual-port move-macro baseline.

1. Predictor read/write collision forwarding now selects the update value
   before the predictor read register. This removes the registered collision
   feedback mux without changing predictions or IPC.
2. The four-entry FetchQueue is a fixed-head shift queue. Dispatch reads
   `entries_q[0]` instead of a wide distributed-RAM payload through a dynamic
   head pointer.
3. Branch miss generation compares the selected direct target or fallthrough
   against the predicted PC. JALR retains its dynamic target compare.
4. An eight-entry, direct-mapped recent-store L0 retains byte-valid words from
   committed cacheable stores after they drain from the StoreBuffer. Pending
   StoreBuffer bytes remain newer and override L0 bytes. The L0 only augments
   load metadata; it does not enter the direct-load arbitration path.

The recent-store state is not speculative: entries are written only when a
committed store is accepted for drain. Branch recovery therefore does not
clear the table. Uncached stores are excluded.

## Workload evidence

A temporary Verilator-only commit profiler was added, used for one 20M
`srcWithMext` run, and removed before final verification.

- committed instructions observed: 18.94M
- sequential adjacent pairs: 18.38M
- existing exact-move macro pairs: 2.145M
- all producer-plus-dependent-ADDI pairs: 2.787M
- load-use adjacent pairs: 4.912M
- same-cycle load-bypass issues: 4.921M
- load-dependent branches: only 20 in the 20M `srcWithMext` window
- loads within 64 commits of a store to the same address: 2.768M
- pure forwarding completions before the recent-store L0: 19,459

The hottest addresses were six stack slots around `0x80120fe8` through
`0x80120ffc`. This showed that the workload repeatedly spills loop variables
and accumulators, while the StoreBuffer loses forwarding coverage as soon as
a committed store drains.

## Final verification

- RV32IM: 52/52 pass.
- `srcSmoke`, 500k cycles:
  - IPC 0.696430
  - commit 348215
  - RV32I 37, fail 0
- `srcWithMext`, 500k cycles:
  - IPC 0.901078
  - commit 450539
  - RV32I 37, M 8, fail 0
- `srcWithMext`, 20M cycles:
  - IPC 0.950644
  - commit 19012874
  - branch 573642, miss 7213
  - load 6045341, store 1132347
  - DCache access 7101992
  - RV32I 37, M 8, fail 0

The 20M IPC improves from 0.947182 to 0.950644, approximately 0.365%.

## Synthesis result

Iteration `iteration52_recent_store_l0`, at a 5 ns constraint:

- WNS: -1.307 ns
- TNS: -1024.867 ns
- setup violating endpoints: 3135
- estimated Fmax: 158.55 MHz
- IPC x Fmax: approximately 150.73

The preceding fixed-head/predictor/branch-only iteration had WNS -1.491 ns,
estimated Fmax 154.06 MHz, and product approximately 145.92. The accepted
iteration improves the synthesis product by approximately 3.29%.

The current worst synthesis path is:

```text
DCache tag BRAM output
  -> hit/completion control
  -> IQ same-cycle load-dependent oldest-ready selection
  -> exec_q operand register
```

This path represents a real high-value operation: 4.921M load consumers use
same-cycle completion bypass in the 20M window.

## Rejected experiments

- Registered load-to-branch wakeup: almost neutral on `srcWithMext`, but
  reduced `srcSmoke` IPC by about 0.37% and worsened WNS to -1.751 ns.
- Duplicated normal/load-bypass IQ selection trees: exact IPC, but the second
  wide payload mux worsened WNS to -2.041 ns.
- Active full-forward DCache bypass: reduced DCache traffic from 7.10M to
  3.87M accesses but changed 20M IPC by only +0.000007 and worsened WNS to
  -1.615 ns because the forwarding compare entered direct-load arbitration.

These results rule out simply adding a load wakeup pipeline stage or placing
recent-store hit logic on the direct request path. A future timing attempt
must preserve the same-cycle load bypass while reducing IQ payload muxing.
