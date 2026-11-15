# Debugger (A.4)

`programs/debugger.asm`, with the disassembler `programs/disasm.inc`. It runs on the kernel debug
interface (`../kernel/debug.md`) and works on the text console, line by line.

```
run debugger <program> [argument]    start it, stopped before its first instruction
run debugger <pid>                   attach to a running program (and stop it)
run debugger                         start empty; then run or attach
```

| Command | What it does |
|---------|--------------|
| `r` | Registers and flags |
| `s [n]` | One instruction (or n) |
| `n` | Next: a `call` is run to its return, anything else is one step |
| `c` | Continue to a breakpoint, a fault or the end; **Esc** stops it |
| `g` | Continue, leaving the keyboard to the program (for programs that read keys) |
| `b <where>`, `bl`, `bd <n>` | Set, list and delete breakpoints (16) |
| `u [where] [n]` | Disassemble n instructions (8) from where (the current one) |
| `x [where] [n]` | Memory in hex and characters, n bytes (64, at most 256), from where (`esp`) |
| `set <reg> <value>` | Change `eax`…`edi`, `ebp`, `esp`, `eip` or `efl` |
| `bt` | Return addresses up the `ebp` chain |
| `sym [text]` | Symbols, or those starting with text |
| `ps` | The process table (needs `GUI_SYSINFO`, A.5) |
| `run <program> [arg]`, `attach <pid>` | Start or attach when nothing is being debugged |
| `detach`, `kill` | Let it run on untraced / end it |
| `q` | Quit: a program the debugger started is ended, an attached one let go |

`<where>` is a hex address (`3001c` or `0x3001c`), a symbol, or symbol+hex (`main+c`). Numbers
for `s`, `u`, `x` and `bd` are decimal; values for `set` are hex or symbols.

Whenever the program stops the debugger says why (`hit breakpoint 1`, `stopped by CPU exception
14 at address 00000010`, `stopped at its entry`, `ended (exit code 7)`) and shows the instruction
at EIP:

```
pid 2 hit breakpoint 1
here:
0003001C  89C1              mov ecx,eax
```

## Breakpoints

Breakpoints are `INT3` bytes written into the program only while it runs: they are planted on
`c`/`g`/`n` and taken out at every stop, so `u` and `x` always show the real code. Leaving a
breakpoint at EIP takes one single step first. `n` uses a sixteenth, temporary breakpoint after
the `call`.

## Symbols

- `<program>.sym`, next to the program: `XXXXXXXX name` lines. `tools/mksym.py` makes one from the
  map NASM writes with `--before '[map symbols prog.map]'` (local labels included, like
  `here.spin`).
- Otherwise, for an ELF program, its `.symtab` (functions, objects and plain labels that are
  defined), read from the file's section headers.

Branch targets, `bt` and `r` show `<symbol+offset>`; `u` prints a `name:` line where a symbol
starts.

## The disassembler

`disasm.inc` is original, table-driven and needs nothing from the system (it also builds into a
host test harness). It decodes the whole one-byte opcode map, the common `0F` two-byte opcodes
(Jcc near, SETcc, CMOVcc, MOVZX/MOVSX, IMUL, BT*, BSF/BSR, SHLD/SHRD, XADD, CMPXCHG, BSWAP, CPUID,
RDTSC, multi-byte NOP, …), the x87 escapes, and the 66/segment/LOCK/REP prefixes, in NASM-style
Intel syntax. Anything else (MMX/SSE, the 67 prefix) is shown as `db 0x..`, one byte.

It was checked against `ndisasm` on a hand-written list and on 3000 random instructions (same
lengths everywhere both decode; differences only in spelling, such as `pushad` for `pusha`).

## Tests

`tools/regress.sh` builds the debugger, `dbgtest`, `dbgtgt` (with `dbgtgt.sym`), `distest` and
the ELF `dbgelf` onto `dev.img`. Checks `dbg-*`: the kernel interface, the disassembler against 70
expected lines (`distest`), entry stop and symbols, breakpoints, step and registers, `set` changing
the exit code, `n` over a call, `bt` through two frames, memory dumps, a fault, Esc stopping a loop,
quitting, and ELF symbols.
