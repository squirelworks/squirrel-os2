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
resets its FPU, enables its local APIC, marks itself online, and parks in `sti` / `hlt`. Parked
APs wake only for interrupts sent to them, and nothing sends any yet: the scheduler still runs
everything on the BSP. Per-CPU run queues are the next box, 2.8-smp-sched.

`cpus` prints one line per CPU (`CPU 1: APIC id 1, online (parked)`, the BSP as
`boot processor`, or `did not start`) and `N CPU(s) online`. Regress: `cpus-one`, and under
`-smp 4` `smp-4` and `smp-4-systest`.

Memory: the trampoline (under 64 bytes) sits at `0x7000` after boot, clear of the boot sector at `0x7C00`; each AP stack is one page from the
allocator (so `mem` shows 4 KB less free per AP).
