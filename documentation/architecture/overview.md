# Architecture

## Naming

Squirrel-OS/2 keeps its name.  
1.0.0 = usable minimal system.  
2.0.0 = first Warp-like release (preemption, windowing, object desktop).  
3.0.0 = 64-bit Warp-style system positioned alongside contemporary desktops.  
Early builds are not described as OS/2.

## Intent

Squirrel-OS/2 is an original operating-system project that assumes full control of the machine after firmware hand-off. It draws inspiration from the protected-mode, multitasking character of OS/2 Warp while remaining entirely self-contained.

## Design Goals

1. **Ownership after boot**  
   Once the boot sector or loader runs, Squirrel-OS/2 owns the CPU, memory map, interrupt table, and devices it chooses to drive.

2. **Incremental replacement of firmware services**  
   Early code may call firmware for convenience. Each milestone replaces those calls with native drivers.

3. **Clear layering**  
   - Boot / loader  
   - Kernel core (memory, interrupts, timer, console)  
   - Higher-level personality (future)

4. **Original code only**  
   No incorporation of external OS/2, osFree, or Voyager sources into this tree.

## Current Stage (0.9.3)

- Boot sector loads a 96 KB kernel (extended disk reads, CHS fallback for floppies).
- Stage 2 checks the CPU, reads the BIOS memory map, and enters 32-bit protected mode with its own GDT and IDT.
- Native drivers: PIT at 100 Hz, PS/2 keyboard, VGA text console, PC speaker, ATA PIO disks, behind a driver table.
- Page allocator and paging, with a separate address space for each loaded program.
- Cooperative processes, 25 system calls through `int 0x80`, crash reports.
- SQFS file system with directories on the data disk.
- Shell with pipes, redirection, history and batch files. Applications: `files`, `calc`, `sci`, `matrix`, `edit`, `vedit`, `draw`.
- SQX and ELF32 program loader. Localization (`en`, `la`, `tlh`).

The full list, with its intentional limits, is in `../specifications.md`. File-level layout: `../../kernel/README.md`.

## Boot Path

```
Firmware (BIOS)
  → boot sector (boot.asm)
    → stage 2: CPU check, E820 memory map, GDT, protected mode (pm.asm)
      → IDT, PIC, PIT, keyboard, paging, page allocator
        → driver table (con, kbd, hd0, hd1), SQFS mount
          → shell (process 0) → applications and loaded programs
```

## Principles

- Document every hardware assumption.
- Keep release notes synchronized with code.
- Prefer small, testable steps over large rewrites.
- Maintain separation from the contemporary / third-party collections.

## Next Architectural Targets

The forward plan is [`../../ROADMAP.md`](../../ROADMAP.md), with PR-sized tasks in [`../../TODO.md`](../../TODO.md):
preemption and threads (1.1), messages (1.2), graphics primitives and windows (1.3 to 1.6), and the object model (1.7 to 1.9).

Longer-range notes in this folder:

- Foreign-application personalities (post-2.0 scaffold — see `foreign-compatibility.md`)
- Firmware independence path (see `firmware-independence.md`)
- Multi-architecture and multi-platform scaffold (see `multi-arch.md`, `platforms.md`)
- Early kernels for x86, AArch64, and RISC-V (see `early-kernel.md`)
