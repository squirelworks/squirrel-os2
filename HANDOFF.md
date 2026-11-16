# Hand-off to Cursor / Codex (2026-11-14; ownership update 2026-11-15; tip-cut roadmap 2026-11-15; merge-wait 2026-11-15)

From 2026-11-14 the remaining Squirrel-OS/2 work is left for Cursor or Codex to
pick up. This file says what is done, what is in flight, and what is open,
with enough detail to start any open item cold. The suite-wide plan for what
comes after this list is
[squirrelsoft `docs/CONTINUANCE.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/CONTINUANCE.md).

## MERGE-WAIT (both lanes — Sarah 2026-11-15)

**`-b55f` and `-2eaf` are frozen on new implementation.** No ring-3-under-stay,
no `2.9-syscall64`, no W.6 startup/syssetup, no new Soft work, no version bumps.
Finish only what keeps the remaining **gate PR** merge-ready (#205; ~~#184~~ /
~~#197~~ / ~~#204~~ already on `main`), then **idle / watch CI** until it lands
and the owner tip-cuts `v2.3.0`. Post-cut ladder work stays paused until Sarah /
credits say go.

Source of truth, in order: `ROADMAP.md` and `TODO.md` on `main`, then the
GitHub issues (epics #114–#119, progress issue #132, hand-off tracker #169), then
this file. If they disagree, `main`'s code wins; fix the docs in your PR.

## Agent ownership (dual Cursor agents)

Two Cursor agents work this tree in parallel. Tag every owned task line with the
literal suffix **`-b55f`** or **`-2eaf`** (same as the branch suffix). Shared
files need coordinated rebases; do not race edits. Suite-wide checklist:
[squirrelsoft `docs/AGENT_LANES.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/AGENT_LANES.md).

**Living lane claims issue:** [#201](https://github.com/squirelworks/squirrel-os2/issues/201) (RPS over #200; see #202). Close #198/#199/#200 when convenient.

**Agent GitHub write path (2026-11-15):** Cloud agent `gh` uses a GitHub App installation token (`cursor[bot]` / `ghs_…`). **Works:** `gh issue create` (title/body only — labels are silently dropped), git push / open PRs. **Fails with 403** (`Resource not accessible by integration`): issue/PR comments (`addComment`), edit issue/PR body, close issues, add/change labels. Do **not** ask Sarah to paste comments or file issues — create a new issue or land text in-repo (HANDOFF / TODO / this PR). Tip-cut handshake stand-in for a #201 comment: [#208](https://github.com/squirelworks/squirrel-os2/issues/208). Filed ladder issues: #209–#218. **No Sarah action required for this coordination sync.**

### Progress notes `-b55f`

- **Landed:** `2.9-lm-paging-b55f` (#193 / `lmpage`); `2.9-lm-stay-thunks-b55f` (#196 / `lmthunk`); `2.9-lm-boot64-b55f` (#204 / `lmboot` / `os-lm64.img` / `LM_BOOT64`); lm-boot64 follow-ups (#222 / nest EOI, nestable thunks, syscall return, `#221` ENOSYS note); tip-cut / MERGE-WAIT docs (#205).
- **ISM ground station (#225):** gap matrix landed in-tree —
  `documentation/guides/ism-flightlab-gaps.md` (**ISM-gaps-b55f**). Next slices:
  serial/USB → soft-RT HIL timing → package Flight Lab → lab setup guide.
  Soft Flight Lab lives in `squirrelsoft/squirrelflightlab/` (S7.1–S7.2b on Soft
  `main`); OS/2 hosts only — no FCC laws here.
- **Paused until Sarah/credits say go (after tip cut):** ring-3 under stay (`2.3.2`, #211) → `2.9-lm-kernel-tick-b55f` (`2.9.0`) → `2.9-syscall64-b55f` (`2.9.1`).
  Exception: Sarah’s #225 ISM ground-station sequence is active for `-b55f`.

### Tasks `-b55f` (this lane)

- [x] `2.9-lm-stay-thunks-b55f` — permanent long-mode stay + compatibility thunks (#196)
- [x] `2.9-lm-boot64-b55f` — boot-time / `LM_BOOT64` everyday long-mode stay (`lmboot` command, os-lm64.img, #204)
- [x] `ISM-gaps-b55f` — #225 item 1 gap matrix (`documentation/guides/ism-flightlab-gaps.md`)
- [ ] `ISM-serial-b55f` — #225 item 2 serial/USB data path (after gaps)
- [ ] `ISM-hil-timing-b55f` — #225 item 3 soft-RT HIL timing
- [ ] `ISM-flightlab-pkg-b55f` — #225 item 4 package Soft Flight Lab
- [ ] `ISM-lab-setup-b55f` — #225 item 5 lab setup guide
- [ ] `2.9-lm-kernel-tick-b55f` — **paused** until tip cut + Sarah/credits go
- [ ] `2.9-syscall64-b55f` — **paused** until tip cut + Sarah/credits go
- [ ] `soft-followups-b55f` — Soft follow-ups only if Sarah leaves notes on Soft
- [ ] `rebase-help-b55f` — when Sarah asks, rebase/CI-unblock open Sarah-held PRs (including `*-2eaf`); coordination only

### Progress notes `-2eaf`

- **Landed:** `W.2-templates-2eaf` (#191); `W.5-openas-2eaf` (#192); `W.3-launchpad-2eaf` (#183); `2.6-shadows-2eaf` (#188); Sarah Gen2 follow-ups (#197); `2.6-icons-2eaf` / `2.6-drag-2eaf` (#184).
- **Paused until Sarah/credits say go (after tip cut):** `W.6-startup-2eaf` (`2.3.1`, #209) → `W.6-syssetup-2eaf` (`2.3.25`, #210) → Gen2 ship `2.6.0`.

### Tasks `-2eaf` (other lane)

- [x] `W.3-launchpad-2eaf` — PR #183
- [x] `2.6-icons-2eaf` / `2.6-drag-2eaf` — PR #184
- [x] `2.6-shadows-2eaf` — PR #188
- [x] `W.5-openas-2eaf` — PR #192
- [ ] `W.6-startup-2eaf` / `W.6-syssetup-2eaf` — claimed (#209 / #210); **paused** until tip cut + Sarah/credits go

**`-b55f` does not take** desktop/Warp boxes while `-2eaf` owns them.  
**`-2eaf` does not take** `2.9-lm-*-b55f` / `2.9-syscall64-b55f` while `-b55f` owns them.

**Shared hotspots:** `HANDOFF.md`, `TODO.md`, `ROADMAP.md`, `kernel/pm.asm`,
`tools/regress.sh`. Feature-private: `-b55f` → `kernel/lm.asm`, `kernel/vm.asm`,
`documentation/kernel/long-mode.md`; `-2eaf` → `kernel/warpcenter.asm`,
`kernel/launchpad.asm`, `kernel/deskicons.asm`, `kernel/desktop.asm`,
`kernel/shadow.asm`, `kernel/wps.asm`, `kernel/progman.asm`, `kernel/filemgr.asm`.

## Release coordination (2026-11-15, lane `-b55f` — tip cut)

**Supersedes** the earlier advice to publish `v2.3.0` from prep commit `fc3ae21` alone.

**Plan (Sarah):** finish the open agent PRs **now**, then the owner tags/publishes **`v2.3.0` from that tip** of `main`. Notes are retargeted so they match the tip (Gen2 + LM slices included). Long-form ladder: [`documentation/releases/TO_3.0.0.md`](documentation/releases/TO_3.0.0.md) (**canonical**; Soft `PATH_TO_3.0.0.md` is not the OS ladder).

| Fact | Value |
|------|-------|
| Last published tag | `v2.1.0` (2026-11-13) |
| Banner on `main` | `2.3.0` (`kernel/pm.asm` `banner_rest`) — stays for the tip cut |
| Prep | #173 landed the first `2.3.0.md`; **retarget** that file for the tip |
| Tag target | `main` HEAD **after** gate PRs merge — **not** `fc3ae21` |
| Gate PRs (must land first) | ~~#184 icons/drag~~ (**merged**); ~~#197 Gen2 follow-ups~~ (**merged**); ~~#204 lm-boot64~~ (**merged**); #205 this docs/roadmap (`-b55f`) |

**Handshake (`-b55f` ↔ `-2eaf`):**

1. **Both lanes — MERGE-WAIT now:** no new feature code. Keep remaining gate PR #205 clean vs `main` and CI-green. When it is on `main`, owner tip-cuts; do **not** start W.6 / ring-3 / syscall64 until Sarah/credits say go (those marks are **post**-2.3.0 — see TO_3.0.0).
2. **Owner (Squirrel):** after the tip is green, Draft release on that commit → Publish `v2.3.0` with `os.img`, `floppy.img`, `data.img`, `cd.iso`, `uefi.img`. Prefill (replace `TIP_SHA` after merge): [releases/new v2.3.0](https://github.com/squirelworks/squirrel-os2/releases/new?tag=v2.3.0&title=Squirrel-OS%2F2%202.3.0%20%E2%80%94%20tip%20after%20open%20PRs&body=See%20documentation%2Freleases%2F2.3.0.md%20on%20main%20tip%20after%20%23184%20%23197%20%23204%20%23205.%0A%0ATag%20target%3A%20TIP_SHA%20%28not%20fc3ae21%29.%0A%0AAssets%20from%20Actions%20Draft%20release%20on%20that%20commit.).
3. **`-2eaf` after tip (paused):** `W.6-startup-2eaf` (#209) → `W.6-syssetup-2eaf` (#210) → Gen2 ship `2.6.0` (owner) → later `3.0-taskmgr` (#217) / `3.0-themes` (#218).
4. **`-b55f` after tip (paused):** ring-3 under stay (#211) → `2.9-lm-kernel-tick-b55f` (`2.9.0`) → `2.9-syscall64-b55f` → freestanding C (#212) → `3.0-users`…`3.0-eventlog` (#213–#216). Soft only if Sarah notes.
5. Agents **never** tag. Visible tip-cut mirror (agents cannot comment on #201): [#208](https://github.com/squirelworks/squirrel-os2/issues/208). **No Sarah paste / issue-filing required.**

## Status legend

Used here, in `ROADMAP.md`, `TODO.md` and on the issues (as labels).

| Mark | Label | Meaning |
|------|-------|---------|
| `- [x]` | `status: done` | On `main`, covered by `tools/regress.sh`. |
| *(in progress)* | `status: in progress` | A branch or PR exists. Finish or rebase it; do not redo it. |
| `- [ ]` | `cursor-codex` | Open. Nobody is on it. Take it (respect Agent ownership above). |
| *(Squirrel)* | `needs: squirrel` | Only the owner can do it (tag/publish a release, real hardware, deleting branches). |

## Where things are

- **Released:** 2.1.0 (2026-11-13). **Next cut:** `v2.3.0` from **tip after
  gate PRs** (~~#184~~ / ~~#197~~ / ~~#204~~ / #205) — see **Release
  coordination**. Path to 3.0.0:
  [`documentation/releases/TO_3.0.0.md`](documentation/releases/TO_3.0.0.md).
  `main` includes 2.2–2.3 GUI, 2.4 ring 3, 2.7 FAT/LFN, 2.8 LM entry/SMP/PAE,
  H.1–H.6, 3.0 net/audio, apps/games/calc, foreign P.1/P.2/P.5/P.6/P.8/P.9/P.10,
  2.5 WarpCenter, Gen2 slices through icons/drag (#184), shadows/templates/
  views/openas, Sarah Gen2 follow-ups (#197), and 2.9 IDT/paging/thunks +
  boot64 (`lmstay` #189, `lmpage` #193, `lmthunk` #196, `lmboot` /
  `os-lm64.img` #204) + lm-boot64 follow-ups (#222). Dual-agent ownership on
  `main` (#195 / #203). CI regress shards on `main` (#220).
- **Test gate:** `tools/regress.sh` and GitHub CI (`.github/workflows/ci.yml`:
  `build` and `regress`, on every PR). Wait for a green `regress` before
  calling a PR ready.
- **Open PRs (2026-11-15, merge-wait / tip-cut gate):** #205 (release-coord /
  TO_3.0.0 docs, `-b55f`). (#183, #184, #188, #191, #192, #193, #195, #196,
  #197, #203, #204, #220, and #222 on `main`.)

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

1. ~~Merge `int/os2-control`, **2.3-bevel-default**, first **2.3.0** prep.~~ Done
   (#168, #172, #173). **Retarget + tip cut** after gate PRs (see **Release
   coordination** and `TO_3.0.0.md` M0).
2. ~~**2.7-diskutil** remainder~~ Done (#179). ~~**P.6 / P.8 windows**~~ Done (#177, #182).
3. **Generation 2 desktop `-2eaf`:** ~~**2.5-***~~ / ~~W.3~~ / ~~context/notebook~~ /
   ~~templates/views/shadows/openas~~ / ~~#197~~ / ~~`2.6-icons`/`drag` #184~~
   done → **tip cut** (#205) → then **pause** until Sarah/credits go →
   `W.6-startup` → `W.6-syssetup` → Gen2 ship `2.6.0`.
4. **2.9 path `-b55f`:** ~~pae / IDT / paging / thunks~~ done; ~~`2.9-lm-boot64`~~
   done (#204 / `lmboot` / `os-lm64.img`; follow-ups #222) → **tip cut** → then **pause** until
   Sarah/credits go → ring-3 under stay → `2.9-lm-kernel-tick` (`2.9.0`) →
   `2.9-syscall64` → freestanding C → Gen3 kernel boxes.
5. **3.0** remainder → `v3.0.0` (see `TO_3.0.0.md` M10–M16).
6. **P.3, P.4, P.7, P.11, P.12**, then 3.x and 4.x (parallel after syscall64;
   not required for the 3.0.0 ship gate unless the owner expands it).

## Task cards

### 2.3-bevel-default — Warp bevels on every widget  `status: done`
Merged as #172.

### 2.3.0 release notes  `needs: squirrel` (retarget for tip cut; tag still open)
- First prep: #173 / banner `2.3.0`. **Retarget** `documentation/releases/2.3.0.md`
  so notes match **tip after** #184 + #197 + #204 (+ #205 docs).
- **Tag target:** `main` HEAD after those merges — **not** `fc3ae21`.
- Ladder after the cut: [`documentation/releases/TO_3.0.0.md`](documentation/releases/TO_3.0.0.md).
- Owner: Actions → Draft release on tip → Publish `v2.3.0`. Prefill in
  **Release coordination** (insert tip SHA when known).

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

### 2.9-lm-kernel — stay in long mode  `-b55f` (boot64 #204 + #222 landed; box still open)
- **Depends on:** 2.8-pae (done on `main`, #180).
- **What:** 64-bit IDT/TSS with IST for double faults, 4-level per-process
  address spaces, the 32-bit kernel reached through compatibility-mode
  thunks, 32-bit programs in compatibility mode.
- **Acceptance:** the whole `regress.sh` passes under `qemu-system-x86_64`
  with the long-mode kernel; the BIOS boot path still boots under `qemu-system-i386`
  with the 32-bit kernel (two build flavours, both in CI). Version mark
  **`2.9.0`** when ticked (`TO_3.0.0.md` M6).
- **Done on `main`:** IDT/TSS stay (`lmstay`, #189); 4-level paging
  (`lmpage`, #193); permanent stay + thunks (`lmthunk`, #196); boot64 everyday
  stay (`lmboot` / `os-lm64.img` / `LM_BOOT64`, #204) + follow-ups (#222):
  nestable `lm64_call32`, nest EOI on overflow, nestable thunk CR3 frames,
  syscall return in eax, everyday IRQ0/1/12 + `int 0x80` gates,
  `lm_enter_everyday` / `lm_boot_enter`. Regress names: lm-boot,
  lm-boot-again, lm-boot64, lm-boot64-again, and the -nolm pair. `systest` +
  `lmtest` pass on the boot64 image under `qemu-system-x86_64`.
- **Still open before ticking (paused until tip cut + Sarah/credits go):**
  32-bit ring-3 programs under permanent stay (exception trampolines / return
  paths — `run hello` on `os-lm64.img` is not green); whole suite as the
  everyday x86_64 flavour. Then `2.9-lm-kernel-tick-b55f` (mark **2.3.2** →
  **2.9.0**).
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

### ISM Flight Lab / ground station (#225)  `-b55f`
- **Goal:** OS/2 as lab / ground host for Soft Flight Lab + Eric HIL — not
  flight-critical avionics.
- **Done:** **ISM-gaps-b55f** — gap matrix
  [`documentation/guides/ism-flightlab-gaps.md`](documentation/guides/ism-flightlab-gaps.md)
  (runtime, numerics, formats, plotting, serial, timing, packaging). Soft
  inventory: `squirrelflightlab/` S7.1–S7.2b; HIL still stub (`fl_planned`).
- **Open (order):** **ISM-serial-b55f** → **ISM-hil-timing-b55f** →
  **ISM-flightlab-pkg-b55f** → **ISM-lab-setup-b55f**. Boxes in `TODO.md` /
  `ROADMAP.md`. Mirror ticks on #225 when the agent token can edit; else
  keep this card + PR bodies as the checklist.
- **Do not:** take W.6 (`-2eaf`); put FCC control laws on OS/2.

### 3.0 remainder — accounts, permissions, services, event log, task manager, themes
- Networking/audio half done. Boxes and marks in `TODO.md` and
  `TO_3.0.0.md` M10–M16: `3.0-users` / `perms` / `services` / `eventlog`
  (`-b55f`, **2.9.2–2.9.5**); `3.0-taskmgr` / `3.0-themes` (`-2eaf`,
  **2.9.6–2.9.7**); ship **`3.0.0`** (owner).

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
