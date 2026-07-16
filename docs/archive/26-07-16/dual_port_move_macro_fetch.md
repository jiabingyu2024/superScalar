# Dual-port move macro fetch

## Result

The accepted iteration adds a second IROM read port and recognizes one narrow,
high-frequency instruction pair:

```text
producer writing rd1
addi rd2, rd1, 0
```

Only an 8-byte-aligned, non-control producer is eligible. Port A reads the
producer and port B reads the adjacent word without an address incrementer.
The frontend advances by eight bytes and pushes one macro fetch entry.

At dispatch, the producer and move receive two consecutive scoreboard entries,
but only the producer enters the issue queue. Consumers of the move temporarily
depend on the producer transaction. Producer completion fills both scoreboard
entries with the same result, preserving two architectural instructions and
in-order single commit.

## Verification

- RV32IM: 52/52 pass.
- `srcSmoke`, 500k cycles: IPC 0.688324, commit 344162, RV32I 37, fail 0.
- `srcWithMext`, 500k cycles: IPC 0.896398, commit 448199, RV32I 37, M 8, fail 0.
- `srcWithMext`, 20M cycles: IPC 0.947182, commit 18943637.
- Long-window branch miss count: 7191 / 571770.
- Long-window DCache hit rate: 0.997432.

Synthesis at a 5 ns constraint:

- WNS: -1.491 ns.
- TNS: -2049.161 ns.
- Estimated Fmax: 154.06 MHz.
- IPC x Fmax: approximately 145.92.

The previous committed baseline had long-window IPC 0.856137 and synthesis
Fmax 164.12 MHz, for an IPC x Fmax of approximately 140.51. The accepted macro
fetch therefore improves the synthesis product by approximately 3.85%.

## Rejected narrowing

Replacing the 32-bit macro instruction payload with only the move destination
register did not change IPC, but changed synthesis mapping and exposed a
DCache-to-IQ-to-execute path:

```text
DCache tag BRAM -> load queue/IQ selection -> exec operand
```

That version produced WNS -1.911 ns and was rejected. Restoring the full macro
payload exactly reproduced WNS -1.491 ns.

## Bottleneck analysis

Dynamic PC counts from the pre-macro 20M trace map 15.91M committed
instructions. The dominant mix is:

- load: 32.12%
- add: 20.30%
- addi: 17.70%
- shift-left-immediate: 17.38%
- store: 5.99%
- multiply: 3.00%
- branch-greater-or-equal: 2.99%

The accepted move macro covers an estimated 1.84M dynamic pairs, about 11.6%
of the traced instruction stream. This explains why the design is now close
to the single-commit ceiling: IPC 0.947 leaves only about 5.3% empty commit
cycles.

The next architecture experiments should therefore target the commit ceiling,
not a larger generic issue queue:

1. Dual-retire only completed producer/move macro pairs.
2. Fuse aligned `addi rd, x0, imm` plus a consuming backward conditional
   branch. The trace contains about 457k such pairs.
3. Evaluate dual-result producer macros such as aligned load-plus-addi or
   shift-plus-add, only if their additional completion logic stays away from
   the existing load wakeup critical path.

Generic dual issue, mirrored DCache hits-under-miss, and further Vivado
directive sweeps remain lower priority.
