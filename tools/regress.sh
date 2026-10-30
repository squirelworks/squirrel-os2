#!/bin/sh
# Build the image and run scripted shell sessions in QEMU, checking the screen.
# Usage: tools/regress.sh   (needs nasm, qemu-system-i386, python3)
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/squirrel-os2-build
mkdir -p "$out"
(cd "$root/kernel" && nasm -f bin boot.asm -o "$out/boot.bin" \
    && nasm -f bin pm.asm -o "$out/pm.bin" 2>/dev/null)
cat "$out/boot.bin" "$out/pm.bin" > "$out/os.img"
rm -f "$out/data.img"
dd if=/dev/zero of="$out/data.img" bs=1024 count=1024 2>/dev/null

fail=0
disk=$out/data.img              # data disk attached as primary slave
check() {   # check NAME EXPECTED KEYS...
    name=$1; want=$2; shift 2
    if python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} "$out/os.img" "$@" | grep -qF -- "$want"; then
        echo "ok   $name"
    else
        echo "FAIL $name (expected: $want)"; fail=1
    fi
}

check systest      'systest: PASS'          systest '<ret>'
check getc-echo    'abz'                    keys '<ret>' abcd '<backspace>' '<backspace>' z '<ret>'
check ls-all       'help'                   ls '<ret>'
check cat          'Hello from Squirrel'    'cat edit' '<ret>'
check cmd-reuse    'systest: PASS'          'cat edit' '<ret>' systest '<ret>'
check calc-sub     'Result: 85'             'run calc' '<ret>' '100 - 15' '<ret>'
check calc-div     'Result: 21'             'run calc' '<ret>' '84 / 4' '<ret>'
check calc-div0    'division by zero'       'run calc' '<ret>' '9 / 0' '<ret>'
check app-exit     'systest: PASS'          'run vedit' '<ret>' hi '<esc>' systest '<ret>'
check shift-mul     'Result: 42'            'run calc' '<ret>' '6 * 7' '<ret>'
check shift-pct     'Result: 30'            'run calc' '<ret>' '200 % 15' '<ret>'
check calc-neg      'Result: -2'            'run calc' '<ret>' '7 - 9' '<ret>'
check calc-1prompt  'calc> 1'               'run calc' '<ret>' '1'
check cmd-bs        'systest: PASS'         systesx '<backspace>' t '<ret>'
check scroll        'systest: PASS'         ls '<ret>' ls '<ret>' ls '<ret>' systest '<ret>'
check exception     'CPU exception 6'       trap '<ret>'
check ps            '0        running'      ps '<ret>'
check proctest      'reaped pid 3 exit code 30'  proctest '<ret>'
check interleave    'worker 3 step 1'       proctest '<ret>'
check app-process   'Result: 42'            'run calc' '<ret>' '6 * 7' '<ret>' '<esc>' 'run calc' '<ret>' '6 * 7' '<ret>'
check slot-reuse    'exit code 30'          'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' \
                    'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' proctest '<ret>'
check disk-detect   'disk 1: 2048 sectors'  disk '<ret>'
check blktest       'blktest: PASS'         blktest '<ret>' blktest '<ret>'
disk=
check no-disk       'no data disk'          blktest '<ret>'
exit $fail
