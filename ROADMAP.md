# Squirrel-OS/2 Roadmap

Forward plan from **0.9.2** (2026-10-31). Concrete work is in [TODO.md](TODO.md).

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
| **3.0.0** | A 64-bit system with the same character, aimed at everyday use. Optional foreign personalities (Linux, Windows, Darwin, Unix) stay out of the core. |

1.0.0 is released (2026-10-31, `documentation/releases/1.0.0.md`).
**2.0.0** is released (2026-11-01, `documentation/releases/2.0.0.md`).
Next are modern hardware H.1–H.6, then the 2.x / 3.0 vision.

## Principles

Every change follows these:

1. **Original code only.** No osFree, Voyager, classic OS/2, or other third-party OS sources in this tree. Firmware and contemporary code stay outside.
2. **Small, testable steps.** One coherent change per pull request. Prefer a change `tools/regress.sh` can check over a large rewrite.
3. **Docs updated in the same change.** Design note, release note when the version moves, and `documentation/README.md` when the current focus moves. New defects go in `documentation/knownbugs.md`.
4. **Base every PR on `main`.** Branch from current `main`. After `main` moves, rebase onto it.
5. **No stacked PRs.** Do not open a PR whose base is another feature branch. If task B needs task A, wait until A is merged, then branch B from `main`.

Also already true of this project: document hardware assumptions, keep accepted limits in `documentation/specifications.md`, and follow `documentation/releases/PROCESS.md`.

## Where 0.9.2 is

Done and covered by `tools/regress.sh`: boot and protected mode, PIT and keyboard, cooperative processes, `int 0x80`, ATA PIO, SQFS with directories, file browser, `calc` / `sci` / `matrix`, full-screen `edit` / `vedit` / `draw`, SQX and ELF32 loaders, user programs, pipes and redirection, line editing and history, batch files, page allocator and per-program address spaces, `SYS_SBRK`, driver table, localization (`en` / `la` / `tlh`), crash reports.

Still scaffolds or stated limits, on purpose:

- `graph` and `topo` print a scaffold message and return (`kernel/pm.asm`). `diff` does numerical derivatives (1.0.7), integrals (1.0.8) and Euler ODEs (1.0.10).
- `graph` waits for graphics primitives (milestone 1.3). The on-screen stub says so.
- `topo` is long-term and is not expected before 2.x (`documentation/apps/calculators.md`).
- Scheduling is cooperative. A process that never yields starves the others (milestone 1.1).
- The x87 state is not saved on a switch. Only one of `sci` or `matrix` should run at a time.
- There is no seek. Programs see file failures only as −1; the shell maps `fs_errno` to text.
- User code runs in ring 0. User mode and growing stacks are 2.x (`documentation/kernel/memory.md`).
- Since then, 0.9.3 fixed the banner (it said `0.2.3`), floppy boot, and the CPU check, and added build/run scripts and a Bochs smoke test (`documentation/releases/0.9.3.md`).
- `documentation/knownbugs.md` has no open defects (KB-1 through KB-10 are resolved).

## Milestones

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
- **1.9** — Pick up, move, and drop an object on the desktop. The keyboard does this. A mouse is not part of the plan.

### Installer (I.1–I.6) — unscheduled

Today the release images are the install: write `os.img` to a USB stick or `floppy.img` to a floppy, byte for byte, and boot it. A real installer boots from that media and copies the system onto the computer's own disk, so the stick can be removed. The boxes are in `TODO.md`. They run alongside the 1.6 desktop work (the author lifted the earlier gate on 2026-10-31), each ships in the next OS version, and none of them is a 2.0.0 requirement.

Assumptions the installer keeps: BIOS boot (Legacy/CSM), an IDE/ATA target disk reached through the existing polled driver, and SQFS as the installed file system. UEFI, AHCI/NVMe, and USB mass storage stay in 2.x.

### 2.0.0 — Warp-style system

Preemptive threads, the windowing system, the object desktop, the hierarchical file system with a graphical browser, the 1.0 applications as desktop objects, a native shell, and basic networking. Original code. No classic OS/2 ABI.

1.9 is on `main`, and networking through the small TCP client shipped in 1.9.3–1.9.8. Warp gaps 1.9.9–1.9.12 are on `main`. **2.0.0** tags that system (`documentation/releases/2.0.0.md`); the owner tags after merge.

### 2.x and 3.0.0

Kept in `documentation/plannedmilestones.md`: 64-bit bring-up, multi-core, UEFI, modern storage and USB, a 64-bit userland, the desktop ported forward, a fuller network, a package manager, then a 3.0.0 system aimed at daily use. User mode (ring 3) and growing stacks land in this era, as `documentation/kernel/memory.md` already says.

2.0.0's prerequisites are on `main`. Modern hardware H.1–H.6 may proceed; break further 2.x / 3.0 work into tasks as needed.

### Modern hardware (H.1–H.6) — unscheduled

Today the system boots the BIOS way and expects IDE/ATA disks, a PS/2-style keyboard, and VGA. Many new PCs have dropped Legacy/CSM boot, and their disks, keyboards, and displays sit behind controllers the kernel does not drive. This milestone is the concrete breakdown of 2.4 (UEFI) and 2.5 (modern storage and USB), plus a framebuffer display. The boxes are in `TODO.md`. None of them starts while a 1.x box is open; the BIOS path keeps working throughout.

## Explicitly later

These exist in the tree as scaffolds or notes. They are not milestones on the way to 1.0 or to the 1.x desktop:

- Foreign personalities F.1–F.10 (`documentation/plannedmilestones.md`, `documentation/architecture/foreign-compatibility.md`). Optional, and not before 2.0. First PR of that era is F.1.
- A full kernel on AArch64 or RISC-V. Early banners already exist (`documentation/architecture/early-kernel.md`). The working kernel stays x86 PC until a later roadmap says otherwise.
- Firmware-independence experiments (`documentation/architecture/firmware-independence.md`). Not a 1.0 requirement.
- Interrupt-driven ATA, a `/dev` tree, and loading driver *code* from programs (`documentation/kernel/drivers.md`). Run-time registration of a null char device is in 1.9.12; the polled IDE driver is enough for current QEMU.
- virtio-blk. `documentation/kernel/block-device.md` says the default IDE controller is enough.
- Journaling, long file names, SMP, UEFI, Wi-Fi, and a package manager. They belong to the 2.x / 3.0 table.
- Binary compatibility with classic OS/2 (SOM, MVDM, WIN-OS/2). Out of scope.

## Speculative

Not tasks. Do not build these unless a later edit to this file promotes them.

- A text-mode `graph` before milestone 1.3. The design mentions text-mode plots, and the running stub refuses to plot until graphics primitives exist. Follow the stub.
- Symbolic algebra for `diff` or `topo`. `diff` is numerical. `topo` stays a scaffold until 2.x.

Promoted into **1.9.9–1.9.12** (see `TODO.md` Warp gaps): priority scheduling, a polled mouse on the desktop, configurable IP addresses, and devices registered at run time.
