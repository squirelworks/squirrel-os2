# RISC-V early kernel

Implemented in `early.S`.

QEMU virt, UART banner, WFI.

```bash
riscv64-linux-gnu-as -o early.o early.S
riscv64-linux-gnu-ld -Ttext=0x80000000 -o early.elf early.o
riscv64-linux-gnu-objcopy -O binary early.elf early.bin
qemu-system-riscv64 -M virt -nographic -bios none -kernel early.bin
```
