#!/usr/bin/env python3
"""Host-side SQFS tool for Squirrel-OS/2 data disks (original code).

  sqfs.py IMAGE format [SIZE_KB]     create/overwrite IMAGE as an empty SQFS disk
  sqfs.py IMAGE ls                   list every file and directory, with paths
  sqfs.py IMAGE put HOSTFILE [PATH]  copy a host file in (replaces PATH)
  sqfs.py IMAGE get PATH [HOSTFILE]  copy a file out (stdout without HOSTFILE)
  sqfs.py IMAGE rm PATH              delete a file or an empty directory
  sqfs.py IMAGE mkdir PATH           make a directory

Paths use '/' between directories (0.8.0); they always start at the root.
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
KIND_FILE, KIND_DIR = 0, 1


class Entry:
    def __init__(self, raw):
        self.name = raw[:NAMELEN].split(b'\0')[0].decode('latin-1')
        self.start, self.size, self.cap = struct.unpack_from('<III', raw, NAMELEN)
        self.parent, self.kind = raw[28], raw[29]

    def pack(self):
        raw = self.name.encode('latin-1').ljust(NAMELEN, b'\0')
        raw += struct.pack('<IIIBBH', self.start, self.size, self.cap,
                           self.parent, self.kind, 0)
        return raw

    def clear(self):
        self.name, self.start, self.size, self.cap = '', 0, 0, 0
        self.parent = self.kind = 0


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
        base = DIR_LBA * SECTOR
        self.entries = [Entry(self.data[base + i * DIRENT:base + (i + 1) * DIRENT])
                        for i in range(MAXFILES)]

    def save(self):
        base = DIR_LBA * SECTOR
        for i, e in enumerate(self.entries):
            self.data[base + i * DIRENT:base + (i + 1) * DIRENT] = e.pack()
        with open(self.path, 'r+b') as f:
            f.write(self.data)

    def find_in(self, name, parent):
        for e in self.entries:
            if e.name and e.name == name and e.parent == parent:
                return e
        return None

    def dir_id(self, e):
        return self.entries.index(e) + 1

    def split(self, path):
        """path -> (directory id, last name); exits if a directory is missing."""
        parts = [p for p in path.split('/') if p and p != '.']
        if not parts:
            sys.exit('sqfs: bad path %r' % path)
        parent = 0
        for p in parts[:-1]:
            e = self.find_in(p, parent)
            if e is None or e.kind != KIND_DIR:
                sys.exit('sqfs: no directory %r in %r' % (p, path))
            parent = self.dir_id(e)
        return parent, parts[-1]

    def lookup(self, path):
        parent, name = self.split(path)
        return self.find_in(name, parent)

    def path_of(self, e):
        names = [e.name]
        seen = 0
        while e.parent and seen < MAXFILES:
            e = self.entries[e.parent - 1]
            names.append(e.name)
            seen += 1
        return '/'.join(reversed(names))

    def new_entry(self, path, kind):
        parent, name = self.split(path)
        check_name(name)
        free = [x for x in self.entries if not x.name]
        if not free:
            sys.exit('sqfs: directory full')
        e = free[0]
        e.clear()
        e.name, e.parent, e.kind = name, parent, kind
        return e

    def alloc(self, sectors):
        lba = DATA_LBA
        while lba + sectors <= self.total:
            clash = [e for e in self.entries if e.name and e.cap
                     and e.start < lba + sectors and lba < e.start + e.cap]
            if not clash:
                return lba
            lba = max(e.start + e.cap for e in clash)
        sys.exit('sqfs: disk full')


def check_name(name):
    if (not name or len(name) >= NAMELEN or name in ('.', '..')
            or any(c <= ' ' or c > '~' or c == '/' for c in name)):
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
        for e in d.entries:
            if e.name:
                if e.kind == KIND_DIR:
                    print('%-24s  <dir>' % (d.path_of(e) + '/'))
                else:
                    print('%-24s %6d' % (d.path_of(e), e.size))
    elif cmd == 'put':
        src = args[0]
        dest = args[1] if len(args) > 1 else os.path.basename(src)
        with open(src, 'rb') as f:
            body = f.read()
        e = d.lookup(dest)
        if e is not None and e.kind == KIND_DIR:
            sys.exit('sqfs: %r is a directory' % dest)
        if e is not None:
            e.cap = 0          # free the old extent before allocating
        else:
            e = d.new_entry(dest, KIND_FILE)
        sectors = max(1, (len(body) + SECTOR - 1) // SECTOR)
        e.start, e.size, e.cap = d.alloc(sectors), len(body), sectors
        d.data[e.start * SECTOR:e.start * SECTOR + len(body)] = body
        d.save()
    elif cmd == 'get':
        e = d.lookup(args[0])
        if e is None or e.kind == KIND_DIR:
            sys.exit('sqfs: not found')
        body = bytes(d.data[e.start * SECTOR:e.start * SECTOR + e.size])
        if len(args) > 1:
            with open(args[1], 'wb') as f:
                f.write(body)
        else:
            sys.stdout.buffer.write(body)
    elif cmd == 'rm':
        e = d.lookup(args[0]) or sys.exit('sqfs: not found')
        if e.kind == KIND_DIR and any(x.name and x.parent == d.dir_id(e)
                                      for x in d.entries):
            sys.exit('sqfs: directory not empty')
        e.clear()
        d.save()
    elif cmd == 'mkdir':
        if d.lookup(args[0]) is not None:
            sys.exit('sqfs: %r exists' % args[0])
        d.new_entry(args[0], KIND_DIR)
        d.save()
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
