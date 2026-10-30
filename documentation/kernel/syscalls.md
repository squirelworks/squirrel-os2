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
| 2 | `SYS_GETC` | — | ASCII code | Blocks. Enter → 10, Backspace → 8, Esc → 27. Key releases and unmapped keys are skipped |
| 3 | `SYS_YIELD` | — | 0 | Switches to the next ready process; if none, halts until the next interrupt |
| 4–7 | `spawn`, `exit`, `wait`, `getpid` | | | Added in 0.1.2, see `processes.md` |
| 8–9 | `bread`, `bwrite` | | | Added in 0.2.0, see `block-device.md` |
| 10–16 | `open`, `read`, `write`, `close`, `create`, `delete`, `rename` | | | Added in 0.2.1, see `filesystem.md` |

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
