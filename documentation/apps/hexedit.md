# Hex editor (A.7)

`run hexedit <file>` shows and edits any file byte by byte. It is a program on the data disk (`programs/hexedit.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). Files up to 128 KB are held in memory from `SYS_SBRK`; a name that does not exist starts an empty file (`New file`). Without a name it prints `usage: run hexedit <file>`.

Each row shows 8 bytes: the offset in hex (`00010:`), the bytes in hex, and the same bytes as text (`.` for bytes outside space to `~`). Bytes changed since the last save are red. After the last byte, `__` marks where typing adds to the file. The cursor's byte is highlighted in both columns, yellow in the column that takes typing. The status row shows the cursor's offset and its byte in hex and decimal (`@00011 = AB 171`), the size and `*` while there are unsaved changes, or the last message.

| Key | Action |
|-----|--------|
| arrows | one byte / one row |
| PgUp / PgDn | 19 rows |
| Home / End | the row's first / last byte |
| Ctrl+Home / Ctrl+End | the file's start / end |
| left click | that byte, in the column clicked |
| `0`–`9`, `a`–`f` | in the hex column: the high half of the byte, then the low half (the cursor then moves on) |
| any character | in the text column: the byte, and the cursor moves on |
| Tab | the other column |
| Insert | a 0 byte before the cursor |
| Delete | remove the byte under the cursor |
| Ctrl+G | go to an offset, typed in hex on the status row |
| Ctrl+S | save |
| Esc | quit; with unsaved changes it asks `Save changes? y/n` (Esc again stays) |

## Self-check

`run hexedit test` writes `htest.bin` with the bytes 0 to 255 and reads it back; types `a`, `b` in the hex column at 0x10 and `Z` in the text column (0xAB, 0x5A); inserts a byte at 0 and deletes one at 0x20; adds a byte by typing at the end; checks that the changed byte is drawn red; saves and reads back. It prints `hexedit: PASS`, or `hexedit: FAIL` and a letter for the first check that failed.

Checks: `hexedit`, `hexedit-view` (the rows and the status row of `htest.bin`), `hexedit-goto`, `hexedit-new` (a new file typed and saved, then opened again), `hexedit-quit` (`n` at the question), `hexedit-usage`.
