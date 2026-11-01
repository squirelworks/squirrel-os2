# Network

Since 1.9.3 the kernel has a small network layer: interfaces with a receive queue, and a loopback interface. It is the base for the 2.0 networking boxes in `../../TODO.md`. These are an NE2000 driver, ARP, IPv4 with ping, UDP for programs, and a small TCP client. The code is `kernel/net.asm`.

## Interfaces

An interface is a record in kernel data:

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | `IF_NAME` | ASCIIZ name (`lo`) |
| 4 | `IF_XMIT` | the transmit routine: esi = frame, ecx = length → CF set if not sent |
| 8 | `IF_HEAD` | the next queue slot to read |
| 12 | `IF_TAIL` | the next queue slot to fill |
| 16 | `IF_COUNT` | frames waiting |
| 20 | `IF_SLOTS` | `NET_QLEN` (8) page addresses |

A frame is 1 to `NET_MTU` (1514) bytes: an Ethernet frame without its CRC. Each queued frame lives in its own 4 KB page from `pg_alloc`, with its length in the first dword and the bytes after it. The page is taken when the frame is queued and given back when it is read. An idle interface holds no memory, so `mem` shows the same free memory before and after `nettest`.

| Routine | In | Out |
|---------|----|-----|
| `net_send` | ebx = interface, esi = frame, ecx = length | CF set if the length is 0 or over `NET_MTU`, or the interface could not take it |
| `net_rxq` | ebx = interface, esi = frame, ecx = length | puts a copy on the receive queue; CF set if the queue is full or no page is free |
| `net_recv` | ebx = interface, edi = buffer, ecx = its size | eax = the frame's length (a longer frame is cut to the buffer), CF clear; or eax = −1, CF set, if nothing is waiting |

A driver's transmit routine sends the frame on its wire, and its receive side calls `net_rxq` for each frame that arrives. The loopback interface `net_lo` transmits by calling `net_rxq` on itself, so what is sent on it comes back in order.

## nettest

`nettest` sends three frames on loopback, of 60, 1514 and 1 bytes, each filled with its own pattern. It reads them back and checks each one's length and bytes, then checks that the queue is empty and that frames of 1515 and 0 bytes are refused. It prints `net: PASS`, or `net: FAIL` (checks `nettest`, `nettest-mem`). With the queue cut to one frame, or with `net_recv` not moving to the next slot, it prints FAIL.
