/* PicoRV32 startup: zero BSS, then jump to main */
    .section .text.init
    .globl _start
_start:
    /* Set stack pointer */
    la   sp, _stack_top

    /* Zero BSS */
    la   t0, _bss_start
    la   t1, _bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    /* Jump to C entry point */
    call main
    /* Halt if main returns */
3:  j 3b
