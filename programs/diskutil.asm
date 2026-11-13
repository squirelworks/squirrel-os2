; Squirrel-OS/2 — Disk Utility (A.5, OS2-APPS). Original code.
; run diskutil  |  run diskutil test
;
; Looks at the data disk (hd1) through the block device, without the
; file system: its SQFS superblock and directory, then shows
;   - the disks (hd0, the boot disk, and hd1) and hd1's size;
;   - how full it is, and a map of it: one column for each stretch of
;     sectors, blue for the superblock and directory, green for file
;     data, light green for room a file has kept but not used, white
;     for free, red for what a check or scan found wrong;
;   - the largest files.
;
;   C: check the file system (every entry's name, kind, parent and
;      sectors; sectors past the end; files that share sectors; names
;      twice in one directory)
;   S: surface scan (read every sector, counting those that fail)
;   Esc: quit
;
;   (2.7) Long names: an entry whose name does not fit keeps a short
;   alias, and the whole name lives in continuation entries (kind 2,
;   directory 0xFF; 23 characters, the checksum of the owner's name, the
;   owner's index and a sequence number). They are counted as part of the
;   directory, the check matches them to their owners, and names are
;   shown and compared in full.
;
; Nothing is written to the disk. "run diskutil test" makes a file of its
; own, finds it, checks and scans the disk, checks a damaged copy of the
; directory, and prints "diskutil: PASS". See documentation/apps/diskutil.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

SQ_MAGIC    equ 0x53465153
DIR_LBA     equ 1
DIR_SECTS   equ 4
DATA_LBA    equ DIR_LBA + DIR_SECTS
DIRENT      equ 32
MAXFILES    equ DIR_SECTS * 512 / DIRENT
NAMELEN     equ 16
E_START     equ 16
E_SIZE      equ 20
E_CAP       equ 24
E_PARENT    equ 28
E_KIND      equ 29
E_LFN       equ 30              ; an owner: how many long-name parts
K_LFN       equ 2               ; (2.7) a long-name part:
LFN_PART    equ 23              ;   characters in it
LFN_SUM     equ 23              ;   the checksum of its owner's name
LFN_OWNER   equ 30              ;   its owner's index
LFN_SEQ     equ 31              ;   1, 2, 3
LFN_NOPAR   equ 0xFF            ;   its "directory"
LFN_MAX     equ 63              ; the longest name

MAP_X       equ 4
MAP_W       equ SCR_W - 8
MAP_H       equ 14
TOP_N       equ 6               ; largest files shown
NPROB       equ 6               ; problems kept for the report
PLEN        equ 72

M_FREE      equ 0               ; sector map kinds
M_META      equ 1
M_DATA      equ 2
M_SLACK     equ 3
M_BAD       equ 4
MAP_MAX     equ 65536           ; sectors mapped (one byte each)

main:
    mov esi, [esp+4]
    mov [arg], esi
    mov eax, SYS_SBRK
    mov ebx, MAP_MAX
    int 0x80
    cmp eax, -1
    je .nomem
    mov [smap], eax
    mov esi, [arg]
    test esi, esi
    jz .gui
    cmp dword [esi], 'test'
    jne .gui
    cmp byte [esi+4], 0
    je selftest
.gui:
    call gui_open
    jc .nogfx
    call analyse
.draw:
    call draw
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .draw
    test eax, EV_DRAG
    jnz .draw
    movzx ebx, ah
    cmp bl, K_ESC
    je .quit
    test eax, 1 << 16
    jnz .draw
    or al, 0x20
    cmp al, 'c'
    je .check
    cmp al, 's'
    je .scan
    jmp .draw
.check:
    call analyse
    call check_fs
    mov byte [shown_rep], 1
    jmp .draw
.scan:
    mov byte [scanning], 1
    call scan
    mov byte [scanning], 0
    mov byte [shown_rep], 2
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret
.nomem:
    mov esi, m_nomem
    call gui_puts
    mov eax, 1
    ret

; ---------- reading the disk ----------
; eax = sector, edi = 512-byte buffer, ebx = handle -> CF if it failed
rd_sector:
    pushad
    mov edx, eax
    mov ecx, edi
    mov eax, SYS_DEVREAD
    int 0x80
    cmp eax, 512
    popad
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; the disks, hd1's superblock and directory -> the map, the counts and
; the largest files
analyse:
    pushad
    mov byte [hd0_ok], 0
    mov byte [hd1_ok], 0
    mov byte [sq_ok], 0
    mov dword [total], 0
    mov eax, SYS_DEVFIND
    mov ebx, s_hd0
    int 0x80
    test eax, eax
    js .hd1
    mov ebx, eax
    xor eax, eax
    mov edi, sect
    call rd_sector
    jc .hd1
    mov byte [hd0_ok], 1
.hd1:
    mov eax, SYS_DEVFIND
    mov ebx, s_hd1
    int 0x80
    test eax, eax
    js .done
    mov [hd1], eax
    mov ebx, eax
    xor eax, eax
    mov edi, sect
    call rd_sector
    jc .done
    mov byte [hd1_ok], 1
    cmp dword [sect], SQ_MAGIC
    jne .done
    mov eax, [sect+8]
    mov [total], eax
    mov eax, [sect+4]
    mov [sq_ver], eax
    mov ecx, DIR_SECTS          ; the directory
    mov eax, DIR_LBA
    mov edi, dir
.d:
    call rd_sector
    jc .done
    inc eax
    add edi, 512
    loop .d
    mov byte [sq_ok], 1
    call map_dir
.done:
    popad
    ret

; dir -> smap, nfiles, ndirs, used, top files
map_dir:
    pushad
    mov edi, [smap]             ; all free
    mov ecx, [total]
    inc ecx
    cmp ecx, MAP_MAX
    jbe .z
    mov ecx, MAP_MAX
.z:
    mov [mapn], ecx
    xor eax, eax
    rep stosb
    mov edi, [smap]             ; the superblock and directory
    mov ecx, DATA_LBA
    mov al, M_META
    rep stosb
    mov dword [nfiles], 0
    mov dword [ndirs], 0
    mov dword [used], DATA_LBA
    mov dword [ntop], 0
    mov dword [databytes], 0
    xor ebx, ebx
.e:
    cmp ebx, MAXFILES
    jae .done
    mov esi, ebx
    shl esi, 5
    add esi, dir
    cmp byte [esi], 0
    je .n
    call is_part                ; (2.7) a long name's part: directory only
    jnc .n
    cmp byte [esi+E_KIND], 1
    jne .file
    inc dword [ndirs]
    jmp .n
.file:
    inc dword [nfiles]
    mov eax, [esi+E_SIZE]
    add [databytes], eax
    mov eax, [esi+E_CAP]
    add [used], eax
    mov eax, [esi+E_SIZE]       ; sectors with data, then the rest kept
    add eax, 511
    shr eax, 9
    mov edx, [esi+E_START]
    xor ecx, ecx
.s:
    cmp ecx, [esi+E_CAP]
    jae .t
    lea edi, [edx+ecx]
    cmp edi, [mapn]
    jae .t
    add edi, [smap]
    mov byte [edi], M_DATA
    cmp ecx, eax
    jb .s1
    mov byte [edi], M_SLACK
.s1:
    inc ecx
    jmp .s
.t:
    call top_add
.n:
    inc ebx
    jmp .e
.done:
    popad
    ret

; esi = a file's entry -> in the largest files, if it is one
top_add:
    pushad
    mov eax, [esi+E_SIZE]
    mov ecx, [ntop]
    mov edx, ecx                ; where it goes: before the first smaller
    xor ebx, ebx
.f:
    cmp ebx, ecx
    jae .at
    mov edi, [top+ebx*4]
    cmp eax, [edi+E_SIZE]
    ja .ins
    inc ebx
    jmp .f
.ins:
    mov edx, ebx
.at:
    cmp edx, TOP_N
    jae .r
    mov ebx, ecx                ; move the rest down
    cmp ebx, TOP_N - 1
    jbe .m
    mov ebx, TOP_N - 1
.m:
    cmp ebx, edx
    jbe .put
    mov edi, [top+ebx*4-4]
    mov [top+ebx*4], edi
    dec ebx
    jmp .m
.put:
    mov [top+edx*4], esi
    cmp ecx, TOP_N
    jae .r
    inc dword [ntop]
.r:
    popad
    ret

; ---------- the check ----------
; dir (as read, or as the self-test changed it) -> nprob and the first
; NPROB problems, the bad sectors marked on the map
check_fs:
    pushad
    mov dword [nprob], 0
    cmp byte [sq_ok], 0
    jne .sb
    mov esi, p_nosq
    call problem
    jmp .done
.sb:
    cmp dword [sq_ver], 1
    je .ent
    mov esi, p_ver
    call problem
.ent:
    xor ebx, ebx                ; each entry
.e:
    cmp ebx, MAXFILES
    jae .done
    mov esi, ebx
    shl esi, 5
    add esi, dir
    cmp byte [esi], 0
    je .n
    call is_part                ; (2.7) a long name's part
    jc .own
    call check_part
    jnc .n
    mov edx, p_part
    call eproblem
    jmp .n
.own:
    call check_long             ; an owner: all its parts there
    jnc .nm
    mov edx, p_long
    call eproblem
.nm:
    call check_name             ; a name of printable characters
    jnc .kind
    mov edx, p_name
    call eproblem
.kind:
    movzx eax, byte [esi+E_KIND]
    cmp eax, 1
    jbe .par
    mov edx, p_kind
    call eproblem
.par:
    movzx eax, byte [esi+E_PARENT]
    test eax, eax
    jz .dup
    cmp eax, MAXFILES
    ja .badpar
    dec eax
    shl eax, 5
    cmp byte [dir+eax], 0
    je .badpar
    cmp byte [dir+eax+E_KIND], 1
    je .dup
.badpar:
    mov edx, p_parent
    call eproblem
.dup:
    call check_dup
    jnc .ext
    mov edx, p_dup
    call eproblem
.ext:
    cmp byte [esi+E_KIND], 0
    jne .n
    mov eax, [esi+E_CAP]        ; its size fits what it kept
    shl eax, 9
    cmp [esi+E_SIZE], eax
    jbe .ends
    mov edx, p_size
    call eproblem
.ends:
    mov eax, [esi+E_CAP]
    test eax, eax
    jz .n
    mov edx, [esi+E_START]
    cmp edx, DATA_LBA
    jb .past
    add eax, edx
    jc .past
    cmp eax, [total]
    jbe .over
.past:
    mov edx, p_past
    call eproblem
    jmp .n
.over:
    call check_overlap
    jnc .n
    mov edx, p_overlap
    call eproblem
    call mark_bad
.n:
    inc ebx
    jmp .e
.done:
    popad
    ret

; esi = entry -> CF if its name is empty, too long or not printable
check_name:
    push eax
    push ecx
    xor ecx, ecx
.c:
    mov al, [esi+ecx]
    test al, al
    jz .end
    cmp al, ' '                 ; (2.7: spaces are allowed)
    jb .bad
    cmp al, '~'
    ja .bad
    cmp al, '/'
    je .bad
    inc ecx
    cmp ecx, NAMELEN
    jb .c
.bad:
    pop ecx
    pop eax
    stc
    ret
.end:
    pop ecx
    pop eax
    clc
    ret

; esi = entry, ebx = its index -> CF if an earlier entry in the same
; directory has its name (the name field, or the whole long name)
check_dup:
    pushad
    mov edi, nm_a
    call full_name
    xor ecx, ecx
.e:
    cmp ecx, ebx
    jae .no
    mov edi, ecx
    shl edi, 5
    add edi, dir
    cmp byte [edi], 0
    je .n
    xchg esi, edi
    call is_part
    xchg esi, edi
    jnc .n
    mov al, [edi+E_PARENT]
    cmp al, [esi+E_PARENT]
    jne .n
    push esi
    push edi
    push ecx
    mov ecx, NAMELEN
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    je .yes
    push esi                    ; (2.7) the whole names
    push edi
    mov esi, edi
    mov edi, nm_b
    call full_name
    mov esi, nm_a
    call streq
    pop edi
    pop esi
    je .yes
.n:
    inc ecx
    jmp .e
.no:
    popad
    clc
    ret
.yes:
    popad
    stc
    ret

; esi = file entry, ebx = index -> CF if another file's sectors overlap
check_overlap:
    pushad
    mov eax, [esi+E_START]
    mov edx, eax
    add edx, [esi+E_CAP]
    xor ecx, ecx
.e:
    cmp ecx, MAXFILES
    jae .no
    cmp ecx, ebx
    je .n
    mov edi, ecx
    shl edi, 5
    add edi, dir
    cmp byte [edi], 0
    je .n
    cmp byte [edi+E_KIND], 0
    jne .n
    cmp dword [edi+E_CAP], 0
    je .n
    cmp [edi+E_START], edx      ; other.start < end
    jae .n
    mov ebp, [edi+E_START]
    add ebp, [edi+E_CAP]
    cmp eax, ebp                ; start < other.end
    jb .yes
.n:
    inc ecx
    jmp .e
.no:
    popad
    clc
    ret
.yes:
    popad
    stc
    ret

; esi = file entry: its sectors red on the map
mark_bad:
    pushad
    mov edx, [esi+E_START]
    mov ecx, [esi+E_CAP]
.m:
    test ecx, ecx
    jz .r
    cmp edx, [mapn]
    jae .r
    mov edi, [smap]
    mov byte [edi+edx], M_BAD
    inc edx
    dec ecx
    jmp .m
.r:
    popad
    ret

; esi = entry, edx = what is wrong: "name: what"
eproblem:
    pushad
    mov edi, nm_a               ; (2.7) the whole name, cut to 24
    call full_name
    mov esi, nm_a
    mov edi, pline
    mov ecx, 24
.c:
    lodsb
    test al, al
    jz .d
    cmp al, ' '
    jb .q
    cmp al, '~'
    jbe .ok
.q:
    mov al, '?'
.ok:
    stosb
    loop .c
.d:
    mov esi, edx
    call scopy
    mov esi, pline
    call problem
    popad
    ret

; esi = text: one more problem (the first NPROB kept)
problem:
    pushad
    mov eax, [nprob]
    inc dword [nprob]
    cmp eax, NPROB
    jae .r
    imul edi, eax, PLEN
    add edi, probs
    mov ecx, PLEN - 1
.c:
    lodsb
    test al, al
    jz .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
.r:
    popad
    ret

; ---------- long names (2.7) ----------
; esi = a used entry -> CF clear if it is a long name's part
is_part:
    cmp byte [esi+E_KIND], K_LFN
    jne .no
    cmp byte [esi+E_PARENT], LFN_NOPAR
    jne .no
    clc
    ret
.no:
    stc
    ret

; esi = entry -> al = the checksum of its 16-byte name field
name_sum:
    push ecx
    push esi
    mov ecx, NAMELEN
    xor al, al
.l:
    ror al, 1
    add al, [esi]
    inc esi
    loop .l
    pop esi
    pop ecx
    ret

; esi = entry -> eax = its index
ent_index:
    mov eax, esi
    sub eax, dir
    shr eax, 5
    ret

; esi = owner, dl = sequence number -> edi = that part, or CF
find_part:
    push eax
    push ebx
    push ecx
    call ent_index
    mov bl, al
    call name_sum
    mov bh, al
    xor ecx, ecx
.e:
    cmp ecx, MAXFILES
    jae .no
    mov edi, ecx
    shl edi, 5
    add edi, dir
    cmp byte [edi], 0
    je .n
    cmp byte [edi+E_KIND], K_LFN
    jne .n
    cmp byte [edi+E_PARENT], LFN_NOPAR
    jne .n
    cmp [edi+LFN_OWNER], bl
    jne .n
    cmp [edi+LFN_SEQ], dl
    jne .n
    cmp [edi+LFN_SUM], bh
    je .yes
.n:
    inc ecx
    jmp .e
.no:
    pop ecx
    pop ebx
    pop eax
    stc
    ret
.yes:
    pop ecx
    pop ebx
    pop eax
    clc
    ret

; esi = a part -> CF if no owner claims it: the owner's index, its
; checksum and the sequence number must all fit
check_part:
    pushad
    movzx eax, byte [esi+LFN_OWNER]
    cmp eax, MAXFILES
    jae .bad
    shl eax, 5
    lea edi, [dir+eax]
    cmp byte [edi], 0
    je .bad
    xchg esi, edi
    call is_part                ; (a part never owns parts)
    xchg esi, edi
    jnc .bad
    mov dl, [esi+LFN_SEQ]
    test dl, dl
    jz .bad
    cmp dl, [edi+E_LFN]
    ja .bad
    xchg esi, edi
    call name_sum
    xchg esi, edi
    cmp al, [esi+LFN_SUM]
    jne .bad
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; esi = an owner -> CF if it counts parts that are not all there (or
; more than a 63-character name needs)
check_long:
    pushad
    movzx ecx, byte [esi+E_LFN]
    cmp ecx, (LFN_MAX + LFN_PART - 1) / LFN_PART
    ja .bad
    mov dl, 1
.p:
    cmp dl, cl
    ja .ok
    call find_part
    jc .bad
    inc dl
    jmp .p
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; esi = entry, edi = a 64-byte buffer -> its whole name there: the long
; name when all its parts are found, otherwise the name field
full_name:
    pushad
    mov ebp, edi
    call is_part
    jnc .field
    movzx ecx, byte [esi+E_LFN]
    test ecx, ecx
    jz .field
    call check_long
    jc .field
    mov dl, 1
    xor ebx, ebx                ; characters so far
.p:
    cmp dl, cl
    ja .end
    push esi
    call find_part
    mov esi, edi
    lea edi, [ebp+ebx]
    push ecx
    mov ecx, LFN_PART
.c:
    lodsb
    test al, al
    jz .cd
    cmp ebx, LFN_MAX
    jae .cd
    stosb
    inc ebx
    loop .c
.cd:
    pop ecx
    pop esi
    inc dl
    jmp .p
.end:
    mov byte [ebp+ebx], 0
    popad
    ret
.field:
    mov edi, ebp
    mov ecx, NAMELEN
.f:
    lodsb
    test al, al
    jz .fe
    stosb
    loop .f
.fe:
    mov byte [edi], 0
    popad
    ret

; esi, edi = strings -> ZF if they are the same
streq:
    push eax
    push esi
    push edi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .r
    inc esi
    inc edi
    test al, al
    jnz .c
.r:
    pop edi
    pop esi
    pop eax
    ret

; ---------- the surface scan ----------
; reads sectors 0 .. total -> nread, nfail (failed sectors red)
scan:
    pushad
    mov dword [nread], 0
    mov dword [nfail], 0
    cmp byte [hd1_ok], 0
    je .done
    mov ecx, [total]
    test ecx, ecx
    jnz .go
    mov ecx, 1                  ; no SQFS: the first sector only
.go:
    inc ecx
    mov [scan_n], ecx
    xor eax, eax
    mov ebx, [hd1]
.s:
    cmp eax, [scan_n]
    jae .done
    mov edi, sect
    call rd_sector
    jnc .ok
    inc dword [nfail]
    cmp eax, [mapn]
    jae .ok
    mov edx, [smap]
    mov byte [edx+eax], M_BAD
.ok:
    inc dword [nread]
    inc eax
    test eax, 63                ; the progress bar now and then
    jnz .s
    cmp byte [scanning], 0
    je .s
    call draw
    jmp .s
.done:
    popad
    ret

; ---------- drawing ----------
draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    mov ebp, WIN_TITLE_H + 3    ; the row being written
    call draw_disks
    call draw_usage
    call draw_map
    call draw_report
    mov byte [gui_ink], C_BLACK
    mov esi, s_keys
    mov eax, 4
    mov ebx, SCR_H - CELL_H - 2
    call gui_text
    call gui_flip
    popad
    ret

; esi = text at the row ebp, then the next row
say:
    push eax
    push ebx
    mov eax, 4
    mov ebx, ebp
    call gui_text
    add ebp, CELL_H + 1
    pop ebx
    pop eax
    ret

draw_disks:
    mov byte [gui_ink], C_BLACK
    mov edi, ln
    mov esi, s_hd0l
    call scopy
    mov esi, s_absent
    cmp byte [hd0_ok], 0
    je .a
    mov esi, s_present
.a:
    call scopy
    mov esi, ln
    call say
    mov edi, ln
    mov esi, s_hd1l
    call scopy
    mov esi, s_absent
    cmp byte [hd1_ok], 0
    je .b
    mov esi, s_nosq
    cmp byte [sq_ok], 0
    je .b
    mov esi, s_sqfs
    call scopy
    mov eax, [total]
    inc eax
    call gui_utoa
    mov esi, s_sectors
    call scopy
    mov eax, [total]
    inc eax
    shr eax, 1
    call gui_utoa
    mov esi, s_kb
.b:
    call scopy
    mov esi, ln
    jmp say

; "Used 123 of 2048 sectors (6%)   Files 12   Directories 1"
draw_usage:
    cmp byte [sq_ok], 0
    je .r
    mov edi, ln
    mov esi, s_used
    call scopy
    mov eax, [used]
    call gui_utoa
    mov esi, s_of
    call scopy
    mov eax, [total]
    inc eax
    call gui_utoa
    mov esi, s_secs
    call scopy
    mov eax, [used]
    mov ecx, 100
    mul ecx
    mov ecx, [total]
    inc ecx
    div ecx
    call gui_utoa
    mov esi, s_pct
    call scopy
    mov esi, ln
    call say
    mov edi, ln
    mov esi, s_files
    call scopy
    mov eax, [nfiles]
    call gui_utoa
    mov esi, s_dirs
    call scopy
    mov eax, [ndirs]
    call gui_utoa
    mov esi, s_bytes
    call scopy
    mov eax, [databytes]
    call gui_utoa
    mov esi, s_bytes2
    call scopy
    mov esi, ln
    call say
.r:
    ret

; the sector map, then the largest files
draw_map:
    cmp byte [sq_ok], 0
    je .r
    add ebp, 2
    mov eax, MAP_X - 1
    mov ebx, ebp
    dec ebx
    mov ecx, MAP_W + 2
    mov edx, MAP_H + 2
    mov byte [gui_ink], C_DGREY
    call gui_box
    xor esi, esi                ; column
.col:
    cmp esi, MAP_W
    jae .legend
    mov eax, [mapn]             ; its sectors: from s0 to s1
    mul esi
    mov ecx, MAP_W
    div ecx
    mov edi, eax
    lea eax, [esi+1]
    mul dword [mapn]
    div ecx
    cmp eax, edi
    ja .rng
    lea eax, [edi+1]
.rng:
    xor ecx, ecx                ; the "worst" kind in it: bad, data, slack, meta, free
    mov edx, [smap]
.k:
    cmp edi, eax
    jae .paint
    movzx ebx, byte [edx+edi]
    movzx ebx, byte [rank+ebx]
    cmp ebx, ecx
    jbe .k1
    mov ecx, ebx
.k1:
    inc edi
    jmp .k
.paint:
    mov cl, [rank_col+ecx]
    mov [gui_ink], cl
    lea eax, [MAP_X+esi]
    mov ebx, ebp
    mov ecx, 1
    mov edx, MAP_H
    call gui_fill
    inc esi
    jmp .col
.legend:
    add ebp, MAP_H + 3
    mov eax, 4                  ; colour keys
    mov esi, legend
.lg:
    cmp byte [esi], 0
    je .lgd
    mov cl, [esi]
    mov [gui_ink], cl
    push eax
    mov ebx, ebp
    mov ecx, 6
    mov edx, 6
    call gui_fill
    mov byte [gui_ink], C_DGREY
    call gui_box
    pop eax
    add eax, 8
    inc esi
    mov byte [gui_ink], C_BLACK
    mov ebx, ebp
    call gui_text
    push eax
    call gui_textw
    pop edx
    add eax, edx
    add eax, 12
.skip:
    inc esi
    cmp byte [esi-1], 0
    jne .skip
    jmp .lg
.lgd:
    add ebp, CELL_H + 3
    mov esi, s_largest          ; the largest files
    call say
    xor ecx, ecx
.t:
    cmp ecx, [ntop]
    jae .r
    mov esi, [top+ecx*4]
    mov edi, nm_a               ; (2.7) the whole name, cut to 21
    call full_name
    mov esi, nm_a
    mov edi, ln
    mov al, ' '
    stosb
    stosb
    push ecx
    mov ecx, 21
.nm:
    lodsb
    test al, al
    jz .pad
    stosb
    loop .nm
.pad:
    lea eax, [ln+24]            ; the size from column 24
    cmp edi, eax
    jae .sz
    mov byte [edi], ' '
    inc edi
    jmp .pad
.sz:
    pop ecx
    mov esi, [top+ecx*4]
    mov eax, [esi+E_SIZE]
    call gui_utoa
    mov esi, s_bytes2
    call scopy
    mov esi, ln
    call say
    inc ecx
    jmp .t
.r:
    ret

; the last check's or scan's result
draw_report:
    mov ebp, SCR_H - 4 * (CELL_H + 1) - CELL_H - 4
    mov byte [gui_ink], C_BLACK
    cmp byte [scanning], 0
    jne .progress
    cmp byte [shown_rep], 1
    je .check
    cmp byte [shown_rep], 2
    je .scan
    ret
.progress:
    mov edi, ln
    mov esi, s_scanning
    call scopy
    mov eax, [nread]
    call gui_utoa
    mov esi, s_of
    call scopy
    mov eax, [scan_n]
    call gui_utoa
    mov esi, ln
    jmp say
.scan:
    mov edi, ln
    mov esi, s_scanned
    call scopy
    mov eax, [nread]
    call gui_utoa
    mov esi, s_secs_read
    call scopy
    mov eax, [nfail]
    call gui_utoa
    mov esi, s_failed
    call scopy
    mov esi, ln
    jmp say
.check:
    cmp dword [nprob], 0
    jne .probs
    mov esi, s_noprob
    jmp say
.probs:
    mov edi, ln
    mov eax, [nprob]
    call gui_utoa
    mov esi, s_probs
    call scopy
    mov esi, ln
    call say
    xor ecx, ecx
.p:
    cmp ecx, [nprob]
    jae .r
    cmp ecx, 3                  ; the first three
    jae .r
    imul esi, ecx, PLEN
    add esi, probs
    call say
    inc ecx
    jmp .p
.r:
    ret

; esi -> edi (edi ends at the zero)
scopy:
    push eax
.c:
    lodsb
    stosb
    test al, al
    jnz .c
    dec edi
    pop eax
    ret

; ---------- self-test ----------
selftest:
    mov byte [bad], 'a'         ; a: a file of known size
    mov eax, SYS_OPEN
    mov ebx, t_name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, sect               ; (any 1500 bytes)
    mov edx, 1500
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, 1500
    jne fail
    inc byte [bad]              ; b: the superblock and the file found
    call analyse
    cmp byte [hd1_ok], 1
    jne fail
    cmp byte [sq_ok], 1
    jne fail
    cmp dword [total], DATA_LBA
    jbe fail
    call find_test
    jc fail
    cmp dword [esi+E_SIZE], 1500
    jne fail
    cmp dword [esi+E_CAP], 3
    jb fail
    mov eax, [esi+E_START]      ; mapped: 3 sectors of data, then slack
    add eax, [smap]
    cmp byte [eax], M_DATA
    jne fail
    cmp byte [eax+2], M_DATA
    jne fail
    mov ecx, [esi+E_CAP]
    cmp ecx, 3
    je .c
    cmp byte [eax+3], M_SLACK
    jne fail
.c:
    cmp dword [nfiles], 1
    jb fail
    mov eax, [ntop]             ; the largest first
    test eax, eax
    jz fail
    mov esi, [top]
    mov eax, [esi+E_SIZE]
    mov ecx, 1
.lg:
    cmp ecx, [ntop]
    jae .lgd
    mov esi, [top+ecx*4]
    cmp [esi+E_SIZE], eax
    ja fail
    mov eax, [esi+E_SIZE]
    inc ecx
    jmp .lg
.lgd:
    inc byte [bad]              ; c: the disk as it is passes the check
    call check_fs
    cmp dword [nprob], 0
    jne fail
    inc byte [bad]              ; d: the surface scan reads it all
    call scan
    cmp dword [nfail], 0
    jne fail
    mov eax, [total]
    inc eax
    cmp [nread], eax
    jne fail
    inc byte [bad]              ; e: damage found (in memory only)
    call find_test
    mov edi, esi                ; a second entry on top of the first
    call free_entry
    jc fail
    push esi
    mov esi, edi
    mov edi, eax
    mov ecx, DIRENT / 4
    rep movsd
    pop esi
    mov byte [eax], 'Z'         ; another name, the same sectors
    mov dword [eax+E_SIZE], 99999
    call check_fs
    cmp dword [nprob], 3        ; overlap twice, and its size
    jb fail
    mov esi, probs
    mov edi, p_overlap
    call contains
    jc fail
    mov esi, probs              ; (the size problem names the file)
    mov edi, p_size
    call any_prob
    jc fail
    inc byte [bad]              ; f: a bad parent and a bad name
    call analyse
    call find_test
    mov byte [esi+E_PARENT], 60
    mov byte [esi+1], 1
    call check_fs
    cmp dword [nprob], 2
    jne fail
    mov edi, p_parent
    call any_prob
    jc fail
    mov edi, p_name
    call any_prob
    jc fail
    inc byte [bad]              ; g: (2.7) a long name, in memory
    call analyse
    mov eax, [nfiles]
    mov [t_nf], eax
    call find_test
    mov edi, t_long
    call fake_long
    jc fail
    call map_dir                ; parts are not files
    mov eax, [nfiles]
    cmp eax, [t_nf]
    jne fail
    call check_fs
    cmp dword [nprob], 0
    jne fail
    mov edi, nm_a
    call full_name
    push esi
    mov esi, nm_a
    mov edi, t_long
    call streq
    pop esi
    jne fail
    inc byte [bad]              ; h: the same long name twice in a directory
    mov edi, esi
    call free_entry
    jc fail
    push esi
    mov esi, edi
    mov edi, eax
    mov ecx, DIRENT / 4
    rep movsd
    pop esi
    mov esi, eax                ; another alias, no sectors
    mov byte [esi], 'Z'
    mov dword [esi+E_SIZE], 0
    mov dword [esi+E_CAP], 0
    mov edi, t_long
    call fake_long
    jc fail
    call check_fs
    cmp dword [nprob], 1
    jne fail
    mov edi, p_dup
    call any_prob
    jc fail
    inc byte [bad]              ; i: parts whose owner has changed
    call analyse
    call find_test
    mov edi, t_long
    call fake_long
    jc fail
    mov byte [esi+1], 'X'       ; the checksum no longer fits
    call check_fs
    cmp dword [nprob], 3        ; two lost parts, an incomplete name
    jne fail
    mov edi, p_part
    call any_prob
    jc fail
    mov edi, p_long
    call any_prob
    jc fail
    mov eax, SYS_DELETE
    mov ebx, t_name
    int 0x80
    inc byte [bad]              ; j: the file has gone
    call analyse
    call find_test
    jnc fail
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
fail:
    mov esi, failm
    call gui_puts
    mov eax, 1
    ret

; -> esi = the test file's entry, or CF
find_test:
    xor ecx, ecx
.e:
    cmp ecx, MAXFILES
    jae .no
    mov esi, ecx
    shl esi, 5
    add esi, dir
    push esi
    push ecx
    mov edi, t_name
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .yes
    inc ecx
    jmp .e
.no:
    stc
    ret
.yes:
    clc
    ret
; esi = owner, edi = a long name -> its parts in unused entries of
; the directory copy (in memory), the owner's count set; CF if no room
fake_long:
    pushad
    mov ebp, edi
    call ent_index
    mov bl, al
    call name_sum
    mov bh, al
    mov dl, 1
.p:
    cmp byte [ebp], 0
    je .ok
    call free_entry
    jc .no
    mov edi, eax
    push edi
    xor eax, eax
    mov ecx, DIRENT / 4
    rep stosd
    pop edi
    mov ecx, LFN_PART
.c:
    mov al, [ebp]
    test al, al
    jz .cd
    mov [edi], al
    inc ebp
    inc edi
    loop .c
.cd:
    sub edi, LFN_PART           ; back to the entry's start
    add edi, ecx
    mov [edi+LFN_SUM], bh
    mov byte [edi+E_PARENT], LFN_NOPAR
    mov byte [edi+E_KIND], K_LFN
    mov [edi+LFN_OWNER], bl
    mov [edi+LFN_SEQ], dl
    mov [esi+E_LFN], dl
    inc dl
    jmp .p
.ok:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; -> eax = an unused entry, or CF
free_entry:
    push ecx
    xor ecx, ecx
.e:
    cmp ecx, MAXFILES
    jae .no
    mov eax, ecx
    shl eax, 5
    add eax, dir
    cmp byte [eax], 0
    je .yes
    inc ecx
    jmp .e
.no:
    pop ecx
    stc
    ret
.yes:
    pop ecx
    clc
    ret
; edi = word -> CF if no kept problem has it
any_prob:
    push ecx
    push esi
    xor ecx, ecx
.p:
    cmp ecx, [nprob]
    jae .no
    cmp ecx, NPROB
    jae .no
    imul esi, ecx, PLEN
    add esi, probs
    call contains
    jnc .yes
    inc ecx
    jmp .p
.no:
    pop esi
    pop ecx
    stc
    ret
.yes:
    pop esi
    pop ecx
    clc
    ret
; esi = text, edi = word -> CF if the word is not in it
contains:
    pushad
.s:
    cmp byte [esi], 0
    je .no
    xor ecx, ecx
.c:
    mov al, [edi+ecx]
    test al, al
    jz .yes
    cmp al, [esi+ecx]
    jne .nx
    inc ecx
    jmp .c
.nx:
    inc esi
    jmp .s
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ---------- data ----------
title db 'Disk Utility', 0
s_keys db 'C: check   S: surface scan   Esc: quit', 0
s_hd0 db 'hd0', 0
s_hd1 db 'hd1', 0
s_hd0l db 'hd0 (boot disk): ', 0
s_hd1l db 'hd1 (data disk): ', 0
s_present db 'present', 0
s_absent db 'absent', 0
s_nosq db 'no SQFS file system', 0
s_sqfs db 'SQFS, ', 0
s_sectors db ' sectors, ', 0
s_kb db ' KB', 0
s_used db 'Used ', 0
s_of db ' of ', 0
s_secs db ' sectors (', 0
s_pct db '%)', 0
s_files db 'Files ', 0
s_dirs db '   Directories ', 0
s_bytes db '   Data ', 0
s_bytes2 db ' bytes', 0
s_largest db 'Largest files:', 0
s_scanning db 'Scanning: sector ', 0
s_scanned db 'Surface scan: ', 0
s_secs_read db ' sectors read, ', 0
s_failed db ' failed', 0
s_noprob db 'Check: no problems found', 0
s_probs db ' problems found:', 0
p_nosq db 'hd1 has no SQFS superblock', 0
p_ver db 'superblock: unknown version', 0
p_name db ': a bad name', 0
p_kind db ': an unknown kind', 0
p_parent db ': its directory is missing', 0
p_dup db ': the same name twice in a directory', 0
p_size db ': larger than its sectors', 0
p_past db ': sectors outside the data area', 0
p_overlap db ': shares sectors with another file', 0
p_part db ': a long-name part without its file', 0
p_long db ': parts of its long name are missing', 0
; map kinds -> rank (which colour wins in a column) -> colour
rank db 0, 1, 3, 2, 4           ; free, meta, data, slack, bad
rank_col db C_WHITE, C_BLUE, C_LGREEN, C_GREEN, C_RED ; (by rank)
legend db C_BLUE, 'system', 0, C_GREEN, 'data', 0, C_LGREEN, 'kept', 0
       db C_WHITE, 'free', 0, C_RED, 'bad', 0, 0
t_name db 'dutest.bin', 0
t_long db 'a disk utility test file with a long name', 0
m_nogfx db 'diskutil: no graphics', 10, 0
m_nomem db 'diskutil: no memory', 10, 0
pass db 'diskutil: PASS', 10, 0
failm db 'diskutil: FAIL '
bad db '?', 10, 0

SQX_BSS
GUI_BSS
arg resd 1
smap resd 1
mapn resd 1
hd1 resd 1
total resd 1
sq_ver resd 1
nfiles resd 1
ndirs resd 1
used resd 1
databytes resd 1
ntop resd 1
top resd TOP_N
nprob resd 1
nread resd 1
nfail resd 1
scan_n resd 1
hd0_ok resb 1
hd1_ok resb 1
sq_ok resb 1
scanning resb 1
shown_rep resb 1
alignb 4
sect resb 2048
dir resb DIR_SECTS * 512
probs resb NPROB * PLEN
pline resb 96
nm_a resb 64
nm_b resb 64
t_nf resd 1
ln resb 96
SQX_END
