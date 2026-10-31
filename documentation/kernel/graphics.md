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

## The text screen while in graphics mode

Mode 13h uses the same video memory as text mode. Byte *n* of the graphics window lands in plane *n* & 3. The text characters and attributes sit in planes 0 and 1 below offset 4000, and the font in plane 2. Pixels there change the text screen or the font when text mode comes back. `gfxtest` uses pixel (160, 100), byte 32160: plane 0, well past the text. Saving and restoring the text planes and the font, so that any pixel can be drawn, belongs with the full-screen graphics of later 1.3 tasks.

## Test

`gfxtest` (a shell command) enters mode 13h, writes colour `0x2A` to pixel (160, 100) and reads it back, does the same with `0x15`, returns to text mode and prints `gfxtest: PASS` if both reads matched (check `gfxtest`). In text mode the window at `0xA0000` is not mapped, so a read there returns `0xFF` and the test fails: with the call to `gfx_mode13` taken out, it prints `gfxtest: FAIL`. Check `gfx-text` runs `systest` after `gfxtest` to show the text screen works again.
