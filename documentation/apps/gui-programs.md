# Graphical programs (A.1)

Programs on the data disk that draw in graphics mode through `SYS_GUI` (`../kernel/syscalls.md`) and the toolkit in `programs/gui.inc`. They run with `run <name>` from the shell, take over the screen in VGA mode 13h (320 × 200) and give the text screen back as it was when they quit. The grapher (C.2) is described in `grapher.md`, Paint and the image viewer (A.2) in `paint.md`, the statistics program (C.3) in `stats.md`, the 3D grapher (C.7) in `graph3d.md`, the hex editor (A.7) in `hexedit.md`, the word processor Write (A.7) in `write.md`. Each draws a window in the window manager's look (white frame, blue title bar, light grey client area) and uses the kernel's 5 × 7 font, so the regression run reads their text with `<gfx>`. A mouse moves a pointer and left clicks work where the program says so.

They are separate files, not kernel code, so they do not use kernel image space. Build and install one as any program (`../../programs/README.md`).

## Calculator (`run calculator`)

A keypad calculator on the kernel's `sci` engine (`GUI_EVAL`), so it takes the same expressions as `sci`: `+ - * / ^`, parentheses, `pi`, `e`, `ans` and `sin cos tan asin acos atan sqrt ln log exp abs`.

| Key | Action |
|-----|--------|
| typing | adds to the expression |
| Enter or `=` | computes it: `= 14` on the second display row |
| Backspace / Delete | removes the last character / clears |
| arrows, Space | move the keypad focus (a black outline), press the key |
| left click | presses the key under the pointer |
| Tab | standard keypad (4 × 5) ↔ scientific (6 × 5: sin, cos, tan, ln, log, sqrt, ^, pi, e, D/R) |
| F2 or D/R | degrees ↔ radians (`DEG` / `RAD` at the bottom right) |
| Esc | quits |

After a result, an operator continues from it (`*2` after `= 14` computes `ans*2`); anything else starts a new expression. Errors read as in `sci`, for example `Error: division by zero` or `Error: syntax at column 4`; a result too long for one row is broken at a space onto the third display row.

Checks: `calculator` (`2+3*4` → `= 14`), `calculator-ans`, `calculator-err`, `calculator-syn`, `calculator-keys` (Space on the focused `4`, Right, Space → `= 45`), `calculator-sci` (Tab, F2, `sin(30)` → `= 0.5`), `calculator-quit`.

## Clock (`run clock`)

An analogue face (twelve marks, hour, minute and red second hands) with the time and date as text under it (`07:41:36  2026-11-13`), from the CMOS clock (`GUI_TIME`, `GUI_DATE`). It looks at the clock five times a second and redraws when the second changes. Esc quits.

`run clock test` draws one face, reads back from the screen the hub, the 12 o'clock mark and a face pixel, waits up to two seconds for the clock to move, and prints `clock: PASS` (or `clock: FAIL` and a letter for the failed check). Checks: `clock`, `clock-gfx`, `clock-quit`.

## Notepad (`run notepad [file]`)

A text editor in a full-screen window, the graphical counterpart of `edit`: up to 16 KB of text, lines longer than the window (52 columns, 21 rows) scroll sideways with the cursor, which is an inverted cell.

| Key | Action |
|-----|--------|
| typing, Enter, Tab (4 spaces) | insert |
| Backspace, Delete | remove before / at the cursor |
| arrows, Home, End, PgUp, PgDn | move (up and down keep the column) |
| Ctrl+S or F2 | save; the first time it asks for a name on the status row |
| Ctrl+O | open another file (asks for its name) |
| Ctrl+N | a new, empty text |
| Esc | quit; with unsaved changes it asks `Save changes? y/n` first (Esc there goes back) |

The title is `Notepad - <file>`; the status row shows the name, `*` while there are unsaved changes, `Ln` and `Col`, and the last message (`Saved`, `Opened`, `New file`, `Not saved!`). Checks: `notepad`, `notepad-save` (the file holds the text afterwards), `notepad-open`, `notepad-ask`, `notepad-quit`.

### Syntax highlighting (A.7)

The name's extension picks a language; other names stay black on white.

| Extension | Comments (green) | Strings (magenta) | Numbers (red) | Blue | Other |
|-----------|------------------|-------------------|---------------|------|-------|
| `.asm`, `.inc` | `;` to the line's end | `"…"` and `'…'` | a word starting with a digit (`10`, `0x3F`) | common instructions and data words (`mov`, `jne`, `db`, `equ`, `dword`, …) | registers and labels (a word at the line's start followed by `:`) brown; `%` directives cyan |
| `.c`, `.h` | `//` to the line's end, `/* … */` over lines | `"…"` with `\` escapes | as above | keywords (`int`, `if`, `return`, `struct`, …) | `#` lines' first word cyan |
| `.bas` | `REM` and `'` to the line's end | `"…"` | as above | keywords (`PRINT`, `IF`, `GOTO`, …, any case) | |

Each redraw runs the highlighter from the start of the text, so a `/* … */` comment that begins above the view is still green. `run notepad -test` draws a line of each language and reads back the colour of a character of each kind (label, instruction, register, number, comment, directive, keyword, string, block comment over two lines, `REM`); it prints `notepad: PASS`, or `notepad: FAIL`, the case's file name and a letter for the character that failed. Check: `notepad-hl`.

## Character map (`run charmap`)

The 95 characters of the system font (0x20–0x7E) in a grid of 16 columns, the chosen one four times larger beside it with its code in hex and decimal (`0x7E`, `126`), and a field of collected characters underneath.

| Key | Action |
|-----|--------|
| arrows, Home, End, or a click | choose a character |
| a typed character | jumps to it |
| Enter or Space | adds the chosen character to the field (up to 40) |
| Backspace | removes the last one |
| F2 | saves the field as the file `charmap.txt` |
| Esc | quits |

Checks: `charmap` (A, B, then `~` reached by typing `z` and Down), `charmap-save`.

## Writing one

```nasm
%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"          ; after the header: it holds code

main:
    call gui_open           ; graphics mode, a clear back buffer (CF: none)
    jc .fail
    mov eax, 40             ; x, y, width, height, title
    mov ebx, 30
    mov ecx, 200
    mov edx, 100
    mov esi, title
    call gui_window         ; sets gui_cx / gui_cy / gui_cw / gui_ch
    call gui_flip           ; the buffer onto the screen
    call gui_getkey         ; eax = ASCII | scancode << 8 | Ctrl << 16
    call gui_close          ; text mode again
    ...
SQX_BSS
GUI_BSS                     ; the toolkit's zeroed data
SQX_END
```

| Routine | In | Does |
|---------|----|------|
| `gui_open`, `gui_close` | — | enter graphics mode with a clear buffer (64 000 bytes from `SYS_SBRK`), and leave it |
| `gui_flip`, `gui_flip_rect` | — / eax, ebx, ecx, edx = rect | copy the buffer (or a part) to the screen; the pointer stays on top |
| `gui_pset`, `gui_pget` | eax = x, ebx = y, cl = colour | one pixel of the buffer (clipped) |
| `gui_peek` | eax = x, ebx = y | cl = the pixel on the screen, for self-checks |
| `gui_fill`, `gui_box`, `gui_bevel` | eax, ebx, ecx, edx = rect | filled rectangle / outline in `gui_ink`; raised or sunken edges (`gui_bevel_up`) |
| `gui_line` | eax, ebx → ecx, edx | a line in `gui_ink` |
| `gui_clip`, `gui_noclip` | eax, ebx, ecx, edx = rect / — | drawing reaches only that rectangle (the whole screen after `gui_open`) |
| `gui_char`, `gui_text`, `gui_textn`, `gui_textw` | eax = x, ebx = y, dl / esi | the kernel font in 6 × 8 cells, ink `gui_ink` on `gui_bg`; `textn` stops at ecx pixels; `textw` returns the width |
| `gui_window`, `gui_button`, `gui_clear` | rect, esi = title / label | a window in the window manager's look; a bevelled button with a centred label; the whole buffer in al |
| `gui_pollkey`, `gui_getkey`, `gui_waitkey` | — / ecx = ticks | a key now (0: none), wait for one, wait at most ecx ticks |
| `gui_event` | ecx = ticks (0: no limit) | a key, `EV_CLICK` (left button, at `gui_mx`, `gui_my`) or 0 on time-out; moves the pointer |
| `gui_ticks`, `gui_utoa`, `gui_itoa`, `gui_puts` | | ticks; decimal text at edi; print on the text screen |

Colours are the `C_*` names of the EGA palette mode 13h keeps (`C_BLUE` 0x01 … `C_WHITE` 0x3F), key scancodes the `K_*` names.

Until the 2.2 window manager gives programs real windows, each program owns the whole screen while it runs; it draws its window over a cyan desktop of its own. The programs will move to the 2.2 window API when it is published in `../kernel/windows.md`.

The spreadsheet Sheet (C.4), with charts linked to its cells, is described in `sheet.md`.
Geometry (C.6), constructions that follow their points, is described in `geometry.md`.
The CAS (C.5), exact algebra and calculus in a console, is described in `cas.md`.
The Notebook (C.8), pages of notes, code, graphs, tables and geometry, is described in `notebook.md`; its scripting language Nut in `nut.md`.
The System Monitor, Log Viewer and Disk Utility (A.5) are described in `sysmon.md`, `logview.md` and `diskutil.md`; they read the system through `GUI_SYSINFO` (`../kernel/syscalls.md`).
