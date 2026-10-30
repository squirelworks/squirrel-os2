# Foreign Application Compatibility — Squirrel-OS/2

## Intent

Squirrel-OS/2 is designed from the ground up and therefore can host programs written for other operating systems without becoming those systems. Foreign binaries (Windows, Linux, macOS/Darwin, Unix/Solaris, Android, iOS) run under original personality layers that translate their ABIs and APIs onto the native Squirrel process model, syscall interface, memory manager, and file system.

No external OS sources (WINE, ReactOS, Linux, Darwin, etc.) are imported. All translation code is original.

This capability is out of scope for the 1.0 and 2.0 Warp-style milestones. It is scaffolded for the 3.0 (64-bit) era and later, when the native desktop, preemptive scheduler, and userland are mature enough to host additional personalities safely.

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
| **windows** | PE / PE32+ | Win32 / Win64 | Highest practical value; start with console + file I/O | Scaffold |
| **linux** | ELF | Linux syscall ABI + glibc subset | Closest to POSIX; useful for many Unix tools | Scaffold |
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

## Current stage

Directories, design, and a minimal ELF loader stub exist.

- `kernel/loaders/elf_stub.asm` — validates ELF32 headers, counts PT_LOAD segments, and provides a Linux syscall trampoline stub (`write`, `exit`).
- No process creation, segment mapping, or real control transfer yet.

### First Linux personality subset (concrete)

| Item | Detail |
|------|--------|
| Format | ELF32 (ELFCLASS32), ET_EXEC or ET_DYN |
| Machine | EM_386 (3) first; AArch64 / x86_64 later |
| Segments | PT_LOAD only; no PT_INTERP / dynamic linking |
| Stack | Linux convention: argc, argv[], envp[], auxv[] (not yet built) |
| Syscalls (initial) | i386: `exit` (1), `write` (4); x86_64: `exit` (60), `write` (1) |
| Translation | Map onto native Squirrel console and process_exit |
| Error | Unknown syscall → -ENOSYS |

### Personality refinement notes

- **windows**: PE optional header, ImageBase, AddressOfEntryPoint, Import Address Table deferred. First target is a console subsystem (kernel32 `WriteFile`/`ExitProcess`).
- **linux / unix**: Shared ELF loader. Linux uses its own syscall numbers; pure POSIX can share the same mappings where they coincide.
- **darwin**: Mach-O load commands (`LC_SEGMENT_64`, `LC_UNIXTHREAD`). Console-only until frameworks are considered.
- **android**: Builds on the linux personality + Bionic ABI differences. APK/ART is a separate managed path.
- **ios**: Remains a placeholder. No loader work until Darwin personality and code-signing policy exist.

## Next concrete steps (beyond this stub)

These belong in `plannedmilestones.md` rather than immediate implementation:

1. Native process model capable of hosting a foreign address space.
2. Segment mapping and entry-point transfer for a static ELF.
3. Real translation of the four syscalls above onto native services.
4. A tiny static test binary (“hello”) that prints via the personality and exits.
5. PE header validation stub (parallel to the ELF stub).
6. Personality registration table so the loader can select windows/linux/darwin at runtime.

## Related

- `multi-arch.md` — native execution on matching architectures
- `overview.md` — ownership after hand-off
- `plannedmilestones.md` — 3.0 positioning and foreign-application notes
- `kernel/personalities/README.md`
- `kernel/loaders/elf_stub.asm`
