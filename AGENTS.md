# Agent guide (Cursor, Codex and other coding agents)

Squirrel-OS/2: an original x86 operating system in NASM, in the spirit of OS/2 Warp.

- **Start here:** [HANDOFF.md](HANDOFF.md) (what is done, in progress and open, with a card per open
  item), then [ROADMAP.md](ROADMAP.md) and [TODO.md](TODO.md). Suite-wide plan:
  `docs/CONTINUANCE.md` in github.com/squirelworks/squirrelsoft.
- **Build:** `tools/build.sh` (needs `nasm`, `python3`). **Test:** `tools/regress.sh` (needs
  `qemu-system-i386`, `qemu-system-x86_64`, `python3-numpy`, `ovmf`). CI runs both on every PR.
- **PRs:** base on `main`; never stack on another feature branch; group related boxes into one
  sizeable PR; confirm the PR targets `main`, is mergeable and CI `regress` is green.
- **Original code only.** No osFree, OS/2, Linux, Wine, ReactOS or DOSBox sources. Specs are fine.
- Every behaviour change: a `check` in `tools/regress.sh`, the design note under `documentation/`,
  the box ticked in `TODO.md`/`ROADMAP.md` and on issue #132.
- Strings: `localization/en`, `la`, `tlh`, then `python3 tools/mkstrings.py`.
- Never tag or publish releases, never delete branches, never merge `klingon-font*` branches.
  Release notes go in `documentation/releases/`; the owner publishes.
