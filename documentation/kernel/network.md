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

## The NE2000 card

Since 1.9.4 `kernel/ne2k.asm` drives an NE2000 on the ISA bus at I/O 0x300, the DP8390-based card QEMU offers as `ne2k_isa`. It is polled, with no IRQ handler, and it moves data with port I/O only. Run QEMU with `-netdev user,id=n0 -device ne2k_isa,netdev=n0,iobase=0x300,irq=9`, which is what `tools/qemu_screen.py --nic` adds.

- **Probe** (`ne_init`, the `devices` entry `ne0`): reset the card, check that the command register reads back what was written (a missing card reads 0xFF), then read the MAC address from the card's address PROM. In word mode each PROM byte comes twice, so the low byte of each word is kept.
- **Card memory**: 256-byte pages. Pages 0x40 to 0x45 hold one frame to send. Pages 0x46 to 0x7F are the receive ring. The card writes at `CURR`, and the driver reads from `BNRY` + 1.
- **Send** (`ne_xmit`, the interface's transmit routine): pad to 60 bytes, copy the frame to page 0x40 by remote DMA, start the transmit and wait for it to end.
- **Receive** (`ne_poll`): while `BNRY` + 1 is not `CURR`, read the frame's 4-byte header (status, next page, length with CRC), read the frame (in two parts when it wraps past the ring's end), queue it on `ne0` with `net_rxq`, and set `BNRY` behind the next page. It returns the number of frames moved.
- **Receive filter**: frames to the card's own address, and broadcasts.

`devices` lists the card as `ne0     net     ready 52:54:00:12:34:56`, or `absent` without one (checks `nic-devices`, `nic-absent`). With the card, `nettest` also sends an ARP request for 10.0.2.2 and waits up to two seconds for an ARP reply, which QEMU's user network sends. It then prints `nic: PASS`, or `nic: FAIL` (check `nic-test`).
