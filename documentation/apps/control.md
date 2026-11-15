# Control Panel (2.3-control)

`control` opens the Control Panel on the window manager's screen. It has eight rows:

| Row | Values | Setting name |
|-----|--------|--------------|
| Colours | Warp, Forest, Plum, Slate | `scheme` 0-3 |
| Double-click | 10 to 200 ticks (100 ticks a second), in steps of 10 | `dblclick` |
| Swap buttons | No, Yes | `swap` 0-1 |
| Mouse speed | Slow (half), Normal, Fast (double) | `speed` 1-3 |
| Key repeat | 0 (30 a second) to 31 (2 a second) | `rate` 0-31 |
| Key delay | 250, 500, 750 or 1000 ms | `delay` 0-3 |
| Date | YYYY-MM-DD, from the CMOS clock | |
| Time | HH:MM:SS, from the CMOS clock | |

A colour scheme sets the desktop and the title bars (focused and idle):

| Scheme | Desktop | Focused title | Idle title |
|--------|---------|---------------|------------|
| Warp | cyan | blue | dark grey |
| Forest | green | brown | dark grey |
| Plum | magenta | red | dark grey |
| Slate | dark grey | blue | black |

## Keys and mouse

| Key | What it does |
|-----|--------------|
| Up / Down | the row before / after |
| Left / Right (or - / +) | the setting's previous / next value, wrapping around; it takes effect at once |
| Enter | on Date or Time: type a new one on the status line, then Enter sets the clock (Esc cancels, Backspace rubs out) |
| Esc | quit; the settings are saved if any changed |

A press on a row chooses it. A press on the chosen row's value acts like Right, or asks for the date or time. The close box and Alt+F4 quit like Esc.

## Saved settings

On quitting after a change, the panel writes `/desktop/control.cfg`, one `name value` line each (`scheme`, `dblclick`, `swap`, `speed`, `rate`, `delay`). At boot, after the data disk is mounted, `cp_boot` reads the file and applies it. A name it does not know, or a value out of range, is skipped. The date and time are not in the file: they go straight to the CMOS clock.

## From the shell

- `control show` prints the settings, whether the keyboard took the repeat rate (`kbd ok`), and the date and time.
- `control NAME VALUE` sets one setting, applies it and saves the file. NAME is one of the setting names above. `control date YYYY-MM-DD` and `control time HH:MM:SS` set the clock. A wrong name or value prints the usage.

## How the settings apply

- **Colours.** `wm_paint` draws the desktop and title bars in `th_desk`, `th_bar` and `th_bar_idle`. These start as the `theme.inc` values; `cp_apply` copies the chosen scheme into them.
- **Double-click.** The Program Manager and the File Manager compare against `cp_dbl` (the old `PM_DBL` is its default).
- **Mouse.** `mouse_byte` passes each move through `cp_mspeed` and the button bits through `cp_mswap`.
- **Keyboard.** `cp_kbd` sends command 0xF3 and `delay << 5 | rate` to the keyboard, with interrupts off, and reads the two 0xFA acknowledgements itself. `kbd_isr` now ignores an interrupt with nothing in the controller's output buffer, so a byte already read this way is not taken as a key.
- **Clock.** `cp_setdate` and `cp_settime` write the CMOS registers (and the century register 0x32), with updates stopped through register B. The values go in as BCD unless register B says binary. A 24-hour clock is assumed.

## Checks

`cptest` prints `cp: PASS`, or `cp: FAIL at N`:
0. the live colours are the saved scheme's (so the boot applied them);
1. `23:59:58` parses and prints back;
2. `2031-02-28` parses and prints back;
3. `24:00:00` and `2031-13-01` are refused;
4. the clock is set to a date and a time and read back, then put back;
5. `cp_set` refuses a value out of range and an unknown name, and takes scheme 2;
6. the desktop is drawn in scheme 2's colour (a pixel read back in mode 13h);
7. with swap on, a made-up left-press packet gives the right button;
8. speed 3 doubles a 4-pixel move and speed 1 halves it;
9. the keyboard acknowledges a repeat rate and delay;
10. a settings text with an unknown name and a value out of range parses as it should.

Every setting is put back afterwards.

The regression checks (`tools/regress.sh`) run on their own disk, `cp.img`, and each one is a new boot:
- `cp-panel`: the window and its default rows.
- `cp-change`: a change saves.
- `cp-reboot`: the change is back after a reboot.
- `cp-cfg`: the saved file.
- `cp-mouse`: a click on the value changes the scheme.
- `cp-rate` and `cp-rate-boot`: the key rate is set from the shell, then after a reboot it is loaded and the keyboard took it.
- `cp-time` and `cp-date-bad`: the clock is set from the panel, and a bad date is refused.
- `cp-cmd-date`: the date and time are set from the shell.
- `cp-bad`: a bad value prints the usage.
- `cptest` and `cp-text`: the self-check passes, and text mode works afterwards.

The code is in `kernel/control.asm`.
