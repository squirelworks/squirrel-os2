#!/bin/sh
# Starts Squirrel-OS/2 in QEMU with the data disk (0.9.3).
#   tools/run.sh            boot from build/os.img
#   tools/run.sh --floppy   boot from build/floppy.img
# Run tools/build.sh first. Extra arguments go to QEMU (e.g. -m 16).
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build
boot="-drive format=raw,file=$out/os.img,index=0,media=disk"
if [ "$1" = "--floppy" ]; then
    boot="-drive format=raw,file=$out/floppy.img,if=floppy -boot a"
    shift
fi
exec qemu-system-i386 $boot \
    -drive format=raw,file="$out/data.img",index=1,media=disk "$@"
