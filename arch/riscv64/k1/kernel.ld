/* Linker Script for Clarigggz OS - Spacemit K1 RISC-V */

ENTRY(_start)

SECTIONS {
    /* OpenSBI next address is 0x80200000 */
    . = 0x80200000;

    .text : {
        KEEP(*(.text.boot))
        *(.text .text.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    .data : {
        *(.data .data.*)
        PROVIDE(__global_pointer$ = . + 0x800);
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
