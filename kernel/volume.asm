; Squirrel-OS/2 — drive letters: mounting FAT volumes (2.7)
; Included from pm.asm, in the high image. Original code.
;
;   mount                 lists the mounted drives
;   mount d: hd2          a disk (whole, or its first FAT partition)
;   mount e: floppy.img   an image file on the SQFS data disk
;   umount d:
;   cp <from> <to>        copies a file; either side may be on a drive
;   fattest d:            exercises FAT writing on a mounted drive
;   lfntest               exercises SQFS long names (fslfn.asm)
;
; Paths that start with a mounted letter ("d:/docs/a.txt") go to fat.asm
; from the SQFS calls. Disks: hd0 (read-only), hd1 when it does not hold
; SQFS, and hd2/hd3 (the secondary channel, registered here when first
; mounted). See documentation/kernel/fat.md.

VOL_MAX       equ 4

; volume record
V_LETTER      equ 0               ; byte, upper case; 0 = free
V_TYPE        equ 1               ; 12, 16 or 32
V_SPC         equ 2               ; sectors per cluster
V_NFATS       equ 3
V_FLAGS       equ 4
V_DEV         equ 8               ; block device
V_BASE        equ 12              ; first sector of the volume on it
V_SECTS       equ 16              ; sectors from there that may be read
V_LOOP        equ 20              ; SQFS entry of an image file, or 0
V_LOOPFD      equ 24              ; ... and the descriptor that holds it
V_FATLBA      equ 28              ; these are sectors in the volume
V_FATSZ       equ 32
V_ROOTLBA     equ 36
V_ROOTSECS    equ 40
V_DATALBA     equ 44
V_MAXCL       equ 48              ; highest cluster number
V_ROOTCL      equ 52              ; FAT32 root cluster, 0 for FAT12/16
V_FSINFO      equ 56
V_HINT        equ 60              ; where to look for a free cluster
V_CLBYTES     equ 64
V_TOTAL       equ 68              ; sectors in the volume
V_SRC         equ 72              ; what it was mounted from (FS_PATHMAX)
V_LEN         equ V_SRC+FS_PATHMAX

VF_RO         equ 1
VF_FSINFO     equ 2               ; FSInfo not yet marked unknown

; esi = path -> CF clear if it starts with a drive letter and ':'
vol_path:
    push eax
    mov al, [esi]
    call fat_upper
    cmp al, 'A'
    jb .no
    cmp al, 'Z'
    ja .no
    cmp byte [esi+1], ':'
    jne .no
    pop eax
    clc
    ret
.no:
    pop eax
    stc
    ret

; esi = "x:..." -> ebp = the volume mounted on x, or CF (FE_NODRIVE)
vol_find:
    push eax
    push ecx
    mov al, [esi]
    call fat_upper
    mov ebp, vol_table
    mov ecx, VOL_MAX
.l:
    cmp [ebp+V_LETTER], al
    je .hit
    add ebp, V_LEN
    loop .l
    mov byte [fs_errno], FE_NODRIVE
    pop ecx
    pop eax
    stc
    ret
.hit:
    pop ecx
    pop eax
    clc
    ret

; ebx = fd -> CF clear if it is open on a FAT drive (the SQFS calls ask)
fs_fd_fat:
    cmp ebx, FS_MAXFD
    jae .no
    push edi
    mov edi, ebx
    shl edi, 4
    cmp dword [fs_fds+edi+FD_DIRENT], 0
    je .no2
    cmp dword [fs_fds+edi+FD_VOL], 0
    je .no2
    pop edi
    clc
    ret
.no2:
    pop edi
.no:
    stc
    ret

; ---------- mount ----------

; esi = "x:", edi = source -> mounts it, saying what happened
vol_mount:
    pushad
    call vol_path
    jc .usage
    cmp byte [esi+2], 0
    jne .usage
    cmp byte [edi], 0
    je .usage
    call vol_find
    jnc .inuse
    mov ebp, vol_table          ; a free record
    mov ecx, VOL_MAX
.f:
    cmp byte [ebp+V_LETTER], 0
    je .slot
    add ebp, V_LEN
    loop .f
    mov esi, vm_full
    jmp .say
.slot:
    push edi                    ; clear it
    mov edi, ebp
    mov ecx, V_LEN
    xor eax, eax
    rep stosb
    pop edi
    mov al, [esi]
    call fat_upper
    mov [vm_letter], al
    mov esi, edi                ; remember the source
    lea edi, [ebp+V_SRC]
    mov ecx, FS_PATHMAX-1
.src:
    lodsb
    stosb
    test al, al
    jz .srcd
    loop .src
    mov byte [edi], 0
.srcd:
    lea esi, [ebp+V_SRC]
    call vol_path
    jnc .nofat                  ; (an image on a FAT drive: not supported)
    call vol_disk
    jnc .dev
    cmp byte [vm_why], 0
    jne .why
    ; an image file on the SQFS disk
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fswhy
    mov [ebp+V_LOOPFD], eax
    shl eax, 4
    mov eax, [fs_fds+eax+FD_DIRENT]
    mov [ebp+V_LOOP], eax
    mov ecx, [eax+DE_SIZE]
    shr ecx, 9
    mov [ebp+V_SECTS], ecx
    call vol_same
    jc .busyloop
    jmp .probe
.dev:
    mov [ebp+V_DEV], ebx
    mov eax, [ebx+DEV_SIZE]
    mov [ebp+V_SECTS], eax
    test dword [ebx+DEV_FLAGS], DEVF_RO
    jz .rw
    or byte [ebp+V_FLAGS], VF_RO
.rw:
    call vol_same
    jc .busy
.probe:
    call vol_probe
    jc .notfat
    mov al, [vm_letter]
    mov [ebp+V_LETTER], al
    call vol_print
    popad
    ret
.notfat:
    cmp dword [ebp+V_LOOP], 0
    je .nofat
    mov ebx, [ebp+V_LOOPFD]
    call fs_close
.nofat:
    mov esi, vm_notfat
    jmp .say
.busyloop:
    mov ebx, [ebp+V_LOOPFD]
    call fs_close
.busy:
    mov esi, vm_twice
    jmp .say
.inuse:
    mov esi, vm_inuse
    jmp .say
.why:
    movzx eax, byte [vm_why]
    mov esi, [vm_whys+eax*4-4]
    jmp .say
.fswhy:
    call fs_why
    popad
    ret
.usage:
    mov esi, vm_usage
.say:
    call puts
    popad
    ret

; esi = name -> ebx = a block device of that name that may be mounted,
; CF if none (vm_why = 0: not a device name at all, so maybe a file)
vol_disk:
    push eax
    push edi
    mov byte [vm_why], 0
    call dev_find
    test ebx, ebx
    jnz .found
    ; hd2 and hd3 are registered the first time they are asked for
    mov ebx, vol_hd2
    mov edi, vol_hd2
    call streq
    je .sec
    mov ebx, vol_hd3
    mov edi, vol_hd3
    call streq
    jne .no
.sec:
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jnz .found
    mov byte [vm_why], 1        ; no such disk
    mov al, 1
    cmp ebx, vol_hd2
    je .bit
    mov al, 2
.bit:
    test [vol_hdreg], al
    jnz .no                     ; registered before, still absent
    or [vol_hdreg], al
    push esi
    mov esi, ebx
    call dev_register
    pop esi
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jz .no
    mov byte [vm_why], 0
.found:
    mov byte [vm_why], 2
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    jne .no
    mov byte [vm_why], 3        ; the SQFS disk
    cmp byte [fs_mounted], 0
    je .ok
    cmp ebx, [fs_dev]
    je .no
.ok:
    mov byte [vm_why], 0
    pop edi
    pop eax
    clc
    ret
.no:
    pop edi
    pop eax
    stc
    ret

; ebp = new volume (V_DEV or V_LOOP set) -> CF if another drive already
; has the same disk or image mounted
vol_same:
    push eax
    push ecx
    push edi
    mov edi, vol_table
    mov ecx, VOL_MAX
.l:
    cmp byte [edi+V_LETTER], 0
    je .n
    mov eax, [ebp+V_LOOP]
    cmp eax, [edi+V_LOOP]
    jne .n
    test eax, eax
    jnz .yes
    mov eax, [ebp+V_DEV]
    cmp eax, [edi+V_DEV]
    je .yes
.n:
    add edi, V_LEN
    loop .l
    pop edi
    pop ecx
    pop eax
    clc
    ret
.yes:
    pop edi
    pop ecx
    pop eax
    stc
    ret

; ebp = volume (V_DEV/V_LOOP and V_SECTS set) -> finds its FAT boot
; sector (sector 0, or the first FAT partition in a partition table) and
; fills in the rest. CF if there is none.
vol_probe:
    pushad
    mov dword [ebp+V_BASE], 0
    xor ecx, ecx
    mov edi, fe_sec
    call vol_rsec
    jc .no
    call vol_bpb_ok
    jnc .bpb
    cmp word [fe_sec+510], 0xAA55
    jne .no
    mov esi, fe_sec+446
    mov ecx, 4
.p:
    mov al, [esi+4]
    mov edi, vol_fattypes
    push ecx
    mov ecx, vol_fattypes_len
    repne scasb
    pop ecx
    je .part
    add esi, 16
    loop .p
    jmp .no
.part:
    mov eax, [esi+8]
    cmp eax, [ebp+V_SECTS]
    jae .no
    mov [ebp+V_BASE], eax
    sub [ebp+V_SECTS], eax
    xor ecx, ecx
    mov edi, fe_sec
    call vol_rsec
    jc .no
    call vol_bpb_ok
    jc .no
.bpb:
    mov al, [fe_sec+13]
    mov [ebp+V_SPC], al
    movzx eax, al
    shl eax, 9
    mov [ebp+V_CLBYTES], eax
    mov al, [fe_sec+16]
    mov [ebp+V_NFATS], al
    movzx eax, word [fe_sec+14]
    mov [ebp+V_FATLBA], eax
    movzx eax, word [fe_sec+22]
    test eax, eax
    jnz .fsz
    mov eax, [fe_sec+36]
.fsz:
    mov [ebp+V_FATSZ], eax
    movzx eax, word [fe_sec+19]
    test eax, eax
    jnz .tot
    mov eax, [fe_sec+32]
.tot:
    mov [ebp+V_TOTAL], eax
    cmp eax, [ebp+V_SECTS]
    ja .no                      ; bigger than its disk
    movzx eax, word [fe_sec+17] ; root entries -> sectors
    shl eax, 5
    add eax, SECTOR_SIZE-1
    shr eax, 9
    mov [ebp+V_ROOTSECS], eax
    movzx eax, byte [ebp+V_NFATS]
    mul dword [ebp+V_FATSZ]
    add eax, [ebp+V_FATLBA]
    mov [ebp+V_ROOTLBA], eax
    add eax, [ebp+V_ROOTSECS]
    mov [ebp+V_DATALBA], eax
    mov ecx, [ebp+V_TOTAL]
    sub ecx, eax
    jbe .no
    mov eax, ecx
    xor edx, edx
    movzx ecx, byte [ebp+V_SPC]
    div ecx                     ; data clusters
    test eax, eax
    jz .no
    lea ecx, [eax+1]
    mov [ebp+V_MAXCL], ecx
    mov dword [ebp+V_HINT], 2
    mov byte [ebp+V_TYPE], 12
    cmp eax, 4085
    jb .typed
    mov byte [ebp+V_TYPE], 16
    cmp eax, 65525
    jb .typed
    mov byte [ebp+V_TYPE], 32
    mov eax, [fe_sec+44]
    cmp eax, 2
    jb .no
    mov [ebp+V_ROOTCL], eax
    movzx eax, word [fe_sec+48]
    test eax, eax
    jz .typed
    cmp eax, 0xFFFF
    je .typed
    mov [ebp+V_FSINFO], eax
    or byte [ebp+V_FLAGS], VF_FSINFO
.typed:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; fe_sec = a boot sector -> CF unless it looks like FAT's
vol_bpb_ok:
    cmp word [fe_sec+11], SECTOR_SIZE
    jne .no
    mov al, [fe_sec+13]         ; a power of two
    test al, al
    jz .no
    mov ah, al
    dec ah
    test al, ah
    jnz .no
    cmp word [fe_sec+14], 0     ; reserved sectors
    je .no
    cmp byte [fe_sec+16], 0     ; FATs
    je .no
    cmp byte [fe_sec+16], 4
    ja .no
    cmp word [fe_sec+19], 0
    jne .t
    cmp dword [fe_sec+32], 0
    je .no
.t:
    cmp word [fe_sec+22], 0
    jne .ok
    cmp dword [fe_sec+36], 0
    je .no
.ok:
    clc
    ret
.no:
    stc
    ret

; ebp = volume -> "D: FAT16, 15 MB, hd2" (and ", read-only")
vol_print:
    pushad
    mov al, [ebp+V_LETTER]
    call putc
    mov esi, vm_fat
    call puts
    movzx eax, byte [ebp+V_TYPE]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, vm_comma
    call puts
    mov eax, [ebp+V_TOTAL]
    shr eax, 1                  ; KB
    mov esi, vm_kb
    cmp eax, 10240
    jb .k
    shr eax, 10
    mov esi, vm_mb
.k:
    push esi
    call itoa
    mov esi, num_buf
    call puts
    pop esi
    call puts
    lea esi, [ebp+V_SRC]
    call puts
    test byte [ebp+V_FLAGS], VF_RO
    jz .nl
    mov esi, vm_ro
    call puts
.nl:
    mov al, 10
    call putc
    popad
    ret

; mount alone: every mounted drive
vol_list:
    pushad
    xor edx, edx
    mov ebp, vol_table
    mov ecx, VOL_MAX
.l:
    cmp byte [ebp+V_LETTER], 0
    je .n
    call vol_print
    inc edx
.n:
    add ebp, V_LEN
    loop .l
    test edx, edx
    jnz .r
    mov esi, vm_none
    call puts
.r:
    popad
    ret

; esi = "x:" -> unmounts it (refused while a file on it is open)
vol_umount:
    pushad
    call vol_path
    jc .usage
    call vol_find
    jc .why
    mov ebx, fs_fds
    mov ecx, FS_MAXFD
.l:
    cmp dword [ebx+FD_DIRENT], 0
    je .n
    cmp [ebx+FD_VOL], ebp
    jne .n
    mov byte [fs_errno], FE_BUSY
    jmp .why
.n:
    add ebx, 16
    loop .l
    call fat_flush
    cmp [fc_vol], ebp
    jne .c
    call fat_drop_cache
.c:
    cmp dword [ebp+V_LOOP], 0
    je .free
    mov ebx, [ebp+V_LOOPFD]
    call fs_close
.free:
    mov byte [ebp+V_LETTER], 0
    mov esi, fs_ok
    call puts
    popad
    ret
.why:
    call fs_why
    popad
    ret
.usage:
    mov esi, vu_usage
    call puts
    popad
    ret

; ---------- cp ----------

; esi = path -> CF clear if it names a directory (SQFS or a drive)
vol_isdir:
    push edx
    call vol_path
    jc .sq
    call fat_is_dir
    pop edx
    ret
.sq:
    cmp byte [fs_mounted], 0
    je .no
    call fs_find_dir
    pop edx
    ret
.no:
    pop edx
    stc
    ret

; cp <from> <to>: <to> may be a directory (the file keeps its name)
cmd_cp_run:
    pushad
    call next_word
    mov ebx, esi
    mov esi, edi
    call next_word
    cmp byte [esi], 0
    je .usage
    cmp byte [ebx], 0
    je .usage
    mov edi, cp_dst
    call fat_copy_path
    mov esi, ebx
    mov edi, cp_src
    call fat_copy_path
    mov esi, cp_dst
    call vol_isdir
    jc .named
    ; into the directory: add "/" and the source's last part
    mov edi, cp_dst
.end:
    cmp byte [edi], 0
    je .atend
    inc edi
    jmp .end
.atend:
    mov al, [edi-1]
    cmp al, '/'
    je .base
    cmp al, ':'
    je .base
    mov byte [edi], '/'
    inc edi
.base:
    mov esi, cp_src             ; after the last '/' or ':'
    mov edx, esi
.b:
    lodsb
    test al, al
    jz .bd
    cmp al, '/'
    je .bs
    cmp al, ':'
    jne .b
.bs:
    mov edx, esi
    jmp .b
.bd:
    mov esi, edx
    mov ecx, cp_dst+FS_PATHMAX-1
.bc:
    cmp edi, ecx
    jae .bz
    lodsb
    stosb
    test al, al
    jnz .bc
.bz:
    mov byte [edi], 0
.named:
    mov esi, cp_src
    mov edi, cp_dst
    call streq
    je .same
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .why
    mov [cp_sfd], eax
    mov esi, cp_dst
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .why1
    mov [cp_dfd], eax
    mov dword [cp_bytes], 0
.copy:
    mov ebx, [cp_sfd]
    mov edi, cp_buf
    mov ecx, CP_BUFSZ
    call fs_read
    cmp eax, -1
    je .why2
    test eax, eax
    jz .done
    mov ecx, eax
    mov ebx, [cp_dfd]
    mov esi, cp_buf
    push ecx
    call fs_write
    pop ecx
    cmp eax, ecx
    jne .why2
    add [cp_bytes], eax
    jmp .copy
.done:
    mov ebx, [cp_dfd]
    call fs_close
    mov ebx, [cp_sfd]
    call fs_close
    mov eax, [cp_bytes]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, cp_copied
    call puts
    popad
    ret
.why2:
    mov al, [fs_errno]
    mov ebx, [cp_dfd]
    call fs_close
    mov [fs_errno], al
.why1:
    mov al, [fs_errno]
    mov ebx, [cp_sfd]
    call fs_close
    mov [fs_errno], al
.why:
    call fs_why
    popad
    ret
.same:
    mov esi, cp_samemsg
    call puts
    popad
    ret
.usage:
    mov esi, cp_usage
    call puts
    popad
    ret

; ---------- the shell's hook ----------

; esi = command line the shell does not know -> CF if not ours either
vol_command:
    push edi
    mov edi, vc_mount
    call streq
    je .list
    mov edi, vc_mount_arg
    call streq_prefix
    je .mount
    mov edi, vc_umount_arg
    call streq_prefix
    je .umount
    mov edi, vc_cp_arg
    call streq_prefix
    je .cp
    mov edi, vc_lfntest
    call streq
    je .lfntest
    mov edi, vc_fattest_arg
    call streq_prefix
    je .fattest
    pop edi
    stc
    ret
.list:
    call vol_list
    jmp .done
.mount:
    add esi, 6
    call next_word
    push esi
    mov esi, edi
    call next_word
    mov edi, esi
    pop esi
    call vol_mount
    jmp .done
.umount:
    add esi, 7
    call next_word
    call vol_umount
    jmp .done
.cp:
    add esi, 3
    call cmd_cp_run
    jmp .done
.lfntest:
    call cmd_lfntest_run
    jmp .done
.fattest:
    add esi, 8
    call next_word
    call cmd_fattest_run
.done:
    pop edi
    clc
    ret

; ---------- fattest ----------

; fattest x:  on a mounted, writable drive: makes a directory, writes a
; file with a long name across clusters, reads it back (by its name in
; another case too), seeks, appends, renames it, moves it into a
; subdirectory, checks that a full directory cannot be removed, removes
; everything and checks that no cluster was lost. PASS or FAIL.
cmd_fattest_run:
    pushad
    call vol_path
    jc .usage
    mov al, [esi]
    mov ecx, ftt_count
    mov ebx, ftt_paths
.patch:
    mov edi, [ebx]
    mov [edi], al
    add ebx, 4
    loop .patch
    mov esi, ftt_dir
    call vol_find
    jc .why
    mov dword [st_fail], 0
    mov esi, ftt_moved          ; leftovers of an earlier run
    call fs_delete
    mov esi, ftt_sub
    call fs_delete
    mov esi, ftt_short
    call fs_delete
    mov esi, ftt_long
    call fs_delete
    mov esi, ftt_dir
    call fs_delete
    call fat_count_free
    mov [ftt_free0], eax
    ; pattern: byte i = i * 7 + (i >> 8)
    mov edi, ftt_b
    xor eax, eax
.fill:
    mov edx, eax
    imul edx, 7
    mov ecx, eax
    shr ecx, 8
    add edx, ecx
    mov [edi+eax], dl
    inc eax
    cmp eax, FTT_LEN+100
    jb .fill
    mov esi, ftt_dir
    call fs_mkdir
    test eax, eax
    call st_check
    mov esi, ftt_long
    mov ecx, O_CREATE
    call fs_open
    cmp eax, -1
    je .fail
    mov [ftt_fd], eax
    mov ebx, eax
    mov esi, ftt_b
    mov ecx, 3000
    call fs_write
    cmp eax, 3000
    call st_check
    mov ebx, [ftt_fd]
    mov esi, ftt_b+3000
    mov ecx, FTT_LEN-3000
    call fs_write
    cmp eax, FTT_LEN-3000
    call st_check
    mov ebx, [ftt_fd]
    call fs_close
    ; read back through the name in other letters
    mov esi, ftt_case
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fail
    mov [ftt_fd], eax
    mov ebx, eax
    mov edi, ftt_a
    mov ecx, FTT_LEN+50
    call fs_read
    cmp eax, FTT_LEN
    call st_check
    mov esi, ftt_a
    mov edi, ftt_b
    mov ecx, FTT_LEN
    repe cmpsb
    call st_check
    mov ebx, [ftt_fd]
    mov edi, ftt_a
    mov ecx, 10
    call fs_read
    test eax, eax
    call st_check
    mov ebx, [ftt_fd]
    mov ecx, 4000
    mov edx, SEEK_SET
    call fs_seek
    cmp eax, 4000
    call st_check
    mov ebx, [ftt_fd]
    mov edi, ftt_a
    mov ecx, 10
    call fs_read
    cmp eax, 10
    call st_check
    mov esi, ftt_a
    mov edi, ftt_b+4000
    mov ecx, 10
    repe cmpsb
    call st_check
    mov ebx, [ftt_fd]
    call fs_close
    ; append 100 bytes
    mov esi, ftt_long
    mov ecx, O_APPEND
    call fs_open
    cmp eax, -1
    je .fail
    mov [ftt_fd], eax
    mov ebx, eax
    mov esi, ftt_b+FTT_LEN
    mov ecx, 100
    call fs_write
    cmp eax, 100
    call st_check
    mov ebx, [ftt_fd]
    xor ecx, ecx
    mov edx, SEEK_END
    call fs_seek
    cmp eax, FTT_LEN+100
    call st_check
    mov ebx, [ftt_fd]
    call fs_close
    ; rename, then into a subdirectory
    mov esi, ftt_long
    mov edi, ftt_short
    call fs_rename
    test eax, eax
    call st_check
    mov esi, ftt_long
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    call st_check
    mov esi, ftt_sub
    call fs_mkdir
    test eax, eax
    call st_check
    mov esi, ftt_short
    mov edi, ftt_sub
    call fs_rename
    test eax, eax
    call st_check
    mov esi, ftt_moved
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fail
    mov [ftt_fd], eax
    mov ebx, eax
    mov edi, ftt_a
    mov ecx, FTT_LEN+200
    call fs_read
    cmp eax, FTT_LEN+100
    call st_check
    mov esi, ftt_a
    mov edi, ftt_b
    mov ecx, FTT_LEN+100
    repe cmpsb
    call st_check
    ; 20 more long names in the subdirectory: it grows past a sector
    mov dword [ftt_n], 0
.many:
    call ftt_many_name
    call fs_create
    test eax, eax
    call st_check
    inc dword [ftt_n]
    cmp dword [ftt_n], 20
    jb .many
    mov edx, ftt_sub            ; the listing sees all 21
    call rl_count
    cmp eax, 21
    call st_check
    mov dword [ftt_n], 17
    call ftt_many_name
    mov ecx, O_APPEND
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    call fs_close
    mov dword [ftt_n], 0
.unmany:
    call ftt_many_name
    call fs_delete
    test eax, eax
    call st_check
    inc dword [ftt_n]
    cmp dword [ftt_n], 20
    jb .unmany
    mov esi, ftt_moved          ; open: cannot be deleted
    call fs_delete
    cmp eax, -1
    call st_check
    mov ebx, [ftt_fd]
    call fs_close
    mov esi, ftt_dir            ; not empty
    call fs_delete
    cmp eax, -1
    call st_check
    mov esi, ftt_moved
    call fs_delete
    test eax, eax
    call st_check
    mov esi, ftt_sub
    call fs_delete
    test eax, eax
    call st_check
    mov esi, ftt_dir
    call fs_delete
    test eax, eax
    call st_check
    mov esi, ftt_dir
    call vol_find
    call fat_count_free
    cmp eax, [ftt_free0]
    call st_check
    mov esi, ftt_pass
    cmp dword [st_fail], 0
    je .out
.fail:
    mov esi, ftt_failmsg
.out:
    call puts
    popad
    ret
.why:
    call fs_why
    popad
    ret
.usage:
    mov esi, ftt_usage
    call puts
    popad
    ret

; -> esi = ftt_many with the number ftt_n (two digits) in it
ftt_many_name:
    push eax
    push edx
    mov eax, [ftt_n]
    mov dl, 10
    div dl
    add ax, '00'
    mov [ftt_many+FTT_NUM], ax
    mov esi, ftt_many
    pop edx
    pop eax
    ret

FTT_LEN equ 9000                ; more than one cluster of up to 8 KB

; ---------- data ----------
align 4
vol_hd2:
    db 'hd2', 0, 0, 0, 0, 0
    dd DEV_BLOCK, ata_dev_probe, ata_dev_read, ata_dev_write, 2, 0, 0, 0
vol_hd3:
    db 'hd3', 0, 0, 0, 0, 0
    dd DEV_BLOCK, ata_dev_probe, ata_dev_read, ata_dev_write, 3, 0, 0, 0
vol_table times VOL_MAX*V_LEN db 0
vol_fattypes db 0x01, 0x04, 0x06, 0x0B, 0x0C, 0x0E
vol_fattypes_len equ $-vol_fattypes
vm_letter db 0
vol_hdreg db 0                  ; 1 hd2, 2 hd3 registered
vm_why db 0
align 4
vm_whys dd vm_nodisk, vm_notblock, vm_sqfs
vm_nodisk db 'No such disk', 10, 0
vm_notblock db 'Not a disk', 10, 0
vm_sqfs db 'That disk holds the SQFS file system', 10, 0
vm_full db 'Four drives are mounted already', 10, 0
vm_inuse db 'That drive letter is in use (umount it first)', 10, 0
vm_twice db 'Already mounted on another drive letter', 10, 0
vm_notfat db 'Not a FAT volume', 10, 0
vm_none db 'No drives mounted. Usage: mount <x:> <disk|image file>', 10, 0
vm_usage db 'Usage: mount <x:> <disk|image file>', 10, 0
vu_usage db 'Usage: umount <x:>', 10, 0
vm_fat db ': FAT', 0
vm_comma db ', ', 0
vm_kb db ' KB, ', 0
vm_mb db ' MB, ', 0
vm_ro db ', read-only', 0
vc_mount db 'mount', 0
vc_mount_arg db 'mount ', 0
vc_umount_arg db 'umount ', 0
vc_cp_arg db 'cp ', 0
vc_lfntest db 'lfntest', 0
vc_fattest_arg db 'fattest ', 0
cp_usage db 'Usage: cp <from> <to|dir>', 10, 0
cp_samemsg db 'A file cannot be copied onto itself', 10, 0
cp_copied db ' bytes copied', 10, 0
CP_BUFSZ equ 2048
align 4
cp_sfd dd 0
cp_dfd dd 0
cp_bytes dd 0
cp_src times FS_PATHMAX db 0
cp_dst times FS_PATHMAX db 0
cp_buf times CP_BUFSZ db 0
ftt_fd dd 0
ftt_a times FTT_LEN+200 db 0
ftt_b times FTT_LEN+200 db 0
ftt_free0 dd 0
ftt_paths dd ftt_dir, ftt_long, ftt_case, ftt_short, ftt_sub, ftt_moved, ftt_many
ftt_count equ ($-ftt_paths)/4
ftt_dir db '?:/fattest-dir', 0
ftt_long db '?:/fattest-dir/A Long File Name for FAT.txt', 0
ftt_case db '?:\FATTEST-DIR\a long file name FOR fat.TXT', 0
ftt_short db '?:/fattest-dir/short.txt', 0
ftt_sub db '?:/fattest-dir/sub', 0
ftt_moved db '?:/fattest-dir/sub/short.txt', 0
ftt_many db '?:/fattest-dir/sub/A file among many, number 00.txt', 0
FTT_NUM equ 45
ftt_n dd 0
ftt_pass db 'fattest: PASS', 10, 0
ftt_failmsg db 'fattest: FAIL', 10, 0
ftt_usage db 'Usage: fattest <x:>', 10, 0

; ---------- listing with long names (2.7) ----------

; SYS_READDIR with bit 31 of ebx set, and for kernel callers: ebx = cursor
; (0 first) | 0x80000000, ecx = RD_LEN-byte buffer, edx = directory path
; ("d:/docs", "/notes", ...) or 0 for the current SQFS directory ->
; the buffer gets the next entry: its whole name (RD_NAME bytes, zero-
; terminated), size (-1 for a directory) and flags (RDF_DIR); eax = the
; next cursor (bit 31 set), 0 at the end, -1 if there is no such directory
RD_NAME       equ 64
RD_SIZE       equ 64
RD_FLAGS      equ 68
RD_LEN        equ 72
RDF_DIR       equ 1
fs_readdir_long:
    pushad
    and ebx, 0x7FFFFFFF
    mov [rl_buf], ecx
    test edx, edx
    jz .cwd
    cmp byte [edx], 0
    je .cwd
    mov esi, edx
    call vol_path
    jnc .fat
    cmp byte [fs_mounted], 0
    je .err
    call fs_find_dir
    jc .err
    jmp .sq
.cwd:
    cmp byte [fs_mounted], 0
    je .err
    mov dl, [fs_cwd]
.sq:
    cmp ebx, FS_MAXFILES
    jae .end
    mov edi, ebx
    shl edi, 5
    add edi, FS_DIR
    inc ebx
    cmp byte [edi], 0
    je .sq
    cmp byte [edi+DE_KIND], DK_LFN
    je .sq
    cmp [edi+DE_PARENT], dl
    jne .sq
    call lfn_name
    mov eax, [edi+DE_SIZE]
    xor edx, edx
    cmp byte [edi+DE_KIND], DK_DIR
    jne .put
    mov eax, -1
    mov edx, RDF_DIR
    jmp .put
.fat:
    call fat_find_dir
    jc .err
    call fd_start
    mov ecx, ebx                ; entries to pass over
.skip:
    call fd_next
    jc .end
    jecxz .got
    dec ecx
    jmp .skip
.got:
    inc ebx
    mov esi, fd_name
    mov eax, [edi+FE_DSIZE]
    xor edx, edx
    test byte [edi+FE_DATTR], FA_DIR
    jz .put
    mov eax, -1
    mov edx, RDF_DIR
.put:
    mov edi, [rl_buf]
    mov [edi+RD_SIZE], eax
    mov [edi+RD_FLAGS], edx
    mov ecx, RD_NAME-1
.c:
    lodsb
    test al, al
    jz .cz
    stosb
    loop .c
.cz:
    mov byte [edi], 0
    or ebx, 0x80000000
    mov [esp+28], ebx
    popad
    ret
.end:
    popad
    xor eax, eax
    ret
.err:
    popad
    mov eax, -1
    ret

; edx = directory path -> eax = its entries (fs_readdir_long), -1 if none
rl_count:
    push ebx
    push ecx
    push edx
    xor eax, eax
    mov [rl_n], eax
    mov ebx, 0x80000000
.l:
    mov ecx, rl_entry
    call fs_readdir_long
    cmp eax, -1
    je .r
    test eax, eax
    jz .d
    inc dword [rl_n]
    mov ebx, eax
    jmp .l
.d:
    mov eax, [rl_n]
.r:
    pop edx
    pop ecx
    pop ebx
    ret

align 4
rl_buf dd 0
rl_n dd 0
rl_entry times RD_LEN db 0
