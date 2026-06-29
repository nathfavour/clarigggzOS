# RISC-V K1 Early Boot Logic
# Clarigggz OS - Core Broker Entry Point

.section .text.boot
.global _start

_start:
    # Initialize Global Pointer (gp) with relaxation disabled for this instruction
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # 1. Disable Interrupts initially in sstatus (SIE bit 1 is cleared)
    # We clear the SIE bit to prevent early interrupts before configuration
    li t0, 2
    csrc sstatus, t0

    # 2. Enable Vector Extension (RVV 1.0) in sstatus
    # We set the VS bits (bits 9-10) to Initial (01) or Dirty (11) status
    li t1, 0x00000600
    csrs sstatus, t1

    # 3. Register S-Mode Trap Vector
    la t0, trap_entry
    csrw stvec, t0

    # 4. Initialize Stack Pointer
    la sp, _boot_stack_top

    # 5. Zero out BSS
    la t2, _bss_start
    la t3, _bss_end
zero_bss_loop:
    bge t2, t3, jump_to_zig
    sb zero, 0(t2)
    addi t2, t2, 1
    j zero_bss_loop

jump_to_zig:
    # 6. Call the Zig Kernel entry point
    call kmain

secondary_hart_park:
    # In S-Mode under OpenSBI, secondary HARTs are parked by default.
    # If any awake, put them to sleep.
    wfi
    j secondary_hart_park

.section .bss
.align 16
_boot_stack_bottom:
    .space 4096 * 4 # 16KB boot stack
_boot_stack_top:
