# Architecture

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

## Current Stage (0.0.1)

- 16-bit real-mode boot sector
- Direct VGA text output
- Firmware timer used for delays (to be replaced)
- PC speaker driven directly

## Target Model (near term)

```
Firmware
  → Squirrel-OS/2 boot sector
    → native PIT setup + interrupt handler
      → protected-mode transition
        → minimal kernel loop
          → console + timer services
```

## Principles

- Document every hardware assumption.
- Keep release notes synchronized with code.
- Prefer small, testable steps over large rewrites.
- Maintain separation from the contemporary / third-party collections.

## Next Architectural Targets

- PIT-driven timer interrupt (see `pit-timer.md`)
- Protected-mode stub with its own GDT and IDT
- Simple linear framebuffer or continued VGA text console
- Basic memory map obtained without firmware calls where practical
