# Mouse (1.9.10, IRQ 12 since 2.0.1)

Location: `../../kernel/mouse.asm`

## Model

A PS/2 mouse on the keyboard controller. Since 2.0.1 it is interrupt-driven: `mouse_init` sets the controller's IRQ 12 enable bit, the kernel unmasks IRQ 2 (the cascade) on the master PIC and IRQ 12 on the slave, and `mouse_isr` (vector `0x2C`) reads one byte per interrupt and passes it to `mouse_byte`, which builds 3-byte packets and updates the soft cursor. The ISR sends end-of-interrupt to both PICs.

Mouse bytes are drained everywhere, not only on the desktop. In 1.9.10 they were read only by `mouse_poll` while the desktop ran, so in the text shell a mouse byte stayed in the controller's output buffer and blocked every key behind it (KB-18). Now IRQ 12 takes them at once, and `kbd_isr` checks bit 5 of port `0x64` before it reads: an auxiliary byte that turns up on IRQ 1 goes to `mouse_byte` instead of the keyboard ring.

`mouse_poll` stays as a fallback for the desktop loop. It runs with interrupts disabled, because the ISRs share the packet state, and normally finds nothing. If the mouse did not answer at boot (`mouse_up` is 0), IRQ 12 stays masked and the masks are the 1.9.10 ones.

| Symbol | Meaning |
|--------|---------|
| `mouse_up` | 1 after a successful enable at boot |
| `mouse_x`, `mouse_y` | cursor in mode-13h pixels (0..319, 0..199) |
| `mouse_btns` | bits 0–2: left, right, middle |
| `mouse_clicks` | count of left-button make edges |
| `mouse_irqs` | count of IRQ 12 interrupts (2.0.1) |

`mouse_init` enables the auxiliary device and streaming. The desktop draws a plus at the cursor and treats a left click on a list row as select; a second click on the same row opens it (`apps/desktop.md`).

## Shell

`mousetest` waits up to two seconds for motion or a click and prints `mouse: PASS`, or `mouse: FAIL` / `mouse: none`. Since 2.0.1 it does not poll, so only the interrupt path can move the cursor while it waits: a PASS means IRQ 12 works.

Regression checks: `mousetest`, `mouse-still` (no motion gives FAIL), `mouse-shell` (motion and a click, then `systest` still types), `mouse-calc` (motion inside `calc` does not disturb its input).

## Limits

- No mouse wheel and no drag-and-drop yet; desktop pick-up / drop stay on the keyboard.
