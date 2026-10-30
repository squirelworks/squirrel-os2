# Memory Management (0.6.x)

Location: `../../kernel/mm.asm`. The address map is in `memory-map.md`.

## Physical page allocator (0.6.0)

### Finding RAM

Before switching to protected mode, `stage2` (in `pm.asm`):

1. Turns on the A20 line through the fast A20 gate (port `0x92`), so addresses above 1 MB do not wrap.
2. Reads the BIOS memory map with `int 0x15, EAX=0xE820`, up to 32 entries of 24 bytes, into `0x1000`.
   The count is kept in `e820_count`, which sits below 32 KB so real mode can reach it.

`mm_init` then frees every whole 4 KB page of *usable* (type 1) RAM between 1 MB and 256 MB.
Everything below 1 MB keeps its fixed layout (kernel, scratch, program area, buffers, stacks).
Without a map, 1–32 MB is assumed and `mem` says so.

### Data structures

- **Free list**: each free page's first dword holds the address of the next free page, and `mm_head` is the first one.
  Allocating pops the head and freeing pushes, so both are O(1).
- **Bitmap** at `0x58000` (8 KB, 1 bit per page below 256 MB): set means in use or not RAM.
  It lets `pg_free` refuse addresses that are misaligned, outside managed RAM, or already free.
- Counters: `mm_total`, `mm_free`, `mm_top` (end of the highest managed page).

### Interface

| Routine / syscall | In | Out |
|-------------------|----|-----|
| `pg_alloc`, `SYS_PALLOC` (19) | — | a zeroed 4 KB page, or 0 when none is left |
| `pg_free`, `SYS_PFREE` (20) | `eax` / `ebx` = page | 0, or −1 if it is not an allocated page |

Both run with interrupts off, so a timer or keyboard interrupt never sees a half-updated list.

### Shell

- `mem` prints the BIOS map and the page totals (`Pages above 1 MB: 129920 KB total, 129920 KB free` with QEMU's default 128 MB).
- `memtest` allocates every page and checks that each comes back zeroed and distinct. It then frees them all, checks the free count is restored, and checks that a double free and a misaligned free are refused.

The bump allocator from 0.0.6 (`kmalloc`) no longer exists in the current kernel. The page allocator replaces it.
