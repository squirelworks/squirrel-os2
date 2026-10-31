# Progress toward 1.0.0 (session summary)

**Superseded.** This file is the 2026-10-14 session snapshot. The ladder it calls
"remaining" (0.1.x through 0.9.x) has since shipped; 0.9.2 is the current release.
Plan from [`../../ROADMAP.md`](../../ROADMAP.md) and [`../../TODO.md`](../../TODO.md).

## Completed this session
- **0.0.4** — Protected-mode IDT + native PIT timer
- **0.0.5** — Keyboard (IRQ1) + console (`putc`/`puts`/`cls`)
- **0.0.6** — Bump allocator (`kmalloc`)

## Scaffolded
- In-memory FS in `kernel/pm.asm` with interactive `calc`, dual editors, drawing stub, and calculator suite scaffolds

## Remaining to 1.0.0
- 0.1.x tasking and syscalls
- 0.2.x real block device + persistent FS + file browser
- 0.3.x program loader + interactive basic calculator (done) / editor / drawing program; advanced calculators scaffolded
- 0.9.x integration

Current kernel is a single protected-mode binary with console, timer, keyboard, and allocator.
