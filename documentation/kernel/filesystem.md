# SQFS — On-disk File System (0.2.1 / 0.2.2, directories 0.8.0)

Location: `../../kernel/fs.asm` (included from `kernel/pm.asm`)

SQFS lives on the **data disk** (ATA drive 1, primary slave). The boot disk is never written.

Since installer step I.2 the file system reaches its disk through `fs_dev` instead of the fixed
`FS_DEV`. It is the data disk at all times, except while `install format` or `install ls` runs:
then it points at partition 1 of the installer's target (`dev_inst` in `kernel/install.asm`,
a block device whose sector 0 is the partition's first sector), and the data disk is loaded
again afterwards. Sector numbers inside SQFS stay relative to the start of its device, so a
partition holds the same layout as a whole data disk. `fs_format_empty` formats without
seeding the built-in files. On an installed system with no data disk (I.4), `fs_dev` is `dev_sys`,
partition 1 of the boot disk, from boot on.

## Disk layout

| LBA | Contents |
|-----|----------|
| 0 | Superblock |
| 1–4 | Directory: 64 entries × 32 bytes |
| 5 … total−1 | File data (contiguous extents) |
| last sector | Not part of the FS; reserved for `blktest` |

### Superblock

| Offset | Field | Value |
|--------|-------|-------|
| 0 | magic | `SQFS` (`0x53465153`) |
| 4 | version | 1 |
| 8 | total | Sectors the FS may use (disk size − 1) |
| 12 | dir LBA | 1 |
| 16 | dir sectors | 4 |
| 20 | data LBA | 5 |

### Directory entry (32 bytes)

| Offset | Field |
|--------|-------|
| 0 | Name, up to 15 characters, zero-padded (first byte 0 = free entry) |
| 16 | Start LBA of the extent |
| 20 | Size in bytes |
| 24 | Capacity in sectors (0 = no extent yet) |
| 28 | Parent directory id, byte (0.8.0; 0 = the root) |
| 29 | Kind, byte: 0 file, 1 directory (0.8.0) |
| 30 | Reserved |

The directory is cached in memory (`KSCRATCH+0x1000`) and written through on every change.

## Directories (0.8.0)

The 64-entry table stays as it is. A directory is just an entry of kind 1, with no extent; its id is its index in the table plus 1. Every entry records the id of the directory it is in. Disks written before 0.8.0 have zeros in those bytes, which means "a file in the root", so they mount unchanged.
Kernels older than 0.8.0 show directories as empty files and every file at the top level.

**Paths.** Every name the file system takes is a path:

- Parts are separated by `/`.
- A path starting with `/` begins at the root; otherwise it begins at the current directory (`fs_cwd`, shown in the prompt and by `pwd`).
- `.` and `..` work. The root is its own parent.
- `fs_walk` resolves all but the last part. `fs_lookup` then finds the last part in that directory.

**Rules:**

- **Opening:** a directory cannot be opened as a file.
- **Deleting:** a directory can be removed only when it is empty and is not the current directory.
- **Renaming:** `mv` can move an entry into another directory (`mv notes docs/notes`). When the new path names an existing directory, the entry moves into it under its own name (`mv notes docs`, `mv notes ..`; 0.9.2). It refuses to move a directory into itself or below itself.
- **Names:** `.` and `..` are refused as names.

**Shell and programs:**

- **Listings:** `ls`, `SYS_READDIR`, `run ls` and the file browser list the current directory. In a `SYS_READDIR` entry, a subdirectory's size reads as −1.
- **Programs:** the loader looks in the current directory first and then in the root. So `run hello` works from anywhere.
- **History:** the shell history is always `/shell.hist`.

## Allocation

Each file is one contiguous extent. Space is found first-fit by scanning the directory for
overlapping extents (no bitmap is needed). When a write needs more room than the extent has,
the file moves to a new extent of `max(needed, 2 × capacity)` sectors and its sectors are copied;
the old extent becomes free simply because no entry points at it.

## Mounting

At boot, after the drive probe:

- SQFS magic present → directory loaded, FS mounted.
- Sector 0 entirely zero (a blank disk) → formatted and seeded with the built-in files
  (`calc`, `sci`, `graph`, `matrix`, `diff`, `topo`, `edit`, `vedit`, `draw`, `help`).
- Anything else → left untouched; the shell says `Data disk is not SQFS; type format to erase it.`

Without a data disk, `ls` and `cat` fall back to the built-in (ROM) table, as before 0.2.1.

## Kernel API

| Routine | In | Out |
|---------|----|-----|
| `fs_create` | `esi` name | 0 / −1 (bad name, exists, directory full) |
| `fs_delete` | `esi` name | 0 / −1 (missing, or open) |
| `fs_rename` | `esi` old, `edi` new | 0 / −1 (missing, new exists, bad name) |
| `fs_open` | `esi` name, `ecx` flags | fd 0–7 / −1 |
| `fs_read` | `ebx` fd, `edi` buf, `ecx` len | bytes read (0 at EOF) / −1 |
| `fs_write` | `ebx` fd, `esi` buf, `ecx` len | bytes written / −1 (disk full) |
| `fs_close` | `ebx` fd | 0 / −1 |
| `fs_seek` | `ebx` fd, `ecx` offset (signed), `edx` whence | new position / −1 (1.0.2) |
| `fs_format` | — | CF on error |

On −1, `fs_errno` says why (0.9.2): `FE_NOFS`, `FE_NAME` (empty, over 15 characters, `.` or `..`),
`FE_EXISTS`, `FE_NODIR` (a directory on the path is missing), `FE_TABLE` (64 entries used),
`FE_NOTFOUND`, `FE_BUSY` (open), `FE_NOTEMPTY`, `FE_CWD` (the current directory), `FE_LOOP`
(a directory into itself), `FE_IO`, `FE_FULL` (no free run of sectors), `FE_ISDIR`, `FE_NOFD`
(all eight descriptors in use). The shell prints the matching message (`fs_report`/`fs_why`), and
the editors and `draw` show it on their message line. Syscalls return −1; since 1.0.3 a program
asks why with `SYS_FSERROR`, which returns the `FE_*` code and copies the same words the shell
prints (localized where the shell's are, as for `Not found`) into the program's buffer. The
reason is the system-wide `fs_errno`, so ask right after the failed call.

Open flags: `O_CREATE` 1, `O_TRUNC` 2, `O_APPEND` 4. Each descriptor has its own position,
starting at 0 (or at the end with `O_APPEND`). Eight descriptors are shared system-wide.

Seek (1.0.2): `fs_seek` moves a descriptor's position to `offset` from the start (`SEEK_SET` 0),
from the current position (`SEEK_CUR` 1), or from the end of the file (`SEEK_END` 2). The new
position must lie between 0 and the file size; anything else returns −1 and leaves the position
unchanged, so a file never gets a hole. Reads and writes then continue from there; a write in the
middle overwrites, and a write past the old end grows the file as before.

## Syscalls

| # | Name | Args | Returns |
|---|------|------|---------|
| 10 | `SYS_OPEN` | `ebx` name, `ecx` flags | fd / −1 |
| 11 | `SYS_READ` | `ebx` fd, `ecx` buf, `edx` len | bytes / −1 |
| 12 | `SYS_WRITE` | `ebx` fd, `ecx` buf, `edx` len | bytes / −1 |
| 13 | `SYS_CLOSE` | `ebx` fd | 0 / −1 |
| 14 | `SYS_CREATE` | `ebx` name | 0 / −1 |
| 15 | `SYS_DELETE` | `ebx` name | 0 / −1 |
| 16 | `SYS_RENAME` | `ebx` old, `ecx` new | 0 / −1 |
| 25 | `SYS_SEEK` | `ebx` fd, `ecx` offset, `edx` whence (0 set, 1 cur, 2 end) | position / −1 (1.0.2) |
| 26 | `SYS_FSERROR` | `ebx` buf, `ecx` buf size | `FE_*` code of the last failure; text in buf (1.0.3) |

## Shell

| Command | Effect |
|---------|--------|
| `ls` | Names and sizes |
| `cat <f>` | Print a file |
| `put <f> <text>` | Append `text` and a newline (creates the file) |
| `mk <f>` | Create an empty file |
| `rm <f>` | Delete |
| `mv <f> <new>` | Rename, or move to another directory (`mv a docs/a`, or `mv a docs` into it) |
| `mkdir <d>` | Make a directory (0.8.0) |
| `cd [d]` | Change the current directory; alone, back to the root (0.8.0) |
| `pwd` | Print the current directory (0.8.0) |
| `ls <d>` | List another directory (0.8.0) |
| `format` | Erase the data disk and reseed the built-in files |
| `fstest` | Create, write 1300 bytes in two pieces (forcing a move), reopen, read back and compare, check EOF, rename, delete |

Typed without its arguments, a command prints how to use it (`mkdir` → `Usage: mkdir <dir>`; 0.9.2).
Failures say why: `Already exists`, `Bad name: 1 to 15 characters, not . or ..`, `No such directory`,
`Directory not empty`, `Is a directory`, `Disk full`, and so on.

`run <app>` still starts the built-in applications; other names are loaded from files by the program loader (0.4.0, `loader.md`).

## Limitations

- 64 entries in all (files and directories together), 15-character names, paths up to 63 characters.
- Seeking is limited to positions inside the file (0 to its size); there are no sparse files.
- Write-through, no cache: every partial sector write is a read-modify-write.
- No journaling or fsck; a crash during a file move can leave the old extent referenced.
