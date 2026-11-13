# Kernel debug interface: SYS_DEBUG (A.4)

Location: `../../kernel/debug.asm` (high image), hooks in `crash.asm`, `proc.asm`, `syscall.asm`.
Programs include `programs/debug.inc`. The debugger built on it is `../apps/debugger.md`.

A program (the tracer) traces another loaded program (the tracee): it starts it stopped before
its first instruction or attaches to a running one, reads and changes its registers and memory,
plants `INT3` breakpoints and single-steps it with the trap flag. Faults in a traced program stop
it instead of ending it.

## Who may trace whom

- Only a loaded program (a process with an address space of its own) is traced; the shell and
  kernel threads are not.
- The tracer must be another program: not the tracee, not a thread of the tracee's program
  (they share memory, and a breakpoint would hit the tracer too), and not the tracee's own tracer.
- One tracer per tracee. The pair is kept per process slot with both pids, so a slot that is
  reused by a new process is never traced by accident.
- When a tracer exits, its tracees are let go: a stopped one runs on, untraced. Breakpoint bytes
  the tracer left in memory stay there (the debugger removes its own before it quits).

## The call

`int 0x80` with `eax = SYS_DEBUG` (47), `ebx` = operation, `ecx` = pid (or file name), `edx` =
argument. Unknown operations and processes the caller does not trace return −1.

| # | Operation | `ecx`, `edx` | Returns |
|---|-----------|--------------|---------|
| 0 | `DBG_ATTACH` | pid | 0, or −1 |
| 1 | `DBG_DETACH` | pid | 0: untraced; resumed if stopped |
| 2 | `DBG_EXEC` | file name, argument or 0 | pid, stopped before its first instruction (reason `DBG_R_ENTRY`), or the loader's `LD_E*` (< 0) |
| 3 | `DBG_WAIT` | pid, 0 wait / 1 poll | the stop reason; `DBG_ENDED` (−2) once it ended; `DBG_RUNNING` (−3) when polling a running one |
| 4 | `DBG_STOP` | pid | 0: it stops (reason `DBG_R_STOP`) after its next instruction in ring 3 |
| 5 | `DBG_GETREGS` | pid, 52-byte block | 0, or −1 when it is not stopped |
| 6 | `DBG_SETREGS` | pid, 52-byte block | 0, or −1 when it is not stopped |
| 7 | `DBG_READ` | pid, `{address, buffer, length}` | bytes copied from it (at most 4096) |
| 8 | `DBG_WRITE` | pid, `{address, buffer, length}` | bytes copied into it |
| 9 | `DBG_CONT` | pid, 0 run / 1 one instruction | 0, or −1 when it is not stopped |
| 10 | `DBG_KILL` | pid | 0: it ends with exit code −1 instead of running on |

Stop reasons are the CPU exception number (1 after a single step, 3 after an `INT3`, 13, 14, …),
`DBG_R_ENTRY` (0x100) or `DBG_R_STOP` (0x101). After an `INT3` the saved EIP points after it; the
debugger puts the original byte back and sets EIP one lower.

Register block (`DR_*` in `debug.inc`): `eax ebx ecx edx esi edi ebp esp eip eflags` (dwords, in
that order), then the reason, the exception's error code and CR2 (read only). `DBG_SETREGS`
changes only the arithmetic flags and DF in EFLAGS (`0x0CD5`); IF, IOPL and the trap flag stay
the kernel's.

`DBG_READ`/`DBG_WRITE` translate through the tracee's page tables and touch only its present user
pages (program area, heap, ring-3 stack), so code can be patched (breakpoints) and kernel memory
can never be reached. The copy stops at the first page it may not touch; 0 means nothing there.

From ring 3 the pointer arguments are checked like every other call (`ring3.md`, kind
`UA_DEBUG`): the file name and argument strings, the register block, the transfer block and
the buffer it names.

## How a stop works

- Vector 3 (`INT3`) is an interrupt gate with DPL 3, so `INT3` in ring 3 is a breakpoint
  exception rather than a general-protection fault. In a program nobody traces it still ends the
  program with the usual report (`CPU exception 3 (breakpoint)`).
- Every exception goes to `exc_report` (`crash.asm`). For a traced process interrupted in ring 3 it
  calls `dbg_trap` first (after a ring-3 stack has been grown, which is not a stop): the process is
  parked in the new state `P_STOPPED` (5, `ps` shows `stopped`) with the exception frame left on its
  kernel stack, its tracer is woken if it waits in `DBG_WAIT`, and the CPU goes to someone else.
  `DBG_GETREGS`/`DBG_SETREGS` read and change that frame. `DBG_CONT` makes it READY; it returns to
  ring 3 through the frame, with the trap flag set for a single step. After a fault the faulting
  instruction runs again (change EIP or kill it).
- A program started by `DBG_EXEC` stops in `proc_enter_user` before its first instruction, on a
  frame of zeroed registers built the same way.
- `DBG_STOP` and `DBG_KILL` on a process that is not stopped set the trap flag in the ring-3 frame
  at the top of its kernel stack (where it will return to ring 3), so it stops (or ends) after one
  more instruction. A process that never ran is caught in `proc_enter_user`.
- Waiting uses `P_WAITING` with `PCB_WAITPID` = the tracee, so the existing wake in `proc_exit`
  also ends a wait when the tracee exits.

## Test

`programs/dbgtest.asm` (`run dbgtest`, regress `dbg-api`) traces `programs/dbgtgt.asm`: started
stopped, one step, an `INT3` breakpoint with the byte read, replaced and restored, registers changed
so the program exits with 7, a page fault that stops it (CR2 and error code checked) and `DBG_KILL`,
attach/stop/read/kill on a running program, reads of kernel memory and past the program area,
a kernel buffer refused, attaching to itself, the shell and nobody refused, and an `INT3` after
`DBG_DETACH` ending the program with a report. `dbg-api-after` checks the system afterwards.
