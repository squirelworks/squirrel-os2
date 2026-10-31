# Drawing Program

Squirrel-OS/2 provides an original drawing program. All code is native to the project. No external graphics libraries or contemporary drawing tools are used.

## Current Stage — ASCII drawer (0.3.3)

While the GUI is unfinished, the drawing program is an ASCII drawer. It runs in VGA text mode on a fixed character canvas, drawn in place (no scrolling). Since 1.6.5, `g` opens a pixel canvas in mode 13h (below).

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
| `g` | Open the pixel canvas (1.6.5, below) |
| Esc / Ctrl+Q | Quit; with unsaved changes asks `s` save and quit, `d` discard, other key cancel |

### File format

A drawing is a plain text file: one line per canvas row, trailing spaces trimmed, trailing blank rows dropped. `cat` shows it as-is and `edit` can change it. On load, longer lines and extra rows are clipped, carriage returns are ignored and control characters become spaces.

### Design Notes

- Code: `kernel/draw.asm`, run as a process through `app_host` like the other apps.
- Canvas: `KSCRATCH+0x8000` (64 × 18 bytes). Fill stack: `KSCRATCH+0x9000` (5120 dword entries, enough that it can never overflow: at most 1 + 4 pushes per cell). File buffer: `KSCRATCH+0xE000`.
- Lines use integer Bresenham; rectangles draw four edges between the sorted corners.
- Reuses the editor's string builder, VGA text helpers, save-as prompt and messages (`kernel/editor.asm`).

## Pixel canvas (1.6.5)

`g` in `draw` opens a pixel canvas in graphics mode: 80 × 50 pixels, each shown as a 3 × 3 square, on a white background with a black frame. The top lines show the file name, the ink (a swatch at the right) and the last message; the bottom line shows the keys.

| Key | Action |
|-----|--------|
| Arrows | Move the cursor (a light red ring) |
| Space | Plot one pixel in the ink |
| `p` | Pen down/up: while down, every move plots (a stroke). Putting it down plots too |
| `x` / Backspace | Erase the pixel (white) |
| `c` | Next ink: black, red, green, blue, yellow, magenta |
| F2 | Save |
| Esc | Back to the text canvas (the pixel image is not kept unless saved) |

The image is saved as `<drawing>.px`, or `drawing.px` if the drawing has no name: a 6-byte header (`SQPX`, width 80, height 50) and then one colour byte per pixel, row by row, 4006 bytes in all. When the pixel canvas opens it loads that file if it is there and has this header and size. The colour bytes are palette indexes as the screen uses them (`../kernel/graphics.md`; white is 0x3F).

From the shell, the canvas switches to graphics mode and back (`gfx_mode13`, `gfx_text`). In a desktop window (`desktop.md`) the screen is already in graphics mode: the canvas draws over the desktop, the desktop's redraw hook is held off meanwhile, and Esc lets the desktop draw itself and the window again.

The self-check `drawpx` (`kernel/drawpx.asm`) works on a blank image named `drawpx.px`. It picks red, puts the pen down at (10, 20) and moves right four times, using the same key handler as the canvas, and draws the screen. Pixel (12, 20) must then be red in the image and in the middle of its square on the screen, and (12, 22) still white. It saves, clears the image (the pixel reads white), loads, and reads red again. It prints `drawpx: PASS`, or FAIL (also when there is no data disk).

## Later

Lines, rectangles and fill on the pixel canvas, more colours, other sizes and a picture viewer are not scheduled yet. Since 1.6.3 the ASCII drawer also runs in a window on the desktop (`desktop.md`).

## Related

- Milestone: 0.3.3 in `documentation/plannedmilestones.md`
- Release note: `documentation/releases/0.3.3.md`
