# File Manager (2.3-filemgr)

`filemgr` is a two-pane File Manager on the window manager's screen. It needs a data disk (without one it says so and stays in text mode). It starts in the shell's current directory.

- **Left pane: the directory tree.** The root `/`, then every directory under it, depth first, indented 8 pixels a level.
- **Right pane: the chosen directory's entries.** Directories come first, then files, each with its size (`<dir>` for a directory).
- **Status line.** Below the panes it shows the keys, a question being asked, or how the last operation went (`Done.`, or the file system's reason, as the shell words it).

The chosen row of the pane with the focus is blue; the other pane's chosen row is grey.

## Keys

| Key | What it does |
|-----|--------------|
| f | the File menu at the chosen row: Copy..., Move..., Rename..., New directory..., Delete (the arrows and Enter, or a click, choose; Esc closes it) |
| Left / Right | the tree / the list gets the focus |
| Up / Down | the row before / after; in the tree the list follows |
| Enter | in the list, open the chosen directory |
| Backspace | up to the parent directory |
| c | copy the chosen file: asks *Copy to:* |
| m | move the chosen entry: asks *Move to:* |
| r | rename the chosen entry: asks *Rename to:* (a name in the same directory) |
| n | make a directory: asks *New directory:* |
| Delete | delete the chosen entry after *Delete? y / n* (a directory must be empty) |
| Esc | cancel a question; otherwise quit |

A target is a name in the shown directory, or a path starting with `/`. When it is a directory, the entry keeps its name there (`m` and `/` move a file to the root).

## Mouse

The right button opens the File menu at the pointer. A press on a row chooses it and gives its pane the focus; a tree row shows that directory. A second press on the same list row within the Control Panel's double-click time (`cp_dbl`, half a second unless changed) opens a directory. Drag a list row onto a tree row to move the entry into that directory; hold Ctrl to copy it instead. Dropping on its own directory does nothing.

## Code

The code is `kernel/filemgr.asm`. It reads the SQFS table directly: an entry's `DE_PARENT` gives the tree, and a directory's id is its index + 1. Operations go through `fs_open`, `fs_read`, `fs_write`, `fs_rename`, `fs_delete` and `fs_mkdir` with absolute paths (`fm_dirpath`, `fm_entpath`). The window paints its panes through `WIN_PAINT` (`windows.md`). The File menu is a `wm_popup`; its choice comes back as `WME_MENU`, which `dk_wmreply` now keeps in `dk_menu` (item + 1) for the caller's loop.

## Checks

`fmtest` makes `/fmt`, `/fmt/sub` and `/fmt/f`, then checks:
- the panes;
- the paths;
- a drop of `f` onto `sub`;
- a copy back into `/fmt` that reads `abc`.

Then it removes them. It prints `fm: PASS` or `fm: FAIL at N`.

On a disk of their own (`fm.img`), with `/w` holding `a.txt` and `sub`:
- `fm-setup`
- `fm-panes`: read off the screen
- `fm-copy`: into `sub`
- `fm-rename`: to `b.txt`
- `fm-move`: to `/`
- `fm-mkdir`: `/w/new`
- `fm-delete`: `sub/a.txt` is gone
- `fm-menu`: Delete chosen from the File menu
- `fm-text`
