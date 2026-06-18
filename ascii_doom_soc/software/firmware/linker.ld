ENTRY(_start)

MEMORY {
    bram (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}

SECTIONS {
    . = 0x00000000;

    .text : {
        *(.text.start)   /* startup first */
        *(.text*)
        *(.rodata*)
    } > bram

    .data : {
        *(.data*)
        *(.sdata*)
    } > bram

    .bss : {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
    } > bram

    /* Stack at the top of BRAM — must match STACKADDR in soc_top.sv */
    _stack_top = ORIGIN(bram) + LENGTH(bram) - 16;

    /* GP relaxation anchor */
    __global_pointer$ = MIN(_stack_top - 0x800, MAX(ABSOLUTE(.), 0x800));
}
