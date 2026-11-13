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

## Mouse: raise, move, size, maximise (2.2-mouse)

`wm_mouse` (eax = x, ebx = y, cl = buttons, bit 0 the left one) takes one mouse state at a time; `wm_inject` is the same routine, for scripts and checks. It keeps the previous buttons, so it sees a press, a drag (button held, pointer moved) and a release. It does not draw: the caller calls `wm_update`.

- A press over a window raises it and gives it the focus (z-order by mouse). Then, by `wm_hit` part: the title starts a move; an edge or corner of a sizable window starts a size; the maximise box maximises the window to the whole screen (saving its rectangle in `WIN_REST`, `WIN_STATE` = `WS_MAX`) or, when it is maximised, restores it. A maximised window cannot be moved or sized.
- While the button is held, a move puts the window at its press-time place plus the pointer's travel; a size moves the edges the part names (`wm_sides`), never below `WM_MIN_W` × `WM_MIN_H` (a left or top edge then stops so the opposite edge stays put). Each step goes through `wm_place` (x, y, width, height in one call; CF and no change when `wm_fits` refuses), so a window dragged past what `wm_fits` allows stays at its last allowed place. The release ends the drag.
- The reply in eax: `WME_NONE`; `WME_CLIENT` with ebx = the window and ecx = x | y << 16 in its client area; `WME_CLOSE` with ebx = the window, or `WME_MENU` (below). Closing is the caller's decision (a program may ask to save first). The system-menu box opens the system menu (**2.2-sysmenu**). The minimise box minimises the window itself (**2.2-minmax**, below).

The desktop (`../apps/desktop.md`) passes every change of the mouse to `wm_mouse`, repaints with `wm_update`, and closes when its own close box is clicked. Its list clicks use the window's current place, so they still work after it is moved.

`windrag` enters the window manager's screen with One at (100, 100) and Two over it at (200, 180), both 200 × 150, and replays a script of mouse states through `wm_inject`, calling `wm_update` after each: a press on One's title (it comes to the top) and a drag by (20, 20); a drag of its bottom-right corner (which Two covered before One came up) by (30, 20); of its left edge 20 to the left; of its right edge far to the left (it stops at the minimum width); a click on the maximise box (One fills the screen) and on the box's new place (One is restored); a client click (the reply and client coordinates are checked); and the close box (the reply is checked, then One is closed and Two must have the focus). After each release it compares One's rectangle with the expected one. It prints `windrag: PASS` or `windrag: FAIL`. Checks `windrag` and `windrag-text`.

`tools/qemu_screen.py` copies each `<gfx>` screen dump into the directory named by `QEMU_SHOTS`, when that is set, for looking at by hand.

## Minimise to icons (2.2-minmax)

`wm_minimise` (eax = id) takes a window with a minimise box out of the z-order and sets `WIN_ICONIC`, so it is not drawn, hit, focused or cycled; the next window down gets the focus. Every minimised window shows as an icon along the bottom of the desktop, `WM_ICON_W` × `WM_ICON_H` (72 × 20) with `WM_ICON_GAP` (8) around them: the k-th minimised window in table order has the k-th place from the left, so icons close up when one is restored. An icon is a raised `gfx_bevel` button on the face colour with the start of the title. `wm_hit` reports an icon (when no window covers the point) as the window with part `HT_ICON`.

`wm_restore` (eax = id) puts a minimised window back on top with the rectangle and maximised state it had. With the mouse, two presses in a row on the same icon restore it (a double click; a press anywhere else in between starts over). `wm_setstate` (eax = id, ebx = `WS_NORMAL`, `WS_MAX` or `WS_MIN`) does any of these from code: `WS_MIN` minimises, `WS_NORMAL` / `WS_MAX` restore an icon first and then maximise or restore the size. Minimising or restoring repaints the whole screen (the icons can all move).

`winmin` opens One and Two (as `windrag`), clicks One's minimise box through `wm_inject`, and checks that Two has the focus, that `wm_hit` finds One's icon at the first place, and that the icon's bevel is on the visible page. It minimises Two with `wm_setstate` (nothing has the focus then), presses One's icon once, Two's once and One's once (nothing is restored), then One's again: One is back with the focus and its rectangle, and Two's icon is now first. Finally One is maximised, minimised and restored by a double click, and must come back maximised. It prints `winmin: PASS` or `winmin: FAIL`. Checks `winmin` and `winmin-text`.

## Pop-up menus and the system menu (2.2-sysmenu)

`wm_popup` (eax, ebx = top left, esi = an array of edx item addresses, at most 8, ecx = the owner window) opens a pop-up menu: a raised, bevelled column of items drawn above every window by `wm_paint`, the chosen item in `TH_SELECT` / `TH_SELECT_TEXT`. One menu is open at a time. While it is open:

- `wm_menukey` (al = a key as `wg_key` takes it) moves the choice with `WK_DOWN` / `WK_UP` (wrapping round), chooses with Enter (10 or 13) and closes with Esc. It returns CF set when no menu (and no keyboard move or size) is active, so the caller can use the key.
- `wm_mouse` gives the next press to the menu: a press on an item chooses it, a press anywhere else closes the menu.
- A choice in an ordinary menu replies `WME_MENU` with ebx = the owner and ecx = the item.

The system menu is a pop-up the window manager answers itself. It opens under the system-menu box when that is clicked, or for the focused window on Alt+Space (`wm_sysmenu`, eax = window). Its items: Restore (from maximised), Move, Size, Minimize, Maximize, and Close, which replies `WME_CLOSE` like the close box. Move and Size set `wm_kmode`; then the arrow keys (`WK_LEFT` 0x11 and `WK_RIGHT` 0x12 are new key codes, with `WK_UP` / `WK_DOWN`) move the window, or its right and bottom edges, 8 pixels a press through `wm_place` (so it never gets too small or loses its title bar), until Enter or Esc.

The keyboard driver now tracks Alt (`kbd_alt`, scancodes 0x38 / 0xB8, the same for right Alt after its 0xE0). The desktop passes Alt keys to `wm_altkey`, the side arrows and, while a menu or keyboard move is active, every key to `wm_menukey`, and quits when the reply closes its own window.

`winmenu` opens One and Two, presses Alt+Space (`wm_altkey`) for Two's menu and chooses Minimize with Down × 3, Enter; clicks One's system-menu box and then Maximize; Alt+Space, Enter (Restore); Move with right, right, down, Enter (One moves by 16, 8); Size with right, right, Enter (16 wider); checks Esc and a click outside each close a menu without acting; and that Close (Up from the first item wraps to it) replies `WME_CLOSE` for One. It prints `winmenu: PASS` or `winmenu: FAIL`. Checks `winmenu`, `winmenu-text`, `sysmenu-desk` (Alt+Space on the desktop shows the menu's items on the screen) and `sysmenu-desk-move`.

## Alt+Tab, Alt+Esc, Alt+F4 (2.2-alttab)

`wm_altkey` (al = the scancode of a key pressed with Alt down) handles:

- **Alt+Tab**: each press steps one window further down the z-order (the order windows were last used), wrapping back to the second, and shows the chosen window's title in a raised box in the middle of the screen. Letting go of Alt (`wm_altup`, called on scancode 0xB8) raises that window and removes the box.
- **Alt+Esc**: the top window goes to the bottom, so the next one gets the focus.
- **Alt+Space**: the focused window's system menu.
- **Alt+F4**: replies `WME_CLOSE` for the focused window.

Other keys return CF set. Minimised windows are not in the z-order, so they are not stepped through.

`winalttab` opens One, Two and Three (Three on top). Alt+Tab and letting go brings Two up; Alt+Tab twice shows the box (read on the visible page) and letting go brings One up; Alt+Esc sends One to the bottom and Two has the focus. It prints the titles from the top (`Two Three One`) and `alttab: PASS` or `alttab: FAIL`. Check `winalttab`.

## Proportional fonts (2.2-propfont)

Two original proportional faces sit beside the 5 × 7 font: `FONT_9`, the window face (9 pixels high: seven above the baseline, two of descender), and `FONT_12`, a bold display face 12 pixels high. Their sources are `tools/fontp9.txt` and `tools/fontp12.txt`, one line per glyph: the code in hex, then the rows, each one to eight `#` or `.` wide (every row of a glyph the same width). `tools/mkfont.py` writes `kernel/fontp.inc` from them (a width table and one byte per row, bit 7 the leftmost column) and `--check` fails the regress run if it is stale. Each glyph is followed by one spacing column; the space is 3 pixels in `FONT_9`, 4 in `FONT_12`.

`gfx_drawstr_p` and `gfx_strwidth_p` (`kernel/pfont.asm`) draw and measure a string; see the table below. A background of `0xFF` in `gfx_bg` is transparent: only the ink is drawn. `wm_drawtitle` uses `FONT_9`, so title bars, pop-up menus (their width is the widest item's `gfx_strwidth_p`), icon labels, the Alt+Tab box, labels and buttons are in the window face. Typed text in a window, fields and lists keep the 5 × 7 font in 6 × 8 cells (`wm_drawtext5`), because there a character's cell is its place (the field cursor, list rows).

`tools/qemu_screen.py` reads both faces as well as the 5 × 7 font: a run of glyphs on a solid background, each matched column for column, with a spacing column after it; a gap one space wide is a space. Words it finds inside 5 × 7 text are dropped. It needs numpy; without it only the 5 × 7 font is read.

`pfont` draws a line in each face on a blue band, reads back ink, clear and spacing pixels, a descender, a transparent `i` and the pixel left of the string, and checks `gfx_strwidth_p` against the x that `gfx_drawstr_p` returns (`Wg` is 11 pixels in `FONT_9`, 13 in `FONT_12`). The lines stay up until a key, then text mode and `pfont: PASS` or `pfont: FAIL`. Checks `pfont`, `pfont-read` (the screen reader finds both lines) and `pfont-text`. Programs draw the window face with `WD_PTEXT`; `progwin` checks its width and a pixel.

## Widgets

Since 1.5.0, `wm_draw` draws a window's widgets after its client area, and `wm_close` drops them (`widgets.md`).

Since 2.3-groups a window record has `WIN_PAINT`: 0, or code that `wm_draw` calls after the widgets to paint the client area itself, with edi = the record and eax, ebx, ecx, edx = the client area (it keeps every register). `wm_create` sets it to 0. The Program Manager's group windows use it (`apps/progman.md`).

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
| `gfx_drawstr_p` | esi = string, eax, ebx = top left, ecx = face (`FONT_9` / `FONT_12`), colours in `gfx_colour` / `gfx_bg` (`0xFF` bg = transparent) | eax = x after the last character's spacing column (**2.2-propfont**) |
| `gfx_strwidth_p` | esi = string, ecx = face | eax = width in pixels, spacing columns included (what `gfx_drawstr_p` advances) |

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

### Programs (syscalls, **2.2-progwin**, in the kernel since 2.2-progwin)

The calls are in `kernel/winsys.asm`, numbers 37–44 (`SYS_COUNT` is 45; 35 is `SYS_GUI`, 36 is `SYS_SETTLS`). A window belongs to the process that opened it (`WIN_OWNER`, its pid; −1 for the kernel's own windows) and is closed when that process exits (`proc_exit` calls `ws_procgone`). Only the owner may use a window. Coordinates are relative to the client area. From ring 3 every pointer (the blocks, the title, a string, blit bytes, the event buffer) must be the program's own memory (`ua_range` / `ua_str`, `ring3.md`), or the call returns −1.

| No. | Name | In | Out |
|-----|------|----|-----|
| 37 | `SYS_WINOPEN` | ebx = block: x, y, width, height (outer size), title address, flags (0 = `WF_DEFAULT`), six dwords | window id, or −1. In text mode the first window enters the window manager's screen (`wm_screen`); when the last program window closes the screen goes back to text. The title is copied into the record (`WIN_TBUF`, up to 31 characters). |
| 38 | `SYS_WINCLOSE` | ebx = id | 0, or −1 if not the caller's |
| 39 | `SYS_WINMOVE` | ebx = id, ecx = x \| y << 16, edx = width \| height << 16 (0 keeps that pair) | 0 or −1 (`wm_place` refused) |
| 40 | `SYS_WINTITLE` | ebx = id, ecx = title | 0 or −1 |
| 41 | `SYS_WINDRAW` | ebx = id, ecx = command block | 0 (`WD_PIXEL`: the colour), or −1 |
| 42 | `SYS_WINFLUSH` | ebx = id | 0 or −1: the window manager's pending repaints (`ws_update`), then the window's area is flipped to the visible page |
| 43 | `SYS_WINEVENT` | ebx = 16-byte buffer, ecx = 0 wait / 1 poll | 0 and the buffer filled, or −1 (poll, nothing waiting) |
| 44 | `SYS_WININFO` | ebx = id (−1 for the screen), ecx = 16-byte buffer | 0 and the client area's x, y, width, height on the screen (the screen: 0, 0, width, height) |

`SYS_WINDRAW` command block, seven dwords: `op`, `x`, `y`, `a`, `b`, `colour`, `ptr`. Every draw is clipped to the client area (`gfx_setclip`) and kept off the windows above it and an open menu (`gfx_occ`, `gfx_occn`: `gfx_putpixel` skips pixels inside those rectangles). Nothing reaches the visible page until `SYS_WINFLUSH`.

| `op` | Meaning |
|------|---------|
| `WD_FILL` (0) | filled rectangle at x, y, size a × b |
| `WD_LINE` (1) | line from x, y to a, b |
| `WD_TEXT` (2) | the 5×7 font string at `ptr`, background `a` (−1: the client colour) |
| `WD_PTEXT` (3) | the proportional string at `ptr`, background `a` (−1: none, only the ink), face `b` (0 `FONT_9`, 1 `FONT_12`); returns its width in pixels (**2.2-propfont**) |
| `WD_BLIT` (4) | a × b bytes of 8-bit pixels at `ptr` (rows packed) to x, y; `colour` = an index left transparent, or −1 |
| `WD_BEVEL` (5) | bevel around x, y, a × b; `colour` 0 raised / 1 sunken |
| `WD_PIXEL` (7) | returns the colour at x, y on the visible page (for checks) |

`WD_COPY` (6) comes later.

There is no backing store. When the window manager repaints part of a program's window (uncovered, moved, focus changed), it paints the frame and a plain client area and posts `WE_PAINT`; the program draws again.

Event record from `SYS_WINEVENT`, dwords: `type`, `window`, `p1`, `p2`.

| `type` | `p1` | `p2` |
|--------|------|------|
| `WE_KEY` (1) | key, as `wg_key` takes it, for the focused window | 1 if Shift is down |
| `WE_DOWN` (2) | x \| y << 16, client-relative, of a left press | buttons |
| `WE_CLOSE` (6) | — | — (the close box, the system menu's Close or Alt+F4; the program decides whether to `SYS_WINCLOSE`) |
| `WE_PAINT` (8) | 0 (the whole client area) | client width \| height << 16 |

`WE_UP`, `WE_MOVE`, `WE_DBLCLK`, `WE_SIZE` and `WE_BUTTON` keep their numbers (3, 4, 5, 7, 9) for later. Each process has a ring of 16 events (`ws_ring`); a full ring drops new events. A process's events are forgotten when it exits.

While a program waits in `SYS_WINEVENT` on a graphics screen, the kernel runs the window manager for it (`ws_pump`): mouse changes go through `wm_mouse`, Alt keys through `wm_altkey`, menu and keyboard move/size keys through `wm_menukey`, and other keys become `WE_KEY` for the program owning the focused window. Repaints go through `ws_update`, which posts `WE_PAINT` to every program window a dirty area touches, then `wm_update`. `vm_map_range` now also writes the framebuffer's page-directory entries into the directory in use and keeps CR3, so a program that enters the graphics screen from its own address space can reach the framebuffer.

`programs/winprog.asm` (`run winprog`) opens One, fills and writes in it, flushes and reads a pixel back; opens Two over One's middle, fills a rectangle in One that reaches under Two, and checks the pixel left of Two is drawn and Two's client is not; checks `SYS_WININFO`; then waits for events: a key (it remembers it) and `WE_CLOSE` for Two (Alt+F4), on which it closes both. Back in text mode it prints `progwin key: x` and `progwin: PASS`. Checks `progwin` (with `x` and Alt+F4 sent) and `progwin-text`.

Widgets in program windows (buttons, fields, lists, menus) get syscalls in 2.3; until then a program draws its own controls with `WD_BEVEL` and `WD_TEXT`.
