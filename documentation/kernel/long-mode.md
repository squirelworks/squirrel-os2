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
  (tests leave after the check; refused when `lm_boot` is set).
- `lm_thunk64(eax = 64-bit routine)`: from compatibility mode, far-jump to `gdt_cs64`, call, and
  return to compat. `lm_thunk32(eax = 32-bit routine)`: from 64-bit code, far-return to `0x08`,
  call, and return to 64-bit.
- `lmthunk`: enter permanently, set a marker from plain 32-bit code, thunk to 64-bit (read LMA,
  thunk back to set a second marker, take three timer IRQs), leave, and print `lmthunk: PASS`.
  Checks: `lm-thunk`, `lm-thunk-again`, `lm-thunk-nolm`.

### Everyday / boot stay (`lmboot`, `LM_BOOT64`)

- The 64-bit IDT installs everyday gates for IRQ0 (timer), IRQ1 (keyboard), IRQ12 (mouse) and
  `int 0x80` (trap gate, DPL 3). Those stubs call the shared 32-bit ISR / syscall bodies through
  nestable `lm64_call32` (free-list frames, separate from `lm_thunk*` slots, so a timer IRQ
  during a thunk is safe; overflow EOIs both PICs and counts `lm_nest_overflow`). The nest
  frame pointer rides the process stack so a yield inside `syscall_isr_body` still returns
  through `lm64_call32_ret`. Native `int 0x80` result comes back in `eax` (not a global).
- Linux/BSD personalities under a permanent stay still return `-ENOSYS` (`-38`) from the
  64-bit gate: `lx_isr` uses `iretd` and is not stay-safe yet. Wire a returnable personality
  body in **`2.9-syscall64`** (after ring-3 under stay); see TODO.md and issue #221.
- `lm_enter_everyday`: `lm_enter_perm` then restores the saved PIC masks so keyboard and mouse
  keep working. `lm_boot_enter` does that and latches `lm_boot` so leave is refused.
- Build flavours: default `os.img` still boots in 32-bit protected mode; `os-lm64.img` is the
  same sources assembled with `-DLM_BOOT64` and calls `lm_boot_enter` after the PIC is programmed.
  `tools/build.sh` and `tools/regress.sh` build both. While staying, `lm_call` / `lm_call_stay`
  switch CR3 to the requested PML4 and use `lm_thunk64` instead of entering and leaving
  (saved CR3 and thunk globals nest on the stack).
- `lmboot`: on the default image, enter everyday, prove LMA + three timer ticks, leave; on the
  boot64 image, prove the same without leaving (LMA still set). Checks: `lm-boot`,
  `lm-boot-again`, `lm-boot64`, `lm-boot64-again`, and the `-nolm` pair under `qemu-system-i386`.
  `systest` and `lmtest` pass under the boot64 image on `qemu-system-x86_64`.

### Ring-3 under permanent stay (`lm64-hello` / `lm64-ring3`)

- While `lm_perm` is set, `vm_load` / the loader / `vm_reload_kernel` put the process (or
  kernel) **PML4** in CR3, not the PAE PDPT. Long-mode PDPTE and `PML4[0]` carry `PG_U` so
  ring-3 walks succeed; `as_pte` refreshes the LM wrapper when it creates a new PAE PDPTE
  (ring-3 stacks live in PDPT[1]).
- Vectors 0..31 (except `#DF` on IST1) use 64-bit stubs that call `exc_report` through
  `lm64_call32`. Stack growth resumes with `iretq` after restoring GPRs; other faults kill
  the process. `smp_on_ap` treats selector `0xC8` (`SEL_TSS64`) as the BSP.
- Checks: `lm64-hello`, `lm64-ring3` on `os-lm64.img` under `qemu-system-x86_64`.

### Everyday x86_64 suite flavour (`REGRESS_FLAVOUR=lm64`)

- `tools/regress.sh` accepts `REGRESS_FLAVOUR=i386|lm64` (default `i386`). The lm64
  flavour boots `os-lm64.img` under `qemu-system-x86_64` for the whole suite; the
  i386 flavour keeps `os.img` under `qemu-system-i386`. CI runs both.
- `vm_map_range` under permanent stay maps into the process PAE PDPT (never the
  PML4) and refreshes LM wrappers so VBE / desktop MMIO stays reachable.
- Everyday IRQ stubs (timer / keyboard / mouse) save the GPRs that `lm64_call32`
  clobbers, so a tick mid ring-3 loop (heap fill, etc.) cannot trash `edi`/`esi`.
- Foreign personality checks (Linux / Win32 / BSD / LX) skip on lm64 until
  `2.9-syscall64` (returnable `int 0x80` body). APs still park under stay but do
  not enter long mode / run ring-3 yet — multi-CPU `smpspin-4` / `smp-*` skip on
  lm64. Native SQX / DOS interpreter / desktop checks run on both flavours.

`2.9-lm-kernel` is ticked (mark **2.9.0**).
