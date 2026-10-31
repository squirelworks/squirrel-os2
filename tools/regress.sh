#!/bin/sh
# Build the image and run scripted shell sessions in QEMU, checking the screen.
# Usage: tools/regress.sh   (needs nasm, qemu-system-i386, python3)
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/squirrel-os2-build
mkdir -p "$out"
python3 "$root/tools/mkstrings.py" --check || exit 1
python3 "$root/tools/mkfont.py" --check || exit 1
(cd "$root/kernel" && nasm -f bin boot.asm -o "$out/boot.bin" \
    && nasm -f bin pm.asm -o "$out/pm.bin" 2>/dev/null)
cat "$out/boot.bin" "$out/pm.bin" > "$out/os.img"
dd if=/dev/zero of="$out/floppy.img" bs=1024 count=1440 2>/dev/null
dd if="$out/os.img" of="$out/floppy.img" conv=notrunc 2>/dev/null
python3 "$root/tools/mkiso.py" "$out/floppy.img" "$out/cd.iso"    # installer I.6
for prog in hello wc elfhello ls cat nest crash heap devtest fpu seek errno zombie spin thread msg keyev waitcycle stackover; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
done
python3 "$root/tools/sqfs.py" "$out/progs.img" format 1024
for prog in hello wc elfhello ls cat nest crash heap devtest fpu seek errno zombie spin thread msg keyev waitcycle stackover; do python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/$prog"; done
printf 'one two\nthree\n' > "$out/notes"
python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/notes"
printf '2 + 3\n6 * 7\n' > "$out/exprs"
python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/exprs"
head -c 70000 /dev/zero | tr '\0' 'x' > "$out/huge"
python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/huge"
printf '# demo\necho start\n@echo quiet line\necho a b c | run wc > cnt\nrun cat cnt\nrun demo2.bat\necho never\n' > "$out/demo.bat"
printf 'echo in demo2\n' > "$out/demo2.bat"
for f in demo.bat demo2.bat; do python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/$f"; done
python3 "$root/tools/sqfs.py" "$out/auto.img" format 1024
printf 'echo autoexec ran\nlang la\n' > "$out/autoexec.bat"
python3 "$root/tools/sqfs.py" "$out/auto.img" put "$out/autoexec.bat"
python3 "$root/tools/sqfs.py" "$out/dkauto.img" format 1024    # 1.6.0: boot into the desktop
mkdir -p "$out/dk" && printf 'desktop\n' > "$out/dk/autoexec.bat"
python3 "$root/tools/sqfs.py" "$out/dkauto.img" put "$out/dk/autoexec.bat"
rm -f "$out/data.img"
dd if=/dev/zero of="$out/data.img" bs=1024 count=1024 2>/dev/null

fail=0
disk=$out/data.img              # data disk attached as primary slave
nl=$(printf '\n_'); nl=${nl%_}  # a newline, for expected text that spans two lines (POSIX sh has no $'\n')
check() {   # check NAME EXPECTED KEYS...
    name=$1; want=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${boot:-"$out/os.img"} "$@")
    case $screen in
        *"$want"*) echo "ok   $name" ;;
        *) echo "FAIL $name (expected: $want)"; fail=1 ;;
    esac
}
check_all() {   # check_all NAME 'WANT1|WANT2|...' KEYS...: every WANT must be on the screen
    name=$1; wants=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${boot:-"$out/os.img"} "$@")
    missing=
    oldifs=$IFS; IFS='|'
    for want in $wants; do
        case $screen in *"$want"*) ;; *) missing="$missing [$want]" ;; esac
    done
    IFS=$oldifs
    if [ -z "$missing" ]; then echo "ok   $name"; else echo "FAIL $name (missing:$missing)"; fail=1; fi
}
check_none() {   # check_none NAME UNWANTED SEEN KEYS...: UNWANTED must not be on the screen, SEEN must
    name=$1; unwanted=$2; seen=$3; shift 3
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${boot:-"$out/os.img"} "$@")
    case $screen in
        *"$unwanted"*) echo "FAIL $name (unexpected: $unwanted)"; fail=1 ;;
        *"$seen"*) echo "ok   $name" ;;
        *) echo "FAIL $name (expected: $seen)"; fail=1 ;;
    esac
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
check line-edit     'hello world'           'echo hllo' '<left>' '<left>' '<left>' e '<end>' ' world' '<ret>'
check line-delete   'systest: PASS'         'xsystest' '<home>' '<delete>' '<ret>'
check line-esc      'systest: PASS'         'junk' '<esc>' systest '<ret>'
check hist-up       'abZ'                   'echo abc' '<ret>' '<up>' '<backspace>' Z '<ret>'
check hist-draft    '> half'                'echo abc' '<ret>' half '<up>' '<down>'
check scroll        'systest: PASS'         ls '<ret>' ls '<ret>' ls '<ret>' systest '<ret>'
check exception     'CPU exception 6 (invalid opcode) in pid 0 (shell)'  trap '<ret>'
check crash-restart 'systest: PASS'         trap '<ret>' '<ret>' systest '<ret>'
# KB-17: a stack overflow is reported and ends only that process; the shell's own restarts
check_all stack-shell '*** stack overflow in pid 0 (shell)|systest: PASS'  overflow '<ret>' '<ret>' systest '<ret>'
check ps-name       '0        running  shell'  ps '<ret>'
check ps            '0        running'      ps '<ret>'
check proctest      'reaped pid 3 exit code 30'  proctest '<ret>'
check mem           'KB free'               mem '<ret>'
check mem-e820      'usable'                mem '<ret>'
check memtest       'memtest: PASS'         memtest '<ret>' memtest '<ret>'
check interleave    'worker 3 step 1'       proctest '<ret>'
check app-process   '= 42'            'run calc' '<ret>' '6 * 7' '<ret>' '<esc>' 'run calc' '<ret>' '6 * 7' '<ret>'
check slot-reuse    'exit code 30'          'run topo' '<ret>' 'run topo' '<ret>' 'run topo' '<ret>' 'run topo' '<ret>' \
                    'run topo' '<ret>' 'run topo' '<ret>' 'run topo' '<ret>' 'run topo' '<ret>' proctest '<ret>'
check sci-float     '= 0.3'                 'run sci' '<ret>' '0.1 + 0.2' '<ret>'
check sci-prec      '= 1024'                'run sci' '<ret>' '2 ^ 10' '<ret>'
check sci-sqrt      '= 1.414213562'         'run sci' '<ret>' 'sqrt(2)' '<ret>'
check sci-deg       '= 0.5'                 'run sci' '<ret>' deg '<ret>' 'sin(30)' '<ret>'
check sci-ln        '= 3'                   'run sci' '<ret>' 'ln(exp(3))' '<ret>'
check sci-exp       '= 1.204e24'            'run sci' '<ret>' '6.02e23 * 2' '<ret>'
check sci-negpow    '= -8'                  'run sci' '<ret>' '(-2) ^ 3' '<ret>'
check sci-domain    'outside the function'  'run sci' '<ret>' 'sqrt(-1)' '<ret>'
check sci-div0      'division by zero'      'run sci' '<ret>' '1 / 0' '<ret>'
check sci-exit      'systest: PASS'         'run sci' '<ret>' q '<ret>' systest '<ret>'
check sci-nox       'syntax at column 1'    'run sci' '<ret>' 'x + 1' '<ret>'
# 1.0.7: diff derivatives (central difference on the sci evaluator)
check diff-sin      "= 1${nl}diff>"           'run diff' '<ret>' 'd sin(x) at 0' '<ret>'
check diff-poly     "= 6${nl}diff>"           'run diff' '<ret>' 'd x^2 at 3' '<ret>'
check diff-exp      '= 2.718281829'         'run diff' '<ret>' 'd exp(x) at 1' '<ret>'
check diff-rad      "= 1${nl}diff>"           'run sci' '<ret>' deg '<ret>' q '<ret>' 'run diff' '<ret>' 'd sin(x) at 0' '<ret>'
check diff-domain   'outside the function'  'run diff' '<ret>' 'd ln(x) at 0' '<ret>'
check diff-noat     'syntax at column 9'    'run diff' '<ret>' 'd sin(x)' '<ret>'
# 1.0.8: diff integrals (composite Simpson)
check diff-int1     "= 2${nl}diff>"           'run diff' '<ret>' 'i 1 from 0 to 2' '<ret>'
check diff-intsin   "= 2${nl}diff>"           'run diff' '<ret>' 'i sin(x) from 0 to pi' '<ret>'
check diff-intexp   '= 1.718281828'         'run diff' '<ret>' 'i exp(x) from 0 to 1' '<ret>'
check diff-intrev   "= -2${nl}diff>"          'run diff' '<ret>' 'i x from 2 to 0' '<ret>'
check diff-noto     'syntax at column 11'   'run diff' '<ret>' 'i x from 1' '<ret>'
# 1.0.10: diff ODE stepper (Euler)
check diff-euler1   "= 1.1${nl}diff>"         'run diff' '<ret>' 'euler y from 0 to 0.1 y0 1 step 0.1' '<ret>'
check diff-euler    '= 2.716923932'         'run diff' '<ret>' 'euler y from 0 to 1 y0 1 step 0.001' '<ret>'
check diff-eulerxy  "= 1.25${nl}diff>"        'run diff' '<ret>' 'euler x*y from 0 to 1 y0 1 step 0.5' '<ret>'
check diff-eulerh   'step must be greater'  'run diff' '<ret>' 'euler y from 0 to 1 y0 1 step 0' '<ret>'
check diff-noy      'syntax at column 3'    'run diff' '<ret>' 'i y from 0 to 1' '<ret>'
check diff-exit     'systest: PASS'         'run diff' '<ret>' q '<ret>' systest '<ret>'
check mx-mul        '43           50'       'run matrix' '<ret>' 'A = [1 2; 3 4]' '<ret>' 'A * [5 6; 7 8]' '<ret>'
check mx-det        'ans = 24'              'run matrix' '<ret>' 'det [2 0 0; 0 3 0; 0 0 4]' '<ret>'
check mx-inv        '1.5         -0.5'      'run matrix' '<ret>' 'inv [1 2; 3 4]' '<ret>'
check mx-scale      '-1.5           -2'     'run matrix' '<ret>' 'X = -[1 2; 3 4] * 0.5' '<ret>'
check mx-mismatch   'sizes do not match'    'run matrix' '<ret>' '[1 2] + [1; 2]' '<ret>'
check mx-singular   'matrix is singular'    'run matrix' '<ret>' 'inv [1 2; 2 4]' '<ret>'
# file system: the first boot formats the blank data disk; later checks
# reuse the same disk, so the persist check reads what fs-put wrote
check fs-ls         'help'                  ls '<ret>'
check fstest        'fstest: PASS'          fstest '<ret>'
check fs-put        'ok'                    'put persist Saved across reboot!' '<ret>'
check fs-persist    'Saved across reboot!'  'cat persist' '<ret>'
check hist-file     'put persist Saved'     'cat shell.hist' '<ret>'
check hist-reboot   '> cat shell.hist'      '<up>'
check fs-mv         'renamed'               'mv persist renamed' '<ret>' ls '<ret>'
check fs-rm         'Not found'             'rm renamed' '<ret>' 'cat renamed' '<ret>'
check fs-dup        'Already exists'        'mk calc' '<ret>'
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
# 1.0.9: Ctrl+F finds text, F3 finds it again (wrapping to the start)
check ed-find       'Found zebra at line 1, column 9'  'put zfind one two zebra' '<ret>' 'run edit zfind' '<ret>' '<ctrl-f>' zebra '<ret>'
check ed-find-at    'one two Xzebra'        'run edit zfind' '<ret>' '<ctrl-f>' zebra '<ret>' X
check ed-find-again 'Found ab at line 2, column 1'  'run edit' '<ret>' 'ab ab' '<ret>' ab '<ctrl-f>' ab '<ret>' '<f3>' '<f3>'
check ed-find-space 'Found b a at line 1'   'run vedit' '<ret>' 'ab ab' '<ctrl-f>' 'b a' '<ret>'
check ed-find-none  'Not found: zz'         'run edit' '<ret>' abc '<ctrl-f>' zz '<ret>'
# 1.0.11: one-level undo (Ctrl+Z)
check_all ed-undo   "ab${nl}~|Undone."          'run edit' '<ret>' abc '<ctrl-z>'
check_all ed-undo-once "ab${nl}~|Nothing to undo." 'run edit' '<ret>' abc '<ctrl-z>' '<ctrl-z>'
check_all ed-undo-bs "abc${nl}~|Undone."        'run edit' '<ret>' abc '<backspace>' '<ctrl-z>'
check_all ed-undo-tab 'L1 C3 off 2|Undone.' 'run vedit' '<ret>' ab '<tab>' '<ctrl-z>'
check ed-undo-save  'Unsaved changes'       'run edit memo3' '<ret>' x '<ctrl-s>' '<ctrl-z>' '<esc>'
check ed-undo-mem   '129912 KB free'        'run edit' '<ret>' x '<ctrl-z>' '<esc>' mem '<ret>'
# 1.0.12: vedit Ctrl+T shows control characters; the buffer stays the same
check_all ved-ctl   "    1 ab\$${nl}|5/16384|Control characters shown" 'run vedit' '<ret>' ab '<ret>' cd '<ctrl-t>'
check_all ved-ctl-off "    1 ab${nl}|Control characters hidden" 'run vedit' '<ret>' ab '<ret>' cd '<ctrl-t>' '<ctrl-t>'
check ved-ctl-edit  'New buffer.'           'run edit' '<ret>' ab '<ctrl-t>'
# with the view scrolled past a short line's end, its '$' is not drawn
check_all ved-ctl-hs "    1${nl}    2 xxxx|L2 C81" 'run vedit' '<ret>' ab '<ret>' xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx '<ctrl-t>'
check fb-edit       'Loaded.'               'run files' '<ret>' '<home>' e
# 0.9.0: the browser starts each 1.0 app and gets it back when it quits
d6="<down> <down> <down> <down> <down> <down>"
check fb-run-edit   '> edit'                'run files' '<ret>' $d6 '<ret>' hi '<esc>' d
check fb-run-vedit  '> vedit'               'run files' '<ret>' $d6 '<down>' '<ret>' hi '<esc>' d
check fb-run-draw   '> draw'                'run files' '<ret>' $d6 '<down>' '<down>' '<ret>' '<spc>' '<esc>' d
check fb-run-calc   '> calc'                'run files' '<ret>' '<ret>' '6 * 7' '<ret>' '<esc>'
check fb-run-back   'systest: PASS'         'run files' '<ret>' $d6 '<down>' '<down>' '<ret>' '<esc>' '<esc>' systest '<ret>'
# 1.0: every 1.0 app in one boot. The last three commands only run if calc, edit,
# draw and files all gave the keyboard back; calc.hist proves calc evaluated 2 + 2,
# walk.txt proves edit saved, and systest proves the shell still works.
check_all walk-1.0  '2 + 2 = 4|walk-ok|systest: PASS' \
                    'rm /calc.hist' '<ret>' 'run calc' '<ret>' '2 + 2' '<ret>' '<esc>' \
                    'run edit walk.txt' '<ret>' 'walk-ok' '<ctrl-s>' '<esc>' \
                    'run draw' '<ret>' '<esc>' 'run files' '<ret>' '<esc>' \
                    'cat /calc.hist' '<ret>' 'cat walk.txt' '<ret>' systest '<ret>'
# 0.9.1: what one boot writes, the next boot sees (each check is a fresh boot)
check persist-w     'ok'                    'mkdir keep' '<ret>' 'put keep/note kept' '<ret>'
check persist-r     'kept'                  'cat keep/note' '<ret>'
check persist-fb    'memo1'                 'run files' '<ret>'
check persist-cd    'note'                  'cd keep' '<ret>' ls '<ret>'
check draw-exit     'systest: PASS'         'run draw' '<ret>' '<right>' '<spc>' '<esc>' d systest '<ret>'
check draw-unsaved  'Unsaved changes'       'run draw' '<ret>' '<spc>' '<esc>'
check draw-rect     '*ooo*'                 'run draw pic' '<ret>' r '<right>' '<right>' '<right>' '<right>' \
                    '<down>' '<down>' r '<left>' '<up>' b o f '<ctrl-s>' '<esc>' 'cat pic' '<ret>'
check draw-line     '**'                    'run draw diag' '<ret>' l '<right>' '<right>' '<right>' '<down>' l \
                    '<ctrl-s>' '<esc>' 'cat diag' '<ret>'
check draw-reload   'Loaded.'               'run draw pic' '<ret>'
check disk-detect   'disk 1: 2048 sectors'  disk '<ret>'
check blktest       'blktest: PASS'         blktest '<ret>' blktest '<ret>'
# installer I.1: a blank 16 MiB scratch image as secondary master is the
# target; the boot disk and the data disk are never picked. The tests only
# ever write to that scratch file.
target=$out/target.img
rm -f "$target"
dd if=/dev/zero of="$target" bs=1024 count=16384 2>/dev/null
mbr() {     # mbr NAME 'blank' | 'TYPE START SIZE': read sector 0 of the target on the host
    got=$(python3 -c 'import struct, sys
d = open(sys.argv[1], "rb").read(512)
if not any(d): print("blank")
elif d[510:] != b"\x55\xaa": print("no signature")
else: print("%02X %d %d" % ((d[450],) + struct.unpack("<II", d[454:462])))' "$target")
    if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected: $2, got: $got)"; fail=1; fi
}
check_all install-list 'disk 0: 193 sectors (0 MiB)  boot disk, not touched|disk 1: 2048 sectors (1 MiB)  data disk, not touched|disk 2: 32768 sectors (16 MiB)  blank|Target: disk 2.' \
                    install '<ret>'
check install-esc   'Nothing was written.'  'install part' '<ret>' '<esc>'
mbr   install-esc-blank 'blank'
check install-fmt-nopart 'Type install part first.'  'install format' '<ret>'
check install-part  'Partition 1: type 7F, start 2048, 30720 sectors (15 MiB)'  'install part' '<ret>' y
mbr   install-mbr   '7F 2048 30720'
check install-again 'has a Squirrel-OS/2 partition'  install '<ret>'
# installer I.2: SQFS with an empty root inside partition 1
part() {    # part NAME 'blank' | 'SQFS[LISTING]': partition 1's first sector and its sqfs.py listing, on the host
    dd if="$target" of="$out/part.img" bs=512 skip=2048 2>/dev/null
    if [ -z "$(head -c 512 "$out/part.img" | tr -d '\0')" ]; then got=blank
    else got="$(head -c 4 "$out/part.img")[$(python3 "$root/tools/sqfs.py" "$out/part.img" ls 2>&1 || true)]"; fi
    if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected: $2, got: $got)"; fail=1; fi
}
check install-ls-nofs 'Partition 1 has no SQFS.'  'install ls' '<ret>'
check install-fmt-esc 'Nothing was written.'  'install format' '<ret>' '<esc>'
part  install-fmt-esc-blank 'blank'
check install-format 'Formatted SQFS with an empty root.'  'install format' '<ret>' y
part  install-sqfs  'SQFS[]'
check install-ls    '0 entries in the root of partition 1.'  'install ls' '<ret>'   # a new boot: it is on the disk
check_all install-back 'help|memo1'        'install ls' '<ret>' ls '<ret>'   # the data disk is the file system again
# installer I.3: the kernel to sectors 1 to 192 of the target, the data disk's root files into its SQFS
check install-mkfile 'ok'                 'put instfile copied-ok' '<ret>'   # a file for the installed system to show
check install-boot-nokernel 'Type install copy first.'  'install boot' '<ret>'
check install-copy-esc 'Nothing was written.'  'install copy' '<ret>' '<esc>'
copied() {  # copied NAME WANT: on the host, 'none' (sector 1 still blank) or 'same' (kernel and files match)
    got=$(python3 -c 'import subprocess, sys
tgt, osimg, data, sq = sys.argv[1:5]
t = open(tgt, "rb").read()
if not any(t[512:1024]): print("none"); sys.exit()
o = open(osimg, "rb").read()
if t[512:512 * 193] != o[512:512 * 193]: print("kernel differs"); sys.exit()
open(tgt + ".part", "wb").write(t[2048 * 512:])
ls = lambda img: subprocess.run(["python3", sq, img, "ls"], capture_output=True, text=True).stdout.split()
get = lambda img, p: subprocess.run(["python3", sq, img, "get", p], capture_output=True).stdout
names = ls(data)
files = [n for n, z in zip(names[0::2], names[1::2]) if "/" not in n and n != "shell.hist"]
bad = [n for n in files if get(data, n) != get(tgt + ".part", n)]
print("same" if files and not bad else "differ: %s" % bad)' "$target" "$out/os.img" "$disk" "$root/tools/sqfs.py")
    if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected: $2, got: $got)"; fail=1; fi
}
copied install-copy-esc-blank 'none'
check_all install-copy 'Kernel copied and read back.|help copied| files copied.'  'install copy' '<ret>' y '<pause>' '<pause>' '<pause>'
copied install-copied 'same'
check install-after-copy 'Target: disk 2.'  install '<ret>'   # a copy of the kernel is not the boot disk
# installer I.4: the boot code and the active flag; then the target boots alone as the only disk
bootsec() { # bootsec NAME 'blank' | 'boots': sector 0 of the target, on the host
    got=$(python3 -c 'import sys
t = open(sys.argv[1], "rb").read(512); o = open(sys.argv[2], "rb").read(512)
if not any(t[:440]): print("blank")
elif t[:440] == o[:440] and t[446] == 0x80 and t[450] == 0x7F and t[510:] == b"\x55\xaa": print("boots")
else: print("wrong")' "$target" "$out/os.img")
    if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (expected: $2, got: $got)"; fail=1; fi
}
check install-boot-esc 'Nothing was written.'  'install boot' '<ret>' '<esc>'
bootsec install-boot-esc-blank 'blank'
check install-boot  'The disk now boots on its own.'  'install boot' '<ret>' y
bootsec install-bootsec 'boots'
saved_disk=$disk; boot=$target; disk=; target=
check_all install-alone 'File system: partition 1 of the boot disk|copied-ok' 'cat instfile' '<ret>'
check install-alone-boot 'boot disk, not touched'  install '<ret>'
boot=; disk=$saved_disk; target=$out/target.img
# installer I.5: run install does I.1 to I.4 after one question, on a second blank scratch image
target=$out/target2.img
rm -f "$target"
dd if=/dev/zero of="$target" bs=1024 count=16384 2>/dev/null
check_all inst-esc  'Target disk: 2 (16 MiB)|Cancelled. Nothing was written.'  'run install' '<ret>' '<pause>' '<esc>'
mbr   inst-esc-blank 'blank'
check inst-la       'Sciurus-OS/2: Installatio'  'lang la' '<ret>' 'run install' '<ret>' '<pause>' '<esc>'
check inst-tlh      "Squirrel-OS/2 jomwI'"  'lang tlh' '<ret>' 'run install' '<ret>' '<pause>' '<esc>'
check_all inst-run  'Partition table ... done|File system ... done|Copying the system ... done|Boot code ... done|Installed.' \
                    'put inst.bat run install' '<ret>' 'run inst.bat' '<ret>' '<pause>' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>'
saved_disk=$disk; boot=$target; disk=; target=
check_all inst-boots 'File system: partition 1 of the boot disk|run install'  'cat inst.bat' '<ret>'
boot=; disk=$saved_disk; target=$out/target.img
target=
check install-none  'No target disk.'       'install part' '<ret>'
# 1.3.0: graphics mode, one pixel written and read back, then text mode again
check gfxtest      'gfxtest: PASS'         gfxtest '<ret>'
check gfx-text     'systest: PASS'         gfxtest '<ret>' systest '<ret>'
# 1.3.1: a line and a filled rectangle, read back
check gfxprim      'gfxprim: PASS'         gfxprim '<ret>'
check gfxprim-text 'systest: PASS'         gfxprim '<ret>' systest '<ret>'
# 1.3.2: a string in graphics mode, ink and background read back
check gfxtext      'gfxtext: PASS'         gfxtext '<ret>'
check gfxtext-text 'systest: PASS'         gfxtext '<ret>' systest '<ret>'
# 1.3.3: graph plots y = f(x); the text screen comes back as it was
check_all graph     'graph> y = x|Plotted y = x for x from -10 to 10: 320 points, 319 on screen' \
                    'run graph' '<ret>' 'y = x' '<ret>' '<pause>' ' ' '<pause>'
check graph-domain  'Plotted y = sqrt(x) for x from -10 to 10: 160 points, 160 on screen' \
                    'run graph' '<ret>' 'y = sqrt(x)' '<ret>' '<pause>' ' ' '<pause>'
check graph-syntax  'Error: syntax at column 8'  'run graph' '<ret>' 'y = x +' '<ret>'
check graph-mem     '129912 KB free'        'run graph' '<ret>' 'y = x' '<ret>' '<pause>' ' ' '<pause>' '<esc>' mem '<ret>'
# 1.4.0: a window created, a frame pixel read back, closed, read again
check wintest      'win: PASS'             wintest '<ret>'
check wintest-text 'systest: PASS'         wintest '<ret>' systest '<ret>'
# 1.4.1: a window moved and resized, frame pixels read back
check winmove      'winmove: PASS'         winmove '<ret>'
check winmove-text 'systest: PASS'         winmove '<ret>' systest '<ret>'
# 1.4.2: two windows; Tab moves the focus and the top, typing goes to the focused one
check_all winfocus 'One got "cd"|Two got "ab"|top: One' \
                   winfocus '<ret>' '<pause>' ab '<tab>' cd '<ret>'
check_all winfocus-none 'One got ""|Two got "xy"|top: Two' \
                   winfocus '<ret>' '<pause>' xy '<ret>'
check winfocus-text 'systest: PASS'        winfocus '<ret>' '<pause>' '<ret>' systest '<ret>'
# 1.5.0: a label in a window, ink read back; gone when its window closes
check labeltest    'label: PASS'           labeltest '<ret>'
check labeltest-text 'systest: PASS'       labeltest '<ret>' systest '<ret>'
# 1.5.1: a button; Enter or Space posts MSG_BUTTON to the shell's queue
check buttontest   'button: PASS (1)'      buttontest '<ret>' '<pause>' '<ret>' '<esc>'
check buttontest-2 'button: PASS (2)'      buttontest '<ret>' '<pause>' ' ' x ' ' '<esc>'
check buttontest-none 'button: no event'   buttontest '<ret>' '<pause>' x '<esc>'
check buttontest-text 'systest: PASS'      buttontest '<ret>' '<pause>' '<esc>' systest '<ret>'
# 1.5.2: an edit field; typed keys land in its buffer, Backspace deletes
check fieldtest    'field: PASS "Hi the"'  fieldtest '<ret>' '<pause>' 'Hi there' '<backspace>' '<backspace>' '<ret>'
check fieldtest-full 'field: PASS "abcdefghijklmnop"' fieldtest '<ret>' '<pause>' abcdefghijklmnopqrst '<esc>'
check fieldtest-text 'systest: PASS'       fieldtest '<ret>' '<pause>' '<esc>' systest '<ret>'
# 1.5.3: a list; Down and Up move the selection, the selected name is printed
check listtest     'list: Beech'           listtest '<ret>' '<pause>' '<down>' '<ret>'
check listtest-end 'list: Dogwood'         listtest '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<down>' '<esc>'
check listtest-up  'list: Acorn'           listtest '<ret>' '<pause>' '<down>' '<up>' '<up>' '<ret>'
check listtest-text 'systest: PASS'        listtest '<ret>' '<pause>' '<esc>' systest '<ret>'
# 1.6.0: the desktop lists the programs (read off the graphics screen); Esc: the shell
check_all desktop  'gfx: Squirrel-OS/2 Desktop|gfx: files|gfx: calc|gfx: edit|gfx: vedit|gfx: draw' \
                   desktop '<ret>' '<pause>' '<gfx>'
check desktop-quit 'systest: PASS'         desktop '<ret>' '<pause>' '<down>' '<esc>' systest '<ret>'
# 1.6.1: calc in a window on the desktop: 2 + 2, Esc back to the desktop
check_all desktop-calc 'gfx: calc> 2 + 2|gfx: = 4' \
                   desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '2 + 2' '<ret>' '<pause>' '<gfx>'
check desktop-calc-back 'gfx: Squirrel-OS/2 Desktop' \
                   desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '2 + 2' '<ret>' '<esc>' '<pause>' '<gfx>'
check desktop-calc-mem '129912 KB free'    desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '2 + 2' '<ret>' '<esc>' '<pause>' '<esc>' mem '<ret>'
check desktop-calc-text 'systest: PASS'    desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' systest '<ret>'
# 1.6.3: draw in a window on the desktop: plot two cells, save, Esc back
check desktop-draw  'gfx: |**' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<right>' ' ' '<pause>' '<gfx>'
check desktop-draw-save "> cat dkdraw${nl}**" \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<right>' ' ' '<f2>' '<pause>' dkdraw '<ret>' '<esc>' '<pause>' '<esc>' 'cat dkdraw' '<ret>'
check desktop-draw-back 'gfx: Squirrel-OS/2 Desktop' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<gfx>'
check desktop-draw-mem '129912 KB free'    desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<esc>' d '<pause>' '<esc>' mem '<ret>'
check desktop-draw-text 'systest: PASS'    desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' systest '<ret>'
# 1.6.4: edit and vedit in a window: type, save, close; cat sees the text
check_all desktop-edit 'gfx: Text Editor: (untitled) [modified]|gfx: Typed in a window' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' 'Typed in a window' '<pause>' '<gfx>'
check desktop-edit-save 'Saved from edit'  desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' 'Saved from edit' \
                   '<ctrl-s>' dkedit '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' 'cat dkedit' '<ret>'
check desktop-vedit-save 'Saved from vedit' desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<ret>' '<pause>' 'Saved from vedit' \
                   '<f2>' dkvedit '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' 'cat dkvedit' '<ret>'
check desktop-edit-mem '129912 KB free'    desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' x '<esc>' d '<pause>' '<esc>' mem '<ret>'
# 1.6.5: pixel drawing in draw: the self-check, the canvas from draw (g), and over the desktop
check drawpx        'drawpx: PASS'          drawpx '<ret>'
check drawpx-text   'systest: PASS'         drawpx '<ret>' systest '<ret>'
check drawpx-mem    '129912 KB free'        drawpx '<ret>' mem '<ret>'
check draw-pixels   'dpx.px'                'run draw dpx' '<ret>' g '<pause>' p '<right>' '<f2>' '<esc>' '<pause>' '<esc>' ls '<ret>'
check_all desktop-draw-pixels 'gfx: Pixels: drawing.px|gfx: Pen down: moving draws.' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' g '<pause>' p '<pause>' '<gfx>'
check desktop-draw-pixels-back 'gfx: Drawing Program' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' g '<pause>' '<esc>' '<pause>' '<gfx>'
# 1.7.0: classes and messages: inherited, overridden, sent to self, unknown
check objtest       'obj: PASS'             objtest '<ret>'
# 1.7.1: fields set through the parent's method, read through the subclass's
check objfields     'obj fields: PASS'      objtest '<ret>'
# 1.7.3: objs lists the classes and the live objects; objtest frees its objects
check_all objs-empty 'Classes:|Objects:|0 live' objs '<ret>'
check_all objs-tree  'Square < Shape|0 live'    objtest '<ret>' objs '<ret>'
check objtest-mem   '129912 KB free'        objtest '<ret>' mem '<ret>'
check objtest-text  'systest: PASS'         objtest '<ret>' objtest '<ret>' systest '<ret>'
# 1.8.0: objtest saves a square, frees it and loads it back
check objstore      'obj store: PASS'       objtest '<ret>'
# 1.8.2: objtest.obj outlives a reboot; objcat prints class and fields (no classes registered yet)
check_all obj-persist 'class Square|0: 5|1: red' 'objcat objtest.obj' '<ret>'
# 1.7.6: the desktop's entries are Program objects; Enter sends open (files too)
check desktop-files 'gfx: Arrows PgUp/PgDn Home/End' \
                   desktop '<ret>' '<pause>' '<ret>' '<pause>' '<gfx>'
check desktop-files-back 'gfx: Squirrel-OS/2 Desktop' \
                   desktop '<ret>' '<pause>' '<ret>' '<pause>' '<esc>' '<pause>' '<gfx>'
check_all desktop-objs 'Program < DesktopObject|0 live' desktop '<ret>' '<pause>' '<esc>' objs '<ret>'
# Opening the desktop twice must not re-register DesktopObject/Program (obj_class is idempotent)
check_all desktop-objs-2 'Program < DesktopObject|0 live' \
                   desktop '<ret>' '<pause>' '<esc>' desktop '<ret>' '<pause>' '<esc>' objs '<ret>'
# 1.8.3: the desktop's entries are object files in /desktop, written the
# first time; a removed file's entry is gone. A disk of their own, so the
# other desktop checks keep all five entries.
dd if=/dev/zero of="$out/dkstore.img" bs=1024 count=1024 2>/dev/null
disk=$out/dkstore.img
check_all dk-store  'files.obj|calc.obj|edit.obj|vedit.obj|draw.obj' \
                   desktop '<ret>' '<pause>' '<esc>' 'ls /desktop' '<ret>'
check_all dk-store-cat 'class Program|name: calc|entry: calc' \
                   desktop '<ret>' '<pause>' '<esc>' 'objcat /desktop/calc.obj' '<ret>'
check_none dk-store-rm 'gfx: draw' 'gfx: Squirrel-OS/2 Desktop' \
                   'rm /desktop/draw.obj' '<ret>' desktop '<ret>' '<pause>' '<gfx>'
check_all dk-store-left 'gfx: files|gfx: vedit' desktop '<ret>' '<pause>' '<gfx>'
check dk-store-open 'gfx: = 4' \
                   desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '2 + 2' '<ret>' '<pause>' '<gfx>'
# 1.9.0: a Tools folder; Enter shows its (empty) contents, Backspace goes up.
# A fresh disk of its own.
dd if=/dev/zero of="$out/dkfold.img" bs=1024 count=1024 2>/dev/null
disk=$out/dkfold.img
check_all dk-folder 'gfx: Squirrel-OS/2 Desktop|gfx: draw|gfx: Tools|gfx: Bksp: up' desktop '<ret>' '<pause>' '<gfx>'
check_none dk-folder-open 'gfx: calc' 'gfx: Tools' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<gfx>'
check_all dk-folder-back 'gfx: Squirrel-OS/2 Desktop|gfx: calc' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<backspace>' '<pause>' '<gfx>'
check_all dk-folder-cat "class Folder|name: Tools|class Program|in:${nl}entry: calc" \
                   desktop '<ret>' '<pause>' '<esc>' 'objcat /desktop/Tools.obj' '<ret>' 'objcat /desktop/calc.obj' '<ret>'
check dk-folder-quit 'systest: PASS' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<esc>' systest '<ret>'
disk=$out/data.img
check gfx-read-list 'gfx: Dogwood'         listtest '<ret>' '<pause>' '<gfx>'
check topo-stub     'Scaffolded. Simplicial homology'  'run topo' '<ret>'
# program loader: a disk prepared on the host with tools/sqfs.py
# 0.9.2: usage hints, file-system error reasons, mv into a directory,
# paths in edit, directories in the browser
check sh-usage      'Usage: mkdir <dir>'    mkdir '<ret>'
check sh-unknown    'Unknown command'       bogus '<ret>'
check fs-e-exists   'Already exists'        'mkdir e1' '<ret>' 'mkdir e1' '<ret>'
check fs-e-name     'Bad name'              'mk abcdefghijklmnopq' '<ret>'
check fs-e-nodir    'No such directory'     'mk nod/x' '<ret>'
check fs-e-isdir    'Is a directory'        'cat e1' '<ret>'
check fs-e-notempty 'Directory not empty'   'mkdir e1/sub' '<ret>' 'put e1/sub/f x' '<ret>' 'rm e1' '<ret>'
check fs-mv-into    'mvf               9'   'put mvf moved-up' '<ret>' 'mv mvf e1' '<ret>' 'ls e1' '<ret>'
check fs-mv-up      'moved-up'              'cd e1' '<ret>' 'mv mvf ..' '<ret>' cd '<ret>' 'cat mvf' '<ret>'
check ed-dir        'Is a directory'        'run edit e1' '<ret>'
check ed-path-w     'Saved'                 'run edit e1/long-name.txt' '<ret>' deep '<ctrl-s>'
check ed-path-r     'deep'                  'cat e1/long-name.txt' '<ret>'
check fb-dir        'in /e1'                'cd e1' '<ret>' 'run files' '<ret>'
check fb-dir-up     '[app]'                 'cd e1' '<ret>' 'run files' '<ret>' '<ret>'
# 0.9.3: release readiness
check ver-banner    'Squirrel-OS/2 1.9.0'   systest '<ret>'
check ver-planned   '(planned: topo)'  systest '<ret>'
check calc-hist-root '1 + 1 = 2'            'mkdir c1' '<ret>' 'cd c1' '<ret>' 'run calc' '<ret>' '1 + 1' '<ret>' '<esc>' 'cat /calc.hist' '<ret>'
boot="--floppy $out/floppy.img"
check floppy-boot   'systest: PASS'         '<pause>' '<pause>' systest '<ret>'
check floppy-data   'kept'                  '<pause>' '<pause>' 'cat keep/note' '<ret>'
check floppy-e820   'usable'                '<pause>' '<pause>' mem '<ret>'
# installer I.6: the CD image (El Torito floppy emulation around floppy.img) boots to the shell
boot="--cdrom $out/cd.iso"
check cd-boot       'systest: PASS'         '<pause>' '<pause>' systest '<ret>'
check cd-data       'kept'                  '<pause>' '<pause>' 'cat keep/note' '<ret>'
boot=
export QEMU_EXTRA='-cpu 486,-pse'
check cpu-nopse     'needs a Pentium-class CPU'
export QEMU_EXTRA='-cpu pentium,-fpu'
check cpu-nofpu     'needs a Pentium-class CPU'
unset QEMU_EXTRA
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
check vm-nest       'own memory intact'     'run nest' '<ret>'
check vm-nest-child 'Argument: from nest'   'run nest' '<ret>'
check vm-crash      'Program ended: pid'    'run crash' '<ret>'
check vm-crash-addr 'address=C0000000 (read, page not present)'  'run crash' '<ret>'
check crash-name    'in pid 1 (crash)'      'run crash' '<ret>'
check crash-regs    'EAX=00000022'          'run crash' '<ret>'
check vm-after      'systest: PASS'         'run crash' '<ret>' systest '<ret>'
check vm-no-leak    '129912 KB free'        'run nest' '<ret>' 'run crash' '<ret>' 'run hello' '<ret>' mem '<ret>'
check vm-ps         'kernel'                ps '<ret>'
check heap          'heap: PASS (1024 KB)'  'run heap' '<ret>'
check heap-limit-after 'Program ended: pid'  'run heap after' '<ret>'
check heap-keep-leak '129912 KB free'       'run heap keep' '<ret>' 'run heap after' '<ret>' mem '<ret>'
# 1.0.1: each process keeps its own x87 registers across a switch
check fpu-switch    'fpu: PASS'             'run fpu' '<ret>' '<pause>'
# 1.0.2: SYS_SEEK
check seek          'seek: PASS'            'run seek' '<ret>' '<pause>'
check devices       'hd1     block   ready 2048 sectors'  devices '<ret>'
check devices-ro    '(read-only for programs)'  devices '<ret>'
check devtest       'devtest: PASS'         'run devtest' '<ret>'
check up-ls         '25 file(s)'             'run ls' '<ret>'
# 1.2.1: a key arrives as a queue event as well as through SYS_GETC
check_all keyev     'keyev: queue q getc q|keyev: PASS'  'run keyev' '<ret>' '<pause>' q '<pause>'
check_all keyev-shift 'keyev: queue Q getc Q|keyev: PASS'  'run keyev' '<ret>' '<pause>' Q '<pause>'
# 1.2.0: message queues between processes
check_all msg       'msg: queue full (-2)|msg: child got ping|msg: PASS'  'run msg' '<ret>' '<pause>'
# 1.1.1: a spawn in the program's own image is a thread sharing its memory
check thread        'thread: PASS'          'run thread' '<ret>'
# KB-16: a wait that closes a cycle of waits returns -1 instead of a kernel panic
check waitcycle     'waitcycle: PASS'       'run waitcycle' '<ret>'
check_all stackover '*** stack overflow in pid|Program ended|stackover: PASS'  'run stackover' '<ret>'
# 1.1.0: the timer preempts a program that spins without a system call
check_all sched-preempt 'spin: second process ran|preempt: PASS' 'run spin' '<ret>' '<pause>'
check up-ls-filter  '4 file(s)'             'run ls he' '<ret>'
# 1.0.3: programs read why a file call failed (SYS_FSERROR), in the shell's words
check errno-nf      'errno: Not found'      'run errno missing' '<ret>'
check errno-dir     'errno: Is a directory' 'mkdir edir' '<ret>' 'run errno edir' '<ret>'
# 1.0.4: zombies nobody waits for do not fill the process table
check zombie        'zombie: PASS'          'run zombie' '<ret>' '<pause>'
check zombie-ps     '2 8 86'                'run zombie' '<ret>' '<pause>' 'ps | run wc' '<ret>'   # header + shell only
check errno-la      'errno: Non inventum'   'lang la' '<ret>' 'run errno missing' '<ret>'
check up-cat        'three'                 'run cat notes' '<ret>'
check up-cat-missing 'not found: zip'       'run cat zip notes' '<ret>'
check sh-redirect   'hi there'              'echo hi there > greet' '<ret>' 'cat greet' '<ret>'
check sh-append     'more'                  'echo more >> greet' '<ret>' 'cat greet' '<ret>'
check sh-pipe       '1 3 6'                 'echo x y z | run cat | run wc' '<ret>'
check sh-stdin      '= 42'                  'run calc < exprs > out' '<ret>' 'cat out' '<ret>'
check sh-quiet      'calc> 2 + 3'           'run calc < exprs > out' '<ret>' 'run cat < out' '<ret>'
check sh-ls-pipe    'demo2.bat'             'ls | run cat' '<ret>'
check sh-badpipe    'command on both sides' 'ls |' '<ret>'
check sh-noname     'needs a file name'     'cat >' '<ret>'
check sh-nofile     'Cannot read nofile'    'run wc < nofile' '<ret>'
check bat-run       'in demo2'              'batch demo.bat' '<ret>'
check bat-quiet     'quiet line'            'batch demo.bat' '<ret>'
check bat-pipe      '1 3 6'                 'batch demo.bat' '<ret>'
check bat-chain     '> echo in demo2'       'run demo.bat' '<ret>'
check bat-missing   'Cannot read nope'      'batch nope' '<ret>'
check dir-pwd       '/d1'                   'mkdir d1' '<ret>' 'cd d1' '<ret>' pwd '<ret>'
check dir-prompt    '/d1>'                  'cd d1' '<ret>'
check dir-path      '1 1 6 d2/n'            'mkdir d2' '<ret>' 'put d2/n nutty' '<ret>' 'run wc d2/n' '<ret>'
check dir-dotdot    '1 1 6 ../n'            'cd d2' '<ret>' 'mkdir s' '<ret>' 'cd s' '<ret>' 'run wc ../n' '<ret>'
check dir-run-root  'Hello from a loaded'   'cd d1' '<ret>' 'run hello' '<ret>'
check dir-hist-root '0 file(s)'             'mkdir d3' '<ret>' 'cd d3' '<ret>' 'run ls' '<ret>'
check dir-ls-prog   '<dir>'                 'run ls d1' '<ret>'
check dir-rm-full   'Directory not empty'   'rm d2' '<ret>'
check dir-mv-cycle  'into itself'           'mkdir d5' '<ret>' 'mkdir d5/e' '<ret>' 'mv d5 d5/e/f' '<ret>'
check dir-mv-into   'g                 6'   'put g nutty' '<ret>' 'mv g d5/g' '<ret>' 'ls d5' '<ret>'
check dir-cd-bad    'No such directory'     'cd nowhere' '<ret>'
check dir-rm-empty  '0 file(s)'             'rm d1' '<ret>' 'run ls d1' '<ret>'
check lang-show     'Language: en (en la tlh)'  lang '<ret>'
check lang-la       'Tabulae:'              'mkdir la1' '<ret>' 'cd la1' '<ret>' 'lang la' '<ret>' ls '<ret>'   # an empty directory: the root listing no longer fits on one screen
check lang-tlh      "ra' tlhaQ"             'lang tlh' '<ret>' xyz '<ret>'
# 1.0.5: usage lines and file-system errors follow lang
check l10n-usage-la 'Usus: mkdir <dir>'     'lang la' '<ret>' mkdir '<ret>'
check l10n-hint-la  '(lineam tabulae addit)'  'lang la' '<ret>' put '<ret>'
check l10n-fe-tlh   "tu'lu'pu'"             'lang tlh' '<ret>' 'mkdir t1' '<ret>' 'mkdir t1' '<ret>'
check l10n-rm-tlh   "tu'lu'be'"             'lang tlh' '<ret>' 'rm nosuch' '<ret>'
check lang-bad      'Unknown language (en la tlh)'  'lang fr' '<ret>'
check lang-banner   'Sciurus-OS/2 1.9.0'    'lang la' '<ret>' 'run calc' '<ret>' '<esc>'
# 1.0.6: calc, edit and draw titles follow lang
check l10n-calc-tlh "mI' De'wI' (Esc to exit)" 'lang tlh' '<ret>' 'run calc' '<ret>'
check l10n-edit-tlh "ghItlhwI': (untitled)" 'lang tlh' '<ret>' 'run edit' '<ret>'
check l10n-draw-la  'Programma pingendi - ASCII canvas' 'lang la' '<ret>' 'run draw' '<ret>'
check l10n-calc-en  'Basic Calculator (Esc to exit)' 'run calc' '<ret>'
check lang-systest  'systest: PROBATUM'     'lang la' '<ret>' systest '<ret>'
disk=$out/auto.img
check bat-autoexec  'autoexec ran'
check lang-autoexec 'Tabulae:'              ls '<ret>'
disk=$out/dkauto.img
check_all desktop-boot 'gfx: Squirrel-OS/2 Desktop|gfx: draw' '<pause>' '<gfx>'
check desktop-boot-quit 'systest: PASS'    '<pause>' '<esc>' systest '<ret>'
disk=
check no-disk       'no data disk'          blktest '<ret>'
check devices-nodisk 'hd1     block   absent'  devices '<ret>'
check rom-fallback  'Hello from Squirrel'   'cat edit' '<ret>'
exit $fail
