#!/bin/sh
# Build the image and run scripted shell sessions in QEMU, checking the screen.
# Usage: tools/regress.sh   (needs nasm, qemu-system-i386, python3)
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/squirrel-os2-build
mkdir -p "$out"
python3 "$root/tools/mkstrings.py" --check || exit 1
python3 "$root/tools/mkfont.py" --check || exit 1
python3 "$root/tools/mkicon.py" --check || exit 1   # 2.3-icons
(cd "$root/kernel" && nasm -f bin boot.asm -o "$out/boot.bin" \
    && nasm -f bin pm.asm -o "$out/pm.bin" 2>/dev/null)
cat "$out/boot.bin" "$out/pm.bin" > "$out/os.img"
dd if=/dev/zero of="$out/floppy.img" bs=1024 count=1440 2>/dev/null
dd if="$out/os.img" of="$out/floppy.img" conv=notrunc 2>/dev/null
python3 "$root/tools/mkiso.py" "$out/floppy.img" "$out/cd.iso"    # installer I.6
for prog in hello wc elfhello ls cat nest crash heap devtest fpu seek errno zombie spin thread msg keyev waitcycle stackover udptest priotest drvtest agetest ring3 smpspin lxhello lxfile lxcat lxsys winrun winhello wincrt winprog clipbrd; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
done
python3 "$root/tools/sqfs.py" "$out/progs.img" format 1024
for prog in hello wc elfhello ls cat nest crash heap devtest fpu seek errno zombie spin thread msg keyev waitcycle stackover udptest priotest drvtest agetest ring3 smpspin lxhello lxfile lxcat lxsys winrun winhello wincrt winprog; do python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/$prog"; done
# OS2-GAMES (G.x): the games get a disk of their own, so the file counts above stay put
python3 "$root/tools/sqfs.py" "$out/games.img" format 1024
for prog in mines reversi klondike freecell hearts chess mahjongg bridge checkers go; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
    python3 "$root/tools/sqfs.py" "$out/games.img" put "$out/$prog"
done
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
# OS2-APPS: graphical programs (SYS_GUI) on a data disk of their own
python3 "$root/tools/sqfs.py" "$out/apps.img" format 1024
for prog in guitest calculator clock notepad grapher charmap paint viewer topology matrixgui stats graph3d hexedit write; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
    python3 "$root/tools/sqfs.py" "$out/apps.img" put "$out/$prog"
done
for prog in sheet geometry cas sysmon logview diskutil notebook; do  # C.4, C.6, C.5, A.5, C.8
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
    python3 "$root/tools/sqfs.py" "$out/apps.img" put "$out/$prog"
done
python3 "$root/tools/sqfs.py" "$out/apps.img" put "$out/crash"   # A.5: logview shows its crash
python3 "$root/tools/sqfs.py" "$out/apps.img" put "$out/clipbrd"   # 2.3-clipboard: progs.img has no free entry
python3 - "$out/grad.bmp" <<'PYEOF'    # A.2: a 24-bit test picture, 64 x 48
import struct, sys
w, h = 64, 48
rows = b''.join(bytes(c for x in range(w) for c in (128, y * 255 // (h - 1), x * 255 // (w - 1))) for y in range(h - 1, -1, -1))
open(sys.argv[1], 'wb').write(b'BM' + struct.pack('<IHHI', 54 + len(rows), 0, 0, 54)
    + struct.pack('<IiiHHIIiiII', 40, w, h, 1, 24, 0, len(rows), 2835, 2835, 0, 0) + rows)
PYEOF
python3 "$root/tools/sqfs.py" "$out/apps.img" put "$out/grad.bmp"
python3 "$root/tools/sqfs.py" "$out/dos.img" format 1024    # P.8: DOS programs under dosrun, on their own disk
nasm -f bin -i "$root/programs/" "$root/programs/dosrun.asm" -o "$out/dosrun"
for prog in doshello doscpu dosfile dosgfx; do nasm -f bin "$root/programs/$prog.asm" -o "$out/$prog.com"; done
nasm -f bin "$root/programs/dosexe.asm" -o "$out/dosexe.exe"
nasm -f bin -i "$root/programs/" "$root/programs/lxsig.asm" -o "$out/lxsig"    # P.2 signals ride along on this disk
nasm -f bin -i "$root/programs/" "$root/programs/bsdhello.asm" -o "$out/bsdhello"    # P.10 FreeBSD rides along on this disk
for f in dosrun winrun doshello.com doscpu.com dosfile.com dosgfx.com dosexe.exe lxsig bsdhello; do python3 "$root/tools/sqfs.py" "$out/dos.img" put "$out/$f"; done
# OS2-HW H.1: the UEFI loaders carry this os.img; an EFI system partition image holds both
(cd "$root/boot/uefi" && nasm -f bin -DOS_IMG="\"$out/os.img\"" bootx64.asm -o "$out/BOOTX64.EFI" \
    && nasm -f bin -DOS_IMG="\"$out/os.img\"" bootia32.asm -o "$out/BOOTIA32.EFI")
python3 "$root/tools/mkesp.py" "$out/esp.img" "$out/BOOTX64.EFI" "$out/BOOTIA32.EFI"
# OS2-HW (H.3-H.6): blkdev on a disk of its own; marked scratch disks for the AHCI/NVMe/USB drivers
python3 "$root/tools/sqfs.py" "$out/hw.img" format 1024
nasm -f bin -i "$root/programs/" "$root/programs/blkdev.asm" -o "$out/blkdev"
python3 "$root/tools/sqfs.py" "$out/hw.img" put "$out/blkdev"
python3 "$root/tools/sqfs.py" "$out/hw.img" put "$out/keyev"
hwdisk() {  # hwdisk FILE: a 4 MB disk with 'SQHW' in sector 0 and 'S100' in sector 100
    python3 - "$1" <<'PYEOF'
import sys
d = bytearray(4 << 20); d[0:4] = b'SQHW'; d[51200:51204] = b'S100'
open(sys.argv[1], 'wb').write(d)
PYEOF
}
sector5() {  # sector5 NAME FILE: the pattern blkdev wrote must be in the image itself
    if python3 -c "import sys; d = open(sys.argv[1], 'rb').read()[2560:2568]; sys.exit(d != bytes.fromhex('05005a5a06015b5b'))" "$2"
    then echo "ok   $1"; else echo "FAIL $1 (sector 5 of $2 not written)"; fail=1; fi
}
rm -f "$out/data.img"
dd if=/dev/zero of="$out/data.img" bs=1024 count=1024 2>/dev/null

fail=0
disk=$out/data.img              # data disk attached as primary slave
nl=$(printf '\n_'); nl=${nl%_}  # a newline, for expected text that spans two lines (POSIX sh has no $'\n')
check() {   # check NAME EXPECTED KEYS...
    name=$1; want=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${nic:+--nic} ${boot:-"$out/os.img"} "$@")
    case $screen in
        *"$want"*) echo "ok   $name" ;;
        *) echo "FAIL $name (expected: $want)"; fail=1 ;;
    esac
}
check_all() {   # check_all NAME 'WANT1|WANT2|...' KEYS...: every WANT must be on the screen
    name=$1; wants=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${nic:+--nic} ${boot:-"$out/os.img"} "$@")
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
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${nic:+--nic} ${boot:-"$out/os.img"} "$@")
    case $screen in
        *"$unwanted"*) echo "FAIL $name (unexpected: $unwanted)"; fail=1 ;;
        *"$seen"*) echo "ok   $name" ;;
        *) echo "FAIL $name (expected: $seen)"; fail=1 ;;
    esac
}
# Count non-overlapping occurrences of needle in haystack (POSIX sh).
count_occ() {
    _s=$1; _n=$2; _c=0
    while :; do
        case $_s in
            *"$_n"*) _c=$((_c + 1)); _s=${_s#*"$_n"} ;;
            *) break ;;
        esac
    done
    echo "$_c"
}
check_once() {   # check_once NAME 'WANT1|WANT2|...' KEYS...: each WANT appears exactly once
    name=$1; wants=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} ${target:+--target "$target"} ${nic:+--nic} ${boot:-"$out/os.img"} "$@")
    bad=
    oldifs=$IFS; IFS='|'
    for want in $wants; do
        n=$(count_occ "$screen" "$want")
        if [ "$n" -ne 1 ]; then bad="$bad [$want x$n]"; fi
    done
    IFS=$oldifs
    if [ -z "$bad" ]; then echo "ok   $name"; else echo "FAIL $name (want exactly 1 each:$bad)"; fail=1; fi
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
# 2.3-clipboard: Ctrl+Ins copies the line, Shift+Ins pastes; Ctrl+X cuts the line, Ctrl+V pastes
check ed-clip-copy  'abc and abc'           'run edit memoc1' '<ret>' abc '<ctrl-insert>' ' and ' '<shift-insert>' '<ctrl-s>' '<esc>' 'cat memoc1' '<ret>' 'rm memoc1' '<ret>'
check ed-clip-cut   'two one'               'run edit memoc2' '<ret>' one '<ret>' two '<up>' '<ctrl-x>' '<end>' ' ' '<ctrl-v>' '<ctrl-s>' '<esc>' 'cat memoc2' '<ret>' 'rm memoc2' '<ret>'
check cbtest        'clip: PASS'            cbtest '<ret>'
check cbtest-text   'systest: PASS'         cbtest '<ret>' systest '<ret>'
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
check ed-undo-mem   '128888 KB free'        'run edit' '<ret>' x '<ctrl-z>' '<esc>' mem '<ret>'
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
check_all install-list "disk 0: $(($(wc -c < "$out/os.img") / 512)) sectors (0 MiB)  boot disk, not touched|disk 1: 2048 sectors (1 MiB)  data disk, not touched|disk 2: 32768 sectors (16 MiB)  blank|Target: disk 2." \
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
# installer I.3: the kernel (low and high images, all of os.img after sector 0) to the same sectors of the target, the data disk's root files into its SQFS
check install-mkfile 'ok'                 'put instfile copied-ok' '<ret>'   # a file for the installed system to show
check install-boot-nokernel 'Type install copy first.'  'install boot' '<ret>'
check install-copy-esc 'Nothing was written.'  'install copy' '<ret>' '<esc>'
copied() {  # copied NAME WANT: on the host, 'none' (sector 1 still blank) or 'same' (kernel and files match)
    got=$(python3 -c 'import subprocess, sys
tgt, osimg, data, sq = sys.argv[1:5]
t = open(tgt, "rb").read()
if not any(t[512:1024]): print("none"); sys.exit()
o = open(osimg, "rb").read()
if t[512:len(o)] != o[512:]: print("kernel differs"); sys.exit()
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
# 2.1: VBE modes 640x480 / 800x600 / 1024x768 at 8/16/32 bpp (13h fallback: vbe: 13h)
check vbetest      'vbe: PASS'             vbetest '<ret>'
check vbetest-text 'systest: PASS'         vbetest '<ret>' systest '<ret>'
check cliptest      'clip: PASS'            cliptest '<ret>'                  # 2.1-blit-clip
check cliptest-text 'systest: PASS'         cliptest '<ret>' systest '<ret>'
check bevtest       'bevel: PASS'           bevtest '<ret>'                   # W.1-theme
check bevtest-text  'systest: PASS'         bevtest '<ret>' systest '<ret>'
check pfont         'pfont: PASS'           pfont '<ret>' '<pause>' '<spc>'   # 2.2-propfont
check_all pfont-read 'gfx: Wg Squirrel window face|gfx: Wg Display face, bold' pfont '<ret>' '<pause>' '<gfx>' '<spc>'
check pfont-text    'systest: PASS'         pfont '<ret>' '<pause>' '<spc>' systest '<ret>'
check icontest      'icon: PASS'            icontest '<ret>'                  # 2.3-icons
check icontest-text 'systest: PASS'         icontest '<ret>' systest '<ret>'
check winvbe        'winvbe: PASS'          winvbe '<ret>'                    # 2.2-vbe-wm
check winvbe-text   'systest: PASS'         winvbe '<ret>' systest '<ret>'
check winclip       'winclip: PASS'         winclip '<ret>'                   # 2.2-clip-z
check winclip-text  'systest: PASS'         winclip '<ret>' systest '<ret>'
check winhit        'winhit: PASS'          winhit '<ret>'                    # 2.2-frame
check winhit-text   'systest: PASS'         winhit '<ret>' systest '<ret>'
check windrag       'windrag: PASS'         windrag '<ret>'                   # 2.2-mouse
check windrag-text  'systest: PASS'         windrag '<ret>' systest '<ret>'
check winmin        'winmin: PASS'          winmin '<ret>'                    # 2.2-minmax
check winmin-text   'systest: PASS'         winmin '<ret>' systest '<ret>'
check winmenu       'winmenu: PASS'         winmenu '<ret>'                   # 2.2-sysmenu
check winmenu-text  'systest: PASS'         winmenu '<ret>' systest '<ret>'
check_all winalttab 'Two Three One|alttab: PASS' winalttab '<ret>'             # 2.2-alttab
check_all sysmenu-desk 'gfx: Restore|gfx: Minimize|gfx: Close' desktop '<ret>' '<pause>' '<alt-spc>' '<pause>' '<gfx>'
check_all sysmenu-desk-move 'gfx: Programs:|desktop' desktop '<ret>' '<pause>' '<alt-spc>' '<pause>' '<down>' '<ret>' '<right>' '<right>' '<ret>' '<pause>' '<gfx>' '<esc>' '<pause>'
# 1.3.2: a string in graphics mode, ink and background read back
check gfxtext      'gfxtext: PASS'         gfxtext '<ret>'
check gfxtext-text 'systest: PASS'         gfxtext '<ret>' systest '<ret>'
# 1.3.3: graph plots y = f(x); the text screen comes back as it was
check_all graph     'graph> y = x|Plotted y = x for x from -10 to 10: 320 points, 319 on screen' \
                    'run graph' '<ret>' 'y = x' '<ret>' '<pause>' ' ' '<pause>'
check graph-domain  'Plotted y = sqrt(x) for x from -10 to 10: 160 points, 160 on screen' \
                    'run graph' '<ret>' 'y = sqrt(x)' '<ret>' '<pause>' ' ' '<pause>'
check graph-syntax  'Error: syntax at column 8'  'run graph' '<ret>' 'y = x +' '<ret>'
check graph-mem     '128888 KB free'        'run graph' '<ret>' 'y = x' '<ret>' '<pause>' ' ' '<pause>' '<esc>' mem '<ret>'
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
# 2.0.2: a list longer than its window scrolls; rows map to items past the scroll
check scrolltest    'scroll: PASS'          scrolltest '<ret>' '<pause>'
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
check desktop-calc-mem '128888 KB free'    desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '2 + 2' '<ret>' '<esc>' '<pause>' '<esc>' mem '<ret>'
check desktop-calc-text 'systest: PASS'    desktop '<ret>' '<pause>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' systest '<ret>'
# 1.6.3: draw in a window on the desktop: plot two cells, save, Esc back
check desktop-draw  'gfx: |**' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<right>' ' ' '<pause>' '<gfx>'
check desktop-draw-save "> cat dkdraw${nl}**" \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<right>' ' ' '<f2>' '<pause>' dkdraw '<ret>' '<esc>' '<pause>' '<esc>' 'cat dkdraw' '<ret>'
check desktop-draw-back 'gfx: Squirrel-OS/2 Desktop' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<gfx>'
check desktop-draw-mem '128888 KB free'    desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' ' ' '<esc>' d '<pause>' '<esc>' mem '<ret>'
check desktop-draw-text 'systest: PASS'    desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' systest '<ret>'
# 1.6.4: edit and vedit in a window: type, save, close; cat sees the text
check_all desktop-edit 'gfx: Text Editor: (untitled) [modified]|gfx: Typed in a window' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' 'Typed in a window' '<pause>' '<gfx>'
check desktop-edit-save 'Saved from edit'  desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' 'Saved from edit' \
                   '<ctrl-s>' dkedit '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' 'cat dkedit' '<ret>'
check desktop-vedit-save 'Saved from vedit' desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<ret>' '<pause>' 'Saved from vedit' \
                   '<f2>' dkvedit '<ret>' '<pause>' '<esc>' '<pause>' '<esc>' 'cat dkvedit' '<ret>'
check desktop-edit-mem '128888 KB free'    desktop '<ret>' '<pause>' '<down>' '<down>' '<ret>' '<pause>' x '<esc>' d '<pause>' '<esc>' mem '<ret>'
# 1.6.5: pixel drawing in draw: the self-check, the canvas from draw (g), and over the desktop
check drawpx        'drawpx: PASS'          drawpx '<ret>'
check drawpx-text   'systest: PASS'         drawpx '<ret>' systest '<ret>'
check drawpx-mem    '128888 KB free'        drawpx '<ret>' mem '<ret>'
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
check objtest-mem   '128888 KB free'        objtest '<ret>' mem '<ret>'
check objtest-text  'systest: PASS'         objtest '<ret>' objtest '<ret>' systest '<ret>'
# 1.8.0: objtest saves a square, frees it and loads it back
check objstore      'obj store: PASS'       objtest '<ret>'
# 1.9.3: the network layer's loopback; frames' pages are given back
check nettest       'net: PASS'             nettest '<ret>'
check nettest-mem   '128888 KB free'        nettest '<ret>' nettest '<ret>' mem '<ret>'
# 1.9.4: an NE2000 card on QEMU's user network
check nic-absent    'ne0     net     absent' devices '<ret>'
nic=1
check nic-devices   'ne0     net     ready 52:54:00:12:34:56' devices '<ret>'
check nic-test      'nic: PASS'             nettest '<ret>'
# 1.9.5: ARP. The gateway answers; an address with nobody there does not.
check arp-self      '52:54:00:12:34:56'     'arp 10.0.2.15' '<ret>'
check arp-gw        '52:55:0a:00:02:02'     'arp 10.0.2.2' '<ret>' '<pause>'
check arp-none      'No reply'              'arp 10.0.2.99' '<ret>' '<pause>' '<pause>' '<pause>'
check arp-bad       'Bad address'           'arp nope' '<ret>'
check ping-gw       '4 of 4'                'ping 10.0.2.2' '<ret>' '<pause>'
# 1.9.8: the host answers one HTTP/1.0 GET; slirp delivers 10.0.2.2 to it
# FETCH_PORT picks the host port; by default a free one, so two runs at once do not clash
fetch_port=${FETCH_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}
python3 -u "$root/tools/fileserve.py" $fetch_port 'hello from squirrel' >"$out/fileserve.log" 2>&1 &
fetch_pid=$!
check fetch-hello   'hello from squirrel'   "fetch 10.0.2.2 $fetch_port /hello.txt" '<ret>' '<pause>' '<pause>' '<pause>'
kill $fetch_pid 2>/dev/null || true
wait $fetch_pid 2>/dev/null || true
# 3.0 (OS2-NET-AUDIO): DHCP from slirp; DNS and HTTP/1.1 from tools/netserve.py on the host
# (slirp delivers 10.0.2.2:<port> to 127.0.0.1:<port>); wget and netcfg on a disk of their own
python3 "$root/tools/sqfs.py" "$out/net.img" format 1024
for prog in wget netcfg; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
    python3 "$root/tools/sqfs.py" "$out/net.img" put "$out/$prog"
done
python3 -u "$root/tools/netserve.py" 18081 18053 >"$out/netserve.log" 2>&1 &
net_pid=$!
net_disk=$disk; disk=$out/net.img
ns='dns 10.0.2.2 18053'
check_all dhcp      'dhcp: bound|inet 10.0.2.15|mask 255.255.255.0|gw 10.0.2.2' 'ifconfig 10.0.2.99 255.255.0.0 10.0.2.9' '<ret>' dhcp '<ret>' '<pause>' '<pause>'
check dhcp-dns      'dns 10.0.2.3'          "$ns" '<ret>' dhcp '<ret>' '<pause>' '<pause>' dns '<ret>'
check host-name     'squirrel.test is 10.0.2.2'      "$ns" '<ret>' 'host squirrel.test' '<ret>' '<pause>'
check host-cname    'www.squirrel.test is 10.0.2.2'  "$ns" '<ret>' 'host www.squirrel.test' '<ret>' '<pause>'
check host-nx       'Host not found'        "$ns" '<ret>' 'host nothere.test' '<ret>' '<pause>'
check host-quad     '10.1.2.3 is 10.1.2.3'  'host 10.1.2.3' '<ret>'
check host-local    'localhost is 127.0.0.1' 'host localhost' '<ret>'
check ping-name     '4 of 4'                "$ns" '<ret>' 'ping squirrel.test' '<ret>' '<pause>' '<pause>'
check fetch-name    'hello from squirrel over HTTP/1.1' "$ns" '<ret>' 'fetch squirrel.test 18081 /hello.txt' '<ret>' '<pause>' '<pause>' '<pause>'
check wget-len      'wget: 200, 34 bytes, sum 2948 -> hello.txt' "$ns" '<ret>' 'run wget http://squirrel.test:18081/hello.txt' '<ret>' '<pause>' '<pause>'
check wget-saved    'hello from squirrel over HTTP/1.1' "$ns" '<ret>' 'run wget squirrel.test:18081/hello.txt' '<ret>' '<pause>' '<pause>' 'cat hello.txt' '<ret>'
check_all wget-chunked 'chunked transfer works|wget: 200, 23 bytes, sum 2247' "$ns" '<ret>' 'run wget squirrel.test:18081/chunked.txt -' '<ret>' '<pause>' '<pause>'
check wget-redirect 'wget: 200, 34 bytes, sum 2948 -> moved' "$ns" '<ret>' 'run wget http://www.squirrel.test:18081/moved' '<ret>' '<pause>' '<pause>'
check_none wget-404 'nope    ' 'wget: 404'  "$ns" '<ret>' 'run wget http://squirrel.test:18081/nope' '<ret>' '<pause>' '<pause>' ls '<ret>'
check wget-big      'wget: 200, 20000 bytes, sum 59120 -> big.bin' "$ns" '<ret>' 'run wget http://squirrel.test:18081/big.bin' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>'
check_all wget-headers 'Host: squirrel.test:18081|User-Agent: SquirrelOS2-wget/3.0' "$ns" '<ret>' 'run wget squirrel.test:18081/echo -' '<ret>' '<pause>' '<pause>'
check wget-nohost   'wget: host not found'  "$ns" '<ret>' 'run wget http://nothere.test/' '<ret>' '<pause>' '<pause>'
check wget-https    'wget: not an http:// URL' 'run wget https://squirrel.test/' '<ret>'
check_all netcfg-set 'method  manual|address 10.0.2.20|dns     10.0.2.2' 'run netcfg set 10.0.2.20 255.255.255.0 10.0.2.2 10.0.2.2' '<ret>'
check netcfg-offnet 'not on that subnet'    'run netcfg set 1.2.3.4 255.255.255.0 10.0.2.2 1.1.1.1' '<ret>'
check_all netcfg-load 'netcfg: saved network.cfg|address 10.0.2.21' 'run netcfg set 10.0.2.21 255.255.255.0 10.0.2.2 10.0.2.3' '<ret>' 'run netcfg save' '<ret>' 'run netcfg dhcp' '<ret>' '<pause>' 'run netcfg load' '<ret>'
check_all netcfg-gui-dhcp 'gfx: Network Settings|gfx: DHCP: bound|gfx: dhcp, lease 1440 min' 'ifconfig 10.0.2.99 255.255.255.0 10.0.2.2' '<ret>' 'run netcfg' '<ret>' '<pause>' '<f2>' '<pause>' '<pause>' '<gfx>'
check_all netcfg-gui-apply 'gfx: Applied|inet 10.0.2.77' 'run netcfg' '<ret>' '<pause>' '<backspace>' '<backspace>' '77' '<ret>' '<pause>' '<gfx>' '<esc>' '<pause>' ifconfig '<ret>'
disk=$net_disk
kill $net_pid 2>/dev/null || true
wait $net_pid 2>/dev/null || true
nic=
check dhcp-nonic    'No DHCP server answered' dhcp '<ret>'
check arp-nonic     'No reply'              'arp 10.0.2.2' '<ret>'
# 1.9.6: ICMP echo. Loopback does not need the card.
check ping-lo       '4 of 4'                'ping 127.0.0.1' '<ret>'
check ping-bad      'Bad address'           'ping nope' '<ret>'
check fetch-bad     'Bad address'           'fetch nope' '<ret>'
# 1.8.2: objtest.obj outlives a reboot; objcat prints class and fields (no classes registered yet)
check_all obj-persist 'class Square|0: 5|1: red' 'objcat objtest.obj' '<ret>'
# 1.7.6: the desktop's entries are Program objects; Enter sends open (files too)
check desktop-files 'gfx: Arrows PgUp/PgDn Home/End' \
                   desktop '<ret>' '<pause>' '<ret>' '<pause>' '<gfx>'
check desktop-files-back 'gfx: Squirrel-OS/2 Desktop' \
                   desktop '<ret>' '<pause>' '<ret>' '<pause>' '<esc>' '<pause>' '<gfx>'
check_all desktop-objs 'Program < DesktopObject|0 live' desktop '<ret>' '<pause>' '<esc>' objs '<ret>'
# Opening the desktop twice must not re-register DesktopObject/Program (obj_class is idempotent).
# check_once counts: a non-idempotent obj_class would print each class line twice and fail.
# "  DesktopObject" is the root class line (two spaces); it is not a substring of
# "Program < DesktopObject" (one space after "<").
check_once desktop-objs-2 'Program < DesktopObject|  DesktopObject|0 live' \
                   desktop '<ret>' '<pause>' '<esc>' desktop '<ret>' '<pause>' '<esc>' objs '<ret>'
# 2.3-groups: the Program Manager on a disk of its own (its places file in /desktop)
pm_disk=$disk
python3 "$root/tools/sqfs.py" "$out/pm.img" format 1024 >/dev/null
disk=$out/pm.img
check pmtest        'pm: PASS'              pmtest '<ret>' '<pause>'
check_all pm-groups 'gfx: Main|gfx: Tools|gfx: calc|gfx: draw' progman '<ret>' '<pause>' '<gfx>'
check_all pm-launch 'gfx: calc> 2 + 2|gfx: = 4' \
                   progman '<ret>' '<pause>' '<right>' '<ret>' '<pause>' '2 + 2' '<ret>' '<pause>' '<gfx>'
check pm-move       'calc 88 12'            progman '<ret>' '<pause>' '<right>' m '<right>' '<right>' '<down>' '<ret>' '<esc>' 'cat /desktop/progman.pos' '<ret>'
check pm-move-reboot 'calc 96 12'           progman '<ret>' '<pause>' '<right>' m '<right>' '<ret>' '<esc>' 'cat /desktop/progman.pos' '<ret>'
check pm-arrange    'calc 72 4'             progman '<ret>' '<pause>' a '<esc>' 'cat /desktop/progman.pos' '<ret>'
check pm-text       'systest: PASS'         progman '<ret>' '<pause>' '<esc>' systest '<ret>'
# 2.3-filemgr: the File Manager on a disk of its own: /w holds a.txt and sub
python3 "$root/tools/sqfs.py" "$out/fm.img" format 1024 >/dev/null
disk=$out/fm.img
check fmtest        'fm: PASS'              fmtest '<ret>'
check fm-setup      'sub/'                  'mkdir w' '<ret>' 'put w/a.txt hello' '<ret>' 'mkdir w/sub' '<ret>' 'ls w' '<ret>'
check_all fm-panes  'gfx: File Manager|gfx: sub|gfx: <dir>|gfx: a.txt' 'cd w' '<ret>' filemgr '<ret>' '<pause>' '<gfx>'
check fm-copy       'hello'                 'cd w' '<ret>' filemgr '<ret>' '<pause>' '<down>' c sub '<ret>' '<esc>' 'cat sub/a.txt' '<ret>'
check fm-rename     'hello'                 'cd w' '<ret>' filemgr '<ret>' '<pause>' '<down>' r b.txt '<ret>' '<esc>' 'cat b.txt' '<ret>'
check fm-move       'hello'                 'cd w' '<ret>' filemgr '<ret>' '<pause>' '<down>' m / '<ret>' '<esc>' 'cat /b.txt' '<ret>'
check fm-mkdir      '/w/new'                'cd w' '<ret>' filemgr '<ret>' '<pause>' n new '<ret>' '<esc>' 'cd new' '<ret>' pwd '<ret>'
check fm-delete     'Not found'             'cd w' '<ret>' filemgr '<ret>' '<pause>' '<ret>' '<delete>' y '<esc>' 'cat sub/a.txt' '<ret>'
check fm-menu       'Not found'             'put w/m.txt x' '<ret>' 'cd w' '<ret>' filemgr '<ret>' '<pause>' '<down>' '<down>' f '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' y '<esc>' 'cat m.txt' '<ret>'
check fm-text       'systest: PASS'         filemgr '<ret>' '<pause>' '<esc>' systest '<ret>'
disk=$pm_disk
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
# 1.9.1: m picks up, p drops into the folder shown (saved), Esc puts back
dd if=/dev/zero of="$out/dkmove.img" bs=1024 count=1024 2>/dev/null
disk=$out/dkmove.img
check_all dk-hold   'gfx: Held: calc|gfx: p: drop|gfx: Esc: back' desktop '<ret>' '<pause>' '<down>' m '<pause>' '<gfx>'
check_all dk-hold-esc "gfx: Squirrel-OS/2 Desktop|gfx: Esc: shell|in:${nl}entry: calc" \
                   desktop '<ret>' '<pause>' '<down>' m '<esc>' '<pause>' '<gfx>' '<esc>' 'objcat /desktop/calc.obj' '<ret>'
check_all dk-move   'gfx: Tools|gfx: calc|gfx: Esc: shell' \
                   desktop '<ret>' '<pause>' '<down>' m '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' p '<pause>' '<gfx>'
check_none dk-move-top 'gfx: calc' 'gfx: Squirrel-OS/2 Desktop' desktop '<ret>' '<pause>' '<gfx>'
check dk-move-cat   'in: Tools'             desktop '<ret>' '<pause>' '<esc>' 'objcat /desktop/calc.obj' '<ret>'
check dk-move-open  'gfx: = 4' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<ret>' '<pause>' '2 + 2' '<ret>' '<pause>' '<gfx>'
check_all dk-move-fold 'gfx: Held: Tools|gfx: Tools' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' m '<ret>' '<pause>' p '<pause>' '<gfx>'
# 1.9.2: r renames (a window with a field), Delete removes after y
dd if=/dev/zero of="$out/dkact.img" bs=1024 count=1024 2>/dev/null
disk=$out/dkact.img
check_all dk-rename-win 'gfx: Rename|gfx: edit' desktop '<ret>' '<pause>' '<down>' '<down>' r '<pause>' '<gfx>'
check_all dk-rename 'gfx: notes|name: notes|entry: edit' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' r '<backspace>' '<backspace>' '<backspace>' '<backspace>' notes '<ret>' '<pause>' '<gfx>' '<esc>' 'objcat /desktop/edit.obj' '<ret>'
check dk-rename-esc 'gfx: notes' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' r '<backspace>' x '<esc>' '<pause>' '<gfx>'
check dk-delete-ask 'gfx: Delete notes? y: yes' desktop '<ret>' '<pause>' '<down>' '<down>' '<delete>' '<pause>' '<gfx>'
check dk-delete-no  'gfx: notes'            desktop '<ret>' '<pause>' '<down>' '<down>' '<delete>' n '<pause>' '<gfx>'
check_none dk-delete "${nl}edit.obj" 'calc.obj' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<delete>' y '<pause>' '<esc>' 'ls /desktop' '<ret>'
check dk-delete-full 'gfx: Not empty' \
                   desktop '<ret>' '<pause>' '<down>' m '<down>' '<down>' '<down>' '<ret>' '<pause>' p '<backspace>' '<pause>' '<down>' '<down>' '<down>' '<delete>' '<pause>' '<gfx>'
# deleting the last slot (the empty Tools folder on a fresh desktop)
dd if=/dev/zero of="$out/dkdel.img" bs=1024 count=1024 2>/dev/null
disk=$out/dkdel.img
check_all dk-delete-last 'gfx: files|gfx: calc|gfx: edit|gfx: vedit|gfx: draw|gfx: Esc: shell' \
                   desktop '<ret>' '<pause>' '<down>' '<down>' '<down>' '<down>' '<down>' '<delete>' y '<pause>' '<gfx>'
check_none dk-delete-last-ls "${nl}Tools.obj" 'draw.obj' 'ls /desktop' '<ret>'
check_all dk-delete-last-again 'gfx: draw|gfx: Squirrel-OS/2 Desktop' desktop '<ret>' '<pause>' '<gfx>'
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
check ver-banner    'Squirrel-OS/2 2.1.0'  systest '<ret>'
check ver-planned   '(planned: topo)'  systest '<ret>'
check calc-hist-root '1 + 1 = 2'            'mkdir c1' '<ret>' 'cd c1' '<ret>' 'run calc' '<ret>' '1 + 1' '<ret>' '<esc>' 'cat /calc.hist' '<ret>'
boot="--floppy $out/floppy.img"
check floppy-boot   'systest: PASS'         '<pause>' '<pause>' systest '<ret>'
check floppy-data   'kept'                  '<pause>' '<pause>' 'cat keep/note' '<ret>'
check floppy-e820   'usable'                '<pause>' '<pause>' mem '<ret>'
check floppy-khigh  '= 42'                  '<pause>' '<pause>' 'run calc' '<ret>' '6 * 7' '<ret>'   # 2.4: calc lives in the high image
# installer I.6: the CD image (El Torito floppy emulation around floppy.img) boots to the shell
boot="--cdrom $out/cd.iso"
check cd-boot       'systest: PASS'         '<pause>' '<pause>' systest '<ret>'
check cd-data       'kept'                  '<pause>' '<pause>' 'cat keep/note' '<ret>'
check cd-khigh      '= 42'                  '<pause>' '<pause>' 'run calc' '<ret>' '6 * 7' '<ret>'
# 2.4: the kernel's high image runs at 1 MB; the page allocator starts above it
head -c $((193 * 512)) "$out/os.img" > "$out/lowonly.img"   # the low image only
boot="$out/lowonly.img"
check khigh-missing 'cannot read the high kernel image'
boot=
check khigh-mem     'Pages above 2 MB:'     mem '<ret>'
# 2.8-smp-ap: the APs from the ACPI MADT start and park; one CPU is still fine
check cpus-one      '1 CPU(s) online'       cpus '<ret>'
export QEMU_EXTRA='-smp 4'
check_all smp-4     'CPU 0: APIC id 0, boot processor|CPU 3: APIC id 3, online|4 CPU(s) online' cpus '<ret>'
check smp-4-systest 'systest: PASS'         cpus '<ret>' systest '<ret>'
unset QEMU_EXTRA
# 2.8-lm-entry: a round trip through long mode (qemu-system-x86_64), and a clean refusal without it
export QEMU_BIN=qemu-system-x86_64
check lm-test       'lm: PASS'              lmtest '<ret>'
check_all lm-again  'lm: PASS|systest: PASS' lmtest '<ret>' lmtest '<ret>' systest '<ret>'
unset QEMU_BIN
check lm-nolm       'lm: no long mode'      lmtest '<ret>'
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
# P.1/P.2: Linux i386 programs (EI_OSABI 3) through the Linux personality
check lx-hello      'lxhello: PASS'         'run lxhello' '<ret>'
check lx-argv       'argc=2 argv[0]=lxhello acorn'  'run lxhello acorn' '<ret>'
check lx-file       'lxfile: PASS'          'run lxfile' '<ret>'
check lx-pipe       'lx: acorns'            'echo acorns | run lxcat' '<ret>'
check lx-then-native 'Hello from a loaded program!'  'run lxhello' '<ret>' 'run hello' '<ret>'
check lx-sys        'lxsys: PASS'           'run lxsys' '<ret>'
check lx-uname      'lxsys: uname Linux i686'       'run lxsys' '<ret>'
# P.5: Win32 PE32 console programs through winrun
check win-hello     'winhello: PASS'        'run winhello' '<ret>'
check win-cmdline   'command line: winhello nuts'   'run winhello nuts' '<ret>'
check win-missing   'not implemented: Beep' 'run winhello beep' '<ret>'
check win-notpe     'not a valid PE file'   'run winrun lxhello' '<ret>'
check win-crt       'wincrt: PASS'          'run wincrt acorn' '<ret>'
check win-printf    'crt: -5 acorn 00ab x  |'       'run wincrt acorn' '<ret>'
check ld-notprog    'Not a program'         'run notes' '<ret>'
check ld-big        'too big'               'run huge' '<ret>'
check ld-missing    'Unknown command or program'    'run nothere' '<ret>'
check ld-again      'Argument: 2'           'run hello 1' '<ret>' 'run hello 2' '<ret>'
check_all progwin  'progwin key: x|progwin: PASS' 'run winprog' '<ret>' '<pause>' '<pause>' x '<pause>' '<alt-f4>' '<pause>' '<pause>'   # 2.2-progwin
check progwin-text  'systest: PASS'         'run winprog' '<ret>' '<pause>' '<pause>' x '<pause>' '<alt-f4>' '<pause>' '<pause>' systest '<ret>'
check ld-browser    'Hello from a loaded'   'run files' '<ret>' '<home>' '<ret>'
check ld-host-ls    'elfhello'              'run ls elf' '<ret>'
check vm-nest       'own memory intact'     'run nest' '<ret>'
check vm-nest-child 'Argument: from nest'   'run nest' '<ret>'
check vm-crash      'Program ended: pid'    'run crash' '<ret>'
check vm-crash-addr 'address=C0000000 (read, page not present)'  'run crash' '<ret>'
check crash-name    'in pid 1 (crash)'      'run crash' '<ret>'
check crash-regs    'EAX=00000022'          'run crash' '<ret>'
check vm-after      'systest: PASS'         'run crash' '<ret>' systest '<ret>'
check vm-no-leak    '128888 KB free'        'run nest' '<ret>' 'run crash' '<ret>' 'run hello' '<ret>' mem '<ret>'
check vm-ps         'kernel'                ps '<ret>'
check heap          'heap: PASS (1024 KB)'  'run heap' '<ret>'
check heap-limit-after 'Program ended: pid'  'run heap after' '<ret>'
check heap-keep-leak '128888 KB free'       'run heap keep' '<ret>' 'run heap after' '<ret>' mem '<ret>'
# 1.0.1: each process keeps its own x87 registers across a switch
check fpu-switch    'fpu: PASS'             'run fpu' '<ret>' '<pause>'
# 1.0.2: SYS_SEEK
check seek          'seek: PASS'            'run seek' '<ret>' '<pause>'
check devices       'hd1     block   ready 2048 sectors'  devices '<ret>'
check devices-ro    '(read-only for programs)'  devices '<ret>'
check devtest       'devtest: PASS'         'run devtest' '<ret>'
check up-ls         '42 file(s)'             'run ls' '<ret>'   # 30 + smpspin (2.8) + winprog + the 7 P.1-P.5 programs + lxfile.txt, win.txt, crt.txt
# 1.2.1: a key arrives as a queue event as well as through SYS_GETC
check_all keyev     'keyev: queue q getc q|keyev: PASS'  'run keyev' '<ret>' '<pause>' q '<pause>'
check_all keyev-shift 'keyev: queue Q getc Q|keyev: PASS'  'run keyev' '<ret>' '<pause>' Q '<pause>'
# 1.2.0: message queues between processes
check_all msg       'msg: queue full (-2)|msg: child got ping|msg: PASS'  'run msg' '<ret>' '<pause>'
# 1.1.1: a spawn in the program's own image is a thread sharing its memory
check thread        'thread: PASS'          'run thread' '<ret>'
# 1.9.7: UDP to itself on loopback, and a second process is refused the port
check udp           'udp: PASS'             'run udptest' '<ret>'
# KB-16: a wait that closes a cycle of waits returns -1 instead of a kernel panic
check waitcycle     'waitcycle: PASS'       'run waitcycle' '<ret>'
check_all stackover '*** stack overflow in pid|Program ended|stackover: PASS'  'run stackover' '<ret>'
# 2.4: programs run in ring 3; bad pointers, kernel memory and privileged instructions are refused
check_all ring3     '*** CPU exception 13 (general protection) in pid|Program ended|ring3: PASS'  'run ring3' '<ret>' '<pause>'
check ring3-after   'systest: PASS'         'run ring3' '<ret>' '<pause>' systest '<ret>'
# 2.8-smp-sched: ring-3 threads on the application processors; kernel entries go to the BSP
check_all smpspin-1 'smpspin: 1 CPU(s)|smpspin: threads ok'  'run smpspin' '<ret>' '<pause>' '<pause>' '<pause>'
export QEMU_EXTRA='-smp 4'
check_all smpspin-4 'smpspin: 4 CPU(s)|smpspin: threads ok'  'run smpspin 4' '<ret>' '<pause>' '<pause>' '<pause>'
check smp-ring3     'ring3: PASS'           'run ring3' '<ret>' '<pause>' '<pause>'
check smp-stackover 'stackover: PASS'       'run stackover' '<ret>' '<pause>'
check smp-thread    'thread: PASS'          'run thread' '<ret>' '<pause>'
check smp-msg       'msg: PASS'             'run msg' '<ret>' '<pause>'
check smp-fpu       'fpu: PASS'             'run fpu' '<ret>' '<pause>'
check smp-preempt   'preempt: PASS'         'run spin' '<ret>' '<pause>'
check smp-heap      'heap: PASS'            'run heap' '<ret>' '<pause>'
check smp-after     'systest: PASS'         'run smpspin 4' '<ret>' '<pause>' '<pause>' '<pause>' systest '<ret>'
unset QEMU_EXTRA
# 1.1.0: the timer preempts a program that spins without a system call
check_all sched-preempt 'spin: second process ran|preempt: PASS' 'run spin' '<ret>' '<pause>'
check up-ls-filter  '6 file(s)'             'run ls he' '<ret>'
# 1.0.3: programs read why a file call failed (SYS_FSERROR), in the shell's words
check errno-nf      'errno: Not found'      'run errno missing' '<ret>'
check errno-dir     'errno: Is a directory' 'mkdir edir' '<ret>' 'run errno edir' '<ret>'
# 1.0.4: zombies nobody waits for do not fill the process table
check zombie        'zombie: PASS'          'run zombie' '<ret>' '<pause>'
check zombie-ps     '2 10 93'               'run zombie' '<ret>' '<pause>' 'ps | run wc' '<ret>'   # header + shell only (prio column)
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
check lang-banner   'Sciurus-OS/2 2.1.0'   'lang la' '<ret>' 'run calc' '<ret>' '<esc>'
# 1.9.9: higher priority keeps a lower-priority child from running
check prio          'prio: PASS'            'run priotest' '<ret>' '<pause>'
# 2.0.2: aging lets a priority-0 child run beside a priority-3 spinner
check age           'age: PASS'             'run agetest' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>'
# 1.9.10: polled mouse sees motion from the QEMU monitor
check mousetest     'mouse: PASS'           mousetest '<ret>' '<pause>' '<mouse-move:12,-8>' '<pause>'
# 2.0.1: mousetest no longer polls, so a still mouse fails; motion and
# clicks in the text shell no longer block the keyboard (KB-18)
# 2.0.1: 9-bit motion and overflow bits, from fixed packets
check mouse-decode  'decode: PASS'          mousetest '<ret>' '<pause>'
check mouse-still   'mouse: FAIL'           mousetest '<ret>' '<pause>' '<pause>' '<pause>'
check mouse-shell   'systest: PASS'         '<mouse-move:10,5>' '<pause>' '<mouse-move:-3,4>' '<mouse-btn:1>' '<mouse-btn:0>' '<pause>' systest '<ret>'
check mouse-calc    '= 42'                  'run calc' '<ret>' '<mouse-move:20,20>' '<pause>' '6*7' '<ret>'
# 2.0.1: the pointer keeps the pixels under it, so it leaves no trail
check ptrtest       'ptr: PASS'             ptrtest '<ret>' '<pause>'
check ptr-trail     'gfx: files'            desktop '<ret>' '<pause>' '<mouse-move:0,-40>' '<pause>' \
                    '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:-8,0>' '<pause>' '<mouse-move:0,-60>' '<pause>' '<gfx>'
# 1.9.11: show and set the guest address
check ifconfig      'inet 10.0.2.15'        ifconfig '<ret>'
check_all ifconfig-set 'inet 10.0.2.20|mask 255.255.255.0|gw 10.0.2.2' 'ifconfig 10.0.2.20 255.255.255.0 10.0.2.2' '<ret>'
# 2.0.2: a gateway off the subnet is refused and nothing changes
check ifconfig-offnet 'Gateway is not on that subnet' 'ifconfig 10.0.2.20 255.255.255.0 192.168.1.1' '<ret>'
check_all ifconfig-offnet-keep 'inet 10.0.2.15|gw 10.0.2.2' 'ifconfig 10.0.2.20 255.255.255.0 192.168.1.1' '<ret>' ifconfig '<ret>'
check ifconfig-offnet-la 'Porta non est in hac subrete' 'lang la' '<ret>' 'ifconfig 10.0.2.20 255.255.255.0 192.168.1.1' '<ret>'
# 1.9.12: register a null device at run time
check drv           'drv: PASS'             'run drvtest' '<ret>'
# 2.0.2: drvtest removes its device again (SYS_DEVUNREG), so it passes every
# time, past the four run-time slots, and devices no longer lists it
check_none drv-devices 'null    char' 'con     char' 'run drvtest' '<ret>' devices '<ret>'
check_none drv-again 'drv: FAIL' 'drv: PASS' 'run drvtest' '<ret>' 'run drvtest' '<ret>' 'run drvtest' '<ret>' 'run drvtest' '<ret>' 'run drvtest' '<ret>' 'run drvtest' '<ret>'
# OS2-GAMES: each game's rules self-check, then a short scripted game
disk=$out/games.img
check mines-test    'mines: PASS'           'run mines test' '<ret>'
check_all mines-play '  1 F |Mines left: 9' 'run mines 5' '<ret>' e5 '<ret>' 'f a1' '<ret>'
check reversi-test  'reversi: PASS'         'run reversi test' '<ret>' '<pause>' '<pause>'
check_all reversi-play 'Computer plays c3|You (X): 3   Computer (O): 3' 'run reversi 1' '<ret>' d3 '<ret>'
check klondike-test 'klondike: PASS'        'run klondike test' '<ret>'
check_all klondike-play 'Stock 23|That move is not allowed' 'run klondike 3' '<ret>' d '<ret>' 12 '<ret>'
check freecell-test 'freecell: PASS'        'run freecell test' '<ret>'
check freecell-play 'Cells (a b c d) 9C  -  -  -' 'run freecell 2' '<ret>' 1a '<ret>'
check hearts-test   'hearts: PASS'          'run hearts test' '<ret>' '<pause>'
check_all hearts-play 'You received:  JH  6H  4H|North plays 2C|You cannot play that card now' 'run hearts 3' '<ret>' 'ah kh jc' '<ret>' 2s '<ret>'
check chess-test    'chess: PASS'           'run chess test' '<ret>' '<pause>' '<pause>'
check_all chess-pgn '[Black "Squirrel Chess"]|1. e4 d5 *' 'run chess 1' '<ret>' e2e4 '<ret>' '<pause>' 'save g.pgn' '<ret>' q '<ret>' 'cat g.pgn' '<ret>'
check mahjongg-test 'mahjongg: PASS'        'run mahjongg test' '<ret>' '<pause>'
check_all mahjongg-play 'Try j1 a3|Tiles left: 106' 'run mahjongg 2' '<ret>' h '<ret>' 'j1 a3' '<ret>'
check bridge-test   'bridge: PASS'          'run bridge test' '<ret>' '<pause>'
check_all bridge-play 'S pass  W pass  N 1H  E pass  S 3H|Contract: 3H by North|Trick: East AS|Play from South' 'run bridge 1' '<ret>' p '<ret>' 3h '<ret>'
# OS2-GAMES: the graphical front ends (run <game> gui [seed]), read off the screen
check klondike-gui  'gfx: That move is not allowed' 'run klondike gui 3' '<ret>' '<pause>' '<ret>' '<right>' '<ret>' '<pause>' '<gfx>'
check freecell-gui  'gfx: That move is not allowed' 'run freecell gui 2' '<ret>' '<pause>' '<ret>' '<right>' '<ret>' '<pause>' '<gfx>'
check hearts-gui    'gfx: You got JH 6H 4H - click to go on' 'run hearts gui 3' '<ret>' '<pause>' ' ' '<right>' ' ' '<right>' ' ' '<ret>' '<pause>' '<gfx>'
check_all mines-gui 'gfx: Mines left: 9|gfx: Click or Enter: open' 'run mines gui 5' '<ret>' '<pause>' '<ret>' '<up>' '<up>' '<up>' '<up>' '<left>' '<left>' '<left>' '<left>' f '<pause>' '<gfx>'
check mines-gui-big 'gfx: Boom! You hit a mine.' 'run mines gui 5 big' '<ret>' '<pause>' '<ret>' '<down>' '<down>' '<down>' '<ret>' '<pause>' '<gfx>'
check_all reversi-gui 'gfx: You 3|gfx: Computer 3' 'run reversi gui 1' '<ret>' '<pause>' '<ret>' '<pause>' '<pause>' '<gfx>'
check_all chess-gui 'gfx: You: e4|gfx: d5' 'run chess gui 1' '<ret>' '<pause>' '<ret>' '<up>' '<up>' '<ret>' '<pause>' '<pause>' '<pause>' '<gfx>'
check mahjongg-gui  'gfx: Tiles left: 106' 'run mahjongg gui 2' '<ret>' '<pause>' '<right>' '<right>' '<right>' '<right>' '<right>' '<right>' '<right>' '<right>' '<right>' '<ret>' '<down>' '<down>' '<left>' '<left>' '<left>' '<left>' '<left>' '<left>' '<left>' '<left>' '<left>' '<ret>' '<pause>' '<gfx>'
check checkers-test 'checkers: PASS'        'run checkers test' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>'
check_all checkers-play 'Computer plays f6-g5|You (b): 12   Computer (w): 12' 'run checkers 1' '<ret>' c3d4 '<ret>' '<pause>' '<pause>'
check go-test       'go: PASS'              'run go test' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>'
check_all go-play   'Computer plays f3|You cannot play there' 'run go 1' '<ret>' e5 '<ret>' e5 '<ret>'
disk=$out/progs.img
# 1.0.6: calc, edit and draw titles follow lang
check l10n-calc-tlh "mI' De'wI' (Esc to exit)" 'lang tlh' '<ret>' 'run calc' '<ret>'
check l10n-edit-tlh "ghItlhwI': (untitled)" 'lang tlh' '<ret>' 'run edit' '<ret>'
check l10n-draw-la  'Programma pingendi - ASCII canvas' 'lang la' '<ret>' 'run draw' '<ret>'
check l10n-calc-en  'Basic Calculator (Esc to exit)' 'run calc' '<ret>'
check lang-systest  'systest: PROBATUM'     'lang la' '<ret>' systest '<ret>'
# OS2-APPS: graphics for programs (SYS_GUI, programs/gui.inc) and the A.1 apps
disk=$out/apps.img
# 2.3-clipboard: cbtest leaves "clip me" on the clipboard; the viewer shows it
check_all clip-viewer 'gfx: Clipboard|gfx: clip me' cbtest '<ret>' 'run clipbrd' '<ret>' '<pause>' '<pause>' '<gfx>' q '<pause>'
check clip-viewer-n 'clipbrd: 7 bytes'      cbtest '<ret>' 'run clipbrd' '<ret>' '<pause>' '<pause>' q '<pause>'
check_all clip-empty 'gfx: (empty)|clipbrd: 0 bytes' 'run clipbrd' '<ret>' '<pause>' '<pause>' '<gfx>' q '<pause>'
check guitest       'guitest: PASS'         'run guitest' '<ret>' '<pause>'
check_all guitest-gfx 'gfx: Gui test|gfx: Hello from a program' 'run guitest hold' '<ret>' '<pause>' '<gfx>'
check_all calculator 'gfx: Calculator|gfx: 2+3*4|gfx: = 14' 'run calculator' '<ret>' '<pause>' '2+3*4' '<ret>' '<pause>' '<gfx>'
check calculator-ans 'gfx: = 28'            'run calculator' '<ret>' '<pause>' '2+3*4' '<ret>' '*2' '<ret>' '<pause>' '<gfx>'
check_all calculator-err 'gfx: Error: division by|gfx: zero' 'run calculator' '<ret>' '<pause>' '1/0' '<ret>' '<pause>' '<gfx>'
check_all calculator-syn 'gfx: Error: syntax at|gfx: column 4' 'run calculator' '<ret>' '<pause>' '2*(' '<ret>' '<pause>' '<gfx>'
check calculator-keys 'gfx: = 45'           'run calculator' '<ret>' '<pause>' '<spc>' '<right>' '<spc>' '<ret>' '<pause>' '<gfx>'
check_all calculator-sci 'gfx: sin|gfx: DEG|gfx: = 0.5' 'run calculator' '<ret>' '<pause>' '<tab>' '<f2>' 'sin(30)' '<ret>' '<pause>' '<gfx>'
check calculator-quit 'systest: PASS'       'run calculator' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check clock         'clock: PASS'           'run clock test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all clock-gfx 'gfx: Clock|gfx: 20'    'run clock' '<ret>' '<pause>' '<gfx>'
check clock-quit    'systest: PASS'         'run clock' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check_all notepad   'gfx: Notepad - memo|gfx: Hello notepad!|gfx: second line|gfx: Ln 1 Col 15' \
                    'run notepad memo' '<ret>' '<pause>' 'Hello notepad' '<ret>' 'second line' '<up>' '<end>' '!' '<pause>' '<gfx>'
check notepad-save  'Hello notepad!'        'run notepad memo' '<ret>' '<pause>' 'Hello notepad!' '<ctrl-s>' '<pause>' '<esc>' '<pause>' 'cat memo' '<ret>'
check notepad-open  'gfx: Hello notepad!'   'run notepad memo' '<ret>' '<pause>' '<gfx>'
check notepad-ask   'gfx: Save changes? y/n' 'run notepad' '<ret>' '<pause>' 'x' '<esc>' '<pause>' '<gfx>'
check notepad-quit  'systest: PASS'         'run notepad' '<ret>' '<pause>' 'x' '<esc>' 'n' '<pause>' systest '<ret>'
check notepad-hl    'notepad: PASS'         'run notepad -test' '<ret>' '<pause>' '<pause>'
# C.2: grapher (explicit, polar, parametric, implicit, inequalities, sliders; roots, extrema, intersections, trace)
check grapher       'grapher: PASS'         'run grapher test' '<ret>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>' '<pause>'
check_all grapher-roots 'gfx: 1: sin(x)|gfx: roots: -9.4248|gfx: -3.1416' 'run grapher sin(x)' '<ret>' '<pause>' 'z' '<pause>' '<gfx>'
check_all grapher-ext 'gfx: min(-7.854, -1)|gfx: max(-4.7124, 1)' 'run grapher sin(x)' '<ret>' '<pause>' 'm' '<pause>' '<gfx>'
check_all grapher-meet 'gfx: meet: (-1, 0)|gfx: (2, 3)' 'run grapher x^2-1' '<ret>' '<pause>' '<tab>' '<ret>' 'y = x + 1' '<ret>' '<tab>' '<tab>' '<tab>' 'i' '<pause>' '<gfx>'
check_all grapher-trace 'gfx: 2: x = 4*cos(t), y = 2*sin(t)|gfx: t=0.0262|gfx: x=3.9986' 'run grapher' '<ret>' '<pause>' 'sin(x)' '<ret>' '<tab>' '<ret>' 'x = 4*cos(t), y = 2*sin(t)' '<ret>' 't' '<right>' '<pause>' '<gfx>'
check grapher-zoom  'gfx: roots: -3.1416'   'run grapher sin(x)' '<ret>' '<pause>' '+' 'z' '<pause>' '<gfx>'
check grapher-syn   'gfx: Error: syntax at column 4' 'run grapher' '<ret>' '<pause>' 'y = 2*(' '<ret>' '<pause>' '<gfx>'
check grapher-quit  'systest: PASS'         'run grapher sin(x)' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check_all grapher-impl 'gfx: 1: x^2+y^2=25|gfx: only for y = f(x)' 'run grapher x^2+y^2=25' '<ret>' '<pause>' '<pause>' 'z' '<pause>' '<gfx>'
check_all grapher-ineq 'gfx: 1: y >= x^2|gfx: Trace is for y =, r = and x =, y =' 'run grapher' '<ret>' '<pause>' 'y >= x^2' '<ret>' '<pause>' 't' '<pause>' '<gfx>'
check grapher-slider 'gfx: a = 2.2'         'run grapher y=a*sin(x)' '<ret>' '<pause>' 'a' '<pause>' '<right>' '<pause>' '<right>' '<pause>' '<up>' '<pause>' '<pause>' '<gfx>'
check grapher-form  'gfx: Use y = f(x), r = f(t), x = f(t), y = g(t), = < >' 'run grapher' '<ret>' '<pause>' 'y < x < 2' '<ret>' '<pause>' '<gfx>'
# A.2: character map, paint, image viewer
check_all charmap   'gfx: Character map|gfx: AB~|gfx: 0x7E|gfx: 126' 'run charmap' '<ret>' '<pause>' '<ret>' '<right>' '<ret>' 'z' '<down>' '<ret>' '<pause>' '<gfx>'
check charmap-save  'AB~'                   'run charmap' '<ret>' '<pause>' '<ret>' '<right>' '<ret>' 'z' '<down>' '<ret>' '<f2>' '<pause>' '<esc>' '<pause>' 'cat charmap.txt' '<ret>'
check paint         'paint: PASS'           'run paint test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all paint-keys 'gfx: Paint - pic.bmp|gfx: Saved' 'run paint' '<ret>' '<pause>' 's' '<spc>' '<ctrl-right>' '<ctrl-down>' '<spc>' '<ctrl-s>' 'pic.bmp' '<ret>' '<pause>' '<gfx>'
check_all paint-open 'gfx: Paint - pic.bmp|gfx: Opened' 'run paint pic.bmp' '<ret>' '<pause>' '<pause>' '<gfx>'
check paint-quit    'systest: PASS'         'run paint' '<ret>' '<pause>' '<spc>' '<esc>' '<esc>' 'n' '<pause>' systest '<ret>'
check_all viewer    'viewer: ptest.bmp 272 x 160, 8 bits|viewer: PASS' 'run viewer ptest.bmp test' '<ret>' '<pause>' '<pause>'
check_all viewer-24 'viewer: grad.bmp 64 x 48, 24 bits|viewer: PASS' 'run viewer grad.bmp test' '<ret>' '<pause>' '<pause>'
check_all viewer-gfx 'gfx: grad.bmp|gfx: 64 x 48, 24 bits|gfx: 2:1' 'run viewer grad.bmp' '<ret>' '<pause>' '<pause>' '+' '<pause>' '<gfx>'
check viewer-bad    'viewer: not an 8- or 24-bit BMP, or not found' 'run viewer nosuch.bmp' '<ret>'
check viewer-quit   'systest: PASS'         'run viewer grad.bmp' '<ret>' '<pause>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# C.9: topology (Betti numbers over Z/2 and Q) and the matrix calculator
check topology      'topology: PASS'        'run topology test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all topology-gfx 'gfx: Torus|gfx: V 7|gfx: Euler characteristic 0|gfx: Betti over Z/2: 1 2 1' 'run topology' '<ret>' '<pause>' '<pause>' '<gfx>'
check_all topology-rp2 'gfx: Betti over Z/2: 1 1 1|gfx: Betti over Q:|gfx: 1 0 0|gfx: Z/2 and Q differ: 2-torsion' 'run topology' '<ret>' '<pause>' '<down>' '<down>' '<pause>' '<gfx>'
check_all topology-custom 'gfx: V 4|gfx: E 5|gfx: F 2|gfx: Euler characteristic 1' 'run topology' '<ret>' '<pause>' '<tab>' '<delete>' '0 1 2, 1 2 3' '<ret>' '<pause>' '<gfx>'
check topology-bad  'gfx: Vertices are 0 to 15' 'run topology' '<ret>' '<pause>' '<tab>' '0 99' '<ret>' '<pause>' '<gfx>'
check matrixgui     'matrixgui: PASS'       'run matrixgui test' '<ret>' '<pause>' '<pause>'
check_all matrixgui-mul 'gfx: A * B =|gfx: 19|gfx: 22|gfx: 43|gfx: 50' 'run matrixgui' '<ret>' '<pause>' '1' '<right>' '2' '<down>' '4' '<left>' '3' '<ret>' '<tab>' '<up>' '5' '<right>' '6' '<down>' '8' '<left>' '7' '<ret>' '*' '<pause>' '<gfx>'
check_all matrixgui-inv 'gfx: inv A =|gfx: -2|gfx: 1.5|gfx: -0.5' 'run matrixgui' '<ret>' '<pause>' '1' '<right>' '2' '<down>' '4' '<left>' '3' '<ret>' 'i' '<pause>' '<gfx>'
check matrixgui-det 'gfx: det A = -2'      'run matrixgui' '<ret>' '<pause>' '1' '<right>' '2' '<down>' '4' '<left>' '3' '<ret>' 'd' '<pause>' '<gfx>'
check matrixgui-sing 'gfx: The matrix is singular' 'run matrixgui' '<ret>' '<pause>' 'i' '<pause>' '<gfx>'
check matrixgui-quit 'systest: PASS'        'run matrixgui' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# C.3: statistics (lists, one- and two-variable statistics, regressions, histogram, box plot, CSV)
check stats         'stats: PASS'           'run stats test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all stats-one 'gfx: n = 5|gfx: mean = 3|gfx: sx = 1.581139|gfx: Q1 = 1.5|gfx: Q3 = 4.5' 'run stats' '<ret>' '<pause>' '1' '<ret>' '2' '<ret>' '3' '<ret>' '4' '<ret>' '5' '<ret>' 'v' '<pause>' '<gfx>'
check_all stats-reg 'gfx: linear: y = a*x + b|gfx: a = 0.6|gfx: b = 2.2|gfx: r^2 = 0.6' 'run stats' '<ret>' '<pause>' '1' '<ret>' '2' '<ret>' '3' '<ret>' '4' '<ret>' '5' '<ret>' '<tab>' '2' '<ret>' '4' '<ret>' '5' '<ret>' '4' '<ret>' '5' '<ret>' 'r' '<pause>' '<gfx>'
check_all stats-quad 'gfx: quadratic: y=a*x^2+b*x+c|gfx: a = -0.285714|gfx: b = 2.314286|gfx: c = 0.2' 'run stats' '<ret>' '<pause>' '1' '<ret>' '2' '<ret>' '3' '<ret>' '4' '<ret>' '5' '<ret>' '<tab>' '2' '<ret>' '4' '<ret>' '5' '<ret>' '4' '<ret>' '5' '<ret>' 'r' 'r' '<pause>' '<gfx>'
check stats-differ  'gfx: L1 and L2 must have the same length' 'run stats' '<ret>' '<pause>' '1' '<ret>' '2' '<ret>' 'x' '<pause>' '<gfx>'
check_all stats-csv 'gfx: Saved|gfx: n = 2|gfx: mean = 7.5' 'run stats' '<ret>' '<pause>' '7' '<ret>' '8' '<ret>' '<ctrl-s>' '<pause>' '<gfx>' '<esc>' '<pause>' 'run stats stats.csv' '<ret>' '<pause>' 'v' '<pause>' '<gfx>'
check stats-quit    'systest: PASS'         'run stats' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# C.7: 3D graphing (surfaces, space curves)
check graph3d       'graph3d: PASS'         'run graph3d test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all graph3d-surf 'gfx: sin(x)*cos(y)|gfx: x, y: -3 to 3|gfx: z: -0.9975 to 0.9975' 'run graph3d sin(x)*cos(y)' '<ret>' '<pause>' '<left>' '<up>' '<pause>' '<gfx>'
check_all graph3d-curve 'gfx: t: 0 to 2 pi|gfx: z: 0 to 1.2566' 'run graph3d' '<ret>' '<pause>' 'x = cos(t), y = sin(t), z = t/5' '<ret>' '<pause>' '<gfx>'
check_all graph3d-size 'gfx: x, y: -6 to 6|gfx: z: 0 to 72' 'run graph3d x^2+y^2' '<ret>' '<pause>' '<pgup>' '<pause>' '<gfx>'
check graph3d-syn   'gfx: Error: syntax at column 4' 'run graph3d' '<ret>' '<pause>' 'z = x*(' '<ret>' '<pause>' '<gfx>'
check graph3d-quit  'systest: PASS'         'run graph3d x*y' '<ret>' '<pause>' 'w' '<pause>' '<esc>' '<pause>' systest '<ret>'
# A.7: hex editor
check hexedit       'hexedit: PASS'         'run hexedit test' '<ret>' '<pause>' '<pause>'
check_all hexedit-view 'gfx: Hex: htest.bin|gfx: 00020: 20 21 22 23 24 25 26 27|gfx: @00011 = AB 171' 'run hexedit htest.bin' '<ret>' '<pause>' '<down>' '<down>' '<right>' '<pause>' '<gfx>'
check hexedit-goto  'gfx: @00080 = 80 128'  'run hexedit htest.bin' '<ret>' '<pause>' '<ctrl-g>' '80' '<ret>' '<pause>' '<gfx>'
check_all hexedit-new 'gfx: Saved|gfx: @00000 = 41 65' 'run hexedit hnew.bin' '<ret>' '<pause>' '4' '1' '4' '2' '<ctrl-s>' '<pause>' '<gfx>' '<esc>' '<pause>' 'run hexedit hnew.bin' '<ret>' '<pause>' '<gfx>'
check hexedit-quit  'systest: PASS'         'run hexedit htest.bin' '<ret>' '<pause>' '7' '<esc>' '<pause>' 'n' '<pause>' systest '<ret>'
check hexedit-usage 'usage: run hexedit <file>' 'run hexedit' '<ret>'
# A.7: word processor
check write         'write: PASS'           'run write test' '<ret>' '<pause>' '<pause>'
check_all write-count 'gfx: Write - wdoc.swp|gfx: words 5|gfx: chars 22 *' 'run write wdoc.swp' '<ret>' '<pause>' 'Two words' '<ret>' 'and two more' '<pause>' '<gfx>'
check_all write-styles 'gfx: Opened|gfx: Centred line' 'run write wdoc.swp' '<ret>' '<pause>' 'Plain ' '<ctrl-i>' 'italic ' '<ctrl-i>' '<ctrl-u>' 'under' '<ctrl-u>' '<ret>' 'Centred line' '<ctrl-e>' '<ctrl-s>' '<pause>' '<esc>' '<pause>' 'run write wdoc.swp' '<ret>' '<pause>' '<pause>' '<gfx>'
check write-ask     'gfx: Save changes? y/n' 'run write' '<ret>' '<pause>' 'x' '<esc>' '<pause>' '<gfx>'
check write-quit    'systest: PASS'         'run write' '<ret>' '<pause>' 'x' '<esc>' '<pause>' 'n' '<pause>' systest '<ret>'
# C.4: spreadsheet with charts
check sheet         'sheet: PASS'           'run sheet test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all sheet-calc 'gfx: A3: =A1*A2+1|gfx: = 7' 'run sheet' '<ret>' '<pause>' '2' '<ret>' '3' '<ret>' '=A1*A2+1' '<ret>' '<up>' '<pause>' '<gfx>'
check_all sheet-chart 'gfx: Line A1:B3|gfx: one|gfx: two' 'run sheet' '<ret>' '<pause>' 'one' '<tab>' 'two' '<ret>' '<left>' '1' '<ret>' '2' '<ret>' '<up>' '<up>' '<right>' '3' '<ret>' '5' '<ret>' '<up>' '<f3>' '<left>' '<up>' '<up>' '<ctrl-g>' '<pause>' '<gfx>'
check sheet-cyc     'gfx: #CYC: it depends on itself' 'run sheet' '<ret>' '<pause>' '=A2' '<ret>' '=A1+1' '<ret>' '<up>' '<pause>' '<gfx>'
check sheet-csv     '1,=A1*2'               'run sheet s.csv' '<ret>' '<pause>' '1' '<tab>' '=A1*2' '<ret>' '<ctrl-s>' '<pause>' '<esc>' '<pause>' 'cat s.csv' '<ret>'
check sheet-quit    'systest: PASS'         'run sheet' '<ret>' '<pause>' 'x' '<ret>' '<esc>' '<pause>' 'n' '<pause>' systest '<ret>'
# C.6: geometry
check geometry      'geometry: PASS'        'run geometry test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all geometry-cmds 'gfx: s1: length 5|gfx: m1 = 5|gfx: D (-1.9365, 3.5)|gfx: E (1.9365, 3.5)' 'run geometry' '<ret>' '<pause>' '(0,0)' '<ret>' '(4,0)' '<ret>' 'C=(0,3)' '<ret>' 'seg B C' '<ret>' 'k=circle C 2' '<ret>' 'circle A B' '<ret>' 'dist B C' '<ret>' 'inter c1 k' '<ret>' '<pause>' '<gfx>'
check_all geometry-move 'gfx: B (4.5, 0)|gfx: m1 = 4.5|gfx: M (2.25, 0)' 'run geometry' '<ret>' '<pause>' '(0,0)' '<ret>' '(4,0)' '<ret>' 'dist A B' '<ret>' 'M=mid A B' '<ret>' '<tab>' '<tab>' '<right>' '<right>' '<pause>' '<gfx>'
check geometry-err  'gfx: Those are not the right kinds of object' 'run geometry' '<ret>' '<pause>' '(0,0)' '<ret>' '(4,0)' '<ret>' 'perp A B' '<ret>' '<pause>' '<gfx>'
check geometry-save 'C=circle A 2'          'run geometry g.geo' '<ret>' '<pause>' '(0,0)' '<ret>' 'C=circle A 2' '<ret>' '<ctrl-s>' '<pause>' '<esc>' '<pause>' 'cat g.geo' '<ret>'
check geometry-quit 'systest: PASS'         'run geometry' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# C.5: computer algebra
check cas           'cas: PASS'             'run cas test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all cas-algebra 'gfx: (x + 3)*(x - 3)|gfx: x^2 - 9|gfx: x = -sqrt(2), x = sqrt(2)' 'run cas' '<ret>' '<pause>' 'factor(x^2-9)' '<ret>' 'expand(ans)' '<ret>' 'solve(x^2=2)' '<ret>' '<pause>' '<gfx>'
check_all cas-calculus 'gfx: x^2*cos(x) + 2*x*sin(x)|gfx: sin(3*x)/3 + C|gfx: 1 - x^2/2 + x^4/24' 'run cas' '<ret>' '<pause>' 'diff(x^2*sin(x))' '<ret>' 'integrate(cos(3*x))' '<ret>' 'series(cos(x), 0, 4)' '<ret>' '<pause>' '<gfx>'
check_all cas-err   'gfx: Error: syntax|gfx: Error: no answer yet for ans' 'run cas' '<ret>' '<pause>' 'ans' '<ret>' 'x +* 2' '<ret>' '<pause>' '<gfx>'
check cas-quit      'systest: PASS'         'run cas' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# A.5: system monitor, log viewer, disk utility (and the kernel's GUI_SYSINFO)
check sysmon        'sysmon: PASS'          'run sysmon test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all sysmon-view 'gfx: System Monitor|gfx: PID STATE|gfx: Memory|sysmon' 'run sysmon' '<ret>' '<pause>' '<pause>' '<gfx>'
check sysmon-prio   'kernel prio 2'         'run sysmon' '<ret>' '<pause>' '<up>' '+' '<pause>' '<esc>' '<pause>' ps '<ret>'
check sysmon-quit   'systest: PASS'         'run sysmon' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check logview       'logview: PASS'         'run logview test' '<ret>' '<pause>' '<pause>'
check_all logview-crash 'Squirrel-OS/2 started|crashed crash (pid 1): page fault|ended crash (pid 1), exit code -1|gfx: Lines 1-5 of 5' 'run crash' '<ret>' '<pause>' 'run logview' '<ret>' '<pause>' '<gfx>'
check_all logview-filter 'gfx: Lines 1-3 of 5|gfx: filter: crash' 'run crash' '<ret>' '<pause>' 'run logview' '<ret>' '<pause>' '/' 'crash' '<ret>' '<pause>' '<gfx>'
check_all logview-file 'gfx: lv.txt|gfx: acorns and oak' 'put lv.txt acorns and oak' '<ret>' 'run logview lv.txt' '<ret>' '<pause>' '<gfx>'
check logview-quit  'systest: PASS'         'run logview' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check diskutil      'diskutil: PASS'        'run diskutil test' '<ret>' '<pause>' '<pause>'
check_all diskutil-check 'gfx: hd1 (data disk): SQFS, 2048 sectors, 1024 KB|gfx: Check: no problems found' 'run diskutil' '<ret>' '<pause>' 'c' '<pause>' '<gfx>'
check diskutil-scan 'gfx: Surface scan: 2048 sectors read, 0 failed' 'run diskutil' '<ret>' '<pause>' 's' '<pause>' '<pause>' '<gfx>'
check diskutil-quit 'systest: PASS'         'run diskutil' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# C.8: notebooks (notes, Nut code, graphs, tables, geometry; C.1: math cells by sqmath)
check notebook      'notebook: PASS'        'run notebook test' '<ret>' '<pause>' '<pause>' '<pause>'
check_all notebook-code 'gfx: 42|gfx: 7 12' 'run notebook' '<ret>' '<pause>' 'c' 'x = 6' '<ret>' 'print x*7' '<ret>' 'print x+1, x*2' '<esc>' '<pause>' '<gfx>'
check_all notebook-cells 'gfx: y = sin(x)|gfx: x: -10 .. 10|gfx: y: -1 .. 1|gfx: d = 5|gfx: 2 hi' 'run notebook' '<ret>' '<pause>' 'g' 'sin(x)' '<esc>' 'o' 'A = (0,0)' '<ret>' 'B = (3,4)' '<ret>' 'seg A B' '<ret>' 'd = dist A B' '<esc>' 't' '=d-3 | hi' '<esc>' '<pause>' '<gfx>'
check notebook-err  'gfx: ! line 2: division by zero' 'run notebook' '<ret>' '<pause>' 'c' 'x = 1' '<ret>' 'print x/0' '<esc>' '<pause>' '<gfx>'
check_all notebook-save '%% code|print 5|%% note|acorns' 'run notebook n.nb' '<ret>' '<pause>' 'n' 'acorns' '<esc>' 'c' 'print 5' '<esc>' '<ctrl-s>' '<pause>' '<esc>' '<pause>' 'cat n.nb' '<ret>'
check_all notebook-math 'gfx: z = -3 + 4i|gfx: v = 25 m/s|gfx: 1/7 = 0.1428571428571428571428571428571428571429' 'run notebook' '<ret>' '<pause>' 'm' 'z = (1+2i)^2' '<ret>' 'v = 90 [km/h] to [m/s]' '<ret>' 'digits 40' '<ret>' '1/7' '<esc>' '<pause>' '<gfx>'
check notebook-quit 'systest: PASS'         'run notebook' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
# P.8: DOS .COM and .EXE programs run in the dosrun 8086 interpreter
disk=$out/dos.img
check_all dos-hello 'Hello from DOS land!|#! tail: acorns|doshello: PASS'  'run dosrun doshello.com acorns' '<ret>'
check dos-cpu       'doscpu: PASS'          'run dosrun doscpu.com' '<ret>'
check_all dos-file  'got: acorn|dosfile: PASS'  'run dosrun dosfile.com' '<ret>' acorn '<ret>'
check_all dos-exe   'Hello from an MZ .EXE!|dosexe: PASS'  'run dosrun dosexe.exe' '<ret>'
check dos-missing   'dosrun: cannot open'   'run dosrun nothere.com' '<ret>'
check dos-after     'systest: PASS'         'run dosrun doscpu.com' '<ret>' systest '<ret>'
# P.8-dos-launch: .com files and MZ files without a PE header go to dosrun by themselves
check_all dos-run-com 'Hello from DOS land!|#! tail: acorns|doshello: PASS'  'run doshello.com acorns' '<ret>'
check_all dos-run-exe 'Hello from an MZ .EXE!|dosexe: PASS'  'run dosexe.exe' '<ret>'
check_all dos-winrun  'Hello from an MZ .EXE!|dosexe: PASS'  'run winrun dosexe.exe' '<ret>'
check dos-run-after   'systest: PASS'         'run doscpu.com' '<ret>' systest '<ret>'
# P.2: Linux signals: handlers, SA_SIGINFO, masks and pending, and a default action that ends the program
check_all lx-sig      'lxsig: PASS|Program ended by signal 15'  'run lxsig' '<ret>' '<pause>'
check_none lx-sig-term 'lxsig: still here' 'Program ended by signal 15'  'run lxsig' '<ret>' '<pause>'
check lx-sig-after    'systest: PASS'         'run lxsig' '<ret>' '<pause>' systest '<ret>'
# P.8: VGA mode 13h: A000, INT 10h pixels, the DAC ports, retrace, teletype text in graphics, back to text
check_all dos-gfx     'gfx: dosgfx: drawn|dosgfx: PASS'  'run dosgfx.com' '<ret>' '<pause>' '<gfx>' x '<pause>'
check dos-gfx-after   'systest: PASS'         'run dosgfx.com' '<ret>' '<pause>' x '<pause>' systest '<ret>'
# P.10: a FreeBSD i386 ELF: arguments on the stack, errors as CF + errno
check_all bsd-hello   'Hello from FreeBSD land!|bsdhello: PASS'  'run bsdhello' '<ret>'
check bsd-after       'Hello from DOS land!'  'run bsdhello' '<ret>' 'run doshello.com' '<ret>'
# 3.0 (OS2-NET-AUDIO): sound. AC'97 and Intel HDA under QEMU (-audiodev none paces the DMA in
# real time; -audiodev wav writes what was played, which tools/wavcheck.py listens to)
python3 "$root/tools/sqfs.py" "$out/snd.img" format 1024
for prog in wavplay sndrec mixer spectrum; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
    python3 "$root/tools/sqfs.py" "$out/snd.img" put "$out/$prog"
done
python3 - "$out" <<'PYEOF'    # test tones: 1 kHz 16-bit mono 22050 Hz, 440 Hz 8-bit stereo 11025 Hz
import math, struct, sys
def wav(name, rate, ch, bits, freq, secs, amp):
    data = bytearray()
    for i in range(int(rate * secs)):
        v = math.sin(2 * math.pi * freq * i / rate)
        for _ in range(ch):
            data += struct.pack('<h', int(v * amp)) if bits == 16 else bytes([128 + int(v * amp / 256)])
    fmt = struct.pack('<HHIIHH', 1, ch, rate, rate * ch * bits // 8, ch * bits // 8, bits)
    open(sys.argv[1] + '/' + name, 'wb').write(b'RIFF' + struct.pack('<I', 36 + len(data)) + b'WAVEfmt '
        + struct.pack('<I', 16) + fmt + b'data' + struct.pack('<I', len(data)) + data)
wav('tone1k.wav', 22050, 1, 16, 1000, 0.5, 12000)
wav('tone8.wav', 11025, 2, 8, 440, 0.5, 20000)
PYEOF
for f in tone1k.wav tone8.wav; do python3 "$root/tools/sqfs.py" "$out/snd.img" put "$out/$f"; done
snd_disk=$disk; disk=$out/snd.img
check audio-none    'audio: no device'      audio '<ret>'
check spectrum-test 'spectrum: peak 1000 Hz, 80 dB' 'run spectrum tone1k.wav test' '<ret>' '<pause>'
check spectrum-8bit 'spectrum: peak 440 Hz' 'run spectrum tone8.wav test' '<ret>' '<pause>'
check wavplay-nodev 'wavplay: no sound device' 'run wavplay tone1k.wav' '<ret>'
export QEMU_EXTRA='-audiodev none,id=snd0 -device AC97,audiodev=snd0'
check audio-ac97    'audio: ac97'           audio '<ret>'
check audiotest-ac97 'audio: PASS ac97'     audiotest '<ret>' '<pause>'
check_all wavplay-ac97 'wavplay: 22050 Hz, 16-bit, mono, 0.50 s|wavplay: played 11025 frames' 'run wavplay tone1k.wav' '<ret>' '<pause>' '<pause>'
check_all wavplay-ac97-8 'wavplay: 11025 Hz, 8-bit, stereo, 0.49 s|wavplay: played 5512 frames' 'run wavplay tone8.wav' '<ret>' '<pause>' '<pause>'
check_all sndrec-ac97 'sndrec: 1.00 s, 88200 bytes, peak 0 -> rec.wav|wavplay: 22050 Hz, 16-bit, stereo, 1.00 s' 'run sndrec rec.wav 1' '<ret>' '<pause>' '<pause>' 'run wavplay rec.wav' '<ret>' '<pause>' '<pause>'
check_all mixer-ac97 'master  39%  39%  on|pcm     74%  74%  muted|record  100%  100%  on' 'run mixer master 40' '<ret>' 'run mixer pcm mute' '<ret>' 'run mixer record 100' '<ret>'
check_all mixer-gui-ac97 'gfx: Mixer|gfx: Device: ac97|gfx: 65%|gfx: muted' 'run mixer' '<ret>' '<pause>' '<down>' '<down>' '<pgdn>' '<right>' m '<pause>' '<gfx>'
check mixer-quit    'systest: PASS'         'run mixer' '<ret>' '<pause>' '<esc>' '<pause>' systest '<ret>'
check_all spectrum-gui 'gfx: Spectrum Analyser|gfx: Peak 1000 Hz|gfx: 11025 Hz' 'run spectrum tone1k.wav' '<ret>' '<pause>' '<gfx>'
export QEMU_EXTRA='-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0'
check audio-hda     'audio: hda codec 0, dac 2, pin 3, adc 4' audio '<ret>'
check audiotest-hda 'audio: PASS hda'       audiotest '<ret>' '<pause>'
check_all wavplay-hda 'wavplay: 11025 Hz, 8-bit, stereo, 0.49 s|wavplay: played 5512 frames' 'run wavplay tone8.wav' '<ret>' '<pause>' '<pause>'
check sndrec-hda    'sndrec: 1.00 s, 88200 bytes, peak 0 -> rec.wav' 'run sndrec rec.wav 1' '<ret>' '<pause>' '<pause>'
check_all mixer-hda 'master  41%  41%  on|record  30%  30%  on' 'run mixer master 40' '<ret>' 'run mixer record 30' '<ret>'
check_all mixer-hda-mute 'master  100%  100%  muted|pcm     100%  100%  muted' 'run mixer master mute' '<ret>'
# what reached QEMU's audio backend: the 1 kHz tone, from both drivers
for snd in "AC97,audiodev=snd0" "intel-hda -device hda-output,audiodev=snd0"; do
    rm -f "$out/played.wav"
    export QEMU_EXTRA="-audiodev wav,id=snd0,path=$out/played.wav -device $snd"
    python3 "$root/tools/qemu_screen.py" --disk "$disk" "$out/os.img" 'run wavplay tone1k.wav' '<ret>' '<pause>' '<pause>' >/dev/null 2>&1 || true
    name=wavout-${snd%%,*}; name=${name%% *}
    if result=$(python3 "$root/tools/wavcheck.py" "$out/played.wav" 1000 0.25); then echo "ok   $name"; else echo "FAIL $name ($result)"; fail=1; fi
done
unset QEMU_EXTRA
disk=$snd_disk
# OS2-HW H.3/H.4: AHCI and NVMe disks as sd0 and nv0 (drivers/ahci.asm, drivers/nvme.asm)
disk=$out/hw.img
hwdisk "$out/sata.img"; hwdisk "$out/nvme.img"
export QEMU_EXTRA="-device ahci,id=ahci -drive if=none,id=sd,file=$out/sata.img,format=raw -device ide-hd,drive=sd,bus=ahci.0 -drive if=none,id=nv,file=$out/nvme.img,format=raw -device nvme,serial=sqhw,drive=nv"
check_all hw-devices 'sd0     block   ready 8192 sectors|nv0     block   ready 8192 sectors'  devices '<ret>'
check hw-ahci       'blkdev: sd0 PASS'      'run blkdev sd0' '<ret>'
sector5 hw-ahci-disk "$out/sata.img"
check hw-nvme       'blkdev: nv0 PASS'      'run blkdev nv0' '<ret>'
sector5 hw-nvme-disk "$out/nvme.img"
check hw-after      'systest: PASS'         'run blkdev sd0' '<ret>' 'run blkdev nv0' '<ret>' systest '<ret>'
unset QEMU_EXTRA
check_none hw-absent 'sd0     block' 'ne0     net' devices '<ret>'
check hw-missing    'blkdev: FAIL'          'run blkdev nv0' '<ret>'
# q35: no IDE at all; the boot disk and the data disk are both on AHCI, the data disk becomes the file system
cp "$out/os.img" "$out/os-q35.img"; truncate -s 2M "$out/os-q35.img"
cp "$out/hw.img" "$out/hw-q35.img"
export QEMU_EXTRA="-M q35"; boot=$out/os-q35.img; disk=$out/hw-q35.img
check_all hw-q35    'hd1     block   absent|sd1     block   ready 2048 sectors|blkdev  '  devices '<ret>' ls '<ret>'
unset QEMU_EXTRA boot
# OS2-HW H.5/H.6: xHCI. QEMU sends typed keys to the USB keyboard once it is there (not to the
# 8042), so these checks only pass if usbkbd.asm turns its reports into scan codes.
disk=$out/hw.img
hwdisk "$out/usb.img"
export QEMU_EXTRA="-device qemu-xhci,id=xhci -device usb-kbd,bus=xhci.0"
check_all hw-usb-kbd "echo Hello, USB World! (a+b)|${nl}Hello, USB World! (a+b)"  'echo Hello, USB World! (a+b)' '<ret>'
check hw-usb-kbd-edit "${nl}Hello, USB World! (a+bX"  'echo Hello, USB World! (a+b)' '<ret>' '<up>' '<backspace>' X '<ret>'
check_all hw-usb-keyev 'keyev: queue Q getc Q|keyev: PASS'  'run keyev' '<ret>' '<pause>' Q '<pause>'
export QEMU_EXTRA="-device qemu-xhci,id=xhci -device usb-kbd,bus=xhci.0 -drive if=none,id=us,file=$out/usb.img,format=raw -device usb-storage,bus=xhci.0,drive=us"
check hw-usb-devices 'ud0     block   ready 8192 sectors'  devices '<ret>'
check hw-usb-msd    'blkdev: ud0 PASS'      'run blkdev ud0' '<ret>'
sector5 hw-usb-msd-disk "$out/usb.img"
check hw-usb-after  'systest: PASS'         'run blkdev ud0' '<ret>' systest '<ret>'
# boot from a USB stick on a machine without IDE (the BIOS reads it; the kernel then finds it as ud0)
cp "$out/os.img" "$out/stick.img"; truncate -s 4M "$out/stick.img"
truncate -s 1M "$out/blank.img"; cp "$out/hw.img" "$out/hw-q35.img"
export QEMU_EXTRA="-M q35 -device qemu-xhci,id=xhci -drive if=none,id=st,file=$out/stick.img,format=raw -device usb-storage,bus=xhci.0,drive=st,bootindex=0"
boot=$out/blank.img; disk=$out/hw-q35.img
check_all hw-usb-boot 'hd0     block   absent|ud0     block   ready 8192 sectors|blkdev  '  devices '<ret>' ls '<ret>'
unset QEMU_EXTRA boot
# OS2-HW H.1/H.2: boot through UEFI firmware from the EFI system partition. The kernel's text
# screen is then in RAM at 0x1f8000 and drawn into the GOP framebuffer, which <gop> reads back.
# Needs OVMF (OVMF_FD, OVMF32_CODE/OVMF32_VARS) and, optionally, SquirrelBIOS (SQUIRRELBIOS_FD);
# without them these checks print "skip".
skip() { echo "skip $1 ($2)"; }
uefi_keys="<pause> <pause> <pause> <pause> <pause> <pause> <pause> <pause>"
OVMF_FD=${OVMF_FD:-/usr/share/ovmf/OVMF.fd}
OVMF32_CODE=${OVMF32_CODE:-/usr/share/OVMF/OVMF32_CODE_4M.fd}
OVMF32_VARS=${OVMF32_VARS:-/usr/share/OVMF/OVMF32_VARS_4M.fd}
disk=$out/hw.img; boot=$out/esp.img
export QEMU_TEXT=0x1f8000 QEMU_BIN=qemu-system-x86_64
if [ -f "$OVMF_FD" ] && command -v qemu-system-x86_64 >/dev/null; then
    export QEMU_EXTRA="-bios $OVMF_FD"
    check_all uefi-x64      'Squirrel-OS/2 2.1|systest: PASS|blkdev  '  $uefi_keys systest '<ret>' ls '<ret>'
    check_all uefi-x64-mem  'BIOS memory map:|usable|KB free'  $uefi_keys mem '<ret>'
    check_all uefi-x64-gop  'gop: Squirrel-OS/2 2.1|gop: > echo UEFI GOP x|gop: UEFI GOP x'  $uefi_keys 'echo UEFI GOP x' '<ret>' '<pause>' '<gop>'
else
    skip uefi-x64 "no OVMF at $OVMF_FD"
fi
if [ -f "$OVMF32_CODE" ] && [ -f "$OVMF32_VARS" ] && command -v qemu-system-x86_64 >/dev/null; then
    cp "$OVMF32_VARS" "$out/ovmf32-vars.fd"
    export QEMU_EXTRA="-drive if=pflash,format=raw,readonly=on,file=$OVMF32_CODE -drive if=pflash,format=raw,file=$out/ovmf32-vars.fd"
    check_all uefi-ia32     'Squirrel-OS/2 2.1|systest: PASS|gop: > systest'  $uefi_keys systest '<ret>' '<pause>' '<gop>'
else
    skip uefi-ia32 "no 32-bit OVMF at $OVMF32_CODE"
fi
if [ -n "$SQUIRRELBIOS_FD" ] && [ -f "$SQUIRRELBIOS_FD" ]; then
    # SquirrelBIOS 2.1.0 x86_64-uefi reads its ESP from virtio-blk only. It sometimes misses
    # BOOTX64.EFI and falls back to its CSM, so this check gets three tries.
    # hd0 is an empty disk with only a boot signature (systest reads it); nothing on it boots
    python3 -c "import sys; open(sys.argv[1], 'wb').write(bytes(510) + b'\x55\xaa' + bytes(1 << 20))" "$out/sig.img"
    boot=$out/sig.img
    export QEMU_EXTRA="-bios $SQUIRRELBIOS_FD -drive if=none,id=esp,format=raw,file=$out/esp.img -device virtio-blk-pci,drive=esp"
    for try in 1 2 3; do
        screen=$(python3 "$root/tools/qemu_screen.py" --disk "$disk" "$boot" '<pause>' '<pause>' '<pause>' systest '<ret>' '<pause>' '<gop>')
        case $screen in *"systest: PASS"*"gop: > systest"*) break ;; esac
    done
    case $screen in
        *"systest: PASS"*"gop: > systest"*) echo "ok   uefi-squirrelbios" ;;
        *) echo "FAIL uefi-squirrelbios (no shell after 3 boots)"; fail=1 ;;
    esac
else
    skip uefi-squirrelbios "set SQUIRRELBIOS_FD to SquirrelBIOS-2.1.0-x86_64-uefi.fd"
fi
unset QEMU_EXTRA QEMU_TEXT QEMU_BIN boot
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
