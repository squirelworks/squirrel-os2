# FAT drives (2.7)

Location: `../../kernel/fat.asm` (the file system), `../../kernel/volume.asm` (drive letters,
`mount`, `umount`, `cp`, `fattest`), both in the high kernel image.

Squirrel-OS/2 reads and writes FAT12, FAT16 and FAT32 volumes for exchanging files with other
systems: floppy and disk images, USB-stick-sized partitions, or an image file kept on the SQFS
data disk. SQFS stays the system's own file system; FAT volumes sit beside it on **drive letters**.

## Mounting

```
mount                      list the mounted drives
mount d: hd2               a disk: the whole disk, or its first FAT partition
mount e: "disk image.img"  an image file on the SQFS disk (a "loop" drive)
umount d:
```

- Disks: `hd2` and `hd3` (the secondary IDE channel: QEMU `-drive ...,index=2` and `index=3`,
  or `--target` in `tools/qemu_screen.py`) are registered as block devices the first time they are
  mounted. `hd0`, the boot disk, mounts read-only. `hd1` mounts only when it does not hold SQFS.
- A disk is a FAT volume when sector 0 is a FAT boot sector (512-byte sectors, a power-of-two
  cluster size, reserved sectors, one to four FATs, a sector count and a FAT size); otherwise the
  first partition table entry of type `01`, `04`, `06`, `0B`, `0C` or `0E` names it.
- The type follows from the number of data clusters, as the specification says: under 4085 is
  FAT12, under 65525 FAT16, otherwise FAT32.
- An image file stays open while it is mounted, so it cannot be deleted (`File is open`); writes
  stay inside its size, so the file never moves on the SQFS disk.
- Up to four drives. A letter or a disk can be mounted only once. `umount` refuses while a file on
  the drive is open.
- `mount` prints `D: FAT16, 15 MB, hd2` (and `, read-only`).

## Paths

A path that starts with a letter and `:` belongs to that drive: `d:/docs/Read me.txt`,
`d:\DOCS\READ ME.TXT`, `d:` (the root). `/` and `\` both separate parts, paths always start at the
drive's root, and `.` and `..` work. Names compare **without regard to case**, against the long
name and the short `NAME.EXT` alike.

The SQFS calls hand these paths to `fat.asm` (`fs_open`, `fs_create`, `fs_mkdir`, `fs_delete`,
`fs_rename`), and descriptors opened there (`FD_VOL` is set) go on to `fat_read`, `fat_write`,
`fat_seek` and `fat_close`. So the shell (`ls d:/docs`, `cat`, `put`, `mk`, `rm`, `mv`, `mkdir`),
the editors and programs through `SYS_OPEN`/`SYS_READ`/... work on FAT unchanged. The eight
descriptors are shared by both file systems. `cd` stays on SQFS, and `SYS_READDIR` lists only the
SQFS directory.

`cp <from> <to>` copies a file between any two places; when `<to>` is a directory (`d:`,
`d:/docs`, `/`) the file keeps its name. `mv` works inside one drive; from one drive to another
it says `Cannot move between drives` (`FE_XDEV`): copy, then remove.

## Long names

- **Reading:** long-name (VFAT) entries before a short entry belong to it when their sequence
  numbers run down to 1 and their checksum matches the short name; otherwise the short name is
  used. Characters outside Latin-1 show as `?`. The short entry's case bits (`0x08` name,
  `0x10` extension) give lower-case short names such as `readme.txt`.
- **Writing:** a name that is a plain 8.3 name in one case per part (`README.TXT`, `notes.txt`)
  gets only a short entry (with the case bits). Any other name gets long-name entries (13
  characters each, the last part first) and a short alias: the name's valid characters in upper
  case, cut to fit `~N`, with the extension's first three characters (`Read Me First.txt` →
  `README~1.TXT`); `N` is the first number no entry of the directory uses.
- Names are 1 to 63 characters without `\ / : * ? " < > |` or control characters.

## Writing

- Clusters are found first-fit from a moving hint. Every FAT copy is written; one FAT sector is
  cached and written back at the end of each call (`fat_flush`).
- A file grows by linking new clusters at the end of its chain; `O_TRUNC` frees the chain.
  After each write the short entry gets the first cluster, the size, the archive bit and the
  modification date and time from the CMOS clock.
- A directory in clusters grows by one zeroed cluster when no run of free entries is long enough;
  FAT12/16's fixed root cannot grow (`Disk full`). A new directory gets `.` and `..` (`..` is 0
  for the root, also on FAT32). Moving a directory updates its `..`; moving it below itself is
  refused (`FE_LOOP`).
- Deleting marks the short entry and its long-name entries `0xE5` and frees the chain; a
  directory must be empty.
- FAT32: the FSInfo free count and next-free hint are set to "unknown" on the first change, so
  other systems recount instead of trusting a stale number.

## Listing with long names

`fs_readdir_long` (`volume.asm`), and `SYS_READDIR` when bit 31 of the cursor in `ebx` is set:
`ecx` = a 72-byte buffer, `edx` = a directory path (`d:/docs`, `/notes`, `My Documents`) or 0 for
the current SQFS directory. The buffer gets the entry's whole name (64 bytes, zero-terminated),
its size (−1 for a directory) and flags (1 = directory); the call returns the next cursor (bit 31
set), 0 at the end, −1 when the directory does not exist. Without bit 31 the call is the 0.8
`SYS_READDIR` (16-byte names, aliases for long ones). Ring 3: the buffer and the path are checked
(`UA_READDIR`).

## Desktop objects

`kernel/fsobj.asm` adds two classes under the desktop's `DesktopObject` (`../apps/desktop.md`),
agreed with the desktop stream: it owns these classes, the desktop only sends them messages.

- **Drive**, fields `name`, `in` and `path` (`D:/`). `mount` writes `/desktop/drive-d.obj`
  (name `Drive D`) and the shredder if it is missing; `umount` removes the drive's file, and a boot
  removes drive files left from before (nothing is mounted after a reboot). `open` shows the drive
  in a window (`dk_textwin`): the entries with long names and sizes, arrows to choose, Enter opens
  a directory or shows a file, Backspace goes up, Esc closes. `drive d:` does the same on the text
  screen. Folder views and the File Manager list `path` with `fs_readdir_long`.
- **Shredder**, `/desktop/shredder.obj`. `drop`: `eax` = the shredder, `ebx` = the dropped object
  or 0, `ecx` = the path to delete (the object's file, or a file or empty directory from a folder
  view, on SQFS or a drive) -> `eax` = 0 when deleted (the desktop then forgets the object), −1
  when refused: a Drive or a Shredder is never shredded, and a path that cannot be deleted stays.
  `open` does nothing.
- The classes are recorded at mount, and at boot when `/desktop` exists, so they are known before
  the desktop loads its object files.
- `fsobjtest` checks the classes, a Drive's `path` through `obj_save`/`obj_load`, the inherited
  `name`, and the shredder deleting a file with a long name and refusing a Drive and a missing
  path. Regress: `fsobjtest`, `drive-obj`, `drive-obj-boot`, `drive-browse`, `drive-show`,
  `drive-up`.

## Tests

- `fattest x:` on a mounted, writable drive: a directory, a 9000-byte file with a long name written
  in two pieces and read back through the name in other letters and `\`, a seek, an append,
  a rename, a move into a subdirectory, 20 more long names in it (the directory grows), refusing to
  delete an open file and a full directory, deleting everything, and the same number of free
  clusters as before. Prints `fattest: PASS`.
- `tools/regress.sh` makes FAT12 (1.44 MB), FAT16 (in a partition) and FAT32 (in a partition)
  images with `tools/fatimg.py`, mounts them, reads files and long names written on the host, runs
  `fattest`, copies files both ways, mounts an image file from the SQFS disk, and afterwards runs
  `tools/fatimg.py IMAGE check` on every image (chains end, no cluster is in two chains or lost,
  sizes fit their chains, `..` entries point at their parents). The images were also checked with
  `fsck.fat -n` and `mtools` while this was written.

`tools/fatimg.py` is the host side: `format SIZE_KB [12|16|32] [--part]`, `ls`, `put`, `get`,
`mkdir`, `check`.

## Limitations

- 512-byte sectors only; no FAT12/16 volumes larger than their type allows, no exFAT.
- No access dates beyond the day, no attributes other than directory and archive are set; the
  read-only attribute is not enforced.
- No `cd` onto a drive (paths on a drive always start at its root).
- An image file on a FAT drive cannot itself be mounted.
- One FAT sector is cached for all drives; there is no other cache.
