# Program Manager (2.3-groups)

`progman` shows the desktop as group windows full of icons, on the window manager's screen (640 × 480 through VBE, or mode 13h). It works on the same objects as `desktop` (`desktop.md`): the `Program` and `Folder` objects in `/desktop` (1.7.6, 1.9.0). The object model stays underneath; the Program Manager is a view of it.

- **Main** holds the top-level programs. Each top-level folder is a group of its own (by default **Tools**), holding the objects whose `in` is that folder. At most four groups of eight icons.
- Each icon is the object's icon (`icons.md`): a folder's, the program's own (the built-in icon named like its `entry`), or the generic program icon. Its caption, the object's name, is centred under it in the window face (`FONT_9`); the chosen icon's caption is highlighted.
- Group windows sit in two columns on a 640-wide screen and cascade on a small one. They move, size, maximise and minimise like any window (`windows.md`). A group's close box minimises it (double-click its icon to bring it back); Main's close box, Alt+F4 on Main and Esc quit.

## Keys

| Key | What it does |
|-----|--------------|
| arrows | choose an icon in the focused group (the top window) |
| Enter | open the chosen icon: sends it `open` (a program runs in a window, as from `desktop`) |
| m | move the chosen icon: the arrows move it 8 pixels a press, Enter or Esc ends and saves |
| a | arrange the focused group's icons in rows, and save |
| Esc | quit |

Alt+Tab, Alt+Esc, Alt+Space (the system menu) and Alt+F4 work as everywhere (2.2-alttab, 2.2-sysmenu).

## Mouse

A press on an icon chooses it. A second press on it within half a second (`PM_DBL`, 50 ticks) is a double-click and opens it. Dragging an icon at least 4 pixels moves it by as much, and saves.

## Places

Moving or arranging writes `/desktop/progman.pos`, one line per icon: `name x y`, the icon's cell in its group's client area. The next `progman` reads it, so places survive a reboot. Icons not in the file are laid out in rows.

## Window manager hook

Each group window's record has `WIN_PAINT = pm_paint` (2.3-groups adds the field, `windows.md`): `wm_draw` calls it after the client area and its widgets, with edi = the record and eax..edx = the client area. `pm_paint` cuts the clip to the client area (`pm_clipin` / `pm_clipout`) and draws the icons and captions.

## Checks

`pmtest` builds the groups without the loop: Main has the five programs and Tools is a group; a press on calc chooses it, a drag of (40, 16) moves it and saves, the file read back puts it there again; two presses 20 ticks apart are a double-click and two far apart are not; arrange puts it back. It prints `pm: PASS` or `pm: FAIL at N` (the check that failed). It needs a data disk for the places file.

On a disk of their own (`pm.img`): `pmtest`, `pm-groups` (the group titles and captions read off the screen), `pm-launch` (calc opened with Enter computes 2 + 2), `pm-move` (m and arrows: `calc 88 12` in the file), `pm-move-reboot` (the next run starts from that place: one more step right gives `calc 96 12`), `pm-arrange` (`calc 72 4` again) and `pm-text`.
