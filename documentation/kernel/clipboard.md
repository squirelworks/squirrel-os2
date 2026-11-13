# Text clipboard (2.3-clipboard)

One kernel text clipboard, shared by field widgets, the editors (`edit` /
`vedit`), the Clipboard viewer, and programs through system calls. Original
code in `kernel/clipboard.asm`.

## Buffer

Up to 1023 characters of text plus a terminating zero (`CLIP_MAX` is 1024).
There is one clipboard for the whole system. It starts empty each boot.

| Routine | In | Out |
|---------|----|-----|
| `clip_put` | `esi` = text, `eax` = length | stores the text (capped), `eax` = length stored, or −1 |
| `clip_get` | `edi` = buffer, `ecx` = most characters | copies into the buffer (zero-terminated), `eax` = length copied |

## System calls

| # | Name | Args | Returns |
|---|------|------|---------|
| 45 | `SYS_CLIPPUT` | `ebx` = ASCIIZ text | length stored, or −1 |
| 46 | `SYS_CLIPGET` | `ebx` = buffer, `ecx` = most characters | length copied |

Listed in `syscalls.md`. Ring-3 callers are pointer-checked (`ring3.md`).

## Keys

In a field widget (`widgets.md`):

| Key | Action |
|-----|--------|
| Ctrl+Ins or Ctrl+C | copy the field's text |
| Shift+Ins or Ctrl+V | paste (append) into the field |
| Shift+Del or Ctrl+X | cut the field (copy, then clear) |
| Tab | next keyable widget in the same window |

`wg_getkey` (`desktop.asm`) turns those chords into `WK_COPY` / `WK_PASTE` /
`WK_CUT` / `WK_TAB` for `wg_key`.

In `edit` / `vedit` (`../apps/editors.md`) the same chords act on the current
line: copy and cut take the line without its newline; paste inserts at the
cursor. The message line says `Copied.`, `Pasted.`, `Cut.`, or
`Clipboard empty.`

## Viewer

`clipboard` opens a window titled `Clipboard` showing the text, or
`(empty)`, and Esc closes it.

## Checks

`cbtest` (named so it does not collide with the 2.1 blit `cliptest`) opens a
window with two fields, types `acorn` into the first, copies, Tabs to the
second, pastes, checks both buffers, cuts the second, checks the clipboard
still holds `acorn`, then puts and gets `xyz` through `sys_clipput` /
`sys_clipget`. It prints `clipboard: PASS` or `clipboard: FAIL`. Checks
`cbtest` and `cbtest-text`. Editor checks: `ed-clip-copy`, `ed-clip-paste`.
The viewer check `clipboard-view` reads `(empty)` off the graphics screen.
