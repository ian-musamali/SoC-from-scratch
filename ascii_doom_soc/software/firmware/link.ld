/* PicoRV32 linker script — Nexys A7 BRAM layout
 * BRAM: 0x0000_0000 – 0x0003_FFFF (256 KB)
 *   .text + .rodata in lower BRAM
 *   .data + .bss    in upper BRAM
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 256K
}

SECTIONS {
    . = 0x00000000;

    .text : {
        *(.text.init)        /* _start must come first */
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > BRAM

    .data : {
        . = ALIGN(4);
        *(.data*)
        . = ALIGN(4);
    } > BRAM

    .bss : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > BRAM

    /* Stack grows downward from top of BRAM */
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM);
}
