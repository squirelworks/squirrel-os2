# Squirrel-OS/2 Planned Milestones

## Vision for 1.0.0

Version 1.0.0 is a functional operating system that:

- Boots and takes ownership of the machine
- Provides a file system
- Includes a file browser
- Can load and run:
  - a text editor
  - a drawing program
  - a calculator

All components are original Squirrel-OS/2 code.

## Milestone Ladder

### 0.0.x — Bare-metal entry
- **0.0.1** — Boot sector: VGA text output + periodic beep (done)
- **0.0.2** — Native PIT timer interrupt
- **0.0.3** — Protected-mode transition, own GDT/IDT

### 0.1.x — Minimal kernel services
- **0.1.0** — Console (keyboard + VGA text)
- **0.1.1** — Basic memory map and allocator
- **0.1.2** — Simple task switch or cooperative loop

### 0.2.x — Storage
- **0.2.0** — Block device driver (ATA or virtio-blk)
- **0.2.1** — Minimal file system (e.g. flat or simple hierarchical)
- **0.2.2** — File browser (list, open, basic navigation)

### 0.3.x — User programs
- **0.3.0** — Program loader
- **0.3.1** — Calculator
- **0.3.2** — Text editor
- **0.3.3** — Drawing program

### 0.9.x — Integration
- **0.9.0** — File browser can launch the three applications
- **0.9.1** — Persistent files across reboot
- **0.9.2** — Polish and stability pass

### 1.0.0 — Functional OS
- Boots to a usable environment
- File system present and browsable
- Text editor, drawing program, and calculator load and run
- Original Squirrel-OS/2 code throughout

## Notes

- Each milestone gets a release note under `releases/`.
- Design details live in `architecture/` and `kernel/`.
- External / contemporary sources stay outside this tree.
