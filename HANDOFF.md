# Hand-off to Cursor / Codex (2026-11-14; ownership update 2026-11-15)

From 2026-11-14 the remaining Squirrel-OS/2 work is left for Cursor or Codex to
pick up. This file says what is done, what is in flight, and what is open,
with enough detail to start any open item cold. The suite-wide plan for what
comes after this list is
[squirrelsoft `docs/CONTINUANCE.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/CONTINUANCE.md).

Source of truth, in order: `ROADMAP.md` and `TODO.md` on `main`, then the
GitHub issues (epics #114–#119, progress issue #132, hand-off tracker #169), then
this file. If they disagree, `main`'s code wins; fix the docs in your PR.

## MERGE-WAIT (both lanes — Sarah 2026-11-15)

**No new implementation** (no ring-3 / syscall64 / W.6 / Soft). Keep gate PRs
#184 / #204 / #205 mergeable; then idle until tip-cut. Post-cut ladder paused
until Sarah/credits say go. Full freeze text lives on #205 `HANDOFF` when that
lands.

## Agent ownership (dual Cursor agents)

Two Cursor agents work this tree in parallel. Tag every owned task line with the
literal suffix **`-b55f`** or **`-2eaf`** (same as the branch suffix). Shared
files need coordinated rebases; do not race edits. Suite-wide checklist:
[squirrelsoft `docs/AGENT_LANES.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/AGENT_LANES.md).

**Living lane claims issue:** [#201](https://github.com/squirelworks/squirrel-os2/issues/201) (RPS over #200; see #202). Close #198/#199/#200 when convenient.

### Progress notes `-b55f`

- **Landed:** `2.9-lm-paging-b55f` (#193 / `lmpage`); `2.9-lm-stay-thunks-b55f` (#196 / `lmthunk`). **This PR / merge-wait:** `2.9-lm-boot64-b55f` (#204 / `lmboot` / `os-lm64.img`). **Paused after tip cut:** ring-3 under stay → `2.9-lm-kernel-tick-b55f` (only once everyday x86_64 suite flavour).

### Tasks `-b55f` (this lane)

- [x] `2.9-lm-stay-thunks-b55f` — permanent long-mode stay + compatibility thunks (`lmthunk`, #196)
- [ ] `2.9-lm-boot64-b55f` *(this PR #204 — merge-wait)* — boot-time / LM_BOOT64 image everyday stay; lmboot command
- [ ] `2.9-lm-kernel-tick-b55f` — tick `2.9-lm-kernel` in TODO/ROADMAP/#132 only after boot stay **and** ring-3 compat programs + full x86_64 suite flavour
- [ ] `2.9-syscall64-b55f` — ELF64 + `syscall`/`sysret` (`hello64`) after lm-kernel
- [ ] `soft-followups-b55f` — Soft follow-ups only if Sarah leaves notes on Soft
- [ ] `rebase-help-b55f` — when Sarah asks, rebase/CI-unblock open Sarah-held PRs (including `*-2eaf`); coordination only

### Progress notes `-2eaf`

- **Landed:** `W.2-templates-2eaf` (#191); `W.5-openas-2eaf` (#192); `W.3-launchpad-2eaf` (#183); `2.6-shadows-2eaf` (#188); Sarah Gen2 follow-ups (#197).
- **This PR:** `2.6-icons-2eaf` / `2.6-drag-2eaf` (#184).

### Tasks `-2eaf` (other lane)

- [x] `W.3-launchpad-2eaf` — PR #183
- [x] `2.6-icons-2eaf` / `2.6-drag-2eaf` — PR #184
- [x] `2.6-shadows-2eaf` — PR #188
- [x] `W.5-openas-2eaf` — PR #192
- [ ] `W.6-startup-2eaf` / `W.6-syssetup-2eaf` — claimed; start after 2.6 icons/shadows on `main`

**`-b55f` does not take** desktop/Warp boxes while `-2eaf` owns them.  
**`-2eaf` does not take** `2.9-lm-*-b55f` / `2.9-syscall64-b55f` while `-b55f` owns them.

**Shared hotspots:** `HANDOFF.md`, `TODO.md`, `ROADMAP.md`, `kernel/pm.asm`,
`tools/regress.sh`. Feature-private: `-b55f` → `kernel/lm.asm`, `kernel/vm.asm`,
`documentation/kernel/long-mode.md`; `-2eaf` → `kernel/warpcenter.asm`,
`kernel/launchpad.asm`, `kernel/deskicons.asm`, `kernel/desktop.asm`,
`kernel/shadow.asm`, `kernel/wps.asm`, `kernel/progman.asm`, `kernel/filemgr.asm`.

## Status legend

Used here, in `ROADMAP.md`, `TODO.md` and on the issues (as labels).

| Mark | Label | Meaning |
|------|-------|---------|
| `- [x]` | `status: done` | On `main`, covered by `tools/regress.sh`. |
| *(in progress)* | `status: in progress` | A branch or PR exists. Finish or rebase it; do not redo it. |
| `- [ ]` | `cursor-codex` | Open. Nobody is on it. Take it (respect Agent ownership above). |
| *(Squirrel)* | `needs: squirrel` | Only the owner can do it (tag/publish a release, real hardware, deleting branches). |

## Where things are

- **Released:** 2.1.0 (2026-11-13). **2.3.0** release notes are prepared
  (`documentation/releases/2.3.0.md`); the owner publishes the tag. `main`
  includes 2.2 real windows, 2.3 Program Manager / File Manager / clipboard /
  Control Panel / bevels, 2.4 ring 3, 2.7 long names + FAT + drive objects
  (diskutil view/check/format), 2.8 long-mode entry, SMP and PAE/NX, H.1–H.6,
  3.0 networking and sound, A.1–A.7, C.1–C.9, G.1–G.9, P.1, P.2, P.5, P.6
  (including Win32 windows), P.8 (including DOS window), P.9 (32-bit LX),
  P.10 (FreeBSD), 2.5 WarpCenter, 2.6-icons/drag (this PR),
  2.6-context/notebook, 2.6-shadows, W.2-templates, W.3-launchpad,
  W.4-views, W.5-openas, Sarah Gen2 follow-ups (#197), and the 2.9
  IDT/TSS stay + paging + thunk + boot64 slices (`lmstay` #189, `lmpage` #193,
  `lmthunk` #196, `lmboot64` #204). Dual-agent ownership docs are on `main`
  (#195 / #203). CI regress shards are on `main` (#220).
- **Test gate:** `tools/regress.sh` and GitHub CI (`.github/workflows/ci.yml`:
  `build` and `regress`, on every PR). Wait for a green `regress` before
  calling a PR ready.
- **Open PRs (2026-11-15):** #184 (this PR, `2.6-icons`/`2.6-drag`); tip-cut
  docs #205 (`-b55f`); lm-boot64 follow-up #222 (`-b55f`).
  (#183, #188, #191, #192, #193, #195, #196, #197, #203, #204, and #220 are on `main`.)

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

Lanes run in parallel (see **Agent ownership**). Within a lane, keep the order.

1. ~~Merge `int/os2-control`, **2.3-bevel-default**, then **2.3.0 release notes**.~~ Done (#168, #172, #173). Owner publishes `v2.3.0`.
2. ~~**2.7-diskutil** remainder~~ Done (#179). ~~**P.6 / P.8 windows**~~ Done (#177, #182).
3. **Generation 2 desktop `-2eaf`:** ~~**2.5-bar → 2.5-menu → 2.5-clock**~~ done
   (#181); ~~`W.3-launchpad-2eaf`~~ done (#183); ~~`2.6-icons-2eaf` →
   `2.6-drag-2eaf`~~ done (#184); ~~**2.6-context → 2.6-notebook**~~ done (#186);
   ~~`W.2-templates-2eaf`~~ done (#191); ~~**W.4-views**~~ done (#190);
   ~~`2.6-shadows-2eaf`~~ done (#188) → ~~`W.5-openas-2eaf`~~ done (#192); then
   `W.6-startup-2eaf` → `W.6-syssetup-2eaf`.
4. **2.9 path `-b55f`:** ~~**2.8-pae**~~ done (#180); ~~IDT/TSS stay~~ done
   (#189); ~~`2.9-lm-paging-b55f`~~ done (#193); ~~`2.9-lm-stay-thunks-b55f`~~
   done (#196); ~~`2.9-lm-boot64-b55f`~~ done (`lmboot` / `os-lm64.img`) →
   ring-3 compat under stay → `2.9-lm-kernel-tick-b55f` → `2.9-syscall64-b55f`.
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

### 2.5 / W.3 — WarpCenter, Squirrel menu, tray clock, LaunchPad  `status: done` (`-2eaf`)
- **Done on `main`:** **2.5-bar**, **2.5-menu**, **2.5-clock**
  (`kernel/warpcenter.asm`, `wcbar` / `wcmenu` / `wcclock` / `warpcenter`).
- **Done on `main` (`W.3-launchpad-2eaf`, #183):** LaunchPad pads on the
  shared WarpCenter top chrome; pads persist and launch → `wclp: PASS`.
- **Files:** `kernel/warpcenter.asm`, `kernel/launchpad.asm`, `kernel/progman.asm`,
  `kernel/wm.asm`, `documentation/apps/desktop.md`.
- **Acceptance:** bar pixel probe `wc-bar: PASS`; menu maps to `calc`
  `wc-menu: PASS`; tray clock ticks after an RTC step `wc-clock: PASS`;
  LaunchPad pads persist and launch `wclp: PASS`.

### 2.6 / W.2 / W.4 / W.5 — Icons, drag/drop, menus, notebooks, shadows, views  `-2eaf`
- **Done on this work / `main`:** **2.6-icons**, **2.6-drag** (`kernel/deskicons.asm`,
  `dkicons` / `dkdrag`; File class + Program `drop` in `desktop.asm`, #184);
  **2.6-context**, **2.6-notebook** (`dkctx` / `nbtest`); **W.4-views**
  (`foldview` / `fold-views`, #190); **W.2-templates** (`kernel/wps.asm`:
  Templates folder, Template class, drag/drop create, settings notebook;
  `wpstmpl` / `wps-tmpl`, #191). **W.5-openas** — context menu Open as →
  Icon / Tree / Details / Settings on File Manager folders and on Program
  Manager objects (`fm_openas_*` / `pm_openas_*`); self-check `openas` →
  `openas: PASS`. **2.6-shadows** (`kernel/shadow.asm`, object-file links under
  `/desktop`; rename/move of the original updates Shadow `target` / `at`;
  `dkshadow` → `dk-shadow: PASS`, #188).
- **Files:** `kernel/deskicons.asm`, `kernel/desktop.asm`, `kernel/progman.asm`,
  `kernel/shadow.asm`, `kernel/object.asm`, `kernel/wps.asm`, `kernel/widget.asm`,
  `kernel/wm.asm`, `kernel/filemgr.asm`, `kernel/pm.asm`,
  `documentation/apps/desktop.md`, `documentation/apps/progman.md`,
  `documentation/apps/filemgr.md`, `documentation/kernel/widgets.md`,
  `documentation/kernel/objects.md`.
- **Acceptance (done):** icon pixel probe `dk-icons: PASS`; file-on-program
  drag `dk-drag: PASS`; right-click menu `dk-ctx: PASS`; notebook tabs
  `nbtest: PASS`; folder Icon/Tree/Details `foldview: PASS`; templates create
  objects `wps: PASS`; "Open as → …" `openas: PASS`; shadow follows rename
  across reboot `dk-shadow: PASS`.

### W.6 — Startup and System Setup (with 2.6 + 2.7-objects)  `-2eaf` (claimed)
- **Split done:** `TODO.md` boxes `W.6-startup-2eaf`, `W.6-syssetup-2eaf`.
  Drive and Shredder classes are already on `main` (**2.7-objects**); this
  card wires Startup and System Setup into the Generation-2 desktop.
- **Files:** `kernel/desktop.asm`, `kernel/fsobj.asm`, `kernel/object.asm`,
  `documentation/apps/desktop.md`, `documentation/kernel/fat.md`.
- **Acceptance:** Startup opens its contents at desktop start `startup: PASS`;
  System Setup opens setup entry points and Drive/Shredder behave as desktop
  objects `syssetup: PASS`.

### 2.8-pae — PAE paging and NX  `status: done`
PAE + NX on `main`. Checks `nx-heap`, `nx-stack`, `cpu-pentium3`.

### 2.9-lm-kernel — stay in long mode  `-b55f` (boot64 landed; box still open)
- **Depends on:** 2.8-pae (done on `main`, #180).
- **What:** 64-bit IDT/TSS with IST for double faults, 4-level per-process
  address spaces, the 32-bit kernel reached through compatibility-mode
  thunks, 32-bit programs in compatibility mode.
- **Acceptance:** the whole `regress.sh` passes under `qemu-system-x86_64`
  with the long-mode kernel; the BIOS boot path still boots under `qemu-system-i386`
  with the 32-bit kernel (two build flavours, both in CI).
- **Done on `main` / this slice:** IDT/TSS stay (`lmstay`, #189); 4-level
  paging (`lmpage`, #193); permanent stay + thunks (`lmthunk`, #196);
  boot64 everyday stay (`lmboot` / `os-lm64.img`): nestable `lm64_call32`,
  everyday IRQ0/1/12 + `int 0x80` gates, `lm_enter_everyday` / `lm_boot_enter`.
  Regress names: lm-boot, lm-boot-again, lm-boot64, lm-boot64-again, and the
  -nolm pair. `systest` + `lmtest` pass on the boot64 image under
  `qemu-system-x86_64`.
- **Still open before ticking:** 32-bit ring-3 programs under permanent stay
  (exception trampolines / return paths — `run hello` on `os-lm64.img` is not
  green); whole suite as the everyday x86_64 flavour. Then
  `2.9-lm-kernel-tick-b55f`.
- **CONTINUANCE 3a (recorded):** freestanding C for new 2.9+ subsystems
  (`-ffreestanding -mno-red-zone -fno-pic`); NASM for boot/entry stubs. See
  `documentation/architecture/overview.md` and squirrelsoft
  `docs/CONTINUANCE.md` decision 3a. Non-blocking: clear busy on the saved TR
  under SMP; `kernel_pml4` is boot-lifetime.

### 2.9-syscall64 — ELF64 programs  `2.9-syscall64-b55f` (after lm-kernel)
- **Depends on:** 2.9-lm-kernel.
- **Acceptance:** `run hello64` prints `hello64: PASS` through
  `syscall`/`sysret`; `int 0x80` 32-bit programs are unchanged; pointer
  checks refuse kernel addresses (`hello64-badptr`).
- **Also (#221):** Linux/BSD under permanent stay still get `-ENOSYS` from
  `lm64_syscall_isr` (`lx_isr` is `iretd`-only); teach a returnable body.

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
