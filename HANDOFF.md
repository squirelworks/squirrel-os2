# Handoff

Work was stopped on 2026-11-14 at the owner's request. Cursor or Codex picks up from here. Each section is one area of work.

## OS2-GUI (Squirrel OS/2 desktop)

### Merged into main

- **2.2-propfont and 2.3-icons:** proportional fonts and SQIC icons.
- **2.3-groups and 2.3-filemgr:** the Program Manager and the File Manager.
- **2.3-clipboard:** merged in #167. SYS_CLIPPUT is 49 and SYS_CLIPGET is 50. Slots 47 and 48 are reserved for SYS_DEBUG and SYS_TTY.

### Open

- **2.3-control, Control Panel v1**
  - PR #168 (int/os2-control, cbc81af), built from `ws/os2-gui/2.3-control` at 944e2e2. Full gate: 786 ok, 0 FAIL.
  - TODO 2.3-control is ticked on that PR.
  - Needs review and merge.
  - Docs: `documentation/apps/control.md`.
- **2.3-bevel-default, Warp bevelled widgets**
  - Branch `ws/os2-gui/2.3-bevel-default`, off main 7844b67. It is not a PR yet.
  - Buttons are raised and press in (`WG_STATE`, `wg_press`, a short flash on Enter or Space). Fields and lists are sunken, and the list selection bar is `TH_SELECT`. A new group box (`wg_group`) is etched.
  - The new `bevwidgets` check passes. buttontest, fieldtest, listtest and scrolltest were updated to probe the new colours.
  - The full gate was stopped part way: 363 ok, 0 FAIL so far. Run the whole gate (`sh tools/regress.sh`, about 45 minutes, one run at a time).
  - Then open the PR and tick TODO 2.3-bevel-default. ROADMAP 2.3 can be ticked once both #168 and this branch are in.
  - Docs: `documentation/kernel/widgets.md`.

### Not started (from the plan, in order)

- **Desktop loader:** scan `/desktop` for objects beyond `dk_defs`, so the Drive and Shredder objects from OS2-FS (`kernel/fsobj.asm`) show up. Add drag-to-Shredder.
  - Contract agreed with OS2-FS: `open` takes no arguments. `drop` takes eax = target, ebx = dropped object, ecx = path, and returns 0, or -1 with CF.
- **W.1 fonts follow-up,** then **W.2–W.6:** WPS objects, settings notebooks, LaunchPad and WarpCenter, folder views, Open as, system objects.
- **2.5 and 2.6** (see TODO.md).

### Working notes

- Every feature gets a `tools/regress.sh` check printing PASS. Run the gate sequentially; parallel runs share `$TMPDIR` and break.
- `progs.img` is at its 64-entry limit. Put new test programs on another image (`apps.img`), or `systest`'s create fails with "directory full" and `lang-systest` fails.
- The `up-ls` count and the `install-copy` screen change when programs are added. Re-check both after a merge.
- In mode 13h, read pixels at y >= `GFX_SAFE_Y` (103). Pixels above it can read back wrong.
- The window manager reads Enter as 10, not 13.
