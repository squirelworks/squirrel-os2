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
| `gfx_fillrect` (1.3.1) | `eax`, `ebx` = top left, `ecx` = width, `edx` = height, colour in `gfx_colour` | — (clipped to the screen) |

## The text screen while in graphics mode

Mode 13h uses the same video memory as text mode. Byte *n* of the graphics window lands in plane *n* & 3. The text characters and attributes sit at the start of planes 0 and 1, and the font in the first 8 KB of plane 2. Pixels there change the text screen or the font when text mode comes back. Everything from byte 32768 on, which is every row from y = 103 (`GFX_SAFE_Y`) down, is clear of both. `gfxtest` (pixel (160, 100), byte 32160, plane 0 past the text) and `gfxprim` (rows 103–199) stay in the clear part. Saving and restoring the text and the font, so that the whole screen can be drawn, belongs with `graph` (task 1.3-graph).

## Test

`gfxtest` (a shell command) enters mode 13h, writes colour `0x2A` to pixel (160, 100) and reads it back, does the same with `0x15`, returns to text mode and prints `gfxtest: PASS` if both reads matched (check `gfxtest`). In text mode the window at `0xA0000` is not mapped, so a read there returns `0xFF` and the test fails: with the call to `gfx_mode13` taken out, it prints `gfxtest: FAIL`. Check `gfx-text` runs `systest` after `gfxtest` to show the text screen works again.

`gfxprim` (1.3.1) clears rows 103–199, draws a line from (20, 120) to (300, 190) in colour `0x0C` and fills the rectangle x 200–259, y 105–124 in `0x0A`. It then reads back seven pixels: the line's two ends and its middle (160, 155), one inside the rectangle, and the three pixels just left of, right of and below the rectangle, which must still be 0. It prints `gfxprim: PASS` when all seven match (checks `gfxprim`, `gfxprim-text`). With the line left out, it prints FAIL.
