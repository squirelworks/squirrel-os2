#!/usr/bin/env python3
"""Host-side FAT12/16/32 image tool for Squirrel-OS/2 tests (original code).

  fatimg.py IMAGE format SIZE_KB [12|16|32] [--part] [--label NAME]
                                       make an empty FAT image; --part puts it
                                       in partition 1 (at sector 2048) of an
                                       MBR disk
  fatimg.py IMAGE ls [PATH]            list a directory (long names)
  fatimg.py IMAGE put HOSTFILE PATH    copy a host file in (long names kept)
  fatimg.py IMAGE get PATH [HOSTFILE]  copy a file out (stdout without HOSTFILE)
  fatimg.py IMAGE mkdir PATH
  fatimg.py IMAGE check                walk every directory and chain: cross-
                                       linked or lost clusters, sizes that do
                                       not fit their chains, long names whose
                                       checksum does not match; exit 1 if any

Paths use '/' and start at the root; names compare without regard to case.
Written from the published FAT and long-name format descriptions, to test
kernel/fat.asm without needing dosfstools or mtools.
"""
import struct
import sys

SECTOR = 512
EOC = 0x0FFFFFFF
LFN_OFFS = (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30)
SHORT_OK = set(b"!#$%&'()-@^_`{}~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") | set(range(0x80, 0x100))


def die(msg):
    sys.exit('fatimg: ' + msg)


def checksum(name11):
    s = 0
    for c in name11:
        s = (((s & 1) << 7) | (s >> 1)) + c & 0xFF
    return s


def fmt(path, size_kb, bits, part, label):
    total = size_kb * 2
    base = 2048 if part else 0
    sects = total - base
    nfats, media = 2, 0xF8
    if bits == 32:
        rsvd, rootents, spc = 32, 0, 1
    else:
        rsvd, rootents = 1, (224 if bits == 12 else 512)
        spc = 1
    rootsecs = (rootents * 32 + SECTOR - 1) // SECTOR
    while True:
        fatsz = 1
        for _ in range(20):
            clusters = (sects - rsvd - nfats * fatsz - rootsecs) // spc
            need = ((clusters + 2) * bits + 7) // 8
            fatsz = (need + SECTOR - 1) // SECTOR
        if bits == 12 and clusters >= 4085 or bits == 16 and clusters >= 65525:
            spc *= 2
            if spc > 128:
                die('too big for FAT%d' % bits)
            continue
        break
    lo, hi = {12: (1, 4084), 16: (4085, 65524), 32: (65525, 0x0FFFFFF5)}[bits]
    if not lo <= clusters <= hi:
        die('%d KB cannot hold FAT%d (%d clusters)' % (size_kb, bits, clusters))
    img = bytearray(total * SECTOR)
    bs = bytearray(SECTOR)
    bs[0:3] = b'\xEB\x58\x90' if bits == 32 else b'\xEB\x3C\x90'
    bs[3:11] = b'SQUIRREL'
    struct.pack_into('<HBHBHHBHHHI', bs, 11, SECTOR, spc, rsvd, nfats, rootents,
                     sects if sects < 0x10000 and bits != 32 else 0, media,
                     fatsz if bits != 32 else 0, 63, 255, base)
    struct.pack_into('<I', bs, 32, sects if sects >= 0x10000 or bits == 32 else 0)
    lab = (label or 'NO NAME').upper().encode()[:11].ljust(11)
    if bits == 32:
        struct.pack_into('<IHHIHH', bs, 36, fatsz, 0, 0, 2, 1, 6)
        bs[64], bs[66] = 0x80, 0x29
        struct.pack_into('<I', bs, 67, 0x5157524C)
        bs[71:82] = lab
        bs[82:90] = b'FAT32   '
    else:
        bs[36], bs[38] = 0x80, 0x29
        struct.pack_into('<I', bs, 39, 0x5157524C)
        bs[43:54] = lab
        bs[54:62] = b'FAT12   ' if bits == 12 else b'FAT16   '
    bs[510:512] = b'\x55\xAA'
    o = base * SECTOR
    img[o:o + SECTOR] = bs
    if bits == 32:
        img[o + 6 * SECTOR:o + 7 * SECTOR] = bs
        fsi = bytearray(SECTOR)
        struct.pack_into('<I', fsi, 0, 0x41615252)
        struct.pack_into('<III', fsi, 484, 0x61417272, 0xFFFFFFFF, 0xFFFFFFFF)
        fsi[510:512] = b'\x55\xAA'
        img[o + SECTOR:o + 2 * SECTOR] = fsi
    if part:
        mbr = bytearray(SECTOR)
        ptype = {12: 0x01, 16: 0x06 if sects >= 65536 else 0x04, 32: 0x0C}[bits]
        struct.pack_into('<B3sB3sII', mbr, 446, 0x80, b'\xFE\xFF\xFF', ptype,
                         b'\xFE\xFF\xFF', base, sects)
        mbr[510:512] = b'\x55\xAA'
        img[0:SECTOR] = mbr
    with open(path, 'wb') as f:
        f.write(img)
    v = Volume(path)
    v.set(0, 0x0FFFFF00 | media)
    v.set(1, EOC)
    if bits == 32:
        v.set(2, EOC)
    v.save()


class Volume:
    def __init__(self, path):
        self.path = path
        with open(path, 'rb') as f:
            self.img = bytearray(f.read())
        self.base = 0
        if not self.bpb_ok(0):
            for i in range(4):
                e = 446 + 16 * i
                if self.img[e + 4] in (1, 4, 6, 0x0B, 0x0C, 0x0E):
                    self.base = struct.unpack_from('<I', self.img, e + 8)[0]
                    break
            if not self.base or not self.bpb_ok(self.base):
                die('not a FAT volume')
        b = self.base * SECTOR
        (_, self.spc, self.rsvd, self.nfats, rootents, tot16, _, fat16) = \
            struct.unpack_from('<HBHBHHBH', self.img, b + 11)
        tot32, fat32, _, _, self.rootcl = struct.unpack_from('<IIHHI', self.img, b + 32)
        self.fatsz = fat16 or fat32
        self.total = tot16 or tot32
        self.rootsecs = (rootents * 32 + SECTOR - 1) // SECTOR
        self.rootlba = self.rsvd + self.nfats * self.fatsz
        self.datalba = self.rootlba + self.rootsecs
        self.clusters = (self.total - self.datalba) // self.spc
        self.bits = 12 if self.clusters < 4085 else 16 if self.clusters < 65525 else 32
        if self.bits != 32:
            self.rootcl = 0

    def bpb_ok(self, lba):
        b = lba * SECTOR
        if b + SECTOR > len(self.img):
            return False
        bps, spc, rsvd, nf = struct.unpack_from('<HBHB', self.img, b + 11)
        return bps == SECTOR and spc and not spc & (spc - 1) and rsvd and 1 <= nf <= 4

    def save(self):
        with open(self.path, 'r+b') as f:
            f.write(self.img)

    def off(self, lba):
        return (self.base + lba) * SECTOR

    # the FAT
    def get(self, n):
        f = self.off(self.rsvd)
        if self.bits == 12:
            w = struct.unpack_from('<H', self.img, f + n + n // 2)[0]
            v = w >> 4 if n & 1 else w & 0xFFF
            return EOC if v >= 0xFF7 else v
        if self.bits == 16:
            v = struct.unpack_from('<H', self.img, f + 2 * n)[0]
            return EOC if v >= 0xFFF7 else v
        v = struct.unpack_from('<I', self.img, f + 4 * n)[0] & 0x0FFFFFFF
        return EOC if v >= 0x0FFFFFF7 else v

    def set(self, n, v):
        for k in range(self.nfats):
            f = self.off(self.rsvd + k * self.fatsz)
            if self.bits == 12:
                o = f + n + n // 2
                w = struct.unpack_from('<H', self.img, o)[0]
                v12 = v & 0xFFF
                w = (w & 0x000F) | (v12 << 4) if n & 1 else (w & 0xF000) | v12
                struct.pack_into('<H', self.img, o, w)
            elif self.bits == 16:
                struct.pack_into('<H', self.img, f + 2 * n, v & 0xFFFF)
            else:
                o = f + 4 * n
                old = struct.unpack_from('<I', self.img, o)[0]
                struct.pack_into('<I', self.img, o, (old & 0xF0000000) | (v & 0x0FFFFFFF))

    def chain(self, c):
        out, seen = [], set()
        while 2 <= c <= self.clusters + 1 and c not in seen:
            out.append(c)
            seen.add(c)
            c = self.get(c)
        return out

    def alloc(self, after=None):
        for c in range(2, self.clusters + 2):
            if self.get(c) == 0:
                self.set(c, EOC)
                if after:
                    self.set(after, c)
                o = self.off(self.clsec(c))
                self.img[o:o + self.spc * SECTOR] = bytes(self.spc * SECTOR)
                return c
        die('disk full')

    def clsec(self, c):
        return self.datalba + (c - 2) * self.spc

    # directories: (byte offset in the image) of each 32-byte slot
    def slots(self, cl):
        if cl == 0:
            o = self.off(self.rootlba)
            return [o + 32 * i for i in range(self.rootsecs * SECTOR // 32)]
        out = []
        for c in self.chain(cl):
            o = self.off(self.clsec(c))
            out += [o + 32 * i for i in range(self.spc * SECTOR // 32)]
        return out

    def entries(self, cl):
        """-> [(name, short entry offset, [offsets of its slots])]"""
        out, lfn, lslots, want, csum = [], {}, [], 0, None
        for o in self.slots(cl):
            e = self.img[o:o + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5:
                lfn, lslots, want = {}, [], 0
                continue
            if e[11] & 0x3F == 0x0F:
                seq = e[0] & 0x1F
                if e[0] & 0x40:
                    lfn, lslots, want, csum = {}, [], seq, e[13]
                if seq != want or e[13] != csum or not seq:
                    lfn, lslots, want = {}, [], 0
                    continue
                chars = []
                for p in LFN_OFFS:
                    chars.append(struct.unpack_from('<H', e, p)[0])
                lfn[seq] = chars
                lslots.append(o)
                want -= 1
                continue
            if e[11] & 0x08 or e[0] == ord('.'):
                lfn, lslots, want = {}, [], 0
                continue
            name = None
            if lfn and want == 0 and checksum(e[:11]) == csum:
                cs = [c for k in sorted(lfn) for c in lfn[k]]
                if 0 in cs:
                    cs = cs[:cs.index(0)]
                name = ''.join(chr(c) if c < 256 else '?' for c in cs)
            else:
                lslots = []
            if name is None:
                b = e[:8].decode('latin-1').rstrip()
                x = e[8:11].decode('latin-1').rstrip()
                if e[12] & 0x08:
                    b = b.lower()
                if e[12] & 0x10:
                    x = x.lower()
                name = b + ('.' + x if x else '')
            out.append((name, o, lslots + [o]))
            lfn, lslots, want = {}, [], 0
        return out

    def find(self, cl, name):
        for n, o, s in self.entries(cl):
            if n.upper() == name.upper():
                return o, s
        return None, None

    def entcl(self, o):
        hi, lo = struct.unpack_from('<H', self.img, o + 20)[0], struct.unpack_from('<H', self.img, o + 26)[0]
        return hi << 16 | lo if self.bits == 32 else lo

    def walk(self, path):
        """path -> (directory cluster, last name)"""
        parts = [p for p in path.replace('\\', '/').split('/') if p and p != '.']
        cl = self.rootcl
        for p in parts[:-1]:
            o, _ = self.find(cl, p)
            if o is None or not self.img[o + 11] & 0x10:
                die('no such directory: %s' % p)
            cl = self.entcl(o) or self.rootcl
        return cl, (parts[-1] if parts else '')

    def add(self, cl, name, attr, first, size):
        if self.find(cl, name)[0] is not None:
            die('exists: %s' % name)
        base, _, ext = name.rpartition('.') if '.' in name[1:] else (name, '', '')
        def short(s, n):
            s = s.upper().replace(' ', '').replace('.', '')
            return bytes(c if c in SHORT_OK else ord('_') for c in s.encode('latin-1'))[:n]
        plain = (len(name) <= 12 and 1 <= len(base) <= 8 and len(ext) <= 3 and '.' not in base
                 and (not ext or ext) and short(base, 8) == base.upper().encode('latin-1')
                 and short(ext, 3) == ext.upper().encode('latin-1')
                 and (base == base.upper() or base == base.lower())
                 and (ext == ext.upper() or ext == ext.lower()))
        caseb = 0
        if plain:
            n11 = short(base, 8).ljust(8) + short(ext, 3).ljust(3)
            caseb = (0x08 if base != base.upper() else 0) | (0x10 if ext != ext.upper() else 0)
            lfn = []
        else:
            b, x = short(base, 8) or b'_', short(ext, 3)
            existing = {bytes(self.img[o:o + 11]) for o in self.slots(cl)
                        if self.img[o] not in (0, 0xE5) and self.img[o + 11] & 0x3F != 0x0F}
            k = 1
            while True:
                tail = b'~%d' % k
                n11 = (b[:8 - len(tail)] + tail).ljust(8) + x.ljust(3)
                if n11 not in existing:
                    break
                k += 1
            u = [ord(c) for c in name] + [0]
            u += [0xFFFF] * (-len(u) % 13)
            parts = [u[i:i + 13] for i in range(0, len(u), 13)]
            if len(name) % 13 == 0:
                parts = parts[:-1] if parts[-1] == [0] + [0xFFFF] * 12 else parts
            lfn = parts
        need = len(lfn) + 1
        slots = self.slots(cl)
        run = []
        for o in slots:
            if self.img[o] in (0, 0xE5):
                run.append(o)
                if len(run) == need:
                    break
            else:
                run = []
        while len(run) < need:
            if cl == 0:
                die('root directory full')
            last = self.chain(cl)[-1]
            c = self.alloc(last)
            o = self.off(self.clsec(c))
            for i in range(self.spc * SECTOR // 32):
                run.append(o + 32 * i)
                if len(run) == need:
                    break
        s = checksum(n11)
        for i, chars in enumerate(reversed(lfn)):
            seq = len(lfn) - i
            e = bytearray(32)
            e[0] = seq | (0x40 if i == 0 else 0)
            e[11], e[13] = 0x0F, s
            for p, ch in zip(LFN_OFFS, chars):
                struct.pack_into('<H', e, p, ch)
            self.img[run[i]:run[i] + 32] = e
        e = bytearray(32)
        e[0:11] = n11
        e[11], e[12] = attr, caseb
        struct.pack_into('<HHHHHHHI', e, 14, 0, 0x5B6D, 0x5B6D, first >> 16, 0, 0x5B6D, first & 0xFFFF, size)
        # (time 0, date 2025-11-13: a fixed stamp keeps test images reproducible)
        self.img[run[-1]:run[-1] + 32] = e
        return run[-1]

    def put(self, data, path):
        cl, name = self.walk(path)
        first, prev = 0, None
        per = self.spc * SECTOR
        for i in range(0, len(data), per):
            c = self.alloc(prev)
            first = first or c
            o = self.off(self.clsec(c))
            chunk = data[i:i + per]
            self.img[o:o + len(chunk)] = chunk
            prev = c
        self.add(cl, name, 0x20, first, len(data))

    def mkdir(self, path):
        cl, name = self.walk(path)
        c = self.alloc()
        o = self.off(self.clsec(c))
        dot = bytearray(32)
        dot[0:11], dot[11] = b'.          ', 0x10
        struct.pack_into('<H', dot, 26, c & 0xFFFF)
        struct.pack_into('<H', dot, 20, c >> 16)
        self.img[o:o + 32] = dot
        dot[1] = ord('.')
        p = 0 if cl == self.rootcl else cl
        struct.pack_into('<H', dot, 26, p & 0xFFFF)
        struct.pack_into('<H', dot, 20, p >> 16)
        self.img[o + 32:o + 64] = dot
        self.add(cl, name, 0x10, c, 0)

    def get_file(self, path):
        cl, name = self.walk(path)
        o, _ = self.find(cl, name)
        if o is None or self.img[o + 11] & 0x10:
            die('no such file: %s' % path)
        size = struct.unpack_from('<I', self.img, o + 28)[0]
        out = bytearray()
        for c in self.chain(self.entcl(o)):
            s = self.off(self.clsec(c))
            out += self.img[s:s + self.spc * SECTOR]
        return bytes(out[:size])

    def check(self):
        problems, owner = [], {}
        def visit(cl, where, depth):
            if depth > 32:
                problems.append('%s: too deep' % where)
                return
            for name, o, slots in self.entries(cl):
                p = where + '/' + name
                first = self.entcl(o)
                ch = self.chain(first) if first else []
                if first and (not ch or self.get(ch[-1]) != EOC):
                    problems.append('%s: chain does not end' % p)
                for c in ch:
                    if c in owner:
                        problems.append('%s: cluster %d also in %s' % (p, c, owner[c]))
                    owner[c] = p
                if self.img[o + 11] & 0x10:
                    sub = self.img[self.off(self.clsec(first)):][:64] if first else b''
                    if not first or sub[0:2] != b'. ' or sub[32:34] != b'..':
                        problems.append('%s: no . and ..' % p)
                    else:
                        par = struct.unpack_from('<H', sub, 58)[0] | (struct.unpack_from('<H', sub, 52)[0] << 16 if self.bits == 32 else 0)
                        want = 0 if cl == self.rootcl else cl
                        if par != want:
                            problems.append('%s: .. is %d, not %d' % (p, par, want))
                    visit(first, p, depth + 1)
                else:
                    size = struct.unpack_from('<I', self.img, o + 28)[0]
                    per = self.spc * SECTOR
                    if len(ch) != (size + per - 1) // per:
                        problems.append('%s: %d bytes in %d clusters' % (p, size, len(ch)))
            # long-name entries left without their short entry
            for o in self.slots(cl):
                if self.img[o] == 0:
                    break
        if self.bits == 32:
            for c in self.chain(self.rootcl):
                owner[c] = '/'
        visit(self.rootcl, '', 0)
        lost = [c for c in range(2, self.clusters + 2) if self.get(c) != 0 and c not in owner]
        if lost:
            problems.append('%d lost clusters (first %d)' % (len(lost), lost[0]))
        return problems


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    path, cmd, args = argv[1], argv[2], argv[3:]
    if cmd == 'format':
        if not args:
            die('format needs a size in KB')
        bits, part, label, rest = 12, False, None, list(args[1:])
        while rest:
            a = rest.pop(0)
            if a == '--part':
                part = True
            elif a == '--label':
                label = rest.pop(0)
            else:
                bits = int(a)
        fmt(path, int(args[0]), bits, part, label)
        return
    v = Volume(path)
    if cmd == 'ls':
        cl = v.rootcl
        if args and args[0].strip('/'):
            pcl, name = v.walk(args[0])
            o, _ = v.find(pcl, name)
            if o is None:
                die('no such directory')
            cl = v.entcl(o) or v.rootcl
        for name, o, _ in v.entries(cl):
            if v.img[o + 11] & 0x10:
                print('%-30s <dir>' % (name + '/'))
            else:
                print('%-30s %d' % (name, struct.unpack_from('<I', v.img, o + 28)[0]))
    elif cmd == 'put':
        v.put(open(args[0], 'rb').read(), args[1])
        v.save()
    elif cmd == 'mkdir':
        v.mkdir(args[0])
        v.save()
    elif cmd == 'get':
        data = v.get_file(args[0])
        if len(args) > 1:
            open(args[1], 'wb').write(data)
        else:
            sys.stdout.buffer.write(data)
    elif cmd == 'check':
        problems = v.check()
        for p in problems:
            print(p)
        print('FAT%d: %s' % (v.bits, 'ok' if not problems else '%d problems' % len(problems)))
        sys.exit(1 if problems else 0)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
