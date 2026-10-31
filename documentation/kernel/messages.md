# Message Queues (1.2)

Location: `../../kernel/msg.asm` (included from `kernel/pm.asm`)

## Model

- Every process slot has one queue of `MSG_QMAX` = 8 messages. A message is one dword: four bytes, or any 32-bit value.
- `spawn` empties the queue of the slot it hands out, so a new process never sees an old process's messages.
- Messages are delivered in the order they were sent (FIFO).
- The queues are kernel memory (`msg_count`, `msg_head`, `msg_data`), not part of any address space, so threads and separately loaded programs use them the same way.

## Calls

| # | Name | Args | Returns |
|---|------|------|---------|
| 27 | `SYS_SEND` | `ebx` = receiver's pid, `ecx` = message | 0; −1 (`MSG_ENOPID`) if no live process has that pid (a zombie counts as gone); −2 (`MSG_EFULL`) if the receiver's queue already holds 8 messages |
| 28 | `SYS_RECV` | — | the oldest message in the caller's own queue |

- `SYS_SEND` never blocks. A full queue is reported at once; the message is not kept, and the sender decides whether to try again later.
- `SYS_RECV` waits while the caller's queue is empty. It waits the way `SYS_GETC` does: through `proc_idle`, which runs other processes or halts until the next interrupt. It cannot fail, so every dword, including −1 and −2, is a valid message.
- A process may send to itself.

`SYS_GETC` is unchanged.

## Key events (1.2.1)

| # | Name | Args | Returns |
|---|------|------|---------|
| 29 | `SYS_KEYEVENTS` | `ebx` = 1 to receive key events, 0 to stop | 0 |

While a process has key events on, every key press also arrives in its queue as the message `MSG_KEY | c` (`MSG_KEY` = `0x4B000000`, `'K'` in the top byte), where `c` is the character `SYS_GETC` returns for that key: Enter 10, Backspace 8, Esc 27, Shift honoured, releases and keys without a character skipped.

The path, in `kbd_isr` (`kernel/pm.asm`) and `key_event` (`kernel/msg.asm`):

1. IRQ 1 puts the raw scancode in the keyboard ring, as before. `SYS_GETC`, the shell and the apps read the ring, so they see every key as they always did.
2. Then `key_event` decodes the same scancode with the same tables, keeping its own Shift state, and posts the character to the process that asked. A full queue drops the event.

Only one process gets key events at a time: the newest caller of `SYS_KEYEVENTS` with 1 takes over. Turning them off only works for the current receiver. A process that ends while it has them on just stops getting them (pids are not reused, so the posts fail quietly).

The queue operations run with interrupts off, because the keyboard IRQ can post in the middle of a `SYS_SEND` or `SYS_RECV`.

`run keyev` turns key events on, reads one key from its queue and the same key with `SYS_GETC`, and prints `keyev: queue q getc q` and `keyev: PASS` when the two match (checks `keyev`, `keyev-shift`).

## Test

`run msg` (check `msg`):

1. sends 8 messages to itself, sees the 9th send return −2 and prints `msg: queue full (-2)`, then receives the 8 back in order;
2. sends to a pid nobody has and expects −1;
3. spawns a child that waits in `SYS_RECV`, sends it the four bytes `ping`, and the child prints `msg: child got ping`.

It prints `msg: PASS` when every step gave the expected result.

## Limitations

- One queue per process, no selecting by sender, and the receiver cannot tell who sent a message unless the message says so.
- No timeout on `SYS_RECV`. A process that waits for a message nobody sends waits until the machine restarts.
- Messages are four bytes. Larger data goes through shared memory (threads) or files.
