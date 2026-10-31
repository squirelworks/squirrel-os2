# Windows

The window manager (`kernel/wm.asm`, since 1.4.0) draws windows in graphics mode with the primitives in `graphics.md`. Keyboard only; there is no mouse.

## Windows

The kernel keeps a table of up to 4 windows (`WM_MAX`). Each record holds:

| Field | Meaning |
|-------|---------|
| `WIN_USED` | 1 while the window is open |
| `WIN_X`, `WIN_Y` | top left corner, in pixels |
| `WIN_W`, `WIN_H` | outer size, frame included |
| `WIN_TITLE` | address of a zero-terminated title |
| `WIN_LEN`, `WIN_BUF` | the characters typed into the window (up to 24) and their count |

A window is a one-pixel frame (white, `WM_FRAME`), a title bar one text row high plus a margin (with the title in white), and a client area below it (light grey, `WM_CLIENT`) that shows the window's typed text in black. The title bar is blue (`WM_BAR`) on the focused window and dark grey (`WM_BAR_IDLE`) on the others. The desktop behind the windows is cyan (`WM_DESKTOP`). The colours are the text mode's EGA palette, which the DAC keeps in mode 13h: the bright colours are at `0x38`–`0x3F`.

## Z-order and focus

Since 1.4.2 the kernel keeps the open windows in a z-order list (`wm_z`, bottom first). A new window goes on top. The top window has the keyboard focus. `wm_redraw` draws from the bottom up, so a window covers the ones below it. Tab (in `winfocus`) calls `wm_cycle`, which brings the bottom window to the top: with two windows the focus goes back and forth.

## Calls

| Routine | In | Out |
|---------|----|-----|
| `wm_create` | eax = x, ebx = y, ecx = width, edx = height, esi = title | eax = window id, or −1 if the table is full, the window is smaller than 16 × 14, or it is not wholly on the screen |
| `wm_close` | eax = window id | the slot is free; an id that is not open is ignored |
| `wm_move` | eax = window id, ebx = new x, ecx = new y | CF if the id is not open or the window would not be wholly on the screen; the window is then unchanged |
| `wm_resize` | eax = window id, ebx = new width, ecx = new height | the top left corner stays; CF as `wm_move`, or if the new size is below the minimum |
| `wm_raise` | eax = window id | puts the window on top, which gives it the focus; CF if the id is not open |
| `wm_cycle` | — | brings the bottom window to the top (nothing with fewer than two) |
| `wm_focus` | — | eax = the focused (top) window's id, or −1 |
| `wm_putc` | al = character | appends it to the focused window's text if there is room |
| `wm_redraw` | — | paints the desktop, then every open window, lowest slot first |

None of these draw; the caller calls `wm_redraw`. A title longer than the bar is cut at the last character that fits.

These are kernel routines. Programs cannot open windows yet.

## Test

`wintest` switches to graphics mode, draws an empty desktop, creates a 200 × 120 window titled `Test window` at (60, 40) and redraws. It reads back a pixel of the left frame and a pixel of the title's first letter, closes the window, redraws, and reads the frame pixel again, which must now be the desktop colour. It returns to text mode and prints `win: PASS` or `win: FAIL`. Checks `wintest` and `wintest-text` (`systest` after it).

`winmove` (1.4.1) creates the same window, moves it to (100, 60) and then resizes it to 100 × 60. After each step it reads back a pixel where the frame was, which must now be the desktop, and a pixel of the new frame. It then tries a move past the right edge and a width below the minimum; both must be refused and leave the window where it was. It prints `winmove: PASS` or `winmove: FAIL`. Checks `winmove` and `winmove-text`.

`winfocus` (1.4.2) is interactive. It opens two overlapping windows, One and then Two, so Two is on top. Tab swaps which window is on top and focused, other keys type into the focused window, and Enter or Esc ends. It then reads the pixel where Two's left edge crosses One's client area: the frame colour there means Two was drawn last. It closes both windows, returns to text mode and prints, for example:

```
winfocus:
One got "cd"
Two got "ab"
top: One
```

after `ab`, Tab, `cd`, Enter. Checks `winfocus` (that sequence), `winfocus-none` (no Tab: Two keeps the focus) and `winfocus-text`.

## Next

Widgets inside windows: labels, buttons, edit fields and lists (1.5, `../../TODO.md`).
