# Programs

Original user programs for the program loader (0.4.0). They are separate files on the data disk,
not part of the kernel image. See `documentation/kernel/loader.md`.

| File | Format | What it does |
|------|--------|--------------|
| `hello.asm` | SQX | Greets and echoes its argument (`run hello world`) |
| `wc.asm` | SQX | Lines, words and bytes of a file (`run wc notes`), or of its input (`ls \| run wc`) |
| `elfhello.asm` | ELF32 | Hand-written ELF header; checks its bss is zeroed |
| `ls.asm` | SQX | Lists the disk with sizes; `run ls txt` filters by substring |
| `cat.asm` | SQX | Prints one or more files (`run cat a b`), or copies its input |
| `nest.asm` | SQX | Runs `hello` from inside itself, waits, then checks its own memory survived (0.6.1) |
| `crash.asm` | SQX | Reads unmapped memory: the fault ends only this program (0.6.1) |
| `heap.asm` | SQX | Grows its heap by 1 MB with `SYS_SBRK`, checks it, gives it back (`run heap`, `run heap after`, `run heap keep`) (0.6.2) |
| `fpu.asm` | SQX | Keeps a value on the FPU stack while a second copy of itself fills all eight registers, then checks it (`run fpu`, 1.0.1) |
| `seek.asm` | SQX | Writes `abcd`, seeks to the second byte and reads `bcd`; checks a seek past the end is refused (`run seek`, 1.0.2) |
| `errno.asm` | SQX | Opens its argument; on failure prints the reason from `SYS_FSERROR` (`run errno missing` → `errno: Not found`, 1.0.3) |
| `zombie.asm` | SQX | Starts 12 threads it never waits for, then one it does; spawning must keep working (`run zombie`, 1.0.4) |
| `stress.asm` | SQX | Stress test of processes, threads, messages, preemption, the FPU, the heap and exec; every part checks its result (`run stress`, `run stress ring`; used by `tools/soak.py`) |
| `waitcycle.asm` | SQX | Waits for the shell, and closes a cycle of waits with a thread; the wait that closes a cycle must return −1, not hang the kernel (`run waitcycle`, KB-16) |
| `stackover.asm` | SQX | Starts a thread that overflows its stack; the kernel must end only that thread, and the program's own memory and stack must be intact (`run stackover`, KB-17) |
| `devtest.asm` | SQX | Uses devices by name: writes through `con`, reads `hd1`, checks `hd0` refuses writes (0.7.x) |
| `udptest.asm` | SQX | Sends a UDP datagram to 127.0.0.1 and reads it back; a second process is refused that port (`run udptest`, 1.9.7) |
| `priotest.asm` | SQX | High-priority spin must keep a low-priority child from running until the priority drops (`run priotest`, 1.9.9) |
| `drvtest.asm` | SQX | Registers a null char device with `SYS_DEVREG`, writes and reads it (`run drvtest`, 1.9.12) |
| `guitest.asm` | SQX | Self-check of `SYS_GUI` and `gui.inc`: draws a window, reads pixels back from the screen, the clock and `GUI_EVAL` (`run guitest`, `run guitest hold`) |
| `calculator.asm` | SQX | Calculator in a window, standard and scientific keypads on the `sci` engine (`run calculator`, A.1) |
| `clock.asm` | SQX | Analogue clock with the time and date (`run clock`, `run clock test`, A.1) |
| `notepad.asm` | SQX | Text editor in a window, with syntax highlighting for .asm/.inc, .c/.h and .bas (`run notepad [file]`, `run notepad -test`, A.1, A.7) |
| `grapher.asm` | SQX | 2D graphing calculator: explicit, polar, parametric and implicit functions, inequalities, sliders, zoom, pan, trace, roots, extrema, intersections (`run grapher [f]`, `run grapher test`, C.2) |
| `charmap.asm` | SQX | Character map of the system font; collects characters, F2 saves them (`run charmap`, A.2) |
| `paint.asm` | SQX | Bitmap painter: pen, line, box, solid box, fill, eraser, undo; 16 colours; saves and opens BMP (`run paint [f]`, `run paint test`, A.2) |
| `viewer.asm` | SQX | Image viewer for 8- and 24-bit BMP with zoom and scrolling, dithered to a 192-colour cube (`run viewer f [test]`, A.2) |
| `hexedit.asm` | SQX | Hex editor: hex and text columns, overwrite, insert, delete, go to offset, save; files up to 128 KB (`run hexedit f`, `run hexedit test`, A.7) |
| `write.asm` | SQX | Write, a word processor: wrapping, bold/italic/underline, paragraph alignment, selection, SQWP or plain-text files (`run write f`, `run write test`, A.7) |
| `graph3d.asm` | SQX | 3D grapher: surfaces z = f(x, y) as coloured meshes drawn back to front, space curves x, y, z = f(t); turn, tilt, zoom, wireframe (`run graph3d [f]`, `run graph3d test`, C.7) |
| `stats.asm` | SQX | Statistics: two lists, one- and two-variable statistics, seven regression models, histogram, box plot, scatter plot, CSV files (`run stats [f]`, `run stats test`, C.3) |
| `topology.asm` | SQX | Topology calculator: face counts, Euler characteristic and Betti numbers over Z/2 and Q of simplicial complexes, 11 ready-made ones or typed (`run topology`, `run topology test`, C.9) |
| `matrixgui.asm` | SQX | Matrices A and B up to 4 x 4 in a grid: + - *, determinant, inverse, transpose, rank, solve A X = B (`run matrixgui`, `run matrixgui test`, C.9) |
| `sheet.asm` | SQX | Sheet, a spreadsheet: 26 x 99 cells, formulas with references and sum/avg/min/max/count, copy and fill, line/bar/scatter charts linked to the cells, CSV (`run sheet f.csv`, `run sheet test`, C.4) |
| `geometry.asm` | SQX | Geometry: free points, midpoints, segments, lines, perpendiculars, parallels, bisectors, circles, intersections, distance/angle/area, all following a dragged point; saved as commands (`run geometry f`, `run geometry test`, C.6) |
| `cas.asm` | SQX | CAS: exact fractions and roots, simplify, expand, factor, solve, diff, integrate, definite integrals, limits and Taylor series in a console (`run cas`, `run cas test`, C.5) |
| `sysmon.asm` | SQX | System Monitor: CPU use and its graph, memory, processes with their CPU share, CPU time, memory and priority (+/- changes it), from `GUI_SYSINFO` (`run sysmon`, `run sysmon test`, A.5) |
| `logview.asm` | SQX | Log Viewer: the kernel log or a text file, scrolling, a filter with the word marked, following the end (`run logview [file]`, `run logview test`, A.5) |
| `diskutil.asm` | SQX | Disk Utility: the disks, how full hd1 is, a sector map, the largest files, a file system check and a surface scan, read-only (`run diskutil`, `run diskutil test`, A.5) |
| `notebook.asm` | SQX | Notebook: cells of notes, Nut code, graphs, tables, geometry and math (sqmath) that share their variables, run from the top; an editor for each cell; saved as text with `%% kind` lines (`run notebook [file]`, `run notebook test`, C.8) |
| `nut.inc` | include | Nut, a small scripting language (numbers and strings, `if`/`while`/`for`, functions), with a host interface for programs (C.8) |
| `sqmath.inc` | include | sqmath, the expression engine v2: real and complex numbers, decimals to 150 places, SI units with `to` conversion, variables and user functions; the notebook's math cells (C.1) |
| `sysinfo.inc` | include | `GUI_SYSINFO` parts and layouts, as `kernel/sysinfo.asm` (A.5) |
| `lxhello.asm` | ELF32 (Linux) | Linux i386 program: `write` to fd 1 and 2, argc/argv from the Linux stack, `-ENOSYS`, `exit` (`run lxhello`, P.1) |
| `lxfile.asm` | ELF32 (Linux) | Linux `open`/`write`/`close`/`lseek`/`read`, `brk`, `mmap2`, `-errno` results (`run lxfile`, P.2) |
| `lxcat.asm` | ELF32 (Linux) | Copies Linux stdin to stdout with `read(0)` (`echo hi \| run lxcat`, P.2) |
| `lxsys.asm` | ELF32 (Linux) | More Linux calls: `writev`, `ioctl`, `uname`, `stat64`, `openat`, `rename`/`unlink`/`mkdir`, `set_thread_area` + GS (`run lxsys`, P.2) |
| `lxsig.asm` | ELF32 (Linux) | Linux signals: handlers with and without a restorer, `SA_SIGINFO`, masks and pending, `SIG_IGN`, `SA_RESETHAND`, then `SIGTERM` ends it (`run lxsig`, P.2) |
| `winrun.asm` | SQX | Win32 PE32 console loader and KERNEL32 shim; the kernel runs it for `MZ` files with a PE header, and it passes DOS `MZ` files on to `dosrun` (`run winrun prog.exe`, P.5) |
| `dosrun.asm` | SQX | DOS `.COM`/`.EXE` runner: an 8086/186 interpreter with the `INT 21h`/BIOS subset; the kernel runs it for `*.com` and DOS `MZ` files (`run prog.com`, P.8, `../documentation/architecture/dosrun.md`) |
| `doshello.asm` | DOS .COM | INT 21h output, the BIOS teletype, the command tail (`run doshello.com acorns`, P.8) |
| `doscpu.asm` | DOS .COM | 8086/186 instructions and flags, steps a–k (`run doscpu.com`, P.8) |
| `dosfile.asm` | DOS .COM | DOS files, memory blocks and buffered input (`run dosfile.com`, P.8) |
| `dosgfx.asm` | DOS .COM | VGA mode 13h: A000, INT 10h pixels and DAC, ports, teletype text in graphics (`run dosgfx.com`, then a key; P.8) |
| `dosexe.asm` | DOS .EXE | Hand-written MZ with relocations, three segments and a far call (`run dosexe.exe`, P.8) |
| `os2run.asm` | SQX | OS/2 32-bit LX loader with DOSCALLS shims; the kernel runs it for `MZ` files with an `LX` header (`run os2run prog.exe`, P.9) |
| `os2hello.asm` | LX | Hand-written OS/2 text-mode program: objects, fixups, DOSCALLS by ordinal, TIB/PIB, files, memory (`run os2hello`, P.9) |
| `winhello.asm` | PE32 | Hand-written Win32 console program: console, files, heap, relocations, imports (`run winhello`, P.5) |
| `wincrt.asm` | PE32 | Hand-written Win32 program on msvcrt: TEB via `fs:`, `__getmainargs`, printf/sprintf, malloc, FILE I/O, atexit/exit (`run wincrt acorn`, P.5) |
| `winshim.inc` | — | The KERNEL32 start-up calls and the msvcrt subset that `winrun` binds imports to |
| `bsdhello.asm` | ELF32 (FreeBSD) | FreeBSD i386 calls with stack arguments and CF + errno: files, lseek, break, mmap, isatty, errors (`run bsdhello`, P.10) |
| `lxelf.inc` | — | ELF header macro (Linux, or FreeBSD with `EI_OSABI` 9) and Linux call numbers for the test programs |
| `mines.asm` | SQX | Minesweeper-class game, G.3 (`run mines [seed] [big]`, `run mines test`); see `documentation/apps/games.md` |
| `reversi.asm` | SQX | Reversi against a two-ply computer player, G.8 (`run reversi [seed]`, `run reversi test`) |
| `klondike.asm` | SQX | Klondike solitaire, draw one, G.1 (`run klondike [seed]`, `run klondike test`) |
| `freecell.asm` | SQX | FreeCell, G.2 (`run freecell [seed]`, `run freecell test`) |
| `hearts.asm` | SQX | Hearts against three computer players, G.4 (`run hearts [seed]`, `run hearts test`) |
| `chess.asm` | SQX | Chess against an alpha-beta engine, with SAN and PGN save, G.5 (`run chess [seed]`, `run chess test`) |
| `mahjongg.asm` | SQX | Mahjongg-style tile solitaire, always solvable deals, G.7 (`run mahjongg [seed]`, `run mahjongg test`) |
| `bridge.asm` | SQX | Contract Bridge with computer bidding (natural, Stayman, Blackwood) and card play, G.6 (`run bridge [seed]`, `run bridge test`) |
| `checkers.asm` | SQX | Checkers (English draughts) against an alpha-beta engine, G.9 (`run checkers [seed]`, `run checkers test`) |
| `go.asm` | SQX | Go on a 9 x 9 board against the computer, area scoring, G.9 (`run go [seed]`, `run go test`) |
| `sqx.inc` | — | SQX header macro and syscall numbers |
| `bmp.inc` | — | BMP reader (8- and 24-bit) and 16-colour writer for programs |
| `gui.inc` | — | Graphics toolkit for programs over `SYS_GUI`: back buffer, pixels, lines, text, windows, buttons, keys, mouse (`../documentation/apps/gui-programs.md`) |
| `games.inc` | — | Shared runtime for the games: output, line input, seeded random numbers, self-test helpers |
| `cards.inc` | — | Playing cards for the card games: deck, printing, parsing |
| `gamegui.inc` | — | Drawing for the games' graphical front ends (`run <game> gui`): table, status bar, cards, suit signs, columns, discs, frames |

Build and install:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img put hello
```
