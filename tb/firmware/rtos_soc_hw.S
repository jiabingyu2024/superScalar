    .section .text.init
    .globl _start
_start:
    # Verify that constants in program ROM are readable through the data port.
    la      t0, rom_constant
    lw      t1, 0(t0)
    li      t2, 0x5aa55aa5
    bne     t1, t2, fail

    la      t0, trap_entry
    csrw    mtvec, t0
    li      t0, 0x80
    csrw    mie, t0
    csrsi   mstatus, 8

    li      t0, 0x0200bff8
    lw      t1, 0(t0)
    addi    t1, t1, 100
    li      t0, 0x02004004
    sw      zero, 0(t0)
    li      t0, 0x02004000
    sw      t1, 0(t0)

spin:
    beqz    s1, spin

pass:
    li      t0, 0x80200040
    li      t1, 0x13572468
    sw      t1, 0(t0)
    j       pass

    .align 2
trap_entry:
    csrr    t0, mcause
    li      t1, 0x80000007
    bne     t0, t1, fail
    li      t0, 0x02004004
    li      t1, -1
    sw      t1, 0(t0)
    li      s1, 1
    mret

fail:
    li      t0, 0x80200040
    li      t1, 0xdead0001
    sw      t1, 0(t0)
    j       fail

    .section .rodata
    .align 2
rom_constant:
    .word 0x5aa55aa5
