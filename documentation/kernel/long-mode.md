# Long mode (2.8–2.9, 64-bit bridge)

The 64-bit bridge moves the kernel to x86-64 long mode in steps that each keep the BIOS boot path
and the whole regression suite working. The steps are boxes in `TODO.md` (section 2.8–2.9 core).

## 2.8-lm-entry: entering and leaving long mode (`kernel/lm.asm`)

The kernel can switch from 32-bit protected mode with paging into long mode, run a 64-bit routine
and come back:

- `lm_supported`: CPUID `0x80000001`, EDX bit 29.
- `lm_init`: resolves a 4-level root through `as_lm_cr3` (kernel or the current process; optional
  `lm_as_override` picks an address-space record). Everyday paging stays the PAE PDPT; the PML4
  is only loaded while in long mode.
- `lm_call(eax = 64-bit routine)`: with interrupts off, turns paging off (the kernel runs
  identity-mapped), keeps CR4.PAE (on since 2.8-pae), loads CR3 with that PML4, sets EFER.LME, turns
  paging on (the CPU is now in IA-32e compatibility mode) and far-jumps to the 64-bit kernel code
  segment `0x40` (`gdt_cs64`: L = 1, D = 0). The routine is called on the same stack, aligned to 16
  bytes. On its `ret` a `retfq` goes back to the 32-bit segment `0x08`, and the way out mirrors the
  way in: paging off, EFER.LME off, CR4 and CR3 restored (PAE stays on; EFER.NXE is left alone),
  paging on. Registers and flags are kept.

## 2.8-pae: PAE paging and NX

The 32-bit kernel's everyday paging is PAE (64-bit entries, a PDPT), the same entry format long mode
will keep. See `memory.md`. Checks: `nx-heap`, `nx-stack`, `cpu-pentium3`.
- Interrupts stay off for the whole round trip: the IDT is still the 32-bit one. A 64-bit IDT
  comes with 2.9-lm-kernel.

`lmtest` runs a routine that reads EFER.LMA from inside, builds a 64-bit value with r8–r15 and
64-bit multiply/add/subtract, and measures a 64-bit push. It prints `lm: PASS`, or `lm: no long
mode` on a CPU without it (`qemu-system-i386`'s default CPU). Regress runs it under
`qemu-system-x86_64` (`QEMU_BIN` in `tools/qemu_screen.py`): checks `lm-test`, `lm-again`,
`lm-nolm`.

## 2.9-lm-kernel (in progress): 64-bit IDT, then 4-level per-process paging

The full box keeps the kernel in long mode for good (4-level per-process spaces, compatibility
thunks for the remaining 32-bit kernel, 32-bit programs in compatibility mode). Landed so far:

### IDT / TSS (`lmstay`)

- `lm_idt_init`: a 256-entry 64-bit IDT (16-byte gates to `gdt_cs64`), a 64-bit TSS at selector
  `0xC8` (`gdt_tss64`) with IST1 on a dedicated page for vector 8, and interrupt gates for the
  timer (`lm64_timer_isr`) and a default EOI stub.
- `lm_call_stay` / `lmstay`: enter long mode like `lm_call`, load the 64-bit IDT and TSS, mask
  the PIC to IRQ0 only, enable interrupts until three timer IRQs have run through the 64-bit
  gate, restore the PIC masks, then leave long mode and restore the 32-bit IDT and
  `SEL_TSS_MAIN`. (Other IRQ lines are masked for the stay so a 64-bit stub cannot EOI them
  without draining the device.) Everyday paging stays the PAE PDPT; CR3 while staying is the
  4-level wrapper from `as_lm_cr3`.
- Checks: `lm-stay`, `lm-stay-again` (under `qemu-system-x86_64`), `lm-stay-nolm` (32-bit QEMU).

### 4-level per-process paging (`lmpage`)

- `as_lm_sync` / `as_lm_cr3` (`vm.asm`): each address space (and the kernel) gets a PML4 whose
  `PML4[0]` points at a long-mode PDPT that mirrors the PAE PDPT's present entries with `P|W`
  and the same page-directory pointers. PAE PDPTE.W stays clear (reserved in PAE). The wrapper
  is built on demand and refreshed before every long-mode entry so late PDPTEs (heap, MMIO) are
  visible. `AS_PML4` holds the root; teardown frees the PML4 and LM PDPT only.
- `lmpage`: two address spaces, different bytes at `0x30000`, enter long mode with each PML4;
  private bytes differ, a kernel mark matches. Checks: `lm-page`, `lm-page-again`, `lm-page-nolm`.

### Permanent stay + compatibility thunks (`lmthunk`)

- `lm_enter_perm` / `lm_leave_perm`: enter IA-32e like the stay path (PML4, 64-bit IDT/TSS,
  IRQ0-only PIC mask), then far-return to the 32-bit kernel segment `0x08` and **remain** with
  EFER.LMA set. Everyday 32-bit kernel code runs in compatibility mode on the 4-level tables.
  `lm_leave_perm` restores the PIC, clears LME, and puts the PAE CR3 and 32-bit IDT/TSS back
  (tests leave after the check; boot still starts in 32-bit protected mode).
- `lm_thunk64(eax = 64-bit routine)`: from compatibility mode, far-jump to `gdt_cs64`, call, and
  return to compat. `lm_thunk32(eax = 32-bit routine)`: from 64-bit code, far-return to `0x08`,
  call, and return to 64-bit.
- `lmthunk`: enter permanently, set a marker from plain 32-bit code, thunk to 64-bit (read LMA,
  thunk back to set a second marker, take three timer IRQs), leave, and print `lmthunk: PASS`.
  Checks: `lm-thunk`, `lm-thunk-again`, `lm-thunk-nolm`.

Still open for the full TODO box: boot (or a second build flavour) that stays in long mode for
the whole run so the suite passes under `qemu-system-x86_64` as everyday mode, and 32-bit
user programs in compatibility mode.
