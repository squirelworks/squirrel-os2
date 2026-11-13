# Multiprocessing (2.8)

## 2.8-smp-ap: starting the application processors (`kernel/smp.asm`)

At boot, once the timer runs and interrupts are on, `smp_init` on the bootstrap processor (BSP):

1. Finds the ACPI RSDP (`RSD PTR `, checksum over its first 20 bytes) in the first KB of the EBDA
   or in `0xE0000–0xFFFFF`, follows the RSDT to the MADT (`APIC`), and reads the local APIC
   address and every enabled processor local APIC entry (type 0) into `smp_cpus` (up to
   `SMP_MAX` = 16). Without a MADT, or with one CPU, it stops: nothing changes for a single CPU.
2. Identity-maps the local APIC registers in the kernel's page directory (`vm_map_range`, kernel
   pages only), turns its local APIC on (spurious vector `0xFF`) and reads its own APIC id.
3. Copies the real-mode trampoline `ap_tramp` to `0x7000` (`SMP_TRAMP`, STARTUP vector `0x07`).
4. For each other CPU: a 4 KB stack from the page allocator, then INIT, a 10–20 ms wait, and a
   STARTUP IPI. If the AP is not online within ten ticks, a second STARTUP, and ten ticks more.

An AP starts in real mode at `0700:0000`. The trampoline loads the kernel's GDT (it lies below
32 KB) and far-jumps into `ap_pm32` in the kernel. There the AP takes its stack from the record the
BSP is starting (`smp_ap_rec`), turns on PSE and the kernel's page directory and the shared IDT,
sets up its FPU, loads its own TSS, enables its local APIC and its timer, marks itself online, and
enters the AP scheduler `ap_idle` (below).

`cpus` prints one line per CPU (`CPU 1: APIC id 1, online`, the BSP as
`boot processor`, or `did not start`) and `N CPU(s) online`. Regress: `cpus-one`, and under
`-smp 4` `smp-4` and `smp-4-systest`.

Memory: the trampoline (under 64 bytes) sits at `0x7000` after boot, clear of the boot sector at `0x7C00`; each AP stack is one page from the
allocator (so `mem` shows 4 KB less free per AP).

## 2.8-smp-sched: ring-3 threads on every CPU

The kernel is not reentrant, so it still runs only on the BSP. The application processors run
ring-3 code:

- **Which threads.** A thread whose kernel stack holds nothing but the way back to ring 3: one the
  BSP's timer preempted in ring 3 (`proc_preempt` sets `PCB_UFRAME`, in the PCB extension
  `proc_ext`), or one an AP's own timer handed back. Threads with a TLS segment (P.5) stay on the
  BSP, because the TLS descriptor is shared. Slot 0 (the shell) and kernel processes never move.
- **Claiming.** States change with `lock cmpxchg`: an AP takes a thread `READY → P_APRUN`
  (`running (AP)` in `ps`), the BSP's `proc_switch` takes one `READY → RUNNING` and rescans when it
  loses the race. The BSP marks the thread it leaves `READY` only after it has moved to the next
  thread's stack, so an AP never resumes a stack that is still in use.
- **Running.** `ap_idle` loads the thread's page directory, sets its own TSS's ESP0 to the
  thread's kernel stack, restores its FPU state, and pops the frame `proc_switch` saved, which
  returns to ring 3. Each CPU has its own TSS (`gdt_tss_cpu`, selectors `0x48 + 8 * i`). An idle
  AP keeps the kernel's page directory, never a process's that may be freed.
- **Entering the kernel on an AP.** `syscall_isr` and `exc_report` first ask `smp_on_ap` (the task
  register is not `tss_main`). On an AP, `ap_divert` saves the registers and the FPU, records CR2
  for a page fault, and leaves the thread `READY` with the kernel entry as its continuation. A
  fixed IPI (`0x42`) wakes the BSP, whose scheduler runs it there: the system call or the fault
  report (`ap_exc_resume` puts CR2 back first) then goes on exactly as if it had happened on the
  BSP.
- **Time slices on APs.** Each AP's local APIC timer (vector `0x41`, periodic) hands its thread
  back as preempted when another thread is waiting (`ap_yield`), so it can run on any CPU.
- **Waiting.** When the BSP has nothing to run but threads are out on APs, it halts until an
  interrupt and looks again, instead of reporting a deadlock.

Test: `programs/smpspin.asm` (`run smpspin [n]`) starts four ring-3 threads that read their CPU's
APIC id with CPUID and make system calls as they spin, until `n` different CPUs have been seen.
Regress: `smpspin-1` (one CPU), and under `-smp 4` `smpspin-4` (`smpspin: 4 CPU(s)`) plus
`smp-ring3`, `smp-stackover`, `smp-thread`, `smp-msg`, `smp-fpu`, `smp-preempt`, `smp-heap` and
`smp-after`, which run the existing test programs with threads moving between CPUs.
