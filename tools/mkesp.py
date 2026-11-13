#!/usr/bin/env python3
"""Make a UEFI-bootable disk image: an MBR with one EFI system partition
(type EFh) holding a FAT16 file system with \\EFI\\BOOT\\<files> (OS2-HW, H.1).

Usage: mkesp.py OUT.img FILE [FILE...]
Each FILE goes to \\EFI\\BOOT\\ under its own name in 8.3 upper case
(BOOTX64.EFI, BOOTIA32.EFI). Write the image to a USB stick, or give it
to QEMU with OVMF or SquirrelBIOS (x86_64-uefi). Original code, written
from the FAT and MBR on-disk formats.
"""
import os, struct, sys

SECTOR = 512
PART_LBA = 2048                 # 1 MiB, the usual alignment
PART_SECTORS = 14336            # 7 MiB: FAT16 with one sector per cluster
ROOT_ENTRIES = 512


def short_name(name):
    base, _, ext = os.path.basename(name).upper().partition('.')
    if not (0 < len(base) <= 8 and len(ext) <= 3):
        sys.exit(f'mkesp: {name} is not an 8.3 name')
    return base.ljust(8).encode() + ext.ljust(3).encode()


def dirent(name11, attr, cluster, size):
    # 11-byte name, attribute, reserved, times (2026-01-01 00:00), cluster, size
    date = ((2026 - 1980) << 9) | (1 << 5) | 1
    return struct.pack('<11sBBBHHHHHHHI', name11, attr, 0, 0, 0, date, date, 0, 0, date, cluster, size)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, files = sys.argv[1], sys.argv[2:]
    clusters = PART_SECTORS            # an upper bound for the FAT size
    spf = (2 * (clusters + 2) + SECTOR - 1) // SECTOR
    root_sectors = ROOT_ENTRIES * 32 // SECTOR
    data_start = 1 + 2 * spf + root_sectors
    count = PART_SECTORS - data_start
    assert 4085 <= count < 65525, 'not a FAT16 cluster count'
    fat = [0xFFF8, 0xFFFF] + [0] * count
    data = {}                          # cluster -> bytes

    def alloc(payload):
        need = max(1, (len(payload) + SECTOR - 1) // SECTOR)
        first = len(data) + 2
        for i in range(need):
            c = first + i
            fat[c] = c + 1 if i < need - 1 else 0xFFFF
            data[c] = payload[i * SECTOR:(i + 1) * SECTOR].ljust(SECTOR, b'\0')
        return first

    efi_c = alloc(b'')                 # \EFI, filled in below
    boot_c = alloc(b'')                # \EFI\BOOT
    entries = b''
    for f in files:
        blob = open(f, 'rb').read()
        entries += dirent(short_name(f), 0x20, alloc(blob), len(blob))
    data[efi_c] = (dirent(b'.          ', 0x10, efi_c, 0) + dirent(b'..         ', 0x10, 0, 0)
                   + dirent(b'BOOT       ', 0x10, boot_c, 0)).ljust(SECTOR, b'\0')
    boot = dirent(b'.          ', 0x10, boot_c, 0) + dirent(b'..         ', 0x10, efi_c, 0) + entries
    if len(boot) > SECTOR:
        sys.exit('mkesp: too many files')
    data[boot_c] = boot.ljust(SECTOR, b'\0')
    root = dirent(b'SQUIRRELEFI', 0x08, 0, 0) + dirent(b'EFI        ', 0x10, efi_c, 0)

    bpb = struct.pack('<3s8sHBHBHHBHHHIIBBBI11s8s', b'\xEB\x3C\x90', b'SQUIRREL', SECTOR, 1, 1, 2,
                      ROOT_ENTRIES, PART_SECTORS, 0xF8, spf, 32, 64, PART_LBA, 0,
                      0x80, 0, 0x29, 0x53514546, b'SQUIRRELEFI', b'FAT16   ')
    vbr = bpb.ljust(510, b'\0') + b'\x55\xAA'
    fat_bytes = struct.pack(f'<{len(fat)}H', *fat).ljust(spf * SECTOR, b'\0')
    part = bytearray(PART_SECTORS * SECTOR)
    part[0:SECTOR] = vbr
    part[SECTOR:SECTOR + spf * SECTOR] = fat_bytes
    part[SECTOR + spf * SECTOR:SECTOR + 2 * spf * SECTOR] = fat_bytes
    r = (1 + 2 * spf) * SECTOR
    part[r:r + len(root)] = root
    for c, blob in data.items():
        o = (data_start + c - 2) * SECTOR
        part[o:o + SECTOR] = blob

    # MBR: one partition, type EFh, LBA only (CHS fields saturated)
    entry = struct.pack('<B3sB3sII', 0, b'\xFE\xFF\xFF', 0xEF, b'\xFE\xFF\xFF', PART_LBA, PART_SECTORS)
    mbr = bytearray(SECTOR)
    mbr[446:462] = entry
    mbr[510:512] = b'\x55\xAA'
    with open(out, 'wb') as fh:
        fh.write(mbr)
        fh.write(b'\0' * (PART_LBA - 1) * SECTOR)
        fh.write(part)


if __name__ == '__main__':
    main()
