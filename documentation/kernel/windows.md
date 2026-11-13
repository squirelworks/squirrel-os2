# Windows

The window manager (`kernel/wm.asm`, since 1.4.0) draws windows in graphics mode with the primitives in `graphics.md`. Keyboard only for window management until later 2.2 boxes; a soft cursor follows the mouse on the desktop. Since **2.2-vbe-wm**, `wm_gfx_enter` selects VBE 640×480 at 8 bpp (theme palette indices in `theme.inc`) when DISPI accepts it, and falls back to VGA mode 13h (320×200) otherwise. Window placement and the desktop fill use the live `gfx_width` / `gfx_height`.

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
| `wm_gfx_enter` (2.2-vbe-wm) | — | VBE 640×480×8, or mode 13h if VBE is refused; clamps the mouse into the live screen; CF if both fail |

None of these draw; the caller calls `wm_redraw`. A title longer than the bar is cut at the last character that fits.

These are kernel routines. Programs cannot open windows yet.

## Test

`wintest` switches to graphics mode, draws an empty desktop, creates a 200 × 120 window titled `Test window` at (60, 40) and redraws. It reads back a pixel of the left frame and a pixel of the title's first letter, closes the window, redraws, and reads the frame pixel again, which must now be the desktop colour. It returns to text mode and prints `win: PASS` or `win: FAIL`. Checks `wintest` and `wintest-text` (`systest` after it).

`winmove` (1.4.1) creates the same window, moves it to (100, 60) and then resizes it to 100 × 60. After each step it reads back a pixel where the frame was, which must now be the desktop, and a pixel of the new frame. It then tries a move past the right edge and a width below the minimum; both must be refused and leave the window where it was. It prints `winmove: PASS` or `winmove: FAIL`. Checks `winmove` and `winmove-text`.

`winvbe` (2.2-vbe-wm) enters VBE 640×480×8 (not the 13h fallback), draws a window titled `VBE window`, and reads a frame pixel and a title-ink pixel from the visible front buffer (`vbe_front_getpixel`). After close and redraw, the frame pixel must be the desktop colour. It prints `winvbe: PASS` or `winvbe: FAIL`. Without VBE it fails (mode 13h is covered by `wintest`). Checks `winvbe` and `winvbe-text`.

`winfocus` (1.4.2) is interactive. It opens two overlapping windows, One and then Two, so Two is on top. Tab swaps which window is on top and focused, other keys type into the focused window, and Enter or Esc ends. It then reads the pixel where Two's left edge crosses One's client area: the frame colour there means Two was drawn last. It closes both windows, returns to text mode and prints, for example:

```
winfocus:
One got "cd"
Two got "ab"
top: One
```

after `ab`, Tab, `cd`, Enter. Checks `winfocus` (that sequence), `winfocus-none` (no Tab: Two keeps the focus) and `winfocus-text`.

## Widgets

Since 1.5.0, `wm_draw` draws a window's widgets after its client area, and `wm_close` drops them (`widgets.md`).

## The 2.2 API (planned)

This section is the window, event and drawing interface that the 2.2 boxes in `TODO.md` build, published before the code so programs (calculator, paint, games) can be written against it. It is a plan: register details can still change while a box is reviewed, and each box updates the section when it lands. Until then the 1.4–2.1 routines above are what the kernel has. Everything above stays valid; 2.2 adds to it.

### Screen and theme

- The window manager draws on a VBE screen, 640×480 at 8 bpp (**2.2-vbe-wm**); mode 13h (320×200) is the fallback. Programs read the screen size from `gfx_width` / `gfx_height` (or `SYS_WININFO`) and never assume one. Double buffering and dirty-rectangle flips arrive with **2.2-clip-z**.
- Colours are palette indices named in `kernel/theme.inc` (**W.1-theme**): `TH_DESKTOP`, `TH_FACE` (3D face grey), `TH_LIGHT`, `TH_SHADOW`, `TH_DARK`, `TH_TITLE` / `TH_TITLE_TEXT` (active), `TH_TITLE_IDLE` / `TH_TITLE_IDLE_TEXT`, `TH_CLIENT`, `TH_TEXT`, `TH_SELECT` / `TH_SELECT_TEXT`, `TH_BORDER` (sizing border). Sizes: `TH_BORDER_W`, `TH_TITLE_H`, `TH_BOX_W` (the title-bar boxes), `TH_BEVEL_W`. Code uses the names, never the numbers.

### Drawing (kernel)

| Routine | In | Out |
|---------|----|-----|
| `gfx_setclip` | eax, ebx = top left, ecx = width, edx = height | every later draw and blit is cut to that rectangle (and to the screen) (**2.1-blit-clip**) |
| `gfx_noclip` | — | the clip is the whole screen again |
| `gfx_copyrect` | eax, ebx = source top left, ecx = width, edx = height, esi, edi = destination top left | copies within the draw target, overlapping rectangles allowed; the destination is clipped (**2.1-blit-clip**) |
| `gfx_bevel` | eax, ebx = top left, ecx = width, edx = height, esi = 0 raised / 1 sunken | a `TH_BEVEL_W` bevel around the rectangle's edge, face not filled (**W.1-theme**) |
| `gfx_drawstr_p` | esi = string, eax, ebx = top left, ecx = face (`FONT_9` / `FONT_12`), colours in `gfx_colour` / `gfx_bg` (`-1` bg = transparent) | eax = x after the last character (**2.2-propfont**) |
| `gfx_strwidth_p` | esi = string, ecx = face | eax = width in pixels |

### Windows (kernel)

The window record gains `WIN_STATE` (`WS_NORMAL`, `WS_MIN`, `WS_MAX`), `WIN_RESTORE` (the rectangle to restore from maximised), `WIN_OWNER` (the pid that gets the events, `-1` for kernel windows) and `WIN_FLAGS` (`WF_SIZABLE`, `WF_MINBOX`, `WF_MAXBOX`, `WF_SYSMENU`; `WF_DEFAULT` is all four). `WM_MAX` becomes 16. A window may be partly off the screen as long as part of its title bar is on it.

| Routine | In | Out |
|---------|----|-----|
| `wm_create` | as before; `edi` = flags (0 means `WF_DEFAULT`) | as before; the caller's pid becomes the owner |
| `wm_client` | eax = window id | eax, ebx = client top left on the screen, ecx, edx = client size; CF if not open |
| `wm_settitle` | eax = window id, esi = title | CF if not open |
| `wm_setstate` | eax = window id, ebx = `WS_*` | minimise / maximise / restore; CF if not open or the flag is missing |
| `wm_hit` | eax = x, ebx = y | eax = top window id under the point or −1; ebx = part: `HT_CLIENT`, `HT_TITLE`, `HT_SYSMENU`, `HT_MIN`, `HT_MAX`, `HT_CLOSE`, `HT_L`, `HT_R`, `HT_T`, `HT_B`, `HT_TL`, `HT_TR`, `HT_BL`, `HT_BR` (**2.2-frame**) |
| `wm_invalidate` | eax = window id, or −1 for the whole screen | marks the window's visible area dirty |
| `wm_update` | — | redraws every dirty area, bottom window first, each clipped to its visible region, then flips those rectangles (**2.2-clip-z**). `wm_redraw` stays as "invalidate all, then update". |
| `wm_mouse` | eax = x, ebx = y, cl = buttons | the window manager's handling of one mouse state: raise on click, drag to move or size, the title-bar boxes, client clicks become events for the owner (**2.2-mouse**) |
| `wm_inject` | as `wm_mouse` | the same, from a script; the regression checks drive windows with it |
| `wm_key` | al = key, ah = shift state | Alt+Tab, Alt+Esc, Alt+Space, Alt+F4 are the window manager's; anything else goes to the focused window's widgets and then its owner (**2.2-sysmenu**, **2.2-alttab**) |

### Programs (syscalls, **2.2-progwin**)

Window syscalls use the reserved block 48–63 so other streams' new calls (35–47) do not collide. A window belongs to the process that opened it and is closed when that process exits. Coordinates are relative to the client area; every draw is clipped to the client area and to the parts of it not covered by other windows. Nothing reaches the screen until `SYS_WINFLUSH` (or the next `wm_update`).

| No. | Name | In | Out |
|-----|------|----|-----|
| 48 | `SYS_WINOPEN` | ebx = block: x, y, width, height (dwords, outer size), title address, flags | window id, or −1 |
| 49 | `SYS_WINCLOSE` | ebx = id | 0, or −1 if not the caller's |
| 50 | `SYS_WINMOVE` | ebx = id, ecx = x \| y << 16, edx = width \| height << 16 (0 keeps that pair) | 0 or −1 |
| 51 | `SYS_WINTITLE` | ebx = id, ecx = title | 0 or −1 |
| 52 | `SYS_WINDRAW` | ebx = id, ecx = command block (below) | 0 or −1 |
| 53 | `SYS_WINFLUSH` | ebx = id | 0 or −1; the dirty parts reach the screen |
| 54 | `SYS_WINEVENT` | ebx = 16-byte buffer, ecx = 0 wait / 1 poll | 0 and the buffer filled, or −1 (poll, nothing waiting) |
| 55 | `SYS_WININFO` | ebx = id (−1 for the screen), ecx = 16-byte buffer | 0 and client x, y, width, height (screen: 0, 0, width, height) |

`SYS_WINDRAW` command block, dwords: `op`, `x`, `y`, `a`, `b`, `colour`, `ptr`.

| `op` | Meaning |
|------|---------|
| `WD_FILL` (0) | filled rectangle at x, y, size a × b |
| `WD_LINE` (1) | line from x, y to a, b |
| `WD_TEXT` (2) | the 5×7 font string at `ptr`, bg = `a` (−1 transparent) |
| `WD_PTEXT` (3) | proportional string at `ptr`, face `b`, bg = `a` |
| `WD_BLIT` (4) | a × b bytes of 8-bit pixels at `ptr` (one byte per pixel, rows packed) to x, y; `colour` = transparent index or −1 |
| `WD_BEVEL` (5) | bevel around x, y, a × b; `colour` 0 raised / 1 sunken |
| `WD_COPY` (6) | copy the client rectangle at (`a` & 0xFFFF, `a` >> 16), size `b` & 0xFFFF × `b` >> 16, to x, y |

Event record from `SYS_WINEVENT`, dwords: `type`, `window`, `p1`, `p2`.

| `type` | `p1` | `p2` |
|--------|------|------|
| `WE_KEY` (1) | key, as `wg_key` takes it | shift state |
| `WE_DOWN` (2) / `WE_UP` (3) / `WE_MOVE` (4) | x \| y << 16, client-relative | buttons |
| `WE_DBLCLK` (5) | x \| y << 16 | buttons |
| `WE_CLOSE` (6) | — | — (the close box or Alt+F4; the program decides whether to `SYS_WINCLOSE`) |
| `WE_SIZE` (7) | new client width \| height << 16 | — |
| `WE_PAINT` (8) | x \| y << 16 of the area to redraw | width \| height << 16 |
| `WE_BUTTON` (9) | widget code | — |

Each process has its own ring of 16 events. When an event is queued, the kernel also posts `MSG_WIN` (`0x57000000`, `'W'` in the top byte, the window id in the low byte) to the owner's message queue, so a program already waiting in `SYS_RECV` wakes up; it then reads the events with `SYS_WINEVENT`. A full ring drops the oldest `WE_MOVE` first.

Widgets in program windows (buttons, fields, lists, menus) get syscalls in 2.3; until then a program draws its own controls with `WD_BEVEL` and `WD_PTEXT`.
