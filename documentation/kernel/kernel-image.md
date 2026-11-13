# Kernel image: low and high parts (2.4)

Up to 2.1 the whole kernel was one 96 KB image that the boot sector loaded to `0x8000–0x1FFFF`,
and it was nearly full. Since the 2.4 kernel work it has two parts, both assembled from
`kernel/pm.asm` in one NASM run, so every label is visible from both and calls between them
are ordinary 32-bit near calls.

| Part | Source | On the boot disk | Runs at | Size |
|------|--------|------------------|---------|------|
| Low image | `pm.asm` section `.text`: `stage2`, the GDT, the real-mode loader `khigh.asm`, the core (interrupts, processes, memory, paging, ATA, SQFS, shell, crash reports, mouse) | sectors 1–192 | `0x8000–0x1FFFF` | fixed 96 KB (`KERNEL_SIZE`), signature `S2OK` last |
| High image | `pm.asm` section `.high` (`vstart=KHIGH_BASE`): apps, editors, calculators, graphics apps, window manager, widgets, desktop, objects, loader, network stack | sector 193 (`KHIGH_LBA`) on, as many as it needs (`KHIGH_SECTS`) | `0x100000` (`KHIGH_BASE`) upward | whole sectors, signature `S2HI` last; at most `KHIGH_MAX` (1 MB, the reserved RAM) and `KHIGH_LIMIT` (it must end before the installer's partition at sector 2048: 949,248 bytes) |

**New kernel code goes in the high image**: add the `%include` between `khigh_start:` and the
`section .text` line near the end of `pm.asm`. The low image keeps code that must stay below
1 MB: anything that runs in real mode (`stage2`, `khigh.asm`) or that real mode addresses with a
16-bit offset (the GDT, `e820_count`). Its free space is left for core code that early boot
needs.

## Loading

1. The boot sector loads sectors 1–192 to `0x8000` as before and jumps to `stage2` with the boot
   drive in `DL`.
2. `stage2` saves `DL`, checks the CPU, turns A20 on and calls `load_high` (`khigh.asm`), still
   in real mode:
   - It reads the high image in chunks into `KSCRATCH` (`0x20000`): 64 sectors per extended
     read (int 0x13, AH=0x42) from a hard disk, one sector at a time by cylinder/head/sector
     (AH=0x02, geometry from AH=0x08, three tries with a reset) from a floppy or a CD in floppy
     emulation, or when an extended read fails.
   - Each chunk is copied to its place above 1 MB in "unreal" mode: protected mode is switched on
     just long enough to load DS and ES with the flat 4 GB data descriptor, then off again; the
     4 GB limits stay in the segment caches, so `a32 rep movsd` reaches `0x100000`.
   - The last dword of the last chunk must be `S2HI`. If a read fails or the signature is
     missing it prints `Squirrel-OS/2: cannot read the high kernel image from the boot disk`
     and halts (regress `khigh-missing` boots an image cut after sector 192).
3. `stage2` goes on as before (E820 map, GDT, protected mode). Paging identity-maps the first
   4 MB with the kernel page table that every address space copies, so the high image is mapped
   in every process.

## Memory

The page allocator (`mm.asm`) now starts at `MM_START = KHIGH_BASE + KHIGH_MAX` (2 MB): the
first megabyte above 1 MB belongs to the high image whatever its size, so it can also hold
uninitialised kernel data later. `mem` prints `Pages above 2 MB: ...`. The system needs at least
4 MB of RAM, as before.

## Installer

`install copy` copies sectors 1 to `INS_KSECTS = 192 + KHIGH_SECTS` of the boot disk (low and
high images) to the target, and `install boot` writes the same boot sector, so an installed
system loads the high image the same way. The partition still starts at sector 2048, which is
why `KHIGH_LIMIT` exists.
