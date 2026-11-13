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
| `notepad.asm` | SQX | Text editor in a window (`run notepad [file]`, A.1) |
| `grapher.asm` | SQX | 2D graphing calculator: explicit, polar, parametric and implicit functions, inequalities, sliders, zoom, pan, trace, roots, extrema, intersections (`run grapher [f]`, `run grapher test`, C.2) |
| `charmap.asm` | SQX | Character map of the system font; collects characters, F2 saves them (`run charmap`, A.2) |
| `paint.asm` | SQX | Bitmap painter: pen, line, box, solid box, fill, eraser, undo; 16 colours; saves and opens BMP (`run paint [f]`, `run paint test`, A.2) |
| `viewer.asm` | SQX | Image viewer for 8- and 24-bit BMP with zoom and scrolling, dithered to a 192-colour cube (`run viewer f [test]`, A.2) |
| `graph3d.asm` | SQX | 3D grapher: surfaces z = f(x, y) as coloured meshes drawn back to front, space curves x, y, z = f(t); turn, tilt, zoom, wireframe (`run graph3d [f]`, `run graph3d test`, C.7) |
| `stats.asm` | SQX | Statistics: two lists, one- and two-variable statistics, seven regression models, histogram, box plot, scatter plot, CSV files (`run stats [f]`, `run stats test`, C.3) |
| `topology.asm` | SQX | Topology calculator: face counts, Euler characteristic and Betti numbers over Z/2 and Q of simplicial complexes, 11 ready-made ones or typed (`run topology`, `run topology test`, C.9) |
| `matrixgui.asm` | SQX | Matrices A and B up to 4 x 4 in a grid: + - *, determinant, inverse, transpose, rank, solve A X = B (`run matrixgui`, `run matrixgui test`, C.9) |
| `mines.asm` | SQX | Minesweeper-class game, G.3 (`run mines [seed] [big]`, `run mines test`); see `documentation/apps/games.md` |
| `reversi.asm` | SQX | Reversi against a two-ply computer player, G.8 (`run reversi [seed]`, `run reversi test`) |
| `klondike.asm` | SQX | Klondike solitaire, draw one, G.1 (`run klondike [seed]`, `run klondike test`) |
| `freecell.asm` | SQX | FreeCell, G.2 (`run freecell [seed]`, `run freecell test`) |
| `hearts.asm` | SQX | Hearts against three computer players, G.4 (`run hearts [seed]`, `run hearts test`) |
| `chess.asm` | SQX | Chess against an alpha-beta engine, with SAN and PGN save, G.5 (`run chess [seed]`, `run chess test`) |
| `mahjongg.asm` | SQX | Mahjongg-style tile solitaire, always solvable deals, G.7 (`run mahjongg [seed]`, `run mahjongg test`) |
| `sqx.inc` | — | SQX header macro and syscall numbers |
| `bmp.inc` | — | BMP reader (8- and 24-bit) and 16-colour writer for programs |
| `gui.inc` | — | Graphics toolkit for programs over `SYS_GUI`: back buffer, pixels, lines, text, windows, buttons, keys, mouse (`../documentation/apps/gui-programs.md`) |
| `games.inc` | — | Shared runtime for the games: output, line input, seeded random numbers, self-test helpers |
| `cards.inc` | — | Playing cards for the card games: deck, printing, parsing |

Build and install:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img put hello
```
