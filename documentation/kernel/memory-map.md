# Physical Memory Map (as of 0.3.0)

| Range | Use |
|-------|-----|
| `0x00000–0x004FF` | Real-mode IVT / BIOS data (left alone) |
| `0x07C00–0x07DFF` | Boot sector |
| `0x08000–0x0FFFF` | Kernel image (`pm.asm`, 32 KB since 0.2.1, loaded by the boot sector) |
| `0x20000–0x2FFFF` | `KSCRATCH`: kernel scratch buffers (ATA identify/test buffers, later FS cache) |
| `0x30000–0x3FFFF` | Program area: the resident loaded program (0.3.0, `loader.md`) |
| `0x40000–0x4FFFF` | Loader staging buffer |
| `0x70000–0x7FFFF` | Process stacks, 8 KB per slot (slot *i* top = `0x70000 + i*0x2000`) |
| `0x9F000` and down | Boot / shell (pid 0) stack |
| `0xB8000–0xB8F9F` | VGA text buffer |

Scratch layout inside `KSCRATCH`:

| Offset | Size | Use |
|--------|------|-----|
| `0x000` | 512 | ATA IDENTIFY data |
| `0x200` | 512 | `blktest` output buffer |
| `0x400` | 512 | `blktest` input buffer |
| `0x600` | 512 | `systest` sector buffer |
| `0x800` | 512 | SQFS superblock |
| `0xA00` | 512 | SQFS sector buffer |
| `0x1000` | 2048 | SQFS directory cache |
| `0x1800` | 256 | `cat` buffer |
| `0x2000` | 2048 | `fstest` pattern buffers |
| `0x4000` | 16384 | Editor text buffer (`edit`/`vedit`) |
| `0x8000` | 1152 | `draw` canvas (64 × 18) |
| `0x9000` | 20480 | `draw` flood-fill stack |
| `0xE000` | 1170 | `draw` load/save buffer |
