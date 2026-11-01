#!/bin/sh
# Builds a release into build/ (0.9.3):
#   os.img       boot sector + kernel, boot it as the first hard disk
#   floppy.img   the same on a 1.44 MB floppy image
#   cd.iso       a bootable CD image around floppy.img (installer I.6)
#   data.img     a 4 MB SQFS data disk with the sample programs (made only
#                if missing, so your files survive a rebuild; --fresh remakes it)
# Needs nasm and python3. Run it from anywhere.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/build
mkdir -p "$out"
python3 "$root/tools/mkstrings.py" --check
(cd "$root/kernel" && nasm -f bin boot.asm -o "$out/boot.bin" \
    && nasm -f bin pm.asm -o "$out/pm.bin")
cat "$out/boot.bin" "$out/pm.bin" > "$out/os.img"
dd if=/dev/zero of="$out/floppy.img" bs=1024 count=1440 2>/dev/null
dd if="$out/os.img" of="$out/floppy.img" conv=notrunc 2>/dev/null
python3 "$root/tools/mkiso.py" "$out/floppy.img" "$out/cd.iso"
if [ "$1" = "--fresh" ] || [ ! -f "$out/data.img" ]; then
    rm -f "$out/data.img"
    python3 "$root/tools/sqfs.py" "$out/data.img" format 4096 >/dev/null
    for src in "$root"/programs/*.asm; do
        name=$(basename "$src" .asm)
        nasm -f bin -i "$root/programs/" "$src" -o "$out/$name"
        python3 "$root/tools/sqfs.py" "$out/data.img" put "$out/$name" >/dev/null
        rm -f "$out/$name"
    done
    echo "data.img: new 4 MB data disk with the sample programs"
fi
rm -f "$out/boot.bin" "$out/pm.bin"
echo "built $out/os.img, $out/floppy.img and $out/cd.iso; run with tools/run.sh"
