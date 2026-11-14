# Control Panel (2.3-control)

`control` is the Control Panel. It changes the theme scheme, mouse
settings, keyboard typematic rate and delay, and the CMOS clock. The
settings are kept in `/desktop/control.cfg` and applied at boot when that
file is there.

## Settings

| Setting | What it does |
|---------|----------------|
| Colours (`scheme`) | Named theme: `warp` (the W.1 defaults), `night` (black desktop, light text), `rose` (magenta desktop, light-red title). Live colours are the `th_*` bytes; `wm` draws with them. |
| Dbl-click (`dbl`) | Ticks between the two presses of a double-click (10..200; default 50). Used by Program Manager and File Manager. |
| Btn swap (`swap`) | `1` swaps the left and right mouse buttons. |
| Speed (`speed`) | Mouse motion multiplier 1..4. |
| Repeat / Delay | Sent to the PS/2 keyboard as typematic rate and delay (`0xF3`). |
| Time / Date | Written to the CMOS RTC (and shown from it). |

## Shell

| Command | Action |
|---------|--------|
| `control` | opens the Control Panel window |
| `control show` | prints the live settings and the clock |
| `control set scheme night` | selects a scheme and applies it |
| `control set dbl 80` | double-click window in ticks |
| `control set swap 1` | swap mouse buttons |
| `control set speed 2` | mouse speed |
| `control set repeat 8` / `delay 40` | keyboard typematic |
| `control set time HH MM SS` | set the RTC time |
| `control set date YYYY MM DD` | set the RTC date |
| `control save` | write `/desktop/control.cfg` (makes `/desktop` if needed) |
| `control load` | read and apply the file |
| `cptest` | self-check → `control: PASS` |

## Window

Up and Down pick a row. Left and Right change it (scheme cycles through
the three names; swap toggles). `S` saves, `L` loads, Esc closes and
returns to text mode.

## File format

One setting per line:

```
scheme night
dbl 77
swap 1
speed 3
repeat 8
delay 33
```

Unknown keys are ignored. A missing file leaves the Warp defaults.

## Testing

`cptest` changes every setting, saves, resets to Warp, loads the file
back, checks the values and that the night desktop colour is live, sets
the RTC and reads it back, then restores Warp on disk. Regression:
`cptest`, `cp-show`, `cp-set`, `cp-save`, `cp-reboot` (a later boot still
has the saved scheme), `cp-time`.
