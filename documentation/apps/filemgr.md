# File Manager (2.3-filemgr), folder views (W.4-views), Open as (W.5-openas)

`filemgr` is a File Manager on the window manager's screen. It needs a data disk (without one it says so and stays in text mode). It starts in the shell's current directory.

## Views (W.4)

`i`, `t` and `d` switch the folder view for this window (`fm_setview`). **Open as** (W.5) opens a folder in a chosen view the same way:

| View | Key | What it shows |
|------|-----|----------------|
| **Icon** | `i` | The chosen directory's entries as a grid of 32×32 icons (`folder` / `file` from `icons.md`) with captions. Arrows move on the grid; Enter opens a directory. |
| **Tree** | `t` | The directory tree alone, full width. Arrows move the selection (and the current directory) as in the Details tree pane. |
| **Details** | `d` | The classic two panes (default). |

- **Left pane (Details): the directory tree.** The root `/`, then every directory under it, depth first, indented 8 pixels a level.
- **Right pane (Details): the chosen directory's entries.** Directories come first, then files, each with its size (`<dir>` for a directory).
- **Status line.** Below the panes it shows the keys (or which view is on), a question being asked, or how the last operation went (`Done.`, or the file system's reason, as the shell words it).

The chosen row of the pane with the focus is blue; the other pane's chosen row is grey. In Icon view the chosen icon has a blue band behind it.

## Keys

| Key | What it does |
|-----|--------------|
| i / t / d | Icon / Tree / Details view (W.4) |
| f | the File menu at the chosen row: Copy..., Move..., Rename..., New directory..., Delete (the arrows and Enter, or a click, choose; Esc closes it) |
| Left / Right | Details: the tree / the list gets the focus; Icon: previous / next icon |
| Up / Down | the row before / after; in the tree the list follows; Icon: up / down a grid row |
| Enter | in the list or Icon view, open the chosen directory |
| Backspace | up to the parent directory |
| c | copy the chosen file: asks *Copy to:* |
| m | move the chosen entry: asks *Move to:* |
| r | rename the chosen entry: asks *Rename to:* (a name in the same directory) |
| n | make a directory: asks *New directory:* |
| Delete | delete the chosen entry after *Delete? y / n* (a directory must be empty) |
| Esc | cancel a question; otherwise quit |

A target is a name in the shown directory, or a path starting with `/`. When it is a directory, the entry keeps its name there (`m` and `/` move a file to the root).

## Mouse

The right button on a **directory** (tree row, or a directory in the list / Icon view) opens **Open as** (W.5): Icon / Tree / Details / Settings. Settings opens a General / View notebook for the folder. On a file (or empty space) the right button still opens the File menu. A press on a row chooses it and gives its pane the focus; a tree row shows that directory. A second press on the same list row within the Control Panel's double-click time (`cp_dbl`, half a second unless changed) opens a directory. Drag a list row onto a tree row to move the entry into that directory; hold Ctrl to copy it instead. Dropping on its own directory does nothing.

## Code

The code is `kernel/filemgr.asm`. It reads the SQFS table directly: an entry's `DE_PARENT` gives the tree, and a directory's id is its index + 1. Operations go through `fs_open`, `fs_read`, `fs_write`, `fs_rename`, `fs_delete` and `fs_mkdir` with absolute paths (`fm_dirpath`, `fm_entpath`). The window paints its panes through `WIN_PAINT` (`windows.md`). The File menu is a `wm_popup`; its choice comes back as `WME_MENU`, which `dk_wmreply` now keeps in `dk_menu` (item + 1) for the caller's loop.

## Checks

`fmtest` makes `/fmt`, `/fmt/sub` and `/fmt/f`, then checks:
- the panes;
- the paths;
- a drop of `f` onto `sub`;
- a copy back into `/fmt` that reads `abc`.

Then it removes them. It prints `fm: PASS` or `fm: FAIL at N`.

`foldview` (W.4) makes `/fv` with `sub/` and `a.txt`, opens a File Manager window on `/fv`, and checks:
- **Details:** two panes, list has `sub` then `a.txt`, tree depth of `/fv` is 1, tree width is the left third;
- **Tree:** one full-width pane, tree still names `/fv` at depth 1;
- **Icon:** folder-icon yellow body and black outline pixels (as `icontest`);
- switching back with `d` restores Details.

Then it removes `/fv` and prints `foldview: PASS` or `foldview: FAIL at N`. Check `fold-views`.

`openas` (W.5) makes `/oa` with `sub/` and `a.txt`, opens File Manager on `/oa`, and drives Open as → Icon / Tree / Details / Settings through `wm_menuchoose` (checks each `fm_view` and a Settings notebook tab face). It then opens Open as → Settings on Program Manager's `calc` (Settings on any object). Removes `/oa` and prints `openas: PASS` or `openas: FAIL at N`. Check `openas`.

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
