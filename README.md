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

**2.3.0** — real windows on the VBE framebuffer, Program Manager / Warp 3 desktop (icons, File Manager, clipboard, Control Panel, bevelled widgets), long names and FAT, drive objects, UEFI and modern disks/USB, long-mode entry and SMP, DHCP/DNS/HTTP and AC'97/HDA audio, the full apps/games/calculator suite, and more foreign programs (OS/2 LX, Win32 GUI/DLL/registry, FreeBSD, DOS graphics). Before it: 2.1.0 (framebuffer, ring 3, first apps/games/foreign programs), 2.0.2 and 2.0.0.  
Build and run with `tools/build.sh` and `tools/run.sh` (`documentation/guides/getting-started.md`).  
Notes: `documentation/releases/2.3.0.md`, `2.1.0.md`, `2.0.2.md`, `2.0.1.md`, `2.0.0.md` (1.0: `1.0.0.md` … `1.0.12.md`; 1.1–1.9 through `1.9.12.md`). Limits: `documentation/specifications.md`. What to do next: [TODO.md](TODO.md) / [HANDOFF.md](HANDOFF.md).  
Font: lowercase `q` now has a straight stem with a right-hand tail on its descender, so it no longer reads as `9`.

## License

Squirrel OS/2 is free software under the [GNU General Public License, version 3](LICENSE) (GPL-3.0), the same license as SquirrelSoft.
