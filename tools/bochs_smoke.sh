#!/bin/sh
# Boots the image in Bochs (a second emulator, with its own BIOS) and
# checks it works there too (0.9.3). Bochs has no way to type keys from
# a script, so autoexec.bat runs the commands and writes their output to
# files, which are read back from the disk image afterwards; a second
# boot checks the files persisted. Needs bochs, nasm, python3, script(1).
# Usage: tools/bochs_smoke.sh
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
work=${TMPDIR:-/tmp}/squirrel-bochs
rm -rf "$work"; mkdir -p "$work"; cd "$work"
sqfs() { python3 "$root/tools/sqfs.py" data.img "$@" >/dev/null; }
(cd "$root/kernel" && nasm -f bin boot.asm -o "$work/boot.bin" && nasm -f bin pm.asm -o "$work/pm.bin")
cat boot.bin pm.bin > hd.img
size() { truncate -s $(($2 * 16 * 63 * 512)) "$1"; }   # whole cylinders
size hd.img 10
sqfs format 1024
printf '2 + 3\n6 * 7\n' > exprs
printf 'systest > /r1\nmkdir docs\nput docs/n saved in bochs\nfstest > /r2\nproctest > /r3\nmemtest > /r4\nrun calc < exprs > /r5\n' > autoexec.bat
sqfs put exprs; sqfs put autoexec.bat
size data.img 20
cat > bochsrc <<CFG
megs: 64
romimage: file=/usr/share/bochs/BIOS-bochs-legacy
vgaromimage: file=/usr/share/bochs/VGABIOS-lgpl-latest
ata0-master: type=disk, path="hd.img", mode=flat, cylinders=10, heads=16, spt=63
ata0-slave: type=disk, path="data.img", mode=flat, cylinders=20, heads=16, spt=63
boot: disk
cpu: model=p4_willamette, ips=50000000
display_library: term
log: bochs.log
mouse: enabled=0
CFG
boot() {   # the Debian build stops in its debugger first: "c" continues
    rm -f hd.img.lock data.img.lock     # (left behind when it is stopped)
    (sleep 2; echo c; sleep "$1") | timeout $(($1 + 5)) script -qfc "bochs -q -f bochsrc" /dev/null >/dev/null 2>&1 || true
}
get() { python3 "$root/tools/sqfs.py" data.img get "$1" "$work/$1" >/dev/null 2>&1 && cat "$work/$1"; }
fail=0
expect() {  # expect FILE TEXT
    if get "$1" | grep -q "$2"; then echo "ok   bochs $2"; else echo "FAIL bochs $2"; fail=1; fi
}
boot 60
expect r1 'systest: PASS'
expect r2 'fstest: PASS'
expect r3 'exit code 30'
expect r4 'memtest: PASS'
expect r5 '= 42'
sqfs rm autoexec.bat
printf 'cat docs/n > /r6\n' > autoexec.bat
sqfs put autoexec.bat
size data.img 20
boot 50
expect r6 'saved in bochs'
exit $fail
