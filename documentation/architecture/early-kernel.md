# Early Kernel — Squirrel-OS/2

Minimal per-architecture entry that owns the machine after firmware hand-off.

| Architecture | File | Console | Behaviour |
|--------------|------|---------|-----------|
| x86 | `arch/x86/early.asm` | VGA text `0xB8000` | Protected mode, banner, halt |
| AArch64 | `arch/arm/early.S` | PL011 `0x09000000` | Banner, WFI |
| RISC-V | `arch/riscv/early.S` | UART `0x10000000` | Banner, WFI |

The existing full x86 kernel (`kernel/pm.asm`) remains the higher stage.  
These early kernels are the clean entry points for each architecture.

See `documentation/architecture/multi-arch.md` and `platforms.md`.
