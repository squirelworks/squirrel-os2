# Process Model (0.1.2)

Location: `../../kernel/proc.asm` (included from `kernel/pm.asm`)

## Model

- Round-robin. A process runs until it calls `yield`, `wait`, `exit`,
  or blocks for input (`getc`, or an app waiting for a key), or until the timer
  preempts it (since 1.1, see "Preemption" below).
- Up to `PROC_MAX` = 8 slots. Slot 0 is the kernel shell, **pid 0**, which runs on the
  boot stack (`0x9F000`) and never exits.
- Slots 1–7 each own an 8 KB stack: slot *i* has its top at `0x7C000 + i * 0x3000`
  (`0x7F000` … `0x91000`). Under each stack is an unmapped guard page, and one more sits
  under the shell's stack, so a stack overflow is reported and ends only that process
  (KB-17, `crash-reports.md`).
- Pids increase from 1 and are not reused.

## PCB (64 bytes since 0.6.1; 32 before)

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | `pid` | Process id |
| 4 | `state` | `free` 0, `ready` 1, `running` 2, `waiting` 3, `zombie` 4 |
| 8 | `esp` | Saved stack pointer while not running |
| 12 | `entry` | Entry function |
| 16 | `arg` | Argument passed to `entry` |
| 20 | `code` | Exit code (valid when zombie) |
| 24 | `waitpid` | Pid this process is waiting on |
| 28 | `parent` | Pid of the creator |
| 32 | `as` | Address space record, 0 = the kernel's (0.6.1, `memory.md`); loaded into CR3 on every switch |
| 40 | `name` | 16 bytes: `shell`, the app or program name (0.8.2), shown by `ps` and in crash reports |
| 60 | `fpu` | 1 once its x87 registers have been saved (1.0.1); 0 means it starts with a reset FPU |

## Lifecycle

1. **spawn(entry, arg)** takes a free slot, builds an initial stack
   (`popad` frame of zeros, `EFLAGS = 0x202`, return address `proc_trampoline`) and marks it `ready`.
2. The scheduler eventually switches to it; `proc_trampoline` calls `entry(arg)` (cdecl).
3. Returning from `entry`, or calling **exit(code)**, stores the code, marks the process
   `zombie`, wakes any process `waiting` on its pid, and switches away for good.
4. **wait(pid)** returns at once if the target is already a zombie; otherwise the caller
   becomes `waiting` and switches. When woken it reaps the zombie (slot becomes `free`)
   and returns the exit code. `wait` on an unknown pid or on itself returns -1.
   So does a wait that would close a cycle: if the target is already waiting,
   directly or through others, for the caller, nobody could ever wake either
   of them (KB-16, `proc_wait_cycle`; check `waitcycle`).

## Context switch

`proc_switch` does `pushfd; cli; pushad`, saves `esp` in the current PCB, scans forward
for the next `ready` slot, loads its `esp`, then `popad; popfd; ret`.
If nothing else is ready and the caller is still `running` it returns with CF set
(nothing happened). If the caller cannot continue (waiting/zombie) and nothing is ready,
the kernel prints `*** kernel panic: no runnable process` and halts.

`proc_idle` = switch if possible, otherwise `sti; hlt`. The shell's idle loop, `yield`,
`getc` and app key waits all use it, so a waiting process never spins.

## Syscalls added

| # | Name | Args | Returns |
|---|------|------|---------|
| 4 | `SYS_SPAWN` | `ebx` = entry, `ecx` = arg | pid, or -1 if all slots are used |
| 5 | `SYS_EXIT` | `ebx` = exit code | does not return |
| 6 | `SYS_WAIT` | `ebx` = pid | exit code, or -1 |
| 7 | `SYS_GETPID` | — | pid of the caller |

`SYS_YIELD` (3) now switches to the next ready process.

## FPU state (1.0.1)

Each process has its own x87 registers. `proc_switch` calls `proc_fpu_swap`, which saves the
outgoing process's registers with `fnsave` into its slot's 108-byte area (`proc_fpu`) and
restores the incoming one's with `frstor`. A process whose state has never been saved
(`PCB_FPU` = 0, set at spawn) gets a freshly reset FPU (`fninit`) instead. The `fpu` program
checks this: it keeps a value on the FPU stack while a second copy of itself fills all
eight registers, then reads its own value back (`fpu: PASS`).

## Threads (1.1)

A thread is not a separate kind of object. **`SYS_SPAWN` with an entry inside the program's own image is the thread primitive:** `proc_spawn` gives the child the caller's address space and adds a reference (`memory.md`), so the new process runs the program's code on the program's data. It differs from the parent only in its slot: its own pid, its own 8 KB stack, its own FPU registers and its own exit code. The address space is freed when the last process using it is reaped.

The scheduler treats a thread like any other process: round-robin, `yield`, and timer preemption of program code (above). There is no priority field and no second scheduler.

Threads share memory without locks. A single instruction such as `inc dword [x]` cannot be split by a switch on this one-CPU system, but a read-modify-write over several instructions can. The `thread` program checks the primitive: it and a thread it spawns each add 1000 to one counter in the program's memory, yielding every 100 steps, and it prints `thread: PASS` when the counter ends at 2000 and the thread's exit code is 1000 (check `thread`).

## Zombies nobody waits for (1.0.4)

A zombie keeps its slot so that its parent can still collect the exit code, but two rules stop
zombies from filling the eight-slot table:

- **Orphans are freed.** A zombie whose parent has exited (no live, non-zombie slot carries the
  parent's pid; pids are never reused) can never be waited for. `proc_reap_orphans` frees all
  of them; `spawn` and `ps` call it first.
- **The table never fills with zombies.** When `spawn` finds no free slot, `proc_reclaim_zombie`
  frees the zombie with the lowest pid and `spawn` tries again. A later `wait` for that pid
  returns −1.

Freeing a zombie releases its address space (`proc_free`). The `zombie` program checks both:
it starts twelve threads that exit without being waited for, then one more that it does wait
for (`zombie: PASS`), and afterwards `ps` shows only the shell.

## Shell integration

- `run <name>` looks the app up in `run_table`, spawns `app_host(start_routine)` and waits
  for it. `app_host` calls the app's start routine, then feeds raw scancodes to
  `kbd_dispatch` until the app clears its mode flag (Esc). Scaffold apps (`graph`, `diff`,
  `topo`) print a message and exit immediately.
- `ps` lists live processes (from the shell you see pid 0; apps run while the shell waits).
- `proctest` spawns three workers that print and yield three times each, then waits for
  each and prints the exit codes (10, 20, 30). Output interleaves
  `worker 1 step 1, worker 2 step 1, worker 3 step 1, worker 1 step 2, …`.
  This restores the behaviour of the 0.1.0 two-task demo on top of the new model.

## Preemption (1.1)

The tick path, all in `timer_isr` (`kernel/pm.asm`) and `proc_preempt` (`kernel/proc.asm`):

1. The PIT fires IRQ 0 at 100 Hz. `timer_isr` counts the tick and sends the EOI first.
2. It decrements `sched_left`, the ticks left in the current slice. While the slice lasts, it returns.
3. When the slice has run out, it looks at the interrupted EIP. Only if that EIP is inside the program area (`PROG_BASE` to `PROG_BASE + PROG_MAX`, `0x30000`–`0x3FFFF`) does it call `proc_preempt`. Otherwise it returns and tries again on the next tick.
4. `proc_preempt` refills the slice, counts the switch in `sched_preempts`, and jumps to `proc_switch`, the same switch `yield` uses. The FPU registers and the address space follow as for any switch.
5. When the preempted process is picked again, `proc_switch` returns into `timer_isr`, which pops its register and returns with `iretd` to where the program was.

Every switch, cooperative or preempted, gives the incoming process a full slice: `SLICE_TICKS` = 5 ticks, 50 ms.

The kernel is not reentrant: kernel code, including system calls a program makes, the shell and the built-in apps, is never preempted. Those still switch only at `yield`, `wait`, `exit` and blocking input, so `proctest` prints exactly what it did before. A program that spins in its own code without a system call no longer starves the others. `run spin` shows it: it spins until a second process it spawned has printed, and prints `preempt: PASS` (check `sched-preempt`).

## Limitations

- Kernel code is not preempted (see "Preemption" above). A built-in app or a long system call that never yields still holds the CPU.
- Everything runs in ring 0. Since 0.6.1 each loaded program has its own address space for its 64 KB at `0x30000` (`memory.md`), but the kernel is mapped in every one and a program can still write over it.
- Keyboard input goes to whichever process reads the ring first; with the shell waiting on
  a foreground app this is always the app.
- A wait for a zombie that was reclaimed (see above) returns −1 instead of its exit code.
