# SQFS — On-disk File System (0.2.1 / 0.2.2)

Location: `../../kernel/fs.asm` (included from `kernel/pm.asm`)

SQFS lives on the **data disk** (ATA drive 1, primary slave). The boot disk is never written.

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
| 28 | Reserved |

The directory is cached in memory (`KSCRATCH+0x1000`) and written through on every change.
The flat namespace is the "flat directory" option of milestone 0.2.1; subdirectories can be
added later by giving entries a type and a parent index in the reserved word.

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
| `fs_format` | — | CF on error |

Open flags: `O_CREATE` 1, `O_TRUNC` 2, `O_APPEND` 4. Each descriptor has its own position,
starting at 0 (or at the end with `O_APPEND`). Eight descriptors are shared system-wide.

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

## Shell

| Command | Effect |
|---------|--------|
| `ls` | Names and sizes |
| `cat <f>` | Print a file |
| `put <f> <text>` | Append `text` and a newline (creates the file) |
| `mk <f>` | Create an empty file |
| `rm <f>` | Delete |
| `mv <f> <new>` | Rename |
| `format` | Erase the data disk and reseed the built-in files |
| `fstest` | Create, write 1300 bytes in two pieces (forcing a move), reopen, read back and compare, check EOF, rename, delete |

`run <app>` still starts the built-in applications; loading programs from files is milestone 0.3.0.

## Limitations

- One flat directory, 64 files, 15-character names.
- No seek call yet; reads and writes are sequential per descriptor.
- Write-through, no cache: every partial sector write is a read-modify-write.
- No journaling or fsck; a crash during a file move can leave the old extent referenced.
