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
| Enter | open the chosen program in a window (`calc` since 1.6.1; the others do nothing yet) |
| Esc | close the desktop, return to text mode and the shell prompt (`Desktop closed.`) |

## Programs in windows

Since 1.6.1, Enter on `calc` runs the calculator in a window titled `calc`, over the desktop. The window shows 52 columns and 20 rows of a text screen. When the calculator quits (Esc), the window closes and the desktop is back with `calc` still selected.

How it works (`dk_textwin` in `kernel/desktop.asm`):

- A page from `pg_alloc` stands in for the text screen. `putc`, `cls` and `scroll_up` write to the address in `txt_base`, which is `0xB8000` normally and this page while the program runs. The cursor (`cur`) is saved and set to 0, and both are put back afterwards.
- A console widget (`wg_console`, `../kernel/widgets.md`) shows the page in the window. It shows the first 20 rows, or, once the cursor is further down, the 20 rows that end at the cursor row. Columns past 52 are cut off.
- `kbd_getscan` calls `kbd_wait_hook` while it waits for a key. While the program runs, the hook redraws the screen if anything was written (`txt_dirty`). So output appears before each key is read.
- The program is called the way `run` calls it. It reads keys as it does in text mode.

`edit`, `vedit` and `draw` write to the text screen directly and open in windows in the next 1.6 tasks (`../../TODO.md`). `files` is not scheduled for a window yet.

## Booting into the desktop

The system still boots to the shell prompt. To boot into the desktop, put a line `desktop` in `autoexec.bat` on the data disk (`../kernel/shell.md`); Esc then reaches the shell as usual.

## Keys for widgets

`wg_getkey` waits for a key and returns it the way `wg_key` takes it: ASCII, 8 for Backspace, 27 for Esc, and `WK_UP` / `WK_DOWN` for the arrows. The desktop uses it, and later programs in windows can too.

## Testing

The regression run cannot read graphics from the VGA text buffer, so `tools/qemu_screen.py` has a `<gfx>` key. It takes a screen dump and reads the text drawn with the kernel's 5 × 7 font at any pixel offset. It prints each run of text it finds as a `gfx: ...` line. A cell counts when its spacing column and bottom row are one colour, and its other pixels then give the glyph. Checks: `desktop` (title and the five names), `desktop-quit` (`systest: PASS` after Esc), `desktop-calc` (`calc> 2 + 2` and `= 4` in the window), `desktop-calc-back` (the desktop after Esc in `calc`), `desktop-calc-mem` (the page is freed), `desktop-calc-text` (the shell screen is intact afterwards), `gfx-read-list` (the reader on `listtest`), and `desktop-boot` / `desktop-boot-quit` (a data disk whose `autoexec.bat` is `desktop`).
