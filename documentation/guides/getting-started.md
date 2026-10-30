# Guides

## Building and running

Requirements: NASM, QEMU (or any emulator that accepts a raw boot image).

```bash
cd kernel
nasm -f bin boot.asm -o boot.bin
nasm -f bin pm.asm -o pm.bin
cat boot.bin pm.bin > os.img
qemu-system-i386 -drive format=raw,file=os.img
```

## Regression run

`tools/regress.sh` builds the image and types scripted commands into headless QEMU,
checking the VGA text screen. Needs Python 3 as well. `tools/qemu_screen.py IMAGE KEYS...`
does a single session and prints the screen, which is handy when adding a check.

## Adding documentation

- Place design notes in `architecture/`.
- Place implementation records in `kernel/`.
- Place how-to material in `guides/`.
- Record version milestones in `releases/`.

Keep entries dated and tied to actual code changes.
