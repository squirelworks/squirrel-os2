# DOS personality (P.8) — design

Status: design only. This page fixes the choices for the first DOS step so it can be built in
one go once ring 3 (2.4) exists. Original design, written from the public descriptions of the
DOS program interface (`INT 21h` functions, the PSP layout, the `.COM` format). No DOSBox,
FreeDOS, ReactOS NTVDM or other DOS code is used.

## Goal of the first step

Run small text-mode DOS `.COM` programs in the shell or a console window: `run game.com
[arguments]` prints, reads keys, reads and writes files, and returns to the shell with its exit
code. `.EXE` (MZ with relocations), DOS extenders, graphics modes and sound come later.

## Choice: virtual-8086 mode, not an emulator

| | V86 mode | x86 interpreter |
|-|----------|-----------------|
| Speed | native | 20–50× slower |
| Kernel needs | a V86 task frame, a GP-fault monitor, an IOPL policy | none (pure program) |
| Size | small monitor (~1–2 KB) | 6–10 KB for a useful 8086 core |
| Fits Squirrel today | after 2.4 (ring 3, TSS with `esp0`, IRET to V86) | could run now as a program |
| Real-hardware value | high: real timing, real DOS speed | low |

**Decision:** V86 mode, as the personality's long-term home, scheduled right after 2.4 gives the
kernel a TSS with a ring-0 stack and IRET into user mode (the same machinery V86 needs). An
interpreter stays a fallback for the 64-bit kernel (long mode has no V86); that later
`programs/dosemu.asm` path would share the `INT 21h` layer described below, which is written as a
table of handlers that take and return a register frame, so both callers fit.

## Memory

Each DOS process gets its own address space (already the case for programs, `vm.asm`). Its
first megabyte is virtual:

| Linear | Contents |
|--------|----------|
| `0x00000–0x003FF` | real-mode IVT: every vector points at a `INT`-trap stub so the monitor sees it |
| `0x00400–0x004FF` | BIOS data area: a copy filled with the values DOS programs read (screen columns, tick count) |
| `0x00500–0x0FFFF` | free (DOS "low memory") |
| `0x10000` | the program segment: PSP at offset 0, the `.COM` image at `0x100`, `SP = 0xFFFE` with a 0 word pushed so `RET` reaches `INT 20h` at PSP:0 |
| `0x20000–0x9FFFF` | conventional memory for `INT 21h` 48h/49h/4Ah |
| `0xB8000–0xBFFFF` | a private text buffer shown in the program's console window (read back when the window draws) |

The kernel's own mappings at those addresses (program area, staging buffer, stacks) are left out
of a DOS address space; the kernel reaches its data through its high mapping once 2.4 moves
it there, which is a prerequisite.

## The monitor

V86 code runs at CPL 3 with `IOPL < 3`, so `INT n`, `CLI`/`STI`, `PUSHF`/`POPF`, `IRET`, `IN`/`OUT`
fault with #GP into the monitor, which decodes the opcode at `CS:IP`:

- `INT n`: `20h` exit; `21h` the DOS table below; `16h` keyboard (00h read, 01h peek); `10h` the
  subset 0Eh teletype, 02h/03h cursor, 00h mode 3 only; `1Ah` 00h ticks. Anything else ends the
  program with `dos: unsupported INT nn AH=xx` (no silent wrong behaviour).
- `CLI`/`STI`/`PUSHF`/`POPF`/`IRET`: a virtual IF bit per process.
- `IN`/`OUT`: refused (message and exit) in the first step; keyboard port 60h and PIT port 40h
  reads may be emulated later for games.

## `INT 21h` first subset

| AH | Function | Native mapping |
|----|----------|----------------|
| 01h, 07h, 08h | key with / without echo | `SYS_GETC` |
| 02h, 09h | character, `$`-terminated string | `SYS_PUTC` / console device |
| 0Ah | buffered line input | line editor |
| 25h, 35h | set / get vector | the per-process IVT |
| 2Ah, 2Ch | date, time | CMOS clock |
| 30h | version | 5.0 |
| 3Ch, 3Dh, 3Eh, 3Fh, 40h, 42h | create, open, close, read, write, seek | `SYS_OPEN`/`SYS_CLOSE`/`SYS_READ`/`SYS_WRITE`/`SYS_SEEK`; DOS handles 0–4 are the console, 5+ = native fd + 5 |
| 41h, 56h | delete, rename | `SYS_DELETE`, `SYS_RENAME` |
| 48h, 49h, 4Ah | allocate, free, resize memory | a paragraph allocator over `0x20000–0x9FFFF` |
| 4Ch | exit with code | `SYS_EXIT` |

Errors set CF and return the DOS error code in AX (2 file not found, 4 too many handles,
5 access denied, 6 invalid handle, 8 out of memory). File names are upper-cased and `8.3`
names map directly onto SQFS names; `C:\` and the current directory map onto the SQFS root and
`cd`.

## Selecting it

The loader picks it by name: a file ending in `.com` (any case) that is not an SQX/ELF/MZ image.
A `.com` beginning with `MZ` is really an `.EXE` and goes to the (later) EXE path.

## Tests (when built)

Hand-written `.COM` programs in `programs/dos/`, assembled with `nasm -f bin` (`org 0x100`):

- `doshello.com`: `AH=09h` string, `AH=4Ch` exit 0 → `doshello: PASS`.
- `dosfile.com`: create/write/close/open/read/seek through `INT 21h` and compare, a missing file
  must set CF with AX = 2 → `dosfile: PASS`.
- `dosint.com`: an unsupported `INT 13h` must end it with the `unsupported INT` message and the
  shell must stay usable.

## Order of work

1. (needs 2.4) TSS `esp0`, IRET to V86, the #GP monitor with `INT 20h`/`21h` 4Ch/09h → `doshello`.
2. File and memory functions → `dosfile`.
3. Console window with the private `0xB8000` buffer; `INT 10h`/`16h` subset.
4. MZ `.EXE` loading with relocations; then BIOS-port emulation for games.
