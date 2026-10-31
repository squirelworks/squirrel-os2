# Process Model (0.1.2; scheduler 1.1)

Location: `../../kernel/proc.asm` (included from `kernel/pm.asm`)

## Model

- Priorities 0–3, round-robin among equals (1.1). A process runs until it calls `yield`,
  `wait`, `exit` or `sleep`, blocks for input (`getc`, or an app waiting for a key), or, if
  it is a loaded program, its time slice runs out (see **Scheduling policy**).
- Up to `PROC_MAX` = 8 slots. Slot 0 is the kernel shell, **pid 0**, which runs on the
  boot stack (`0x9F000`) and never exits.
- Slots 1–7 each own an 8 KB stack: slot *i* has its top at `0x70000 + i * 0x2000`
  (`0x72000` … `0x7E000`).
- Pids increase from 1 and are not reused.

## PCB (64 bytes since 0.6.1; 32 before)

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | `pid` | Process id |
| 4 | `state` | `free` 0, `ready` 1, `running` 2, `waiting` 3, `zombie` 4, `sleeping` 5 (1.1) |
| 8 | `esp` | Saved stack pointer while not running |
| 12 | `entry` | Entry function |
| 16 | `arg` | Argument passed to `entry` |
| 20 | `code` | Exit code (valid when zombie) |
| 24 | `waitpid` | Pid this process is waiting on |
| 28 | `parent` | Pid of the creator |
| 32 | `as` | Address space record, 0 = the kernel's (0.6.1, `memory.md`); loaded into CR3 on every switch |
| 36 | `prio` | Priority 0–3, inherited from the parent; the shell is 1 (1.1) |
| 40 | `name` | 16 bytes: `shell`, the app or program name (0.8.2), shown by `ps` and in crash reports |
| 56 | `wake` | Tick to wake at while `sleeping` (1.1) |
| 60 | `fpu` | 1 once the process's FPU registers have been saved (1.1) |

## Lifecycle

1. **spawn(entry, arg)** takes a free slot, builds an initial stack
   (`popad` frame of zeros, `EFLAGS = 0x202`, return address `proc_trampoline`) and marks it `ready`.
2. The scheduler eventually switches to it; `proc_trampoline` calls `entry(arg)` (cdecl).
3. Returning from `entry`, or calling **exit(code)**, stores the code, marks the process
   `zombie`, wakes any process `waiting` on its pid, and switches away for good.
4. **wait(pid)** returns at once if the target is already a zombie; otherwise the caller
   becomes `waiting` and switches. When woken it reaps the zombie (slot becomes `free`)
   and returns the exit code. `wait` on an unknown pid or on itself returns -1.

## Context switch

`proc_switch` does `pushfd; cli; pushad`, wakes sleepers whose tick has come, and picks the
`ready` process with the highest priority, taking the first one after the current slot
among equals. It saves the outgoing FPU registers (`fnsave`) and restores the incoming
ones (`frstor`, or `fninit` the first time), saves `esp`, loads the next CR3 and `esp`,
then `popad; popfd; ret`.
If nothing else is ready and the caller is still `running` it returns with CF set
(nothing happened). If the caller cannot continue (waiting, sleeping, zombie) and nothing
is ready, it waits with `hlt` while some process sleeps; otherwise the kernel prints
`*** kernel panic: no runnable process` and halts.

## Scheduling policy (1.1)

- **Priorities.** 0 (background), 1 (normal, the default), up to 3. A new process gets its
  parent's priority. `SYS_SETPRIO` or the shell's `prio <pid> <n>` changes it.
- **Yielding and blocking** (`yield`, `getc`, `wait`, `sleep`, key waits) switch to the
  best `ready` process of *any* priority. The shell idles by yielding, so background
  programs run whenever the shell is waiting for a key.
- **Preemption.** The PIT runs at 100 Hz, and a slice is 5 ticks (50 ms). When a slice is
  used up, the next tick that interrupts a loaded program, or the next return from a
  syscall into one, calls `proc_preempt`. That switches only to a `ready` process of at
  least the same priority, so a busy program shares the CPU with its equals and gives way
  to higher priorities, but never to lower ones.
- **Only loaded programs are preempted** (code at `PROG_BASE`, `0x30000`–`0x3FFFF`). The
  kernel and the built-in apps share unlocked state (the console, file system buffers,
  the ATA driver), so they still switch only where they yield or block. That is the
  "falls back to cooperative" part. Making the kernel preemptible needs locks first.
- `sched` shows the mode, ticks and the number of preemptions. `sched coop` turns
  preemption off and `sched preempt` turns it back on.
- Strict priorities can starve: a busy priority-2 program keeps priority-1 work waiting
  until it blocks. Nothing ages priorities yet.

## Threads

A program's threads are processes that share its address space: `SYS_SPAWN` with an entry
inside the program starts one, and it inherits the address space (reference counted) and
the priority. `SYS_WAIT` joins it, and `SYS_EXIT` or returning ends it. Each thread has its
own 8 KB stack, FPU registers and priority. There are no locks yet. Threads that share
data must do so with single aligned writes, as `spin` does with its `stop` flag.

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

Added in 1.1:

| # | Name | Args | Returns |
|---|------|------|---------|
| 25 | `SYS_SLEEP` | `ebx` = ticks (10 ms each) | 0, after at least that long (0 just yields) |
| 26 | `SYS_SETPRIO` | `ebx` = pid (0: the caller), `ecx` = 0–3 | 0, or -1 for no such process or a priority above 3 |
| 27 | `SYS_TICKS` | — | ticks since boot (100 per second) |

## Shell integration

- `run <name>` looks the app up in `run_table`, spawns `app_host(start_routine)` and waits
  for it. `app_host` calls the app's start routine, then feeds raw scancodes to
  `kbd_dispatch` until the app clears its mode flag (Esc). Stub apps (`sci`, `graph`, …)
  print and exit immediately.
- `ps` lists live processes (from the shell you see pid 0; apps run while the shell waits),
  with a PRIO column since 1.1.
- `run spin` (1.1) checks preemption: two threads busy-loop without yielding and both make
  progress. `run spin prio` checks that a priority-0 thread waits while its parent is busy
  and runs while it sleeps, and `run spin sleep` checks `SYS_SLEEP`.
- `proctest` spawns three workers that print and yield three times each, then waits for
  each and prints the exit codes (10, 20, 30). Output interleaves
  `worker 1 step 1, worker 2 step 1, worker 3 step 1, worker 1 step 2, …`.
  This restores the behaviour of the 0.1.0 two-task demo on top of the new model.

## Limitations

- Only loaded programs are preempted (see above). A built-in app or kernel code that
  never yields still starves everyone.
- Everything runs in ring 0 with one address space; no per-process memory protection.
- Keyboard input goes to whichever process reads the ring first; with the shell waiting on
  a foreground app this is always the app.
- Zombies that nobody waits for keep their slot.
