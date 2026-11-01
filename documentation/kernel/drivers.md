# Device Drivers (0.7.x)

Location: `../../kernel/dev.asm` (registry and dispatch), `../../kernel/chardev.asm` (console and keyboard), `../../kernel/ata.asm` (disks).

## Model

Each device is a static **descriptor** owned by its driver. `dev_register` probes it and adds it to `dev_table` (up to 16). Code that wants a device finds it by name and calls it through the registry, never the driver directly.

| Offset | Field | Meaning |
|--------|-------|---------|
| 0 | name | Up to 7 characters, zero-padded to 8 |
| 8 | type | `DEV_CHAR` 1 or `DEV_BLOCK` 2 |
| 12 | probe | `ebx` = descriptor → CF if the device is absent |
| 16 | read | See below |
| 20 | write | See below |
| 24 | unit | The driver's own number (the ATA drive, …) |
| 28 | flags | `DEVF_UP` (set by the registry when the probe succeeds), `DEVF_RO` (programs may not write) |
| 32 | size | Block devices: sectors (set by the probe) |

Every operation gets `ebx` = the descriptor:

| Type | read | write |
|------|------|-------|
| Character | `edi` = buffer, `ecx` = count → `eax` = bytes, or −1 | `esi` = buffer, `ecx` = count → `eax` = bytes, or −1 |
| Block | `ecx` = sector, `edi` = 512-byte buffer → CF on error | `ecx` = sector, `esi` = buffer → CF on error |

An operation a device does not have points at `dev_fail` (−1).

## Kernel interface

| Routine | In | Out |
|---------|----|-----|
| `dev_init` | — | Registers the built-in devices (`dev_builtin`), after `ata_init` |
| `dev_register` | `esi` = descriptor | CF if the table is full |
| `dev_find` | `esi` = name | `ebx` = descriptor of a present device, or 0 |
| `dev_read`, `dev_write` | `ebx` = character device, as above | −1 if it is not a present character device |
| `dev_bread`, `dev_bwrite` | `ebx` = block device, as above | CF if it is not a present block device; all registers kept |

## Built-in devices

| Name | Type | Driver | Notes |
|------|------|--------|-------|
| `con` | char, write | `chardev.asm` (0.7.1) | Writes through `putc`, so redirection and pipes see it. `SYS_PUTS` uses it. |
| `kbd` | char, read | `chardev.asm` (0.7.1) | Blocking ASCII reads (Enter 10, Backspace 8, Esc 27). `SYS_GETC` uses it when input is not redirected. |
| `hd0` | block | `ata.asm` (0.7.2) | Primary master, the boot disk. Read-only for programs. |
| `hd1` | block | `ata.asm` (0.7.2) | Primary slave, the data disk. SQFS (`FS_DEV`) and `SYS_BREAD`/`SYS_BWRITE` use it. |

A missing disk stays in the table as `absent`, and every call on it fails.

## Syscalls

| # | Name | In | Out |
|---|------|----|-----|
| 22 | `SYS_DEVFIND` | `ebx` = name | Handle (table index), or −1 |
| 23 | `SYS_DEVREAD` | `ebx` = handle, `ecx` = buffer, `edx` = count (char) or sector (block) | Bytes read (512 for a sector), or −1 |
| 24 | `SYS_DEVWRITE` | Same | Bytes written, or −1 (also for `DEVF_RO` devices) |

`programs/devtest.asm` writes through `con`, reads the SQFS superblock from `hd1`, and checks that a write to `hd0` and an unknown name are refused.

## Shell

`devices` lists the table:

```
NAME    TYPE    STATUS
con     char    ready
kbd     char    ready
hd0     block   ready 193 sectors (read-only for programs)
hd1     block   ready 2048 sectors
```

## Devices at run time (1.9.12)

`SYS_DEVREG` (`ebx` = ASCIIZ name, 1–7 characters) registers a ready null character device under that name. Reads fill the buffer with zeros; writes discard the bytes and report success. Up to four such devices fit beside the built-ins. A name already in the table (present or absent) is refused. `programs/drvtest.asm` registers `null`, writes and reads it, and prints `drv: PASS` (checks `drv`, `drv-devices`).

## Not yet

- Interrupt-driven I/O. The ATA driver still polls.
- Loading driver *code* from a file (ops today are the kernel's null routines).
- A `/dev`-style namespace in the file system.
