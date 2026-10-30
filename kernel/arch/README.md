# Architecture-specific kernel code

```
kernel/arch/
  x86/     ← current protected-mode path (boot.asm / pm.asm still at kernel/ root for now)
  arm/     ← scaffold
  riscv/   ← scaffold
```

Portable services will move to `kernel/common/` once interfaces stabilize.  
See `../../documentation/architecture/multi-arch.md`.
