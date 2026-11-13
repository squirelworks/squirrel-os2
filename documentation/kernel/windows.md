# Windows

The window manager (`kernel/wm.asm`, since 1.4.0) draws windows in graphics mode with the primitives in `graphics.md`. Keyboard, and on the desktop a mouse (`mouse.md`).

## Screen (2.2-vbe-wm)

`wm_screen` enters the screen the window manager draws on: 640×480 at 8 bpp through VBE (`vbe_setup`, `vbe_mode`), or VGA mode 13h (320×200) when VBE is not there or refuses the mode. CF means neither could be entered. Colours are palette indices in both, from `kernel/theme.inc`; the DAC keeps the EGA palette in either mode. `wm_create`, `wm_move`, `wm_resize` and `wm_redraw` use the live size (`gfx_width`, `gfx_height`), not 320×200. The desktop (`../apps/desktop.md`) uses `wm_screen`; the 1.4 tests (`wintest`, `winmove`, `winfocus`) and the widget tests still enter mode 13h themselves, so their pixel positions are unchanged. Since **2.2-clip-z** `wm_screen` also arms double buffering (`vbe_dblbuf`), so the window manager draws on the back page and flips (see below); a mode without room for two pages draws on the front.

`winvbe` enters the screen, opens a 200 × 120 window at (400, 300), which is wholly outside 320×200, redraws, and reads back its left edge and bottom-right corner (frame), the title bar, the client area and the desktop just left of it. It closes the window, redraws, and checks the left edge is desktop again. It returns to text mode and prints `winvbe: PASS`, or `winvbe: FAIL` (also when VBE was not entered). Checks `winvbe` and `winvbe-text`.

## Windows

The kernel keeps a table of up to 16 windows (`WM_MAX`; 4 before 2.2-clip-z). Each record holds:

| Field | Meaning |
|-------|---------|
| `WIN_USED` | 1 while the window is open |
| `WIN_X`, `WIN_Y` | top left corner, in pixels |
| `WIN_W`, `WIN_H` | outer size, frame included |
| `WIN_TITLE` | address of a zero-terminated title |
| `WIN_LEN`, `WIN_BUF` | the characters typed into the window (up to 24) and their count |
| `WIN_FLAGS` | `WF_*`: which title-bar boxes it has and whether it can be sized (2.2-frame) |

A window is a one-pixel frame (white, `WM_FRAME`), a title bar one text row high plus a margin (with the title in white), and a client area below it (light grey, `WM_CLIENT`) that shows the window's typed text in black. The title bar is blue (`WM_BAR`) on the focused window and dark grey (`WM_BAR_IDLE`) on the others. The desktop behind the windows is cyan (`WM_DESKTOP`). The colours are the text mode's EGA palette, which the DAC keeps in mode 13h: the bright colours are at `0x38`–`0x3F`.

## Z-order and focus

Since 1.4.2 the kernel keeps the open windows in a z-order list (`wm_z`, bottom first). A new window goes on top. The top window has the keyboard focus. `wm_redraw` draws from the bottom up, so a window covers the ones below it. Tab (in `winfocus`) calls `wm_cycle`, which brings the bottom window to the top: with two windows the focus goes back and forth.

## Calls

| Routine | In | Out |
|---------|----|-----|
| `wm_create` | eax = x, ebx = y, ecx = width, edx = height, esi = title | eax = window id, or −1 if the table is full, the window is smaller than 16 × 14, or its title bar would not be on the screen (below) |
| `wm_close` | eax = window id | the slot is free; an id that is not open is ignored |
| `wm_move` | eax = window id, ebx = new x, ecx = new y | CF if the id is not open or the title bar would leave the screen; the window is then unchanged |
| `wm_resize` | eax = window id, ebx = new width, ecx = new height | the top left corner stays; CF as `wm_move`, or if the new size is below the minimum |
| `wm_raise` | eax = window id | puts the window on top, which gives it the focus; CF if the id is not open |
| `wm_cycle` | — | brings the bottom window to the top (nothing with fewer than two) |
| `wm_focus` | — | eax = the focused (top) window's id, or −1 |
| `wm_putc` | al = character | appends it to the focused window's text if there is room |
| `wm_redraw` | — | paints the desktop, then every open window, bottom first, flips the whole page when double buffering, and clears the dirty list |
| `wm_update` | — | repaints and flips only the areas marked dirty (2.2-clip-z, below) |
| `wm_invalidate` | eax = window id, or −1 for the whole screen | marks it dirty for `wm_update` |

None of these draw; the caller calls `wm_redraw` or, since 2.2-clip-z, `wm_update`. A title longer than the bar is cut at the last character that fits.

These are kernel routines. Programs cannot open windows yet.

## Test

`wintest` switches to graphics mode, draws an empty desktop, creates a 200 × 120 window titled `Test window` at (60, 40) and redraws. It reads back a pixel of the left frame and a pixel of the title's first letter, closes the window, redraws, and reads the frame pixel again, which must now be the desktop colour. It returns to text mode and prints `win: PASS` or `win: FAIL`. Checks `wintest` and `wintest-text` (`systest` after it).

`winmove` (1.4.1) creates the same window, moves it to (100, 60) and then resizes it to 100 × 60. After each step it reads back a pixel where the frame was, which must now be the desktop, and a pixel of the new frame. It then tries a move that puts the title bar wholly past the right edge (x = 320; since 2.2-clip-z a window may hang partly off the screen) and a width below the minimum; both must be refused and leave the window where it was. It prints `winmove: PASS` or `winmove: FAIL`. Checks `winmove` and `winmove-text`.

`winfocus` (1.4.2) is interactive. It opens two overlapping windows, One and then Two, so Two is on top. Tab swaps which window is on top and focused, other keys type into the focused window, and Enter or Esc ends. It then reads the pixel where Two's left edge crosses One's client area: the frame colour there means Two was drawn last. It closes both windows, returns to text mode and prints, for example:

```
winfocus:
One got "cd"
Two got "ab"
top: One
```

after `ab`, Tab, `cd`, Enter. Checks `winfocus` (that sequence), `winfocus-none` (no Tab: Two keeps the focus) and `winfocus-text`.

## Partly off-screen windows, dirty areas and partial repaint (2.2-clip-z)

A window may hang off the left, right and bottom edges of the screen. `wm_fits` (used by `wm_create`, `wm_move`, `wm_resize`) refuses only a window below the minimum size, one whose top edge is above the screen, one whose title bar would not fit in the screen's height, and one with no column on the screen (x at or past the right edge, or x + width at or before 0). Drawing off the screen is clipped by `gfx_putpixel`.

`wm_create`, `wm_close`, `wm_move` and `wm_resize` (old and new rectangle), `wm_raise` and `wm_putc` mark the screen areas they change in a list of up to 8 (`WM_DIRTY_MAX`); more, or `wm_invalidate -1`, means the whole screen. `wm_update` repaints each marked area: it sets the clip rectangle (`gfx_setclip`) to the area and paints the desktop and every window bottom first, so in that area each window shows exactly where nothing above it covers it, and no pixel outside the areas is written. `gfx_fillrect` loops only over the part of a rectangle inside the clip, so painting a large window into a small area is cheap. With double buffering it marks each area with `vbe_dirty` and flips once, so only those areas reach the visible page. `wm_redraw` stays a full repaint and full flip.

The mouse pointer (`mouse.md`) is drawn on the back page too; `ptr_show` marks the box it left and the box it now covers and flips just those.

`winclip` enters the window manager's screen with double buffering, opens One at (100, 100) and Two at (150, 150), both 200 × 150, and redraws. It changes one desktop pixel at (600, 20) on the back page only, moves Two to (380, 250) and calls `wm_update`. On the visible page it reads where Two covered One's client (One's client now), Two's old left edge inside One (One's client), Two's old place beyond One (desktop), Two's new left edge and title bar, and the changed pixel, which must still show the desktop there, while the back page must still hold the change: neither repainted nor flipped. It then moves Two so it hangs 160 pixels off the right edge (allowed; its left edge is read on the visible page after `wm_update`) and to x = 640 (refused), opens windows until the table holds 16 and checks the 17th is refused, closes them all, returns to text mode and prints `winclip: PASS` or `winclip: FAIL`. Checks `winclip` and `winclip-text`.

## Frame and hit testing (2.2-frame)

A new window has `WF_DEFAULT`: `WF_SIZABLE`, `WF_SYSMENU`, `WF_MINBOX`, `WF_MAXBOX` and `WF_CLOSEBOX`; `wm_setflags` (eax = id, ebx = flags) changes them. The title bar draws, inside the frame, a system-menu box at its left end and minimise, maximise and close boxes at its right end, as the flags ask. Each box is `WM_BOX` square (the bar's height, 10 pixels): the face colour, a raised `gfx_bevel`, and an original glyph in the 4 × 4 square inside the bevel: a bar across the middle (system menu), an X (close), a square outline with a thick top (maximise), a bar at the bottom (minimise). The title starts 2 pixels after the system-menu box and is cut before the right-hand boxes. The minimum window width (`WM_MIN_W`) is now 58 pixels, room for all four boxes and a little title.

`wm_hit` (eax = x, ebx = y) returns in eax the top window under the point, or −1 over the desktop, and in ebx the part (`HT_*`):

| Part | Where |
|------|-------|
| `HT_T`, `HT_B` | a sizable window's top two rows (the frame and the row below), and its bottom `WM_GRIP` (3) rows |
| `HT_L`, `HT_R` | its left and right 3 columns between those |
| `HT_TL`, `HT_TR`, `HT_BL`, `HT_BR` | the top or bottom band within `WM_CORNER` (8) pixels of an end |
| `HT_SYSMENU`, `HT_MIN`, `HT_MAX`, `HT_CLOSE` | the boxes, in the rest of the title bar |
| `HT_TITLE` | the rest of the title bar (and a window that cannot be sized has no edge parts) |
| `HT_CLIENT` | everything else |

The mouse (**2.2-mouse**) uses it to decide between moving, sizing and the boxes.

`winhit` opens One at (40, 30), 200 × 120, and Two over its bottom right at (150, 100), 120 × 80, in mode 13h, and calls `wm_hit` at 21 points: One's title, each box, the title between the boxes, each edge, three corners and the client; One just left of Two; Two's client, left edge, title and bottom-right corner where it covers One; and two points on the desktop. It also reads back One's close box (the bevel's light corner and the X's first pixel) and the system-menu bar. It prints `winhit: PASS` or `winhit: FAIL`. Checks `winhit` and `winhit-text`. `wintest` reads the title's first letter after the system-menu box.

## Widgets

Since 1.5.0, `wm_draw` draws a window's widgets after its client area, and `wm_close` drops them (`widgets.md`).

## The 2.2 API (planned)

This section is the window, event and drawing interface that the 2.2 boxes in `TODO.md` build, published before the code so programs (calculator, paint, games) can be written against it. It is a plan: register details can still change while a box is reviewed, and each box updates the section when it lands. Until then the 1.4–2.1 routines above are what the kernel has. Everything above stays valid; 2.2 adds to it.

### Screen and theme

- The window manager draws on the VBE back buffer, 640×480 at 8 bpp, and flips only the dirty rectangles (**2.2-vbe-wm**). Mode 13h (320×200) is the fallback, so programs read the screen size from `gfx_width` / `gfx_height` (or `SYS_WININFO`) and never assume one.
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
| `wm_create` | as before | as before, with `WF_DEFAULT`; `wm_setflags` changes the flags (2.2-frame); the caller's pid becomes the owner (**2.2-progwin**) |
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
