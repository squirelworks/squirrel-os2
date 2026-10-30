# Release Process

## Versioning

Squirrel-OS/2 uses a simple `major.minor.patch` scheme for early development:

- **0.0.x** — boot sector / pre-kernel experiments
- **0.1.x** — protected-mode entry and native timer
- **0.2.x** — minimal kernel services (console, memory map, basic interrupts)

## What belongs in a release

1. Updated or new code under `kernel/` (or future source trees).
2. Corresponding notes in `documentation/kernel/` and `documentation/architecture/`.
3. A release marker in `documentation/releases/X.Y.Z.md` containing:
   - Date
   - Summary of changes
   - Known limitations
   - Build/run instructions if they changed

## Steps

1. Implement and manually verify the change (QEMU or equivalent).
2. Update the relevant design or kernel note.
3. Write the release file.
4. Adjust `documentation/README.md` status line if the focus shifted.
5. Tag the milestone in the project log (this file or a future CHANGELOG).

## Current releases

| Version | Date       | Summary                          |
|---------|------------|----------------------------------|
| 0.0.1   | 2026-10-14 | Initial boot sector (`UwU` + beep) |
| 0.0.2   | 2026-10-14 | Native PIT timer (IRQ0)            |
| 0.0.3   | 2026-10-14 | Protected-mode transition (GDT)    |
| 0.0.4   | 2026-10-14 | IDT + native timer in PM           |
| 0.0.5   | 2026-10-14 | Keyboard input + console           |
| 0.0.6   | 2026-10-14 | Bump allocator                     |
| 0.1.0   | 2026-10-14 | Cooperative task switch            |
| 0.3.1   | 2026-10-14 | Calculator suite (basic interactive) |
| 0.1.1   | 2026-10-30 | System call interface (`int 0x80`)   |
| 0.1.2   | 2026-10-30 | Basic process model                  |
| 0.2.0   | 2026-10-30 | ATA PIO block device driver          |
| 0.2.1   | 2026-10-30 | SQFS on-disk file system (+0.2.2 API) |
| 0.2.3   | 2026-10-30 | File browser                         |
| 0.3.2   | 2026-10-30 | Full-screen editors with load/save   |
| 0.3.3   | 2026-10-30 | Drawing program polish               |
| 0.4.0   | 2026-10-30 | Program loader (SQX + ELF32, 0.4.1)  |
| 0.3.4   | 2026-10-30 | Scientific and matrix calculators    |
| 0.4.2   | 2026-10-30 | User programs: ls, cat (+ readdir)   |
| 0.5.0   | 2026-10-30 | Pipes and redirection                |
| 0.5.1   | 2026-10-30 | Line editing and command history     |
| 0.5.2   | 2026-10-30 | Batch files and autoexec.bat         |
| 0.6.0   | 2026-10-30 | Physical page allocator              |
| 0.6.1   | 2026-10-30 | Paging and per-process address spaces |
| 0.6.2   | 2026-10-30 | Program heaps (`SYS_SBRK`)           |
| 0.7.0   | 2026-10-30 | Driver registration table            |
| 0.7.1   | 2026-10-30 | Console and keyboard as devices      |
| 0.7.2   | 2026-10-30 | ATA disks as block devices           |

## Next planned release

**0.3.x** — Application polish and program loader.
