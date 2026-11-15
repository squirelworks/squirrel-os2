#!/usr/bin/env python3
"""A DNS server and an HTTP/1.1 server for the 3.0 network checks.

The guest reaches both through QEMU user-net: slirp delivers the guest's
UDP and TCP to 10.0.2.2:<port> on the host at 127.0.0.1:<port>. The
regression starts this, points the guest's resolver at it with
`dns 10.0.2.2 <dnsport>`, and fetches pages with `run wget`.

DNS (UDP, A queries only):
  squirrel.test       -> 10.0.2.2
  www.squirrel.test   -> CNAME squirrel.test, then 10.0.2.2 (name compression)
  anything else       -> NXDOMAIN

HTTP/1.1 (one request per connection, Connection: close):
  /hello.txt          Content-Length body
  /chunked.txt        Transfer-Encoding: chunked
  /moved              302 to /hello.txt
  /big.bin            BIG_SIZE bytes, byte i = (i * 7 + 3) & 255, Content-Length
  /echo               the request's Host and User-Agent lines, as the body
  anything else       404

Usage: tools/netserve.py HTTPPORT DNSPORT   (runs until killed)
Original code.
"""
import socket
import struct
import sys
import threading

HELLO = b'hello from squirrel over HTTP/1.1\n'
CHUNKS = [b'chunked ', b'transfer ', b'works\n']
BIG_SIZE = 20000


def big():
    return bytes((i * 7 + 3) & 255 for i in range(BIG_SIZE))


def dns_name(data, pos):
    labels = []
    while data[pos]:
        n = data[pos]
        labels.append(data[pos + 1:pos + 1 + n].decode('ascii', 'replace'))
        pos += 1 + n
    return '.'.join(labels).lower(), pos + 1


def dns_answer(query):
    qid, flags, qd = struct.unpack('>HHH', query[:6])
    name, end = dns_name(query, 12)
    question = query[12:end + 4]
    qtype = struct.unpack('>H', query[end:end + 2])[0]
    head = lambda rcode, an: struct.pack('>HHHHHH', qid, 0x8180 | rcode, 1, an, 0, 0)
    a_rr = lambda ptr: struct.pack('>HHHIH', 0xC000 | ptr, 1, 1, 60, 4) + bytes([10, 0, 2, 2])
    if qtype == 1 and name == 'squirrel.test':
        return head(0, 1) + question + a_rr(12)
    if qtype == 1 and name == 'www.squirrel.test':
        # CNAME www.squirrel.test -> squirrel.test (as a pointer into the question)
        target = 12 + 1 + len('www')            # "squirrel.test" inside the question
        cname = struct.pack('>HHHIH', 0xC00C, 5, 1, 60, 2) + struct.pack('>H', 0xC000 | target)
        return head(0, 2) + question + cname + a_rr(target)
    return head(3, 0) + question


def serve_dns(port):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', port))
    while True:
        data, peer = sock.recvfrom(1024)
        try:
            sock.sendto(dns_answer(data), peer)
            print('dns', dns_name(data, 12)[0], flush=True)
        except Exception as exc:   # a malformed query: no answer
            print('dns bad', exc, flush=True)


def respond(conn):
    conn.settimeout(10)
    data = b''
    while b'\r\n\r\n' not in data and len(data) < 8192:
        chunk = conn.recv(2048)
        if not chunk:
            return
        data += chunk
    lines = data.split(b'\r\n')
    print('http', lines[0].decode('ascii', 'replace'), flush=True)
    parts = lines[0].split()
    path = parts[1] if len(parts) > 1 else b'/'
    if path == b'/hello.txt':
        body = HELLO
        conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n'
                     b'Connection: close\r\n\r\n' % len(body) + body)
    elif path == b'/chunked.txt':
        out = b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n'
        for c in CHUNKS:
            out += b'%x;ext=1\r\n' % len(c) + c + b'\r\n'
        conn.sendall(out + b'0\r\nX-Trailer: yes\r\n\r\n')
    elif path == b'/moved':
        conn.sendall(b'HTTP/1.1 302 Found\r\nLocation: /hello.txt\r\nContent-Length: 0\r\n'
                     b'Connection: close\r\n\r\n')
    elif path == b'/big.bin':
        body = big()
        conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n'
                     % len(body) + body)
    elif path == b'/echo':
        body = b'\n'.join(l for l in lines if l.lower().startswith((b'host:', b'user-agent:'))) + b'\n'
        conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n'
                     % len(body) + body)
    else:
        body = b'not here\n'
        conn.sendall(b'HTTP/1.1 404 Not Found\r\nContent-Length: %d\r\nConnection: close\r\n\r\n'
                     % len(body) + body)


def serve_http(port):
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('127.0.0.1', port))
    sock.listen(4)
    while True:
        conn, _ = sock.accept()
        try:
            respond(conn)
        except OSError as exc:
            print('http error', exc, flush=True)
        finally:
            conn.close()


def main():
    http_port, dns_port = int(sys.argv[1]), int(sys.argv[2])
    threading.Thread(target=serve_dns, args=(dns_port,), daemon=True).start()
    print('listening', http_port, dns_port, flush=True)
    serve_http(http_port)


if __name__ == '__main__':
    main()
