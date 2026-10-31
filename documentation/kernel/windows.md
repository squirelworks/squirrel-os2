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

A window is a one-pixel frame (white, `WM_FRAME`), a title bar one text row high plus a margin (blue, `WM_BAR`, with the title in white), and a client area below it (light grey, `WM_CLIENT`). The desktop behind the windows is cyan (`WM_DESKTOP`). The colours are the text mode's EGA palette, which the DAC keeps in mode 13h: the bright colours are at `0x38`–`0x3F`.

## Calls

| Routine | In | Out |
|---------|----|-----|
| `wm_create` | eax = x, ebx = y, ecx = width, edx = height, esi = title | eax = window id, or −1 if the table is full, the window is smaller than 16 × 14, or it is not wholly on the screen |
| `wm_close` | eax = window id | the slot is free; an id that is not open is ignored |
| `wm_redraw` | — | paints the desktop, then every open window, lowest slot first |

`wm_create` and `wm_close` do not draw; the caller calls `wm_redraw`. A title longer than the bar is cut at the last character that fits.

These are kernel routines. Programs cannot open windows yet.

## Test

`wintest` switches to graphics mode, draws an empty desktop, creates a 200 × 120 window titled `Test window` at (60, 40) and redraws. It reads back a pixel of the left frame and a pixel of the title's first letter, closes the window, redraws, and reads the frame pixel again, which must now be the desktop colour. It returns to text mode and prints `win: PASS` or `win: FAIL`. Checks `wintest` and `wintest-text` (`systest` after it).

## Later in 1.4

Moving and resizing a window, then two windows with z-order and keyboard focus (`../../TODO.md`).
