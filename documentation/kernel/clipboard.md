# Clipboard (2.3-clipboard)

The kernel holds one text clipboard of up to 1024 bytes (`CLIP_MAX`, `kernel/clip.asm`). What is copied replaces what was there. The clipboard lasts until the next copy or a reboot.

## Keys

| Keys | In a field widget | In `edit` / `vedit` |
|------|-------------------|---------------------|
| Ctrl+Ins, Ctrl+C | copy the field's text | copy the cursor's line (without its newline) |
| Shift+Ins, Ctrl+V | paste at the end, up to the first newline and as much as the field takes | type the clipboard at the cursor (one Ctrl+Z takes it back) |
| Shift+Del, Ctrl+X | cut: copy the text, then empty the field | cut the cursor's line and its newline |

`clip_key` turns those keys (al = the scancode, after `kbd_shift_track`) into the widget keys `WK_COPY` (0x03), `WK_PASTE` (0x16) and `WK_CUT` (0x18). `wg_getkey`, `dk_trykey` and `fieldtest` call it, and `wg_key` passes the widget keys to the focused window's field (`clip_field`). The editors read Ctrl and Shift themselves.

## Kernel

| Routine | In | Out |
|---------|----|-----|
| `clip_put` | esi = text, ecx = length | the clipboard holds it, cut to `CLIP_MAX`; eax = the length kept |
| `clip_get` | edi = buffer, ecx = its size | as much as fits is copied (no zero added); eax = the clipboard's length |

## System calls

| No. | Name | In | Out |
|-----|------|----|-----|
| 49 | `SYS_CLIPPUT` | ebx = text, ecx = length | the length kept |
| 50 | `SYS_CLIPGET` | ebx = buffer, ecx = its size | the clipboard's length; as much as fits is copied |

From ring 3, ebx must point at ecx bytes of the program's own memory (`UA_B_C`).

## Clipboard viewer

`run clipbrd` (`programs/clipbrd.asm`) is a ring-3 program with a window (`windows.md`, the program calls). It shows the clipboard's text one line per row in the window face (`WD_PTEXT`), or `(empty)`. It paints again on `WE_PAINT`. `q` or Alt+F4 closes it, and on the way out it prints `clipbrd: N bytes`.

## Checks

`cbtest` (the name `cliptest` is the 2.1 clip-rectangle test) works through two windows:
- In the first window, a field holds `clip me`; `WK_COPY` copies it.
- In a second window with an empty field, `WK_PASTE` pastes it and `WK_CUT` empties the field.
- `SYS_CLIPGET` reads `clip me` back.

It prints `clip: PASS` or `clip: FAIL`. Checks:
- `cbtest`
- `cbtest-text`
- `ed-clip-copy`: `abc and abc`
- `ed-clip-cut`: `two one`
- `clip-viewer` and `clip-viewer-n`: the viewer after `cbtest`
- `clip-empty`: the viewer after a fresh boot
