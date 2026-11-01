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
|  [Tools ]                             |
| Enter: open  Bksp: up  Esc: shell     |
+---------------------------------------+
```

| Key | Action |
|-----|--------|
| Up, Down | choose a program in the list |
| Enter | send `open` to the chosen entry, which runs the program in a window (`calc` since 1.6.1, `draw` 1.6.3, `edit` and `vedit` 1.6.4, `files` 1.7.6) |
| Backspace | in a folder: back to the top level (1.9.0) |
| m | pick up the chosen object (1.9.1) |
| p | drop the held object into the folder shown (1.9.1) |
| Esc | put a held object back (1.9.1); otherwise close the desktop, return to text mode and the shell prompt (`Desktop closed.`) |

## Programs in windows

Since 1.6.1, Enter on `calc` runs the calculator in a window titled `calc`, over the desktop. Since 1.6.4, `edit` and `vedit` open the same way, with an empty buffer: Ctrl+S or F2 asks for a file name, and Esc closes the window. The window shows 52 columns and 20 rows of a text screen. When the calculator quits (Esc), the window closes and the desktop is back with `calc` still selected.

How it works (`dk_textwin` in `kernel/desktop.asm`):

- A page from `pg_alloc` stands in for the text screen. `putc`, `cls` and `scroll_up` write to the address in `txt_base`, which is `0xB8000` normally and this page while the program runs. The cursor (`cur`) is saved and set to 0, and both are put back afterwards.
- A console widget (`wg_console`, `../kernel/widgets.md`) shows the page in the window. It shows the first 20 rows, or, once the cursor is further down, the 20 rows that end at the cursor row. Columns past 52 are cut off.
- `kbd_getscan` calls `kbd_wait_hook` while it waits for a key. While the program runs, the hook redraws the screen if anything was written (`txt_dirty`). So output appears before each key is read.
- The program is called the way `run` calls it, with no file name. It reads keys as it does in text mode.
- `txt_cols` and `txt_rows` are 52 and 20 while the program runs, and 80 and 25 otherwise. The editor fits its screen to them, so its status and message rows are the last two rows of the window.

### draw (1.6.3)

Enter on `draw` runs the ASCII drawing program the same way, in a window titled `draw`. Its frame, canvas, status row and message row are written through `txt_base` (`dr_frame`, `dr_draw`, and `sb_row`, which `edit` shares), and each sets `txt_dirty`. The window is 52 × 20 of the program's 80 × 25 screen:

- While drawing, the cursor is on the canvas, so the window shows the title, the top border and all 18 canvas rows, and canvas columns 0 to 43. Columns 44 to 63, the status row, the key help and the message row are off the window.
- When `draw` asks a question on the message row (Save as, the unsaved-changes question on Esc, the new brush), it first moves the cursor to that row (`dr_askrow`), so the window shows rows 5 to 24 and the question is visible. On the text screen the cursor stays where it was.
- Esc (and d or s if there are unsaved changes) closes the window, and the desktop is back with `draw` selected.

### edit and vedit (1.6.4)

Enter on `edit` or `vedit` opens the editor with an empty buffer. Ctrl+S or F2 asks for a file name and saves; Esc closes the window (after asking, if there are unsaved changes). The editor fits its screen to `txt_cols` × `txt_rows`, so the window shows 18 text rows of 52 columns, the status row (inverted) and the message row. The key reminder on `edit`'s status row is left out when it does not fit.

### files (1.7.6)

Enter on `files` runs the file browser in a window the same way. It writes through `putc`, `puts` and `cls`, so nothing in it changed. The window shows the 20 rows that end at the cursor, which the browser keeps on its bottom row: the key help, the entry count and the 18 entries above them; its title row and the first entries are above the window. Esc closes it. Opening a program from inside it runs that program in the same window.

## Entries as objects (1.7.6)

The entries are objects (`../kernel/objects.md`). The desktop records two classes:

- `DesktopObject`: field `name`; methods `name` (returns it) and `open` (opens nothing, returns −1).
- `Program` under it: field `entry`, the program's routine (since 1.8.3 its name, as text); `open` passes the entry and the name to `dk_textwin`.

When the desktop starts it makes one `Program` per entry (files, calc, edit, vedit, draw) and sets both fields; the list shows what each one answers to `name`. Enter sends `open` to the selected one. When the desktop closes it frees them, so afterwards `objs` lists the two classes and no live objects (check `desktop-objs`).

## Entries kept on disk (1.8.3)

Since 1.8.3 the entries are object files in `/desktop` on the data disk (`../kernel/objects.md`, "Object files"). When the desktop starts and `/desktop` does not exist yet, it makes the directory and saves one `Program` per default entry as `/desktop/<name>.obj`: `files.obj`, `calc.obj`, `edit.obj`, `vedit.obj` and `draw.obj`. It then loads each of those files that is still there, in that order, and lists them. A removed file's entry is not listed. `entry` is now the program's name as text (`calc`), not the address of its routine, so a file stays valid when the kernel is rebuilt; `open` looks the name up among the programs the desktop knows and opens nothing for a name it does not know. After the desktop has run (so `Program` is recorded), `objcat /desktop/calc.obj` shows `class Program`, `name: calc` and `entry: calc`.

Without a data disk, or with none of the files left, the desktop lists the built-in entries as before. Checks (on a data disk of their own): `dk-store` (`ls /desktop` after the first desktop lists the five files), `dk-store-cat`, `dk-store-rm` (with `draw.obj` removed, the next desktop does not list `draw`), `dk-store-left` (it still lists the others), `dk-store-open` (calc, now the second entry after `files`, still opens and computes).

## Folders (1.9.0)

`DesktopObject` has a second text field, `in`: the name of the folder that holds the object, empty for the top level. A `Folder` class under `DesktopObject` has no fields of its own; its `open` makes the desktop show that folder. The desktop lists only the objects whose `in` is the folder being shown, and the window title is the folder's name (`Squirrel-OS/2 Desktop` at the top level). Backspace goes back to the top level. With nothing in the folder, the list is empty and Enter does nothing.

The first time, `/desktop` also gets `Tools.obj`, an empty folder, after the five programs. A `Program`'s fields are now `name`, `in` and `entry`, one more than in 1.8, so 1.8's files are refused when they load. When none of the files load, the desktop writes the defaults again, so a 1.8 disk gets all six entries back. Checks (on a data disk of their own): `dk-folder` (the top level lists `draw` and `Tools`), `dk-folder-open` (Enter on `Tools` shows a list without `calc`, titled `Tools`), `dk-folder-back` (Backspace shows the programs again), `dk-folder-cat` (`objcat` shows `class Folder` and a `Program`'s empty `in`), `dk-folder-quit`.

## Pick up, move and drop (1.9.1)

`m` picks up the chosen object, and the help row then reads `Held: <name>  p: drop  Esc: back`. The object stays held while Enter and Backspace move between the top level and a folder. `p` drops it into the folder being shown. That sets its `in` field to the folder's name (empty at the top level) and saves its file in `/desktop`, so the move outlives a reboot. The lists are redrawn, and the help row goes back to normal. Esc while holding puts the object back where it was and writes nothing. A second Esc closes the desktop as before. A folder can be dropped only at the top level, because folders do not nest. Inside a folder, `p` is refused and the folder stays held.

Checks (on a data disk of their own): `dk-hold` (the help row names `calc`), `dk-hold-esc` (Esc puts it back: the desktop is still open, and `calc.obj`'s `in` is still empty), `dk-move` (pick up `calc`, open `Tools`, drop: `Tools` lists `calc`), `dk-move-top` (after a reboot the top level does not list `calc`), `dk-move-cat` (`objcat` shows `in: Tools`, the object's new parent), `dk-move-open` (`calc`, opened from `Tools`, computes `2 + 2`), `dk-move-fold` (`Tools` cannot be dropped into itself).

## Booting into the desktop

The system still boots to the shell prompt. To boot into the desktop, put a line `desktop` in `autoexec.bat` on the data disk (`../kernel/shell.md`); Esc then reaches the shell as usual.

## Keys for widgets

`wg_getkey` waits for a key and returns it the way `wg_key` takes it: ASCII, 8 for Backspace, 27 for Esc, and `WK_UP` / `WK_DOWN` for the arrows. The desktop uses it, and later programs in windows can too.

## Testing

The regression run cannot read graphics from the VGA text buffer, so `tools/qemu_screen.py` has a `<gfx>` key. It takes a screen dump and reads the text drawn with the kernel's 5 × 7 font at any pixel offset. It prints each run of text it finds as a `gfx: ...` line. A cell counts when its spacing column and bottom row are one colour, and its other pixels then give the glyph. Checks: `desktop` (title and the five names), `desktop-quit` (`systest: PASS` after Esc), `desktop-calc` (`calc> 2 + 2` and `= 4` in the window), `desktop-calc-back` (the desktop after Esc in `calc`), `desktop-calc-mem` (the page is freed), `desktop-calc-text` (the shell screen is intact afterwards), `desktop-draw` (two plotted cells next to the canvas border, read off the window), `desktop-draw-save` (the saved file holds them), `desktop-draw-back`, `desktop-draw-mem` and `desktop-draw-text` (as for `calc`), `gfx-read-list` (the reader on `listtest`), and `desktop-boot` / `desktop-boot-quit` (a data disk whose `autoexec.bat` is `desktop`).
