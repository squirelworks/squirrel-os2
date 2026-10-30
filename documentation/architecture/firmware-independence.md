# Firmware Independence — Squirrel-OS/2

## Intent

Squirrel-OS/2 assumes the machine after firmware hand-off and progressively removes dependence on firmware services. The long-term goal is that a user can run the system on open firmware (Coreboot + payload) or on a machine whose proprietary BIOS is used only for the initial load. Writing a complete modern BIOS from scratch is outside the project scope; owning the machine after hand-off is inside it.

## Current hand-off

- Firmware (BIOS or UEFI) loads the 512-byte boot sector at `0x7C00`.
- Boot sector uses INT 0x13 to load the second stage.
- Second stage enters protected mode, installs its own GDT and IDT, programs the PIC and PIT, and drives VGA text and the keyboard directly.
- After that point the only remaining firmware call is the initial disk load.

## Incremental replacement plan

1. **Native block device** (0.2.0)  
   Replace INT 0x13 with an ATA PIO or virtio-blk driver. After this, the boot sector can still be loaded by firmware, but the second stage never calls the BIOS again.

2. **Memory map without firmware**  
   Prefer e820-style information obtained by the boot sector before the hand-off, or a simple fixed map for QEMU/real-mode targets. Document the assumption.

3. **Coreboot payload scaffold**  
   A thin payload that Coreboot can launch. It receives the Coreboot memory map and jumps to the existing stage-2 entry point. This gives people who want open firmware a path without requiring a full custom BIOS.

4. **Optional minimal firmware target**  
   For QEMU `pc` or a single known board, a small 16-bit firmware image that does the absolute minimum (DRAM is already up under QEMU, basic PCI, then load the OS image). This is a research/scaffold item, not a 1.0 requirement.

## What we will not do in the near term

- Re-implement a full POST, ACPI tables, or multi-device boot menu.
- Target Secure Boot or UEFI runtime services.
- Claim binary compatibility with existing BIOS option ROMs.

## Ownership after hand-off

Once stage-2 runs:

- CPU mode and interrupt table are ours.
- Timer (PIT) is programmed by us.
- Video memory is written directly.
- Keyboard is handled by our IRQ1 path.
- Storage will be handled by our block driver.

Firmware is used only to get the first instructions executing. After that, Squirrel-OS/2 is the owner of the machine.

## VM ROM

SquirrelBIOS lives in its own tree: `../../squirrelbios/`  
(also at https://github.com/squirelworks/squirrelbios).

The x86 image (`squirrelbios/x86/squirrel-bios.asm`) is a 64 KB ROM that prints a banner, performs an ATA PIO read of LBA 0 into `0x7C00`, and jumps there. AArch64 and RISC-V images print on their UARTs and halt. The hand-off contract is in `squirrelbios/common/handoff.md`.

## Multi-architecture expansion

Support for additional CPUs and platforms is described in:
- `multi-arch.md` — layering and architecture list
- `platforms.md` — per-platform hand-off contracts
- `../../squirrelbios/` — firmware images
- `kernel/arch/{x86,arm,riscv}/` — early kernels

x86 PC remains the reference.

## Status

Scaffold. Next implementation step is a native disk driver so the second stage no longer needs INT 0x13. Coreboot payload notes can follow once the block device is stable.

See also: `architecture/overview.md`, `plannedmilestones.md` (0.2.x storage).
