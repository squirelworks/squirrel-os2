# Widgets

Widgets (`kernel/widget.asm`, since 1.5.0) are drawn inside windows (`windows.md`). Each widget belongs to one window and has a place relative to the top left of that window's client area. When the window manager draws a window, it draws the window's widgets after the client area. Closing a window drops its widgets. Keyboard only.

## Widgets

The kernel keeps a table of up to 16 widgets (`WG_MAX`), shared by all windows. Each record holds:

| Field | Meaning |
|-------|---------|
| `WG_USED` | 1 while the widget exists |
| `WG_KIND` | what it is: `WGK_LABEL`, `WGK_BUTTON`, `WGK_FIELD`, `WGK_LIST` or `WGK_CONSOLE` |
| `WG_WIN` | the window it belongs to |
| `WG_X`, `WG_Y` | its place in the client area, in pixels |
| `WG_TEXT` | address of a zero-terminated string |
| `WG_PID`, `WG_CODE` | button: the process its events go to, and its code; field: `WG_CODE` is the most characters; list: `WG_CODE` is how many items |
| `WG_SEL` | list: the selected item, from 0 |

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

`wg_button` records the calling process (`proc_cur`) as the button's owner. A button posts `MSG_BUTTON | code` to its owner's queue (`messages.md`). `MSG_BUTTON` is `0x42000000` (`'B'` in the top byte), and the code is the low 24 bits. The post is the same `msg_put` that `SYS_SEND` uses, with interrupts off; a full queue drops the event.

## Edit field

A field is a box as wide as its most characters, showing the text of a buffer the caller owns and an underline cursor after it. Editing changes the buffer in place, so the caller reads the text from it at any time.

| Routine | In | Out |
|---------|----|-----|
| `wg_field` | eax = window id, ebx = x, ecx = y, esi = buffer (zero-terminated, room for edx characters and the zero), edx = most characters | eax = widget id, or −1 |

## List

A list is a box as wide as its longest item, with one row per item. The selected row is a black bar with white text. If not all rows fit in the client area, the list is not drawn.

| Routine | In | Out |
|---------|----|-----|
| `wg_list` | eax = window id, ebx = x, ecx = y, esi = items (an array of edx addresses of zero-terminated strings), edx = how many, at least 1 | eax = widget id, or −1; the first item is selected |
| `wg_selected` | eax = a list's widget id | eax = its selected item, from 0 |

## Console

A console shows part of an 80 × 25 text buffer laid out as at `0xB8000` (character and attribute words). The characters are drawn in black on the client colour; a cell whose attribute has a background colour (such as the editor's status row) is drawn inverted, and the cell at the cursor is drawn inverted too (or back to normal, on such a row), as a block cursor. As many columns as fit are shown. The rows shown are the first `edx`, or the `edx` rows that end at the cursor row (`cur`) once the cursor is further down. If those rows do not fit in the client area, the console is not drawn. It takes no keys. The desktop uses it to run text programs in windows (`../apps/desktop.md`).

| Routine | In | Out |
|---------|----|-----|
| `wg_console` | eax = window id, ebx = x, ecx = y, esi = buffer, edx = rows shown | eax = widget id, or −1 |

## Keys

`wg_key` (al = ASCII, 8 for Backspace, `WK_UP` 0x18 and `WK_DOWN` 0x19 for the arrows) gives a key to the first widget of the focused window (`wm_focus`) that takes keys: a button, a field or a list. It returns CF clear if the widget used the key, CF set if not, so the caller can use it.

- Button: Enter (10 or 13) or Space posts its event.
- Field: a printable character (0x20 to 0x7E) is appended if there is room; when the field is full the key is used and dropped. Backspace deletes the last character. Enter and Esc are not used.
- List: `WK_DOWN` and `WK_UP` move the selection and stop at the first and last item. Other keys are not used.

The caller turns keys into these codes; the scancodes for the arrows are 0x48 (Up) and 0x50 (Down). Moving between widgets in one window is not there yet: the first widget that takes keys gets them.

## Tests

The test windows put a label at (4, 5) and the box beside it (field, list) at (44, 2). The label's text is then level with the text inside the box (2 pixels down for the border and padding, plus one), and there are 10 pixels between a 5-character label and the box.


`labeltest` switches to graphics mode and opens a window. It reads the pixel where the label's first glyph will go, which must be the client colour. It then adds the label `Name: Squirrel` at (4, 5) and redraws. The top left pixel of `N` must now be ink, and the pixel next to it must be background. It closes the window and opens a new one in the same slot. That window must not show the old label. The test prints `label: PASS` or `label: FAIL`. Checks `labeltest` and `labeltest-text` (`systest` after it).

`buttontest` (1.5.1) empties the shell's queue (the shell is pid 0), then opens a window with the label `Press Enter:` and an `OK` button with code `0xB7`. It reads back the box's top left pixel, which must be black. Keys go to `wg_key` until Esc. Then it reads the shell's queue. Every message must be `MSG_BUTTON | 0xB7`, and there must be one per press. It prints `button: PASS (n)` for n events, `button: no event`, or `button: FAIL`. Checks: `buttontest` (Enter: 1 event), `buttontest-2` (Space, `x`, Space: 2 events, so `x` posts nothing), `buttontest-none` (`x` only), and `buttontest-text`.

`fieldtest` (1.5.2) opens a window with the label `Name:` and a 16-character field over an empty buffer. Keys go to `wg_key`, with the Backspace scancode passed as 8, until Enter or Esc. It then reads the field box's top left pixel, which must be black, and prints `field: PASS "<text>"` with the buffer's text, or `field: FAIL`. Checks: `fieldtest` (`Hi there`, two Backspaces: `"Hi the"`), `fieldtest-full` (20 letters: the first 16 stay), and `fieldtest-text`. Without the store in `wg_key`, `fieldtest` prints `field: PASS ""`, and the check fails.

`listtest` (1.5.3) opens a window with the label `Pick:` and a list of `Acorn`, `Beech`, `Cedar` and `Dogwood`. Keys go to `wg_key`, with the arrows passed as `WK_UP` and `WK_DOWN`, until Enter or Esc. It reads a pixel of the selected row below its text, which must be the black bar, and prints `list: <name>` with the selected item, or `list: FAIL`. Checks: `listtest` (Down: `Beech`), `listtest-end` (five Downs: `Dogwood`), `listtest-up` (Down, Up, Up: `Acorn`), and `listtest-text`. With the selection store taken out of `wg_key`, `listtest` prints `list: Acorn` and the check fails.

## Next

The desktop shell (1.6) hosts the applications as windows (`../../ROADMAP.md`).
