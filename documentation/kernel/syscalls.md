# System Call Interface (0.1.1)

Location: `../../kernel/syscall.asm` (included from `kernel/pm.asm`)

## Gate

- Vector `0x80`, installed by `syscall_init` during IDT setup.
- 32-bit **trap gate**, DPL 3 (`0xEF`). A trap gate leaves `IF` as the caller had it,
  so handlers may block with `sti; hlt`; `iretd` restores the caller's flags.
- DPL 3: loaded programs run in ring 3 since 2.4 and call it from there. Their pointer
  arguments are checked first (`ring3.md`); a bad one makes the call return −1 without running.

## Calling convention

| Register | Role |
|----------|------|
| `eax` | Call number in, return value out |
| `ebx` | Argument 1 |
| `ecx` | Argument 2 (unused so far) |
| `edx` | Argument 3 (unused so far) |

All registers other than `eax` are preserved (`pushad`/`popad` around the handler).
Flags are restored by `iretd`.
A call number `>= SYS_COUNT` returns `SYS_ENOSYS` (`-1`) without touching anything else.

## Dispatch

`syscall_isr` bounds-checks `eax`, then calls `syscall_table[eax]`.
Handlers are plain near functions: arguments arrive in `ebx`/`ecx`/`edx`,
result goes in `eax`, and they may clobber any other register.
Adding a call means: write the handler, append it to `syscall_table`,
add its `SYS_*` constant, bump `SYS_COUNT`.

## Calls

| # | Name | Args | Returns | Notes |
|---|------|------|---------|-------|
| 0 | `SYS_PUTC` | `ebx` = char | 0 | `10` = newline, `8` = backspace (erase previous cell) |
| 1 | `SYS_PUTS` | `ebx` = ASCIIZ pointer | bytes written | From ring 3 the string must be the program's own memory (2.4, `ring3.md`) |
| 2 | `SYS_GETC` | — | ASCII code, or −1 | Blocks. Enter → 10, Backspace → 8, Esc → 27. Key releases and unmapped keys are skipped. With redirected input (0.5.0) it returns the next byte, and −1 at the end |
| 3 | `SYS_YIELD` | — | 0 | Switches to the next ready process; if none, halts until the next interrupt |
| 4–7 | `spawn`, `exit`, `wait`, `getpid` | | | Added in 0.1.2, see `processes.md` |
| 8–9 | `bread`, `bwrite` | | | Added in 0.2.0, see `block-device.md` |
| 10–16 | `open`, `read`, `write`, `close`, `create`, `delete`, `rename` | | | Added in 0.2.1, see `filesystem.md` |
| 17 | `SYS_EXEC` | `ebx` = file name, `ecx` = argument or 0 | pid, or < 0 | Added in 0.4.0, see `loader.md` |
| 18 | `SYS_READDIR` | `ebx` = cursor (0 to start), `ecx` = 20-byte buffer | next cursor; 0 at the end; −1 without a disk | Added in 0.4.2: fills the 16-byte name and the size (dword at +16) of the next file. Since 2.7, with bit 31 of `ebx` set: `ecx` = 72-byte buffer (whole name, size, flags), `edx` = directory path or 0, any SQFS directory or drive (`fat.md`) |
| 19–20 | `SYS_PALLOC`, `SYS_PFREE` | | | Added in 0.6.0, see `memory.md`. Kernel-only since 2.4: from ring 3 they return −1 |
| 21 | `SYS_SBRK` | `ebx` = bytes to grow (negative shrinks, 0 asks) | the old break, or −1 | Added in 0.6.2: moves the end of the program's heap at `0x40000000` (up to 4 MB), see `memory.md` |
| 22–24 | `SYS_DEVFIND`, `SYS_DEVREAD`, `SYS_DEVWRITE` | | | Added in 0.7.0, see `drivers.md` |
| 25 | `SYS_SEEK` | `ebx` = fd, `ecx` = offset (signed), `edx` = 0 from start / 1 from current / 2 from end | new position, or −1 | Added in 1.0.2, see `filesystem.md` |
| 26 | `SYS_FSERROR` | `ebx` = buffer, `ecx` = its size | the `FE_*` code of the last failed file call; the buffer gets the shell's words for it, zero-terminated, without a newline | Added in 1.0.3, see `filesystem.md` |
| 27–28 | `SYS_SEND`, `SYS_RECV` | | | Added in 1.2.0: a four-byte message to another process's queue, see `messages.md` |
| 29 | `SYS_KEYEVENTS` | `ebx` = 1 on, 0 off | 0 | Added in 1.2.1: key presses also arrive in the caller's queue as `MSG_KEY` + ASCII, see `messages.md` |
| 30 | `SYS_NETSENDTO` | `ebx` = 16-byte block | bytes sent, or −1 | Added in 1.9.7: UDP send, see `network.md` |
| 31 | `SYS_NETRECVFROM` | `ebx` = 20-byte block | bytes, −1 port taken, −2 nothing | Added in 1.9.7: UDP receive, see `network.md` |
| 32 | `SYS_SETPRIO` | `ebx` = 0..3 | 0, or −1 | Added in 1.9.9: set the caller's scheduling priority, see `processes.md` |
| 33 | `SYS_DEVREG` | `ebx` = name | 0, or −1 | Added in 1.9.12: register a null char device, see `drivers.md` |
| 34 | `SYS_DEVUNREG` | `ebx` = name | 0, or −1 | Added in 2.0.2: remove a device `SYS_DEVREG` made and free its slot, see `drivers.md` |
| 35 | `SYS_GUI` | `ebx` = operation, `ecx` = its argument | depends on the operation | Graphics for programs (OS2-APPS): see [SYS_GUI](#sys_gui) below |
| 36 | `SYS_SETTLS` | `ebx` = base address | the selector (`0x3B`) | Added for P.5: the caller's FS/GS segment base, kept per process and reloaded on every switch; FS and GS are loaded at once. Used for the Win32 TEB, see `../architecture/foreign-compatibility.md` |
| 37–44 | `SYS_WINOPEN`, `SYS_WINCLOSE`, `SYS_WINMOVE`, `SYS_WINTITLE`, `SYS_WINDRAW`, `SYS_WINFLUSH`, `SYS_WINEVENT`, `SYS_WININFO` | see `windows.md` | see `windows.md` | Added in 2.2 (**2.2-progwin**): windows for programs |
| 45 | `SYS_NET` | `ebx` = operation, `ecx`/`edx` = its arguments | depends on the operation | Added in 3.0: names, the TCP connection and the interface settings for programs, see [SYS_NET in `network.md`](network.md#sys_net) |
| 46 | `SYS_AUDIO` | `ebx` = operation, `ecx`/`edx` = its arguments | depends on the operation | Added in 3.0: sound for programs, see [SYS_AUDIO in `audio.md`](audio.md#sys_audio) |
| 47 | `SYS_DEBUG` | `ebx` = operation, `ecx` = pid, `edx` = argument | depends on the operation | Added for A.4: trace another program (start it stopped, breakpoints, single step, registers, memory), see `debug.md` |
| 48 | `SYS_TTY` | `ebx` = operation \| tty << 8, `ecx`, `edx` = arguments | depends on the operation | Added for A.3: terminals; a program's output and keys through a terminal's window, see `tty.md` |
| 49 | `SYS_CLIPPUT` | `ebx` = text, `ecx` = length | the length kept | Added in 2.3 (**2.3-clipboard**): see `clipboard.md` |
| 50 | `SYS_CLIPGET` | `ebx` = buffer, `ecx` = its size | the clipboard's length | Added in 2.3: as much as fits is copied |

Example:

```nasm
    mov eax, SYS_PUTS
    mov ebx, msg
    int 0x80            ; eax = strlen(msg)
```

## Keyboard path change

`getc` needs commands to run outside interrupt context, so 0.1.1 moves keyboard handling:

1. `kbd_isr` (IRQ1) only reads the scancode into a 64-byte ring (`kbd_ring`) and sends EOI.
   A full ring drops the scancode.
2. The idle loop in `pm` dequeues scancodes with interrupts off, then calls `kbd_dispatch`
   (the former ISR body) with interrupts on.
3. `SYS_GETC` reads from the same ring, so while a command is blocked in `getc`
   the keys go to it instead of the shell.

## Testing

Shell commands:

- `systest` — calls `puts`, `putc`, `yield` and an unknown number, checks return values and
  that `esi`/`edi` survive; prints `systest: PASS` or `systest: FAIL`.
- `keys` — echoes typed characters via `getc` → `putc` until Enter (try Backspace).

Automated: `tools/regress.sh` builds the image and drives these (plus existing commands)
through headless QEMU.

## Limitations / next steps

- No ring-3 code exists yet, so no privilege transition or pointer checks are exercised.
- (0.1.2) `yield` now switches processes; see `processes.md`.
- Do not call `SYS_GETC` from an interrupt handler; it needs IRQ1 to be deliverable.

## SYS_GUI

`SYS_GUI` (35, `kernel/appsys.asm`) gives a program on the data disk what the built-in graphical apps use. `ebx` selects the operation; `ecx` is its argument. The program draws into a buffer of its own, one byte a pixel, and copies it to the screen with `GUI_BLIT`; `programs/gui.inc` wraps all of it (`../apps/gui-programs.md`).

| `ebx` | Name | `ecx` | Returns |
|-------|------|-------|---------|
| 0 | `GUI_ENTER` | — | 0, or −1 when there are no pages for the text copy. VGA mode 13h, 320 × 200, as `gfx_mode13` (the text screen and the font are saved) |
| 1 | `GUI_LEAVE` | — | 0. Text mode, with the text screen as it was |
| 2 | `GUI_BLIT` | rect block | 0. Copies the block's buffer to the screen; pixels off the screen are skipped |
| 3 | `GUI_READ` | rect block | 0. Copies the screen into the block's buffer (0 off the screen): read-back for self-checks |
| 4 | `GUI_KEY` | — | 0 when no key is waiting, else ASCII \| scancode << 8 \| Ctrl << 16. Does not wait. Releases, Shift and Ctrl give 0 (both are tracked); Esc and Backspace give 27 and 8; keys without ASCII (arrows, F-keys) give 0 in the low byte and their scancode |
| 5 | `GUI_MOUSE` | — | x \| y << 10 \| buttons << 20 (bit 0 left, 1 right, 2 middle; 320 × 200), or −1 without a mouse |
| 6 | `GUI_FONT` | buffer | bytes copied: the kernel's 5 × 7 font, 7 bytes a glyph from `0x20` to `0x7E`, column 0 in bit 4 |
| 7 | `GUI_TICKS` | — | the timer's ticks since boot (100 a second) |
| 8 | `GUI_TIME` | — | hours << 16 \| minutes << 8 \| seconds, from the CMOS clock (BCD or binary) |
| 9 | `GUI_DATE` | — | year << 16 \| month << 8 \| day (the century register, or 20) |
| 10 | `GUI_EVAL` | eval block | 0, or −1 on an error. Evaluates an expression with the `sci` engine |
| 11 | `GUI_PALETTE` | first entry \| count << 16; `edx` = 3 bytes an entry (red, green, blue, 0–63) | 0, or −1 if the entries are not all within 64–255. Sets VGA DAC entries; 0–63 are refused because text mode uses them |
| 12 | `GUI_SYSINFO` | buffer, or pid \| priority << 16; `edx` = part | see below (A.5, `kernel/sysinfo.asm`) |

Rect block: six dwords, `x`, `y`, `width`, `height`, `buffer`, `pitch` (bytes from one buffer row to the next). Width and height up to 4096 and pitch up to 65536, or the call returns −1.

Eval block (40 bytes): `+0` the expression (zero-terminated); `+4` flags: bits 0–1 the variables allowed (0 none, 1 `x`, 2 `x` and `y`), bit 8 degrees, bit 9 store the result as `ans`; `+8` x and `+16` y (doubles); `+24` the result (double, out); `+32` the address of a 40-byte buffer for the result as `sci` prints it, or for the error message (`syntax at column `, `division by zero`, `outside the function domain`, ...), or 0; `+36` (out) the column of a syntax error, from 1. The call resets the FPU.

From ring 3 (`ring3.md`) every buffer must be the program's own memory, or the call returns −1 without running: the rect block and the `pitch × (height − 1) + width` bytes of its buffer, the font buffer, the eval block with its expression and its text buffer, and the palette bytes. The block's pointers are read once and checked on that copy.

### GUI_SYSINFO (A.5)

`GUI_SYSINFO` (12, `kernel/sysinfo.asm`, layouts in `programs/sysinfo.inc`) gives the system monitor and the log viewer a snapshot of the system. `edx` picks the part:

| `edx` | `ecx` | Returns |
|-------|-------|---------|
| 0 | a 32-byte buffer | 0. Dwords: `+0` timer ticks since boot, `+4` of them idle (the CPU halted in `proc_idle`), `+8` pages of RAM the kernel manages (4 KB), `+12` of them free, `+16` process slots in use, `+20` slots (`PROC_MAX`), `+24` preemptions by the timer, `+28` bytes in the kernel log |
| 1 | `PROC_MAX` × 40 bytes | 0. A row for each slot: `+0` pid, `+4` state (0 free, 1 ready, 2 running, 3 waiting, 4 zombie), `+8` priority, `+12` parent's pid, `+16` KB of its own address space (−1: the kernel's), `+20` ticks it has had the CPU, `+24` name (16 bytes, zero-terminated) |
| 2 | a 4096-byte buffer | the bytes copied: the kernel log, lines of `[seconds] text` |
| 3 | pid \| priority << 16 | 0, or −1 if there is no such live process or the priority is above 3. Sets that process's priority (`SYS_SETPRIO` sets only the caller's) |

Any other part returns −1. CPU time is counted by the timer: each tick goes to the process that was running, or to idle time while `proc_idle` has halted the CPU; a slot's count starts again at 0 when `proc_spawn` reuses it. The kernel log keeps the last 4 KB (the oldest lines go first): the boot (`Squirrel-OS/2 started: N KB of memory`), each program the loader starts (`started NAME (pid N)`), each process that ends (`ended NAME (pid N), exit code C`), and each exception report (`crashed NAME (pid N): page fault`). From ring 3 the buffer of parts 0 to 2 must be the program's own memory.

Check: `guitest` (`run guitest`: a window drawn by a program, five pixels read back from the screen, a key poll with nothing typed, the ticks and the date, `2^10` = `1024`, a syntax error at column 4, and `x^2` at x = 3; in ring 3, that kernel-memory buffers are refused for each operation that takes one; it prints `guitest: PASS`), and `guitest-gfx` (`run guitest hold` keeps the window up so the run reads its title and text).
