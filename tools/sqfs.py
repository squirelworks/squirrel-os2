#!/usr/bin/env python3
"""Host-side SQFS tool for Squirrel-OS/2 data disks (original code).

  sqfs.py IMAGE format [SIZE_KB]     create/overwrite IMAGE as an empty SQFS disk
  sqfs.py IMAGE ls                   list files
  sqfs.py IMAGE put HOSTFILE [NAME]  copy a host file in (replaces NAME)
  sqfs.py IMAGE get NAME [HOSTFILE]  copy a file out (stdout without HOSTFILE)
  sqfs.py IMAGE rm NAME              delete a file

The format matches kernel/fs.asm and documentation/kernel/filesystem.md.
"""
import os
import struct
import sys

SECTOR = 512
MAGIC = 0x53465153
VERSION = 1
DIR_LBA, DIR_SECTS = 1, 4
DATA_LBA = DIR_LBA + DIR_SECTS
DIRENT = 32
MAXFILES = DIR_SECTS * SECTOR // DIRENT
NAMELEN = 16


class Disk:
    def __init__(self, path):
        self.path = path
        with open(path, 'rb') as f:
            self.data = bytearray(f.read())
        if len(self.data) < (DATA_LBA + 2) * SECTOR:
            sys.exit('sqfs: image too small')
        magic, ver, self.total = struct.unpack_from('<III', self.data, 0)
        if magic != MAGIC:
            sys.exit('sqfs: not an SQFS disk (run format first)')
        self.entries = []
        for i in range(MAXFILES):
            off = DIR_LBA * SECTOR + i * DIRENT
            raw = self.data[off:off + DIRENT]
            name = raw[:NAMELEN].split(b'\0')[0].decode('latin-1')
            start, size, cap = struct.unpack_from('<III', raw, NAMELEN)
            self.entries.append([name, start, size, cap])

    def save(self):
        for i, (name, start, size, cap) in enumerate(self.entries):
            off = DIR_LBA * SECTOR + i * DIRENT
            raw = name.encode('latin-1').ljust(NAMELEN, b'\0')
            raw += struct.pack('<IIII', start, size, cap, 0)
            self.data[off:off + DIRENT] = raw
        with open(self.path, 'r+b') as f:
            f.write(self.data)

    def find(self, name):
        for e in self.entries:
            if e[0] == name:
                return e
        return None

    def alloc(self, sectors):
        lba = DATA_LBA
        while lba + sectors <= self.total:
            clash = [e for e in self.entries if e[0] and e[3]
                     and e[1] < lba + sectors and lba < e[1] + e[3]]
            if not clash:
                return lba
            lba = max(e[1] + e[3] for e in clash)
        sys.exit('sqfs: disk full')


def check_name(name):
    if not name or len(name) >= NAMELEN or any(c <= ' ' or c > '~' for c in name):
        sys.exit('sqfs: bad name %r' % name)


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    path, cmd, args = argv[1], argv[2], argv[3:]
    if cmd == 'format':
        size = int(args[0]) * 1024 if args else 1024 * 1024
        with open(path, 'wb') as f:
            f.truncate(size)
            sb = struct.pack('<IIIIII', MAGIC, VERSION, size // SECTOR - 1,
                             DIR_LBA, DIR_SECTS, DATA_LBA)
            f.write(sb)
        return
    d = Disk(path)
    if cmd == 'ls':
        for name, start, size, cap in d.entries:
            if name:
                print('%-16s %6d' % (name, size))
    elif cmd == 'put':
        src = args[0]
        name = args[1] if len(args) > 1 else os.path.basename(src)
        check_name(name)
        with open(src, 'rb') as f:
            body = f.read()
        e = d.find(name)
        if e:
            e[0] = ''          # free the old extent before allocating
        sectors = max(1, (len(body) + SECTOR - 1) // SECTOR)
        lba = d.alloc(sectors)
        if e is None:
            free = [x for x in d.entries if not x[0]]
            if not free:
                sys.exit('sqfs: directory full')
            e = free[0]
        e[:] = [name, lba, len(body), sectors]
        d.data[lba * SECTOR:lba * SECTOR + len(body)] = body
        d.save()
    elif cmd == 'get':
        e = d.find(args[0]) or sys.exit('sqfs: not found')
        body = bytes(d.data[e[1] * SECTOR:e[1] * SECTOR + e[2]])
        if len(args) > 1:
            with open(args[1], 'wb') as f:
                f.write(body)
        else:
            sys.stdout.buffer.write(body)
    elif cmd == 'rm':
        e = d.find(args[0]) or sys.exit('sqfs: not found')
        e[:] = ['', 0, 0, 0]
        d.save()
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
