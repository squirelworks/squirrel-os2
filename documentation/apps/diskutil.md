# Disk Utility (A.5, 2.7)

`run diskutil` looks at the data disk (`hd1`) through the block device, without going through the file system, and never writes to it. It is a program on the data disk (`programs/diskutil.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`).

It shows:

- the disks: whether `hd0` (the boot disk) and `hd1` answer, and `hd1`'s SQFS size (`../kernel/filesystem.md`);
- how full `hd1` is (the sectors files keep, the superblock and directory included), the number of files and directories, and the bytes of data in the files;
- a map of the disk, one column for each stretch of sectors: blue for the superblock and directory, green for file data, light green for sectors a file keeps but does not use, white for free, red for sectors that a check or a scan found wrong;
- the six largest files, with their whole names.

### Other disks and FAT volumes (2.7)

`run diskutil hd2` (or `hd0` to `hd3`) looks at another disk the same way. `hd2` and `hd3`, the disks of the secondary IDE channel, become block devices the first time they are mounted (`../kernel/fat.md`), so `mount d: hd2` first. A disk that does not hold SQFS is looked at as a FAT volume, the same way `mount` finds one: a FAT boot sector in sector 0, otherwise the first partition table entry of type `01`, `04`, `06`, `0B`, `0C` or `0E`; FAT12, FAT16 or FAT32 by the number of clusters.

- The disk line reads `hd2: FAT16, 30720 sectors, 15360 KB`; the usage line counts clusters in use (`Used 3 of 30449 clusters (0%)`), then the files, directories and bytes as for SQFS.
- The first FAT is read into memory (up to 512 KB of it: any FAT12 or FAT16 volume, and FAT32 up to 128 K clusters; a larger one shows `The FAT is too large to check`). Every directory is walked from the root and every chain followed; the map shows the reserved sectors, the FATs, the fixed root and the directories in blue, file data in green, the rest of each file's last cluster in light green, and bad, lost or shared clusters in red. A map column stands for more than one sector when the volume is larger than 65536 sectors.
- The largest files are listed with their long (VFAT) names.
- The check (`C`) lists: a chain that leaves the disk, meets a bad or a free cluster, or shares clusters with another chain; a file whose size does not fit its chain; `.` or `..` pointing elsewhere; long-name entries that do not belong to the entry after them (wrong order or checksum); clusters in use that no file reaches (`12 clusters in use by no file (lost)`); a FAT copy that differs from the first; a first FAT entry that does not match the media byte. Problems are named by the file's whole name, cut to 15 characters.
- The surface scan reads the volume's sectors (from its partition's first sector).

The results agree with `fsck.fat -n` on images made with `mkfs.fat` and `mtools`, written by Squirrel-OS/2, and damaged on the host (a lost cluster, a FAT copy that differs).

### Long names (2.7)

SQFS keeps a name longer than its 15-character field in continuation entries (`../kernel/filesystem.md`): kind 2, directory `0xFF`, 23 characters each, with the checksum of the owner's name field, the owner's index and a sequence number; the owner's byte 30 counts them. The Disk Utility counts these entries as part of the directory, not as files, shows and compares the whole names (the largest files, the problems, the same name twice in a directory), and allows spaces in names. The check adds two problems: a part that no entry claims (its owner is gone, renamed by an older kernel, or its checksum or sequence number does not fit; the kernel frees such parts at the next mount), and an owner whose parts are not all there.

## Keys

`C` checks the file system: the superblock's version, and for each directory entry that its name is printable and not too long, its kind is a file or a directory, its directory exists, no other entry in the same directory has its name, its size fits the sectors it keeps, its sectors are inside the data area, and no other file uses them. The first three problems are listed under the map, each with the entry's name; files that share sectors turn red on the map. `S` scans the surface: it reads every sector of the disk, with a progress count, and reports how many could not be read (red on the map). Esc quits.

## Checks

`run diskutil test` writes a 1500-byte file, finds it in the directory with three sectors of data on the map, checks that the largest files are in order, that the disk passes the check and that the scan reads every sector. Then it damages its copy of the directory in memory: a second entry on the file's sectors with a size too large (three problems: two overlaps and the size), then a missing directory and a bad name (two problems). Then, in memory again, it gives the file a 41-character long name in two parts: the parts are not counted as files, the check finds no problems and the whole name reads back; a second entry with the same long name in the directory is one problem; and changing the file's name field so that the parts' checksum no longer fits gives three (two parts without their file, one incomplete long name). It deletes the file, checks that it has gone, and prints `diskutil: PASS`. The regress run also reads the window after `C` and after `S`.

`run diskutil test hd2` checks a FAT disk that `tools/regress.sh` makes with `tools/fatimg.py`: a directory `docs`, `README.TXT` (24 bytes) and `docs/A Long Document Name.txt` (14 bytes). It finds the volume, two files and one directory, no problems, `README.TXT` first among the largest files and the long name read. Then, in the FAT in memory only: a free cluster marked in use is one lost cluster, and the FAT copy now differs; one file's chain running on into the other's gives shared clusters and a size that does not fit; after reading the FAT again, the first file's cluster is green on the map. It prints `diskutil: PASS`.
