# Squirrel-OS/2 Documentation

Ongoing documentation for the Squirrel-OS/2 project.

Squirrel-OS/2 is an original operating-system effort in the spirit of OS/2 Warp.  
All material under this tree is project-native. External or contemporary sources are kept separate and are not copied here.

## Structure

| Directory       | Purpose                                      |
|-----------------|----------------------------------------------|
| `architecture/` | High-level design, goals, and system model   |
| `kernel/`       | Kernel design notes and implementation log   |
| `guides/`       | Build, run, and contribution guides          |
| `releases/`     | Release notes and version history            |

## Status

Documentation is active.

- Architecture overview expanded
- PIT timer design added (`architecture/pit-timer.md`)
- Release process formalized (`releases/PROCESS.md`)
- Milestone plan added (`plannedmilestones.md`) — 1.0.0 defined
- Known bugs list added (`knownbugs.md`) — no open defects as of 0.9.3 (KB-11 to KB-15 found and resolved in 0.9.3)
- Specifications added (`specifications.md`) — capabilities and intentional limitations, current to 0.9.3
- Forward plan: [`../ROADMAP.md`](../ROADMAP.md). Task list: [`../TODO.md`](../TODO.md). Milestone history: `plannedmilestones.md`
- 0.1.1 syscall interface implemented (`kernel/syscalls.md`, `releases/0.1.1.md`); regression script `tools/regress.sh`
- 0.1.2 process model implemented (`kernel/processes.md`, `releases/0.1.2.md`)
- 0.2.0 ATA PIO block driver implemented (`kernel/block-device.md`, `releases/0.2.0.md`)
- 0.2.1/0.2.2 SQFS file system implemented (`kernel/filesystem.md`, `releases/0.2.1.md`)
- 0.2.3 file browser implemented (`apps/files.md`, `releases/0.2.3.md`)
- 0.3.x apps: calculator polish, editors (`releases/0.3.2.md`), draw (`releases/0.3.3.md`)
- 0.4.0–0.4.2 program loader and user programs (`kernel/loader.md`, `releases/0.4.0.md`, `releases/0.4.2.md`)
- 0.3.4 scientific and matrix calculators (`apps/calculators.md`, `releases/0.3.4.md`)
- 0.5.0 pipes and redirection (`kernel/shell.md`, `releases/0.5.0.md`)
- 0.5.1 line editing and command history (`kernel/shell.md`, `releases/0.5.1.md`)
- 0.5.2 batch files (`kernel/shell.md`, `releases/0.5.2.md`)
- 0.6.0 page allocator (`kernel/memory.md`, `releases/0.6.0.md`)
- 0.6.1 paging and per-process address spaces (`kernel/memory.md`, `releases/0.6.1.md`)
- 0.6.2 program heaps with `SYS_SBRK` (`kernel/memory.md`, `releases/0.6.2.md`)
- 0.7.0–0.7.2 device model: registry, console, keyboard, disks (`kernel/drivers.md`, `releases/0.7.0.md`)
- 0.8.0 SQFS directories (`kernel/filesystem.md`, `releases/0.8.0.md`)
- 0.8.1 localization runtime (`kernel/localization.md`, `releases/0.8.1.md`)
- 0.8.2 crash reports and shell restart (`kernel/crash-reports.md`, `releases/0.8.2.md`)
- 0.9.0 browser launches the 1.0 apps (`releases/0.9.0.md`)
- 0.9.1 files persist across reboots (`releases/0.9.1.md`)
- 0.9.2 stability and polish pass (`releases/0.9.2.md`, `knownbugs.md`)
- 0.9.3 release readiness: floppy boot, CPU check, build/run scripts, Bochs (`releases/0.9.3.md`, `guides/getting-started.md`)
- **1.0.0 released** — the usable minimal system (`releases/1.0.0.md`, `specifications.md`)
- 1.0.1 each process keeps its own FPU registers (`releases/1.0.1.md`, `kernel/processes.md`)
- 1.0.2 `SYS_SEEK` on open files (`releases/1.0.2.md`, `kernel/filesystem.md`)
- Next: 1.0.x patch releases, then 1.1 preemption (`../ROADMAP.md`, tasks in `../TODO.md`)
