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
for prog in hello wc elfhello; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
done
python3 "$root/tools/sqfs.py" "$out/progs.img" format 1024
for prog in hello wc elfhello; do python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/$prog"; done
printf 'one two\nthree\n' > "$out/notes"
python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/notes"
head -c 70000 /dev/zero | tr '\0' 'x' > "$out/huge"
python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/huge"
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

check fs-format     'formatted SQFS'        ls '<ret>'   # must run first: blank disk
check systest      'systest: PASS'          systest '<ret>'
check getc-echo    'abz'                    keys '<ret>' abcd '<backspace>' '<backspace>' z '<ret>'
check ls-all       'help'                   ls '<ret>'
check cat          'Hello from Squirrel'    'cat edit' '<ret>'
check cmd-reuse    'systest: PASS'          'cat edit' '<ret>' systest '<ret>'
check calc-sub     '= 85'             'run calc' '<ret>' '100 - 15' '<ret>'
check calc-div     '= 21'             'run calc' '<ret>' '84 / 4' '<ret>'
check calc-div0    'division by zero'       'run calc' '<ret>' '9 / 0' '<ret>'
check app-exit     'systest: PASS'          'run vedit' '<ret>' hi '<esc>' d systest '<ret>'
check shift-mul     '= 42'            'run calc' '<ret>' '6 * 7' '<ret>'
check shift-pct     '= 30'            'run calc' '<ret>' '200 % 15' '<ret>'
check calc-neg      '= -2'            'run calc' '<ret>' '7 - 9' '<ret>'
check calc-prec     '= 14'                  'run calc' '<ret>' '2 + 3 * 4' '<ret>'
check calc-paren    '= 20'                  'run calc' '<ret>' '(2 + 3) * 4' '<ret>'
check calc-chain    '= 21'                  'run calc' '<ret>' '(2 + 3) * 4' '<ret>' '+ 1' '<ret>'
check calc-ans      '= 40'                  'run calc' '<ret>' '20' '<ret>' 'ans * 2' '<ret>'
check calc-tax      '= 115'                 'run calc' '<ret>' '100 + 15%' '<ret>'
check calc-overflow 'Error: overflow'       'run calc' '<ret>' '99999 * 99999' '<ret>'
check calc-syntax   'syntax at column 5'    'run calc' '<ret>' '2 + * 3' '<ret>'
check calc-hist     '6 * 7 = 42'            'run calc' '<ret>' '6 * 7' '<ret>' hist '<ret>'
check calc-1prompt  'calc> 1'               'run calc' '<ret>' '1'
check cmd-bs        'systest: PASS'         systesx '<backspace>' t '<ret>'
check scroll        'systest: PASS'         ls '<ret>' ls '<ret>' ls '<ret>' systest '<ret>'
check exception     'CPU exception 6'       trap '<ret>'
check ps            '0        running'      ps '<ret>'
check proctest      'reaped pid 3 exit code 30'  proctest '<ret>'
check interleave    'worker 3 step 1'       proctest '<ret>'
check app-process   '= 42'            'run calc' '<ret>' '6 * 7' '<ret>' '<esc>' 'run calc' '<ret>' '6 * 7' '<ret>'
check slot-reuse    'exit code 30'          'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' \
                    'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' 'run sci' '<ret>' proctest '<ret>'
# file system: the first boot formats the blank data disk; later checks
# reuse the same disk, so the persist check reads what fs-put wrote
check fs-ls         'help'                  ls '<ret>'
check fstest        'fstest: PASS'          fstest '<ret>'
check fs-put        'ok'                    'put persist Saved across reboot!' '<ret>'
check fs-persist    'Saved across reboot!'  'cat persist' '<ret>'
check fs-mv         'renamed'               'mv persist renamed' '<ret>' ls '<ret>'
check fs-rm         'Not found'             'rm renamed' '<ret>' 'cat renamed' '<ret>'
check fs-dup        'error'                 'mk calc' '<ret>'
check fb-list       '[app]'                 'run files' '<ret>'
check fb-launch     '= 42'            'run files' '<ret>' '<ret>' '6 * 7' '<ret>'
check fb-view       'press any key'         'run files' '<ret>' '<down>' v
check fb-delete     'Not found'             'put junk x' '<ret>' 'run files' '<ret>' '<end>' d y '<esc>' 'cat junk' '<ret>'
check fb-exit       'systest: PASS'         'run files' '<ret>' '<esc>' systest '<ret>'
check ed-save       'Saved text'            'run edit memo1' '<ret>' 'Saved text' '<ctrl-s>' '<esc>' 'cat memo1' '<ret>'
check ed-reload     'Loaded.'               'run edit memo1' '<ret>'
check ed-move       'Hello editor!'         'run edit' '<ret>' 'Hello editor' '<ret>' 'two' '<up>' '<end>' '!'
check ed-vstatus    'L1 C4 off 3'           'run vedit' '<ret>' abc
check ed-vaction    "Deleted 'c'"           'run vedit' '<ret>' abc '<backspace>'
check ed-unsaved    'Unsaved changes'       'run edit' '<ret>' x '<esc>'
check ed-saveas     'memo2'                 'run edit' '<ret>' hi '<f2>' memo2 '<ret>' '<esc>' ls '<ret>'
check fb-edit       'Loaded.'               'run files' '<ret>' '<home>' e
check draw-exit     'systest: PASS'         'run draw' '<ret>' '<right>' '<spc>' '<esc>' d systest '<ret>'
check draw-unsaved  'Unsaved changes'       'run draw' '<ret>' '<spc>' '<esc>'
check draw-rect     '*ooo*'                 'run draw pic' '<ret>' r '<right>' '<right>' '<right>' '<right>' \
                    '<down>' '<down>' r '<left>' '<up>' b o f '<ctrl-s>' '<esc>' 'cat pic' '<ret>'
check draw-line     '**'                    'run draw diag' '<ret>' l '<right>' '<right>' '<right>' '<down>' l \
                    '<ctrl-s>' '<esc>' 'cat diag' '<ret>'
check draw-reload   'Loaded.'               'run draw pic' '<ret>'
check disk-detect   'disk 1: 2048 sectors'  disk '<ret>'
check blktest       'blktest: PASS'         blktest '<ret>' blktest '<ret>'
# program loader: a disk prepared on the host with tools/sqfs.py
disk=$out/progs.img
check ld-sqx        'Hello from a loaded program!'  'run hello' '<ret>'
check ld-arg        'Argument: world'       'run hello world' '<ret>'
check ld-wc         '2 3 14 notes'          'run wc notes' '<ret>'
check ld-elf        'Hello from an ELF program!'    'run elfhello' '<ret>'
check ld-notprog    'Not a program'         'run notes' '<ret>'
check ld-big        'too big'               'run huge' '<ret>'
check ld-missing    'Unknown command or program'    'run nothere' '<ret>'
check ld-again      'Argument: 2'           'run hello 1' '<ret>' 'run hello 2' '<ret>'
check ld-browser    'Hello from a loaded'   'run files' '<ret>' '<home>' '<ret>'
check ld-host-ls    'elfhello'              ls '<ret>'
disk=
check no-disk       'no data disk'          blktest '<ret>'
check rom-fallback  'Hello from Squirrel'   'cat edit' '<ret>'
exit $fail
