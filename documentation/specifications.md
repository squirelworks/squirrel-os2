# Squirrel-OS/2 Specifications

Current capabilities and intentional limitations.  
Updated with each release.

## 0.0.2 — Capabilities

- Boots from a 512-byte sector after firmware hand-off
- Sets text video mode and writes `UwU` directly to VGA text memory (`0xB8000`)
- Owns periodic timing via PIT channel 0 (~100 Hz) and a native IRQ0 handler
- Drives the PC speaker for short beeps
- Produces a beep approximately every 15 seconds with light jitter
- Runs in 16-bit real mode

## 0.0.2 — Intentional Limitations

| Item | Description |
|------|-------------|
| Real mode only | No memory protection or protected-mode features yet |
| Boot-sector size | Entire image must fit in 512 bytes |
| Firmware video init | Uses `int 0x10` once to set mode 3; display writes are direct thereafter |
| Timing precision | Beep interval is approximate by design at this stage |
| Jitter | Simple free-running seed; not a high-quality random source |
| Tick width | 16-bit counter (wraps after ~10.9 min at 100 Hz) |
| Hardware dependency | Speaker and PIT behavior follow classic PC / emulator expectations |
| No input | Keyboard is not read |
| No storage | No file system or block device |
| No processes | Single control loop |

## 0.0.3 — Capabilities

- Boot sector loads a second stage
- Enters 32-bit protected mode with its own GDT
- Writes `UwU` from protected mode
- Produces a single beep
- Stack set in protected mode

## 0.0.3 — Intentional Limitations

| Item | Description |
|------|-------------|
| No IDT yet | Interrupts are not handled in protected mode |
| Single beep | Periodic timer from 0.0.2 not yet restored |
| Firmware disk load | Second stage is read via `int 0x13` |
| Firmware video init | Mode set still uses `int 0x10` |
| No input / storage / processes | Unchanged |

## Notes

- Items listed here are accepted characteristics of the current milestone.
- Defects that violate these specifications belong in `knownbugs.md`.
- Future milestones (see `plannedmilestones.md`) remove limitations by design.
