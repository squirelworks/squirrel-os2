# Ring 3 and protection (2.4)

Since 2.4, loaded programs (`run`, `SYS_EXEC`) and the threads they start with `SYS_SPAWN` run
in ring 3. The kernel, the shell and the built-in apps stay in ring 0. A process runs in ring 3
exactly when it has an address space of its own (`PCB_AS` ≠ 0).

## Segments and the TSS

| Selector | Use |
|----------|-----|
| `0x08` / `0x10` | Kernel code / stack (ring 0, flat) |
| `0x18` / `0x20` | TSS of the normal task / of the double-fault task (`crash-reports.md`) |
| `0x2B` (`USER_CS`) | Ring-3 code, flat |
| `0x33` (`USER_DS`) | Ring-3 data, flat. The kernel also keeps it in DS, ES, FS and GS, so an `iretd` to ring 3 never needs to reload them |

All segments are flat (base 0, 4 GB); protection comes from paging. The timer, keyboard,
mouse, system-call and exception entries reload DS and ES (`KSEGS` in `pm.asm`), in case a
program put a null selector there.

`tss_main` holds `SS0 = 0x10` and `ESP0`, the stack the CPU switches to when ring-3 code is
interrupted or calls the kernel. `proc_switch` sets `ESP0` to the top of the incoming slot's
8 KB kernel stack (`proc_set_esp0`); the shell's slot uses the boot stack.

## Starting a program

`proc_trampoline` sends a process with an address space to `proc_enter_user`, which, on the
slot's ring-3 stack (below):

1. writes a 9-byte exit stub at the top (`mov ebx, eax` / `mov eax, SYS_EXIT` / `int 0x80`);
2. copies the 64-byte argument string under it when the argument is the loader's copy (kernel
   memory a ring-3 program could not read); a thread's argument is passed as it is;
3. pushes the argument and the stub's address, so `entry(arg)` returning exits with its value;
4. clears the general registers and `iretd`s to `USER_CS:entry` with `EFLAGS = 0x202` (IF on,
   IOPL 0).

## Page tables

Every address space is a copy of the kernel's page directory with a private copy of the 0–4 MB
page table (`vm.asm`). The user bit (`PG_U`) is set only on:

- the 0–4 MB directory entry, and in its table only the 16 program-area pages (`0x30000`–`0x3FFFF`);
- the heap's directory entry and pages (`0x40000000`, `SYS_SBRK`);
- the ring-3 stack directory entry and pages (`0x7FC00000`).

Everything else, the kernel's low and high images, its data and stacks, the identity-mapped RAM
and the framebuffer, is supervisor-only. A ring-3 access there is a page fault with the user bit
in the error code (`error=00000005` for a read).

## Growing stacks

Each process slot *i* has a 512 KB ring-3 stack window from `0x7FC00000 + i * 0x80000`; its top
is the next window's start. Pages are mapped when first touched: the page-fault handler
(`exc_report`) asks `vm_ustack_fault`, which maps a zeroed page when the address is in the
current thread's own window and returns to the faulting instruction without a report. The lowest
page of every window is never mapped: a fault there is reported as `*** stack overflow in pid N`
and ends that thread. The pages stay mapped for later threads in the same slot of the same
address space, and are freed with the address space.

## Ending a misbehaving program

A ring-3 page fault, general-protection fault (`cli`, `hlt`, `in`/`out`, an `int` to a ring-0
gate) or any other exception goes through `exc_report`, which prints the report and ends only that
process with exit code −1 (`Program ended: pid N`), as it did for programs before 2.4. The
timer preempts any process interrupted in ring 3 once its slice is used up.

## System-call pointer checks

`syscall_isr` looks at the caller's CS. From ring 3 it first runs `sys_uargs`, which checks every
pointer argument against the caller's own memory: the program area, the heap up to the break and
the ring-3 stack windows. A buffer must lie wholly inside one of them; a string must start in one
and end (zero byte) inside the same one. One byte per call in `sys_uarg_kind` says what to check:

| Kind | Calls |
|------|-------|
| `ebx` string | `puts`, `open`, `create`, `delete`, `devfind`, `devreg`, `devunreg` |
| `ebx`, `ecx` strings | `rename`; `exec` (`ecx` may be 0) |
| `ecx` buffer of `edx` bytes | `read`, `write`; `devread`/`devwrite` (a sector for block devices) |
| `ebx` buffer of `ecx` bytes | `fserror` |
| `ecx` sector / 20 bytes | `bread`, `bwrite` / `readdir` |
| block and the buffer it points to | `netsendto` (16-byte block), `netrecvfrom` (20-byte block) |
| kernel-only | `palloc`, `pfree`: they deal in physical pages. Programs use `SYS_SBRK` |
| per operation | `gui`: the rect block and its buffer, the font buffer, the eval block and its strings, the palette bytes (`syscalls.md`) |

In the ring-3 stack windows, pages can be unmapped, so every page a buffer or string covers
must also be safe for the kernel to touch (`ua_page_ok`): either it is mapped, or it lies in the
calling thread's own window above the guard page, where a kernel access just grows the stack.
A pointer into another thread's untouched stack page or into a guard page is refused instead of
faulting inside the kernel (which would end the caller).

A call that fails the check does not run and returns −1 (`SYS_EFAULT`). Calls from ring 0 are
not checked.

## Test

`programs/ring3.asm` (`run ring3`, checks `ring3` and `ring3-after`): checks that CS has RPL 3;
that `puts`, `fserror` and `readdir` refuse kernel and out-of-area pointers, and pointers into
another slot's untouched stack page or a guard page, and `palloc` is refused; that six threads reading or writing kernel memory, running `cli`, `hlt`, `in` or
`int 0x21` are each ended with −1 while the program carries on; and that a thread can use 64 KB
of stack. `stackover` checks the guard page.
