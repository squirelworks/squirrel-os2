/* Squirrel-OS/2 — AArch64 early kernel
 * QEMU virt machine. PL011 UART at 0x09000000.
 * Original code.
 *
 * Build:
 *   aarch64-linux-gnu-as -o early.o early.S
 *   aarch64-linux-gnu-ld -Ttext=0x40080000 -o early.elf early.o
 *   aarch64-linux-gnu-objcopy -O binary early.elf early.bin
 * Run:
 *   qemu-system-aarch64 -M virt -cpu cortex-a57 -nographic -kernel early.bin
 */

.global _start
_start:
    ldr x1, =stack_top
    mov sp, x1

    ldr x2, =0x09000000      /* PL011 data register */
    adr x3, banner
1:
    ldrb w4, [x3], #1
    cbz w4, 2f
    str w4, [x2]
    b 1b
2:
    wfi
    b 2b

.align 4
banner:
    .asciz "Squirrel-OS/2 ARM early\n"

.align 12
stack_bottom:
    .skip 4096
stack_top:
