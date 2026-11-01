# Mouse (1.9.10)

Location: `../../kernel/mouse.asm`

## Model

A polled PS/2 mouse on the keyboard controller. There is no IRQ12 handler: `mouse_poll` reads auxiliary bytes when bit 5 of port `0x64` is set, builds 3-byte packets, and updates a soft cursor.

| Symbol | Meaning |
|--------|---------|
| `mouse_up` | 1 after a successful enable at boot |
| `mouse_x`, `mouse_y` | cursor in mode-13h pixels (0..319, 0..199) |
| `mouse_btns` | bits 0–2: left, right, middle |
| `mouse_clicks` | count of left-button make edges |

`mouse_init` enables the auxiliary device and streaming. The desktop draws a plus at the cursor and treats a left click on a list row as select; a second click on the same row opens it (`apps/desktop.md`).

## Shell

`mousetest` waits up to two seconds for motion or a click and prints `mouse: PASS`, or `mouse: FAIL` / `mouse: none`.

## Limits

- Polled only; the PIC still masks the slave (IRQ12 unused).
- No mouse wheel and no drag-and-drop yet; desktop pick-up / drop stay on the keyboard.
