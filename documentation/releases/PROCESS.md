# Release Process

## Versioning

Squirrel-OS/2 uses a simple `major.minor.patch` scheme for early development:

- **0.0.x** — boot sector / pre-kernel experiments
- **0.1.x** — protected-mode entry and native timer
- **0.2.x** — minimal kernel services (console, memory map, basic interrupts)
- **0.3.x–0.9.x** — applications, loader, shell, memory, drivers, directories, integration
- **1.0.0** — the usable minimal system; **1.0.x** patch releases, then **1.x** minor releases toward 2.0 (`../../ROADMAP.md`)

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

## Pull request workflow

To keep review and merging simple:

- Base every PR on `main` (not on another feature branch).
- One logical milestone or coherent change per PR.
- Do not stack feature branches on other feature branches.
- After pushing, confirm the PR targets `main` and shows as mergeable with no conflicts.
- Prefer merging bottom-up only when the base is already `main`.

This avoids retargeting chains and confirmation steps.

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
| 0.8.0   | 2026-10-30 | SQFS directories                     |
| 0.8.1   | 2026-10-30 | Localization runtime                 |
| 0.8.2   | 2026-10-30 | Crash reports and shell restart      |
| 0.9.0   | 2026-10-31 | Browser launches the 1.0 apps        |
| 0.9.1   | 2026-10-31 | Files persist across reboots         |
| 0.9.2   | 2026-10-31 | Stability and polish pass            |
| 0.9.3   | 2026-10-31 | Release readiness                    |
| 1.0.0   | 2026-10-31 | Usable minimal system                |
| 1.0.1   | 2026-10-31 | FPU state saved per process          |
| 1.0.2   | 2026-10-31 | Seek on open files                   |
| 1.0.3   | 2026-10-31 | Programs read file-error reasons     |
| 1.0.4   | 2026-10-31 | Zombies no longer fill the table     |
| 1.0.5   | 2026-10-31 | Localized usage lines and FS errors  |
| 1.0.6   | 2026-10-31 | App titles follow the language       |
| 1.0.7   | 2026-10-31 | Numerical derivatives in diff        |
| 1.0.8   | 2026-10-31 | Numerical integrals in diff          |
| 1.0.9   | 2026-10-31 | Search in the editors                |
| 1.0.10  | 2026-10-31 | Euler ODE stepper in diff            |
| 1.0.11  | 2026-10-31 | One-level undo in the editors        |
| 1.0.12  | 2026-10-31 | vedit shows control characters      |
| 1.1.0   | 2026-10-31 | Timer preempts spinning programs     |
| 1.1.1   | 2026-10-31 | Threads share a program's memory     |
| 1.2.0   | 2026-10-31 | Message queues between processes     |
| 1.2.1   | 2026-10-31 | Key events in the message queue      |
| 1.3.0   | 2026-10-31 | Graphics mode and a pixel            |
| 1.3.1   | 2026-10-31 | Lines and filled rectangles          |
| 1.3.2   | 2026-10-31 | Text in graphics mode                |
| 1.3.3   | 2026-10-31 | graph plots a function               |
| 1.4.0   | 2026-10-31 | Windows: create and close            |
| 1.4.1   | 2026-10-31 | Windows: move and resize             |
| 1.4.2   | 2026-10-31 | Windows: z-order and focus           |
| 1.5.0   | 2026-10-31 | Widgets: label                       |
| 1.5.1   | 2026-10-31 | Widgets: button                      |

## Next planned release

**1.0.x** — Patch releases for the holes the docs already name (seek, error reasons for programs, FPU save, zombies, localization, `diff`, editor search and undo), then **1.1** — preemptive scheduler and threads.

1.0.0 is released (`1.0.0.md`). Milestone 1.1 (1.0.1 through 1.1.1) is summarized for its tag in `1.1.md`. Its applications are checked together in one boot by `walk-1.0` in `tools/regress.sh`.

The forward plan and the PR-sized tasks are [`../../ROADMAP.md`](../../ROADMAP.md) and [`../../TODO.md`](../../TODO.md).
