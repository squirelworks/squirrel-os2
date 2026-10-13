# Guides

## Building the current boot sector

Requirements: NASM, QEMU (or any emulator that accepts a raw boot image).

```bash
cd kernel
nasm -f bin boot.asm -o boot.bin
qemu-system-i386 -drive format=raw,file=boot.bin
```

## Adding documentation

- Place design notes in `architecture/`.
- Place implementation records in `kernel/`.
- Place how-to material in `guides/`.
- Record version milestones in `releases/`.

Keep entries dated and tied to actual code changes.
