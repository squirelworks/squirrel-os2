#!/usr/bin/env python3
"""Boot the Squirrel-OS/2 image in headless QEMU, type keys, print the screen.

Usage: qemu_screen.py [--disk DATA_IMAGE] [--target DISK] [--floppy|--cdrom] IMAGE [KEYS...]
Each KEYS argument is typed as text; a token like "<ret>", "<esc>",
"<backspace>" or "<up>" is sent as that single QEMU key name, and
"<pause>" waits a second before the next key, and "<gfx>" reads the text
drawn in graphics mode (the 5 x 7 font of tools/font5x7.txt, in 6 x 8
cells at any pixel offset) and prints each line found as "gfx: <text>"
after the text screen.
--disk attaches DATA_IMAGE as the primary slave (the kernel's data disk).
--target attaches DISK as the secondary master (the installer's target;
always a scratch image, never a real disk).
--floppy boots IMAGE from the floppy drive instead of the first hard disk.
--cdrom boots IMAGE as a CD in the secondary master position (installer I.6).
QEMU_EXTRA in the environment adds QEMU options (e.g. QEMU_EXTRA='-cpu 486,-pse'). The 80x25 VGA text buffer is printed at the end.
"""
import os, socket, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

KEYMAP = {' ': 'spc', '\n': 'ret', '-': 'minus', '=': 'equal', '/': 'slash',
          '.': 'dot', ',': 'comma', ';': 'semicolon',
          '+': 'shift-equal', '*': 'shift-8', '%': 'shift-5', '!': 'shift-1',
          '?': 'shift-slash', '(': 'shift-9', ')': 'shift-0', ':': 'shift-semicolon', '_': 'shift-minus',
          '^': 'shift-6', '[': 'bracket_left', ']': 'bracket_right',
          '<': 'shift-comma', '>': 'shift-dot', '|': 'shift-backslash'}


def monitor(sock, cmd):
    sock.sendall((cmd + '\n').encode())
    time.sleep(0.04)
    sock.setblocking(False)
    try:
        while sock.recv(4096):
            pass
    except BlockingIOError:
        pass
    sock.setblocking(True)


def read_ppm(path):
    """-> (width, height, bytes of RGB) of a binary PPM (QEMU screendump)."""
    data = open(path, 'rb').read()
    fields, pos = [], 0
    while len(fields) < 4:              # P6, width, height, maxval
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            pos = data.index(b'\n', pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    return int(fields[1]), int(fields[2]), data[pos + 1:]


def gfx_text(path):
    """Lines of text drawn with the kernel's font on a 320 x 200 screen
    (QEMU may dump it doubled to 640 x 400). A cell is read only when its
    spacing column and bottom row are all one colour (the background); its
    other pixels are ink where they differ from that colour."""
    import mkfont
    font = {tuple(rows): chr(c) for c, rows in mkfont.read().items() if c != 0x20}
    w, h, rgb = read_ppm(path)
    sx, sy = w // 320, h // 200
    px = [[rgb[((y * sy) * w + x * sx) * 3:((y * sy) * w + x * sx) * 3 + 3]
           for x in range(320)] for y in range(200)]
    lines = []
    for oy in range(8):
        for ox in range(6):
            for top in range(oy, 200 - 7, 8):
                text = ''
                for left in range(ox, 320 - 5, 6):
                    bg = px[top + 7][left + 5]
                    ch = ' '
                    if all(px[top + 7][left + i] == bg for i in range(6)) and \
                            all(px[top + r][left + 5] == bg for r in range(7)):
                        rows = tuple(sum((px[top + r][left + c] != bg) << (4 - c) for c in range(5))
                                     for r in range(7))
                        ch = font.get(rows, ' ')
                    text += ch
                for word in text.split('  '):   # runs of text, two spaces apart
                    word = word.strip()
                    if len(word) >= 2 and word not in lines:
                        lines.append(word)
    return lines


def main():
    args = sys.argv[1:]
    drives = []
    if args[:1] == ['--disk']:
        drives = ['-drive', f'format=raw,file={args[1]},index=1,media=disk']
        args = args[2:]
    if args[:1] == ['--target']:        # installer I.1: the disk to install to
        drives += ['-drive', f'format=raw,file={args[1]},index=2,media=disk']
        args = args[2:]
    boot = []
    if args[:1] == ['--floppy']:            # boot IMAGE as a floppy (0.9.3)
        boot = ['-boot', 'a']
        args = args[1:]
    cdrom = args[:1] == ['--cdrom']         # boot IMAGE as a CD (I.6)
    if cdrom:
        boot = ['-boot', 'd']
        args = args[1:]
    image, keys = args[0], args[1:]
    extra = os.environ.get('QEMU_EXTRA', '').split()   # e.g. "-cpu 486,-pse"
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, 'mon')
    dump = os.path.join(tmp, 'vga.bin')
    gfx = []                            # text read from graphics mode
    qemu = subprocess.Popen(['qemu-system-i386', '-display', 'none',
                             '-drive', (f'format=raw,file={image},index=2,media=cdrom' if cdrom
                                        else f'format=raw,file={image},if=floppy' if boot
                                        else f'format=raw,file={image},index=0,media=disk'),
                             *boot, *drives, *extra,
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
            if chunk == '<pause>':      # let the guest run for a second
                time.sleep(1)
                continue
            if chunk == '<gfx>':        # read the text off the graphics screen
                shot = os.path.join(tmp, f'gfx{len(gfx)}.ppm')
                monitor(sock, f'screendump "{shot}"')
                for _ in range(50):
                    if os.path.exists(shot) and os.path.getsize(shot) > 0:
                        break
                    time.sleep(0.1)
                time.sleep(0.2)
                gfx += gfx_text(shot)
                continue
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
        for line in gfx:
            print('gfx: ' + line)
    finally:
        qemu.kill()


if __name__ == '__main__':
    main()
