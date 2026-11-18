# Path to 3.0.0 — dual-agent walkthrough

**Canonical home:** this file in **squirrel-os2** (PR [#205](https://github.com/squirelworks/squirrel-os2/pull/205) / `cursor/release-coord-b55f`). Soft [`docs/PATH_TO_3.0.0.md`](https://github.com/squirelworks/squirrelsoft/blob/main/docs/PATH_TO_3.0.0.md) is a **suite index only** (Soft [#166](https://github.com/squirelworks/squirrelsoft/pull/166) retargets it away from owning the OS ladder). Soft epics [#163](https://github.com/squirelworks/squirrelsoft/issues/163) / [#164](https://github.com/squirelworks/squirrelsoft/issues/164) still carry **stale** `fc3ae21` / Soft-as-source-of-truth wording until `-2eaf` closes or rewrites them — do not follow those for tip-cut rules.

**Index:** [ROADMAP.md](../../ROADMAP.md) (milestones) · [TODO.md](../../TODO.md) (boxes) · [HANDOFF.md](../../HANDOFF.md) (live status / lanes) · living claims [#201](https://github.com/squirelworks/squirrel-os2/issues/201) · tip-cut handshake [#208](https://github.com/squirelworks/squirrel-os2/issues/208) · progress [#132](https://github.com/squirelworks/squirrel-os2/issues/132).

**Audience:** both Cursor agents (`-b55f` = long mode / 2.9 → 3.0 kernel; `-2eaf` = desktop / Warp) and the owner (tags only). Written so either lane can resume after a credit reset without reinventing the plan.

**Supersedes (2026-11-15):** the earlier release-coord advice to tag prep commit `fc3ae21` alone. **New cut rule:** finish the open agent PRs listed below, then the owner tags/publishes from **that tip** of `main` (retargeted `2.3.0` notes).

---

## Version ladder scheme (why these bumps)

Squirrel-OS/2 already uses `major.minor.patch` in `PROCESS.md`. This walkthrough adds **fine-grain marks** so credit-reset resumes have named checkpoints:

| Bump | When to use | Example |
|------|-------------|---------|
| **+0.0.1** | One PR-sized box; tiny acceptance surface | `2.3.1` = W.6-startup alone |
| **+0.0.25** | Small multi-file slice, or the second half of a pair that should not wait for a full minor | `2.3.25` = W.6-syssetup closing Gen2 GUI |
| **+0.25.0** | Medium milestone: a ROADMAP subsection closes, banner may move | `2.6.0` = Generation 2 desktop declared complete |
| **+X.Y.0 (new minor/major)** | ROADMAP generation or bridge ship | `2.9.0` = lm-kernel everyday; `3.0.0` = 64-bit Warp + Gen3 |

**Rules agents must keep:**

1. Only the **owner** creates GitHub tags / Releases (`AGENTS.md`).
2. Agents prepare `documentation/releases/X.Y.Z.md`, bump `banner_rest` when the cut asks for it, update PROCESS, and leave a prefilled `releases/new?…` link in HANDOFF.
3. Do **not** invent parallel version lines. Prefer the next free mark in the ladder below; if a slice lands out of order, insert a `+0.0.1` and note the depends-on.
4. Lane tags on every checkpoint: **`-b55f`**, **`-2eaf`**, **shared**, or **owner**.

---

## Phase 0 — Finish open PRs, then cut 2.3.0 (now)

### Gate: open PRs that must land before the tip cut

| PR | Lane | Branch | Box / purpose | Merge gate |
|----|------|--------|---------------|------------|
| [#184](https://github.com/squirelworks/squirrel-os2/pull/184) | `-2eaf` | `cursor/impl-2.6-icons-drag-2eaf` | `2.6-icons` + `2.6-drag` | CI green; mergeable |
| [#197](https://github.com/squirelworks/squirrel-os2/pull/197) | `-2eaf` | `cursor/followup-gen2-sarah-2eaf` | Sarah Gen2 follow-ups | After or with #184 as needed; CI green |
| [#204](https://github.com/squirelworks/squirrel-os2/pull/204) | `-b55f` | `cursor/2.9-lm-boot64-b55f` | `LM_BOOT64` / boot-time stay | **Rebase first** (`mergeable_state: dirty`); CI green |
| [#205](https://github.com/squirelworks/squirrel-os2/pull/205) | `-b55f` / shared | `cursor/release-coord-b55f` | This roadmap / retargeted notes | Docs-only; land with or just before the cut |

Optional but preferred: any other open agent PR that is already CI-green and meant for this tip. Do **not** hold the cut for W.6 or ring-3-under-stay (those are post-2.3.0 marks).

### M0 — `v2.3.0` tip cut  ·  **owner**  ·  depends: #184 + #197 + #204 on `main`

| Field | Value |
|-------|-------|
| **Version** | `2.3.0` (banner already `2.3.0` on `main`) |
| **Tag target** | `main` HEAD **after** the gate PRs merge — **not** `fc3ae21` |
| **Notes** | Retargeted [`2.3.0.md`](2.3.0.md) (Gen2 + LM slices that landed after #173) |
| **Acceptance** | Notes match tip; Actions Draft release assets from that commit; owner Publishes |
| **Agents** | No freeze beyond finishing the gate PRs; no unilateral tag |

**Handshake after M0:**

1. **Owner:** Publish `v2.3.0` from tip; see HANDOFF prefilled link (updated when tip SHA is known).
2. **`-2eaf`:** Start `W.6-startup-2eaf` (M1).
3. **`-b55f`:** Start ring-3 under stay (M2) — do **not** tick `2.9-lm-kernel` yet.

---

## Phase 1 — Close Generation 2 + continue 2.9 (parallel lanes)

Lanes run **in parallel**. Within a lane, keep order.

### M1 — `2.3.1` W.6 Startup  ·  `-2eaf`  ·  depends: M0 (icons on `main`)

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` |
| **Box** | `W.6-startup-2eaf` (`TODO.md`) |
| **Issue** | [#209](https://github.com/squirelworks/squirrel-os2/issues/209) `W.6-startup: open Startup folder objects at desktop start` |
| **Acceptance** | `startup: PASS` / `w6-startup`; Drive/Shredder unchanged |
| **Release note** | Short `2.3.1.md` when owner wants a patch tag; else fold into next mark |

### M2 — ring-3 under permanent stay  ·  `-b55f`  ·  depends: M0 (#204 on `main`) — **done this cut as `2.3.1`**

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` → banner **`2.3.1`** (next free after `v2.3.0`; ladder name was `2.3.2`) |
| **Box** | `2.9-lm-ring3-stay` — ring-3 programs while EFER.LMA stays; compat CS |
| **Branch pattern** | `cursor/2.9-lm-ring3-stay-b55f` |
| **Issue** | [#211](https://github.com/squirelworks/squirrel-os2/issues/211) |
| **Acceptance** | `lm64-hello` / `lm64-ring3` on `os-lm64.img`; no tick of full `2.9-lm-kernel` yet |
| **Depends-on** | #204 `LM_BOOT64` on `main` |

*If M1 and M2 race on version numbers, use calendar order of merge for the patch; do not renumber history.*

### M3 — `2.3.25` W.6 System Setup  ·  `-2eaf`  ·  depends: M1

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.25` (medium-small: closes W.6 with Startup) |
| **Box** | `W.6-syssetup-2eaf` |
| **Issue** | [#210](https://github.com/squirelworks/squirrel-os2/issues/210) `W.6-syssetup: System Setup object + Drive/Shredder desktop wiring` |
| **Acceptance** | `syssetup: PASS` / `w6-setup` |
| **Note** | After M1+M3, Generation 2 GUI boxes in ROADMAP are complete |

### M4 — `2.6.0` Generation 2 declared complete  ·  **shared / owner**  ·  depends: M3

| Field | Value |
|-------|-------|
| **Bump** | `+0.25.0`-class jump to **`2.6.0`** so the banner matches ROADMAP **2.6** |
| **Why 2.6.0 not 2.4.0** | ROADMAP already used **2.4** for ring 3 (shipped earlier). Gen2 = 2.5–2.7 / W.*; shipping tag **`2.6.0`** means “Workplace Shell desktop generation done” |
| **Acceptance** | All 2.5 / 2.6 / W.2–W.6 boxes `[x]`; release note `2.6.0.md`; banner `2.6.0` |
| **Owner** | Publishes tag; agents prepare notes |

### M5 — `2.6.1` Soft follow-ups (optional)  ·  `-b55f` only if Sarah notes · else `-2eaf`

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` |
| **Trigger** | Sarah leaves Soft GNSS/NTRIP / suite notes |
| **Default** | Skip; do not invent Soft work |

---

## Phase 2 — Everyday long-mode kernel (`-b55f` spine)

### M6 — `2.9.0` tick `2.9-lm-kernel`  ·  `-b55f`  ·  depends: M2 + x86_64 suite flavour — **done this cut**

| Field | Value |
|-------|-------|
| **Bump** | Jump to **`2.9.0`** (ROADMAP bridge ship) |
| **Box** | `2.9-lm-kernel-tick-b55f` — tick TODO / ROADMAP / #132 when **all** of: stay+thunks (#196), boot64 (#204), ring-3 under stay (M2 / #231), and `REGRESS_FLAVOUR=lm64` under `qemu-system-x86_64`, plus BIOS/`i386` flavour still green |
| **CONTINUANCE 3a** | Freestanding C allowed for **new** 2.9+ subsystems; NASM for boot/entry; docs already in `documentation/architecture/overview.md` |
| **Acceptance** | Full suite both flavours; box ticked; note `2.9.0.md` |
| **Non-goals** | ELF64 `syscall` (that is M7); foreign personality under stay (skip on lm64 until M7) |

### M7 — `2.9.1` `2.9-syscall64` / `hello64`  ·  `-b55f`  ·  depends: M6

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` |
| **Box** | `2.9-syscall64-b55f` |
| **Acceptance** | `hello64: PASS` via `syscall`/`sysret`; `int 0x80` unchanged; `hello64-badptr` |
| **Unlocks** | P.3 ELF64, P.7 PE64 (later marks) |

### M8 — `2.9.25` freestanding C in `tools/build.sh`  ·  `-b55f` / shared  ·  depends: M6 (may parallel M7)

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.25` |
| **What** | Wire `-ffreestanding -mno-red-zone -fno-pic` objects into the kernel image; one trivial C symbol linked; NASM stubs unchanged |
| **Acceptance** | Build + regress both flavours; design note updated |
| **Issue** | [#212](https://github.com/squirelworks/squirrel-os2/issues/212) `2.9: freestanding C objects in kernel build (CONTINUANCE 3a)` |

### M9 — `2.9.50` first C subsystem slice (optional)  ·  `-b55f`  ·  depends: M8

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.25` from 2.9.25 → treat as **2.9.50** mark in notes (document in PROCESS as intentional mid-minor) |
| **What** | Port or add one small new subsystem in C (not a wholesale rewrite of `pm.asm`) |
| **Acceptance** | Named check; no regression of NASM paths |

---

## Phase 3 — Generation 3 remainder → `3.0.0`

Networking/sound half of 3.0 is **already on `main`**. Remaining boxes (split here so credit reset has checkboxes):

### M10 — `2.9.2` `3.0-users`  ·  `-b55f` (kernel) / shared UI  ·  depends: M6 recommended

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` from last 2.9.x |
| **What** | Login screen, `/etc`-style account file, hashed passwords |
| **Acceptance** | `users: PASS` (name TBD in PR); wrong password refused; reboot keeps accounts |
| **Issue** | [#213](https://github.com/squirelworks/squirrel-os2/issues/213) `3.0-users: login screen and account file` |

### M11 — `2.9.3` `3.0-perms`  ·  `-b55f`  ·  depends: M10

| Field | Value |
|-------|-------|
| **What** | Owner and mode on SQFS entries; checked in `fs.asm` |
| **Acceptance** | `perms: PASS`; unprivileged open denied |
| **Issue** | [#214](https://github.com/squirelworks/squirrel-os2/issues/214) |

### M12 — `2.9.4` `3.0-services`  ·  `-b55f`  ·  depends: M10

| Field | Value |
|-------|-------|
| **What** | Start at boot; restart on crash |
| **Acceptance** | `services: PASS` |
| **Issue** | [#215](https://github.com/squirelworks/squirrel-os2/issues/215) |

### M13 — `2.9.5` `3.0-eventlog`  ·  `-b55f`  ·  depends: M12

| Field | Value |
|-------|-------|
| **What** | Kernel + service log; existing log viewer reads it |
| **Acceptance** | `eventlog: PASS` |
| **Issue** | [#216](https://github.com/squirelworks/squirrel-os2/issues/216) |

### M14 — `2.9.6` `3.0-taskmgr`  ·  `-2eaf`  ·  depends: M6 (SMP stats already exist)

| Field | Value |
|-------|-------|
| **Bump** | `+0.0.1` |
| **What** | End task, priorities, CPU per CPU |
| **Acceptance** | `taskmgr: PASS` |
| **Lane** | Desktop/Warp lane owns the GUI; coordinate `pm.asm` / `regress.sh` with `-b55f` |
| **Issue** | [#217](https://github.com/squirelworks/squirrel-os2/issues/217) |

### M15 — `2.9.7` `3.0-themes`  ·  `-2eaf`  ·  depends: M4 (Gen2 widgets)

| Field | Value |
|-------|-------|
| **What** | Warp 4 default + “Classic” + Luna-like via `theme.inc` tables |
| **Acceptance** | `themes: PASS`; Control Panel switches survive reboot |
| **Issue** | [#218](https://github.com/squirelworks/squirrel-os2/issues/218) |

### M16 — `3.0.0` ship  ·  **owner**  ·  depends: M7 + M10–M15

| Field | Value |
|-------|-------|
| **Bump** | Major **`3.0.0`** — “64-bit Warp” / NT–XP class per ROADMAP |
| **Banner** | `3.0.0` |
| **Notes** | Full `3.0.0.md`; suite matrix with SquirrelBIOS (CONTINUANCE M3) |
| **Acceptance** | All Phase 2–3 boxes `[x]`; both QEMU flavours green; owner Publishes |
| **Agents** | Prepare notes + prefilled link; never tag |

---

## Phase 4 — Parallel foreign / later (do not block 3.0.0 unless noted)

These may start after their depends-on; they are **not** required to publish `3.0.0` unless the owner expands the ship gate.

| Mark | Title | Lane | Depends | Acceptance |
|------|-------|------|---------|------------|
| `2.9.8` / later | P.3 dynamic ELF + ELF64 | `-b55f` | M7 | musl-style loader check |
| later | P.7 PE64 | `-b55f` | M7 | PE64 hello |
| later | P.4 X11 subset | shared | M6+ | `xeyes`-class |
| later | P.9-16 NE | shared | — | 16-bit OS/2 text |
| later | P.10 other BSD/Solaris | `-b55f` | — | call tables |
| later | P.11 Darwin research | shared | — | design note first |
| later | P.12 sandbox / seamless | shared | Gen2 | caps + DnD/clipboard |
| 3.x | Compositor / virtio-gpu / … | shared | 3.0.0 | per ROADMAP |
| 4.x | HiDPI / touch / store | shared | 3.x | per ROADMAP |

---

## Resume after credits reset

### In flight (verify with `gh pr list` / HANDOFF before coding)

| Lane | Now | Next |
|------|-----|------|
| **`-b55f`** | #204 lm-boot64 (rebase if dirty); this docs PR #205 | After M0: **M2 ring-3 under stay** → M6 lm-kernel tick → M7 syscall64 |
| **`-2eaf`** | W.6 done (#209/#210) | Gen2 ship **M4 `2.6.0`** (owner) → M14/M15 when Gen3 GUI opens |
| **Owner** | Publish nothing until gate PRs land | **M0** tag `v2.3.0` from tip; later M4 / M6 / M16 |
| **Shared** | HANDOFF / TODO / ROADMAP / `pm.asm` / `regress.sh` | Rebase; do not race |

### Cold-start checklist (either agent)

1. `git fetch origin main && git checkout main && git pull`
2. Read **HANDOFF.md → Agent ownership** and **Release coordination**
3. Read this file’s **Resume** table; confirm open PRs still match
4. Claim work by opening/using a filed issue (#209–#218) or updating HANDOFF in your PR — **do not** rely on commenting on [#201](https://github.com/squirelworks/squirrel-os2/issues/201) (agent `addComment` is 403)
5. Branch `cursor/<box>-b55f` or `cursor/<box>-2eaf` from `main` only
6. Tick TODO/ROADMAP/#132 in the same PR as the code

### Do not

- Steal the other lane’s open boxes
- Tag or Publish releases
- Stack PRs on feature branches
- Treat `fc3ae21` as the 2.3.0 tag target (superseded)
- Ask Sarah to paste issue comments or file ladder issues (agents use `gh issue create`)

---

## Filed issues (2026-11-15, `-b55f` via `gh issue create`)

**No Sarah action required.** Tip-cut handshake: [#208](https://github.com/squirelworks/squirrel-os2/issues/208). Ladder:

| # | Title | Lane |
|---|-------|------|
| [#209](https://github.com/squirelworks/squirrel-os2/issues/209) | W.6-startup | `-2eaf` |
| [#210](https://github.com/squirelworks/squirrel-os2/issues/210) | W.6-syssetup | `-2eaf` |
| [#211](https://github.com/squirelworks/squirrel-os2/issues/211) | ring-3 under permanent stay | `-b55f` |
| [#212](https://github.com/squirelworks/squirrel-os2/issues/212) | freestanding C objects | `-b55f` |
| [#213](https://github.com/squirelworks/squirrel-os2/issues/213) | 3.0-users | `-b55f` / shared |
| [#214](https://github.com/squirelworks/squirrel-os2/issues/214) | 3.0-perms | `-b55f` |
| [#215](https://github.com/squirelworks/squirrel-os2/issues/215) | 3.0-services | `-b55f` |
| [#216](https://github.com/squirelworks/squirrel-os2/issues/216) | 3.0-eventlog | `-b55f` |
| [#217](https://github.com/squirelworks/squirrel-os2/issues/217) | 3.0-taskmgr | `-2eaf` |
| [#218](https://github.com/squirelworks/squirrel-os2/issues/218) | 3.0-themes | `-2eaf` |

Keep [#201](https://github.com/squirelworks/squirrel-os2/issues/201) as the **lane claims** pointer; full roadmap text lives here / in HANDOFF. Agent tokens cannot comment on #201 — use #208 + in-repo docs.

---

## Ladder at a glance

```
[open PRs #184 #197 #204 #205]
        │
        ▼
   v2.3.0 tip cut (owner)          ← M0  retargeted notes
        │
   ┌────┴────────────────────┐
   ▼                         ▼
2.3.1 W.6-startup (-2eaf)   2.3.2 ring-3 stay (-b55f)   ← M1 / M2
   │                         │
2.3.25 W.6-syssetup          │                         ← M3
   │                         │
2.6.0 Gen2 ship (owner)      │                         ← M4
                             ▼
                      2.9.0 lm-kernel tick (-b55f)      ← M6
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        2.9.1 syscall64  2.9.25 C build  (optional 2.9.50)
              │
              ▼
     2.9.2…2.9.7  Gen3 remainder (users…themes)
              │
              ▼
           v3.0.0 (owner)                              ← M16
```
