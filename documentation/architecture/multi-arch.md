# Multi-Architecture Strategy — Squirrel-OS/2 & SquirrelBIOS

## Intent

Squirrel-OS/2 and its firmware (SquirrelBIOS) are structured so that architecture-specific code is isolated and the higher-level personality remains original and shared where practical. Support is scaffolded for multiple CPUs; implementation proceeds one architecture at a time, starting from the existing x86 PC path.

## Layers

| Layer | Responsibility | Architecture dependence |
|-------|----------------|-------------------------|
| **SquirrelBIOS** | Reset, early hardware init, memory map, hand-off | Fully platform + CPU specific |
| **Early kernel** | Mode switch, interrupt controller, timer, console, page tables | CPU specific |
| **Kernel core** | Scheduler, memory allocator, syscalls, file system | Mostly portable |
| **Personality** | Shell, editors, applications, future windowing | Portable (with thin arch hooks) |

## Supported architectures (scaffold)

| Architecture | Status | Notes |
|--------------|--------|-------|
| **x86 (i386 / x86_64)** | Active | Early kernel in `kernel/arch/x86/early.asm`. Full kernel remains `kernel/pm.asm`. |
| **AArch64 (ARM64)** | Early kernel implemented | `kernel/arch/arm/early.S` — QEMU virt, PL011 banner. |
| **RISC-V (RV64)** | Early kernel implemented | `kernel/arch/riscv/early.S` — QEMU virt, UART banner. |
| **Others** | Placeholder | Added only when a concrete target and maintainer exist. |

## Principles

- Each architecture has its own SquirrelBIOS image and early kernel entry.
- No external OS sources are imported.
- Firmware hands off; the OS owns the machine thereafter.
- Shared code lives in architecture-neutral directories once the interfaces stabilize.
- Document every hardware assumption per platform.

## Directory intent

```
squirrelbios/         ← own tree (also https://github.com/squirelworks/squirrelbios)
  x86/                ← 64 KB ROM with ATA hand-off
  arm/                ← AArch64 firmware
  riscv/              ← RISC-V firmware
  common/             ← hand-off contract

firmware/             ← stub pointer only

kernel/
  arch/
    x86/
    arm/
    riscv/
  common/             ← future portable kernel services
```

## Current priority

Finish native block device and stable hand-off on x86 PC, then implement the AArch64 QEMU `virt` path as the second concrete architecture.

See also: `platforms.md`, `firmware-independence.md`, `overview.md`.
