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

`SYS_GETC` is unchanged. Delivering keys through the queue as well is task **1.2-key-event**.

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
