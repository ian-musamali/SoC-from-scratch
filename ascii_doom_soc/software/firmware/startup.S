# PicoRV32 startup — must be first in the link order.
# Stack is pre-loaded by PicoRV32's STACKADDR parameter, but we set it
# explicitly here as well so the firmware is self-contained.
.section .text.start
.global  _start
_start:
    .option norelax
    la   sp, _stack_top     # top of BRAM
    la   gp, __global_pointer$
    .option relax
    call main
_hang:
    j    _hang
