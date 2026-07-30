    .section .text.init
    .globl _start
_start:
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
    j       pass

    .align 2
trap_entry:
    csrr    t0, mcause
    li      t1, 0x80000007
    bne     t0, t1, fail
    csrr    t0, mepc
    andi    t0, t0, 3
    bnez    t0, fail

    li      t0, 0x02004004
    li      t1, -1
    sw      t1, 0(t0)
    li      s1, 1
    mret

pass:
    li      t0, 0x80001000
    li      t1, 1
    sw      t1, 0(t0)
    j       pass

fail:
    li      t0, 0x80001000
    li      t1, 3
    sw      t1, 0(t0)
    j       fail

    .section .tohost,"aw",@progbits
    .align 2
    .globl tohost
tohost:
    .word 0
