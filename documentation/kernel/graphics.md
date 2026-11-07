# Graphics Primitives (1.3)

Location: `../../kernel/gfx.asm` (included from `kernel/pm.asm`)

## Mode

- 320 × 200 with 256 colours: VGA mode 13h. Pixel (x, y) is the byte at `0xA0000 + y * 320 + x`.
- Protected mode has no BIOS, so `gfx_mode13` and `gfx_text` program the VGA registers directly: the misc output register, 5 sequencer, 25 CRTC, 9 graphics-controller and 21 attribute-controller registers, from the tables `gfx_regs_13h` and `gfx_regs_text`. CRTC registers 0–7 are unlocked first (bit 7 of register `0x11`).
- `gfx_text` returns to the 80 × 25 text mode and puts the hardware cursor back. The DAC palette is not changed by either.
- Live geometry is in `gfx_base`, `gfx_width`, `gfx_height`, `gfx_pitch`, `gfx_bpp` (mode 13h sets them to `0xA0000` / 320 / 200 / 320 / 8). `gfx_putpixel` / `gfx_getpixel` use those fields; at 32 bpp they write and read a dword (the colour byte is the blue channel) and keep `eax` / `ebx`.

## VBE linear framebuffer (2.1)

`kernel/vbe.asm` (since **2.1-vbe-mode**, modes in **2.1-modes**, double buffering in **2.1-dblbuf**) sets Bochs/QEMU DISPI linear modes from protected mode: 640×480, 800×600 and 1024×768 at 8, 16 and 32 bpp.

- DISPI ports `0x01CE` / `0x01CF` on QEMU's standard VGA (PCI `1234:1111`). The LFB address is that device's BAR0; `vm_map_range` identity-maps enough 4 MB pages in the kernel page directory for two copies of the largest mode (1024×768×32), so double buffering has room. Process page directories created earlier are not updated yet; only the kernel directory is, which is enough while the shell alone draws.
- `vbe_setup` finds DISPI and the BAR, maps the LFB, and saves the text screen/font (`gfx_save`). `vbe_mode` (width, height, bpp) programs DISPI, reads XRES/YRES/BPP back, and updates `gfx_*` / `gfx_vbe`. CF means setup failed or the adapter refused the mode (then DISPI is disabled and the text screen restored). `gfx_vbe_640_32` is a thin wrapper for 640×480×32.
- **Double buffering:** `vbe_setup` maps two copies of the largest mode in the LFB. `vbe_dblbuf` keeps the DISPI-visible page as the front (`vbe_front`) and points `gfx_base` at the next page in VRAM (the back). `gfx_putpixel` / `gfx_getpixel` then draw and read the back. `vbe_flip` blits the back page onto the front; `gfx_base` stays on the back. `vbe_front_getpixel` reads the visible page without changing the draw target. Leaving the mode (`gfx_text` / `vbe_disable`) or entering a new mode clears the double-buffer state.
- PCI BAR discovery probes function 0 of each bus/dev first and only scans functions 1–7 when function 0 exists, so a missing VGA is not a full 65,536-slot walk.
- `gfx_putpixel` / `gfx_getpixel` honour 8, 16 and 32 bpp (at 16/32 bpp the colour byte is the low byte of the pixel).
- `gfx_text` disables DISPI when `gfx_vbe` is set, then loads the text registers and restores the saved screen/font.
- The desktop and window manager still use mode 13h. Later 2.1 boxes add dirty rectangles and a blitter with clipping.

### Test

`vbetest` walks all nine modes above; for each it writes colours `0x2A` and `0x15` to pixel (100, 100) and reads them back, then arms double buffering, draws `0x3C` on the back, checks the front is still `0x15`, flips, and checks the front is `0x3C`. It returns to text mode and prints `vbe: PASS`. When VBE setup fails it uses mode 13h once (no double buffering) and prints `vbe: 13h` if that read-back works. Checks `vbetest` and `vbetest-text` (`systest` after it).

## Routines

| Routine | In | Out |
|---------|----|-----|
| `gfx_mode13` | — | graphics mode |
| `gfx_text` | — | text mode, cursor restored |
| `gfx_putpixel` | `eax` = x, `ebx` = y, `cl` = colour | — (off-screen pixels are ignored; draws the back buffer when double buffering) |
| `gfx_getpixel` | `eax` = x, `ebx` = y | `cl` = colour (0 off screen; reads the draw target) |
| `vbe_dblbuf` | — (current VBE mode) | CF set if not in VBE mode or virtual height refused |
| `vbe_flip` | — | blits the back buffer onto the visible front; CF if double buffering is off |
| `vbe_front_getpixel` | `eax` = x, `ebx` = y | `cl` = colour from the visible page (0 off screen) |
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
