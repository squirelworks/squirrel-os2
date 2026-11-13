# Disk Utility (A.5)

`run diskutil` looks at the data disk (`hd1`) through the block device, without going through the file system, and never writes to it. It is a program on the data disk (`programs/diskutil.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`).

It shows:

- the disks: whether `hd0` (the boot disk) and `hd1` answer, and `hd1`'s SQFS size (`../kernel/filesystem.md`);
- how full `hd1` is (the sectors files keep, the superblock and directory included), the number of files and directories, and the bytes of data in the files;
- a map of the disk, one column for each stretch of sectors: blue for the superblock and directory, green for file data, light green for sectors a file keeps but does not use, white for free, red for sectors that a check or a scan found wrong;
- the six largest files.

## Keys

`C` checks the file system: the superblock's version, and for each directory entry that its name is printable and not too long, its kind is a file or a directory, its directory exists, no other entry in the same directory has its name, its size fits the sectors it keeps, its sectors are inside the data area, and no other file uses them. The first three problems are listed under the map, each with the entry's name; files that share sectors turn red on the map. `S` scans the surface: it reads every sector of the disk, with a progress count, and reports how many could not be read (red on the map). Esc quits.

## Checks

`run diskutil test` writes a 1500-byte file, finds it in the directory with three sectors of data on the map, checks that the largest files are in order, that the disk passes the check and that the scan reads every sector. Then it damages its copy of the directory in memory: a second entry on the file's sectors with a size too large (three problems: two overlaps and the size), then a missing directory and a bad name (two problems). It deletes the file, checks that it has gone, and prints `diskutil: PASS`. The regress run also reads the window after `C` and after `S`.
