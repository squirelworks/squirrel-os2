# UEFI loaders (OS2-HW, H.1)

| File | What |
|------|------|
| `bootx64.asm` | `\EFI\BOOT\BOOTX64.EFI`: PE32+ EFI application for 64-bit UEFI firmware |
| `bootia32.asm` | `\EFI\BOOT\BOOTIA32.EFI`: PE32 EFI application for 32-bit UEFI firmware |
| `handoff32.inc` | The 32-bit hand-off both share, after `ExitBootServices` |

Both are original NASM sources assembled as flat files: the PE headers are written out by
hand, the image is laid out on disk exactly as in memory, and the code is position-independent,
so no linker and no relocation table are needed. Each carries the whole `os.img` (boot sector,
low and high kernel images) inside, so the EFI system partition needs nothing else.

`tools/build.sh` builds `build/BOOTX64.EFI`, `build/BOOTIA32.EFI` and `build/uefi.img` (an
8 MB disk with an MBR and a FAT16 EFI system partition, made by `tools/mkesp.py`). Write
`uefi.img` to a USB stick, or copy the two `.EFI` files to `\EFI\BOOT\` on any ESP.
`tools/run.sh --uefi` starts it in QEMU. The design is in
`documentation/kernel/hardware.md`.
