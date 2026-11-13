# Foreign Application Compatibility — Squirrel-OS/2

## Intent

Squirrel-OS/2 is designed from the ground up and therefore can host programs written for other operating systems without becoming those systems. Foreign binaries (Windows, Linux, macOS/Darwin, Unix/Solaris, Android, iOS) run under original personality layers that translate their ABIs and APIs onto the native Squirrel process model, syscall interface, memory manager, and file system.

No external OS sources (WINE, ReactOS, Linux, Darwin, etc.) are imported. All translation code is original.

The first console subsets (P.1, P.2, P.5) run on the 2.x kernel today; the full layers (GUI mapping, sandboxing) belong to the 3.0 (64-bit) era, when the native desktop, ring 3 and userland are mature enough to host additional personalities safely.

## Design Goals

1. **Native ownership** — The Squirrel kernel remains the only kernel. Foreign programs never see a foreign kernel; they see a translated ABI.
2. **Layered personalities** — Each foreign OS is a loadable personality that supplies:
   - Binary format loader (PE, ELF, Mach-O, etc.)
   - System-call / API translation table
   - Process and address-space conventions
   - Optional graphics / windowing mapping onto the Squirrel desktop
3. **Architecture matching first** — Prefer native execution on a matching CPU (x86_64 PE on x86_64, AArch64 ELF on AArch64). Binary translation or user-mode emulation is a later, optional path for cross-architecture use.
4. **Isolation** — Foreign processes run in ordinary Squirrel processes with restricted capabilities. A personality cannot replace the kernel or the Workplace Shell analogue.
5. **Incremental subset** — Start with the smallest useful subset of each ABI (console, file I/O, basic memory) and grow only as needed. Full GUI compatibility is explicitly deferred.

## Architecture

```
User process (foreign binary)
        │
        ▼
Personality layer (windows / linux / darwin / …)
  • Binary loader
  • Syscall / API translator
  • Library stubs (original)
        │
        ▼
Native Squirrel syscall ABI
        │
        ▼
Kernel (scheduler, memory, FS, devices)
```

Shared services live in `kernel/personalities/common/` (format detection, process setup helpers, mapping utilities).  
Each personality lives in its own directory under `kernel/personalities/`.

## Supported personalities (scaffold)

| Personality | Binary format | Primary ABI / API | Priority notes | Status |
|-------------|---------------|-------------------|----------------|--------|
| **windows** | PE / PE32+ | Win32 / Win64 | Highest practical value; start with console + file I/O | PE32 console subset (P.5) |
| **linux** | ELF | Linux syscall ABI + glibc subset | Closest to POSIX; useful for many Unix tools | Static ELF32 subset (P.1, P.2) |
| **unix** | ELF | POSIX / System V | Overlaps heavily with linux; shared code where possible | Scaffold |
| **darwin** | Mach-O | Darwin / XNU syscalls + limited frameworks | Harder (closed frameworks); console first | Scaffold |
| **solaris** | ELF | Solaris / Illumos syscalls | Treat as unix variant unless specific needs arise | Scaffold |
| **android** | ELF (Bionic) or APK | Android NDK / ART runtime | Requires either Bionic translation or a managed runtime; later | Scaffold |
| **ios** | Mach-O (signed / entitlements) | Darwin + iOS frameworks | Extremely restricted; research / emulation path only | Placeholder |

## Loader responsibilities

A foreign binary loader (under `kernel/loaders/`):

1. Identifies the format and required personality.
2. Creates a Squirrel process with the correct address-space layout.
3. Maps segments / sections and applies relocations.
4. Sets up the initial stack, arguments, and environment in the foreign convention.
5. Transfers control to the personality’s entry stub.

## Principles

- Original code only.
- Document every assumed ABI detail (calling convention, syscall numbers, structure layouts).
- Prefer thin translation over reimplementation of large libraries.
- Sandbox by default; elevate only with explicit user or package-manager consent.
- Graphics and windowing map onto the native Squirrel desktop; foreign GUI toolkits are not hosted as peers.
- Android and iOS are treated as special cases (managed runtimes or heavy translation) and do not block progress on Windows / Linux / Unix.

## Current stage (P.1, P.2, P.5 working; P.8 designed)

Two personalities run real programs today, both inside ordinary Squirrel processes in ring 0
(like native programs, until ring 3 lands in 2.4):

| Step | What runs | Where | Test |
|------|-----------|-------|------|
| P.1 | Linux i386 static ELF32: `write`, `exit` | `kernel/personalities/linux/linux.asm` | `programs/lxhello.asm`: `lxhello: PASS` |
| P.2 | Linux files, memory, `writev`, `ioctl`, `stat64`, `uname`, TLS, time: about 45 calls | same | `programs/lxfile.asm`, `programs/lxsys.asm`: `PASS`; `programs/lxcat.asm` reads a pipe |
| P.5 | Win32 PE32 console programs (KERNEL32 and msvcrt), MinGW-built ones included | `programs/winrun.asm`, `programs/winshim.inc` (user-space loader and shims) | `programs/winhello.asm`, `programs/wincrt.asm`: `PASS` |
| P.8 | DOS `.COM` | design only: `dos-personality.md` | — |

### Linux personality (P.1, P.2)

**Selecting it.** The native loader (`kernel/loader.asm`) already loads static ELF32 images.
An ELF whose `e_ident[EI_OSABI]` is 3 (`ELFOSABI_LINUX`) is marked as a Linux process: the
loader stores the real entry point in the process slot (`PCB_LINUX`, offset 36) and starts the
process through `lx_enter_user`. Native ELF programs (OSABI 0, like `elfhello`) are unchanged. A program
built with a normal toolchain can be marked with `elfedit --output-osabi=Linux`; it must still
be static, linked into the 64 KB program area (`-Ttext=0x30000`, see `loader.md`) and use
`int 0x80` (no vDSO, no `sysenter`).

For example, a freestanding C program whose `_start` makes `int 0x80` calls:

```bash
gcc -m32 -static -nostdlib -fno-pic -fno-stack-protector -O2 \
    -Wl,-Ttext-segment=0x30000 -Wl,-z,noseparate-code -Wl,--build-id=none prog.c -o prog
elfedit --output-osabi=Linux prog
python3 tools/sqfs.py data.img put prog
```

**Initial stack.** Linux programs run in ring 3 like native ones (2.4). `proc_enter_user` hands
a Linux process to `lx_enter_user`, which copies the program name and the argument text to its
ring-3 stack, builds the System V i386 process stack under them and enters `e_entry` with
`edx = 0`:

```
esp ->  argc            1, or 2 when the run line had an argument
        argv[0]         the program name
        argv[1]         the whole argument text (only when there is one)
        NULL
        NULL            envp is empty
        AT_NULL, 0      auxv is empty
```

**System calls.** `syscall_isr` checks `PCB_LINUX` of the current process; when it is set,
`int 0x80` goes to `lx_isr`, which looks the number up in `lx_calls` (the i386 numbers from the
public ABI). Arguments in `ebx, ecx, edx, esi, edi, ebp`; the result in `eax`, errors as
`-errno`; every other register is preserved. Unknown numbers return `-ENOSYS` (−38).
From ring 3, each call's pointer arguments are checked first against the caller's own memory
(a kind byte per table entry, `lx_uargs`, built on the native `ua_range`/`ua_str` of
`../kernel/ring3.md`, iovecs included); a bad pointer returns `-EFAULT` (−14) without running
the call.

| Nr | Call | Mapping |
|----|------|---------|
| 1, 252 | `exit`, `exit_group` | `proc_exit` with the code |
| 3 | `read` | fd 0: a line from the keyboard (echoed) or the redirected input, 0 at its end; fd ≥ 3: `SYS_READ` |
| 4 | `write` | fd 1, 2: the console device (follows `>` redirection); fd ≥ 3: `SYS_WRITE`; fd 0: `-EBADF` |
| 5 | `open` | `SYS_OPEN`; `O_CREAT`/`O_TRUNC`/`O_APPEND` map to the native flags; access mode ignored; missing file `-ENOENT` |
| 6 | `close` | fd ≥ 3: `SYS_CLOSE` (`-EBADF` when not open); 0–2: 0 |
| 19 | `lseek` | `SYS_SEEK` (same whence values); console `-ESPIPE` |
| 20 | `getpid` | native pid |
| 45 | `brk` | moves the native heap break (`SYS_SBRK`); `brk(0)` reports it; refused moves report the old break |
| 90, 192 | `mmap`, `mmap2` | `MAP_ANONYMOUS` only: page-aligned pages from the heap; anything else `-ENODEV` |
| 91 | `munmap` | accepted (0); the pages return when the process ends |
| 10, 40 | `unlink`, `rmdir` | `SYS_DELETE` |
| 38, 39 | `rename`, `mkdir` | `SYS_RENAME`, `fs_mkdir` |
| 33 | `access` | 0 when the file opens, else `-ENOENT` |
| 295 | `openat` | `AT_FDCWD` (−100) or an absolute path, then as `open` |
| 140 | `_llseek` | as `lseek`, 64-bit result (the high word must be 0) |
| 145, 146 | `readv`, `writev` | each `iovec` in turn; stops at a short transfer |
| 54 | `ioctl` | fds 0–2 answer `TCGETS` (zeroed termios), `TIOCGWINSZ` (25 × 80) and accept `TCSETS*`, so `isatty` is true there; files `-ENOTTY` |
| 195, 196, 197 | `stat64`, `lstat64`, `fstat64` | `st_mode` (regular 0644, or a character device for fds 0–2), `st_size`, `st_blocks`, `st_blksize`; the rest 0 |
| 122 | `uname` | `Linux`, `squirrel`, `2.6.32-squirrel`, `Squirrel-OS/2 Linux personality`, `i686` |
| 183 | `getcwd` | `/` |
| 13, 78, 265 | `time`, `gettimeofday`, `clock_gettime` | time since boot from the 100 Hz tick (there is no clock call yet) |
| 162 | `nanosleep` | one yield |
| 174, 175, 176 | `rt_sigaction`, `rt_sigprocmask`, `rt_sigpending` | per process, signals 1–32 (below); `SIGKILL`/`SIGSTOP` cannot be caught or blocked |
| 37, 238, 270 | `kill`, `tkill`, `tgkill` | pid 0, −1 or its own: itself; another Linux process: pending there; a native program `-EPERM` |
| 119, 173 | `sigreturn`, `rt_sigreturn` | reload the registers and the mask from the signal frame |
| 29 | `pause` | waits for a deliverable signal, then `-EINTR` |
| 64 | `getppid` | the parent's pid |
| 24, 47, 49, 50, 199–202 | uid and gid calls | 0 |
| 224, 258 | `gettid`, `set_tid_address` | the pid |
| 125, 219 | `mprotect`, `madvise` | accepted (0) |
| 243 | `set_thread_area` | entry −1 or 7: the per-process TLS segment (below) with `base_addr`; the program loads GS with `0x3B` |

File descriptors: Linux 0–2 are the console; Linux fd *n* ≥ 3 is native fd *n*−3. `brk` and
anonymous `mmap` share the one native heap at `0x40000000`, so shrinking `brk` below a mapping
returns that mapping's pages too; real programs grow `brk` and do not do this.

Signals: a pending, unblocked signal is delivered when its process returns from `int 0x80`.
The kernel pushes a frame on the user stack: the return address (`sa_restorer` with
`SA_RESTORER`, else a `mov eax, 173 / int 0x80` stub inside the frame), the signal number,
pointers to a `siginfo` (`si_signo`, `SI_USER`, `si_pid`) and a `ucontext` holding the i386
`sigcontext` and the old mask, and starts the handler with the signal and `SA_NODEFER`-less
self-blocking applied; `SA_RESETHAND` is honoured. `sigreturn`/`rt_sigreturn` restore the
general registers, `eip`, `esp`, the arithmetic flags and DF, and the mask. Default actions:
`SIGCHLD`, `SIGCONT`, `SIGURG`, `SIGWINCH` and the stop signals are ignored (no job control);
every other signal ends the process with exit code 128 + n and the line
`Program ended by signal n`. A frame that does not fit the user stack ends it with `SIGSEGV`.
Test: `programs/lxsig.asm` (checks `lx-sig`, `lx-sig-term`, `lx-sig-after`).

Not yet: signals from CPU exceptions (a fault still ends the program as for native ones),
signals that interrupt a blocked call, `sigaltstack`, `alarm`/timers, real-time signals above 32,
`clone`/`fork`/`execve`, `dup`/`pipe`, `getdents64`, `chdir`, a real
clock, dynamic linking (P.3), ELF64.

The TLS segment is the same per-process descriptor the Windows layer uses for FS (see the TEB
paragraph below): `set_thread_area` sets its base and the kernel reloads FS and GS with it on
every switch.

### FreeBSD personality (P.10)

A static ELF32 with `EI_OSABI` 9 (FreeBSD) loads like a Linux one, with the same initial stack,
and is marked in `bsd_slot` (`kernel/personalities/bsd/bsd.asm`). Its `int 0x80` arrives in
`lx_isr`, which sends it to `bsd_isr`: the call number is in `eax` and the arguments are on the
user stack above the libc stub's return address, as FreeBSD i386 passes them. Most calls reuse
the Linux handlers; the result comes back FreeBSD's way, `eax` = value with CF clear, or `eax`
= errno (positive; `EAGAIN` 35, `ENOSYS` 78, `ENAMETOOLONG` 63, `ENOTEMPTY` 66, the low ones as
Linux) with CF set. 64-bit results put the high half in `edx`.

| FreeBSD | Calls | Notes |
|---|---|---|
| 1, 431 | `exit`, `thr_exit` | |
| 3, 4, 6, 120, 121 | `read`, `write`, `close`, `readv`, `writev` | as Linux |
| 5 | `open` | `O_CREAT` 0x200, `O_TRUNC` 0x400, `O_APPEND` 8 translated |
| 10, 128, 136, 137, 33 | `unlink`, `rename`, `mkdir`, `rmdir`, `access` | as Linux |
| 17 | `break` | 0 or `ENOMEM`; the heap is the native one at `0x40000000` |
| 197, 477 | `mmap` (with and without the FreeBSD 6 pad) | `MAP_ANON` (0x1000) only |
| 199, 478 | `lseek` (with and without the pad) | 64-bit result, high half 0 |
| 54 | `ioctl` | `TIOCGETA` and `TIOCGWINSZ` on fds 0–2, so `isatty` works |
| 116, 232, 240 | `gettimeofday`, `clock_gettime`, `nanosleep` | as Linux |
| 326 | `__getcwd` | `/`, result 0 |
| 20, 24, 25, 43, 47, 253 | `getpid`, uid/gid calls, `issetugid` | the pid, or 0 |
| 73, 74, 75 | `munmap`, `mprotect`, `madvise` | accepted |

Test: `programs/bsdhello.asm` (checks `bsd-hello`, `bsd-after`). Not yet: `stat` (FreeBSD's
`struct stat` differs), `sysctl`, signals, `getdirentries`, and the other systems in P.10:
NetBSD and OpenBSD (their own numbers and ELF notes) and Solaris (`lcall 7,0` / `int 0x91`).

### OS/2 text-mode personality (P.9)

`os2run` (`programs/os2run.asm`) runs OS/2 32-bit text-mode programs in the LX format. The
kernel loader hands it every `MZ` file whose `e_lfanew` points at `LX`. It is a user program,
like `winrun`: it reads the file into its heap, gives each object page-aligned memory, copies
the pages (legal and zero-filled; not iterated), applies the fixups (source types 32-bit offset
and 32-bit self-relative; targets internal, import by ordinal and import by name, with
additive values and source lists), and calls the entry point on the stack object as
`entry(hmod, 0, env, cmdline)`. The TIB is reached through FS (`SYS_SETTLS`), with
`tib_pexchain` = −1, a TIB2 (thread 1) and the PIB from `DosGetInfoBlocks`. The command line is
`name NUL arguments NUL NUL`; the environment is empty.

DOSCALLS imports by ordinal bind to `_System` shims (arguments on the stack, the caller pops,
`APIRET` in `eax`). Any other import is bound to a stub that prints
`os2run: MODULE.ordinal is not implemented` and ends the program with exit code 3 when called.

| Ordinal | Call | Notes |
|---|---|---|
| 282, 281 | `DosWrite`, `DosRead` | handles 0–2 the console (a read gives one line with CR LF), files = native fd + 3 |
| 273, 257 | `DosOpen`, `DosClose` | open flags: exists → fail / open / replace, new → fail / create; action 1, 2 or 3; `ERROR_OPEN_FAILED` |
| 256, 259 | `DosSetFilePtr`, `DosDelete` | |
| 234 | `DosExit` | the result is the exit code |
| 299, 304 | `DosAllocMem`, `DosFreeMem` | page-aligned, zeroed heap; freeing is accepted |
| 312 | `DosGetInfoBlocks` | TIB and PIB |
| 348 | `DosQuerySysInfo` | max path 260, page size 4096, version 20.45, ms count; the rest 0 |
| 274, 275 | `DosQueryCurrentDir`, `DosQueryCurrentDisk` | the root of C: |
| 224, 227 | `DosQueryHType`, `DosScanEnv` | devices for 0–2; no variables |
| 212, 229, 286 | `DosError`, `DosSleep`, `DosBeep` | accepted (`DosSleep` yields once) |

Test: `programs/os2hello.asm`, a hand-written LX (checks `os2-hello`, `os2-missing`,
`os2-notlx`, `os2-after`). Not yet: 16-bit code and 16:16 fixups, iterated pages, program
DLLs, threads, VIO/KBD/MOU, PM.

### Windows personality (P.5)

**Selecting it.** When the kernel loader finds an `MZ` file it runs the program `winrun` (from
the data disk) with the argument `<file> <argument>`, so `run prog.exe` and `run winrun prog.exe`
are the same. The kernel holds only this hand-off; the PE loader and the KERNEL32 shim are an
ordinary SQX program, so they cost no kernel space and move to ring 3 unchanged.

**Loading.** `winrun` checks `MZ`, `PE\0\0`, machine `0x14C`, PE32 optional header magic
`0x10B` and subsystem 3 (console). It takes `SizeOfImage` bytes of page-aligned heap (so the
image sits at `0x40000000` or a little above, never at its `ImageBase`), copies the headers,
reads each section's raw data to its RVA (bss parts read as zero), and applies the base
relocations (`IMAGE_REL_BASED_HIGHLOW`; `ABSOLUTE` padding is skipped). An image without
relocations cannot move and is refused with a message.

**Imports.** For each import descriptor, every thunk gets an address. Functions of
`KERNEL32.dll` (any case) that the shim provides are bound to it; every other import (any DLL,
or by ordinal) is bound to a 10-byte stub that prints `winrun: not implemented: <name>` and ends
the program with exit code 3 when called. A program that imports more than it calls still runs.

**The shim** (stdcall, callee pops; keeps `ebx`, `esi`, `edi`, `ebp`):

| Function | Behaviour |
|----------|-----------|
| `GetStdHandle` | −10/−11/−12 → console handles `0x10`/`0x11`/`0x12` |
| `WriteFile`, `WriteConsoleA` | console: characters through `SYS_PUTC`; files: `SYS_WRITE` |
| `ReadFile` | console: one line, keys echoed, Enter as CR LF; files: `SYS_READ` |
| `CreateFileA` | `SYS_OPEN`; `CREATE_ALWAYS`/`CREATE_NEW` create and truncate, `OPEN_ALWAYS` creates, `TRUNCATE_EXISTING` truncates; file handle = native fd + `0x100`; failure `INVALID_HANDLE_VALUE` and last error 2 |
| `CloseHandle`, `SetFilePointer` | `SYS_CLOSE`, `SYS_SEEK` (the high dword is ignored) |
| `ExitProcess` | `SYS_EXIT`; returning from the entry point does the same with `eax` |
| `GetCommandLineA` | the file name and the argument text |
| `GetLastError`, `SetLastError` | one value per program |
| `GetModuleHandleA(NULL)`, `GetModuleHandleW(NULL)` | the image base |
| `GetProcessHeap`, `HeapAlloc`, `HeapFree` | zeroed heap memory, 8-byte aligned; free is a no-op |
| `VirtualAlloc`, `VirtualFree` | page-aligned zeroed heap pages; free is a no-op |

Start-up code from compilers also needs the rest of what `programs/winshim.inc` adds:
critical sections (no-ops, one thread), `TlsAlloc`/`TlsGetValue`/`TlsSetValue` (64 slots in the
TEB), `VirtualProtect`/`VirtualQuery`, `MultiByteToWideChar`/`WideCharToMultiByte` (Latin-1),
`LoadLibrary*`/`GetProcAddress` (the DLL loader, P.6 below), `GetStartupInfoA`, `Sleep` (a yield),
console-mode and code-page queries, `DeleteFileA`, `ExitThread`.

**msvcrt.** Imports from `msvcrt.dll` bind to a small C runtime in the same file (cdecl):
`__getmainargs` (argv split from the command line at spaces, an empty environment), `_initterm`,
`_onexit`/`atexit` and `exit` (runs them, last first), `_exit`, `abort`, `_errno`, the
`__p__fmode`/`__p__commode`/`__set_app_type` family; `malloc`/`calloc`/`realloc` (heap with a
size header; `free` keeps the memory), `str*`/`mem*`/`atoi`; stdio on `FILE` (`_iob[0..2]`
are the console, `fopen` `r`/`w`/`a` makes file streams): `fwrite`, `fread`, `fputc`, `fputs`,
`puts`, `putchar`, `fgetc`, `getchar`, `fgets`, `fopen`, `fclose`, `fflush`; and `printf`,
`fprintf`, `vprintf`, `vfprintf`, `sprintf`, `vsprintf` with `%d %i %u %x %X %p %s %c %%`, the
`-` and `0` flags, width, `*`, string precision and the `l`/`h`/`ll`/`I64` sizes (64-bit values
print their low word). The data imports `_iob`, `__initenv`, `__mb_cur_max`, `_fmode`,
`_commode` bind to variables.

**TEB and PEB.** Before the entry point, `winrun` builds a TEB (exception list −1, stack base
and limit, `Self` at `+0x18`, ids, the PEB at `+0x30`, TLS slots at `+0xE10`) and a PEB (image
base at `+8`) and asks the kernel for a segment based there with `SYS_SETTLS` (36). FS then
reaches the TEB as on Windows. The kernel keeps one TLS base per process slot and reloads FS
and GS on every switch (`kernel/personalities/common/tls.asm`, GDT selector `0x3B`); for every
other process the base is 0, a plain flat segment.

With that, ordinary MinGW-w64 console programs run unchanged, both with MinGW's own printf and
with msvcrt's (`-D__USE_MINGW_ANSI_STDIO=0`), including `atexit` and `__thread` variables
(MinGW's emulated TLS). Checked by hand with a stripped `i686-w64-mingw32-gcc -O2 -s` build of a
program using printf formats, malloc/realloc, fopen/fprintf/fgets, TlsAlloc and `__thread`:

```bash
i686-w64-mingw32-gcc -O2 -s prog.c -o prog.exe
python3 tools/sqfs.py data.img put prog.exe     # then: run prog.exe arguments
```

Compiled binaries are not kept in the tree (they carry MinGW's runtime); the regression tests
are hand-written PE32 files: `programs/winhello.asm` (KERNEL32 only) and `programs/wincrt.asm`
(msvcrt start-up, printf, sprintf, malloc, FILE I/O, atexit/exit, the TEB through `fs:`).

Not yet: SEH (an exception ends the program like any fault), threads (`CreateThread`),
wide-character stdio, `msvcrt` math and time, PE32+ (P.7).

### Windows GUI, registry and DLLs (P.6)

**USER32 and GDI32** (`programs/wingui.inc`) put GUI-subsystem programs (subsystem 2) on
`SYS_GUI`'s 320 x 200 screen, drawn in a back buffer. Top-level windows (up to 4) get a frame
and a title bar; the newest is on top and has the keyboard. One message queue per program hands
out posted messages, then `WM_PAINT` for invalid windows, `WM_TIMER` for due timers (10 ms
ticks), then keys (`WM_KEYDOWN`, `WM_CHAR` through `TranslateMessage`) and left clicks (a click
at the right end of a title bar is `WM_CLOSE`). COLORREFs go to the nearest of the 64 EGA
colours. USER32: `RegisterClass(Ex)A`, `CreateWindowExA`, `ShowWindow`, `UpdateWindow`,
`DestroyWindow`, `DefWindowProcA`, `Get/PeekMessageA`, `TranslateMessage`, `DispatchMessageA`,
`PostQuitMessage`, `Post/SendMessageA`, `BeginPaint`/`EndPaint`, `GetDC`/`ReleaseDC`,
`Invalidate/ValidateRect`, `GetClientRect`, `FillRect`, `DrawTextA`, `MessageBoxA`,
`LoadCursorA`/`LoadIconA`, `GetSystemMetrics`, `Set/KillTimer`, `SetWindowTextA`,
`MessageBeep`, `wsprintfA`. GDI32: `GetStockObject`, `CreateSolidBrush`, `CreatePen`,
`DeleteObject`, `SelectObject`, `SetTextColor`/`SetBkColor`/`SetBkMode`, `TextOutA`,
`Set/GetPixel`, `MoveToEx`/`LineTo`, `Rectangle`. Not provided: child windows and controls,
menus, resources, fonts beyond the system one, bitmaps. Each window becomes a real desktop
window once program windows arrive with 2.2. A MinGW `-mwindows` program was checked by hand.

**Registry** (`programs/winreg.inc`): ADVAPI32 `RegOpenKeyExA`, `RegCreateKeyExA`,
`RegCloseKey`, `RegSetValueExA`, `RegQueryValueExA` (with `ERROR_MORE_DATA`) and
`RegDeleteValueA` over one text file, `registry.dat`, one value per line as
`KEY|NAME|TYPE|HEXDATA` (for example `HKCU\Software\Acorn|count|4|02000000`). The file is
read on the first call and written after every change, so values outlive the program. The
roots are `HKCR`, `HKCU`, `HKLM`, `HKU`; key names compare without case; up to 48 values and
8 open keys.

**DLLs** (in `programs/winrun.asm`, an original loader written from the PE format): an import
from a DLL that is not a shim is looked for on the disk as its name in lower case plus `.dll`
(`ACORN.DLL` → `acorn.dll`). It is mapped like the program — fresh heap, base relocations, its
own imports bound, which may load further DLLs (the loader saves its state around each load) —
and its imports bind through its export table by name or by ordinal. A forwarded export
(`KERNEL32.GetLastError`) binds to the shim of that name. `DllMain(base, DLL_PROCESS_ATTACH, 0)`
runs once per DLL, dependencies first, after the TEB exists and before the program's entry
point; FALSE ends the program. At run time `LoadLibraryA/W`, `LoadLibraryExA/W` load the same
way (or return the loaded one), `GetModuleHandleA/W` find loaded DLLs, `GetProcAddress` takes
names or ordinals, and shim DLLs (`kernel32`, `msvcrt`, `user32`, `gdi32`, `advapi32`) answer
with one pseudo handle whose procedures are the shims. A DLL that is not on the disk binds its
imports to the stub that names them. Up to 8 DLLs; no `DLL_PROCESS_DETACH`, no TLS callbacks.
Checked by hand with a MinGW-built DLL (its own CRT start-up and `DllMain`) and a program
that imports from it and also reaches it through `LoadLibraryA`/`GetProcAddress`.

Tests: `programs/winwnd.asm` (a window, painting, a timer, keys), `programs/winreg.asm`
(values set, read back, deleted, and kept across two runs) and `programs/windll.asm` with its
DLL `programs/winlib.asm` (`acorn.dll`: name, ordinal and data imports, a forwarder, DllMain,
LoadLibrary and GetProcAddress, a missing DLL).

### Ring 3

Both layers run in ring 3 since 2.4: Linux programs enter through `lx_enter_user` and call the
kernel only through the `int 0x80` gate with checked pointers; the Windows layer is an ordinary
user program, and the TLS selector `0x3B` is a DPL 3 data segment, so ring-3 code loads it into
FS or GS itself.

## Related

- `multi-arch.md` — native execution on matching architectures
- `overview.md` — ownership after hand-off
- `plannedmilestones.md` — 3.0 positioning and foreign-application notes
- `kernel/personalities/README.md`
- `kernel/loaders/elf_stub.asm` (the original design sketch)
- `kernel/personalities/linux/linux.asm`, `programs/winrun.asm`
- `dos-personality.md` — P.8 design
