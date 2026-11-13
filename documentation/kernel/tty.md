# Terminals for programs: SYS_TTY (A.3)

Location: `../../kernel/tty.asm` (high image), hooks in `pm.asm` (`putc`), `syscall.asm`
(`sys_getc`), `appsys.asm` (`GUI_KEY`) and `proc.asm` (spawn, exit). Used by the Terminal
(`../apps/terminal.md`).

A program that wants to show other programs in a window of its own opens a tty and starts programs
on it. A process on a tty:

- prints into the tty's 4 KB output ring instead of the screen: everything that goes through the
  kernel's `putc` while it is the current process (`SYS_PUTC`, `SYS_PUTS`, the `con` device, Linux
  `write(1)`, and its own crash report);
- reads the tty's 256-byte input ring with `SYS_GETC` (waiting while it is empty; byte 4, Ctrl+D,
  reads as −1, the end of the input) and with `GUI_KEY` (0 while it is empty);
- passes the tty on to every process it starts (threads and `SYS_EXEC` alike).

When the output ring is full, the writer waits for the terminal to take some (inside an exception
report, with interrupts off, the rest is dropped). When the terminal exits or closes the tty, the
programs on it print on the console again and a waiting `SYS_GETC` returns −1.

## The call

`int 0x80` with `eax = SYS_TTY` (38), `ebx` = operation `| tty << 8`, `ecx`, `edx` = arguments.
Only the process that opened a tty may use it; the shell and programs already on a tty cannot open
one. Anything else returns −1.

| # | Operation | `ecx`, `edx` | Returns |
|---|-----------|--------------|---------|
| 0 | `TTY_OPEN` | — | the tty (1–4), or −1 |
| 1 | `TTY_CLOSE` | — | 0 |
| 2 | `TTY_EXEC` | file name, argument or 0 | pid of the program, started on the tty (as `SYS_EXEC`: the caller is its parent), or `LD_E*` |
| 3 | `TTY_READ` | buffer, size | bytes of output taken (0 when there is none; never waits) |
| 4 | `TTY_WRITE` | bytes, count | bytes put into the input (fewer when it is full) |
| 5 | `TTY_POLL` | pid of a child, pointer to a dword | 0 still running; 1 ended: its exit code is stored and it is reaped; −1 no such child |

Pointer arguments from ring 3 are checked (`ring3.md`, kind `UA_TTY`). `TTY_POLL` lets a terminal
watch several programs without blocking in `SYS_WAIT`.

## Test

The `term-*` checks in `tools/regress.sh` (see `../apps/terminal.md`): output of `hello`, the input
of `wc` with Ctrl+D, two sessions at once, a crash report landing in the window, the debugger in a
window (its Esc arrives through `GUI_KEY`), and the system after quitting with a program running.
