# Block Device Driver (0.2.0)

Since 0.7.2 the two drives are also registered as the block devices `hd0` and `hd1` (`drivers.md`). SQFS and `SYS_BREAD`/`SYS_BWRITE` reach them through the device table, and a drive number other than 0 or 1 is now refused.

Location: `../../kernel/ata.asm` (included from `kernel/pm.asm`)

## Scope

- ATA PIO on the **primary channel** (`0x1F0–0x1F7`, control `0x3F6`), polled, no IRQs.
- LBA28, one 512-byte sector per call.
- Drive 0 = primary master = the boot disk holding the OS image.
- Drive 1 = primary slave = the **data disk**. All writes from programs go here.

## Kernel API

| Routine | In | Out |
|---------|----|-----|
| `ata_init` | — | Probes both drives with IDENTIFY, fills `ata_sectors[0..1]` |
| `ata_read` | `ebx` drive, `ecx` LBA, `edi` buffer | CF set on error |
| `ata_write` | `ebx` drive, `ecx` LBA, `esi` buffer | CF set on error; issues FLUSH CACHE |

Errors (CF set): drive absent, LBA ≥ drive size, controller ERR/DF, or a polling timeout.
An absent drive or an ATAPI device reports 0 sectors.

## Syscalls

| # | Name | Args | Returns |
|---|------|------|---------|
| 8 | `SYS_BREAD` | `ebx` LBA, `ecx` buffer, `edx` drive | 0 or -1 |
| 9 | `SYS_BWRITE` | `ebx` LBA, `ecx` buffer | 0 or -1 (always drive 1) |

## Shell commands

- `disk` — lists both drives with their size, or `none`.
- `blktest` — writes a pattern to the last sector of the data disk, clears the buffer,
  reads it back and compares. Prints `blktest: PASS` / `FAIL`, or explains that no data disk is attached.
- `systest` additionally reads drive 0 sector 0 via `SYS_BREAD` and checks the `0xAA55` boot
  signature, and checks that an out-of-range `SYS_BWRITE` returns -1.

## Running with a data disk

```bash
dd if=/dev/zero of=data.img bs=1M count=1
qemu-system-i386 -drive format=raw,file=os.img,index=0,media=disk \
                 -drive format=raw,file=data.img,index=1,media=disk
```

`tools/regress.sh` creates a fresh 1 MB data disk for each run.

## Limitations / next steps

- Single-sector, polled transfers; no DMA, no IRQ14, no secondary channel, no LBA48.
- virtio-blk is not implemented; QEMU's default IDE controller is enough for now.
- The file system (0.2.1) sits on drive 1.
