# RISC-V K1 System Trap Handler
# Clarigggz OS - Core Broker

.section .text
.global trap_entry
.align 4 # RISC-V requires 4-byte alignment for stvec

trap_entry:
    # 1. Save all general purpose registers
    # (Simplified for now, in production we'd save to the thread's context)
    addi sp, sp, -256
    sd ra, 0(sp)
    sd t0, 8(sp)
    sd t1, 16(sp)
    sd t2, 24(sp)
    sd a0, 32(sp)
    sd a1, 40(sp)
    sd a2, 48(sp)
    sd a3, 56(sp)
    sd a4, 64(sp)
    sd a5, 72(sp)
    sd a6, 80(sp)
    sd a7, 88(sp)
    # ... more regs ...

    # 2. Call the Zig trap dispatcher
    # a0: scause, a1: sepc, a2: stval
    csrr a0, scause
    csrr a1, sepc
    csrr a2, stval
    call k_trap_handler

    # 3. Restore all registers
    ld ra, 0(sp)
    ld t0, 8(sp)
    ld t1, 16(sp)
    ld t2, 24(sp)
    ld a0, 32(sp)
    ld a1, 40(sp)
    ld a2, 48(sp)
    ld a3, 56(sp)
    ld a4, 64(sp)
    ld a5, 72(sp)
    ld a6, 80(sp)
    ld a7, 88(sp)
    addi sp, sp, 256

    # 4. Return from trap (sret)
    sret
