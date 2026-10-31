# Graphics Primitives (1.3)

Location: `../../kernel/gfx.asm` (included from `kernel/pm.asm`)

## Mode

- 320 × 200 with 256 colours: VGA mode 13h. Pixel (x, y) is the byte at `0xA0000 + y * 320 + x`.
- Protected mode has no BIOS, so `gfx_mode13` and `gfx_text` program the VGA registers directly: the misc output register, 5 sequencer, 25 CRTC, 9 graphics-controller and 21 attribute-controller registers, from the tables `gfx_regs_13h` and `gfx_regs_text`. CRTC registers 0–7 are unlocked first (bit 7 of register `0x11`).
- `gfx_text` returns to the 80 × 25 text mode and puts the hardware cursor back. The DAC palette is not changed by either.

## Routines

| Routine | In | Out |
|---------|----|-----|
| `gfx_mode13` | — | graphics mode |
| `gfx_text` | — | text mode, cursor restored |
| `gfx_putpixel` | `eax` = x, `ebx` = y, `cl` = colour | — (off-screen pixels are ignored) |
| `gfx_getpixel` | `eax` = x, `ebx` = y | `cl` = colour (0 off screen) |
| `gfx_line` (1.3.1) | `eax`, `ebx` = one end, `ecx`, `edx` = the other, colour in `gfx_colour` | — (Bresenham, both ends included, any direction) |
| `gfx_fillrect` (1.3.1) | `eax`, `ebx` = top left, `ecx` = width, `edx` = height, colour in `gfx_colour` | — (clipped to the screen; x and y may be negative) |
| `gfx_drawchar` (1.3.2) | `eax`, `ebx` = top left of the cell, `dl` = character, ink in `gfx_colour`, background in `gfx_bg` | — (a 6 × 8 cell) |
| `gfx_drawstr` (1.3.2) | `esi` = zero-terminated string, `eax`, `ebx` = top left, colours as `gfx_drawchar` | — (6 pixels per character) |

## The text screen while in graphics mode

Mode 13h uses the same video memory as text mode. Byte *n* of the graphics window lands in plane *n* & 3. The text characters and attributes sit at the start of planes 0 and 1, and the font in the first 8 KB of plane 2. Drawing there overwrites the text screen and the font.

Since 1.3.3, `gfx_mode13` first saves both, in three pages from `pg_alloc`: the 4000 bytes of text from `0xB8000`, and the 8 KB of font from plane 2. It reads the font through `0xA0000` with plane 2 selected and odd/even addressing off (`gfx_plane2`). `gfx_text` writes both back once the text registers are loaded, and frees the pages. So any pixel can be drawn, and the screen and the font are as they were afterwards (`graph` draws the whole screen; check `graph-mem` shows the pages come back). If no pages are free, `gfx_mode13` returns with CF set and stays in text mode. The test commands (`gfxtest`, `gfxprim`, `gfxtext`) were written before that and still keep to rows 103–199 (`GFX_SAFE_Y`), past the text and the font.

## Font (1.3.2)

The graphics font is an original 5 × 7 design for the printable ASCII codes 0x20–0x7E. Its source is `tools/font5x7.txt`: one line per glyph, the code in hex and then seven rows of five `#` (ink) or `.` (background). `tools/mkfont.py` turns it into `kernel/font.inc` (seven bytes per glyph, bit 4 the leftmost column); `tools/mkfont.py --check`, run by `tools/regress.sh`, fails if the two disagree. A character outside the font draws as `?`.

Each character fills a 6 × 8 cell: the glyph, then one column and one row of background, so a string reads as words on a solid band.

## Test

`gfxtest` (a shell command) enters mode 13h, writes colour `0x2A` to pixel (160, 100) and reads it back, does the same with `0x15`, returns to text mode and prints `gfxtest: PASS` if both reads matched (check `gfxtest`). In text mode the window at `0xA0000` is not mapped, so a read there returns `0xFF` and the test fails: with the call to `gfx_mode13` taken out, it prints `gfxtest: FAIL`. Check `gfx-text` runs `systest` after `gfxtest` to show the text screen works again.

`gfxprim` (1.3.1) clears rows 103–199, draws a line from (20, 120) to (300, 190) in colour `0x0C` and fills the rectangle x 200–259, y 105–124 in `0x0A`. It also fills a rectangle 20 wide starting at x = -10, y 130–139, in `0x09`, of which x 0–9 is on the screen. It then reads back ten pixels: the line's two ends and its middle (160, 155), one inside the first rectangle, the three pixels just left of, right of and below it, which must still be 0, and (0, 135), (9, 135) and (10, 135) for the clipped one. It prints `gfxprim: PASS` when all ten match (checks `gfxprim`, `gfxprim-text`). With the line left out, it prints FAIL.

`gfxtext` (1.3.2) clears rows 103–199 and draws `Squirrel-OS/2` at (40, 140), ink `0x0F` on background `0x01`. It reads back two ink pixels and the top-left background pixel of the `S`, the spacing column after it, and the pixel left of the string, which must still be 0, and prints `gfxtext: PASS` (checks `gfxtext`, `gfxtext-text`). Without the drawing, it prints FAIL.
