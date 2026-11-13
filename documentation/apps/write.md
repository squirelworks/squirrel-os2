# Write, a word processor (A.7)

`run write [file]` edits a styled document. It is a program on the data disk (`programs/write.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`). A name that does not exist starts an empty document (`New file`); without a name the document has no name until it is saved (Ctrl+S then asks `Save as:`). A document holds up to 12,000 characters; the file buffer comes from `SYS_SBRK`.

Paragraphs wrap at word boundaries to a 50-column page; a word longer than a line is split. Each character can be **bold**, *italic* and underlined, and each paragraph is aligned left, centred or right. The status row shows the style that typing uses (`BIU`, with `-` for a style that is off), the cursor's paragraph alignment, the word and character counts and `*` while there are unsaved changes, or the last message.

| Key | Action |
|-----|--------|
| typing | insert; a selection is replaced by what is typed |
| Enter | a new paragraph, with the same alignment |
| Backspace / Delete | remove a character, or the selection |
| arrows | one character / one wrapped line |
| Home / End | the start / end of the line |
| PgUp / PgDn | 19 lines |
| Ctrl+Home / Ctrl+End | the start / end of the document |
| F3 | start a selection at the cursor; moving the cursor extends it |
| left click / drag | move the cursor / select |
| Ctrl+B, Ctrl+I, Ctrl+U | bold, italic, underline: toggles the selection's style, or the style of what is typed next |
| Ctrl+L, Ctrl+E, Ctrl+R | align the paragraph (or every paragraph in the selection) left, centre or right |
| Ctrl+S | save |
| Ctrl+O | open a file (asks for its name on the status row) |
| Ctrl+N | a new, empty document |
| Esc | drop the selection; with none, quit. With unsaved changes Ctrl+O, Ctrl+N and Esc ask `Save changes? y/n` (Esc again stays) |

## Files

A name ending in `.txt` is saved as plain text: the styles and alignment are dropped. Any other name is saved in the SQWP form: the five bytes `SQWP1`, the length as a 32-bit number, the text, then one byte for each character with its style (1 bold, 2 italic, 4 underline; on the newline that ends a paragraph, 0x10 centre, 0x20 right). A file that is not SQWP opens as plain text (carriage returns dropped, tabs as spaces).

## Self-check

`run write test` types 13 words and checks that they wrap to two lines of the right lengths and that 13 words are counted; selects the first word with F3 and makes it bold, and checks that it is drawn with more ink than the next; underlines typed text at the end; centres the paragraph and checks where its second line starts; saves `wtest.swp` and opens it again with its styles and alignment; saves `wtest.txt` and opens it again without them; and replaces a selection by typing. It prints `write: PASS`, or `write: FAIL` and a letter for the first check that failed.

Checks: `write`, `write-count` (the counts while typing), `write-styles` (italic, underline and a centred paragraph saved and opened again), `write-ask`, `write-quit` (`n` at the question).
