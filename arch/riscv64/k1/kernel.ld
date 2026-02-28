/* Linker Script for Clarigggz OS - Spacemit K1 RISC-V */

ENTRY(_start)

SECTIONS {
    /* Typical start for RISC-V bare-metal firmware/kernels */
    . = 0x80000000;

    .text : {
        KEEP(*(.text.boot))
        *(.text .text.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    .data : {
        *(.data .data.*)
    }

    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        _bss_end = .;
    }

    /DISCARD/ : {
        *(.comment)
        *(.note.GNU-stack)
    }
}
