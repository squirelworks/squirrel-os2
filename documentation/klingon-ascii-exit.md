# Klingon ASCII exit (scaffold)

**Status:** documentation only. No code conversion in this change.  
**Branch line:** `klingon-font` joke world (`may'Duj` / pIqaD UI).  
**Do not merge into `main`.**

This note scaffolds a future **full ASCII-to-Klingon purge**: every user-visible
surface on the joke line should read as if the machine never had ASCII — not
only VGA glyphs and `lang tlh` strings, but also leftover English `db`
literals, built-in help files, and eventually **COM1 / serial**.

## Why this exists

Today the joke is incomplete in two ways:

1. **UI chrome** — many kernel and program strings are still hard-coded English
   (Control Panel, window-manager tests, graph/diff prompts, sysmon headers,
   …). Localization covers a growing set via `localization/*/strings.txt`, but
   the policy in `localization/README.md` is not finished.
2. **Serial / COM1** — SquirrelBIOS's `klingon-font` branch loads pIqaD on VGA
   and **leaves COM1 unchanged** so `make test` can still match ASCII tokens.
   That is a deliberate Latin leak. A full purge must cover COM1 (and any OS
   path that prints to serial) without breaking smoke harnesses.

Sibling work on this line (starship UI / `may'Duj` branding) cleans product
chrome. This scaffold is the **next chapter**: inventory, phases, and hard
gates before anyone touches COM1.

## Non-goals (this scaffold)

- Do **not** change COM1 / UART / `console.c` / BIOS serial banners now.
- Do **not** retarget `tools/regress.sh` or BIOS `make test` expectations.
- Do **not** merge joke behaviour onto `main`.
- Do **not** invent Unicode pIqaD on the wire until the harness plan lands.

## Target end state

On `klingon-font` (and matching BIOS `klingon-font`):

| Surface | End state |
|---------|-----------|
| VGA / VBE text | pIqaD glyphs (already) |
| Shell / desktop / apps | Klingon copy via `lstr` / keys; no English chrome |
| Built-in help / sample files | Klingon (or braced Latin command names only) |
| COM1 / PL011 / NS16550 banners | Klingon (or a documented dual-channel test mode) |
| Smoke / regress | Pass without requiring Latin on the joke default path |

`main` stays English / ASCII. Joke branches stay forever separate
(`AGENTS.md`: never merge `klingon-font*`).

## Related trees

| Tree | Role in the purge |
|------|-------------------|
| `squirrel-os2` `klingon-font` | OS strings, font load, default `lang tlh`, UI |
| `squirrelbios` `klingon-font` | VGA pIqaD; **COM1 still ASCII today** |
| Host harnesses | QEMU `-serial stdio`, `tools/regress.sh`, BIOS `make test` |

OS work alone cannot finish the purge: COM1 banners live in firmware.

## Encoding note

`tools/mkstrings.py` currently requires **printable ASCII** values and maps
Klingon digraphs (`tlh`, `ch`, `gh`, `ng`) to single glyphs `0x80`–`0x83` for
the VGA font. Serial is a different medium: hosts expect UTF-8 or Latin-1.
A COM1 purge must pick one of:

- keep digraph Latin on the wire (still "ASCII", weaker joke), or
- emit a documented UTF-8 pIqaD mapping and teach harnesses to decode it, or
- add a joke-only serial escape / second UART for Latin diagnostics.

That choice is **open** and belongs in a future implementation PR — not here.

## Phased plan (summary)

See the checkbox list in [`klingon-ascii-exit-checklist.md`](klingon-ascii-exit-checklist.md).

| Phase | Scope | COM1? |
|-------|--------|-------|
| **0** | Docs + inventory (this scaffold) | Untouched |
| **1** | Finish `lstr` migration for user-visible OS chrome | Untouched |
| **2** | Built-in files / help / sample text on the joke line | Untouched |
| **3** | Design COM1 encoding + harness dual-path | Design only |
| **4** | Implement COM1 / firmware serial Klingonization | **Then** change COM1 |
| **5** | Cross-repo proof (OS + BIOS screenshots + serial dumps) | Done |

## Hard gate before Phase 4

Do not land COM1 code until all of these are true:

1. Written encoding choice (digraph Latin vs UTF-8 pIqaD vs dual UART).
2. BIOS `make test` plan that still proves boot without false Latin requirements
   on the joke default (or a documented `KLINGON_SERIAL_LATIN=1` escape).
3. OS `tools/regress.sh` plan for any serial-scraped checks on joke builds.
4. Explicit owner OK to break/fix serial expectations on `klingon-font` only.

## Pointers

- Product joke overview: [`../README.md`](../README.md) (Klingon font section)
- String policy: [`../localization/README.md`](../localization/README.md)
- Runtime: [`kernel/localization.md`](kernel/localization.md)
- Checklist: [`klingon-ascii-exit-checklist.md`](klingon-ascii-exit-checklist.md)
- Matching firmware joke: SquirrelBIOS `klingon-font` README (COM1 unchanged today)
