# Kernel Notes

## boot.asm (current — 0.9.3)

- Loads 192 sectors (LBA 1–192, the 96 KB `pm.asm` image) to `0x8000` and jumps to `0000:8000`.
  Up to 1.7.2 it was 128 sectors (64 KB); `KERNEL_SIZE` in `pm.asm` grew when that was nearly full. The image ends at `0x1FFFF`,
  just below `KSCRATCH`.
- From a hard disk it uses the BIOS extended read (int 0x13, AH=0x42, disk address packet),
  in three reads of 64 sectors (`0x0000:0x8000`, `0x1000:0x0000` and `0x1800:0x0000`), since some
  firmware caps one read at 127 sectors. None of them crosses a 64 KB boundary. The firmware's
  boot drive (`dl`) is saved for the later reads.
- From a floppy (`dl` < 0x80), or when the extended read fails, it reads one sector at a time
  with AH=0x02. The geometry comes from AH=0x08, each LBA is converted to cylinder/head/sector,
  and every read gets up to three tries with a drive reset in between (0.9.3; before, a floppy
  boot hung).
- If the kernel cannot be read it prints `Squirrel-OS/2: cannot read the kernel from the boot disk`
  and halts.
- The kernel's real-mode entry clears DS/ES first (the floppy path leaves ES past the image,
  which broke the E820 memory map), then checks the CPU: without CPUID, an FPU or 4 MB pages
  (PSE) it prints `Squirrel-OS/2 needs a Pentium-class CPU (CPUID, FPU, 4 MB pages).` and halts.
- The kernel's last dword is the signature `S2OK`; at boot the kernel checks it and prints
  `Warning: kernel image only partly loaded` if it is missing.
- The GDT sits right after the real-mode entry code, inside the first 32 KB, because `lgdt` in
  real mode addresses it with a 16-bit offset.
- Earlier revisions: 0.2.1 loaded 64 sectors (32 KB) in one read; before that, CHS reads
  (AH=0x02) of 16, then 32 sectors.


## boot.asm (current — 0.0.2)

Location: `../../kernel/boot.asm`

### Behavior

- 16-bit real-mode boot sector
- Writes `UwU` to VGA text memory at `0xB8000`
- Native PIT channel 0 (~100 Hz) + IRQ0 handler
- Periodic PC-speaker beep (~15 s ± jitter) driven by the tick counter
- No firmware timer calls

### Ownership

Original Squirrel-OS/2 code.

### Planned Evolution

1. Protected-mode stub with own GDT/IDT.
2. Split into loader + kernel proper if size requires it.
3. Introduce a simple console and richer timer API.

See `../releases/` for version markers.
