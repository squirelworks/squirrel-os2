# Network

Since 1.9.3 the kernel has a small network layer: interfaces with a receive queue, and a loopback interface. It is the base for the 2.0 networking boxes in `../../TODO.md`. These are an NE2000 driver, ARP, IPv4 with ping, UDP for programs, and a small TCP client. The code is `kernel/net.asm`, `kernel/ne2k.asm` and `kernel/arp.asm`.

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
- **Receive** (`ne_poll`): while `BNRY` + 1 is not `CURR`, read the frame's 4-byte header (status, next page, byte count), read the frame (in two parts when it wraps past the ring's end), queue it on `ne0` with `net_rxq`, and set `BNRY` behind the next page. The byte count includes that header and the frame, not a CRC. It returns the number of frames moved.
- **Receive filter**: frames to the card's own address, and broadcasts.

`devices` lists the card as `ne0     net     ready 52:54:00:12:34:56`, or `absent` without one (checks `nic-devices`, `nic-absent`). With the card, `nettest` also sends an ARP request for 10.0.2.2 and waits up to two seconds for an ARP reply, which QEMU's user network sends. It then prints `nic: PASS`, or `nic: FAIL` (check `nic-test`).

## Ethernet and ARP

Since 1.9.5 the guest has the address 10.0.2.15, which is the address QEMU's user network gives a guest. `net_pump` polls the card and takes every waiting frame off `ne0` and off loopback. A frame whose type is ARP (bytes `08 06`) is handled; anything else is dropped until IPv4 arrives.

An ARP frame is the 14-byte Ethernet header plus 28 bytes: Ethernet and IPv4, address lengths 6 and 4, then a request (`00 01`) or a reply (`00 02`), then the sender's Ethernet address and IP address and the target's. The kernel keeps eight of these in a table. A repeat of an address replaces its row; a ninth address replaces the oldest.

`arp_resolve` returns the Ethernet address for an IP address. 10.0.2.15 is the card's own address and is not asked for. Any other address is looked up, and on a miss a broadcast request is sent and the card is polled for two seconds (200 ticks). The reply's sender is stored. No card, or no reply, is a failure.

The shell command `arp <ip>` prints that address as `52:55:0a:00:02:02`, or `No reply`, or `Bad address` when the text is not four numbers. `arp 10.0.2.2` is the gateway QEMU answers, whose address is `52:55:0a:00:02:02` (checks `arp-gw`, `arp-self`, `arp-none`, `arp-bad`, `arp-nonic`). A request for our own address is answered, so the gateway can find us later.

## IPv4 and ping

Since 1.9.6 `kernel/ip.asm` sends and receives IPv4. The header is 20 bytes: version 4, no options, and a fragment is dropped. The checksum covers the header only. The guest's network defaults to 10.0.2.15 with mask 255.255.255.0 and gateway 10.0.2.2, which is QEMU's user network. Since 1.9.11 those three values are kept in `net_our_ip`, `net_netmask` and `net_gw_ip` and can be changed.

`ip_output` chooses the wire. 127.0.0.0/8 and the guest's own address go out on loopback, with 127.0.0.1 as the source when the destination is on 127.0.0.0/8. Another address on the same network (matched with the mask) is asked of ARP and sent on `ne0`. Anything else is sent to the gateway's Ethernet address, still addressed to the real destination. An address learned from a received frame is kept in the ARP table.

`ifconfig` prints `inet`, `mask` and `gw`. `ifconfig <ip> <mask> <gw>` sets them (checks `ifconfig`, `ifconfig-set`).

ICMP echo (type 8) to us, or to 127.0.0.1, is answered with an echo reply (type 0). `ping <ip>` sends four requests, waits up to a second for each matching reply, and prints how many came back, as `4 of 4`. `ping 10.0.2.2` is the gateway. `ping 127.0.0.1` does not need the card (checks `ping-lo`, `ping-gw`, `ping-bad`).

## UDP

Since 1.9.7 a program can send and receive UDP. There are four sockets. Each bound port belongs to one process; when that process is gone the port is free again. A datagram carries at most 256 bytes, and four may wait on a socket. The checksum covers the pseudo-header and the datagram. A received checksum of zero is accepted as "not computed".

`net_sendto` (`SYS_NETSENDTO`, 30) takes a block in `ebx`:

| Offset | Size | Meaning |
|--------|------|---------|
| 0 | 4 | destination address, first octet in the low byte |
| 4 | 2 | destination port |
| 6 | 2 | local port, or 0 to pick one from 4096 up |
| 8 | 4 | the bytes |
| 12 | 4 | how many |

It returns how many bytes were sent, or −1 if the local port is taken or the datagram cannot be sent.

`net_recvfrom` (`SYS_NETRECVFROM`, 31) takes a block in `ebx`:

| Offset | Size | Meaning |
|--------|------|---------|
| 0 | 2 | local port to bind |
| 2 | 2 | source port, written on return |
| 4 | 4 | buffer |
| 8 | 4 | size of the buffer (a longer datagram is cut) |
| 12 | 4 | source address, written on return |
| 16 | 4 | ticks to wait, or 0 to return at once |

It returns the datagram's length, −1 if another process already has the port, or −2 if nothing arrived. The buffer receives only as many bytes as fit. Binding and receiving are the same call: the first call with nothing waiting still keeps the port.

`programs/udptest.asm` binds port 5000, sends `udpok` to 127.0.0.1:5000, reads it back, and a second process is refused that port. It prints `udp: PASS` (check `udp`).

## TCP

Since 1.9.8 the kernel can keep one TCP connection: connect, send, receive, close. Segments we send have no options. A segment we receive may, and those bytes are skipped. Data is kept only when its sequence number is the next one expected; anything else is acknowledged so the sender tries again. Each segment is sent a second time if nothing comes back within a second.

`fetch <ip> <port> <path>` connects, sends `GET <path> HTTP/1.0` and a blank line, and prints whatever comes back until the server closes or the wait ends. `No reply` means the handshake or the request was not acknowledged.

The regression listens on the host at 127.0.0.1:18080 (`tools/fileserve.py`). QEMU's user network delivers a guest connection to 10.0.2.2:18080 there. `fetch 10.0.2.2 18080 /hello.txt` prints the file (check `fetch-hello`).
