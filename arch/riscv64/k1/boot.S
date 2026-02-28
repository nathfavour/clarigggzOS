# RISC-V K1 Early Boot Logic
# Clarigggz OS - Core Broker Entry Point

.section .text.boot
.global _start

_start:
    # 1. HART Initialization (Multi-core awareness)
    csrr t0, mhartid
    bnez t0, secondary_hart_park # Only HART 0 continues, others park

    # 2. Disable Interrupts initially
    csrci mstatus, 8

    # 3. Enable Vector Extension (RVV 1.0)
    # mstatus[VS] = 11 (Initial) or 01 (Initial)
    # We set it to 'Initial' (01) to allow RVV instructions
    li t1, 0x00000600 # VS bits in mstatus
    csrs mstatus, t1

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
    # Article I: The Power Budget
    # All non-primary cores must immediately WFI until woken by the Core Broker.
    wfi
    j secondary_hart_park

.section .bss
.align 16
_boot_stack_bottom:
    .space 4096 * 4 # 16KB boot stack
_boot_stack_top:
