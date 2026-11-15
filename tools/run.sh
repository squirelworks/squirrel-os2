#!/bin/sh
# Starts Squirrel-OS/2 in QEMU with the data disk (0.9.3).
#   tools/run.sh            boot from build/os.img
#   tools/run.sh --floppy   boot from build/floppy.img
#   tools/run.sh --uefi     boot build/uefi.img with 64-bit UEFI firmware (OVMF_FD,
#                           default /usr/share/ovmf/OVMF.fd; or a SquirrelBIOS
#                           x86_64-uefi .fd, which reads the ESP from virtio only)
# Run tools/build.sh first. Extra arguments go to QEMU (e.g. -m 16).
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build
boot="-drive format=raw,file=$out/os.img,index=0,media=disk"
if [ "$1" = "--floppy" ]; then
    boot="-drive format=raw,file=$out/floppy.img,if=floppy -boot a"
    shift
fi
qemu=qemu-system-i386
if [ "$1" = "--uefi" ]; then        # OS2-HW H.1
    boot="-bios ${OVMF_FD:-/usr/share/ovmf/OVMF.fd} -drive if=none,id=esp,format=raw,file=$out/uefi.img -device virtio-blk-pci,drive=esp"
    qemu=qemu-system-x86_64
    shift
fi
exec $qemu $boot \
    -drive format=raw,file="$out/data.img",index=1,media=disk "$@"
