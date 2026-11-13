# Modern hardware drivers (OS2-HW, H.1–H.6)

Location: `../../kernel/drivers/`. Roadmap 2.8–2.9, boxes H.1–H.6 in `../../TODO.md`.

The 1.x/2.x drivers talk to the PC's ISA-era hardware: ATA PIO on ports `0x1F0`/`0x170`, the
8042 keyboard, VGA text mode. These drivers add the hardware that a PC built since about 2010
has instead. They are 32-bit, polled, and written so the 64-bit kernel (OS2-K, 2.8–2.9) can
take them over: no BIOS calls, no fixed physical addresses besides what the PCI bus reports,
DMA memory from `pg_alloc`.

| File | What |
|------|------|
| `hw.asm` | `hw_init` (boot, after `dev_init`), `hw_tick` (every timer interrupt), data-disk pick |
| `pci.asm` | PCI configuration access (mechanism #1), class search, memory BARs, `pci_enable`, `hw_udelay`, `hw_map_mmio` |
| `ahci.asm` | H.3: AHCI SATA disks as `sd0`, `sd1` |
| `nvme.asm` | H.4: NVMe namespace 1 as `nv0` |

## Start-up

`pm` calls `hw_init` right after `dev_init`, still with interrupts off and before the first
program's address space exists. Each driver looks for its controller by PCI class code
(`pci_find_class`), maps its registers with `hw_map_mmio` (identity, 4 MB pages in the kernel
page directory, which every address space copies when it is made), turns on memory decoding
and bus mastering, and calls `dev_register` for each disk it finds. Nothing is registered for
hardware that is not there, so `devices` on an older machine looks as before.

## Disks: `sd0`, `sd1`, `nv0`

They are ordinary block devices (`documentation/kernel/drivers.md`): 512-byte sectors, `DEV_SIZE`
in sectors, read and write through `dev_bread`/`dev_bwrite` and `SYS_DEVREAD`/`SYS_DEVWRITE`.
Programs may write them (unlike `hd0`).

- **AHCI** (`ahci.asm`, PCI class 01/06/01, registers in BAR5): `GHC.AE` on; every implemented
  port with a link (`SSTS.DET` = 3) and an ATA signature gets one page of DMA memory (command
  list, received-FIS area, one command table, a 512-byte bounce buffer), `IDENTIFY DEVICE` for its
  size (LBA48 words 100–103, else words 60–61), then `READ DMA EXT`/`WRITE DMA EXT` one sector
  at a time on command slot 0, polled on `PxCI` with a time-out. A task-file error restarts the
  port's command engine so the next command works. The first two disks found are `sd0`, `sd1`.
- **NVMe** (`nvme.asm`, PCI class 01/08/02, registers in BAR0): reset (`CC.EN` = 0), admin queues
  of 16 entries, `CC.EN` = 1, `IDENTIFY` namespace 1, then one I/O completion queue and one I/O
  submission queue (16 entries each, interrupts off). `READ`/`WRITE` of one block, polled on the
  completion queue's phase bit, command ID = submission slot. Namespaces formatted with blocks
  other than 512 bytes are not registered.

Both copy through a bounce buffer in their own DMA page: a caller's buffer may be in a
program's address space (the program area is not identity-mapped), and the copy costs nothing
next to the polling.

### The data disk on machines without IDE

The file system uses `hd1`, the ATA primary slave. A machine without IDE (QEMU `-M q35`, most
PCs since about 2010) boots from its AHCI or NVMe disk through the BIOS, and then has no `hd1`.
`hw_pick_data_disk` then gives the file system the first of `sd0`, `sd1`, `nv0` whose sector 0
holds an SQFS superblock. A blank disk is never picked, so nothing is formatted by surprise.
`format` and the installer still work only with `hd1`.

## Tests

`programs/blkdev.asm` (`run blkdev NAME`) reads sector 0 (`SQHW`) and sector 100 (`S100`) of a
disk made by `tools/regress.sh`, writes a pattern to sector 5, reads it back and prints
`blkdev: NAME PASS`. `tools/regress.sh` then checks on the host that the pattern really is in
sector 5 of the image file.

| Check | QEMU devices | What |
|-------|--------------|------|
| `hw-devices` | `-device ahci` + `ide-hd`, `-device nvme` | `devices` lists `sd0` and `nv0` with 8192 sectors |
| `hw-ahci`, `hw-ahci-disk` | same | `blkdev sd0`, and sector 5 of the image |
| `hw-nvme`, `hw-nvme-disk` | same | `blkdev nv0`, and sector 5 of the image |
| `hw-after` | same | the shell still works after both |
| `hw-absent`, `hw-missing` | none | no `sd0` in `devices`, `blkdev nv0` fails cleanly |
| `hw-q35` | `-M q35` | no IDE: `hd1` absent, the AHCI data disk `sd1` holds the file system (`ls`) |

## Not yet

- Interrupts (MSI/INTx): everything polls.
- More than one sector per command, more than one AHCI controller, NVMe namespaces past 1.
- Disks above 2^32 sectors (2 TB) are capped at 2^32−1 sectors; BARs above 4 GB are skipped.
- Real-hardware checks: AHCI BIOS/OS hand-off (`BOHC`) and staggered spin-up are not done.
