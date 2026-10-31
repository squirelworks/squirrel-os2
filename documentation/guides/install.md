# Installing Squirrel-OS/2 onto a disk

Status: **in progress**. Steps I.1 and I.2 are done; I.3 to I.6 are open in `TODO.md`.

## Today

The release images are the install. Write `os.img` byte for byte to a USB stick or a disk
(or `floppy.img` to a floppy) and boot it on a PC with a legacy BIOS. The system then runs
from that medium, and the data disk is a second disk on the primary IDE channel.

## What the installer will do

The installer boots from that medium and copies the system onto the computer's own disk, so
the medium can be removed afterwards. Each step is one pull request:

| Step | What it does | State |
|------|--------------|-------|
| I.1-target | Find the target disk, refuse the boot and data disks, write an MBR with one partition | done |
| I.2-format | Format SQFS inside that partition (SQFS learns a starting LBA) | done |
| I.3-copy | Copy the kernel and the sample programs onto the target | open |
| I.4-bootable | Write the boot code into the target's MBR so the PC boots from it alone | open |
| I.5-ui | A text-mode `install` program that walks through I.1 to I.4, with a confirm step, localized | open |
| I.6-cd | Optional: a bootable CD image around `floppy.img` | open |

The steps do not move the OS version. They are named by their box.

Assumptions: BIOS boot (Legacy/CSM), an IDE/ATA target disk reached through the polled
driver, SQFS as the installed file system. UEFI, AHCI/NVMe and USB mass storage stay in 2.x.

## Disk layout on the target

| Sectors | Contents | Written by |
|---------|----------|------------|
| 0 | MBR: boot code (from I.4; zero until then), disk signature at 440, partition table at 446, `55 AA` at 510 | I.1 (table), I.4 (code) |
| 1 to 128 | The 64 KB kernel image, where the boot sector loads it from | I.4 |
| 129 to 2047 | Unused | — |
| 2048 to the end | Partition 1, type `7F`, SQFS | I.1 (entry), I.2 (file system) |

Partition 1 starts at 1 MiB, the usual alignment, and runs to the last sector of the disk.
Type `7F` is the MBR type set aside for alternative OS development, so other systems leave it
alone. The entry is not marked active until I.4 makes the disk bootable. The CHS fields use
255 heads and 63 sectors per track, and `FE FF FF` past cylinder 1023.

## Step I.1: the target disk

Since I.1 the ATA driver also probes the secondary IDE channel, so it sees four drives:

| Drive | Position | Role |
|-------|----------|------|
| 0 | primary master | boot disk |
| 1 | primary slave | data disk (the file system) |
| 2 | secondary master | possible target |
| 3 | secondary slave | possible target |

Two shell commands:

- `install` lists the four drives with their size and what is on them, then names the target.
- `install part` asks before it writes anything:

  ```
  Write a new partition table to disk 2: 32768 sectors (16 MiB)
  Everything on that disk is lost. Write it? (y/n)
  ```

  Only `y` writes. Any other key, Esc included, prints `Nothing was written.` After writing,
  the sector is read back and compared, and the partition entry is shown.

The target is the first drive that is present, is not drive 1, and is not the boot disk.
The boot disk is found by content, not by position: its sector 1 starts with the running
kernel's first instructions (from `stage2` up to `gdt`, which nothing writes to). That also
covers a boot from floppy, where drive 0 may be an empty disk that can be installed to.
A drive that cannot be read is treated as the boot disk and never picked. The target must be
at least 2 MiB.

Programs cannot reach drives 2 and 3: they have no entry in the device table, so
`SYS_BREAD`/`SYS_BWRITE` refuse them.

These installer messages are English only, like `disk` and `blktest`. The `install` program of I.5
is the localized one.

## Step I.2: the file system

- `install format` checks that the target's partition 1 is a type-`7F` partition that fits
  on the disk (else: `Type install part first.`), asks the same y/n question, and formats
  SQFS there with an empty root. The built-in files are not added.
- `install ls` lists the root of that file system and counts its entries, for example
  `0 entries in the root of partition 1.` Without SQFS there it says `Type install format.`

Both point the file system at the partition only while they run (`fs_dev`, see
`../kernel/filesystem.md`). The data disk is loaded again afterwards, with the same current
directory and open files, so the shell history and everything else stay on the data disk.
The partition's SQFS has the same layout as a data disk, so on the host
`dd if=target.img of=part.img bs=512 skip=2048` and `tools/sqfs.py part.img ls` read it.

## Trying it in QEMU

Always use a scratch image as the target, never a real disk:

```bash
tools/build.sh
dd if=/dev/zero of=build/target.img bs=1M count=16
qemu-system-i386 -drive format=raw,file=build/os.img,index=0,media=disk \
                 -drive format=raw,file=build/data.img,index=1,media=disk \
                 -drive format=raw,file=build/target.img,index=2,media=disk
```

Then type `install`, `install part` and `install format`, and after a reboot `install ls`. On the host, `fdisk -l build/target.img` shows the
new partition. `tools/regress.sh` does the same with a fresh 16 MiB image each run
(`tools/qemu_screen.py --target`) and reads the table back on the host.

## Limits so far

- One partition, the whole disk after the first MiB. No other partitions are kept.
- While `install format` or `install ls` runs, the file system is the target's. A program
  running in the background at that moment would see it too.
- LBA28 only: disks up to 128 GiB.
- A USB stick, CD or floppy that the BIOS booted from is not an ATA disk, so the kernel cannot
  read files back from it yet. I.3 decides where the copy comes from (the running kernel is
  already in memory; the sample programs are on the data disk).
