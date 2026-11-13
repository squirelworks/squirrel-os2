# Disk Utility (A.5)

`run diskutil` looks at the data disk (`hd1`) through the block device, without going through the file system, and never writes to it. It is a program on the data disk (`programs/diskutil.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`).

It shows:

- the disks: whether `hd0` (the boot disk) and `hd1` answer, and `hd1`'s SQFS size (`../kernel/filesystem.md`);
- how full `hd1` is (the sectors files keep, the superblock and directory included), the number of files and directories, and the bytes of data in the files;
- a map of the disk, one column for each stretch of sectors: blue for the superblock and directory, green for file data, light green for sectors a file keeps but does not use, white for free, red for sectors that a check or a scan found wrong;
- the six largest files, with their whole names.

### Long names (2.7)

SQFS keeps a name longer than its 15-character field in continuation entries (`../kernel/filesystem.md`): kind 2, directory `0xFF`, 23 characters each, with the checksum of the owner's name field, the owner's index and a sequence number; the owner's byte 30 counts them. The Disk Utility counts these entries as part of the directory, not as files, shows and compares the whole names (the largest files, the problems, the same name twice in a directory), and allows spaces in names. The check adds two problems: a part that no entry claims (its owner is gone, renamed by an older kernel, or its checksum or sequence number does not fit; the kernel frees such parts at the next mount), and an owner whose parts are not all there.

## Keys

`C` checks the file system: the superblock's version, and for each directory entry that its name is printable and not too long, its kind is a file or a directory, its directory exists, no other entry in the same directory has its name, its size fits the sectors it keeps, its sectors are inside the data area, and no other file uses them. The first three problems are listed under the map, each with the entry's name; files that share sectors turn red on the map. `S` scans the surface: it reads every sector of the disk, with a progress count, and reports how many could not be read (red on the map). Esc quits.

## Checks

`run diskutil test` writes a 1500-byte file, finds it in the directory with three sectors of data on the map, checks that the largest files are in order, that the disk passes the check and that the scan reads every sector. Then it damages its copy of the directory in memory: a second entry on the file's sectors with a size too large (three problems: two overlaps and the size), then a missing directory and a bad name (two problems). Then, in memory again, it gives the file a 41-character long name in two parts: the parts are not counted as files, the check finds no problems and the whole name reads back; a second entry with the same long name in the directory is one problem; and changing the file's name field so that the parts' checksum no longer fits gives three (two parts without their file, one incomplete long name). It deletes the file, checks that it has gone, and prints `diskutil: PASS`. The regress run also reads the window after `C` and after `S`.
