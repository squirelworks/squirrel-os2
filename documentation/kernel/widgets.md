# Widgets

Widgets (`kernel/widget.asm`, since 1.5.0) are drawn inside windows (`windows.md`). Each widget belongs to one window and has a place relative to the top left of that window's client area. When the window manager draws a window, it draws the window's widgets after the client area. Closing a window drops its widgets. Keyboard only.

## Widgets

The kernel keeps a table of up to 16 widgets (`WG_MAX`), shared by all windows. Each record holds:

| Field | Meaning |
|-------|---------|
| `WG_USED` | 1 while the widget exists |
| `WG_KIND` | what it is: `WGK_LABEL` |
| `WG_WIN` | the window it belongs to |
| `WG_X`, `WG_Y` | its place in the client area, in pixels |
| `WG_TEXT` | address of a zero-terminated string |

A widget is cut to its window's client area. A label whose text row does not fit below is not drawn; a label that runs past the right edge loses the characters that do not fit.

## Label

A label is one line of text in black (`WM_TEXT`) on the client colour. It does nothing with keys.

| Routine | In | Out |
|---------|----|-----|
| `wg_label` | eax = window id, ebx = x, ecx = y, esi = text | eax = widget id, or −1 if the window is not open or the table is full |
| `wg_drop` | eax = window id | removes all of that window's widgets (`wm_close` calls it) |

Adding a widget does not draw it; the caller calls `wm_redraw`.

## Test

`labeltest` switches to graphics mode and opens a window. It reads the pixel where the label's first glyph will go, which must be the client colour. It then adds the label `Name: Squirrel` at (4, 4) and redraws. The top left pixel of `N` must now be ink, and the pixel next to it must be background. It closes the window and opens a new one in the same slot. That window must not show the old label. The test prints `label: PASS` or `label: FAIL`. Checks `labeltest` and `labeltest-text` (`systest` after it).

## Later in 1.5

A button that activates from the keyboard, a one-line edit field, and a list (`../../TODO.md`). Those widgets take keys and talk to the 1.2 message queue.
