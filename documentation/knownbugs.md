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

Open:

- **KB-1** No Shift handling, so `+`, `*` and `%` cannot be typed; `calc` effectively supports only `-` and `/`.
- **KB-2** `calc` prints negative results as large unsigned numbers (`itoa` is unsigned).
- **KB-3** Console does not scroll; output past row 25 is written beyond the visible screen (redraws in `draw`/`edit` run off quickly).
- **KB-4** `run calc` shows `calc> > ` because the shell prompt is printed after the app prompt.
- **KB-5** `default_isr` returns to the faulting instruction, so any CPU exception hangs instead of reporting.
- **KB-6** `vedit_sample` in `pm.asm` triggers an NASM warning (`''H''` is not a valid escaped quote).

## Notes

- Add an entry only when behavior contradicts `specifications.md` or a stated milestone goal.
- Reference bug IDs in release notes when a fix lands.
- Do not delete closed entries; mark them resolved.
