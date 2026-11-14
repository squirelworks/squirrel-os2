# Hand-off to Cursor / Codex (2026-11-14)

From 2026-11-14 the remaining Squirrel-OS/2 work is left for Cursor or Codex to
pick up. This file says what is done, what is in flight, and what is open,
with enough detail to start any open item cold. The suite-wide plan for what
comes after this list is
[squirrelsoft `docs/CONTINUANCE.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/CONTINUANCE.md).

Source of truth, in order: `ROADMAP.md` and `TODO.md` on `main`, then the
GitHub issues (epics #114–#119, progress issue #132, hand-off tracker), then
this file. If they disagree, `main`'s code wins; fix the docs in your PR.

## Status legend

Used here, in `ROADMAP.md`, `TODO.md` and on the issues (as labels).

| Mark | Label | Meaning |
|------|-------|---------|
| `- [x]` | `status: done` | On `main`, covered by `tools/regress.sh`. |
| *(in progress)* | `status: in progress` | A branch or PR exists. Finish or rebase it; do not redo it. |
| `- [ ]` | `cursor-codex` | Open. Nobody is on it. Take it. |
| *(Squirrel)* | `needs: squirrel` | Only the owner can do it (tag/publish a release, real hardware, deleting branches). |

## Where things are

- **Released:** 2.1.0 (2026-11-13). **2.3.0** release notes are prepared
  (`documentation/releases/2.3.0.md`); the owner publishes the tag. `main`
  includes 2.2 real windows, 2.3 Program Manager / File Manager / clipboard /
  Control Panel / bevels, 2.4 ring 3, 2.7 long names + FAT + drive objects
  (diskutil view/check/format), 2.8 long-mode entry and SMP, H.1–H.6, 3.0 networking
  and sound, A.1–A.7, C.1–C.9, G.1–G.9, P.1, P.2, P.5, P.6 (GUI, registry,
  DLLs), P.8 (dosrun, launch, mode 13h), P.9 (32-bit LX), P.10 (FreeBSD).
- **Test gate:** `tools/regress.sh` (558 `check` lines at 2.3.0) and GitHub CI
  (`.github/workflows/ci.yml`: `build` and `regress`, on every PR). Wait for
  a green `regress` before calling a PR ready.
- **Open PRs:** none at the 2.3.0 prep. Take the next free box in the order
  below; if a competing PR appears, stand down.

## Rules (Squirrel's; do not break)

1. Base every PR on `main`. Never stack a branch on another feature branch;
   if B needs A, wait for A to merge. Group functionally related boxes into
   one sizeable PR rather than one PR per box. Before finishing, confirm the
   PR targets `main` and GitHub shows it mergeable with CI green.
2. Original code only: no osFree, classic OS/2, Linux, Wine, ReactOS, DOSBox
   or other OS sources. Public specs are fine; cite them in the design note.
3. Every behaviour change gets a `check` in `tools/regress.sh` (GUI checks
   read pixels back and print `PASS`; never rely on screenshots).
4. Docs move with the code: design note under `documentation/`, the box in
   `TODO.md` and `ROADMAP.md`, the matching line on #132.
5. New user-visible strings go in `localization/en`, `la` and `tlh`, then
   `python3 tools/mkstrings.py` regenerates `kernel/strings.inc`.
6. Only Squirrel tags and publishes releases. When a release is ready, hand
   over finished release notes in `documentation/releases/X.Y.Z.md`, one
   prefilled `releases/new?...` link and the assets; not a list of steps.
7. Never merge `klingon-font*` branches. Never delete branches (Squirrel's call).

## Build and test

```sh
sudo apt-get install nasm qemu-system-x86 python3 python3-numpy ovmf
tools/build.sh            # build/os.img, floppy.img, cd.iso, uefi.img, data.img
tools/regress.sh          # the whole QEMU regression run; prints the ok count
qemu-system-i386 -drive file=build/os.img,format=raw -drive file=build/data.img,format=raw
```

`tools/qemu_screen.py` drives a scripted session and reads the screen
(text mode, 5x7 and proportional framebuffer fonts). Copy an existing
`check` in `regress.sh` that is closest to your feature.

## Suggested order

1. ~~Merge `int/os2-control`, **2.3-bevel-default**, then **2.3.0 release notes**.~~ Done (#168, #172, and the 2.3.0 prep PR). Owner publishes `v2.3.0`.
2. ~~**2.7-diskutil** remainder (in-OS FAT format; #171 shipped view/check without ticking the box).~~ Done (format FAT12/16/32 from `diskutil`).
3. **Generation 2 desktop** from the split boxes in `TODO.md`: **2.5-bar →
   2.5-menu → 2.5-clock → W.3-launchpad**, then **2.6-icons → 2.6-drag →
   2.6-context → 2.6-notebook → 2.6-shadows → W.2-templates → W.4-views →
   W.5-openas**, then **W.6-startup → W.6-syssetup** (W.6 needs 2.6 + 2.7-objects).
4. **2.8-pae → 2.9-lm-kernel → 2.9-syscall64** (the 64-bit kernel; largest risk).
5. **3.0** remainder (accounts, permissions, services, event log, task manager, themes).
6. **P.3, P.4, P.7, P.11, P.12**, then 3.x and 4.x.

## Task cards

### 2.3-bevel-default — Warp bevels on every widget  `status: done`
Merged as #172.

### 2.3.0 release notes  `needs: squirrel` (prep done)
- Prep: `documentation/releases/2.3.0.md`, PROCESS row, banner `2.3.0`,
  README / ROADMAP / HANDOFF / TODO **2.3.0** box. Owner runs
  Actions → Draft release on the merge commit and Publishes `v2.3.0`
  with `os.img`, `floppy.img`, `data.img`, `cd.iso`, `uefi.img`.

### 2.7-diskutil — FAT and long names in `diskutil`  `status: done`
View/check shipped as #171; format FAT12/16/32 from the OS completes the box.
`run diskutil format hd2 12|16|32`, `run diskutil test format hd2 N`, and GUI
`F` then `Y`. Checks `diskutil-fmt12` / `16` / `32`, `diskutil-fmt-gui`,
host `fatimg.py check`, and `fattest` on the formatted images.

### P.6-win32-windows — Win32 top-level windows as desktop windows  `done (this branch)`
- **What:** `CreateWindowEx` top-level windows from `programs/wingui.inc`
  become real 2.2 windows (title bar, move, z-order, close → `WM_CLOSE`),
  instead of drawing through the full-screen `SYS_GUI` surface.
- **Files:** `programs/winrun.asm`, `programs/wingui.inc`, `kernel/winsys.asm`,
  `kernel/wm.asm`, `documentation/architecture/foreign-compatibility.md`.
- **Acceptance:** `winwnd` shows in the window list with its title; a scripted
  click on its close box delivers `WM_CLOSE` and the program prints
  `winwnd: PASS`. Native windows keep working (`progwin`).

### P.8-dos-window — DOS screen in its own window  `status: done`
- Follow-up after #177: 1x/2x `WD_SBLIT`, text window (`win`), cursor/flush
  fix; checks `dos-win`, `dos-win-2x`, `dos-win-text`.

### 2.5 / W.3 — WarpCenter, Squirrel menu, tray clock, LaunchPad  `cursor-codex`
- **Done on this work:** **2.5-bar**, **2.5-menu**, **2.5-clock**
  (`kernel/warpcenter.asm`, `wcbar` / `wcmenu` / `wcclock` / `warpcenter`).
- **Still open:** **W.3-launchpad** (pads that persist and launch → `wclp: PASS`).
- **Files:** `kernel/warpcenter.asm`, `kernel/progman.asm`, `kernel/wm.asm`,
  `documentation/apps/desktop.md`.
- **Acceptance (done):** bar pixel probe `wc-bar: PASS`; menu maps to `calc`
  `wc-menu: PASS`; tray clock ticks after an RTC step `wc-clock: PASS`.

### 2.6 / W.2 / W.4 / W.5 — Icons, drag/drop, menus, notebooks, shadows, views  `cursor-codex`
- **Split done:** `TODO.md` boxes **2.6-icons**, **2.6-drag**, **2.6-context**,
  **2.6-notebook**, **2.6-shadows**, **W.2-templates**, **W.4-views**,
  **W.5-openas**. Start after **2.5-bar**.
- **Files:** `kernel/desktop.asm`, `kernel/progman.asm`, `kernel/object.asm`,
  `kernel/wm.asm`, `kernel/widget.asm` (notebook tabs are a new widget),
  `documentation/apps/desktop.md`, `documentation/kernel/widgets.md`.
- **Acceptance:** icon pixel probe `dk-icons: PASS`; file-on-program drag
  `dk-drag: PASS`; right-click menu `dk-ctx: PASS`; notebook tabs `nbtest: PASS`;
  shadow follows rename across reboot `dk-shadow: PASS`; templates create
  objects `wps: PASS`; folder Icon/Tree/Details `foldview: PASS`;
  "Open as → …" `openas: PASS`.

### W.6 — Startup and System Setup (with 2.6 + 2.7-objects)  `cursor-codex`
- **Split done:** `TODO.md` boxes **W.6-startup**, **W.6-syssetup**. Drive and
  Shredder classes are already on `main` (**2.7-objects**); this card wires
  Startup and System Setup (and those two) into the Generation-2 desktop.
- **Files:** `kernel/desktop.asm`, `kernel/fsobj.asm`, `kernel/object.asm`,
  `documentation/apps/desktop.md`, `documentation/kernel/fat.md`.
- **Acceptance:** Startup opens its contents at desktop start `startup: PASS`;
  System Setup opens setup entry points and Drive/Shredder behave as desktop
  objects `syssetup: PASS`.

### 2.8-pae — PAE paging and NX  `cursor-codex`
- **Files:** `kernel/vm.asm`, `kernel/mm.asm`, `kernel/lm.asm`,
  `documentation/kernel/memory.md`, `documentation/kernel/long-mode.md`.
- **Acceptance:** the 32-bit kernel runs on PAE (64-bit entries, PDPT);
  a ring-3 program that jumps into its heap or stack is ended with a
  page-fault report (`nx-heap`, `nx-stack` checks); the whole suite passes
  with PAE on; CPUs without NX keep working (`-cpu pentium3` check).

### 2.9-lm-kernel — stay in long mode  `cursor-codex`
- **Depends on:** 2.8-pae.
- **What:** 64-bit IDT/TSS with IST for double faults, 4-level per-process
  address spaces, the 32-bit kernel reached through compatibility-mode
  thunks, 32-bit programs in compatibility mode.
- **Acceptance:** the whole `regress.sh` passes under `qemu-system-x86_64`
  with the long-mode kernel; the BIOS boot path still boots under `qemu-system-i386`
  with the 32-bit kernel (two build flavours, both in CI).
- **Advice:** do it in steps that each keep CI green (IDT first, then paging,
  then thunks). **CONTINUANCE 3a (recorded):** new 2.9+ subsystems may use
  freestanding C (`-ffreestanding -mno-red-zone -fno-pic`) linked into the
  flat image; keep NASM for boot/entry stubs and existing code. See
  `documentation/architecture/overview.md` (Language for new kernel
  subsystems) and squirrelsoft `docs/CONTINUANCE.md` decision 3a.

### 2.9-syscall64 — ELF64 programs  `cursor-codex`
- **Depends on:** 2.9-lm-kernel.
- **Acceptance:** `run hello64` prints `hello64: PASS` through
  `syscall`/`sysret`; `int 0x80` 32-bit programs are unchanged; pointer
  checks refuse kernel addresses (`hello64-badptr`).

### 3.0 remainder — accounts, permissions, services, event log, task manager, themes  `cursor-codex`
- Networking (DHCP, DNS, HTTP, netcfg) and audio (AC'97, HDA, mixer, A.6 apps)
  are done. Split the rest into boxes first: `3.0-users` (login screen,
  `/etc`-style account file, hashed passwords), `3.0-perms` (owner and mode
  on SQFS entries, checked in `fs.asm`), `3.0-services` (start at boot,
  restart on crash), `3.0-eventlog` (kernel + service log, viewed by the
  existing log viewer), `3.0-taskmgr` (end task, priorities, CPU per CPU
  from SMP), `3.0-themes` (Warp 4 default, "Classic" and a Luna-like theme
  through `theme.inc` tables).

### P.3, P.4, P.7, P.9-16, P.10, P.11, P.12 — more foreign programs  `cursor-codex`
- **P.3** dynamic ELF (an original `ld.so`-style loader for musl first,
  then glibc) and ELF64 (needs 2.9-syscall64).
- **P.4** an X11 protocol server subset mapping X windows onto Squirrel windows
  (start with `xeyes`-class core requests over a Unix socket).
- **P.7** PE64 (needs 2.9-syscall64).
- **P.9-16** 16-bit NE OS/2 text-mode programs in `os2run` (16-bit DOSCALLS entry points through 16:16 thunks).
- **P.10** Solaris and NetBSD/OpenBSD i386 call tables over the Linux handlers, as FreeBSD's.
- **P.11** Darwin Mach-O command-line programs (research note first).
- **P.12** sandbox and capability flags per personality; clipboard and
  drag-and-drop shared with native windows.
- Each ships a tiny hand-written test binary in `programs/` and a `PASS` check.

### 3.x and 4.x  `cursor-codex` (later)
As written in `ROADMAP.md`. Split into boxes when 3.0 is released.

### Housekeeping
- Stale `ws/*` branches that are ahead of `main` but superseded:
  `ws/os2-apps/apps-4`, `ws/os2-gui/plan-2.2-2.3`, `ws/os2-net-audio/audio`,
  `ws/os2-net-audio/net-dhcp-dns-http`. Their work is on `main` through the
  condensed PRs; check with `git log main..BRANCH` before reusing anything.
  Do not delete them (Squirrel's call).
