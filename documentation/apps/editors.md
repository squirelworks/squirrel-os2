# Text Editors

Squirrel-OS/2 provides two distinct text editors. Both are original implementations.

## Normal Editor (`edit`)

For ordinary use.

- Simple character insertion and deletion
- Cursor movement (arrows, home, end)
- Load and save via the file system
- Status line shows file name and modified flag only
- Minimal key chords
- Suitable for notes, letters, and short documents

## Verbose Editor (`vedit`)

For people who want every detail visible.

- Full status line: line, column, byte offset, character code (decimal and hex), insert/overwrite mode, modified flag, file size, buffer capacity
- Explicit feedback on every command (echo of key, resulting state)
- Line numbers always shown
- Optional display of control characters and whitespace
- Detailed error and warning messages
- Command history and last-action description
- Suitable for source code, configuration, and precise editing

## Current Status (2026-10-30)

Both editors are implemented in `kernel/editor.asm` as one full-screen engine running as its own process.

### Shared behaviour

- 16 KB buffer, drawn in place (rows 0–22 text, row 23 status, row 24 messages); vertical and horizontal scrolling keep the cursor visible.
- Cursor: arrows, Home/End (line), PgUp/PgDn (23 lines); up/down remember the wanted column across short lines.
- Editing: printable keys (with Shift), Enter, Backspace, Delete, Tab (4 spaces), Insert toggles insert/overwrite.
- Files: `run edit <file>` / `run vedit <file>` loads the file (or starts a new one with that name).
  The name may be a path of up to 63 characters (`run edit docs/notes.txt`; 0.9.2). A directory, or a
  path through a missing directory, is reported on the message line and the buffer starts untitled;
  Ctrl+S or F2 saves (asks for a name if untitled); Esc or Ctrl+Q quits, asking `s`ave / `d`iscard / cancel when modified.
- Without a data disk the editors still work in memory and say that saving is unavailable.
- A failed save shows why (`Disk full`, `Bad name: ...`, `Is a directory`, ...). When the name itself was the problem, the buffer becomes untitled so the next save asks for another one (0.9.2). `draw` does the same.
- From the file browser, `e` opens the selected file in `edit`.
- Undo (1.0.11): Ctrl+Z takes back the last edit, which is one typed key, Enter, Backspace, Delete, or Tab (all four spaces). It restores the text, the cursor, and the modified flag as they were before that edit, and says `Undone.` There is one level only: a second Ctrl+Z says `Nothing to undo.` The next edit makes a new undo point. How it works: before each edit, the whole buffer is copied to four pages from the page allocator. The editor takes them when it starts and gives them back when it exits. If no pages are free, Ctrl+Z says `Undo unavailable: no free memory.`
- Search (1.0.9): Ctrl+F asks `Find (Esc cancels):` on the message line. The text may contain spaces. The search starts just after the cursor, wraps to the start of the buffer, and is case-sensitive. The cursor lands on the first character of the match, and the message line says `Found zebra at line 1, column 9`, or `Not found: zebra`. F3 finds the same text again. Before any Ctrl+F, F3 says `Nothing to find again: Ctrl+F first`.

### `edit` status line

`Text Editor: name [modified]` and the key reminder `Ctrl+F find  Ctrl+S save  Esc quit`. Messages only for load/save/errors.

### `vedit` additions

- Line-number gutter on every line.
- Status: `L<line> C<col> off <byte offset> '<char>' 0x<hex> (<dec>) INS|OVR MOD|--- <size>/<capacity> <name>`.
- Ctrl+T (1.0.12) toggles the display of control characters. When it is on, a line end shows as a dim `$` after the last character, a tab as `>`, and any other control character as `^`. When it is off, line ends are invisible and control characters show as `.`, as before. The message line says which mode is on. Only the display changes: the buffer, its size and the cursor column stay the same. The display starts off each time `vedit` opens. In `edit`, Ctrl+T does nothing.
- A message for every action: `Typed 'a' 0x61 (97)`, `Deleted '\n' 0x0A (10)`, `Moved.`, mode changes, load/save results.

### Not yet

- Command history, an undo history deeper than one step, and a visible mark for spaces.
- Files larger than 16 KB load truncated (with a warning).

## Commands

```
run edit [file]
run vedit [file]
```

## Design Notes

- Both share the same underlying buffer primitives.
- The verbose editor simply exposes more state and logs more actions.
- Neither depends on external editor sources.
- Keys come from the scancode queue (`kbd_getscan`), with Shift and Ctrl tracked by `kbd_shift_track`.
- File I/O uses the SQFS kernel API (`fs_open`/`fs_read`/`fs_write`).
