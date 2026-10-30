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

## Current Status (2026-10-14)

Basic interactive buffers are implemented in `kernel/pm.asm` for the present stage:

- `run edit` / `run vedit` enter editor mode
- Shared buffer (`edit_buf`, 256 bytes)
- Insert printable characters
- Backspace deletes last character
- Enter inserts newline
- Esc exits back to command line
- Verbose mode shows a status prefix (full numeric status still scaffolded)
- Redraws buffer after each change
- Uses existing keyboard ISR path and VGA text output

This matches the current kernel (no separate process, no persistent FS yet).

Next (scaffolded in plannedmilestones 0.3.2):
- Cursor movement
- Full numeric verbose status (line/col/offset/char)
- Load/save to in-memory files
- Larger capacity / proper line handling

## Commands

```
run edit
run vedit
```

## Design Notes

- Both share the same underlying buffer primitives.
- The verbose editor simply exposes more state and logs more actions.
- Neither depends on external editor sources.
- Keyboard input is already available (IRQ1).
- File I/O will use the in-memory file table until persistent storage arrives.
