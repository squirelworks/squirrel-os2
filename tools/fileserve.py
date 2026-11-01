#!/usr/bin/env python3
"""One HTTP/1.0 response, then exit. The guest reaches it through QEMU user-net.

QEMU's slirp gateway is 10.0.2.2. A connection from the guest to
10.0.2.2:<port> arrives here on 127.0.0.1:<port>. The regression starts
this, then runs `fetch 10.0.2.2 <port> /hello.txt`.

Usage: tools/fileserve.py PORT TEXT
"""
import socket
import sys

port = int(sys.argv[1])
body = sys.argv[2].encode('ascii')
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('127.0.0.1', port))
sock.listen(1)
print('listening', port, flush=True)
sock.settimeout(40)
try:
    conn, _ = sock.accept()
except socket.timeout:
    sys.exit(0)
data = b''
conn.settimeout(5)
try:
    while b'\r\n\r\n' not in data and len(data) < 4096:
        chunk = conn.recv(1024)
        if not chunk:
            break
        data += chunk
except socket.timeout:
    pass
head = b'HTTP/1.0 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n' % len(body)
conn.sendall(head + body)
conn.close()
sock.close()
