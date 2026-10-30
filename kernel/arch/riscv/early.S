/* Squirrel-OS/2 — RISC-V early kernel
 * QEMU virt machine. UART at 0x10000000.
 * Original code.
 *
 * Build:
 *   riscv64-linux-gnu-as -o early.o early.S
 *   riscv64-linux-gnu-ld -Ttext=0x80000000 -o early.elf early.o
 *   riscv64-linux-gnu-objcopy -O binary early.elf early.bin
 * Run:
 *   qemu-system-riscv64 -M virt -nographic -bios none -kernel early.bin
 */

.global _start
_start:
    la sp, stack_top

    li t0, 0x10000000        /* UART data register */
    la t1, banner
1:
    lb t2, 0(t1)
    beqz t2, 2f
    sb t2, 0(t0)
    addi t1, t1, 1
    j 1b
2:
    wfi
    j 2b

.align 4
banner:
    .asciz "Squirrel-OS/2 RISC-V early\n"

.align 12
stack_bottom:
    .skip 4096
stack_top:
