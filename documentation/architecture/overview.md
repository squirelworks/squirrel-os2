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

- Boot sector loads the 96 KB low kernel image (extended disk reads, CHS fallback for floppies); `stage2` loads the high image above 1 MB the same way (2.4, `kernel/kernel-image.md`).
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

## Language for new kernel subsystems (CONTINUANCE 3a)

**Decision (before 2.9-lm-kernel):** new kernel subsystems from 2.9 onward
may be written in freestanding C. NASM stays for boot, entry stubs, and all
existing assembly. This records
[squirrelsoft `docs/CONTINUANCE.md` decision 3a](https://github.com/squirelworks/squirrelsoft/blob/main/docs/CONTINUANCE.md#3a-write-new-kernel-code-in-freestanding-c).

**Recommendation / intended compile and link story**

- Compile C with `-ffreestanding -mno-red-zone -fno-pic` (and the usual
  freestanding companions the build will pin when C lands: no libc, no
  red-zone on x86-64, position-dependent code matching the flat kernel image).
- Link the resulting objects into the same flat kernel image the NASM build
  already produces; C entry points are called from NASM stubs (and the reverse
  as needed). No separate C runtime or ELF kernel image is implied yet.
- Keep rewriting existing NASM out of scope unless a subsystem is being
  replaced on purpose.

**Why**

- Single files such as `kernel/control.asm` are already past ~1,400 lines;
  freestanding C keeps new 64-bit work reviewable without growing those units.
- squirrelsoft cores (`sqmath`, `sqqr`, `sqdsp`, `sqfelica`, `sqgui`) and
  SquirrelBIOS `common/efi` drivers are already freestanding C and can be
  linked rather than re-implemented in NASM (suite decision 3b follows later).

**What this change does *not* do**

- No C sources land in this documentation PR.
- The build (`tools/build.sh`) is not switched; only the intended flags and
  flat-image link story are recorded so 2.9-lm-kernel can adopt them without
  re-opening the language question.

See also `HANDOFF.md` (2.9-lm-kernel) and `ROADMAP.md` (2.8–2.9).

## Next Architectural Targets

The forward plan is [`../../ROADMAP.md`](../../ROADMAP.md), with PR-sized tasks in [`../../TODO.md`](../../TODO.md):
preemption and threads (1.1), messages (1.2), graphics primitives and windows (1.3 to 1.6), and the object model (1.7 to 1.9).

Longer-range notes in this folder:

- Foreign-application personalities (post-2.0 scaffold — see `foreign-compatibility.md`)
- Firmware independence path (see `firmware-independence.md`)
- Multi-architecture and multi-platform scaffold (see `multi-arch.md`, `platforms.md`)
- Early kernels for x86, AArch64, and RISC-V (see `early-kernel.md`)
