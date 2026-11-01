# BIOS / firmware docs for Squirrel-OS/2

## In this OS tree (`squirelworks/squirrel-os2`)

| Doc | What it covers |
|-----|----------------|
| `documentation/kernel/boot-sector.md` | `boot.asm`: BIOS int 0x13 load, floppy/CHS fallback, CPU check, signature |
| `documentation/kernel/memory-map.md` | Real-mode / protected-mode layout after firmware hand-off |
| `documentation/architecture/firmware-independence.md` | Intent: own the machine after hand-off; BIOS only for initial load |
| `documentation/architecture/platforms.md` | Per-platform hand-off contracts |
| `documentation/architecture/multi-arch.md` | Arch layering |
| `documentation/guides/getting-started.md` | QEMU / Bochs / VirtualBox boot |
| `documentation/guides/install.md` | Installer on BIOS/IDE/ATA |

Those files are also copied under `../documentation/` in this pack.

## Separate repo: SquirrelBIOS

Firmware images are **not** in the OS tree. They live at:

- https://github.com/squirelworks/squirrelbios
- Local path referenced by the OS docs: `squirrelbios/` (sibling of this repo)

Key file there (not copied here — fetch from that repo):

- `squirrelbios/common/handoff.md` — hand-off contract
- `squirrelbios/x86/squirrel-bios.asm` — 64 KB ROM: banner, ATA PIO read of LBA 0 → `0x7C00`, jump

UEFI / AHCI / NVMe / USB are **H.\*** boxes in `TODO.md` (not before 2.0.0 prerequisites).
