# Modern hardware drivers (OS2-HW, H.1–H.6)

Location: `../../kernel/drivers/`, `../../boot/uefi/`. Roadmap 2.8–2.9, boxes H.1–H.6 in `../../TODO.md`.

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
| `xhci.asm` | H.5: xHCI host controller, root-hub ports, device enumeration, rings and events |
| `usbkbd.asm` | H.5: USB boot keyboard into the `kbd` scan-code queue |
| `usbmsd.asm` | H.6: USB mass storage (bulk-only, SCSI) as `ud0` |
| `gopcon.asm` | H.2: the 80 x 25 text console drawn into a UEFI GOP framebuffer |
| `../../boot/uefi/` | H.1: `BOOTX64.EFI`, `BOOTIA32.EFI` and their shared hand-off |

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

## USB: xHCI, keyboard, mass storage

**Controller** (`xhci.asm`, PCI class 0C/03/30, registers in BAR0). `xhci_init` takes the
controller from the firmware (USB legacy support capability: OS-owned semaphore, SMIs off),
halts and resets it, and sets up: the device context base address array (with scratchpad
buffers if the controller asks for them), a command ring, one event ring segment of 256 TRBs
with its segment table, and interrupter 0 with interrupts off. Every ring is one page: 255
TRBs and a link TRB with toggle-cycle back to the start.

**Events.** `xhci_poll` drains the event ring and moves the dequeue pointer. It runs on every
timer interrupt (`hw_tick`), and the synchronous paths call it with interrupts off while they
wait. Command completions go to `xhci_cmd_*`, transfer events to the device record they belong
to (by slot), except the keyboard's interrupt endpoint, which goes straight to
`usbkbd_event`.

**Enumeration.** At boot every root-hub port with a device is reset (USB 2; USB 3 ports enable
themselves), then: Enable Slot, Address Device (EP0 packet size 8/64/512 by speed, then from the
device descriptor with Evaluate Context for full speed), the device and configuration
descriptors, and the first interface that is a boot keyboard (HID 3/1/1) or a bulk-only SCSI
mass-storage device (8/6/50h). `xhci_configure` sends SET_CONFIGURATION and Configure Endpoint
for its endpoints (interrupt IN, or bulk IN and OUT, each with its own ring). A bulk endpoint
that stalls is recovered with Reset Endpoint, Set TR Dequeue Pointer and
CLEAR_FEATURE(ENDPOINT_HALT). Up to four devices are kept; hubs are not supported yet, so a
device must be on a root port.

**Keyboard** (`usbkbd.asm`). SET_PROTOCOL(boot) and SET_IDLE(0), then one 8-byte interrupt IN
transfer is kept queued. Each report is compared with the previous one: changed modifier bits
and keys that appeared or went away become PC set-1 make and break codes (with `E0` for the
extended keys), pushed into `kbd_ring` and through `key_event` exactly as `kbd_isr` does for the
8042. The shell, `kbd`, `SYS_GETC` and `SYS_KEYEVENTS` need no change. Not yet: typematic
repeat, LEDs.

**Mass storage** (`usbmsd.asm`). TEST UNIT READY until LUN 0 is ready (REQUEST SENSE after each
failure, for the first unit attention), READ CAPACITY(10), and if the blocks are 512 bytes the
stick is registered as the block device `ud0`. Each sector is a command block wrapper on bulk
OUT, a 512-byte READ(10)/WRITE(10) data stage, and a command status wrapper on bulk IN whose
signature, tag and status are checked. One stick for now. A stick holding SQFS at sector 0
becomes the data disk on a machine without `hd1`, like `sd0`/`nv0`.

**Booting from a stick.** The BIOS reads the boot sector and both kernel images through int 13h
(SeaBIOS and SquirrelBIOS do this for USB on xHCI); the kernel then finds the stick as `ud0`.
`hw-usb-boot` boots that way on a `q35` machine with no IDE disk at all.

## UEFI boot (H.1)

`boot/uefi/bootx64.asm` and `bootia32.asm` are EFI applications that carry `os.img` inside and
start the kernel the way the BIOS path does, so the kernel needs almost nothing new:

1. Find the GOP (`LocateProtocol`), set its current mode again (some firmware only programs the
   adapter on `SetMode`) and note the framebuffer: base (must be below 4 GB), width, height,
   bytes per line, and pixel order (RGB or BGR; bit-mask and Blt-only modes are not used).
2. If the firmware loaded the loader or its stack where the kernel goes (below 640 KB or at
   1–2 MB; SquirrelBIOS 2.1.0 does), copy the whole loader to pages from `AllocatePages`
   below 4 GB, with a new stack, and go on there. The code is position-independent.
3. `GetMemoryMap`, check that nothing the firmware keeps after exit (runtime, ACPI, reserved,
   MMIO) is in `0x1000–0x9FFFF` or `0x100000–0x1FFFFF`, then `ExitBootServices` (with
   up to three tries if the map key went stale).
4. Long mode → 32-bit compatibility mode → protected mode with paging off, `EFER.LME` and
   `CR4` cleared (the 32-bit loader only turns paging off). From here `handoff32.inc`:
5. Find the kernel's hand-off header (`uefi_hdr` in `kernel/pm.asm`: signature `S2UE`, then the
   addresses of `pm`, `gdt_desc`, `ld_drive`, `e820_count`, `KERNEL_SIZE`, `KHIGH_BASE`), copy
   the low image to `0x8000` and the high image to `KHIGH_BASE`.
6. Turn the UEFI memory map into E820 entries in `E820_BUF` (loader, boot-services and free
   memory → usable; ACPI reclaim → 3; ACPI NVS → 4; unusable → 5; the rest → reserved;
   neighbours of one type merged, at most 32 entries) and set `e820_count`, `ld_drive` = 80h.
7. Put the interrupt hardware back the way a BIOS leaves it, since the kernel drives the 8259:
   local APIC LINT0 as ExtINT (virtual wire), LINT1 NMI, APIC timer masked, every I/O APIC
   entry masked; and the 8042 keyboard controller with scan-code translation and IRQ 1 on.
   (SquirrelBIOS 2.1.0 leaves LINT0 masked and translation off.)
8. Fill `UEFI_INFO` (`0x1300`, signature `S2EF`) with the framebuffer, load the kernel's GDT
   and far-jump to `08h:pm`.

`stage2` (the BIOS path) clears `UEFI_INFO`, so the kernel can tell the two apart.

## GOP text console (H.2)

On a UEFI boot the screen is a linear framebuffer, and a PC without a VGA has nothing at
`0xB8000`. `gopcon_init` (first in `hw_init`) maps the framebuffer and points the eight page
table entries of `0xB8000–0xBFFFF` at RAM (`GOP_SHADOW`, the last 32 KB of the high image's
megabyte). Every address space copies that page table, so `putc`, `cls`, the editors and every
other writer of the text screen keep working unchanged. `gopcon_tick` (every other timer tick)
compares the 80 × 25 cells with what it drew last and draws the cells that changed with the
5 × 7 font from `font.inc`: 8 × 16 pixel cells with the glyph at (1, 1) and its rows doubled
(6 × 8 cells on screens smaller than 640 × 400), zoomed by the largest whole number that still
fits (2 at 1280 × 800). The 16 text colours come from the attribute byte; the cursor is an
underline at `[cur]`; CP437 box-drawing characters are drawn as single lines and the block
characters solid. While a graphics program has the screen (`gfx_saved`) nothing is drawn.

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
| `hw-usb-kbd`, `hw-usb-kbd-edit`, `hw-usb-keyev` | `-device qemu-xhci -device usb-kbd` | typing (shift, punctuation, Up, Backspace) and `keyev`. QEMU sends typed keys only to the USB keyboard once it exists, so the 8042 path cannot make these pass |
| `hw-usb-devices`, `hw-usb-msd`, `hw-usb-msd-disk`, `hw-usb-after` | and `-device usb-storage` | `ud0` with 8192 sectors, `blkdev ud0`, sector 5 of the image |
| `hw-usb-boot` | `-M q35`, `usb-storage` with `bootindex=0` | boots from the stick: `hd0` absent, `ud0` present, data disk on AHCI |
| `uefi-x64`, `uefi-x64-mem` | `qemu-system-x86_64 -bios OVMF.fd`, ESP as the first disk | `BOOTX64.EFI` starts the kernel: banner, `systest`, the data disk (`ls`), the converted memory map |
| `uefi-x64-gop` | same | `<gop>` reads the text back off the framebuffer's pixels (`tools/qemu_screen.py`) |
| `uefi-ia32` | 32-bit OVMF (`OVMF32_CODE_4M.fd`, pflash) | `BOOTIA32.EFI`: `systest`, and the GOP screen |
| `uefi-squirrelbios` | SquirrelBIOS 2.1.0 `x86_64-uefi` (`SQUIRRELBIOS_FD`), ESP on virtio-blk | the same on our own firmware; three tries, because SquirrelBIOS 2.1.0 sometimes fails to read the 200 KB `BOOTX64.EFI` and falls back to its CSM |

The UEFI checks read the text screen from `GOP_SHADOW` (`QEMU_TEXT=0x1f8000`) and print `skip`
when the firmware files are not there (`OVMF_FD`, `OVMF32_CODE`, `OVMF32_VARS`; on Debian and
Ubuntu the `ovmf` and `ovmf-ia32` packages).

## Not yet

- Interrupts (MSI/INTx): everything polls.
- UEFI: graphics programs (VGA mode 13h, Bochs VBE) still program the VGA directly, so on a
  machine without one they do not work after a UEFI boot. Secure Boot signing of the loaders.
  A framebuffer above 4 GB or with a bit-mask pixel format gets no console.
- USB hubs, more than one stick, keyboard repeat and LEDs, USB mice, isochronous transfers.
- More than one sector per command, more than one AHCI controller, NVMe namespaces past 1.
- Disks above 2^32 sectors (2 TB) are capped at 2^32−1 sectors; BARs above 4 GB are skipped.
- Real-hardware checks: AHCI BIOS/OS hand-off (`BOHC`) and staggered spin-up are not done.
