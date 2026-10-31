# Widgets

Widgets (`kernel/widget.asm`, since 1.5.0) are drawn inside windows (`windows.md`). Each widget belongs to one window and has a place relative to the top left of that window's client area. When the window manager draws a window, it draws the window's widgets after the client area. Closing a window drops its widgets. Keyboard only.

## Widgets

The kernel keeps a table of up to 16 widgets (`WG_MAX`), shared by all windows. Each record holds:

| Field | Meaning |
|-------|---------|
| `WG_USED` | 1 while the widget exists |
| `WG_KIND` | what it is: `WGK_LABEL` or `WGK_BUTTON` |
| `WG_WIN` | the window it belongs to |
| `WG_X`, `WG_Y` | its place in the client area, in pixels |
| `WG_TEXT` | address of a zero-terminated string |
| `WG_PID`, `WG_CODE` | button: the process its events go to, and its code |

A widget is cut to its window's client area. A label whose text row does not fit below is not drawn; a label that runs past the right edge loses the characters that do not fit.

## Label

A label is one line of text in black (`WM_TEXT`) on the client colour. It does nothing with keys.

| Routine | In | Out |
|---------|----|-----|
| `wg_label` | eax = window id, ebx = x, ecx = y, esi = text | eax = widget id, or −1 if the window is not open or the table is full |
| `wg_drop` | eax = window id | removes all of that window's widgets (`wm_close` calls it) |

Adding a widget does not draw it; the caller calls `wm_redraw`.

## Button

A button is its text in a white box with a black border, 2 pixels of padding around the text (`WG_BTN_PAD`). The box is cut at the client area's right edge.

| Routine | In | Out |
|---------|----|-----|
| `wg_button` | eax = window id, ebx = x, ecx = y, esi = text, edx = code | eax = widget id, or −1 |
| `wg_key` | al = ASCII of a key | CF clear if a widget used the key, CF set if not |

`wg_button` records the calling process (`proc_cur`) as the button's owner. `wg_key` takes Enter (10 or 13) and Space. If the focused window (`wm_focus`) has a button, its first button posts `MSG_BUTTON | code` to the owner's queue (`messages.md`). `MSG_BUTTON` is `0x42000000` (`'B'` in the top byte), and the code is the low 24 bits. The post is the same `msg_put` that `SYS_SEND` uses, with interrupts off; a full queue drops the event. Other keys come back with CF set for the caller to use. A window with several buttons, and moving between widgets, come with the later widgets.

## Tests

`labeltest` switches to graphics mode and opens a window. It reads the pixel where the label's first glyph will go, which must be the client colour. It then adds the label `Name: Squirrel` at (4, 4) and redraws. The top left pixel of `N` must now be ink, and the pixel next to it must be background. It closes the window and opens a new one in the same slot. That window must not show the old label. The test prints `label: PASS` or `label: FAIL`. Checks `labeltest` and `labeltest-text` (`systest` after it).

`buttontest` (1.5.1) empties the shell's queue (the shell is pid 0), then opens a window with the label `Press Enter:` and an `OK` button with code `0xB7`. It reads back the box's top left pixel, which must be black. Keys go to `wg_key` until Esc. Then it reads the shell's queue. Every message must be `MSG_BUTTON | 0xB7`, and there must be one per press. It prints `button: PASS (n)` for n events, `button: no event`, or `button: FAIL`. Checks: `buttontest` (Enter: 1 event), `buttontest-2` (Space, `x`, Space: 2 events, so `x` posts nothing), `buttontest-none` (`x` only), and `buttontest-text`.

## Later in 1.5

A one-line edit field and a list (`../../TODO.md`). Those widgets take keys and talk to the 1.2 message queue.
