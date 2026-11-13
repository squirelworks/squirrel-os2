; Squirrel-OS/2 — FAT12/16/32 read and write (2.7)
; Included from pm.asm, in the high image. Original code, written from the
; published FAT and long-file-name on-disk format descriptions.
;
; A FAT volume is mounted on a drive letter (volume.asm) and reached with
; paths that start with it: "d:/docs/Long name.txt". The SQFS calls
; (fs_open, fs_read, ..., fs_create, fs_mkdir, fs_delete, fs_rename) hand
; such paths and descriptors to the routines here, so the shell, the
; editors and programs (SYS_OPEN ...) work on FAT without knowing it.
;
; - FAT12, FAT16 and FAT32 by cluster count; 512-byte sectors.
; - Long names (VFAT) are read and written; a name that is not a plain
;   8.3 name gets long-name entries and a unique short alias (NAME~1.EXT).
;   Names compare without regard to case, as on DOS and OS/2.
; - All FAT copies are written. FAT32's FSInfo free count is marked
;   unknown on the first change, so other systems recount.
; - Directories grow by a cluster when full (not FAT12/16's fixed root).
; See documentation/kernel/fat.md.

FAT_EOC       equ 0x0FFFFFFF      ; end of chain, as fat_get returns it
FA_RO         equ 0x01
FA_LABEL      equ 0x08
FA_DIR        equ 0x10
FA_ARCH       equ 0x20
FA_LFN        equ 0x0F

; directory entry
FE_DNAME      equ 0               ; 8 + 3, space-padded
FE_DATTR      equ 11
FE_DCASE      equ 12              ; 0x08 base, 0x10 extension in lower case
FE_DCTIME     equ 14
FE_DCDATE     equ 16
FE_DADATE     equ 18
FE_DCLHI      equ 20
FE_DMTIME     equ 22
FE_DMDATE     equ 24
FE_DCLLO      equ 26
FE_DSIZE      equ 28

FAT_NAMEBUF   equ 13*20+4         ; long names as found on disk (up to 260)
FAT_MAXRUN    equ 8               ; long-name entries + the short one we write

; open FAT file (one per descriptor; FD_DIRENT points here)
FF_VOL        equ 0
FF_FIRST      equ 4               ; first cluster, 0 = none yet
FF_SIZE       equ 8
FF_LBA        equ 12              ; sector of its short entry
FF_OFF        equ 16              ; offset of it in that sector
FF_CIDX       equ 20              ; cluster index last looked up, -1 none
FF_CCL        equ 24              ; ... and that cluster
FF_LEN        equ 32

; ---------- sectors ----------

; ebp = volume, ecx = sector in the volume, edi = buffer -> CF on error
vol_rsec:
    pushad
    call vol_lba
    jc .bad
    call dev_bread
.bad:
    popad
    ret

; ebp = volume, ecx = sector, esi = buffer -> CF on error (or read-only)
vol_wsec:
    pushad
    test byte [ebp+V_FLAGS], VF_RO
    jnz .bad
    call vol_lba
    jc .r
    call dev_bwrite
.r:
    popad
    ret
.bad:
    popad
    stc
    ret

; ebp = volume, ecx = sector in it -> ebx = device, ecx = its sector
vol_lba:
    cmp ecx, [ebp+V_SECTS]
    jae .bad
    add ecx, [ebp+V_BASE]
    mov ebx, [ebp+V_LOOP]       ; an image file on the SQFS disk?
    test ebx, ebx
    jz .dev
    add ecx, [ebx+DE_START]
    mov ebx, [fs_dev]
    clc
    ret
.dev:
    mov ebx, [ebp+V_DEV]
    clc
    ret
.bad:
    stc
    ret

; ---------- the FAT (one sector cached) ----------

; ebp = volume, eax = byte offset in the FAT -> esi = that byte in
; fc_buf; CF on error
fat_ptr:
    push eax
    push ecx
    push edi
    mov ecx, eax
    shr ecx, 9
    cmp ebp, [fc_vol]
    jne .load
    cmp ecx, [fc_sec]
    je .have
.load:
    call fat_flush
    jc .err
    mov [fc_vol], ebp
    mov dword [fc_sec], -1
    push ecx
    add ecx, [ebp+V_FATLBA]
    mov edi, fc_buf
    call vol_rsec
    pop ecx
    jc .err
    mov [fc_sec], ecx
.have:
    and eax, SECTOR_SIZE-1
    lea esi, [fc_buf+eax]
    pop edi
    pop ecx
    pop eax
    clc
    ret
.err:
    pop edi
    pop ecx
    pop eax
    stc
    ret

; Writes the cached FAT sector to every copy of the FAT if it changed.
fat_flush:
    pushad
    cmp byte [fc_dirty], 0
    je .ok
    mov ebp, [fc_vol]
    mov ecx, [fc_sec]
    add ecx, [ebp+V_FATLBA]
    movzx edx, byte [ebp+V_NFATS]
.w:
    mov esi, fc_buf
    call vol_wsec
    jc .bad
    add ecx, [ebp+V_FATSZ]
    dec edx
    jnz .w
    mov byte [fc_dirty], 0
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; Forgets the cache (after a volume goes away)
fat_drop_cache:
    mov dword [fc_vol], 0
    mov dword [fc_sec], -1
    mov byte [fc_dirty], 0
    ret

; ebp = volume, eax = cluster -> eax = the next one: 0 free, FAT_EOC at
; the end of the chain (bad or out-of-range values read as the end too).
; CF on a disk error.
fat_get:
    push ecx
    push edx
    push esi
    mov ecx, eax
    cmp byte [ebp+V_TYPE], 12
    je .f12
    cmp byte [ebp+V_TYPE], 16
    je .f16
    shl eax, 2
    call fat_ptr
    jc .err
    mov eax, [esi]
    and eax, 0x0FFFFFFF
    jmp .chk
.f16:
    shl eax, 1
    call fat_ptr
    jc .err
    movzx eax, word [esi]
    jmp .chk
.f12:
    mov eax, ecx
    shr eax, 1
    add eax, ecx
    call fat_ptr
    jc .err
    movzx edx, byte [esi]
    inc eax
    call fat_ptr
    jc .err
    movzx eax, byte [esi]
    shl eax, 8
    or eax, edx
    test ecx, 1
    jz .even
    shr eax, 4
    jmp .chk
.even:
    and eax, 0xFFF
.chk:
    test eax, eax
    jz .ok
    cmp eax, 2
    jb .end
    cmp eax, [ebp+V_MAXCL]
    jbe .ok
.end:
    mov eax, FAT_EOC
.ok:
    pop esi
    pop edx
    pop ecx
    clc
    ret
.err:
    pop esi
    pop edx
    pop ecx
    stc
    ret

; ebp = volume, eax = cluster, edx = value (FAT_EOC for the end) -> CF
fat_set:
    pushad
    mov ecx, eax
    cmp byte [ebp+V_TYPE], 12
    je .f12
    cmp byte [ebp+V_TYPE], 16
    je .f16
    shl eax, 2
    call fat_ptr
    jc .err
    and edx, 0x0FFFFFFF
    mov ebx, [esi]
    and ebx, 0xF0000000         ; the top four bits are kept
    or ebx, edx
    mov [esi], ebx
    jmp .dirty
.f16:
    shl eax, 1
    call fat_ptr
    jc .err
    mov [esi], dx
    jmp .dirty
.f12:
    and edx, 0xFFF
    mov eax, ecx
    shr eax, 1
    add eax, ecx                ; byte offset
    call fat_ptr
    jc .err
    test ecx, 1
    jz .even
    mov bl, dl                  ; odd: high nibble of the first byte
    shl bl, 4
    mov bh, [esi]
    and bh, 0x0F
    or bh, bl
    mov [esi], bh
    mov byte [fc_dirty], 1
    inc eax
    call fat_ptr
    jc .err
    mov ebx, edx
    shr ebx, 4
    mov [esi], bl
    jmp .dirty
.even:
    mov [esi], dl               ; even: the first byte, low nibble of the next
    mov byte [fc_dirty], 1
    inc eax
    call fat_ptr
    jc .err
    mov bl, [esi]
    and bl, 0xF0
    mov bh, dh
    and bh, 0x0F
    or bl, bh
    mov [esi], bl
.dirty:
    mov byte [fc_dirty], 1
    call fat_fsinfo_unknown
    popad
    clc
    ret
.err:
    popad
    stc
    ret

; FAT32: on the first change since mounting, mark FSInfo's free count and
; next-free hint unknown.
fat_fsinfo_unknown:
    test byte [ebp+V_FLAGS], VF_FSINFO
    jz .r
    and byte [ebp+V_FLAGS], ~VF_FSINFO
    pushad
    mov ecx, [ebp+V_FSINFO]
    mov edi, fe_sec
    call vol_rsec
    jc .o
    cmp dword [fe_sec+484], 0x61417272
    jne .o
    mov dword [fe_sec+488], -1
    mov dword [fe_sec+492], -1
    mov esi, fe_sec
    call vol_wsec
.o:
    popad
.r:
    ret

; ebp = volume -> eax = a free cluster, now the end of a chain of its own.
; CF (fs_errno FE_FULL or FE_IO) if there is none.
fat_alloc:
    push ecx
    push edx
    mov eax, [ebp+V_HINT]
    mov ecx, [ebp+V_MAXCL]
    dec ecx                     ; clusters to look at
.l:
    cmp eax, 2
    jb .wrap
    cmp eax, [ebp+V_MAXCL]
    jbe .try
.wrap:
    mov eax, 2
.try:
    push eax
    call fat_get
    mov edx, eax
    pop eax
    jc .io
    test edx, edx
    jz .found
    inc eax
    loop .l
    mov byte [fs_errno], FE_FULL
    jmp .no
.found:
    mov edx, FAT_EOC
    call fat_set
    jc .io
    lea edx, [eax+1]
    mov [ebp+V_HINT], edx
    pop edx
    pop ecx
    clc
    ret
.io:
    mov byte [fs_errno], FE_IO
.no:
    pop edx
    pop ecx
    stc
    ret

; ebp = volume, eax = first cluster (0: nothing) -> frees the chain. CF.
fat_free_chain:
    pushad
.l:
    cmp eax, 2
    jb .ok
    cmp eax, FAT_EOC
    je .ok
    mov ebx, eax
    call fat_get
    jc .bad
    xchg eax, ebx
    xor edx, edx
    call fat_set
    jc .bad
    cmp eax, [ebp+V_HINT]
    jae .h
    mov [ebp+V_HINT], eax
.h:
    mov eax, ebx
    jmp .l
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; ebp = volume -> eax = free clusters (reads the whole FAT)
fat_count_free:
    push ebx
    push ecx
    xor ebx, ebx
    mov ecx, 2
.l:
    cmp ecx, [ebp+V_MAXCL]
    ja .d
    mov eax, ecx
    call fat_get
    jc .d
    test eax, eax
    jnz .n
    inc ebx
.n:
    inc ecx
    jmp .l
.d:
    mov eax, ebx
    pop ecx
    pop ebx
    ret

; ebp = volume, eax = cluster -> ecx = its first sector
fat_clsec:
    push eax
    push edx
    sub eax, 2
    movzx ecx, byte [ebp+V_SPC]
    mul ecx
    add eax, [ebp+V_DATALBA]
    mov ecx, eax
    pop edx
    pop eax
    ret

; ebp = volume, eax = cluster -> its sectors are zeroed. CF.
fat_zero_cluster:
    pushad
    mov edi, fe_zero
    mov ecx, SECTOR_SIZE/4
    push eax
    xor eax, eax
    rep stosd
    pop eax
    call fat_clsec
    movzx edx, byte [ebp+V_SPC]
.w:
    mov esi, fe_zero
    call vol_wsec
    jc .bad
    inc ecx
    dec edx
    jnz .w
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; ebp = volume -> eax = the root directory's cluster number as used here:
; 0 for FAT12/16's fixed root, the root cluster on FAT32
fat_root:
    mov eax, [ebp+V_ROOTCL]
    ret

; edi = short entry -> eax = its first cluster (0 = none)
fat_entcl:
    movzx eax, word [edi+FE_DCLHI]
    shl eax, 16
    mov ax, [edi+FE_DCLLO]
    ret

; edi = short entry, eax = cluster -> stored in it
fat_setcl:
    mov [edi+FE_DCLLO], ax
    push eax
    shr eax, 16
    mov [edi+FE_DCLHI], ax
    pop eax
    ret

; ---------- directories: raw entries ----------

; ebp = volume, eax = directory cluster (0: the fixed root) -> starts
; walking its entries with di_next
di_start:
    mov [di_clus], eax
    mov dword [di_sec], 0
    mov dword [di_ent], 0
    mov byte [di_loaded], 0
    mov byte [di_err], 0
    ret

; -> edi = the next raw entry in di_buf (di_lba, di_off say where it is
; on the disk); CF at the end of the directory (di_err set on a disk error)
di_next:
    push eax
    push ecx
    cmp byte [di_loaded], 0
    je .first
    inc dword [di_ent]
    cmp dword [di_ent], SECTOR_SIZE/32
    jb .have
    mov dword [di_ent], 0
    inc dword [di_sec]
.first:
    cmp dword [di_clus], 0
    jne .chain
    mov ecx, [di_sec]           ; the fixed root
    cmp ecx, [ebp+V_ROOTSECS]
    jae .end
    add ecx, [ebp+V_ROOTLBA]
    jmp .load
.chain:
    movzx ecx, byte [ebp+V_SPC]
    cmp [di_sec], ecx
    jb .insec
    mov eax, [di_clus]
    call fat_get
    jc .err
    cmp eax, 2
    jb .end
    cmp eax, FAT_EOC
    je .end
    mov [di_clus], eax
    mov dword [di_sec], 0
.insec:
    mov eax, [di_clus]
    call fat_clsec
    add ecx, [di_sec]
.load:
    mov [di_lba], ecx
    push edi
    mov edi, di_buf
    call vol_rsec
    pop edi
    jc .err
    mov byte [di_loaded], 1
.have:
    mov edi, [di_ent]
    shl edi, 5
    mov [di_off], edi
    add edi, di_buf
    pop ecx
    pop eax
    clc
    ret
.err:
    mov byte [di_err], 1
    mov byte [fs_errno], FE_IO
.end:
    pop ecx
    pop eax
    stc
    ret

; ebp = volume, ecx = sector, edx = offset, esi = 32 bytes -> written
; into that entry. CF.
fat_put_entry:
    pushad
    push esi
    mov edi, fe_sec
    call vol_rsec
    pop esi
    jc .bad
    lea edi, [fe_sec+edx]
    push ecx
    mov ecx, 8
    rep movsd
    pop ecx
    mov esi, fe_sec
    call vol_wsec
    jc .bad
    popad
    clc
    ret
.bad:
    mov byte [fs_errno], FE_IO
    popad
    stc
    ret

; ebp = volume, ecx = sector, edx = offset -> that entry marked deleted
fat_kill_entry:
    pushad
    mov edi, fe_sec
    call vol_rsec
    jc .bad
    mov byte [fe_sec+edx], 0xE5
    mov esi, fe_sec
    call vol_wsec
    jc .bad
    popad
    clc
    ret
.bad:
    mov byte [fs_errno], FE_IO
    popad
    stc
    ret

; ---------- directories: names ----------

; ebp = volume, eax = directory -> starts fd_next
fd_start:
    call di_start
    mov byte [lf_expect], 0
    mov byte [lf_ready], 0
    mov dword [fd_npos], 0
    ret

; -> the next visible entry (not free, not a label, not "." or ".."):
; edi = its short entry (in di_buf), fd_name = its name (long when it has
; a valid one), fd_short = its short name as "NAME.EXT", fd_pos/fd_npos =
; where its long-name entries and short entry are. CF at the end.
fd_next:
    push eax
    push ecx
    push edx
    push esi
.l:
    call di_next
    jc .end
    mov al, [edi]
    test al, al
    jz .end                     ; the end marker
    cmp al, 0xE5
    je .reset
    mov al, [edi+FE_DATTR]
    and al, 0x3F
    cmp al, FA_LFN
    je .lfn
    test byte [edi+FE_DATTR], FA_LABEL
    jnz .reset
    cmp byte [edi], '.'
    je .reset
    ; a short entry: the long name before it belongs to it if complete
    ; and its checksum matches
    call fd_addpos
    call fat_fmt_short
    cmp byte [lf_ready], 0
    je .short
    call fat_sum11
    cmp al, [lf_sum]
    jne .short
    mov esi, lf_buf
    jmp .named
.short:
    mov eax, [fd_npos]          ; only the short entry
    mov ecx, [fd_pos+eax*8-8]
    mov edx, [fd_pos+eax*8-4]
    mov [fd_pos], ecx
    mov [fd_pos+4], edx
    mov dword [fd_npos], 1
    mov esi, fd_short
.named:
    push edi
    mov edi, fd_name
    mov ecx, FAT_NAMEBUF-1
.c:
    lodsb
    stosb
    test al, al
    jz .cd
    loop .c
    mov byte [edi], 0
.cd:
    pop edi
    mov byte [lf_ready], 0
    mov byte [lf_expect], 0
    pop esi
    pop edx
    pop ecx
    pop eax
    clc
    ret
.reset:
    mov byte [lf_ready], 0
    mov byte [lf_expect], 0
    mov dword [fd_npos], 0
    jmp .l
.lfn:
    mov al, [edi]
    test al, 0x40
    jz .cont
    and al, 0x1F                ; the last part comes first
    jz .reset
    cmp al, 20
    ja .reset
    mov [lf_expect], al
    mov dl, [edi+13]
    mov [lf_sum], dl
    mov byte [lf_ready], 0
    mov dword [fd_npos], 0
    push edi                    ; terminate it where the last part ends
    movzx ecx, al
    imul ecx, 13
    mov byte [lf_buf+ecx], 0
    pop edi
.cont:
    mov al, [edi]
    and al, 0x1F
    cmp al, [lf_expect]
    jne .reset
    test al, al
    jz .reset
    mov dl, [edi+13]
    cmp dl, [lf_sum]
    jne .reset
    call fd_addpos
    movzx edx, al
    dec edx
    imul edx, 13
    add edx, lf_buf             ; where these 13 characters go
    mov esi, lf_offs
    mov ecx, 13
.ch:
    push esi
    movzx esi, byte [esi]
    mov ax, [edi+esi]
    pop esi
    inc esi
    cmp ax, 0xFFFF
    jne .ch1
    xor ax, ax
.ch1:
    test ah, ah
    jz .ch2
    mov al, '?'                 ; outside Latin-1
.ch2:
    mov [edx], al
    inc edx
    loop .ch
    dec byte [lf_expect]
    jnz .l
    mov byte [lf_ready], 1
    jmp .l
.end:
    pop esi
    pop edx
    pop ecx
    pop eax
    stc
    ret

; records where the raw entry di_next just gave is (up to 21 places)
fd_addpos:
    push eax
    push ecx
    mov eax, [fd_npos]
    cmp eax, 21
    jae .r
    mov ecx, [di_lba]
    mov [fd_pos+eax*8], ecx
    mov ecx, [di_off]
    mov [fd_pos+eax*8+4], ecx
    inc dword [fd_npos]
.r:
    pop ecx
    pop eax
    ret

; edi = short entry -> al = the long-name checksum of its 11-byte name
fat_sum11:
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

; edi = short entry -> fd_short = "NAME.EXT" (lower case where its case
; byte says so)
fat_fmt_short:
    pushad
    mov esi, edi
    mov edi, fd_short
    mov bl, [esi+FE_DCASE]
    xor ecx, ecx
.b:
    mov al, [esi+ecx]
    cmp al, ' '
    je .bd
    test ecx, ecx
    jnz .b1
    cmp al, 0x05                ; stands for a first byte of 0xE5
    jne .b1
    mov al, 0xE5
.b1:
    test bl, 0x08
    jz .b2
    call fat_lower
.b2:
    stosb
    inc ecx
    cmp ecx, 8
    jb .b
.bd:
    cmp byte [esi+8], ' '
    je .done
    mov al, '.'
    stosb
    mov ecx, 8
.e:
    mov al, [esi+ecx]
    cmp al, ' '
    je .done
    test bl, 0x10
    jz .e1
    call fat_lower
.e1:
    stosb
    inc ecx
    cmp ecx, 11
    jb .e
.done:
    mov byte [edi], 0
    popad
    ret

fat_lower:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 'a'-'A'
.r:
    ret

fat_upper:
    cmp al, 'a'
    jb .r
    cmp al, 'z'
    ja .r
    sub al, 'a'-'A'
.r:
    ret

; esi, edi = names -> ZF set if equal without regard to case
fat_streqi:
    push eax
    push esi
    push edi
.l:
    mov al, [esi]
    call fat_upper
    mov ah, al
    mov al, [edi]
    call fat_upper
    cmp al, ah
    jne .ne
    test al, al
    jz .eq
    inc esi
    inc edi
    jmp .l
.eq:
    xor eax, eax
    jmp .o
.ne:
    or eax, 1
.o:
    pop edi
    pop esi
    pop eax
    ret

; ebp = volume, eax = directory, esi = name -> CF if it is not there;
; otherwise fd_ent = a copy of its short entry and fd_pos/fd_npos where
; its entries are. Matches the long or the short name.
fat_find:
    pushad
    call fd_start
.l:
    call fd_next
    jc .no
    push edi
    mov edi, fd_name
    call fat_streqi
    pop edi
    je .hit
    push edi
    mov edi, fd_short
    call fat_streqi
    pop edi
    jne .l
.hit:
    mov esi, edi
    mov edi, fd_ent
    mov ecx, 8
    rep movsd
    popad
    clc
    ret
.no:
    cmp byte [di_err], 0
    jne .io
    mov byte [fs_errno], FE_NOTFOUND
.io:
    popad
    stc
    ret

; ebp = volume, eax = directory -> eax = its parent (the root's parent
; is the root). CF on a disk error.
fat_parent:
    push ecx
    push edi
    cmp eax, [ebp+V_ROOTCL]
    je .ok
    test eax, eax
    jz .ok
    call fat_clsec              ; ".." is the second entry of the first sector
    mov edi, fe_sec
    call vol_rsec
    jc .err
    cmp word [fe_sec+32], '..'
    jne .root
    mov edi, fe_sec+32
    call fat_entcl
    test eax, eax
    jnz .ok
.root:
    mov eax, [ebp+V_ROOTCL]
.ok:
    pop edi
    pop ecx
    clc
    ret
.err:
    mov byte [fs_errno], FE_IO
    pop edi
    pop ecx
    stc
    ret

; ---------- paths ----------

; esi = "x:path" -> ebp = the volume, eax = the directory the last part is
; in, [fat_base] = the last part ("" when the path names a directory with
; a trailing '/' or is just "x:"). Parts are separated by '/' or '\' and
; always start at the root of the drive. CF with fs_errno.
fat_walk:
    push ecx
    push edx
    push esi
    push edi
    call vol_find
    jc .fail                    ; FE_NODRIVE
    add esi, 2
    mov edi, fat_pathbuf
    mov ecx, FS_PATHMAX
.copy:
    lodsb
    cmp al, '\'
    jne .cp
    mov al, '/'
.cp:
    stosb
    test al, al
    jz .copied
    loop .copy
    mov byte [fs_errno], FE_NAME
    jmp .fail
.copied:
    call fat_root
    mov esi, fat_pathbuf
.part:
    cmp byte [esi], '/'
    jne .scan
    inc esi
    jmp .part
.scan:
    mov edi, esi
.s:
    mov dl, [edi]
    test dl, dl
    jz .last
    cmp dl, '/'
    je .mid
    inc edi
    jmp .s
.mid:
    mov byte [edi], 0
    inc edi
.trail:
    cmp byte [edi], '/'
    jne .more
    inc edi
    jmp .trail
.more:
    cmp byte [edi], 0
    je .last
    call fat_step
    jc .fail
    mov esi, edi
    jmp .scan
.last:
    mov [fat_base], esi
    pop edi
    pop esi
    pop edx
    pop ecx
    clc
    ret
.fail:
    pop edi
    pop esi
    pop edx
    pop ecx
    stc
    ret

; esi = one part, eax = directory -> eax = the directory it names. CF
; (FE_NODIR) if none.
fat_step:
    cmp byte [esi], 0
    je .ok
    cmp word [esi], '.'
    je .ok
    cmp word [esi], '..'
    jne .name
    cmp byte [esi+2], 0
    jne .name
    jmp fat_parent
.name:
    call fat_find
    jc .no
    test byte [fd_ent+FE_DATTR], FA_DIR
    jz .no
    push edi
    mov edi, fd_ent
    call fat_entcl
    pop edi
    test eax, eax
    jnz .ok
    call fat_root               ; ".." entries of the root's children say 0
.ok:
    clc
    ret
.no:
    mov byte [fs_errno], FE_NODIR
    stc
    ret

; esi = path -> ebp = volume, eax = cluster of the directory it names. CF
; if it does not name a directory.
fat_find_dir:
    push esi
    call fat_walk
    jc .r
    mov esi, [fat_base]
    call fat_step
.r:
    pop esi
    ret

; esi = name -> CF if not a valid FAT long name: 1 to 63 characters, not
; "." or "..", none of \ / : * ? " < > | or control characters
fat_check_name:
    push eax
    push ecx
    push esi
    call fs_check_name          ; length, "." and ".."
    jc .bad
.l:
    lodsb
    test al, al
    jz .ok
    cmp al, ' '
    jb .bad
    push edi
    mov edi, fat_badchars
    mov ecx, fat_badchars_len
    repne scasb
    pop edi
    je .bad
    jmp .l
.ok:
    pop esi
    pop ecx
    pop eax
    clc
    ret
.bad:
    mov byte [fs_errno], FE_NAME
    pop esi
    pop ecx
    pop eax
    stc
    ret

; ---------- short names and aliases ----------

; esi = characters, ecx = how many, edi = destination, ebx = room ->
; eax = characters written (upper case); dl: 1 lower case seen, 2 upper
; case seen, 4 a character a short name cannot hold (space and '.' are
; dropped, others become '_'), 8 cut short. Keeps ecx, esi, edi.
sn_part:
    push ecx
    push esi
    push edi
    xor eax, eax
    xor edx, edx
    jecxz .d
.l:
    mov dh, [esi]
    inc esi
    cmp dh, ' '
    je .drop
    cmp dh, '.'
    je .drop
    cmp dh, 'a'
    jb .nl
    cmp dh, 'z'
    ja .nl
    or dl, 1
    sub dh, 'a'-'A'
    jmp .ok
.nl:
    cmp dh, 'A'
    jb .other
    cmp dh, 'Z'
    ja .other
    or dl, 2
    jmp .ok
.other:
    call fat_short_ok
    jnc .ok
    or dl, 4
    mov dh, '_'
.ok:
    cmp eax, ebx
    jae .cut
    mov [edi+eax], dh
    inc eax
    loop .l
    jmp .d
.cut:
    or dl, 8
    jmp .d
.drop:
    or dl, 4
    loop .l
.d:
    pop edi
    pop esi
    pop ecx
    ret

; dh = character (not a letter) -> CF unless a short name may hold it
fat_short_ok:
    cmp dh, 0x80
    jae .ok
    cmp dh, '0'
    jb .tab
    cmp dh, '9'
    jbe .ok
.tab:
    push eax
    push ecx
    push edi
    mov al, dh
    mov edi, fat_shortchars
    mov ecx, fat_shortchars_len
    repne scasb
    pop edi
    pop ecx
    pop eax
    je .ok
    stc
    ret
.ok:
    clc
    ret

; esi = long name -> fs_short (11 bytes) and fs_case; fs_needlfn = 1 when
; it is not a plain 8.3 name (one case per part, valid characters) and
; needs long-name entries; fs_short then holds the start of its alias
; (sn_bn base characters), which fat_alias numbers.
fat_shortname:
    pushad
    mov edi, fs_short
    mov ecx, 11
    mov al, ' '
    rep stosb
    mov byte [fs_case], 0
    mov byte [fs_needlfn], 0
    mov [sn_src], esi
    call strlen
    mov [sn_len], eax
    xor edx, edx                ; the last dot, not a leading one
    mov ecx, 1
.dot:
    cmp ecx, eax
    jae .dd
    cmp byte [esi+ecx], '.'
    jne .dn
    mov edx, ecx
.dn:
    inc ecx
    jmp .dot
.dd:
    mov [sn_dot], edx
    mov ecx, eax
    test edx, edx
    jz .b
    mov ecx, edx
.b:
    mov edi, fs_short
    mov ebx, 8
    call sn_part
    mov [sn_bflags], dl
    mov [sn_bn], eax
    mov byte [sn_eflags], 0
    mov dword [sn_en], 0
    mov edx, [sn_dot]
    test edx, edx
    jz .judge
    mov esi, [sn_src]
    lea esi, [esi+edx+1]
    mov ecx, [sn_len]
    sub ecx, edx
    dec ecx
    mov edi, fs_short+8
    mov ebx, 3
    call sn_part
    mov [sn_eflags], dl
    mov [sn_en], eax
.judge:
    mov al, [sn_bflags]
    test al, 12
    jnz .lfn
    and al, 3
    cmp al, 3
    je .lfn
    cmp dword [sn_bn], 0
    je .lfn
    cmp dword [sn_dot], 0
    je .plain
    mov al, [sn_eflags]
    test al, 12
    jnz .lfn
    and al, 3
    cmp al, 3
    je .lfn
    cmp dword [sn_en], 0
    je .lfn
.plain:
    xor al, al
    test byte [sn_bflags], 1
    jz .p1
    or al, 0x08
.p1:
    test byte [sn_eflags], 1
    jz .p2
    or al, 0x10
.p2:
    mov [fs_case], al
    popad
    ret
.lfn:
    mov byte [fs_needlfn], 1
    cmp dword [sn_bn], 0
    jne .r
    mov byte [fs_short], '_'
    mov dword [sn_bn], 1
.r:
    popad
    ret

; ebp = volume, eax = directory, esi = 11-byte short name -> CF clear if
; an entry of the directory has it
fat_short_exists:
    pushad
    call di_start
.l:
    call di_next
    jc .no
    cmp byte [edi], 0
    je .no
    cmp byte [edi], 0xE5
    je .l
    mov al, [edi+FE_DATTR]
    and al, 0x3F
    cmp al, FA_LFN
    je .l
    push esi
    mov ecx, 11
    repe cmpsb
    pop esi
    jne .l
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ebp = volume, eax = directory, fs_short = alias start (sn_bn base
; characters) -> fs_short = "BASE~N  EXT", the first N from 1 that no
; entry of the directory uses
fat_alias:
    pushad
    mov esi, fs_short
    mov edi, sn_base
    mov ecx, 8
    rep movsb
    mov ebx, 1
.try:
    ; digits of ebx
    push eax
    mov eax, ebx
    xor ecx, ecx
    mov esi, 10
.dg:
    xor edx, edx
    div esi
    add dl, '0'
    push edx
    inc ecx
    test eax, eax
    jnz .dg
    mov edx, 7
    sub edx, ecx                ; base characters kept
    cmp edx, [sn_bn]
    jbe .k
    mov edx, [sn_bn]
.k:
    mov edi, fs_short
    push ecx
    mov esi, sn_base
    mov ecx, edx
    rep movsb
    pop ecx
    mov al, '~'
    stosb
.pd:
    pop eax
    stosb
    loop .pd
.sp:
    cmp edi, fs_short+8
    jae .done
    mov byte [edi], ' '
    inc edi
    jmp .sp
.done:
    pop eax
    mov esi, fs_short
    call fat_short_exists
    jc .free
    inc ebx
    cmp ebx, 999999
    jbe .try
.free:
    popad
    ret

; ---------- making entries ----------

; ebp = volume, eax = directory, ecx = entries wanted in a row -> fr_pos
; holds their places. A directory in clusters grows when it is full;
; FAT12/16's fixed root cannot. CF with fs_errno.
fat_find_free:
    pushad
    mov [fr_want], ecx
    xor ebx, ebx                ; places found in a row
    call di_start
.l:
    call di_next
    jc .end
    mov al, [edi]
    test al, al
    jz .free
    cmp al, 0xE5
    je .free
    xor ebx, ebx
    jmp .l
.free:
    mov ecx, [di_lba]
    mov [fr_pos+ebx*8], ecx
    mov ecx, [di_off]
    mov [fr_pos+ebx*8+4], ecx
    inc ebx
    cmp ebx, [fr_want]
    jb .l
    popad
    clc
    ret
.end:
    cmp byte [di_err], 0
    jne .fail
    mov byte [fs_errno], FE_FULL
    cmp dword [di_clus], 0
    je .fail                    ; the fixed root is full
    ; one more cluster, zeroed, at the end of the chain
    call fat_alloc
    jc .fail
    call fat_zero_cluster
    jc .fail
    mov edx, eax
    mov eax, [di_clus]
    call fat_set
    jc .fail
    mov eax, edx
    mov [di_clus], eax          ; (the next one links after it)
    call fat_clsec
    movzx edx, byte [ebp+V_SPC]
    shl edx, 4                  ; entries in it
    xor esi, esi
.more:
    mov eax, esi
    shr eax, 4
    add eax, ecx
    mov [fr_pos+ebx*8], eax
    mov eax, esi
    and eax, 15
    shl eax, 5
    mov [fr_pos+ebx*8+4], eax
    inc ebx
    cmp ebx, [fr_want]
    jae .ok
    inc esi
    cmp esi, edx
    jb .more
    jmp .end                    ; (a run longer than a cluster)
.ok:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ebp = volume, eax = directory, esi = name (checked), fe_tmpl = the short
; entry to write (attributes, cluster, size, times) -> writes the name's
; long-name entries and the short entry with its short name or alias.
; CF with fs_errno.
fat_add:
    pushad
    mov [fa_name], esi
    call fat_shortname
    mov ecx, 1
    cmp byte [fs_needlfn], 0
    je .counted
    call fat_alias
    push eax
    mov eax, [sn_len]
    add eax, 12
    xor edx, edx
    mov ebx, 13
    div ebx
    lea ecx, [eax+1]
    pop eax
.counted:
    mov [fa_n], ecx
    call fat_find_free
    jc .fail
    mov esi, fs_short           ; name the template
    mov edi, fe_tmpl
    mov ecx, 11
    rep movsb
    mov al, [fs_case]
    mov [fe_tmpl+FE_DCASE], al
    mov edi, fe_tmpl
    call fat_sum11
    mov [fa_sum], al
    ; long-name entries, the last part first
    xor ebx, ebx                ; index in fr_pos
.lfn:
    mov eax, [fa_n]
    dec eax
    cmp ebx, eax
    jae .short
    sub eax, ebx                ; this entry's order number
    mov [fa_ord], eax
    mov edi, fe_lfn
    push eax
    mov ecx, 8
    xor eax, eax
    rep stosd
    pop eax
    test ebx, ebx
    jnz .o
    or al, 0x40
.o:
    mov [fe_lfn], al
    mov byte [fe_lfn+FE_DATTR], FA_LFN
    mov al, [fa_sum]
    mov [fe_lfn+13], al
    mov edx, [fa_ord]
    dec edx
    imul edx, 13                ; first character of this part
    mov esi, lf_offs
    mov ecx, 13
.ch:
    movzx edi, byte [esi]
    inc esi
    mov eax, 0xFFFF
    cmp edx, [sn_len]
    ja .put
    mov eax, 0
    je .put
    push esi
    mov esi, [fa_name]
    movzx eax, byte [esi+edx]
    pop esi
.put:
    mov [fe_lfn+edi], ax
    inc edx
    loop .ch
    mov ecx, [fr_pos+ebx*8]
    mov edx, [fr_pos+ebx*8+4]
    mov esi, fe_lfn
    call fat_put_entry
    jc .fail
    inc ebx
    jmp .lfn
.short:
    mov ecx, [fr_pos+ebx*8]
    mov edx, [fr_pos+ebx*8+4]
    mov [fa_lba], ecx
    mov [fa_off], edx
    mov esi, fe_tmpl
    call fat_put_entry
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; fe_tmpl = an empty entry with attribute al and the time now
fat_tmpl:
    push eax
    push ecx
    push edi
    mov edi, fe_tmpl
    push eax
    mov ecx, 8
    xor eax, eax
    rep stosd
    pop eax
    mov [fe_tmpl+FE_DATTR], al
    call fat_now
    mov [fe_tmpl+FE_DCTIME], ax
    mov [fe_tmpl+FE_DMTIME], ax
    shr eax, 16
    mov [fe_tmpl+FE_DCDATE], ax
    mov [fe_tmpl+FE_DMDATE], ax
    mov [fe_tmpl+FE_DADATE], ax
    pop edi
    pop ecx
    pop eax
    ret

; -> eax = DOS date (high word) and time (low word) from the CMOS clock
fat_now:
    push ebx
    push ecx
    push edx
    push edi
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    mov [fn_bin], al            ; bit 2: binary, not BCD
    mov ebx, fn_regs
    mov edi, fn_vals
    mov ecx, 6
.r:
    mov al, [ebx]
    out 0x70, al
    in al, 0x71
    test byte [fn_bin], 4
    jnz .s
    mov dh, al                  ; BCD -> binary
    and dh, 0x0F
    shr al, 4
    mov dl, 10
    mul dl
    add al, dh
.s:
    mov [edi], al
    inc ebx
    inc edi
    loop .r
    sub edi, 6
    movzx eax, byte [fn_vals+5] ; year (00..99) -> since 1980
    add eax, 20
    shl eax, 4
    or al, [fn_vals+4]          ; month
    shl eax, 5
    or al, [fn_vals+3]          ; day
    shl eax, 5
    movzx edx, byte [fn_vals+2] ; hours
    or eax, edx
    shl eax, 6
    or al, [fn_vals+1]          ; minutes
    shl eax, 5
    movzx edx, byte [fn_vals]
    shr edx, 1                  ; seconds / 2
    or eax, edx
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- the calls SQFS hands over ----------

; esi = "x:path", al = DK_FILE or DK_DIR -> eax = 0 or -1 (fs_errno)
fat_make:
    pushad
    mov [fm_kind], al
    call fat_walk
    jc .fail
    mov [fm_dir], eax
    mov esi, [fat_base]
    call fat_check_name
    jc .fail
    mov byte [fs_errno], FE_IO
    test byte [ebp+V_FLAGS], VF_RO
    jnz .fail
    call fat_find
    jnc .exists
    cmp byte [di_err], 0
    jne .fail
    mov al, FA_ARCH
    cmp byte [fm_kind], DK_DIR
    jne .file
    ; a directory: a zeroed cluster with "." and ".."
    call fat_alloc
    jc .fail
    mov [fm_cl], eax
    call fat_zero_cluster
    jc .undo
    mov al, FA_DIR
    call fat_tmpl
    mov esi, fat_dot
    mov edi, fe_tmpl
    mov ecx, 11
    rep movsb
    mov eax, [fm_cl]
    mov edi, fe_tmpl
    call fat_setcl
    call fat_clsec
    xor edx, edx
    mov esi, fe_tmpl
    call fat_put_entry
    jc .undo
    mov byte [fe_tmpl+1], '.'
    mov eax, [fm_dir]
    cmp eax, [ebp+V_ROOTCL]
    jne .pp
    xor eax, eax                ; the root is cluster 0 in ".."
.pp:
    call fat_setcl
    mov edx, 32
    call fat_put_entry
    jc .undo
    mov al, FA_DIR
    call fat_tmpl
    mov eax, [fm_cl]
    mov edi, fe_tmpl
    call fat_setcl
    jmp .add
.file:
    call fat_tmpl
.add:
    mov eax, [fm_dir]
    mov esi, [fat_base]
    call fat_add
    jc .undo
    call fat_flush
    popad
    xor eax, eax
    ret
.undo:
    cmp byte [fm_kind], DK_DIR
    jne .fail
    mov eax, [fm_cl]
    call fat_free_chain
.fail:
    call fat_flush
    popad
    mov eax, -1
    ret
.exists:
    mov byte [fs_errno], FE_EXISTS
    jmp .fail

; ebp = volume -> CF if some descriptor has the entry fd_pos[fd_npos-1]
; open (FE_BUSY)
fat_busy:
    pushad
    mov eax, [fd_npos]
    mov ecx, [fd_pos+eax*8-8]
    mov edx, [fd_pos+eax*8-4]
    mov ebx, fs_fds
    mov esi, FS_MAXFD
.l:
    cmp [ebx+FD_VOL], ebp
    jne .n
    mov edi, [ebx+FD_DIRENT]
    test edi, edi
    jz .n
    cmp [edi+FF_LBA], ecx
    jne .n
    cmp [edi+FF_OFF], edx
    je .busy
.n:
    add ebx, 16
    dec esi
    jnz .l
    popad
    clc
    ret
.busy:
    mov byte [fs_errno], FE_BUSY
    popad
    stc
    ret

; ebp = volume -> marks every entry in fd_pos deleted. CF.
fat_kill_run:
    pushad
    xor ebx, ebx
.l:
    cmp ebx, [fd_npos]
    jae .ok
    mov ecx, [fd_pos+ebx*8]
    mov edx, [fd_pos+ebx*8+4]
    call fat_kill_entry
    jc .bad
    inc ebx
    jmp .l
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; esi = "x:path" -> eax = 0 or -1. A directory must be empty.
fat_delete:
    pushad
    call fat_walk
    jc .fail
    mov esi, [fat_base]
    call fat_find
    jc .fail
    call fat_busy
    jc .fail
    mov byte [fs_errno], FE_IO
    test byte [ebp+V_FLAGS], VF_RO
    jnz .fail
    mov edi, fd_ent
    call fat_entcl
    mov [fm_cl], eax
    test byte [fd_ent+FE_DATTR], FA_DIR
    jz .gone
    mov ecx, [fd_npos]          ; (fd_next below reuses fd_pos)
    shl ecx, 1
    mov esi, fd_pos
    mov edi, fr_pos
    rep movsd
    push dword [fd_npos]
    test eax, eax
    jz .empty
    call fd_start
    call fd_next
    jc .empty
    pop eax
    mov byte [fs_errno], FE_NOTEMPTY
    jmp .fail
.empty:
    pop ecx
    mov [fd_npos], ecx
    shl ecx, 1
    mov esi, fr_pos
    mov edi, fd_pos
    rep movsd
.gone:
    call fat_kill_run
    jc .fail
    mov eax, [fm_cl]
    call fat_free_chain
    jc .fail
    call fat_flush
    popad
    xor eax, eax
    ret
.fail:
    call fat_flush
    popad
    mov eax, -1
    ret

; esi = old "x:path", edi = new path -> eax = 0 or -1. The new path may
; name a directory (the entry moves into it under its name), a path on
; the same drive ("x:dir/name"), or, without a drive, a name in the same
; directory ("name") or a path from the drive's root ("dir/name").
fat_rename:
    pushad
    mov [fr_old], esi
    ; the new path, with the drive
    xchg esi, edi
    call vol_path
    xchg esi, edi
    jc .nodrive
    mov al, [edi]
    call fat_upper
    mov ah, al
    mov al, [esi]
    call fat_upper
    cmp al, ah
    mov byte [fs_errno], FE_XDEV
    jne .fail
    mov esi, edi
    mov edi, fr_new
    call fat_copy_path
    jmp .newok
.nodrive:
    mov ebx, edi                ; new
    mov edi, fr_new
    mov al, [esi]
    stosb
    mov al, ':'
    stosb
    push esi                    ; a bare name: the old one's directory
    mov esi, ebx
.sl:
    lodsb
    test al, al
    jz .bare
    cmp al, '/'
    jne .sl
    pop esi
    mov al, '/'
    stosb
    jmp .tail
.bare:
    pop esi
    add esi, 2
    mov edx, edi                ; after the last '/' of the old path
.ol:
    lodsb
    test al, al
    jz .od
    stosb
    cmp al, '/'
    je .slash
    cmp al, '\'
    jne .ol
.slash:
    mov edx, edi
    jmp .ol
.od:
    mov edi, edx
.tail:
    mov esi, ebx
    mov ecx, fr_new+FS_PATHMAX-1
.tl:
    cmp edi, ecx
    jae .long
    lodsb
    stosb
    test al, al
    jnz .tl
    jmp .newok
.long:
    mov byte [fs_errno], FE_NAME
    jmp .fail
.newok:
    ; the new place: an existing directory, or a directory and a name
    mov esi, fr_new
    call fat_find_dir
    jc .plain
    mov [fr_dir], eax
    mov esi, [fr_old]
    call fat_walk
    jc .fail
    mov esi, [fat_base]
    jmp .named
.plain:
    mov esi, fr_new
    call fat_walk
    jc .fail
    mov [fr_dir], eax
    mov esi, [fat_base]
.named:
    mov edi, fr_name
    call fat_copy_path
    mov esi, fr_name
    call fat_check_name
    jc .fail
    mov eax, [fr_dir]
    call fat_find
    jnc .exists
    cmp byte [di_err], 0
    jne .fail
    ; the old entry
    mov esi, [fr_old]
    call fat_walk
    jc .fail
    mov [fr_odir], eax
    mov esi, [fat_base]
    call fat_find
    jc .fail
    call fat_busy
    jc .fail
    mov byte [fs_errno], FE_IO
    test byte [ebp+V_FLAGS], VF_RO
    jnz .fail
    mov ecx, [fd_npos]          ; keep where it is
    mov [fr_npos], ecx
    shl ecx, 1
    mov esi, fd_pos
    mov edi, fr_opos
    rep movsd
    test byte [fd_ent+FE_DATTR], FA_DIR
    jz .move
    ; a directory must not move below itself
    mov edi, fd_ent
    call fat_entcl
    mov ebx, eax
    mov eax, [fr_dir]
    mov byte [fs_errno], FE_LOOP
.up:
    cmp eax, ebx
    je .fail
    cmp eax, [ebp+V_ROOTCL]
    je .move
    test eax, eax
    jz .move
    call fat_parent
    jc .fail
    jmp .up
.move:
    mov esi, fd_ent
    mov edi, fe_tmpl
    mov ecx, 8
    rep movsd
    mov eax, [fr_dir]
    mov esi, fr_name
    call fat_add
    jc .fail
    mov ecx, [fr_npos]
    mov [fd_npos], ecx
    shl ecx, 1
    mov esi, fr_opos
    mov edi, fd_pos
    rep movsd
    call fat_kill_run
    jc .fail
    ; a directory that changed parent: its ".." follows
    test byte [fe_tmpl+FE_DATTR], FA_DIR
    jz .done
    mov eax, [fr_dir]
    cmp eax, [fr_odir]
    je .done
    mov edi, fe_tmpl
    call fat_entcl
    call fat_clsec
    mov edi, fe_sec
    call vol_rsec
    jc .done
    cmp word [fe_sec+32], '..'
    jne .done
    mov eax, [fr_dir]
    cmp eax, [ebp+V_ROOTCL]
    jne .pp
    xor eax, eax
.pp:
    mov edi, fe_sec+32
    call fat_setcl
    mov esi, fe_sec
    call vol_wsec
.done:
    call fat_flush
    popad
    xor eax, eax
    ret
.exists:
    mov byte [fs_errno], FE_EXISTS
.fail:
    call fat_flush
    popad
    mov eax, -1
    ret

; esi = path -> copied to edi (at most FS_PATHMAX-1 characters)
fat_copy_path:
    push eax
    push ecx
    mov ecx, FS_PATHMAX-1
.l:
    lodsb
    stosb
    test al, al
    jz .d
    loop .l
    mov byte [edi], 0
.d:
    pop ecx
    pop eax
    ret

; esi = "x:path", ecx = flags -> eax = fd or -1
fat_open:
    pushad
    mov [fo_flags], ecx
    call fat_walk
    jc .fail
    mov [fo_dir], eax
    mov esi, [fat_base]
    mov byte [fs_errno], FE_ISDIR
    cmp byte [esi], 0
    je .fail
    cmp word [esi], '.'
    je .fail
    cmp word [esi], '..'
    jne .look
    cmp byte [esi+2], 0
    je .fail
.look:
    call fat_find
    jnc .found
    cmp byte [di_err], 0
    jne .fail
    test dword [fo_flags], O_CREATE
    jz .fail
    mov esi, [fat_base]
    call fat_check_name
    jc .fail
    mov byte [fs_errno], FE_IO
    test byte [ebp+V_FLAGS], VF_RO
    jnz .fail
    mov al, FA_ARCH
    call fat_tmpl
    mov eax, [fo_dir]
    call fat_add
    jc .fail
    call fat_flush
    mov eax, [fo_dir]
    call fat_find
    jc .fail
.found:
    mov byte [fs_errno], FE_ISDIR
    test byte [fd_ent+FE_DATTR], FA_DIR
    jnz .fail
    ; a free descriptor
    mov ebx, fs_fds
    xor edx, edx
.f:
    cmp dword [ebx+FD_DIRENT], 0
    je .slot
    add ebx, 16
    inc edx
    cmp edx, FS_MAXFD
    jb .f
    mov byte [fs_errno], FE_NOFD
    jmp .fail
.slot:
    mov edi, edx
    shl edi, 5
    add edi, fat_files
    mov [edi+FF_VOL], ebp
    push edi
    mov edi, fd_ent
    call fat_entcl
    pop edi
    mov [edi+FF_FIRST], eax
    mov eax, [fd_ent+FE_DSIZE]
    mov [edi+FF_SIZE], eax
    mov eax, [fd_npos]
    mov ecx, [fd_pos+eax*8-8]
    mov [edi+FF_LBA], ecx
    mov ecx, [fd_pos+eax*8-4]
    mov [edi+FF_OFF], ecx
    mov dword [edi+FF_CIDX], -1
    mov [ebx+FD_DIRENT], edi
    mov dword [ebx+FD_POS], 0
    mov [ebx+FD_VOL], ebp
    test dword [fo_flags], O_TRUNC
    jz .notrunc
    cmp dword [edi+FF_SIZE], 0
    jne .trunc
    cmp dword [edi+FF_FIRST], 0
    je .notrunc
.trunc:
    test byte [ebp+V_FLAGS], VF_RO
    jnz .notrunc
    mov eax, [edi+FF_FIRST]
    call fat_free_chain
    mov dword [edi+FF_FIRST], 0
    mov dword [edi+FF_SIZE], 0
    call fat_update_entry
    call fat_flush
.notrunc:
    test dword [fo_flags], O_APPEND
    jz .done
    mov eax, [edi+FF_SIZE]
    mov [ebx+FD_POS], eax
.done:
    mov [esp+28], edx
    popad
    ret
.fail:
    popad
    mov eax, -1
    ret

; edi = open FAT file -> its short entry gets the first cluster, size and
; the time now. CF.
fat_update_entry:
    pushad
    mov ebp, [edi+FF_VOL]
    mov ebx, edi
    mov ecx, [ebx+FF_LBA]
    mov edi, fe_sec
    call vol_rsec
    jc .bad
    mov edx, [ebx+FF_OFF]
    lea edi, [fe_sec+edx]
    mov eax, [ebx+FF_FIRST]
    call fat_setcl
    mov eax, [ebx+FF_SIZE]
    mov [edi+FE_DSIZE], eax
    call fat_now
    mov [edi+FE_DMTIME], ax
    shr eax, 16
    mov [edi+FE_DMDATE], ax
    mov [edi+FE_DADATE], ax
    or byte [edi+FE_DATTR], FA_ARCH
    mov esi, fe_sec
    call vol_wsec
    jc .bad
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; edx = open FAT file, eax = cluster index in it, bl = 1 to grow the file
; when it has fewer -> eax = that cluster. CF at the end (or disk full).
fat_cluster_at:
    push ebx
    push ecx
    push edx
    push esi
    push ebp
    mov [fca_file], edx
    mov [fca_grow], bl
    mov ebp, [edx+FF_VOL]
    mov esi, eax                ; wanted index
    mov eax, [edx+FF_FIRST]
    test eax, eax
    jnz .have
    cmp byte [fca_grow], 0
    je .end
    call fat_alloc
    jc .end
    mov [edx+FF_FIRST], eax
    mov dword [edx+FF_CIDX], -1
.have:
    xor ecx, ecx                ; index of the cluster in eax
    cmp dword [edx+FF_CIDX], -1
    je .walk
    cmp [edx+FF_CIDX], esi
    ja .walk
    mov ecx, [edx+FF_CIDX]
    mov eax, [edx+FF_CCL]
.walk:
    cmp ecx, esi
    je .got
    mov ebx, eax
    call fat_get
    jc .end
    cmp eax, 2
    jb .eoc
    cmp eax, FAT_EOC
    jne .next
.eoc:
    cmp byte [fca_grow], 0
    je .end
    call fat_alloc
    jc .end
    mov edx, eax
    mov eax, ebx
    call fat_set                ; link it after the last one
    jc .end
    mov eax, edx
.next:
    inc ecx
    jmp .walk
.got:
    mov edx, [fca_file]
    mov [edx+FF_CIDX], ecx
    mov [edx+FF_CCL], eax
    pop ebp
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.end:
    pop ebp
    pop esi
    pop edx
    pop ecx
    pop ebx
    stc
    ret

; ebx = fd -> edi = its descriptor, edx = its open FAT file
fat_desc:
    mov edi, ebx
    shl edi, 4
    add edi, fs_fds
    mov edx, [edi+FD_DIRENT]
    ret

; ebx = fd (a FAT one), edi = buffer, ecx = length -> eax = bytes or -1
fat_read:
    pushad
    mov [fx_dst], edi
    call fat_desc
    mov eax, [edx+FF_SIZE]
    sub eax, [edi+FD_POS]
    jbe .eof
    cmp ecx, eax
    jbe .len
    mov ecx, eax
.len:
    mov [fx_total], ecx
.chunk:
    test ecx, ecx
    jz .done
    mov ebp, [edx+FF_VOL]
    push ecx
    push edi
    xor ebx, ebx                ; (no growing)
    call fat_sector_of          ; ecx = sector, [fx_inoff]
    jc .failp
    mov edi, fe_sec
    call vol_rsec
    jc .failp
    pop edi
    pop ecx
    mov eax, [fx_inoff]
    and eax, SECTOR_SIZE-1
    mov ebx, SECTOR_SIZE
    sub ebx, eax
    cmp ebx, ecx
    jbe .n
    mov ebx, ecx
.n:
    push ecx
    push edi
    lea esi, [fe_sec+eax]
    mov edi, [fx_dst]
    mov ecx, ebx
    rep movsb
    mov [fx_dst], edi
    pop edi
    pop ecx
    add [edi+FD_POS], ebx
    sub ecx, ebx
    jmp .chunk
.done:
    mov eax, [fx_total]
    mov [esp+28], eax
    popad
    ret
.eof:
    popad
    xor eax, eax
    ret
.failp:
    pop edi
    pop ecx
    mov byte [fs_errno], FE_IO
    popad
    mov eax, -1
    ret

; edi = descriptor, edx = its open FAT file, ebp = volume, bl = 1 to grow
; -> ecx = the sector holding the descriptor's position, [fx_inoff] =
; the position's offset in its cluster. CF at the end of the file.
fat_sector_of:
    push eax
    push edx
    mov eax, [edi+FD_POS]
    push edx
    xor edx, edx
    div dword [ebp+V_CLBYTES]
    mov [fx_inoff], edx
    pop edx
    call fat_cluster_at
    jc .r
    call fat_clsec
    mov eax, [fx_inoff]
    shr eax, 9
    add ecx, eax
    clc
.r:
    pop edx
    pop eax
    ret

; ebx = fd (a FAT one), esi = buffer, ecx = length -> eax = bytes or -1
fat_write:
    pushad
    mov [fx_src], esi
    mov [fx_total], ecx
    call fat_desc
    mov ebp, [edx+FF_VOL]
    mov byte [fs_errno], FE_IO
    test byte [ebp+V_FLAGS], VF_RO
    jnz .fail
    mov eax, [edi+FD_POS]
    add eax, ecx
    jc .fail
.chunk:
    test ecx, ecx
    jz .done
    push ecx
    mov bl, 1
    call fat_sector_of
    mov [fx_lba], ecx
    pop ecx
    mov byte [fs_errno], FE_FULL
    jc .partial
    mov byte [fs_errno], FE_IO
    mov eax, [fx_inoff]
    and eax, SECTOR_SIZE-1
    mov ebx, SECTOR_SIZE
    sub ebx, eax
    cmp ebx, ecx
    jbe .n
    mov ebx, ecx
.n:
    cmp ebx, SECTOR_SIZE        ; a whole sector needs no read first
    je .fill
    push ecx
    push edi
    mov ecx, [fx_lba]
    mov edi, fe_sec
    call vol_rsec
    pop edi
    pop ecx
    jc .partial
.fill:
    push ecx
    push edi
    lea edi, [fe_sec+eax]
    mov esi, [fx_src]
    mov ecx, ebx
    rep movsb
    mov [fx_src], esi
    mov ecx, [fx_lba]
    mov esi, fe_sec
    call vol_wsec
    pop edi
    pop ecx
    jc .partial
    add [edi+FD_POS], ebx
    sub ecx, ebx
    mov eax, [edi+FD_POS]
    cmp eax, [edx+FF_SIZE]
    jbe .chunk
    mov [edx+FF_SIZE], eax
    jmp .chunk
.done:
    push edi
    mov edi, edx
    call fat_update_entry
    pop edi
    jc .fail
    call fat_flush
    jc .fail
    mov eax, [fx_total]
    mov [esp+28], eax
    popad
    ret
.partial:                       ; keep what was written
    push edi
    mov edi, edx
    call fat_update_entry
    pop edi
    call fat_flush
.fail:
    popad
    mov eax, -1
    ret

; ebx = fd, ecx = offset, edx = whence -> eax = position or -1, as fs_seek
fat_seek:
    push edi
    push esi
    push edx
    mov esi, edx
    call fat_desc
    xor eax, eax
    cmp esi, SEEK_SET
    je .add
    mov eax, [edi+FD_POS]
    cmp esi, SEEK_CUR
    je .add
    mov eax, [edx+FF_SIZE]
    cmp esi, SEEK_END
    jne .bad
.add:
    add eax, ecx
    js .bad
    cmp eax, [edx+FF_SIZE]
    ja .bad
    mov [edi+FD_POS], eax
    pop edx
    pop esi
    pop edi
    ret
.bad:
    pop edx
    pop esi
    pop edi
    mov eax, -1
    ret

; ebx = fd -> eax = 0
fat_close:
    push edi
    push edx
    call fat_desc
    mov dword [edi+FD_DIRENT], 0
    mov dword [edi+FD_VOL], 0
    call fat_flush
    pop edx
    pop edi
    xor eax, eax
    ret

; esi = "x:path" -> CF clear if it names a directory
fat_is_dir:
    push eax
    push ebp
    call fat_find_dir
    pop ebp
    pop eax
    ret

; ls x:path: the directory's entries, like ls on SQFS
fat_list:
    pushad
    call fat_find_dir
    jc .why
    push eax
    mov esi, [lstr+LS_FILES*4]
    call lputs_nl
    pop eax
    call fd_start
.l:
    call fd_next
    jc .end
    mov esi, fd_name
    call puts
    test byte [edi+FE_DATTR], FA_DIR
    jz .file
    mov al, '/'
    call putc
    mov al, ' '                 ; (a name of 18 or more: one space)
    call putc
    mov al, 18
    call puts_pad
    mov esi, fs_m_dir
    call puts
    jmp .eol
.file:
    mov al, ' '                 ; (a name of 18 or more: one space)
    call putc
    mov al, 18
    call puts_pad
    mov eax, [edi+FE_DSIZE]
    push edi
    call itoa
    pop edi
    mov esi, num_buf
    call puts
.eol:
    mov al, 10
    call putc
    jmp .l
.end:
    cmp byte [di_err], 0
    je .r
.why:
    call fs_why
.r:
    popad
    ret

; ---------- data ----------
fat_badchars db '\/:*?"<>|'
fat_badchars_len equ $-fat_badchars
fat_shortchars db "!#$%&'()-@^_`{}~"
fat_shortchars_len equ $-fat_shortchars
lf_offs db 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30
fat_dot db '.          '
fn_regs db 0, 2, 4, 7, 8, 9     ; seconds, minutes, hours, day, month, year
fn_vals times 6 db 0
fn_bin db 0
fc_dirty db 0
lf_expect db 0
lf_ready db 0
lf_sum db 0
di_loaded db 0
di_err db 0
fs_case db 0
fs_needlfn db 0
sn_bflags db 0
sn_eflags db 0
fm_kind db 0
fca_grow db 0
fa_sum db 0
fs_short times 12 db 0
sn_base times 8 db 0
align 4
fc_vol dd 0
fc_sec dd -1
di_clus dd 0
di_sec dd 0
di_ent dd 0
di_lba dd 0
di_off dd 0
fd_npos dd 0
fd_pos times 21*2 dd 0
fr_pos times 21*2 dd 0
fr_opos times 21*2 dd 0
fr_npos dd 0
fr_want dd 0
fat_base dd 0
sn_src dd 0
sn_len dd 0
sn_dot dd 0
sn_bn dd 0
sn_en dd 0
fa_name dd 0
fa_n dd 0
fa_ord dd 0
fa_lba dd 0
fa_off dd 0
fm_dir dd 0
fm_cl dd 0
fo_flags dd 0
fo_dir dd 0
fr_old dd 0
fr_dir dd 0
fr_odir dd 0
fca_file dd 0
fx_dst dd 0
fx_src dd 0
fx_total dd 0
fx_inoff dd 0
fx_lba dd 0
fat_files times FS_MAXFD*FF_LEN db 0
fd_ent times 32 db 0
fe_tmpl times 32 db 0
fe_lfn times 32 db 0
fr_new times FS_PATHMAX db 0
fr_name times FS_PATHMAX db 0
fat_pathbuf times FS_PATHMAX db 0
fd_short times 16 db 0
fd_name times FAT_NAMEBUF db 0
lf_buf times FAT_NAMEBUF db 0
fc_buf times SECTOR_SIZE db 0
di_buf times SECTOR_SIZE db 0
fe_sec times SECTOR_SIZE db 0
fe_zero times SECTOR_SIZE db 0
