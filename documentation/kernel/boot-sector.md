# Kernel Notes

## boot.asm (current — 0.5.1)

- Loads 128 sectors (LBA 1–128, the 64 KB `pm.asm` image) to `0x8000` with the BIOS
  extended read (int 0x13, AH=0x42, disk address packet), in two reads of 64 sectors
  (`0x0000:0x8000` and `0x1000:0x0000`), since some firmware caps one read at 127 sectors.
  The firmware's boot drive (`dl`) is saved for the second read.
- Jumps to `0000:8000`; halts if a read fails.
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
