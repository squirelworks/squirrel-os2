# Log Viewer (A.5)

`run logview` shows the kernel log; `run logview FILE` shows a text file. It is a program on the data disk (`programs/logview.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`).

The kernel log (`GUI_SYSINFO`, `../kernel/syscalls.md`) has a line for the boot, for each program that starts and ends (with its exit code), and for each crash (with the exception), each starting with the seconds since boot:

    [0.00] Squirrel-OS/2 started: 128896 KB of memory
    [1.75] started crash (pid 1)
    [1.75] crashed crash (pid 1): page fault
    [1.75] ended crash (pid 1), exit code -1

Lines with `crashed` or `error` in them are drawn in red. The row under the text says which lines are shown, of how many, the filter, and whether the viewer is following.

## Keys

| Key | |
|-----|-|
| Up, Down, PgUp, PgDn, Home, End | scroll |
| Left, Right | scroll sideways, 8 columns at a time |
| `/` | type a filter and press Enter: only the lines with that word in them stay (capitals or not), with the word marked. An empty filter shows every line again; Esc drops the one being typed |
| F5 | read the log or the file again |
| `F` | follow: read it again every second and stay at the end. On at first for the kernel log |
| Esc | quit |

## Checks

`run logview test` reads the kernel log (its first line is the boot line, and one says `started logview`), filters it on `started `, writes a file of its own (CR LF and LF endings, an empty line, no newline at the end) and checks its five lines and a filter in capitals that finds two, checks that scrolling stays within the lines, and that a missing file is reported. It prints `logview: PASS`. The regress run also shows a crash in the log (`logview-crash`), filters it (`logview-filter`) and shows a file (`logview-file`).
