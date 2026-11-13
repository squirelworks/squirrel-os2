# Mouse (1.9.10, IRQ 12 since 2.0.1)

Location: `../../kernel/mouse.asm`

## Model

A PS/2 mouse on the keyboard controller. Since 2.0.1 it is interrupt-driven: `mouse_init` sets the controller's IRQ 12 enable bit, the kernel unmasks IRQ 2 (the cascade) on the master PIC and IRQ 12 on the slave, and `mouse_isr` (vector `0x2C`) reads one byte per interrupt and passes it to `mouse_byte`, which builds 3-byte packets and updates the soft cursor. The ISR sends end-of-interrupt to both PICs.

Mouse bytes are drained everywhere, not only on the desktop. In 1.9.10 they were read only by `mouse_poll` while the desktop ran, so in the text shell a mouse byte stayed in the controller's output buffer and blocked every key behind it (KB-18). Now IRQ 12 takes them at once, and `kbd_isr` checks bit 5 of port `0x64` before it reads: an auxiliary byte that turns up on IRQ 1 goes to `mouse_byte` instead of the keyboard ring.

`mouse_poll` stays as a fallback for the desktop loop. It runs with interrupts disabled, because the ISRs share the packet state, and normally finds nothing. If the mouse did not answer at boot (`mouse_up` is 0), IRQ 12 stays masked and the masks are the 1.9.10 ones.

| Symbol | Meaning |
|--------|---------|
| `mouse_up` | 1 after a successful enable at boot |
| `mouse_x`, `mouse_y` | cursor in pixels, kept inside the live mode (`gfx_width` × `gfx_height`; 320 × 200 before 2.2) |
| `mouse_btns` | bits 0–2: left, right, middle |
| `mouse_clicks` | count of left-button make edges |
| `mouse_irqs` | count of IRQ 12 interrupts (2.0.1) |

`mouse_init` enables the auxiliary device and streaming. The desktop draws a plus at the cursor and treats a left click on a list row as select; a second click on the same row opens it (`apps/desktop.md`).

## Pointer save-under (2.0.1)

The desktop's pointer is a small plus (centre, below, left, right) in colour `0x0F`, drawn by `ptr_show` in `kernel/mouse.asm`. Before drawing it, `ptr_show` reads the pixels it will cover into `ptr_save`. When the pointer moves, `ptr_hide` writes them back first, so it leaves no trail. Before 2.0.1 the old position was never restored, so a pointer that crossed the program list wiped out letters.

`wm_redraw` clears `ptr_vis`. A full repaint has already painted over the pointer, so the saved pixels are stale and must not be written back. The next `ptr_show` saves the new pixels and draws the pointer again. Off-screen pixels are skipped (`gfx_putpixel` clips them, and `gfx_getpixel` returns 0 for them).

`ptrtest` fills mode 13h with a pattern, shows the pointer, moves it, hides it, and checks that the pattern comes back each time. It prints `ptr: PASS` or `ptr: FAIL`.

## Packet decoding (2.0.1)

`mouse_decode` turns a 3-byte packet into screen motion. PS/2 motion is 9 bits: byte 1 and byte 2 hold the low 8 bits of X and Y, and bits 4 and 5 of byte 0 are their sign bits. Before 2.0.1 the driver sign-extended bytes 1 and 2 on their own, so any move of more than 127 counts in one packet went the wrong way. For example, Y = `0x90` with no sign bit is +144, not −112. Bits 6 and 7 of byte 0 are the X and Y overflow bits. When either is set, the motion is meaningless, so it is dropped and only the buttons are used.

`mousetest` first runs `mouse_decode` on a table of fixed packets: each sign case, a 9-bit move each way, and an overflow on each axis. It prints `decode: PASS` or `decode: FAIL`. This works with no mouse attached.

## Shell

`mousetest` waits up to two seconds for motion or a click and prints `mouse: PASS`, or `mouse: FAIL` / `mouse: none`. Since 2.0.1 it does not poll, so only the interrupt path can move the cursor while it waits: a PASS means IRQ 12 works.

Regression checks: `mousetest`, `mouse-still` (no motion gives FAIL), `mouse-shell` (motion and a click, then `systest` still types), `mouse-calc` (motion inside `calc` does not disturb its input), `ptrtest`, and `ptr-trail` (the pointer sweeps across the desktop list, and `files` still reads whole).

## Limits

- No mouse wheel and no drag-and-drop yet; desktop pick-up / drop stay on the keyboard.
