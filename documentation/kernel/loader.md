# Program Loader (0.4.0 / 0.4.1)

Location: `../../kernel/loader.asm` (included from `kernel/pm.asm`)

The loader runs programs stored as files on the SQFS data disk. Before the loader, every app was
built into the kernel image; now `run <name>` falls back to the disk when `<name>` is not a
built-in app.

## Running a program

```
run <file> [argument text]
```

The shell looks up `<file>` in the built-in app table first. If it is not there, it calls
`SYS_EXEC`, waits for the program to exit, and prints a message if loading failed:

| Result | Message |
|--------|---------|
| −1 | `Unknown command or program` (no such file, or no data disk) |
| −2 | `Not a program (bad SQX/ELF header)` |
| −3 | `Program too big for the 64 KB program area` |
| −4 | `Another program is still running` |
| −5 | `Too many processes` |

In the file browser (`run files`), Enter on a program file runs it and then waits for a key
so its output stays visible. Enter on any other file still views it.

## Memory

| Range | Use |
|-------|-----|
| `0x30000–0x3FFFF` | Program area: the resident program's code, data and bss |
| `0x40000–0x4FFFF` | Staging buffer: the whole file is read here first |

Exactly one program is resident at a time. The loader remembers the last program's pid; a
new `exec` is refused while that process is alive (not free or zombie). Each program runs in an
ordinary process slot with that slot's 8 KB stack, so it is scheduled, waited on and reaped like
the built-in apps. Programs run in ring 0 like the rest of the system. There is no protection
yet (see 2.x).

## Formats

The first four bytes select the format.

### SQX (flat binary)

A flat image linked to run at `0x30000`, starting with a 16-byte header:

| Offset | Field |
|--------|-------|
| 0 | Magic `SQX1` |
| 4 | Entry address (absolute, must fall inside the file after the header) |
| 8 | Memory size: file plus bss, at most 64 KB, at least the file size |
| 12 | Reserved (0) |

The loader copies the file to `0x30000` and zeroes the remaining memory up to the memory size.
`programs/sqx.inc` provides the header macro and the syscall numbers.

### ELF32

A static `ET_EXEC` image for `EM_386`, little-endian, with 32-byte program headers. Every
`PT_LOAD` segment must lie entirely inside the program area; `p_filesz` bytes are copied from the
file and the rest of `p_memsz` reads as zero (the whole area is cleared first). Other segment
types are ignored. The entry point must be inside the area. There is no dynamic linking,
interpreter or relocation. `PT_INTERP` is ignored and such a program will not run correctly.

`kernel/loaders/elf_stub.asm` remains the separate design sketch for a Linux personality.
The native loader here takes no Linux ABI. Programs use the Squirrel-OS/2 `int 0x80` calls.

## Program ABI

- Entry: called as `main(arg)` with the cdecl convention: `[esp+4]` points to the argument text
  (the rest of the `run` line, up to 63 characters, empty string if none).
- Exit: return the exit code in `eax`, or call `SYS_EXIT`.
- I/O: the syscalls in `syscalls.md` (`SYS_PUTS`, `SYS_GETC`, file calls, …).
- `SYS_EXEC` (17): `ebx` = file name, `ecx` = argument string or 0 → pid, or a negative result
  from the table above. The caller waits with `SYS_WAIT`.

## Putting programs on the disk

`tools/sqfs.py` reads and writes SQFS images on the host:

```bash
nasm -f bin -i programs/ programs/hello.asm -o hello
python3 tools/sqfs.py data.img format 1024     # new 1 MB SQFS disk (erases it)
python3 tools/sqfs.py data.img put hello
python3 tools/sqfs.py data.img ls
python3 tools/sqfs.py data.img get notes       # copy a file out (to stdout)
```

Sample programs live in `programs/` (see its README): `hello`, `wc`, `ls`, `cat` (SQX) and
`elfhello` (a hand-written ELF32 image that also checks its bss is zeroed).

The loader was first numbered 0.3.0 and is 0.4.0 (flat) / 0.4.1 (ELF32) in the 0.4.x–0.8.x
laundry list. The list asked to hook `kernel/loaders/elf_stub.asm`; the native loader parses ELF
itself instead, because the stub targets the Linux ABI (see `kernel/loaders/README.md`).
