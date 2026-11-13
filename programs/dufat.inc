; Squirrel-OS/2 — Disk Utility: FAT volumes (2.7, OS2-FS). Original code.
; Included by diskutil.asm.
;
; A disk that does not hold SQFS is looked at as FAT12, FAT16 or FAT32:
; its boot sector, or the first FAT partition of its partition table
; (types 01, 04, 06, 0B, 0C, 0E). The first FAT is read into memory; the
; directories are walked from the root, every file's and directory's
; cluster chain is followed, and the map is drawn from what was found:
; blue for the reserved sectors, the FATs, the fixed root and the
; directories, green for file data, light green for the rest of a file's
; last cluster, white for free, red for bad, lost or shared clusters.
;
; The check finds: chains that leave the disk, run into a free or bad
; cluster, or share clusters with another chain; files whose size does
; not fit their chain; "." and ".." entries that point elsewhere;
; long-name (VFAT) entries that do not belong to the entry after them;
; clusters in use that no file reaches (lost); FAT copies that differ
; from the first; a first FAT entry that does not match the media byte.
; Nothing is written to the disk. See documentation/apps/diskutil.md.

FAT_MEM     equ 512 * 1024      ; the first FAT, at most
FAT_BITS    equ 64 * 1024       ; one bit per cluster: 512 K clusters
F_EOC       equ 0x0FFFFFFF      ; fat_get: the end of a chain
F_BAD       equ 0x0FFFFFF7      ; fat_get: a bad cluster
FQ_MAX      equ 256             ; directories waiting to be walked
FQ_LEN      equ 32              ;   cluster, parent, root flag, name
FQ_NAME     equ 9
FT_LEN      equ 72              ; largest files: name 64, size, cluster
FT_SIZE     equ 64
FT_CLUS     equ 68
A_LFN       equ 0x0F            ; directory entry attributes
A_LABEL     equ 0x08
A_DIR       equ 0x10

; eax = sector of the volume, edi = 512-byte buffer -> CF if it failed
fat_rd:
    push eax
    push ebx
    add eax, [vbase]
    mov ebx, [hd1]
    call rd_sector
    pop ebx
    pop eax
    ret

; esi = a sector -> CF unless it is a FAT boot sector we can read
bpb_ok:
    push eax
    push edx
    cmp word [esi+11], 512
    jne .no
    movzx eax, byte [esi+13]    ; sectors per cluster: a power of two
    test eax, eax
    jz .no
    lea edx, [eax-1]
    test eax, edx
    jnz .no
    cmp word [esi+14], 0        ; reserved sectors
    je .no
    mov al, [esi+16]            ; FATs
    cmp al, 1
    jb .no
    cmp al, 4
    ja .no
    cmp word [esi+19], 0        ; sectors
    jne .fs
    cmp dword [esi+32], 0
    je .no
.fs:
    cmp word [esi+22], 0        ; FAT size
    jne .yes
    cmp dword [esi+36], 0
    je .no
.yes:
    pop edx
    pop eax
    clc
    ret
.no:
    pop edx
    pop eax
    stc
    ret

; sect = the disk's sector 0 -> CF unless a FAT volume was found: the
; volume's numbers (vbase, fspc, ..., total) set, fat_ok = 1
fat_probe:
    pushad
    mov dword [vbase], 0
    mov esi, sect
    call bpb_ok
    jnc .got
    cmp word [sect+510], 0xAA55 ; a partition table
    jne .no
    mov esi, sect + 446
    mov ecx, 4
.pe:
    mov al, [esi+4]
    mov edi, fat_ptypes
    push ecx
    mov ecx, 6
    repne scasb
    pop ecx
    je .part
    add esi, 16
    loop .pe
    jmp .no
.part:
    mov eax, [esi+8]
    test eax, eax
    jz .no
    mov [vbase], eax
    mov ebx, [hd1]
    mov edi, sect
    call rd_sector
    jc .no
    mov esi, sect
    call bpb_ok
    jc .no
.got:
    movzx eax, byte [sect+13]
    mov [fspc], eax
    shl eax, 9
    mov [fclbytes], eax
    movzx eax, word [sect+14]
    mov [frsv], eax
    movzx eax, byte [sect+16]
    mov [fnfats], eax
    mov al, [sect+21]
    mov [fmedia], al
    movzx eax, word [sect+19]
    test eax, eax
    jnz .tot
    mov eax, [sect+32]
.tot:
    mov [fsects], eax
    mov dword [frootcl], 0
    movzx eax, word [sect+22]
    test eax, eax
    jnz .fsz
    mov eax, [sect+36]
    mov edx, [sect+44]
    mov [frootcl], edx
.fsz:
    mov [ffatsz], eax
    mul dword [fnfats]
    add eax, [frsv]
    mov [frootlba], eax
    movzx eax, word [sect+17]   ; the fixed root's sectors
    shl eax, 5
    add eax, 511
    shr eax, 9
    mov [frootsecs], eax
    add eax, [frootlba]
    mov [fdatalba], eax
    mov ecx, [fsects]
    cmp ecx, eax
    jbe .no
    sub ecx, eax
    mov eax, ecx
    xor edx, edx
    div dword [fspc]
    test eax, eax
    jz .no
    inc eax
    mov [fmaxcl], eax           ; clusters 2 .. fmaxcl
    dec eax
    mov dword [ftype], 12       ; the type follows from the clusters
    cmp eax, 4085
    jb .typed
    mov dword [ftype], 16
    cmp eax, 65525
    jb .typed
    mov dword [ftype], 32
    cmp dword [frootcl], 2
    jb .no
.typed:
    mov eax, [fsects]
    dec eax
    mov [total], eax
    mov byte [fat_ok], 1
    popad
    clc
    ret
.no:
    mov dword [vbase], 0
    popad
    stc
    ret

; the volume's map: its sectors in units of 2^mshift, the system area blue
fat_map_init:
    pushad
    mov eax, [total]
    inc eax
    xor ecx, ecx
.sh:
    mov edx, eax
    shr edx, cl
    cmp edx, MAP_MAX            ; (rounded up, it still fits)
    jb .shd
    inc ecx
    jmp .sh
.shd:
    mov [mshift], ecx
    mov edx, 1
    shl edx, cl
    dec edx
    add eax, edx
    shr eax, cl
    mov [mapn], eax
    mov edi, [smap]
    mov ecx, eax
    xor eax, eax
    rep stosb
    xor eax, eax                ; reserved, FATs, fixed root
.m:
    cmp eax, [fdatalba]
    jae .r
    mov cl, M_META
    call map_mark
    inc eax
    jmp .m
.r:
    popad
    ret

; eax = sector of the volume, cl = a map kind: its unit takes the kind
; if that ranks higher than what is there
map_mark:
    pushad
    mov dl, cl
    mov ecx, [mshift]
    shr eax, cl
    cmp eax, [mapn]
    jae .r
    add eax, [smap]
    movzx ebx, byte [eax]
    mov bl, [rank+ebx]
    movzx ecx, dl
    cmp bl, [rank+ecx]
    jae .r
    mov [eax], dl
.r:
    popad
    ret

; the first FAT into memory -> CF if it does not fit (fat_big set)
fat_load:
    pushad
    mov byte [fat_big], 1
    cmp dword [fat_mem], 0      ; the memory, the first time
    jne .have
    mov eax, SYS_SBRK
    mov ebx, FAT_MEM + FAT_BITS
    int 0x80
    cmp eax, -1
    je .no
    mov [fat_mem], eax
    add eax, FAT_MEM
    mov [fbits], eax
.have:
    mov eax, [fmaxcl]           ; the bytes of FAT that matter
    inc eax
    cmp dword [ftype], 12
    jne .b16
    mov edx, eax
    shr edx, 1
    add eax, edx
    inc eax
    jmp .bs
.b16:
    shl eax, 1
    cmp dword [ftype], 16
    je .bs
    shl eax, 1
.bs:
    cmp eax, FAT_MEM
    ja .no
    mov ecx, [fmaxcl]
    shr ecx, 3
    cmp ecx, FAT_BITS - 1
    jae .no
    add eax, 511
    shr eax, 9
    cmp eax, [ffatsz]
    jbe .n
    mov eax, [ffatsz]
.n:
    mov [fatn], eax             ; sectors read
    mov ecx, eax
    mov eax, [frsv]
    mov edi, [fat_mem]
.rd:
    call fat_rd
    jc .no
    inc eax
    add edi, 512
    loop .rd
    mov byte [fat_big], 0
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; eax = cluster -> eax = its FAT entry (F_EOC for any end, F_BAD)
fat_get:
    push ebx
    push edx
    mov ebx, [fat_mem]
    cmp dword [ftype], 12
    jne .f16
    mov edx, eax
    shr edx, 1
    add edx, eax
    movzx edx, word [ebx+edx]
    test eax, 1
    jz .ev
    shr edx, 4
.ev:
    and edx, 0xFFF
    cmp edx, 0xFF7
    jb .val
    je .bad
    jmp .eoc
.f16:
    cmp dword [ftype], 16
    jne .f32
    movzx edx, word [ebx+eax*2]
    cmp edx, 0xFFF7
    jb .val
    je .bad
    jmp .eoc
.f32:
    mov edx, [ebx+eax*4]
    and edx, 0x0FFFFFFF
    cmp edx, F_BAD
    jb .val
    je .bad
.eoc:
    mov eax, F_EOC
    jmp .r
.bad:
    mov eax, F_BAD
    jmp .r
.val:
    mov eax, edx
.r:
    pop edx
    pop ebx
    ret

; eax = cluster, edx = value (F_EOC for an end): the FAT in memory only
; (the self-test damages it there)
fat_put:
    pushad
    mov ebx, [fat_mem]
    cmp dword [ftype], 12
    jne .f16
    and edx, 0xFFF
    mov ecx, eax
    shr ecx, 1
    add ecx, eax
    test eax, 1
    jz .ev
    shl edx, 4
    and word [ebx+ecx], 0x000F
    or [ebx+ecx], dx
    jmp .r
.ev:
    and word [ebx+ecx], 0xF000
    or [ebx+ecx], dx
    jmp .r
.f16:
    cmp dword [ftype], 16
    jne .f32
    mov [ebx+eax*2], dx
    jmp .r
.f32:
    and edx, 0x0FFFFFFF
    and dword [ebx+eax*4], 0xF0000000
    or [ebx+eax*4], edx
.r:
    popad
    ret

; eax = cluster -> eax = its first sector in the volume
cl_sector:
    push edx
    sub eax, 2
    mul dword [fspc]
    add eax, [fdatalba]
    pop edx
    ret

; eax = cluster, ecx = its place in the chain (0 first), edx = the
; file's size or -1 for a directory: its sectors on the map
mark_cluster:
    pushad
    mov ebx, ecx
    call cl_sector
    mov esi, eax                ; its sectors
    mov eax, ebx
    mul dword [fclbytes]
    mov edi, eax                ; the file offset of each
    mov edx, [esp+20]           ; (the size, from pushad)
    mov ebx, [fspc]
.s:
    mov cl, M_META
    cmp edx, -1
    je .k
    mov cl, M_DATA
    cmp edi, edx
    jb .k
    mov cl, M_SLACK
.k:
    mov eax, esi
    call map_mark
    inc esi
    add edi, 512
    dec ebx
    jnz .s
    popad
    ret

; eax = cluster: all its sectors red
mark_cl_bad:
    pushad
    call cl_sector
    mov ebx, [fspc]
.s:
    mov cl, M_BAD
    call map_mark
    inc eax
    dec ebx
    jnz .s
    popad
    ret

; eax = first cluster, edx = size or -1 (a directory), nm_a = its name
; -> ecx = the chain's length; its clusters taken in fbits and mapped;
; problems for chains that leave the disk, meet a free or bad cluster or
; another chain
follow_chain:
    push eax
    push ebx
    xor ecx, ecx
.c:
    cmp eax, 2
    jb .out
    cmp eax, [fmaxcl]
    ja .out
    mov ebx, [fbits]
    bts dword [ebx], eax
    jc .cross
    call mark_cluster
    inc ecx
    call fat_get
    cmp eax, F_EOC
    je .end
    cmp eax, F_BAD
    je .badc
    test eax, eax
    jz .free
    cmp ecx, [fmaxcl]
    jbe .c
    jmp .end
.out:
    push edx
    mov edx, p_fout
    call nproblem
    pop edx
    jmp .end
.cross:
    call mark_cl_bad
    push edx
    mov edx, p_fcross
    call nproblem
    pop edx
    jmp .end
.badc:
    push edx
    mov edx, p_fbadc
    call nproblem
    pop edx
    jmp .end
.free:
    push edx
    mov edx, p_ffree
    call nproblem
    pop edx
.end:
    pop ebx
    pop eax
    ret

; the whole volume: map, counts, largest files, problems (nprob)
fat_analyse:
    pushad
    mov dword [nprob], 0
    call fat_map_init
    call fat_load
    jc .big
    call fat_check_mem
    jmp .r
.big:
    mov esi, p_fbig
    call problem
.r:
    popad
    ret

; the walk and the counts from the FAT in memory (the self-test calls
; this again after damaging it)
fat_check_mem:
    pushad
    mov dword [nprob], 0
    call fat_map_init
    mov edi, [fbits]
    mov ecx, [fmaxcl]
    shr ecx, 3
    inc ecx
    xor eax, eax
    rep stosb
    call fat_walk
    call fat_count
    call fat_copies
    popad
    ret

; every directory from the root (a queue of them, FQ_MAX at a time)
fat_walk:
    pushad
    xor eax, eax
    mov [nfiles], eax
    mov [ndirs], eax
    mov [databytes], eax
    mov [nftop], eax
    mov [fq_full], al
    mov edi, fq                 ; the root
    mov ecx, FQ_LEN / 4
    rep stosd
    mov eax, [frootcl]
    mov [fq], eax
    mov byte [fq+8], 1
    mov byte [fq+FQ_NAME], '/'
    mov dword [fqn], 1
    test eax, eax               ; FAT32: the root's chain
    jz .q
    mov word [nm_a], '/'
    mov edx, -1
    call follow_chain
.q:
    xor ebx, ebx
.w:
    cmp ebx, [fqn]
    jae .r
    imul esi, ebx, FQ_LEN
    add esi, fq
    call walk_dir
    inc ebx
    jmp .w
.r:
    popad
    ret

; esi = a queued directory: each of its entries
walk_dir:
    pushad
    mov [wd_rec], esi
    mov byte [lf_on], 0
    mov eax, [esi]
    test eax, eax
    jnz .chain
    mov eax, [frootlba]         ; FAT12/16's fixed root
    mov ecx, [frootsecs]
.fx:
    mov edi, fsec
    call fat_rd
    jc .r
    call dir_sector
    jc .r
    inc eax
    loop .fx
    jmp .r
.chain:
    xor ebp, ebp                ; clusters so far
.cl:
    push eax
    call cl_sector
    mov ecx, [fspc]
.cs:
    mov edi, fsec
    call fat_rd
    jc .csd
    call dir_sector
    jc .csd
    inc eax
    loop .cs
    pop eax
    call fat_get
    cmp eax, 2
    jb .r
    cmp eax, [fmaxcl]
    ja .r
    inc ebp
    cmp ebp, [fmaxcl]
    jbe .cl
    jmp .r
.csd:
    pop eax
.r:
    popad
    ret

; fsec = 16 directory entries -> CF at the end of the directory
dir_sector:
    pushad
    mov edi, fsec
    mov ecx, 16
.e:
    call dir_entry
    jc .end
    add edi, 32
    loop .e
    popad
    clc
    ret
.end:
    popad
    stc
    ret

; edi = a directory entry of the directory wd_rec -> CF if it ends it
dir_entry:
    pushad
    mov al, [edi]
    test al, al
    jz .end
    cmp al, 0xE5
    je .gone
    mov al, [edi+11]
    and al, 0x3F
    cmp al, A_LFN
    je .lfn
    test byte [edi+11], A_LABEL
    jnz .gone
    call sum11                  ; a short entry: its long name?
    cmp byte [lf_on], 0
    je .short
    cmp byte [lf_exp], 1
    jne .orph
    cmp al, [lf_sum]
    jne .orph
    mov byte [lf_on], 0
    mov esi, lname
    push edi
    mov edi, nm_a
    mov ecx, 16
    rep movsd
    pop edi
    jmp .named
.orph:
    call lfn_orphan
.short:
    call short_name
.named:
    cmp byte [edi], '.'
    je .dots
    movzx eax, word [edi+26]    ; its first cluster
    cmp dword [ftype], 32
    jne .c16
    movzx edx, word [edi+20]
    shl edx, 16
    or eax, edx
.c16:
    mov edx, [edi+28]
    test byte [edi+11], A_DIR
    jnz .dir
    inc dword [nfiles]          ; a file
    add [databytes], edx
    xor ecx, ecx
    test eax, eax
    jz .len
    call follow_chain
.len:
    push eax
    mov eax, edx                ; the clusters its size needs
    add eax, [fclbytes]
    jc .lbad
    dec eax
    push edx
    xor edx, edx
    div dword [fclbytes]
    pop edx
    cmp eax, ecx
    je .lok
.lbad:
    push edx
    mov edx, p_fsize
    call nproblem
    pop edx
.lok:
    pop eax
    mov eax, edx
    call ftop_add
    jmp .ok
.dir:
    inc dword [ndirs]
    mov edx, -1
    call follow_chain
    test ecx, ecx
    jz .ok
    mov ecx, [fqn]              ; walk it later
    cmp ecx, FQ_MAX
    jb .qa
    cmp byte [fq_full], 0
    jne .ok
    mov byte [fq_full], 1
    mov esi, p_fqfull
    call problem
    jmp .ok
.qa:
    inc dword [fqn]
    imul ecx, FQ_LEN
    add ecx, fq
    mov [ecx], eax
    mov esi, [wd_rec]           ; its parent: 0 for the root
    xor edx, edx
    cmp byte [esi+8], 0
    jne .qp
    mov edx, [esi]
.qp:
    mov [ecx+4], edx
    mov byte [ecx+8], 0
    lea edi, [ecx+FQ_NAME]
    mov esi, nm_a
    mov ecx, FQ_LEN - FQ_NAME - 1
.qn:
    lodsb
    stosb
    test al, al
    jz .ok
    loop .qn
    mov byte [edi], 0
    jmp .ok
.dots:                          ; "." is this directory, ".." its parent
    movzx eax, word [edi+26]
    cmp dword [ftype], 32
    jne .d16
    movzx edx, word [edi+20]
    shl edx, 16
    or eax, edx
.d16:
    mov esi, [wd_rec]
    mov edx, [esi]
    cmp byte [edi+1], '.'
    jne .dc
    mov edx, [esi+4]
.dc:
    cmp eax, edx
    je .ok
    lea esi, [esi+FQ_NAME]      ; named after the directory
    push edi
    mov edi, nm_a
    mov ecx, FQ_LEN - FQ_NAME
    rep movsb
    pop edi
    mov edx, p_fdot
    call nproblem
    jmp .ok
.lfn:
    call lfn_part
    jmp .ok
.gone:
    cmp byte [lf_on], 0
    je .ok
    call lfn_orphan
.ok:
    popad
    clc
    ret
.end:
    cmp byte [lf_on], 0
    je .e2
    call lfn_orphan
.e2:
    popad
    stc
    ret

; long-name entries that no short entry took: one problem
lfn_orphan:
    pushad
    mov byte [lf_on], 0
    mov esi, lname
    mov edi, nm_a
    mov ecx, 16
    rep movsd
    mov edx, p_forph
    call nproblem
    popad
    ret

; edi = a long-name entry: its 13 characters into lname
lfn_part:
    pushad
    movzx eax, byte [edi]
    test al, 0x40
    jz .next
    cmp byte [lf_on], 0         ; the first (the name's last part)
    je .first
    call lfn_orphan
.first:
    and al, 0x1F
    jz .bad
    cmp al, 20
    ja .bad
    mov byte [lf_on], 1
    mov [lf_exp], al
    mov dl, [edi+13]
    mov [lf_sum], dl
    push edi
    push eax
    mov edi, lname
    mov ecx, 64 / 4
    xor eax, eax
    rep stosd
    pop eax
    pop edi
    jmp .chars
.next:
    cmp byte [lf_on], 0
    je .bad
    inc al
    cmp al, [lf_exp]
    jne .bad
    dec al
    mov dl, [edi+13]
    cmp dl, [lf_sum]
    jne .bad
    mov [lf_exp], al
.chars:
    dec eax                     ; its characters from (seq - 1) * 13
    imul ebx, eax, 13
    mov esi, lfn_offs
    mov ecx, 13
.ch:
    movzx eax, byte [esi]
    movzx eax, word [edi+eax]
    test eax, eax
    jz .z
    cmp eax, 0xFFFF
    je .nx
    cmp eax, 0x100
    jb .put
    mov al, '?'
.put:
    cmp ebx, 63
    jae .nx
    mov [lname+ebx], al
    jmp .nx
.z:
    cmp ebx, 63
    jae .nx
    mov byte [lname+ebx], 0
.nx:
    inc ebx
    inc esi
    loop .ch
    popad
    ret
.bad:
    cmp byte [lf_on], 0
    je .bad2
    call lfn_orphan
    popad
    ret
.bad2:
    mov word [lname], '?'       ; a stray part
    mov edx, p_forph
    mov esi, lname
    push edi
    mov edi, nm_a
    mov ecx, 16
    rep movsd
    pop edi
    call nproblem
    popad
    ret

; edi = short entry -> al = the checksum of its 11-byte name
sum11:
    push ecx
    push esi
    mov esi, edi
    mov ecx, 11
    xor al, al
.l:
    ror al, 1
    add al, [esi]
    inc esi
    loop .l
    pop esi
    pop ecx
    ret

; edi = short entry -> nm_a = "NAME.EXT" (lower case where its case
; bits say so)
short_name:
    pushad
    mov esi, edi
    mov edi, nm_a
    mov bl, [esi+12]            ; 0x08 the name, 0x10 the extension
    mov edx, 8
    xor ecx, ecx
.b:
    mov al, [esi+ecx]
    cmp ecx, 0
    jne .b1
    cmp al, 0x05
    jne .b1
    mov al, 0xE5
.b1:
    test bl, 0x08
    jz .b2
    call lower
.b2:
    stosb
    inc ecx
    cmp ecx, edx
    jb .b
.tb:                            ; trailing spaces off
    cmp edi, nm_a
    je .ext
    cmp byte [edi-1], ' '
    jne .ext
    dec edi
    jmp .tb
.ext:
    cmp byte [esi+8], ' '
    je .z
    mov al, '.'
    stosb
    mov ecx, 8
.e:
    mov al, [esi+ecx]
    test bl, 0x10
    jz .e1
    call lower
.e1:
    stosb
    inc ecx
    cmp ecx, 11
    jb .e
.te:
    cmp byte [edi-1], ' '
    jne .z
    dec edi
    jmp .te
.z:
    mov byte [edi], 0
    popad
    ret

lower:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    or al, 0x20
.r:
    ret

; nm_a = name, eax = size, the file's first cluster in its entry (edi):
; among the largest files, if it is one
ftop_add:
    pushad
    movzx ebp, word [edi+26]    ; its first cluster (for the self-test)
    cmp dword [ftype], 32
    jne .c
    movzx edx, word [edi+20]
    shl edx, 16
    or ebp, edx
.c:
    mov ecx, [nftop]
    xor ebx, ebx
.f:
    cmp ebx, ecx
    jae .at
    imul edi, ebx, FT_LEN
    cmp eax, [ftop+edi+FT_SIZE]
    ja .at
    inc ebx
    jmp .f
.at:
    cmp ebx, TOP_N
    jae .r
    mov edx, ecx                ; move the smaller ones down
    cmp edx, TOP_N - 1
    jbe .m
    mov edx, TOP_N - 1
.m:
    cmp edx, ebx
    jbe .put
    push eax
    imul esi, edx, FT_LEN
    lea edi, [ftop+esi]
    lea esi, [ftop+esi-FT_LEN]
    mov ecx, FT_LEN / 4
    rep movsd
    pop eax
    dec edx
    jmp .m
.put:
    imul edi, ebx, FT_LEN
    add edi, ftop
    mov [edi+FT_SIZE], eax
    mov [edi+FT_CLUS], ebp
    mov esi, nm_a
    mov ecx, 64 / 4
    rep movsd
    cmp dword [nftop], TOP_N
    jae .r
    inc dword [nftop]
.r:
    popad
    ret

; every cluster's FAT entry: used, bad, lost (in use, but no chain
; reached it)
fat_count:
    pushad
    xor eax, eax
    mov [fused], eax
    mov [fbad], eax
    mov [flost], eax
    mov ebx, 2
.c:
    cmp ebx, [fmaxcl]
    ja .d
    mov eax, ebx
    call fat_get
    test eax, eax
    jz .n
    cmp eax, F_BAD
    jne .u
    inc dword [fbad]
    mov eax, ebx
    call mark_cl_bad
    jmp .n
.u:
    inc dword [fused]
    mov edx, [fbits]
    bt dword [edx], ebx
    jc .n
    inc dword [flost]
    mov eax, ebx
    call mark_cl_bad
.n:
    inc ebx
    jmp .c
.d:
    cmp dword [flost], 0
    je .r
    mov edi, pline              ; "12 clusters in use by no file"
    mov eax, [flost]
    call gui_utoa
    mov esi, p_flost
    call scopy
    mov esi, pline
    call problem
.r:
    popad
    ret

; the other FATs against the first; the first entry against the media byte
fat_copies:
    pushad
    mov al, [fmedia]
    mov edx, [fat_mem]
    cmp al, [edx]
    je .cp
    mov esi, p_fmedia
    call problem
.cp:
    mov ebx, 1
.k:
    cmp ebx, [fnfats]
    jae .r
    mov eax, [ffatsz]
    mul ebx
    add eax, [frsv]
    mov ebp, [fat_mem]
    mov edx, [fatn]
.s:
    mov edi, fsec
    call fat_rd
    jc .diff
    mov esi, ebp
    mov ecx, 128
    repe cmpsd
    jne .diff
    inc eax
    add ebp, 512
    dec edx
    jnz .s
    jmp .n
.diff:
    mov edi, pline              ; "FAT copy 2 differs from the first"
    mov esi, p_fcopy
    call scopy
    lea eax, [ebx+1]
    call gui_utoa
    mov esi, p_fcopy2
    call scopy
    mov esi, pline
    call problem
.n:
    inc ebx
    jmp .k
.r:
    popad
    ret

; edx = what is wrong, nm_a = whose: "name: what"
nproblem:
    pushad
    mov esi, nm_a
    jmp eproblem.cut

; ---------- the FAT self-test: run diskutil test hd2 ----------
; The disk: tools/regress.sh makes it with tools/fatimg.py: a directory
; "docs", README.TXT (24 bytes) and "docs/A Long Document Name.txt"
; (14 bytes), so that both files keep one cluster each.
fat_selftest:
    mov byte [bad], 'A'         ; A: found, read, no problems
    call analyse
    cmp byte [fat_ok], 1
    jne fail
    cmp byte [fat_big], 0
    jne fail
    cmp dword [nprob], 0
    jne fail
    cmp dword [nfiles], 2
    jne fail
    cmp dword [ndirs], 1
    jne fail
    cmp dword [nftop], 2
    jne fail
    mov esi, ftop               ; the larger first
    cmp dword [esi+FT_SIZE], 24
    jne fail
    mov edi, t_readme
    call streq
    jne fail
    lea esi, [ftop+FT_LEN]      ; the long name read
    mov edi, t_flong
    call streq
    jne fail
    inc byte [bad]              ; B: a lost cluster, a FAT copy differs
    mov eax, 2
.free:
    cmp eax, [fmaxcl]
    ja fail
    push eax
    call fat_get
    test eax, eax
    pop eax
    jz .take
    inc eax
    jmp .free
.take:
    mov edx, F_EOC
    call fat_put
    call fat_check_mem
    mov edi, p_flost
    call any_prob
    jc fail
    cmp dword [flost], 1
    jne fail
    cmp dword [fnfats], 2
    jb .c
    mov edi, p_fcopy2
    call any_prob
    jc fail
.c:
    inc byte [bad]              ; C: one file's chain runs into the other's
    call analyse
    mov eax, [ftop+FT_CLUS]
    mov edx, [ftop+FT_LEN+FT_CLUS]
    call fat_put
    call fat_check_mem
    mov edi, p_fcross
    call any_prob
    jc fail
    mov edi, p_fsize            ; (and the first is now too long)
    call any_prob
    jc fail
    inc byte [bad]              ; D: the map: data green, lost red
    call analyse
    mov eax, [ftop+FT_CLUS]
    call cl_sector
    mov ecx, [mshift]
    shr eax, cl
    add eax, [smap]
    cmp byte [eax], M_DATA
    jne fail
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
