# Physical Memory Map (as of 0.6.2)

Paging is on since 0.6.1, but the kernel's page directory maps the first 256 MB to itself, so
every address below is both virtual and physical. Only the program area differs per program.

| Range | Use |
|-------|-----|
| `0x00000–0x004FF` | Real-mode IVT / BIOS data (left alone) |
| `0x01000–0x012FF` | BIOS E820 memory map, copied by `stage2` (0.6.0) |
| `0x07C00–0x07DFF` | Boot sector |
| `0x08000–0x17FFF` | Kernel image (`pm.asm`, 64 KB since 0.5.1; 32 KB from 0.2.1), loaded by the boot sector |
| `0x20000–0x2FFFF` | `KSCRATCH`: kernel scratch buffers (ATA identify/test buffers, later FS cache) |
| `0x30000–0x3FFFF` | Program area. Each loaded program sees its own 16 pages here (0.6.1, `memory.md`) |
| `0x40000–0x4FFFF` | Loader staging buffer |
| `0x50000–0x57BFF` | `matrix` variables (27 × 304 bytes from `0x50000`) and temporaries (64 × 304 bytes from `0x53000`) |
| `0x58000–0x59FFF` | Page allocator bitmap (0.6.0, `memory.md`) |
| `0x60000–0x6FFFF` | Shell pipe/redirect buffers, 2 × 32 KB (0.5.0, `shell.md`) |
| `0x70000–0x7FFFF` | Process stacks, 8 KB per slot (slot *i* top = `0x70000 + i*0x2000`) |
| `0x9F000` and down | Boot / shell (pid 0) stack |
| `0xB8000–0xB8F9F` | VGA text buffer |
| `0x100000` and up | Pages handed out by the page allocator (usable RAM up to 256 MB), including page directories and tables |
| `0x10000000` and up | Not mapped: any access faults (0.6.1) |
| `0x40000000–0x403FFFFF` | A program's heap, mapped page by page as `SYS_SBRK` grows it (0.6.2, `memory.md`) |

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
| `0x2000` | 1300 | `fstest` pattern buffer |
| `0x2800` | 2048 | Shell history: 16 lines × 128 bytes (0.5.1) |
| `0x3000` | 4096 | Batch script text (0.5.2) |
| `0x4000` | 16384 | Editor text buffer (`edit`/`vedit`) |
| `0x8000` | 1152 | `draw` canvas (64 × 18) |
| `0x9000` | 20480 | `draw` flood-fill stack |
| `0xE000` | 1170 | `draw` load/save buffer |
| `0xF000` | 1300 | `fstest` read-back buffer (moved from `0x2800` in 0.8.0, where it overwrote the shell history) |
