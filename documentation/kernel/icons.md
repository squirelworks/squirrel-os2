# Icons (2.3-icons)

Squirrel-OS/2 icons are an original format: 32 × 32 pixels, up to 15 colours plus transparent, 536 bytes. The built-in icons are drawn as text art in `tools/icons/*.txt`; `tools/mkicon.py` turns them into `kernel/icons.inc` (`--check`, run by `tools/regress.sh`, fails if it is stale), and `tools/mkicon.py ART.txt FILE` writes a single icon file for a disk.

## Text art

```
# comment
colour K 0x00   # a letter of the art and the palette index it stands for
colour Y 0x0E
..KKKKKKKK......................   32 rows of 32 characters:
..KYYYYYYK......................   a named letter, or "." for transparent
```

At most 15 `colour` lines. Palette indices are the screen's 8-bit indices. The DAC keeps the 64-colour EGA palette in both the VBE mode and mode 13h (index bits: 0x01 blue, 0x02 green, 0x04 red at two thirds, 0x08, 0x10, 0x20 the same at one third), so an icon looks the same in both: black 0x00, blue 0x01, green 0x02, cyan 0x03, red 0x04, brown 0x14, light grey 0x07, dark grey 0x38, light blue 0x39, light green 0x3A, light red 0x3C, yellow 0x3E, white 0x3F (as `theme.inc`).

## Icon file (SQIC)

| Offset | Size | Contents |
|--------|------|----------|
| 0 | 4 | `SQIC` |
| 4 | 1 | width (32) |
| 5 | 1 | height (32) |
| 6 | 2 | flags, reserved (0) |
| 8 | 16 | the palette index of each nibble value; nibble 0 is transparent (byte 8 unused) |
| 24 | 512 | the pixels, rows top first, two a byte, the left one in the high nibble |

## Kernel

| Routine | In | Out |
|---------|----|-----|
| `gfx_drawicon` | esi = icon, eax, ebx = top left | draws it through `gfx_putpixel` (so the clip and occluders apply), skipping transparent pixels; CF set and nothing drawn if esi is not an SQIC icon or its width is odd |
| `icon_byname` | esi = name | esi = the built-in icon (CF clear), or CF set and esi unchanged |

`icon_table` lists the built-in icons, two dwords each (name, data), `ICON_COUNT` of them, sorted by name; `ICON_<NAME>` is each one's index. The set: `calc`, `draw`, `edit`, `file`, `files` (the file browser), `folder`, `graph`, `program` (any program without its own), `shell`, `vedit`.

## Test

`icontest` fills a band with the desktop colour, draws `folder` and `calc` (looked up with `icon_byname`), reads back a transparent corner of each, the folder's outline, body and highlight and the calculator's display and last key, checks that an unknown name and a damaged icon are refused (nothing drawn), then prints `icon: PASS` or `icon: FAIL`. Checks `icontest` and `icontest-text`.
