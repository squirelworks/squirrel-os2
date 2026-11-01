# SquirrelSoft handoff pack — Squirrel-OS/2 docs

Generated for moving work into a new SquirrelSoft environment.
Repo: https://github.com/squirelworks/squirrel-os2  
Current `main` tip when packed: after **#104** (1.9.3 network loopback). Banner on `main`: **1.9.3**.  
NE2000 (1.9.4) was prepared on branch `cursor/ne2k-2.0-9130` (tested in QEMU; open PR after rebase onto post-#104 `main`).

## How to use

Copy this folder into the new environment, or pull the same paths from the git tree.
Authoritative copies always live in the repo; this pack is a snapshot.

## What is done (laundry list)

| Area | Status |
|------|--------|
| 1.0–1.9 object desktop | Done on `main` (folders, move, rename/delete) |
| Installer I.1–I.6 | Done on `main` |
| **2.0-loop** | Merged as 1.9.3 (#104) |
| **2.0-nic** | Code + QEMU smoke on `cursor/ne2k-2.0-9130`; needs PR onto `main` |
| 2.0-arp → tcp, then **2.0.0** | Open in `TODO.md` — **ask owner before tagging 2.0.0** |
| Modern hardware H.1–H.6 | Not started (UEFI, AHCI, NVMe, USB, …) |

## Process rules (from ROADMAP)

1. Original code only (no classic OS/2 / osFree sources).
2. One TODO box → one PR into `main`.
3. No stacked PRs; rebase onto current `main`.
4. Docs + release note + TODO tick in the same PR when the version moves.
5. Run `tools/regress.sh` before push.

## Pack layout

```
root/                  README.md, ROADMAP.md, TODO.md
documentation/
  README.md            Living index
  specifications.md    Accepted limits by version
  plannedmilestones.md History / long-range vision
  knownbugs.md
  releases/PROCESS.md  How versions move
  releases/1.8.*–1.9.* Recent release notes (incl. network)
  kernel/              Design notes (boot, net, objects, FS, …)
  architecture/        Firmware independence, platforms, multi-arch
  guides/              getting-started, install
  apps/desktop.md      Object desktop behaviour
bios/README.md         Pointers to BIOS docs + SquirrelBIOS repo
```

## Docs created/updated for networking (2.0 start)

- `documentation/kernel/network.md` — layer, loopback, NE2000
- `documentation/releases/1.9.3.md` — 2.0-loop
- `documentation/releases/1.9.4.md` — 2.0-nic (on ne2k branch)
- `TODO.md` 2.0 section — PR-sized boxes

## BIOS / firmware docs (in this OS tree)

See `bios/README.md`. Primary: `documentation/kernel/boot-sector.md`, `documentation/architecture/firmware-independence.md`.

## Next PR to open

1. Rebase `cursor/ne2k-2.0-9130` onto `main`, full `tools/regress.sh`, PR **2.0-nic** / 1.9.4.
2. Then **2.0-arp**, **2.0-ping**, **2.0-udp**, **2.0-tcp**.
3. **2.0.0** release only after owner OK.
