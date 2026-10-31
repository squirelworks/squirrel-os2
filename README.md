# Squirrel-OS/2

An original operating-system effort in the spirit of OS/2 Warp.

**Naming note:** The repository is named Squirrel-OS/2 and the project keeps that name.  
Early releases (through 1.0.0) are a usable minimal system.  
Version 2.0.0 is the first release intended to claim Warp-like character  
(preemptive scheduling, windowing, object desktop).  
Version 3.0.0 is the 64-bit evolution aimed at competing with contemporary  
desktop operating systems.  
Do not describe pre-2.0 builds as OS/2.

All material under this tree is project-native.  
Third-party and contemporary sources remain outside this directory.

## Layout

```
squirrel-os2/
├── README.md
├── ROADMAP.md              ← goals, principles, milestones from 0.9.2
├── TODO.md                 ← PR-sized tasks and acceptance checks
├── documentation/          ← ongoing project documentation
│   ├── architecture/
│   ├── kernel/
│   ├── guides/
│   └── releases/
├── kernel/                 ← original kernel code
├── squirrelbios/           ← own firmware tree (also on GitHub)
├── firmware/               ← stub pointer to squirrelbios/
└── docs/                   (legacy pointer; prefer documentation/)
```

## Documentation

See `documentation/README.md` for the living documentation set.

- Forward plan: [ROADMAP.md](ROADMAP.md)
- Task list: [TODO.md](TODO.md)
- Milestone history and the 2.0 / 3.0 vision: `documentation/plannedmilestones.md`

## Current release

**0.9.2** — stability and polish (file system, browser, `edit`, `vedit`, `draw`, `calc`, `sci`, `matrix`).  
The 0.0.1–0.9.2 ladder is done. Next is **1.0.0**, the packaging of that minimal system.  
Notes: `documentation/releases/0.9.2.md`. What to do next: [TODO.md](TODO.md).
