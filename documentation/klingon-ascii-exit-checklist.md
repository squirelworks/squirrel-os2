# Klingon ASCII-exit checklist

Companion to [`klingon-ascii-exit.md`](klingon-ascii-exit.md).  
**This PR / scaffold:** Phase 0 only. **COM1 code stays frozen.**

Use these boxes on follow-up PRs against base `klingon-font` (never `main`).

---

## Phase 0 — Scaffold (this change)

- [x] Plan doc: `documentation/klingon-ascii-exit.md`
- [x] Checklist: this file
- [x] README pointer under the Klingon font section
- [x] Explicit **COM1 do-not-touch** gate documented
- [ ] (optional) Mirror a one-line pointer in SquirrelBIOS `klingon-font` README — separate repo PR

---

## Phase 1 — OS user-visible `lstr` migration

Move hard-coded English `db` chrome to `localization/{en,la,tlh}/strings.txt`
per `localization/README.md`, regenerate `kernel/strings.inc`, keep
`{command}` braces where Latin spellings must survive digraph pass.

### High-traffic chrome (start here)

- [ ] Control Panel (`kernel/control.asm`) — titles, schemes, prompts, quit line
- [ ] Window manager chrome / system menu labels still in English (`kernel/wm.asm`)
- [ ] Desktop leftovers beyond `desktop_title` / `desktop_bye`
- [ ] WarpCenter / LaunchPad any remaining Latin labels
- [ ] Graph / sci / matrix / diff prompts and status lines
- [ ] Sysmon headers and status strings (`programs/sysmon.asm`)
- [ ] Terminal / file manager / clipboard viewer chrome
- [ ] Network tool messages not yet keyed (`arp`/`ping` extras, DHCP lines)
- [ ] Installer / diskutil user messages on the joke line

### Policy checks

- [ ] Every new key present in `en`, `la`, and `tlh`
- [ ] `python3 tools/mkstrings.py` + `tools/mkstrings.py --check`
- [ ] `tools/regress.sh` still green with `nasm -DDEFAULT_LANG_EN` (English path)
- [ ] Manual `lang tlh` boot: no English chrome in the touched apps
- [ ] Do **not** touch COM1 / serial drivers

### Inventory aid (not authoritative)

Rough grep for leftover literals (re-run when starting Phase 1):

```bash
rg -n "db '[A-Za-z][^']{2,}" kernel programs --glob '*.asm' | rg -v "PASS|FAIL"
```

Expect hundreds of hits; triage user-visible chrome first, leave regress
`PASS`/`FAIL` tokens and filenames alone unless they appear on screen.

---

## Phase 2 — Built-in files and samples

- [ ] Built-in `help` / `calc` / `sci` / `matrix` text files (README notes they stay English today)
- [ ] Any joke-line sample documents shipped on `data.img`
- [ ] Char map / font demo strings that still teach Latin letter names as primary UI
- [ ] Keep command *words* (`q`, `clear`, `lang`, …) Latin unless a separate command-rename epic exists

---

## Phase 3 — COM1 design (docs / harness only)

**Still no COM1 code.** Produce a short design addendum (new section or follow-up doc) that picks:

- [ ] Wire encoding: digraph Latin **or** UTF-8 pIqaD **or** dual UART / escape
- [ ] BIOS `make test` strategy on `klingon-font` (token table, decoder, or Latin escape env)
- [ ] OS regress strategy for any serial-scraped checks under joke default lang
- [ ] Owner sign-off recorded in the design note

### Known COM1 touchpoints (implement later — list only)

Firmware (SquirrelBIOS `klingon-font`):

- [ ] `x86` POST / boot banners printed on COM1
- [ ] `x86_64` `core/console.c` / `textcon.c` (UEFI-class serial)
- [ ] Arm PL011 / RISC-V NS16550 banners if those platforms join the joke
- [ ] Stand-in `tests/*.asm` expectations that grep Latin on serial

OS (only if a path writes diagnostics to serial on the joke line):

- [ ] Any kernel debug / early-boot serial mirror (inventory before coding)
- [ ] Regress wrappers that scrape QEMU `-serial stdio`

---

## Phase 4 — COM1 implementation (blocked)

Blocked on Phase 3 gate. When unblocked:

- [ ] Firmware serial strings Klingonized on `klingon-font` only
- [ ] Harness updated; `main` / non-joke configs unchanged
- [ ] OS side only if inventory found serial printers
- [ ] Proof: serial dump artifact + note that VGA and COM1 agree on language

---

## Phase 5 — Proof package

- [ ] Boot banner screenshot (already partly covered by starship UI proofs)
- [ ] Desktop / one app screenshot under `lang tlh`
- [ ] COM1 capture showing no Latin product chrome (after Phase 4)
- [ ] `tools/regress.sh` EXIT 0 on joke tip with `DEFAULT_LANG_EN` path
- [ ] BIOS `make test` EXIT 0 on BIOS `klingon-font` tip

---

## Explicit freezes

| Item | Until |
|------|--------|
| COM1 / UART code | Phase 4 after Phase 3 sign-off |
| Merging into `main` | Never for joke behaviour |
| Deleting `klingon-font*` | Owner only |
| Changing smoke tokens without harness plan | Never |
