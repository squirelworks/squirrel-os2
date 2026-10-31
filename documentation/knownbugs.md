# Squirrel-OS/2 Known Bugs

Defects relative to the current specifications.  
Accepted limitations and capabilities live in `specifications.md`.

## 0.0.2

No defects are currently recorded against the 0.0.2 specification.

(Earlier observations about real-mode operation, 512-byte size, approximate timing, and the one-time firmware video call are intentional limitations, not bugs.)

## 0.1.1

Resolved in 0.1.1:

- `ls` printed garbage after the first file name (`putc` clobbered `ebx`). Resolved.
- A shorter command typed after a longer one was not recognised (command line only had its first byte cleared). Resolved.
- `calc`: `a - b` and `a / b` gave wrong results (`atoi` clobbered the first operand). Resolved.
- `calc`: any division hung the machine (`cdq` overwrote the divisor, divide error looped through `default_isr`). Resolved.

Open at 0.1.1 (all resolved after 0.1.1, ship with 0.1.2):

- **KB-1** No Shift handling, so `+`, `*` and `%` could not be typed. Resolved: Shift tracked, shifted map added, keypad `* - +` mapped.
- **KB-2** `calc` printed negative results as large unsigned numbers. Resolved: `itoa` is signed.
- **KB-3** Console did not scroll. Resolved: `putc` scrolls at row 25 and moves the hardware cursor.
- **KB-4** `run calc` showed `calc> > `. Resolved: the shell prompt is skipped when an interactive app starts.
- **KB-5** `default_isr` returned to the faulting instruction, hanging on any CPU exception. Resolved: vectors 0–31 print `*** CPU exception N at EIP 0x...` and halt (`trap` command demonstrates).
- **KB-6** NASM warning on `vedit_sample`. Resolved.
- Also: the shell command line now accepts Backspace; the calculator banner no longer advertises an unimplemented `q` exit.

Open:

- **KB-7** `draw`, `edit` and `vedit` redraw by appending a fresh copy below the old one rather than in place, so the screen scrolls on every key. (Resolved: `edit`/`vedit` in 0.3.2, `draw` in 0.3.3.)

## 0.9.2

Found during the 0.9.2 polish pass, all resolved in 0.9.2:

- **KB-8** `run edit <path>` and `run draw <path>` cut the name to 15 characters (the argument buffer was sized for a single file name), so a path into a directory opened the wrong file. Resolved: app arguments and the save-as prompts take paths of up to 63 characters.
- **KB-9** Opening a directory in `edit`/`vedit`/`draw` claimed `New file (not on disk yet).`, and saving then failed with `Disk error.`. Resolved: the reason is shown and the buffer starts untitled.
- **KB-10** The file browser did not list directories, so files in a subdirectory could not be reached from it, and a refused delete gave no feedback. Resolved: directories are listed and can be entered; refusals are explained.
- Also: file commands answered every failure with `error`, and argument commands typed alone with `Unknown command`. Both now say what is wrong.

## 0.9.3

Found while checking release readiness (booting in other configurations and in Bochs), all resolved in 0.9.3:

- **KB-11** Booting from a floppy image hung: the boot sector only used extended disk reads, which floppies do not support. Resolved with a CHS fallback.
- **KB-12** After a floppy boot the BIOS memory map was missing (`no BIOS map: assumed 32 MB`): ES still pointed past the kernel when E820 ran. Resolved: the kernel clears DS/ES first.
- **KB-13** On a CPU without an FPU or 4 MB pages the kernel crashed silently. Resolved: it now says it needs a Pentium-class CPU and halts.
- **KB-14** The boot banner said 0.2.3. Resolved: `banner_rest` carries the current version.
- **KB-15** `calc` wrote `calc.hist` into the current directory, so each directory got its own history. Resolved: it is kept at `/calc.hist`.
- Also: `graph`, `diff` and `topo` were listed as apps but are scaffolds; the banner now lists them as planned.

## Notes

- Add an entry only when behavior contradicts `specifications.md` or a stated milestone goal.
- Reference bug IDs in release notes when a fix lands.
- Do not delete closed entries; mark them resolved.
