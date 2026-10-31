# Desktop

`desktop` (since 1.6.0) is a shell command that switches to graphics mode and shows the desktop. The desktop is a window titled `Squirrel-OS/2 Desktop`, drawn with the window manager and widgets (`../kernel/windows.md`, `../kernel/widgets.md`). It is implemented in `kernel/desktop.asm`. Keyboard only.

```
+---------------------------------------+
| Squirrel-OS/2 Desktop                 |
| Programs:                             |
|  [files ]                             |
|  [calc  ]   <- the selected row is a  |
|  [edit  ]      black bar              |
|  [vedit ]                             |
|  [draw  ]                             |
|                                       |
| Up/Down: choose   Esc: shell          |
+---------------------------------------+
```

| Key | Action |
|-----|--------|
| Up, Down | choose a program in the list |
| Esc | close the desktop, return to text mode and the shell prompt (`Desktop closed.`) |

Opening the chosen program in a window comes in the next 1.6 tasks: `calc`, then `edit` and `vedit`, then `draw` (`../../TODO.md`). Enter does nothing yet.

## Booting into the desktop

The system still boots to the shell prompt. To boot into the desktop, put a line `desktop` in `autoexec.bat` on the data disk (`../kernel/shell.md`); Esc then reaches the shell as usual.

## Keys for widgets

`wg_getkey` waits for a key and returns it the way `wg_key` takes it: ASCII, 8 for Backspace, 27 for Esc, and `WK_UP` / `WK_DOWN` for the arrows. The desktop uses it, and later programs in windows can too.

## Testing

The regression run cannot read graphics from the VGA text buffer, so `tools/qemu_screen.py` has a `<gfx>` key. It takes a screen dump and reads the text drawn with the kernel's 5 × 7 font at any pixel offset. It prints each run of text it finds as a `gfx: ...` line. A cell counts when its spacing column and bottom row are one colour, and its other pixels then give the glyph. Checks: `desktop` (title and the five names), `desktop-quit` (`systest: PASS` after Esc), `gfx-read-list` (the reader on `listtest`), and `desktop-boot` / `desktop-boot-quit` (a data disk whose `autoexec.bat` is `desktop`).
