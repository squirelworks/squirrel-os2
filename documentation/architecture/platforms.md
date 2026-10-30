# Platforms — SquirrelBIOS & Squirrel-OS/2

## Intent

Hardware variety is handled by platform-specific SquirrelBIOS images. Each platform description records the CPU, firmware entry, devices that must be driven, and the hand-off contract to the OS.

## Platform list (scaffold)

### x86 PC (current)
- **CPU**: i386 (x86_64 planned)
- **Firmware**: 64 KB Squirrel ROM loaded by QEMU `-bios` (reset vector at offset 0xFFF0)
- **Early devices**: VGA text, PIT, PIC, keyboard, ATA or virtio-blk
- **Hand-off**: Boot sector at 0x7C00 or direct jump to stage-2
- **Status**: Active — early kernel in `kernel/arch/x86/early.asm`; full kernel in `kernel/pm.asm`

### QEMU AArch64 `virt`
- **CPU**: AArch64
- **Firmware**: Minimal EL2/EL1 image (device tree aware)
- **Early devices**: PL011 UART, GIC, generic timer, virtio-blk
- **Hand-off**: Jump to kernel entry with device tree pointer
- **Status**: Early kernel implemented (`kernel/arch/arm/early.S`)

### QEMU RISC-V `virt`
- **CPU**: RV64
- **Firmware**: Minimal M-mode image
- **Early devices**: UART, PLIC/AIA, CLINT, virtio-blk
- **Hand-off**: S-mode entry with device tree
- **Status**: Early kernel implemented (`kernel/arch/riscv/early.S`)

### Future platforms
Added only with a written platform note that lists:
- Reset / entry address
- Required early devices
- Memory map source
- Hand-off register or structure convention

## Hand-off contract (common)

Regardless of architecture, SquirrelBIOS provides:
1. A memory map (fixed or discovered).
2. A console device already usable or a known base address.
3. A jump or call into the OS entry point with architecture-defined arguments.
4. No further firmware calls required after the jump.

The OS then owns interrupts, timers, and storage.

## Status

x86 PC is the reference. Early kernels exist for AArch64 and RISC-V. Firmware images for the non-x86 platforms remain scaffold.
