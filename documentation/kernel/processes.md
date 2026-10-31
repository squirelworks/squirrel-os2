# Process Model (0.1.2)

Location: `../../kernel/proc.asm` (included from `kernel/pm.asm`)

## Model

- Cooperative, round-robin. A process runs until it calls `yield`, `wait`, `exit`,
  or blocks for input (`getc`, or an app waiting for a key).
- Up to `PROC_MAX` = 8 slots. Slot 0 is the kernel shell, **pid 0**, which runs on the
  boot stack (`0x9F000`) and never exits.
- Slots 1–7 each own an 8 KB stack: slot *i* has its top at `0x70000 + i * 0x2000`
  (`0x72000` … `0x7E000`).
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

## Limitations

- No preemption (milestone 1.1 in [`../../ROADMAP.md`](../../ROADMAP.md)). A process that never yields starves everyone.
- Everything runs in ring 0. Since 0.6.1 each loaded program has its own address space for its 64 KB at `0x30000` (`memory.md`), but the kernel is mapped in every one and a program can still write over it.
- Keyboard input goes to whichever process reads the ring first; with the shell waiting on
  a foreground app this is always the app.
- Zombies that nobody waits for keep their slot (TODO.md task 1.0-zombie).
- The x87 FPU state is not saved on a switch (TODO.md task 1.0-fpu).
