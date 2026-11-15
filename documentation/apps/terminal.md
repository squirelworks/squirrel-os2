# Terminal (A.3)

`programs/terminal.asm`: several shells in windows, on `SYS_GUI` (the 2.2 windows when they land)
and the kernel's terminals (`../kernel/tty.md`).

```
run terminal
```

Up to four sessions, each a window with a shell of its own. The programs started in a session print
into its window and read the keys typed there, so several line-oriented programs (the games, the
debugger, `wc`, `cat`, …) run side by side.

| Key | What it does |
|-----|--------------|
| F1–F4 | Switch to session 1–4, opening it the first time |
| F5 | One window (the focused session) or all sessions stacked |
| F10 | Quit: programs still running are ended |
| Ctrl+C | End the program running in the session |
| Ctrl+D | End its input (`SYS_GETC` returns −1) |

In a session (prompt `N>`):

| Command | What it does |
|---------|--------------|
| `<program> [argument]` | Runs a program from the disk (`run <program>` works too); the prompt comes back when it ends, with `[exit code N]` when that is not 0 |
| `help` | The commands and keys |
| `clear` | Clears the window |
| `echo <text>` | Prints the text |
| `exit` | Closes the session; closing the last one quits |

The session shell is the terminal's own: the kernel shell's built-in commands (`ls`, `ps`, `cd`,
…) belong to the console. Programs that switch to graphics themselves (`SYS_GUI`) are not meant to
run in a terminal. Ctrl+C ends a program through `SYS_DEBUG` (the terminal attaches to it and
kills it), so it works for any program the terminal started.

Each session keeps 23 rows of 52 columns; a stacked window shows the rows above its cursor that fit.

Tests: `term-*` in `tools/regress.sh` (`dev.img`).
