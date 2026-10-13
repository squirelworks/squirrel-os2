# Kernel Notes

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
