# Long mode (2.8–2.9, 64-bit bridge)

The 64-bit bridge moves the kernel to x86-64 long mode in steps that each keep the BIOS boot path
and the whole regression suite working. The steps are boxes in `TODO.md` (section 2.8–2.9 core).

## 2.8-lm-entry: entering and leaving long mode (`kernel/lm.asm`)

The kernel can switch from 32-bit protected mode with paging into long mode, run a 64-bit routine
and come back:

- `lm_supported`: CPUID `0x80000001`, EDX bit 29.
- `lm_init` (once): 4-level tables from the page allocator. A PML4 and a PDPT, then four page
  directories of 2 MB pages that identity-map the first 4 GB (`LM_MAP_GB`), so every kernel
  address means the same in both modes.
- `lm_call(eax = 64-bit routine)`: with interrupts off, turns paging off (the kernel runs
  identity-mapped), sets CR4.PAE, loads CR3 with the PML4, sets EFER.LME, turns paging on (the CPU is
  now in IA-32e compatibility mode) and far-jumps to the 64-bit kernel code segment `0x40`
  (`gdt_cs64`: L = 1, D = 0). The routine is called on the same stack, aligned to 16 bytes. On its
  `ret` a `retfq` goes back to the 32-bit segment `0x08`, and the way out mirrors the way in: paging
  off, EFER.LME off, CR4 and CR3 restored, paging on. Registers and flags are kept.
- Interrupts stay off for the whole round trip: the IDT is still the 32-bit one. A 64-bit IDT
  comes with 2.9-lm-kernel.

`lmtest` runs a routine that reads EFER.LMA from inside, builds a 64-bit value with r8–r15 and
64-bit multiply/add/subtract, and measures a 64-bit push. It prints `lm: PASS`, or `lm: no long
mode` on a CPU without it (`qemu-system-i386`'s default CPU). Regress runs it under
`qemu-system-x86_64` (`QEMU_BIN` in `tools/qemu_screen.py`): checks `lm-test`, `lm-again`,
`lm-nolm`.
