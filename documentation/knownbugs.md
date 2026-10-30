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

- **KB-7** `draw`, `edit` and `vedit` redraw by appending a fresh copy below the old one rather than in place, so the screen scrolls on every key.

## Notes

- Add an entry only when behavior contradicts `specifications.md` or a stated milestone goal.
- Reference bug IDs in release notes when a fix lands.
- Do not delete closed entries; mark them resolved.
