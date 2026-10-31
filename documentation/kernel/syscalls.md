# System Call Interface (0.1.1)

Location: `../../kernel/syscall.asm` (included from `kernel/pm.asm`)

## Gate

- Vector `0x80`, installed by `syscall_init` during IDT setup.
- 32-bit **trap gate**, DPL 3 (`0xEF`). A trap gate leaves `IF` as the caller had it,
  so handlers may block with `sti; hlt`; `iretd` restores the caller's flags.
- DPL 3 means future ring-3 code can call it. Today everything runs in ring 0.

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
| 1 | `SYS_PUTS` | `ebx` = ASCIIZ pointer | bytes written | No pointer validation yet |
| 2 | `SYS_GETC` | — | ASCII code, or −1 | Blocks. Enter → 10, Backspace → 8, Esc → 27. Key releases and unmapped keys are skipped. With redirected input (0.5.0) it returns the next byte, and −1 at the end |
| 3 | `SYS_YIELD` | — | 0 | Switches to the next ready process; if none, halts until the next interrupt |
| 4–7 | `spawn`, `exit`, `wait`, `getpid` | | | Added in 0.1.2, see `processes.md` |
| 8–9 | `bread`, `bwrite` | | | Added in 0.2.0, see `block-device.md` |
| 10–16 | `open`, `read`, `write`, `close`, `create`, `delete`, `rename` | | | Added in 0.2.1, see `filesystem.md` |
| 17 | `SYS_EXEC` | `ebx` = file name, `ecx` = argument or 0 | pid, or < 0 | Added in 0.4.0, see `loader.md` |
| 18 | `SYS_READDIR` | `ebx` = cursor (0 to start), `ecx` = 20-byte buffer | next cursor; 0 at the end; −1 without a disk | Added in 0.4.2: fills the 16-byte name and the size (dword at +16) of the next file |
| 19–20 | `SYS_PALLOC`, `SYS_PFREE` | | | Added in 0.6.0, see `memory.md` |
| 21 | `SYS_SBRK` | `ebx` = bytes to grow (negative shrinks, 0 asks) | the old break, or −1 | Added in 0.6.2: moves the end of the program's heap at `0x40000000` (up to 4 MB), see `memory.md` |
| 22–24 | `SYS_DEVFIND`, `SYS_DEVREAD`, `SYS_DEVWRITE` | | | Added in 0.7.0, see `drivers.md` |
| 25 | `SYS_SEEK` | `ebx` = fd, `ecx` = offset (signed), `edx` = 0 from start / 1 from current / 2 from end | new position, or −1 | Added in 1.0.2, see `filesystem.md` |
| 26 | `SYS_FSERROR` | `ebx` = buffer, `ecx` = its size | the `FE_*` code of the last failed file call; the buffer gets the shell's words for it, zero-terminated, without a newline | Added in 1.0.3, see `filesystem.md` |
| 27–28 | `SYS_SEND`, `SYS_RECV` | | | Added in 1.2.0: a four-byte message to another process's queue, see `messages.md` |
| 29 | `SYS_KEYEVENTS` | `ebx` = 1 on, 0 off | 0 | Added in 1.2.1: key presses also arrive in the caller's queue as `MSG_KEY` + ASCII, see `messages.md` |

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
