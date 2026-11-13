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

`ifconfig` prints `inet`, `mask` and `gw`. `ifconfig <ip> <mask> <gw>` sets them (checks `ifconfig`, `ifconfig-set`). Since 2.0.2 the gateway must be on the new subnet, meaning `(gw XOR ip) AND mask` is zero. Otherwise it prints "Gateway is not on that subnet" and changes nothing (checks `ifconfig-offnet`, `ifconfig-offnet-keep`, `ifconfig-offnet-la`).

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

## Broadcasts (3.0)

`ip_output` sends to 255.255.255.255 on the card with the Ethernet broadcast address, without asking ARP. `ip_input` takes frames to 255.255.255.255, and while the DHCP client is asking it takes frames to any address (a server sends its offer to the address it offers). The NE2000 filter already accepts broadcasts.

`udp_csum` sums the pseudo-header and the datagram in place, so it checks datagrams of any length; `udp_send_raw` (eax = destination, edx = local port | remote port << 16, esi/ecx = bytes up to 576) is how the kernel's own clients send.

## DHCP (3.0)

`kernel/dhcp.asm`, from RFC 2131 and RFC 2132. `dhcp_run` sets the address to 0.0.0.0, broadcasts a DISCOVER from port 68 to port 67 (broadcast flag set, the card's MAC as the client address, a parameter list asking for options 1, 3, 6 and 51), takes the first OFFER for our transaction id and MAC, broadcasts a REQUEST for it (options 50 and 54), and on the ACK sets the address, the mask (option 1, or 255.255.255.0), the gateway (option 3), the DNS server (option 6, port 53) and the lease (option 51). Each step waits three seconds and is tried twice. A NAK or no answer puts the old address back and leaves everything else alone. While it runs, `udp_input` hands datagrams for port 68 to `dhcp_input` before any socket sees them, since a DHCP message is longer than a socket datagram (`UDP_MAX`).

The settings are not renewed when the lease runs out; run `dhcp` again (QEMU's lease is a day).

The shell command `dhcp` prints `dhcp: bound` and the `ifconfig` lines, or `No DHCP server answered` (checks `dhcp`, `dhcp-dns`, `dhcp-nonic`). Setting an address by hand with `ifconfig` or `SYS_NET` marks the settings as manual again.

## DNS (3.0)

`kernel/dns.asm`, from RFC 1035. `dns_resolve` (esi = name → eax = address, CF on failure, `dns_why` = 1 no such name, 2 no answer, 3 a bad name) reads a dotted quad as it is, answers `localhost` with 127.0.0.1, looks in an eight-name cache, and otherwise sends one query (type A, class IN, recursion desired) from port 5353 to the DNS server, twice at most, two seconds each. The answer must come from the server's address with the query's id. The first A record is used; records before it, such as a CNAME, are stepped over, and names in the answer may be compressed (a two-byte pointer). The cache is emptied when the server or the network changes.

The server is QEMU's resolver 10.0.2.3 at boot, or what DHCP said. `dns` shows it; `dns <ip> [port]` sets it, the port being for a test server (the regression's `tools/netserve.py` listens on 127.0.0.1:18053 and is reached as `dns 10.0.2.2 18053`). `host <name>` prints `<name> is <address>`, `Host not found`, `No reply` or `Bad address` (checks `host-name`, `host-cname`, `host-nx`, `host-quad`, `host-local`). `ping` and `fetch` take a name as well as an address (checks `ping-name`, `fetch-name`).

## TCP changes (3.0)

- The receive buffer is 8 KB, and the window offered is what is free in it. When a program takes data out of a buffer whose last offered window was under a quarter of it, an ACK announces the larger window.
- Data is sent 512 bytes a segment; each segment is acknowledged before the next (`tcp_send` loops).
- Each connection uses a new local port from 41000 to 41999, so a second connection soon after the first is not mistaken for it.
- `ne_poll` stops taking frames off the card while the receive queue is full and `net_pump` comes back for the rest, so a burst of segments waits in the card's ring instead of being dropped.

## SYS_NET

`SYS_NET` (37, `kernel/netsys.asm`) gives programs the resolver, the TCP connection and the settings. `ebx` is the operation, as with `SYS_GUI`; pointers from ring 3 are checked per operation (`UA_NET`). `programs/net.inc` has the numbers and address helpers, and `programs/http.inc` builds an HTTP/1.1 client on it (`../apps/network.md`).

| `ebx` | Name | Arguments | Returns |
|-------|------|-----------|---------|
| 0 | `NET_RESOLVE` | `ecx` = name | the address, or −1 |
| 1 | `NET_CONNECT` | `ecx` = address, `edx` = port | 0, −1 no answer, −2 another program has the connection |
| 2 | `NET_SEND` | `ecx` = bytes, `edx` = count | the count, or −1 |
| 3 | `NET_RECV` | `ecx` = buffer, `edx` = size | bytes, 0 when the other side closed and nothing is left, −2 when nothing came for three seconds, −1 not the caller's |
| 4 | `NET_CLOSE` | — | 0, or −1 when it is not the caller's |
| 5 | `NET_INFO` | `ecx` = 28-byte block | 0: +0 address, +4 mask, +8 gateway, +12 DNS server, +16 its port (word), +18 MAC, +24 flags (bit 0 a card, bit 1 from DHCP, bits 16–31 the lease in minutes) |
| 6 | `NET_SET` | `ecx` = 20-byte block: address, mask, gateway, DNS server, its port (word, 0 = 53) | 0, or −1 when the gateway is off the subnet or the address is 0 |
| 7 | `NET_DHCP` | — | 0, or −1 |

There is still one kernel TCP connection. The program that opens it owns it until it closes it or ends; another program's `NET_CONNECT` gets −2 meanwhile. `NET_RECV` pumps the card and yields while it waits.
