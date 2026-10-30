# Crash Reports (0.8.2)

Location: `../../kernel/crash.asm`. The 32 exception stubs in `pm.asm` push the vector and jump to `exc_report`.

## What a report shows

```
*** CPU exception 14 (page fault) in pid 1 (crash)
    EIP=0003001C error=00000000 address=C0000000 (read, page not present)
    EAX=00000022 EBX=00030024 ECX=00000000 EDX=00000000
    ESI=00000000 EDI=00000000 EBP=00000000 ESP=00071FF8
    stack: 000094F6 0000F548 00000000 00000000
Program ended: pid 1
```

| Line | Content |
|------|---------|
| 1 | Vector, its name (divide error, invalid opcode, general protection, page fault, …), and the process that was running with its name |
| 2 | Faulting EIP; the error code for the vectors that push one; for a page fault, CR2 and whether it was a read or a write of a missing page or a protection fault |
| 3–4 | The general registers as they were at the fault (saved with `pushad` before anything else runs); ESP is the value before the CPU pushed its frame |
| 5 | The top four dwords of the faulting stack (skipped if ESP is outside the mapped 256 MB) |

The report switches to the kernel page directory first, so it works even when the fault came while the loader had a program's directory loaded.

Process names (`PCB_NAME`, 16 bytes) are new in 0.8.2:

- the shell is `shell`;
- a built-in app gets its `run` name;
- a loaded program gets its file name.

`ps` shows them too.

## What happens next

| Where | Result |
|-------|--------|
| Any process but the shell (a loaded program, a built-in app, a test worker) | `Program ended: pid N`; the process exits with code −1 and the shell's `wait` returns |
| The shell (pid 0) | `The shell crashed. Enter: restart the shell   R: reboot`. Enter resets the shell stack, turns off output capture, redirected input and any batch script, reloads the kernel page directory and shows a fresh prompt. Processes started earlier keep running. R pulses the CPU reset line through the keyboard controller. |
| Before the shell is up (during boot) | `System halted.` |

Before 0.8.2, a fault anywhere but a loaded program halted the machine. The `trap` command (`ud2`) shows the shell case.

## Limits

- Everything runs in ring 0 on the current stack. A stack overflow into unmapped memory becomes a double fault while the CPU pushes the frame, and the machine resets (triple fault). A separate fault stack needs a TSS (2.x).
- Restarting the shell leaves any file descriptors the shell had open.
