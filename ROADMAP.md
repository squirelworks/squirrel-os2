# Squirrel-OS/2 Roadmap

Forward plan from **2.0.0** (2026-11-01, `750a990`) to 4.x. Concrete work is in [TODO.md](TODO.md).
The 2.0.0 → 4.x plan below was imported from the SquirrelSoft addendum (2026-11-04) and is tracked by the epics #114–#119.

The record of 0.0.1 through 0.9.2, and the long-range 2.0 / 3.0 vision, stays in
`documentation/plannedmilestones.md`. Release notes stay in `documentation/releases/`.
`documentation/releases/progress-to-1.0.md` is an old session snapshot; do not plan from it.

## Goals

Squirrel-OS/2 is an original operating system in the spirit of OS/2 Warp.
The code in this tree is project-native. Early releases are not described as OS/2.

| Release | What it is |
|---------|------------|
| **1.0.0** | A usable minimal system: it boots, it has a file system and a file browser, and it runs `edit`, `vedit`, `draw`, and the calculator suite that exists today (`calc`, `sci`, `matrix`). |
| **2.0.0** | The first release that can honestly be called Warp-like: preemptive scheduling, an original windowing system, an object desktop. Original concepts, not binary compatibility with classic OS/2. |
| **3.0.0** | A 64-bit system with the same character, aimed at everyday use: the "NT / XP class" GUI generation, with user accounts, services and themes. Foreign personalities (Linux, Windows, DOS, Unix, Darwin) run programs as ordinary windows but stay out of the core. |
| **4.x** | The "Windows 10/11 class" generation: HiDPI, touch, accessibility, a package manager. |

1.0.0 is released (2026-10-31, `documentation/releases/1.0.0.md`).
**2.0.0** is released (2026-11-01, `documentation/releases/2.0.0.md`), and so are **2.0.1** and **2.0.2** (2026-11-04), which finish the 2.0.x clean-up.
**Resumed 2026-11-07:** work continues at **2.1** (framebuffer graphics), then the GUI generations below. Modern hardware H.1–H.6 is scheduled in the 64-bit bridge (2.8–2.9). The PR-sized boxes for 2.1 are in `TODO.md`.

SquirrelBIOS (github.com/squirelworks/squirrelbios) is the firmware this system is meant to sit on; booting Squirrel-OS/2 is its main acceptance test. Squirrel-OS/2 keeps booting under SeaBIOS in QEMU as well. Many built-in applications are first built as desktop programs in squirrelsoft and then ported here.

## Principles

Every change follows these:

1. **Original code only.** No osFree, Voyager, classic OS/2, or other third-party OS sources in this tree. Firmware and contemporary code stay outside.
2. **Small, testable steps.** One coherent change per pull request. Prefer a change `tools/regress.sh` can check over a large rewrite.
3. **Docs updated in the same change.** Design note, release note when the version moves, and `documentation/README.md` when the current focus moves. New defects go in `documentation/knownbugs.md`.
4. **Base every PR on `main`.** Branch from current `main`. After `main` moves, rebase onto it.
5. **No stacked PRs.** Do not open a PR whose base is another feature branch. If task B needs task A, wait until A is merged, then branch B from `main`.

Also already true of this project: document hardware assumptions, keep accepted limits in `documentation/specifications.md`, and follow `documentation/releases/PROCESS.md`.

## Where things are (2.1 started)

Done and covered by `tools/regress.sh`: 32-bit x86 in ring 0, preemptive priority scheduling and threads, messages, VGA mode 13h (320×200×256) graphics, the window manager (`kernel/wm.asm`), widgets, the desktop (`kernel/desktop.asm`) with an object model and persistent objects, a polled PS/2 mouse, SQFS with the file browser, the installer, `calc` / `sci` / `matrix` / `diff`, `edit` / `vedit` / `draw`, the NE2000 driver with ARP, IPv4, UDP, a TCP client and `ifconfig`, `SYS_DEVREG`, and en / la / tlh localization.

2.0.1 and 2.0.2 closed every follow-up from 1.9.10–1.9.12: the mouse runs on IRQ 12 and is drained everywhere, the cursor has a save-under, PS/2 sign bits are handled, clicks in a scrolled list pick the right row, priority aging stops starvation, `SYS_DEVUNREG` frees device slots, and `ifconfig` refuses an off-subnet gateway (402 checks at 2.0.2).

**2.1 in progress:** `2.1-vbe-mode` / `2.1-modes` / `2.1-dblbuf` / `2.1-dirty` map VBE linear framebuffers (640×480, 800×600, 1024×768 at 8/16/32 bpp via Bochs/QEMU DISPI + PCI BAR0), double-buffer with a VRAM back page, blit present with dirty rectangles, and check them with `vbetest`; mode 13h remains the desktop fallback. Remaining box: `2.1-blit-clip`.

Still scaffolds: `graph` and `topo` (replaced by C.2 and C.9 below).

Every milestone below is a checkbox. Tick it in the PR that merges its last piece (and, for an OS milestone, once it is released), and tick the same line in the progress issue #132. Nested boxes are PR-sized steps.

## Done (0.9.2 → 2.0.0)

Kept as a record of how the 2.0.0 system was planned. Do not plan from these sections.

### 1.0.0 — Usable minimal system

Tag the system that already boots. The banner, the release note, and the living indexes name 1.0.0. One regression session runs the file browser, `calc`, `edit` (save and read back), and `draw` in a single boot. `graph` / `diff` / `topo` stay scaffolds at this tag.

### 1.0.x — Holes the docs already name

Patch releases after 1.0.0, each one PR. These are limits written down in the kernel notes, not new product ideas: seek, a failure reason programs can read, saving the FPU across a switch, reaping a zombie nobody waited for, and moving strings that already have localization keys onto those keys. Numerical `diff` (derivative, then integral, then one ODE method) is the calculator work that does not need graphics. Editor search, one-level undo, and the control-character toggle are the "Not yet" lines in `documentation/apps/editors.md`.

### 1.1 — Preemptive scheduler and threads

The PIT tick can switch to another ready process even when the current one does not call `yield`. `proctest` keeps working. A spinning process no longer freezes the machine. Thread means a spawn that shares the parent's address space: `proc_spawn` already keeps the parent's pages until the loader builds a new one (`documentation/kernel/memory.md`). 1.1 tests that and documents it. Priority levels are a 2.0 expectation; they are not part of 1.1.

Start 1.1 only after the FPU save in 1.0.x is on `main`. A preemptive switch in the middle of `sci` or `matrix` would corrupt results without it.

### 1.2 — Messages and an event queue

A fixed queue between processes, with send and receive. Keyboard input grows a "key" event beside `SYS_GETC`. `SYS_GETC` keeps working. This is the queue the window manager will read.

### 1.3 — Graphics primitives

A graphics mode the kernel can enter and leave, back to the VGA text console. Pixel, line, filled rectangle, and bitmap text, each checked by a command that prints `PASS` after reading the framebuffer back. Headless QEMU does not need to OCR a picture.

### 1.4 — Window manager

Create, move, resize, z-order, and focus, drawn with the 1.3 primitives. The keyboard drives focus. Two windows can be on screen, and keys go to the focused one.

### 1.5 — Widget set

Button, label, edit field, and list, each in its own PR, each talking to the 1.2 queue.

### 1.6 — Desktop shell

A shell that hosts `files`, `calc`, `edit`, `vedit`, and `draw` as windows and returns to the desktop when they quit. Pixel drawing inside `draw` (the "Later" section of `documentation/apps/draw.md`) follows this, as its own PR.

### 1.7–1.9 — Object desktop

From `documentation/plannedmilestones.md`. 1.7 and 1.8 are on `main` (classes and messages, instance fields, an `objs` listing, the desktop entries as objects; an object file format, `objcat` after a reboot, the desktop's entries kept in `/desktop`), and 1.9 is split into boxes in `TODO.md` (folders, pick up and drop, rename and delete):

- **1.7** — A small object model (class, method, inheritance) sufficient for a desktop.
- **1.8** — Objects stored in the file system and loaded back.
- **1.9** — Pick up, move, and drop an object on the desktop. The keyboard does this. (A polled mouse was added later, in 1.9.10.)

### Installer (I.1–I.6) — unscheduled

Today the release images are the install: write `os.img` to a USB stick or `floppy.img` to a floppy, byte for byte, and boot it. A real installer boots from that media and copies the system onto the computer's own disk, so the stick can be removed. The boxes are in `TODO.md`. They run alongside the 1.6 desktop work (the author lifted the earlier gate on 2026-10-31), each ships in the next OS version, and none of them is a 2.0.0 requirement.

Assumptions the installer keeps: BIOS boot (Legacy/CSM), an IDE/ATA target disk reached through the existing polled driver, and SQFS as the installed file system. UEFI, AHCI/NVMe, and USB mass storage stay in 2.x.

### 2.0.0 — Warp-style system

Preemptive threads, the windowing system, the object desktop, the hierarchical file system with a graphical browser, the 1.0 applications as desktop objects, a native shell, and basic networking. Original code. No classic OS/2 ABI.

1.9 is on `main`, and networking through the small TCP client shipped in 1.9.3–1.9.8. Warp gaps 1.9.9–1.9.12 are on `main`. **2.0.0** tags that system (`documentation/releases/2.0.0.md`); the owner tags after merge.

## Plan: 2.0.0 → 4.x

Each milestone is one or a few PRs, each with the `tools/regress.sh` count reported and its docs updated. GUI milestones are checked by reading the framebuffer back (`PASS` lines), not by screenshots. The boxes for the milestone being worked on are in `TODO.md`; later milestones are split into boxes, in a docs-only PR, when they come up.

The GUI grows in generations, and each generation is a shippable milestone (epic #114). The OS/2 Warp Workplace Shell look is the default theme at every generation (W.1–W.6, epic #117). Unix, Solaris and macOS ideas (virtual desktops, a dock, a global menu bar) are options, never the default.

### 2.0.x — Clean up 2.0 (first)

- [x] **2.0.1** — An interrupt-driven mouse driver on IRQ 12, drained everywhere (including the text shell); a save-under for the cursor so it leaves no trail; PS/2 sign bits handled. Released 2026-11-04.
- [x] **2.0.2** — A click picks the right row when the list is scrolled; priority aging so a priority-0 process cannot starve; `SYS_DEVUNREG`; `ifconfig` refuses a gateway outside the subnet. Released 2026-11-04.
- [x] Tests: `drvtest` twice per boot, `mousetest` packet-decode cases, the regression count grows.

### 2.1–2.3 — Generation 1: "Windows 3.1 / OS/2 Warp 3 class"

- [ ] **2.1 Framebuffer graphics** — A VBE linear framebuffer at 640×480, 800×600 and 1024×768 in 8, 16 and 32 bpp (from SquirrelBIOS or a real VGA BIOS). Mode 13h stays as the fallback. Double buffering, dirty rectangles, a blitter and clip regions. Test: set a mode, draw, read pixels back; regress in both 13h and VBE. PR-sized boxes: `TODO.md` **2.1-vbe-mode** … **2.1-blit-clip**.
- [ ] **2.2 Real windows** — Overlapping windows that move and resize, with title bar, minimise / maximise / close, a system menu, z-order by mouse, focus, and Alt+Tab. Original proportional bitmap fonts. Test: scripted window-manager operations produce the expected window list and pixel probes.
- [ ] **2.3 Program Manager / Warp 3 desktop** — Icon groups, double-click to launch, a two-pane File Manager, a clipboard, Control Panel v1 (colours, mouse, date and time, keyboard). Warp-style bevelled 3D controls are the default theme.

### 2.4 — Ring 3 and protection

- [ ] **2.4 Ring 3** — The prerequisite for everything after it. User mode, per-process page tables with the kernel protected, a syscall gate, growing stacks, and ending a misbehaving program without bringing the system down.

### 2.5–2.7 — Generation 2: "Windows 95 / OS/2 Warp 4 class"

- [ ] **2.5** — A WarpCenter-style bar (the default; a taskbar layout is a setting), a Squirrel menu, a tray clock.
- [ ] **2.6** — Desktop objects with icons, drag and drop between folders and onto programs, context menus on the right button, Warp-style settings notebooks with tabs, shadows (shortcuts).
- [ ] **2.7** — Long file names, FAT12/16/32 read and write for exchanging media, drive objects, a shredder object.

### 2.8–2.9 — 64-bit bridge

The old 2.1–2.9 bridge plan in `documentation/plannedmilestones.md`, renumbered here. 32-bit programs keep running in compatibility mode. The H boxes (with acceptance) are in `TODO.md`. The BIOS boot path keeps working throughout.

- [ ] x86-64 long-mode kernel and 64-bit paging
- [ ] SMP scheduler
- [ ] H.1 UEFI loader
- [ ] H.2 GOP text console
- [ ] H.3 AHCI
- [ ] H.4 NVMe
- [ ] H.5 USB keyboard (xHCI)
- [ ] H.6 USB storage
- [ ] 64-bit syscall ABI

### 3.0 — Generation 3: "NT / XP class" (3.0.0 is the 64-bit Warp)

- [ ] **3.0** — User accounts and a login screen, file permissions, services, an event log, a task manager, a theme engine (Warp 4 by default, plus original "Classic" and "Luna-like" themes), audio (HDA / AC97 and a mixer), a network settings GUI, DHCP, DNS and an HTTP client.

### 3.x — Generation 4: "Windows 7 / modern Unix desktops"

- [ ] **3.x** — A compositing window manager (off-screen windows, alpha, animation), GPU 2D acceleration (virtio-gpu first), desktop search, taskbar previews, virtual desktops, an optional dock or global menu bar, and several monitors.

### 4.x — Generation 5: "Windows 10/11 class"

- [ ] **4.x** — HiDPI scaling and a vector UI, touch input, a modern Settings app (the Warp notebooks stay as the "classic" view), a notification centre, accessibility (screen reader, high contrast, magnifier), a package manager with a store front-end, and signed updates.

### Built-in applications (A.1–A.7, parallel track, epic #115)

Each app is first built in squirrelsoft as a desktop program, then ported.

- [ ] **A.1** (2.1+) — Calculator with standard and scientific modes in a window (the existing `calc` / `sci` engines), Clock, Notepad (GUI `edit`)
- [ ] **A.2** (2.2+) — Paint (bitmap tools, palette, save as BMP or an own format), image viewer, character map
- [ ] **A.3** (2.3+) — Settings / Control Panel, File Manager, Terminal (several shells in windows)
- [ ] **A.4** (2.4+) — Debugger: process list, INT3 breakpoints, single step, registers, memory view, an original disassembler, symbols from SQX / ELF
- [ ] **A.5** (2.5+) — Task / system monitor (CPU, memory, processes, priorities), disk utility, log viewer
- [ ] **A.6** (3.0+) — Media player (WAV first), sound recorder, spectrum analyser (port of SquirrelSound)
- [ ] **A.7** (3.0+) — Text editor with syntax highlighting, hex editor, a simple word processor

### Games (G.1–G.9, epic #116)

Each has its rules core with unit tests in squirrelsoft first; card and board graphics are original.

- [x] **G.1** Solitaire (Klondike)
- [x] **G.2** FreeCell
- [x] **G.3** A Minesweeper-class game
- [x] **G.4** Hearts (three AI players)
- [x] **G.5** Chess (own alpha-beta engine, PGN)
- [ ] **G.6** Contract Bridge (bidding and play AI)
- [x] **G.7** Mahjongg solitaire
- [x] **G.8** Reversi
- [ ] **G.9** Checkers or Go (stretch)

### Calculator suite — Desmos and TI-Nspire class (C.1–C.9, epic #119)

- [ ] **C.1** — Expression engine v2: real and complex numbers, arbitrary-precision decimals, units, variables, user functions (a shared C core, `sqmath`, in squirrelsoft).
- [ ] **C.2** — 2D graphing: y = f(x), implicit, parametric, polar, inequalities, sliders, zoom and pan, trace, intersections, roots and extrema. This replaces the `graph` scaffold.
- [ ] **C.3** — Tables and lists, 1- and 2-variable statistics, regressions (linear, polynomial, exponential, logarithmic, power, logistic), histograms and box plots.
- [ ] **C.4** — A spreadsheet linked to graphs.
- [ ] **C.5** — CAS: simplify, expand, factor, solve, symbolic derivatives and integrals, limits, series.
- [ ] **C.6** — Geometry: points, lines, circles, constructions, measurements, dynamic dragging.
- [ ] **C.7** — 3D graphing: surfaces and parametric curves.
- [ ] **C.8** — Notebooks whose pages mix notes, graphs, geometry and spreadsheets; scripting in an original BASIC- or Lua-like interpreter.
- [ ] **C.9** — `topo` (topology / surveying calculator) and a matrix / linear-algebra GUI.

### Warp styling (W.1–W.6, every generation, epic #117)

- [ ] **W.1** — Warp 4 colour scheme, bevels and fonts (original bitmaps that give the feel, not copies).
- [ ] **W.2** — The Workplace Shell object model in the GUI: everything is an object with a settings notebook; a templates folder; drag a template to create an object.
- [ ] **W.3** — WarpCenter / LaunchPad bar.
- [ ] **W.4** — Folder views: icon, tree, details.
- [ ] **W.5** — Context menu "Open as → Icon / Tree / Details / Settings".
- [ ] **W.6** — Startup folder, Shredder, Drives and System Setup objects.

### Running other systems' programs (P.1–P.12, extends F.1–F.10, epic #118)

Foreign programs should show up as ordinary Squirrel windows.

Each P step ships a tiny original test binary in the tree and a regression `PASS`. All of them need 2.4 (ring 3) first.

- [ ] **P.1** (= F.1–F.4) — Linux static ELF32 (`write` / `exit`).
- [ ] **P.2** — Linux file I/O, `mmap`, `brk`, signals.
- [ ] **P.3** — Dynamic ELF with a glibc / musl loader, ELF64.
- [ ] **P.4** — An X11-protocol (or Wayland) server that maps foreign windows onto Squirrel windows.
- [ ] **P.5** (= F.5 / F.9) — Win32 PE console subset.
- [ ] **P.6** — Win32 GUI subset (USER / GDI onto the Squirrel window manager and graphics), registry emulation, an original DLL loader (a Wine-like design, no Wine code).
- [ ] **P.7** — PE64.
- [ ] **P.8** — A DOS personality (V86 mode or an emulator) for DOS programs in a window.
- [ ] **P.9** — OS/2 16/32-bit text-mode API (`DosWrite` and the like), optional and late.
- [ ] **P.10** — POSIX / Unix (Solaris, BSD) through the Linux layer plus syscall tables.
- [ ] **P.11** — Darwin Mach-O command-line programs (research).
- [ ] **P.12** (= F.10) — Sandbox and capability flags, plus seamless-window integration (taskbar, clipboard, drag and drop shared with native programs).

## Explicitly later

Not milestones yet. Where the 2.0.0 → 4.x plan above schedules something that used to be listed here, the plan wins.

- Foreign personalities F.1–F.10 are now P.1–P.12 above (`documentation/architecture/foreign-compatibility.md`). First PR of that era is still F.1.
- A full kernel on AArch64 or RISC-V. Early banners already exist (`documentation/architecture/early-kernel.md`). The working kernel stays x86 PC until a later roadmap says otherwise.
- Firmware-independence experiments (`documentation/architecture/firmware-independence.md`).
- Interrupt-driven ATA, a `/dev` tree, and loading driver *code* from programs (`documentation/kernel/drivers.md`). Run-time registration of a null char device is in 1.9.12; the polled IDE driver is enough for current QEMU.
- virtio-blk. `documentation/kernel/block-device.md` says the default IDE controller is enough.
- Journaling and Wi-Fi. Long file names are 2.7, SMP and UEFI are 2.8–2.9, a package manager is 4.x.
- Binary compatibility with classic OS/2 (SOM, MVDM, WIN-OS/2) stays out of scope. The one exception is P.9, an optional late personality for OS/2 16/32-bit text-mode programs.

## Speculative

Not tasks. Do not build these unless a later edit to this file promotes them.

- Symbolic algebra for `diff` or `topo` was speculative; it is now the C.5 CAS milestone of the calculator suite.

Promoted earlier into **1.9.9–1.9.12** (see `TODO.md` Warp gaps): priority scheduling, a polled mouse on the desktop, configurable IP addresses, and devices registered at run time.
