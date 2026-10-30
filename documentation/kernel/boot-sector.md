# Kernel Notes

## boot.asm (current — 0.2.1)

- Loads 64 sectors (LBA 1–64, the 32 KB `pm.asm` image) to `0x8000` with the BIOS
  extended read (int 0x13, AH=0x42, disk address packet), keeping the firmware's boot drive in `dl`.
- Jumps to `0000:8000`; halts if the read fails.
- Earlier revisions used CHS reads (AH=0x02) of 16, then 32 sectors.


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
