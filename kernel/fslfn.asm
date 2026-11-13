; Squirrel-OS/2 — long file names in SQFS (2.7)
; Included from pm.asm, in the high image. Original code.
;
; A name of up to FS_LNAMEMAX (63) characters. The directory entry keeps
; 15 characters in its name field as before: the name itself when it
; fits, otherwise a short alias that is unique in its directory (the
; first characters, '~' and a number: "a-very-long-n~1"). A long name
; itself lives in continuation entries in the same 64-entry table:
;
;   0..22  23 characters of the name, zero-padded
;   23     checksum of the owner's 16-byte name field
;   24..27 zero (so older kernels see no extent here)
;   28     0xFF (no directory has that id: older kernels never list it)
;   29     DK_LFN
;   30     the owner's entry index (0..63)
;   31     its sequence number, 1 for the first part
;
; The owner's byte DE_LFN counts its parts. Kernels before 2.7 show the
; alias and leave the parts alone; if they delete or rename the owner,
; the parts no longer match it and lfn_sweep frees them at the next mount.
; See documentation/kernel/filesystem.md.

LFN_PART      equ 23              ; characters per continuation entry
LFN_SUM       equ 23              ; offset of the checksum
LFN_OWNER     equ 30
LFN_SEQ       equ 31
LFN_NOPARENT  equ 0xFF

; edi = entry -> al = checksum of its 16-byte name field
lfn_sum:
    push ecx
    push esi
    mov esi, edi
    mov ecx, FS_NAMELEN
    xor al, al
.l:
    ror al, 1
    add al, [esi]
    inc esi
    loop .l
    pop esi
    pop ecx
    ret

; edi = entry -> al = its index in the table
lfn_index:
    push edi
    sub edi, FS_DIR
    shr edi, 5
    mov eax, edi
    pop edi
    ret

; edi = entry -> CF clear if it is one of a long name's parts
lfn_is_part:
    cmp byte [edi], 0
    je .no
    cmp byte [edi+DE_KIND], DK_LFN
    jne .no
    cmp byte [edi+DE_PARENT], LFN_NOPARENT
    jne .no
    clc
    ret
.no:
    stc
    ret

; edi = entry -> esi = its whole name: the entry's own name field, or the
; name put together in lfn_buf. A part that is missing gives the alias.
lfn_name:
    mov esi, edi
    cmp byte [edi+DE_LFN], 0
    je .r
    pushad
    call lfn_sum
    mov bl, al                  ; checksum the parts must carry
    call lfn_index
    mov bh, al                  ; owner index
    movzx ebp, byte [edi+DE_LFN]
    mov edi, lfn_buf
    mov dl, 1                   ; sequence
.part:
    movzx eax, dl
    cmp eax, ebp
    ja .done
    mov esi, FS_DIR
    mov ecx, FS_MAXFILES
.find:
    xchg esi, edi
    call lfn_is_part
    xchg esi, edi
    jc .next
    cmp [esi+LFN_OWNER], bh
    jne .next
    cmp [esi+LFN_SEQ], dl
    jne .next
    cmp [esi+LFN_SUM], bl
    je .got
.next:
    add esi, FS_DIRENT
    loop .find
    popad                       ; a part is missing: the alias
    ret
.got:
    mov ecx, LFN_PART
    rep movsb
    inc dl
    jmp .part
.done:
    mov byte [edi], 0
    popad
    mov esi, lfn_buf
.r:
    ret

; esi = name, dl = directory -> edi = the entry it names, or 0. The whole
; name or the alias matches.
lfn_find_in:
    push ecx
    push ebx
    mov ebx, esi
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [edi], 0
    je .n
    cmp byte [edi+DE_KIND], DK_LFN
    je .n
    cmp [edi+DE_PARENT], dl
    jne .n
    mov esi, ebx
    push edi
    call streq_bounded
    pop edi
    je .hit
    cmp byte [edi+DE_LFN], 0
    je .n
    call lfn_name
    push edi
    mov edi, ebx
    call streq
    pop edi
    je .hit
.n:
    add edi, FS_DIRENT
    loop .l
    xor edi, edi
.hit:
    mov esi, ebx
    pop ebx
    pop ecx
    ret

; edi = entry -> frees the parts of its long name; DE_LFN = 0
lfn_drop:
    pushad
    call lfn_index
    mov bl, al
    mov byte [edi+DE_LFN], 0
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    call lfn_is_part
    jc .n
    cmp [edi+LFN_OWNER], bl
    jne .n
    push ecx
    push edi
    mov ecx, FS_DIRENT/4
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
.n:
    add edi, FS_DIRENT
    loop .l
    popad
    ret

; edi = entry (in use, DE_PARENT set), esi = name (checked by
; fs_check_name), dl = its directory -> the entry gets that name: its own
; when it fits in 15 characters, otherwise an alias and parts. CF, with
; nothing changed, when the table has no room for the parts. Keeps all
; registers.
lfn_set_name:
    pushad
    mov [lfn_entry], edi
    mov [lfn_src], esi
    mov [lfn_dir], dl
    call strlen
    mov [lfn_len], eax
    xor ecx, ecx                ; parts needed
    cmp eax, FS_NAMELEN-1
    jbe .counted
    add eax, LFN_PART-1
    xor edx, edx
    mov ebx, LFN_PART
    div ebx
    mov ecx, eax
.counted:
    mov [lfn_need], ecx
    ; room: free entries plus the parts this entry has now
    call lfn_index
    mov bl, al
    xor edx, edx
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.room:
    cmp byte [edi], 0
    je .free
    call lfn_is_part
    jc .rn
    cmp [edi+LFN_OWNER], bl
    jne .rn
.free:
    inc edx
.rn:
    add edi, FS_DIRENT
    loop .room
    cmp edx, [lfn_need]
    jb .full
    mov edi, [lfn_entry]
    call lfn_drop
    push edi                    ; clear the name field
    mov ecx, FS_NAMELEN/4
    xor eax, eax
    rep stosd
    pop edi
    cmp dword [lfn_need], 0
    jne .long
    mov esi, [lfn_src]          ; it fits
    mov ecx, [lfn_len]
    rep movsb
    jmp .ok
.long:
    mov byte [edi], '~'         ; in use while the alias is chosen
    call lfn_alias
    mov eax, [lfn_need]
    mov [edi+DE_LFN], al
    call lfn_sum
    mov bh, al                  ; checksum
    call lfn_index
    mov bl, al                  ; owner
    mov esi, [lfn_src]          ; the whole name, in parts
    mov dl, 1
.part:
    movzx eax, dl
    cmp eax, [lfn_need]
    ja .ok
    mov edi, FS_DIR             ; a free entry (there is room)
.f:
    cmp byte [edi], 0
    je .slot
    add edi, FS_DIRENT
    jmp .f
.slot:
    push edi
    mov ecx, FS_DIRENT/4
    xor eax, eax
    rep stosd
    pop edi
    push edi
    mov ecx, LFN_PART
.c:
    lodsb
    test al, al
    jz .cd
    stosb
    loop .c
    jmp .cf
.cd:
    dec esi                     ; stay on the terminating zero
.cf:
    pop edi
    mov [edi+LFN_SUM], bh
    mov byte [edi+DE_PARENT], LFN_NOPARENT
    mov byte [edi+DE_KIND], DK_LFN
    mov [edi+LFN_OWNER], bl
    mov [edi+LFN_SEQ], dl
    inc dl
    jmp .part
.ok:
    popad
    clc
    ret
.full:
    popad
    stc
    ret

; [lfn_entry] = entry, [lfn_src] = its long name, [lfn_dir] = directory:
; writes the first alias "<start>~N" (N = 1..99) that no other entry of
; the directory uses, as name or alias, into the name field.
lfn_alias:
    pushad
    mov ebp, 1
.try:
    ; digits of ebp into lfn_num, count in ecx
    mov eax, ebp
    xor ecx, ecx
    mov ebx, 10
.dg:
    xor edx, edx
    div ebx
    add dl, '0'
    push edx
    inc ecx
    test eax, eax
    jnz .dg
    mov edi, lfn_try
    mov edx, FS_NAMELEN-2       ; 14 = prefix + digits
    sub edx, ecx
    mov esi, [lfn_src]
    push ecx
    mov ecx, edx
    rep movsb
    pop ecx
    mov al, '~'
    stosb
.pd:
    pop eax
    stosb
    loop .pd
    xor al, al
    stosb
    ; used by another entry of the directory?
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
    mov dl, [lfn_dir]
.l:
    cmp edi, [lfn_entry]
    je .n
    cmp byte [edi], 0
    je .n
    cmp byte [edi+DE_KIND], DK_LFN
    je .n
    cmp [edi+DE_PARENT], dl
    jne .n
    mov esi, lfn_try
    push edi
    call streq_bounded
    pop edi
    je .used
    call lfn_name
    push edi
    mov edi, lfn_try
    call streq
    pop edi
    je .used
.n:
    add edi, FS_DIRENT
    loop .l
    mov esi, lfn_try            ; free: take it
    mov edi, [lfn_entry]
    mov ecx, FS_NAMELEN-1
    rep movsb
    popad
    ret
.used:
    inc ebp
    cmp ebp, 99
    jbe .try
    popad                       ; (64 entries cannot use 99 aliases)
    ret

; After mounting: frees parts whose owner is gone or no longer matches
; them (an older kernel deleted or renamed it), and writes the table
; back if anything changed.
lfn_sweep:
    pushad
    xor ebp, ebp
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    call lfn_is_part
    jc .n
    movzx esi, byte [edi+LFN_OWNER]
    cmp esi, FS_MAXFILES
    jae .drop
    shl esi, 5
    add esi, FS_DIR
    cmp byte [esi], 0
    je .drop
    cmp byte [esi+DE_KIND], DK_LFN
    je .drop
    mov al, [edi+LFN_SEQ]
    test al, al
    jz .drop
    cmp al, [esi+DE_LFN]
    ja .drop
    push edi
    mov edi, esi
    call lfn_sum
    pop edi
    cmp al, [edi+LFN_SUM]
    je .n
.drop:
    push ecx
    push edi
    mov ecx, FS_DIRENT/4
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    inc ebp
.n:
    add edi, FS_DIRENT
    loop .l
    test ebp, ebp
    jz .r
    call fs_flush_dir
.r:
    popad
    ret

; lfntest: long names end to end. Creates a 40-character name, writes
; and reads it back under that name and under its alias, lists it, renames
; it to another long name in a directory and back to a short name, checks
; that the parts are freed, and that a second long name with the same
; start gets its own alias. Prints PASS or FAIL.
cmd_lfntest_run:
    call fs_need
    jc .r
    mov dword [st_fail], 0
    mov esi, lft_long1
    call fs_delete
    mov esi, lft_long2
    call fs_delete
    mov esi, lft_moved
    call fs_delete
    mov esi, lft_short
    call fs_delete
    mov esi, lft_dir
    call fs_delete
    call lfn_free_count
    mov [lft_free0], eax
    ; create and write under the long name
    mov esi, lft_long1
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov esi, lft_data
    mov ecx, lft_data_len
    call fs_write
    cmp eax, lft_data_len
    call st_check
    call fs_close
    ; the entry and three parts: 49 = 23 + 23 + 3
    call lfn_free_count
    mov edx, [lft_free0]
    sub edx, eax
    cmp edx, 4
    call st_check
    ; found by its whole name, and it reads the alias it was given
    mov esi, lft_long1
    call fs_lookup
    test edi, edi
    jz .fail
    mov esi, edi
    mov edi, lft_alias1
    call streq
    call st_check
    ; read back through the alias
    mov esi, lft_alias1
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov edi, FT_BUF2
    mov ecx, 100
    call fs_read
    cmp eax, lft_data_len
    call st_check
    call fs_close
    ; a second name with the same 13-character start gets ~2
    mov esi, lft_long2
    call fs_create
    test eax, eax
    call st_check
    mov esi, lft_long2
    call fs_lookup
    test edi, edi
    jz .fail
    mov esi, edi
    mov edi, lft_alias2
    call streq
    call st_check
    ; the whole name comes back from the entry
    mov esi, lft_long2
    call fs_lookup
    call lfn_name
    mov edi, lft_long2
    call streq
    call st_check
    ; rename into a directory under another long name
    mov esi, lft_dir
    call fs_mkdir
    test eax, eax
    call st_check
    mov esi, lft_long1
    mov edi, lft_moved
    call fs_rename
    test eax, eax
    call st_check
    mov esi, lft_moved
    call fs_lookup
    test edi, edi
    jz .fail
    cmp dword [edi+DE_SIZE], lft_data_len
    call st_check
    mov esi, lft_long1
    call fs_lookup
    test edi, edi
    call st_check
    ; the listing call gives the whole name
    mov ebx, 0x80000000
    mov ecx, rl_entry
    mov edx, lft_dir
    call fs_readdir_long
    test eax, eax
    jns .fail                   ; (bit 31 set: an entry)
    mov esi, rl_entry
    mov edi, lft_moved_name
    call streq
    call st_check
    ; and to a short name: its parts are freed
    mov esi, lft_moved
    mov edi, lft_short
    call fs_rename
    test eax, eax
    call st_check
    mov esi, lft_long2
    call fs_delete
    test eax, eax
    call st_check
    call lfn_free_count
    mov edx, [lft_free0]
    sub edx, eax
    cmp edx, 3                  ; lft_short, lft_dir and its part
    call st_check
    ; too long (64 characters) is refused
    mov esi, lft_toolong
    call fs_create
    cmp eax, -1
    call st_check
    mov esi, lft_short
    call fs_delete
    mov esi, lft_dir
    call fs_delete
    test eax, eax
    call st_check
    mov esi, lft_pass
    cmp dword [st_fail], 0
    je .out
.fail:
    mov esi, lft_failmsg
.out:
    call puts
.r:
    ret

; -> eax = free entries in the table
lfn_free_count:
    push ecx
    push edi
    xor eax, eax
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [edi], 0
    jne .n
    inc eax
.n:
    add edi, FS_DIRENT
    loop .l
    pop edi
    pop ecx
    ret

lfn_buf times 3*LFN_PART+1 db 0   ; (a 63-character name has 3 parts)
lfn_try times FS_NAMELEN db 0
align 4
lfn_entry dd 0
lfn_src dd 0
lfn_len dd 0
lfn_need dd 0
lft_free0 dd 0
lfn_dir db 0
lft_long1 db 'quarterly-report-for-the-squirrels-of-the-oak.txt', 0   ; 49: three parts
lft_alias1 db 'quarterly-rep~1', 0
lft_long2 db 'quarterly-report-draft-two', 0
lft_alias2 db 'quarterly-rep~2', 0
lft_dir db 'lfn-test-directory', 0
lft_moved db 'lfn-test-directory/acorns-and-other-winter-stores', 0
lft_short db 'lfnshort', 0
lft_moved_name db 'acorns-and-other-winter-stores', 0
lft_toolong db '1234567890123456789012345678901234567890123456789012345678901234', 0
lft_data db 'Long names, short aliases.', 10
lft_data_len equ $-lft_data
lft_pass db 'lfntest: PASS', 10, 0
lft_failmsg db 'lfntest: FAIL', 10, 0

; fs_rename from SQFS to a drive letter: refused (cp, then rm)
fs_rename_xdev:
    mov byte [fs_errno], FE_XDEV
    mov eax, -1
    ret
