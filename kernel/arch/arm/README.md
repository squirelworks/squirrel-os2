# AArch64 early kernel

Implemented in `early.S`.

QEMU virt, PL011 UART banner, WFI.

```bash
aarch64-linux-gnu-as -o early.o early.S
aarch64-linux-gnu-ld -Ttext=0x40080000 -o early.elf early.o
aarch64-linux-gnu-objcopy -O binary early.elf early.bin
qemu-system-aarch64 -M virt -cpu cortex-a57 -nographic -kernel early.bin
```
