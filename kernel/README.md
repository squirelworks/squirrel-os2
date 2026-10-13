# Squirrel-OS/2 Kernel Scaffold

Pure original bare-metal entry point for the Squirrel-OS/2 project.

## boot.asm

A 512-byte boot sector that:

- Takes control after the firmware
- Writes `UwU` directly to VGA text memory
- Beeps the PC speaker roughly every 15 seconds with light jitter

This is not derived from osFree, Voyager, or any other external OS/2 source. It is the first unique code under Squirrel-OS/2.

### Build & run

```bash
nasm -f bin boot.asm -o boot.bin
qemu-system-i386 -drive format=raw,file=boot.bin
```

Requires NASM and QEMU.

## Next

- Replace BIOS timer calls with a direct PIT interrupt handler
- Move to a proper protected-mode kernel
- Add more of the Warp-style personality while remaining original
