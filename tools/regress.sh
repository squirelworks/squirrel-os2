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
for prog in hello wc elfhello ls cat nest crash heap devtest; do
    nasm -f bin -i "$root/programs/" "$root/programs/$prog.asm" -o "$out/$prog"
done
python3 "$root/tools/sqfs.py" "$out/progs.img" format 1024
for prog in hello wc elfhello ls cat nest crash heap devtest; do python3 "$root/tools/sqfs.py" "$out/progs.img" put "$out/$prog"; done
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
printf 'echo autoexec ran\n' > "$out/autoexec.bat"
python3 "$root/tools/sqfs.py" "$out/auto.img" put "$out/autoexec.bat"
rm -f "$out/data.img"
dd if=/dev/zero of="$out/data.img" bs=1024 count=1024 2>/dev/null

fail=0
disk=$out/data.img              # data disk attached as primary slave
check() {   # check NAME EXPECTED KEYS...
    name=$1; want=$2; shift 2
    screen=$(python3 "$root/tools/qemu_screen.py" ${disk:+--disk "$disk"} "$out/os.img" "$@")
    case $screen in
        *"$want"*) echo "ok   $name" ;;
        *) echo "FAIL $name (expected: $want)"; fail=1 ;;
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
check exception     'CPU exception 6'       trap '<ret>'
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
check vm-nest       'own memory intact'     'run nest' '<ret>'
check vm-nest-child 'Argument: from nest'   'run nest' '<ret>'
check vm-crash      'Program ended: pid'    'run crash' '<ret>'
check vm-crash-addr 'address 0xC0000000'    'run crash' '<ret>'
check vm-after      'systest: PASS'         'run crash' '<ret>' systest '<ret>'
check vm-no-leak    '129912 KB free'        'run nest' '<ret>' 'run crash' '<ret>' 'run hello' '<ret>' mem '<ret>'
check vm-ps         'kernel'                ps '<ret>'
check heap          'heap: PASS (1024 KB)'  'run heap' '<ret>'
check heap-limit-after 'Program ended: pid'  'run heap after' '<ret>'
check heap-keep-leak '129912 KB free'       'run heap keep' '<ret>' 'run heap after' '<ret>' mem '<ret>'
check devices       'hd1     block   ready 2048 sectors'  devices '<ret>'
check devices-ro    '(read-only for programs)'  devices '<ret>'
check devtest       'devtest: PASS'         'run devtest' '<ret>'
check up-ls         '15 file(s)'             'run ls' '<ret>'
check up-ls-filter  '4 file(s)'             'run ls he' '<ret>'
check up-cat        'three'                 'run cat notes' '<ret>'
check up-cat-missing 'not found: zip'       'run cat zip notes' '<ret>'
check sh-redirect   'hi there'              'echo hi there > greet' '<ret>' 'cat greet' '<ret>'
check sh-append     'more'                  'echo more >> greet' '<ret>' 'cat greet' '<ret>'
check sh-pipe       '1 3 6'                 'echo x y z | run cat | run wc' '<ret>'
check sh-stdin      '= 42'                  'run calc < exprs > out' '<ret>' 'cat out' '<ret>'
check sh-quiet      'calc> 2 + 3'           'run calc < exprs > out' '<ret>' 'run cat < out' '<ret>'
check sh-ls-pipe    'elfhello'              'ls | run cat' '<ret>'
check sh-badpipe    'command on both sides' 'ls |' '<ret>'
check sh-noname     'needs a file name'     'cat >' '<ret>'
check sh-nofile     'Cannot read nofile'    'run wc < nofile' '<ret>'
check bat-run       'in demo2'              'batch demo.bat' '<ret>'
check bat-quiet     'quiet line'            'batch demo.bat' '<ret>'
check bat-pipe      '1 3 6'                 'batch demo.bat' '<ret>'
check bat-chain     '> echo in demo2'       'run demo.bat' '<ret>'
check bat-missing   'Cannot read nope'      'batch nope' '<ret>'
check dir-pwd       '/d1'                   'mkdir d1' '<ret>' 'cd d1' '<ret>' pwd '<ret>'
check dir-prompt    '/d1> '                 'cd d1' '<ret>'
check dir-path      '1 1 6 d2/n'            'mkdir d2' '<ret>' 'put d2/n nutty' '<ret>' 'run wc d2/n' '<ret>'
check dir-dotdot    '1 1 6 ../n'            'cd d2' '<ret>' 'mkdir s' '<ret>' 'cd s' '<ret>' 'run wc ../n' '<ret>'
check dir-run-root  'Hello from a loaded'   'cd d1' '<ret>' 'run hello' '<ret>'
check dir-hist-root '0 file(s)'             'mkdir d3' '<ret>' 'cd d3' '<ret>' 'run ls' '<ret>'
check dir-ls-prog   '<dir>'                 'run ls d1' '<ret>'
check dir-rm-full   'error'                 'rm d2' '<ret>'
check dir-mv-cycle  'error'                 'mkdir d5' '<ret>' 'mkdir d5/e' '<ret>' 'mv d5 d5/e/f' '<ret>'
check dir-mv-into   'g                 6'   'put g nutty' '<ret>' 'mv g d5/g' '<ret>' 'ls d5' '<ret>'
check dir-cd-bad    'No such directory'     'cd nowhere' '<ret>'
check dir-rm-empty  '0 file(s)'             'rm d1' '<ret>' 'run ls d1' '<ret>'
disk=$out/auto.img
check bat-autoexec  'autoexec ran'
disk=
check no-disk       'no data disk'          blktest '<ret>'
check devices-nodisk 'hd1     block   absent'  devices '<ret>'
check rom-fallback  'Hello from Squirrel'   'cat edit' '<ret>'
exit $fail
