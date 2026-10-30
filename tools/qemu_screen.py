#!/usr/bin/env python3
"""Boot the Squirrel-OS/2 image in headless QEMU, type keys, print the screen.

Usage: qemu_screen.py IMAGE [KEYS...]
Each KEYS argument is typed as text; a token like "<ret>", "<esc>",
"<backspace>" or "<up>" is sent as that single QEMU key name. The 80x25 VGA text buffer is printed at the end.
"""
import os, socket, subprocess, sys, tempfile, time

KEYMAP = {' ': 'spc', '\n': 'ret', '-': 'minus', '=': 'equal', '/': 'slash',
          '.': 'dot', ',': 'comma', ';': 'semicolon',
          '+': 'shift-equal', '*': 'shift-8', '%': 'shift-5', '!': 'shift-1',
          '?': 'shift-slash', ':': 'shift-semicolon', '_': 'shift-minus'}


def monitor(sock, cmd):
    sock.sendall((cmd + '\n').encode())
    time.sleep(0.08)
    sock.setblocking(False)
    try:
        while sock.recv(4096):
            pass
    except BlockingIOError:
        pass
    sock.setblocking(True)


def main():
    image, keys = sys.argv[1], sys.argv[2:]
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, 'mon')
    dump = os.path.join(tmp, 'vga.bin')
    qemu = subprocess.Popen(['qemu-system-i386', '-display', 'none',
                             '-drive', f'format=raw,file={image}',
                             '-monitor', f'unix:{path},server,nowait'])
    try:
        for _ in range(50):
            if os.path.exists(path):
                break
            time.sleep(0.1)
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(path)
        time.sleep(1.5)
        for chunk in keys:
            if chunk.startswith('<') and chunk.endswith('>') and len(chunk) > 2:
                monitor(sock, 'sendkey ' + chunk[1:-1])
                continue
            for ch in chunk:
                key = KEYMAP.get(ch, ch)
                if ch.isupper():
                    key = 'shift-' + ch.lower()
                monitor(sock, 'sendkey ' + key)
        time.sleep(0.5)
        monitor(sock, f'pmemsave 0xb8000 4000 "{dump}"')
        for _ in range(50):
            if os.path.exists(dump) and os.path.getsize(dump) == 4000:
                break
            time.sleep(0.1)
        data = open(dump, 'rb').read()
        for row in range(25):
            line = data[row * 160:(row + 1) * 160:2].decode('cp437')
            print(line.rstrip())
    finally:
        qemu.kill()


if __name__ == '__main__':
    main()
