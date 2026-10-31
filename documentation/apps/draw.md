# Drawing Program

Squirrel-OS/2 provides an original drawing program. All code is native to the project. No external graphics libraries or contemporary drawing tools are used.

## Current Stage — ASCII drawer (0.3.3)

While the GUI is unfinished, the drawing program is an ASCII drawer. It runs in VGA text mode on a fixed character canvas, drawn in place (no scrolling). There is no pixel graphics, framebuffer, mode 13h or linear-framebuffer path yet.

### Commands

```
run draw            start with an empty, unnamed canvas
run draw <file>     load <file> from the data disk (or start a new one with that name);
                    <file> may be a path (0.9.2)
```

The file browser (`run files`) launches `draw` like any other app.

### Screen

- Rows 0–1: title and top border
- Rows 2–19: the 64 × 18 canvas, screen columns 8–71, with a border
- Row 21: status line: cursor position, brush, pen state, file name, `[modified]`, and the pending line/rectangle corner
- Rows 22–23: key help
- Row 24: message for the last action (loaded, saved, filled, errors)

### Keys

| Key | Action |
|-----|--------|
| Arrows | Move the cursor (clamped to the canvas) |
| Space | Plot the brush character |
| `x` / Backspace | Erase (plot a space) |
| `p` | Pen down/up: while down, every move plots the brush |
| `b` | Choose the brush: the next printable key becomes the brush |
| `l` | Line: press at the first corner, move, press again |
| `r` | Rectangle outline: press at one corner, move, press at the opposite corner |
| `f` | Flood fill the region under the cursor (4-connected) with the brush |
| `c` | Clear the canvas |
| Ctrl+S / F2 | Save (asks for a name when the canvas has none) |
| Esc / Ctrl+Q | Quit; with unsaved changes asks `s` save and quit, `d` discard, other key cancel |

### File format

A drawing is a plain text file: one line per canvas row, trailing spaces trimmed, trailing blank rows dropped. `cat` shows it as-is and `edit` can change it. On load, longer lines and extra rows are clipped, carriage returns are ignored and control characters become spaces.

### Design Notes

- Code: `kernel/draw.asm`, run as a process through `app_host` like the other apps.
- Canvas: `KSCRATCH+0x8000` (64 × 18 bytes). Fill stack: `KSCRATCH+0x9000` (5120 dword entries, enough that it can never overflow: at most 1 + 4 pushes per cell). File buffer: `KSCRATCH+0xE000`.
- Lines use integer Bresenham; rectangles draw four edges between the sorted corners.
- Reuses the editor's string builder, VGA text helpers, save-as prompt and messages (`kernel/editor.asm`).

## Later (after GUI exists)

Pixel drawing, freehand, filled shapes and save-as-bitmap wait for the graphics primitives and window manager (milestones 1.3–1.4 and beyond). Integration as a desktop object follows once the window manager exists (1.4+).

## Related

- Milestone: 0.3.3 in `documentation/plannedmilestones.md`
- Release note: `documentation/releases/0.3.3.md`
