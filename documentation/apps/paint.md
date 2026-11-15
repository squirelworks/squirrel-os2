# Paint and the image viewer (A.2)

Two programs on the data disk for pictures, built on `SYS_GUI` and `gui.inc` (`gui-programs.md`) and sharing `programs/bmp.inc`, an original reader and writer for the BMP layout (file header, 40-byte info header or larger, uncompressed).

## Paint (`run paint [file.bmp]`)

A 272 × 160 canvas in the 16 EGA colours, with six tools down the left, the palette under the canvas and a status row (tool, cross position, `*` while unsaved, help or the last message).

| Tool | Key | Mouse | Keyboard |
|------|-----|-------|----------|
| Pen | `p` | left button: a dot, drag for a stroke | Space puts the pen down or up; with it down, arrows draw |
| Line | `l` | two clicks: the ends | Space at one end, then at the other |
| Box | `b` | two clicks: opposite corners | Space at each corner |
| Solid | `s` | as Box, filled | as Box |
| Fill | `f` | a click fills the area of one colour there | Space |
| Erase | `e` | as Pen, in white | as Pen |

While a Line or Box is half made, its outline follows the cross and the status row says `Space or click: second corner`; Esc drops it.

| Key | Action |
|-----|--------|
| arrows, Ctrl+arrows | move the cross 1 or 8 pixels |
| `c` / `]` and `C` / `[`, or a click on the palette | next / previous colour |
| `u` | undo the last change (once more redoes it) |
| Ctrl+S or F2 | save; the first time it asks `Save as:` on the status row |
| Ctrl+O | open a BMP (asks for its name) |
| Ctrl+N | a new white canvas |
| Esc | drops a half-made shape or lifts the pen; otherwise quits, asking `Save changes? y/n` if there are unsaved changes |

Files are 8-bit BMPs with a 16-colour palette (`bmp_save16`), 43 638 bytes for the full canvas; any program that reads BMP opens them. Paint opens any 8-bit or 24-bit BMP: each pixel becomes the nearest of the 16 colours; a larger picture is cut at 272 × 160 and a smaller one sits at the top left on white.

Fill works scanline by scanline with a stack of seeds on the heap, so it does not recurse. The canvas, the undo copy and that stack come from `SYS_SBRK`.

`run paint test` draws with Line, Box, Fill (and checks that it stays inside the box), undo and redo, Solid and Erase, checks the canvas after each, reads a filled pixel back from the screen, saves `ptest.bmp`, clears, opens it again and compares the whole canvas. It prints `paint: PASS`, or `paint: FAIL` and a letter for the step. Checks: `paint`, `paint-keys` (a solid box by keyboard, saved as `pic.bmp`), `paint-open`, `paint-quit`.

## Image viewer (`run viewer <file.bmp>`)

Shows an 8-bit or 24-bit BMP on black, with an info row: name, size, bits per pixel and zoom (`1:2` is half size, `2:1` double).

| Key | Action |
|-----|--------|
| `+` / `-` | zoom in / out, from 1:8 to 8:1 |
| arrows | scroll a quarter of the screen |
| Home | the largest zoom up to 1:1 that shows the whole picture (also at start) |
| Esc | quit; it prints `viewer: grad.bmp 64 x 48, 24 bits` |

Colours: the viewer loads a colour cube of 6 reds × 8 greens × 4 blues into DAC entries 64–255 (`GUI_PALETTE`, `../kernel/syscalls.md`) and maps every pixel into it through a 4 × 4 ordered dither, so smooth gradients come out as fine patterns rather than bands. Text mode only uses entries 0–63, so the shell's colours are as before afterwards.

`run viewer <file> test` draws the picture, reads back the screen pixel at the picture's centre and checks it is the cube colour (with that pixel's dither) of the picture pixel shown there; it prints the info line and `viewer: PASS` or `viewer: FAIL`. Checks: `viewer` (Paint's `ptest.bmp`), `viewer-24` (a 64 × 48 24-bit gradient the regression run writes), `viewer-gfx`, `viewer-bad`, `viewer-quit`.
