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
- Known bugs list added (`knownbugs.md`)
- Specifications added (`specifications.md`) — capabilities and intentional limitations
- Current milestone: 0.0.3 protected-mode transition; next target re-introduce timer under IDT
