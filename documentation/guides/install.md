# Installing Squirrel-OS/2 onto a disk

Status: **in progress**. Steps I.1 to I.5 are done: `run install` makes a target disk that boots on its own. I.6 (a CD image) is open in `TODO.md`.

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
| I.3-copy | Copy the kernel and the sample programs onto the target | done |
| I.4-bootable | Write the boot code into the target's MBR so the PC boots from it alone | done |
| I.5-ui | A text-mode `install` program that walks through I.1 to I.4, with a confirm step, localized | done |
| I.6-cd | Optional: a bootable CD image around `floppy.img` | open |

Each step ships in the next OS version, like any other release: I.1 and I.2 are in 1.7.2.

Assumptions: BIOS boot (Legacy/CSM), an IDE/ATA target disk reached through the polled
driver, SQFS as the installed file system. UEFI, AHCI/NVMe and USB mass storage stay in 2.x.

## Disk layout on the target

| Sectors | Contents | Written by |
|---------|----------|------------|
| 0 | MBR: boot code (from I.4; zero until then), disk signature at 440, partition table at 446, `55 AA` at 510 | I.1 (table), I.4 (code) |
| 1 to 192 | The 96 KB kernel image, where the boot sector loads it from | I.4 |
| 193 to 2047 | Unused | — |
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
kernel's first instructions (from `stage2` up to `gdt`, which nothing writes to), and the end
of its sector 0 (disk signature, partition table, `55 AA`) matches the boot sector that is still
in memory at `0x7C00`. The second test (since I.3) tells the boot disk from a target that
already holds a copy of the kernel: the target has its own signature and partition table. That also
covers a boot from floppy, where drive 0 may be an empty disk that can be installed to.
A drive that cannot be read is treated as the boot disk and never picked. The target must be
at least 2 MiB.

Programs cannot reach drives 2 and 3: they have no entry in the device table, so
`SYS_BREAD`/`SYS_BWRITE` refuse them.

These shell-command messages are English only, like `disk` and `blktest`. The `run install`
program of I.5 is the localized one.

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

## Step I.3: copying the system

`install copy` needs a target with an SQFS partition (I.2) and a mounted data disk, and finds
the boot disk as above (else: `The boot disk is not an IDE disk, so the kernel cannot be read
back.`). It asks y/n, then:

1. **The kernel.** Sectors 1 to 192 of the boot disk, the 96 KB image the boot sector loads, go
   to the same sectors of the target, each one read back and compared. They lie before the
   partition, in the first MiB.
2. **The files.** Every file in the root of the data disk is read into the loader's 64 KB
   staging buffer (`LD_STAGE`) and written to the root of the target's file system, replacing
   a file of the same name. These are the sample programs and anything else saved there;
   subdirectories are not copied, and a file over 64 KB is skipped. One line per file says
   `copied`, `failed` or `skipped`, then the count.

The file system is switched to the target only for each write, as in I.2.

## Step I.4: making it boot

`install boot` needs the kernel on the target (I.3; else `Type install copy first.`) and the
boot disk as an IDE disk. It asks y/n, then copies bytes 0 to 439 of the boot disk's sector 0
(the boot code; `boot.asm` refuses to assemble past byte 440) over the target's, keeps the
target's disk signature and partition table, marks partition 1 active (`80`), writes the
sector and reads it back. The boot code is the same one the release images use: it loads
sectors 1 to 192 and jumps to the kernel.

**Running from the installed disk.** At boot, when no data disk is attached at all,
`ins_mount_system` looks for the boot disk (found the same way as above) and, if its
partition 1 holds SQFS, makes that the file system through `dev_sys`, a second partition
device like `dev_inst`. The boot screen then says
`File system: partition 1 of the boot disk (an installed system).` and `ls`, `cat`, `run` and
the shell history use the partition. With a data disk attached, the data disk wins, as before.

The whole run, from a blank disk:

```
install part      (y)
install format    (y)
install copy      (y)
install boot      (y)
```

Then power off, remove the release disk, and boot the target.

## Step I.5: the install program

`run install` (also from a batch file: a line `run install`) is the installer for people. It
clears the screen and shows, in the current language (`lang`):

```
Squirrel-OS/2 Installer

Target disk: 2 (16 MiB)
Everything on the target disk will be erased.
Enter: install    Esc: cancel
```

Esc writes nothing (`Cancelled. Nothing was written.`). Enter runs the four steps without
asking again, one line each:

```
Partition table ... done
File system ... done
Copying the system ... done
Boot code ... done
Installed. Remove the release disk and restart the computer.
```

A step that fails stops the run (`The installation stopped. The target disk may be
incomplete.`). With no target, no IDE boot disk, or no data disk it says so and writes
nothing. The texts are the `inst_*` keys in `localization/*/strings.txt` (English, Latin,
Klingon). The step-by-step shell commands of I.1 to I.4 stay, in English, for testing and for
finer control; both share the same routines (`ins_do_part`, `ins_do_format`,
`ins_do_kernel`, `ins_do_files`, `ins_do_boot`).

## Trying it in QEMU

Always use a scratch image as the target, never a real disk:

```bash
tools/build.sh
dd if=/dev/zero of=build/target.img bs=1M count=16
qemu-system-i386 -drive format=raw,file=build/os.img,index=0,media=disk \
                 -drive format=raw,file=build/data.img,index=1,media=disk \
                 -drive format=raw,file=build/target.img,index=2,media=disk
```

Then type `run install` and press Enter (or go step by step with `install`, `install part`,
`install format`, `install copy` and `install boot`).
To boot the result alone: `qemu-system-i386 -drive format=raw,file=build/target.img,index=0,media=disk`. On the host, `fdisk -l build/target.img` shows the
new partition. `tools/regress.sh` does the same with a fresh 16 MiB image each run
(`tools/qemu_screen.py --target`) and reads the table back on the host.

## Limits so far

- One partition, the whole disk after the first MiB. No other partitions are kept.
- While `install format` or `install ls` runs, the file system is the target's. A program
  running in the background at that moment would see it too.
- LBA28 only: disks up to 128 GiB.
- A USB stick, CD or floppy that the BIOS booted from is not an ATA disk, so `install copy`
  cannot read the kernel back from it yet. The files come from the data disk, which is always
  an IDE disk.
