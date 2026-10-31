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

## Paging and address spaces (0.6.1)

Location: `../../kernel/vm.asm`.

### Kernel mapping

`vm_init` runs right after `mm_init`. It takes two pages from the allocator and builds:

- **A page table for 0–4 MB** with 4 KB pages, mapping every page to itself.
- **The kernel page directory.** Entry 0 points at that table. Entries 1–63 are 4 MB pages (CR4.PSE) that identity-map 4–256 MB.
  Everything above 256 MB is left unmapped.

It then loads CR3 and sets CR0.PG. Because the mapping is the identity, the kernel keeps running at the same addresses, and every pointer in the system means the same thing before and after.

### Per-program address spaces

`as_create` builds one for each program the loader starts:

| Pages | Content |
|-------|---------|
| 1 | Page directory: a copy of the kernel's |
| 1 | Private copy of the 0–4 MB page table |
| 16 | The program area `0x30000–0x3FFFF`, fresh zeroed pages |

So a program sees the whole kernel at the usual addresses, but its own 64 KB at `0x30000`.
Two programs linked at the same address can be alive at once. `nest` starts `hello` and waits for it, then checks that its own code and data at `0x30000` were not overwritten.

The records live in `as_table` (one per process slot):

| Field | Meaning |
|-------|---------|
| `AS_PD` | Physical address of the page directory (what CR3 is set to) |
| `AS_REFS` | Processes using it; the last `as_release` frees every page |
| `AS_PAGES` | Pages owned, shown by `ps` as memory in KB |

Each PCB has a `PCB_AS` field (0 means the kernel's directory):

- `proc_switch` loads the next process's directory, and skips the reload when it is the same one.
- `proc_spawn` gives a child its parent's address space and adds a reference. So a thread spawned by a program runs in that program's memory.
- The loader then moves a freshly loaded program to its own address space.
- `proc_wait` releases a process's address space when it reaps it.

### Faults

The exception report now also prints CR2 for a page fault. If the faulting process has its own address space, the report ends with `Program ended: pid N`, the process exits with code −1, and the shell carries on (`run crash` reads `0xC0000000`).

A fault anywhere else (the shell, a built-in app, the kernel) still halts the system as before.

Everything still runs in ring 0, so a program can still write over kernel memory. Protection (user mode) remains a 2.x item.

## Program heap (0.6.2)

Each program's address space has a heap that starts empty at `HEAP_BASE` = `0x40000000` and can grow to 4 MB, which is one page table (directory entry 256).

`SYS_SBRK` (21) moves the end of the heap, the *break*:

| `ebx` | Effect | `eax` |
|-------|--------|-------|
| > 0 | Grows the heap by that many bytes | The old break, the start of the new memory |
| < 0 | Shrinks it | The old break |
| 0 | Nothing | The current break |
| any, when refused | Nothing changes | −1 |

The call is refused when:

- the break would leave `0x40000000–0x40400000`;
- memory runs out (pages mapped by this call are given back first);
- the caller has no address space of its own (the shell and built-in apps).

How it works:

- **Growing:** fresh zeroed pages are mapped for every page the heap newly covers. The heap's page table is made the first time it is needed.
- **Shrinking:** whole pages past the new break are unmapped (with `invlpg`) and freed at once. So touching them afterwards faults and ends the program (`run heap after`).
- **Exit:** when the process is reaped, `as_teardown` frees whatever heap is left, along with its table (`run heap keep`, then `mem`).
- **Memory count:** heap pages count in `AS_PAGES`, so `ps` includes them.

Stacks are not grown. A program keeps its process slot's 8 KB stack, and all code still runs in ring 0, where a fault while pushing on an unmapped stack page could not be reported. Growing stacks waits for user mode (2.x).
