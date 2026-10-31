#!/usr/bin/env python3
"""Wraps a 1.44 MB floppy image in a bootable CD image (original code).

  tools/mkiso.py FLOPPY.img OUT.iso

The CD is ISO 9660 with an El Torito boot record in floppy emulation: the
BIOS boots the floppy image as drive 0, so the boot sector's floppy path
(CHS reads) loads the kernel as from a real floppy. The ISO file system
itself is empty (a root directory only). Installer step I.6.
"""
import struct
import sys

SECTOR = 2048
FLOPPY_SIZE = 1474560
PVD, BOOTREC, TERM, LPATH, MPATH, ROOT, CATALOG, IMAGE = 16, 17, 18, 19, 20, 21, 22, 23


def both16(n):
    return struct.pack('<H', n) + struct.pack('>H', n)


def both32(n):
    return struct.pack('<I', n) + struct.pack('>I', n)


def dir_record(extent, size, name):
    rec = bytes([34, 0]) + both32(extent) + both32(size) + bytes(7) + bytes([2, 0, 0])
    rec += both16(1) + bytes([1]) + name
    return rec


def pad(data):
    return data + bytes(-len(data) % SECTOR)


def make(floppy):
    if len(floppy) != FLOPPY_SIZE:
        sys.exit('mkiso: the floppy image must be %d bytes' % FLOPPY_SIZE)
    total = IMAGE + FLOPPY_SIZE // SECTOR
    root = dir_record(ROOT, SECTOR, b'\0') + dir_record(ROOT, SECTOR, b'\1')

    pvd = bytearray(SECTOR)
    pvd[0:7] = b'\1CD001\1'
    pvd[8:40] = b' ' * 32
    pvd[40:72] = b'SQUIRREL_OS2'.ljust(32)
    pvd[80:88] = both32(total)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(SECTOR)
    pvd[132:140] = both32(10)                   # path table: the root only
    pvd[140:144] = struct.pack('<I', LPATH)
    pvd[148:152] = struct.pack('>I', MPATH)
    pvd[156:190] = root[:34]
    pvd[190:813] = b' ' * (813 - 190)
    for off in (813, 830, 847, 864):            # dates: not specified
        pvd[off:off + 17] = b'0' * 16 + b'\0'
    pvd[881] = 1

    boot = bytearray(SECTOR)
    boot[0:7] = b'\0CD001\1'
    boot[7:39] = b'EL TORITO SPECIFICATION'.ljust(32, b'\0')
    boot[71:75] = struct.pack('<I', CATALOG)

    term = bytearray(SECTOR)
    term[0:7] = b'\xffCD001\1'

    lpath = bytes([1, 0]) + struct.pack('<I', ROOT) + struct.pack('<H', 1) + b'\0\0'
    mpath = bytes([1, 0]) + struct.pack('>I', ROOT) + struct.pack('>H', 1) + b'\0\0'

    valid = bytearray(32)
    valid[0] = 1                                # header, platform 0 (x86)
    valid[4:28] = b'Squirrel-OS/2'.ljust(24, b'\0')
    valid[30:32] = b'\x55\xaa'
    check = -sum(struct.unpack('<16H', bytes(valid))) & 0xFFFF
    valid[28:30] = struct.pack('<H', check)
    entry = bytearray(32)
    entry[0] = 0x88                             # bootable
    entry[1] = 2                                # 1.44 MB floppy emulation
    entry[6:8] = struct.pack('<H', 1)           # load one virtual sector
    entry[8:12] = struct.pack('<I', IMAGE)

    out = bytes(SECTOR * PVD) + bytes(pvd) + bytes(boot) + bytes(term)
    out += pad(lpath) + pad(mpath) + pad(root) + pad(bytes(valid) + bytes(entry))
    out += floppy
    assert len(out) == total * SECTOR
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], 'rb') as f:
        data = make(f.read())
    with open(sys.argv[2], 'wb') as f:
        f.write(data)


if __name__ == '__main__':
    main()
