; Squirrel-OS/2 — SQFS on-disk file system (0.2.1 / 0.2.2)
; Included from pm.asm. Original code.
;
; Flat directory of contiguous extents on the data disk (device hd1,
; the primary slave).
; See documentation/kernel/filesystem.md for the format.

FS_DEV        equ dev_hd1     ; the data disk (0.7.2: through the device table)
FS_MAGIC      equ 0x53465153    ; 'SQFS'
FS_VERSION    equ 1
FS_DIR_LBA    equ 1
FS_DIR_SECTS  equ 4
FS_DATA_LBA   equ FS_DIR_LBA+FS_DIR_SECTS
FS_DIRENT     equ 32
FS_MAXFILES   equ FS_DIR_SECTS*SECTOR_SIZE/FS_DIRENT    ; 64
FS_NAMELEN    equ 16            ; including the terminating zero
FS_MAXFD      equ 8

; superblock (sector 0)
SB_MAGIC      equ 0
SB_VERSION    equ 4
SB_TOTAL      equ 8             ; sectors usable by the FS
SB_DIRLBA     equ 12
SB_DIRSECTS   equ 16
SB_DATALBA    equ 20

; directory entry
DE_NAME       equ 0
DE_START      equ 16
DE_SIZE       equ 20            ; bytes
DE_CAP        equ 24            ; sectors allocated

; open flags
O_CREATE      equ 1
O_TRUNC       equ 2
O_APPEND      equ 4

; buffers in the kernel scratch area
FS_SB         equ KSCRATCH+0x800
FS_SEC        equ KSCRATCH+0xA00
FS_DIR        equ KSCRATCH+0x1000   ; 2 KB directory cache (write-through)

; ---------- mount / format ----------

; Mounts the data disk. A blank disk (sector 0 all zero) is formatted
; and seeded with the built-in files; any other non-SQFS disk is left
; alone and reported.
fs_mount_boot:
    pushad
    mov byte [fs_mounted], 0
    cmp dword [FS_DEV+DEV_SIZE], FS_DATA_LBA+2
    jb .out                     ; no (usable) data disk
    mov ebx, FS_DEV
    xor ecx, ecx
    mov edi, FS_SB
    call dev_bread
    jc .out
    cmp dword [FS_SB+SB_MAGIC], FS_MAGIC
    je .mount
    mov esi, FS_SB
    mov ecx, SECTOR_SIZE/4
.blank:
    lodsd
    test eax, eax
    jnz .foreign
    loop .blank
    call fs_format
    jc .out
    mov esi, fs_msg_formatted
    call puts
    jmp .out
.foreign:
    mov esi, fs_msg_foreign
    call puts
    jmp .out
.mount:
    call fs_load
.out:
    popad
    ret

; Superblock in FS_SB -> loads the directory and marks mounted. CF on error.
fs_load:
    pushad
    mov ebx, FS_DEV
    mov ecx, FS_DIR_LBA
    mov edi, FS_DIR
.r:
    call dev_bread
    jc .fail
    inc ecx
    add edi, SECTOR_SIZE
    cmp ecx, FS_DIR_LBA+FS_DIR_SECTS
    jb .r
    mov eax, [FS_SB+SB_TOTAL]
    mov [fs_total], eax
    mov byte [fs_mounted], 1
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Writes a fresh superblock and empty directory, then seeds the built-in
; files. CF on error.
fs_format:
    pushad
    mov byte [fs_mounted], 0
    mov edi, FS_SB
    mov ecx, SECTOR_SIZE/4
    xor eax, eax
    rep stosd
    mov dword [FS_SB+SB_MAGIC], FS_MAGIC
    mov dword [FS_SB+SB_VERSION], FS_VERSION
    mov eax, [FS_DEV+DEV_SIZE]
    dec eax                     ; last sector is kept for blktest
    mov [FS_SB+SB_TOTAL], eax
    mov dword [FS_SB+SB_DIRLBA], FS_DIR_LBA
    mov dword [FS_SB+SB_DIRSECTS], FS_DIR_SECTS
    mov dword [FS_SB+SB_DATALBA], FS_DATA_LBA
    mov edi, FS_DIR
    mov ecx, FS_DIR_SECTS*SECTOR_SIZE/4
    xor eax, eax
    rep stosd
    mov eax, [FS_SB+SB_TOTAL]
    mov [fs_total], eax
    call fs_flush_dir
    jc .fail
    mov ebx, FS_DEV
    xor ecx, ecx
    mov esi, FS_SB
    call dev_bwrite
    jc .fail
    mov byte [fs_mounted], 1
    mov dword [fs_fds], 0       ; drop any open descriptors
    mov edi, fs_fds
    mov ecx, FS_MAXFD*4
    xor eax, eax
    rep stosd
    call fs_seed
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Copies every ROM file into the file system.
fs_seed:
    pushad
    mov ebx, file_table
    mov ecx, [file_count]
.f:
    push ecx
    push ebx
    mov esi, ebx                ; name
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .next
    mov edx, eax                ; fd
    mov esi, [ebx+8]            ; data
    call strlen
    mov ecx, eax
    mov ebx, edx
    call fs_write
    mov ebx, edx
    call fs_close
.next:
    pop ebx
    pop ecx
    add ebx, 16
    loop .f
    popad
    ret

fs_flush_dir:
    pushad
    mov ebx, FS_DEV
    mov ecx, FS_DIR_LBA
    mov esi, FS_DIR
.w:
    call dev_bwrite
    jc .fail
    inc ecx
    add esi, SECTOR_SIZE
    cmp ecx, FS_DIR_LBA+FS_DIR_SECTS
    jb .w
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ---------- directory helpers ----------

; esi = name -> edi = dirent or 0
fs_lookup:
    push ecx
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [edi], 0
    je .n
    push edi
    call streq_bounded
    pop edi
    je .hit
.n:
    add edi, FS_DIRENT
    loop .l
    xor edi, edi
.hit:
    pop ecx
    ret

; esi, edi = names; ZF set if equal (compares at most FS_NAMELEN bytes)
streq_bounded:
    push eax
    push ecx
    push esi
    mov ecx, FS_NAMELEN
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .ne
    test al, al
    jz .eq
    inc esi
    inc edi
    loop .c
.eq:
    xor eax, eax                ; ZF=1
    jmp .o
.ne:
    or eax, 1                   ; ZF=0
.o:
    pop esi
    pop ecx
    pop eax
    ret

; esi = name -> CF set if empty or too long
fs_check_name:
    push eax
    call strlen
    test eax, eax
    jz .bad
    cmp eax, FS_NAMELEN-1
    ja .bad
    pop eax
    clc
    ret
.bad:
    pop eax
    stc
    ret

; esi = ASCIIZ -> eax = length
strlen:
    push esi
    xor eax, eax
.l:
    cmp byte [esi+eax], 0
    je .d
    inc eax
    jmp .l
.d:
    pop esi
    ret

; ecx = sectors wanted, edx = dirent to ignore (or 0) -> eax = first LBA
; of a free run, CF if the disk is full. First fit over the extents.
fs_alloc:
    push ebx
    push esi
    push edi
    mov eax, FS_DATA_LBA
.retry:
    mov edi, FS_DIR
    mov esi, FS_MAXFILES
.e:
    cmp byte [edi], 0
    je .next
    cmp edi, edx
    je .next
    mov ebx, [edi+DE_CAP]
    test ebx, ebx
    jz .next
    add ebx, [edi+DE_START]     ; ebx = end of this extent
    cmp [edi+DE_START], eax     ; overlap if start < cand+n and cand < end
    jb .chk2
    push eax
    add eax, ecx
    cmp [edi+DE_START], eax
    pop eax
    jae .next
.chk2:
    cmp eax, ebx
    jae .next
    mov eax, ebx                ; move past it and rescan
    jmp .retry
.next:
    add edi, FS_DIRENT
    dec esi
    jnz .e
    push eax
    add eax, ecx
    cmp eax, [fs_total]
    pop eax
    ja .full
    clc
    jmp .out
.full:
    stc
.out:
    pop edi
    pop esi
    pop ebx
    ret

; edi = dirent, ecx = sectors needed. Moves the file to a larger extent
; if its capacity is smaller. CF on error (disk full / IO).
fs_ensure_cap:
    pushad
    cmp ecx, [edi+DE_CAP]
    jbe .ok
    mov eax, [edi+DE_CAP]       ; grow to max(needed, 2*cap)
    shl eax, 1
    cmp eax, ecx
    jae .sized
    mov eax, ecx
.sized:
    mov ecx, eax
    mov edx, edi
    call fs_alloc
    jc .fail
    ; copy the old extent sector by sector
    mov ebp, eax                ; new start
    xor esi, esi
.copy:
    cmp esi, [edi+DE_CAP]
    jae .moved
    push ecx
    push edi
    mov ebx, FS_DEV
    mov ecx, [edi+DE_START]
    add ecx, esi
    mov edi, FS_SEC
    call dev_bread
    pop edi
    pop ecx
    jc .fail
    push ecx
    push esi
    mov ebx, FS_DEV
    lea ecx, [ebp+esi]
    mov esi, FS_SEC
    call dev_bwrite
    pop esi
    pop ecx
    jc .fail
    inc esi
    jmp .copy
.moved:
    mov [edi+DE_START], ebp
    mov [edi+DE_CAP], ecx
    call fs_flush_dir
    jc .fail
.ok:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ---------- public API (kernel; also behind syscalls 10..16) ----------

; esi = name -> eax = 0, or -1 (bad name, exists, directory full, no FS)
fs_create:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    call fs_check_name
    jc .fail
    call fs_lookup
    test edi, edi
    jnz .fail
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.f:
    cmp byte [edi], 0
    je .slot
    add edi, FS_DIRENT
    loop .f
    jmp .fail
.slot:
    push edi
    mov ecx, FS_DIRENT/4
    xor eax, eax
    rep stosd
    pop edi
    push edi
    call strlen
    mov ecx, eax
    rep movsb
    pop edi
    call fs_flush_dir
    jc .fail
    popad
    xor eax, eax
    ret
.fail:
    popad
    mov eax, -1
    ret

; esi = name -> 0 or -1. Refused while the file is open.
fs_delete:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    call fs_lookup
    test edi, edi
    jz .fail
    call fs_is_open
    jc .fail
    mov byte [edi], 0
    mov dword [edi+DE_CAP], 0
    call fs_flush_dir
    jc .fail
    popad
    xor eax, eax
    ret
.fail:
    popad
    mov eax, -1
    ret

; esi = old name, edi = new name -> 0 or -1
fs_rename:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    push esi
    mov esi, edi
    call fs_check_name
    jc .fail_pop
    call fs_lookup              ; new name must not exist
    test edi, edi
    jnz .fail_pop
    mov ebx, esi                ; ebx = new name
    pop esi
    call fs_lookup
    test edi, edi
    jz .fail
    push edi
    mov ecx, FS_NAMELEN/4
    xor eax, eax
    rep stosd
    pop edi
    mov esi, ebx
    call strlen
    mov ecx, eax
    rep movsb
    call fs_flush_dir
    jc .fail
    popad
    xor eax, eax
    ret
.fail_pop:
    pop esi
.fail:
    popad
    mov eax, -1
    ret

; edi = dirent -> CF set if some descriptor refers to it
fs_is_open:
    push ecx
    push ebx
    mov ebx, fs_fds
    mov ecx, FS_MAXFD
.l:
    cmp [ebx], edi
    je .yes
    add ebx, 16
    loop .l
    pop ebx
    pop ecx
    clc
    ret
.yes:
    pop ebx
    pop ecx
    stc
    ret

; descriptor table: 16 bytes each: dirent (0 = free), position
FD_DIRENT     equ 0
FD_POS        equ 4

; esi = name, ecx = flags (O_CREATE, O_TRUNC, O_APPEND) -> eax = fd or -1
fs_open:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    call fs_lookup
    test edi, edi
    jnz .found
    test ecx, O_CREATE
    jz .fail
    call fs_create
    test eax, eax
    jnz .fail
    call fs_lookup
.found:
    mov ebx, fs_fds
    xor edx, edx
.f:
    cmp dword [ebx+FD_DIRENT], 0
    je .slot
    add ebx, 16
    inc edx
    cmp edx, FS_MAXFD
    jb .f
    jmp .fail
.slot:
    mov [ebx+FD_DIRENT], edi
    mov dword [ebx+FD_POS], 0
    test ecx, O_TRUNC
    jz .notrunc
    mov dword [edi+DE_SIZE], 0
    call fs_flush_dir
.notrunc:
    test ecx, O_APPEND
    jz .done
    mov eax, [edi+DE_SIZE]
    mov [ebx+FD_POS], eax
.done:
    mov [esp+28], edx
    popad
    ret
.fail:
    popad
    mov eax, -1
    ret

; ebx = fd -> edi = descriptor or CF
fs_fd:
    cmp ebx, FS_MAXFD
    jae .bad
    mov edi, ebx
    shl edi, 4
    add edi, fs_fds
    cmp dword [edi+FD_DIRENT], 0
    je .bad
    clc
    ret
.bad:
    stc
    ret

fs_close:
    push edi
    call fs_fd
    jc .bad
    mov dword [edi+FD_DIRENT], 0
    pop edi
    xor eax, eax
    ret
.bad:
    pop edi
    mov eax, -1
    ret

; ebx = fd, edi = buffer, ecx = length -> eax = bytes read, or -1
fs_read:
    pushad
    mov ebp, edi                ; ebp = destination
    call fs_fd
    jc .fail
    mov edx, edi                ; edx = descriptor
    mov esi, [edx+FD_DIRENT]
    mov eax, [esi+DE_SIZE]
    sub eax, [edx+FD_POS]
    jbe .eof
    cmp ecx, eax
    jbe .len
    mov ecx, eax
.len:
    mov [fs_xfer_total], ecx
.chunk:
    test ecx, ecx
    jz .done
    ; sector = pos / 512, offset = pos % 512
    mov eax, [edx+FD_POS]
    push ecx
    push edx
    mov ebx, FS_DEV
    mov ecx, eax
    shr ecx, 9
    add ecx, [esi+DE_START]
    mov edi, FS_SEC
    call dev_bread
    pop edx
    pop ecx
    jc .fail
    mov eax, [edx+FD_POS]
    and eax, SECTOR_SIZE-1
    mov ebx, SECTOR_SIZE
    sub ebx, eax                ; bytes left in this sector
    cmp ebx, ecx
    jbe .n
    mov ebx, ecx
.n:
    push ecx
    push esi
    lea esi, [FS_SEC+eax]
    mov edi, ebp
    mov ecx, ebx
    rep movsb
    pop esi
    pop ecx
    add ebp, ebx
    add [edx+FD_POS], ebx
    sub ecx, ebx
    jmp .chunk
.done:
    mov eax, [fs_xfer_total]
    mov [esp+28], eax
    popad
    ret
.eof:
    popad
    xor eax, eax
    ret
.fail:
    popad
    mov eax, -1
    ret

; ebx = fd, esi = buffer, ecx = length -> eax = bytes written, or -1
fs_write:
    pushad
    mov ebp, esi                ; ebp = source
    call fs_fd
    jc .fail
    mov edx, edi                ; edx = descriptor
    mov esi, [edx+FD_DIRENT]
    mov [fs_xfer_total], ecx
    ; make room for pos + len
    mov eax, [edx+FD_POS]
    add eax, ecx
    jc .fail
    add eax, SECTOR_SIZE-1
    shr eax, 9
    push ecx
    mov ecx, eax
    mov edi, esi
    call fs_ensure_cap
    pop ecx
    jc .fail
.chunk:
    test ecx, ecx
    jz .done
    mov eax, [edx+FD_POS]
    push ecx
    push edx
    mov ebx, FS_DEV
    mov ecx, eax
    shr ecx, 9
    add ecx, [esi+DE_START]
    mov [fs_xfer_lba], ecx
    mov edi, FS_SEC
    call dev_bread               ; read-modify-write
    pop edx
    pop ecx
    jc .fail
    mov eax, [edx+FD_POS]
    and eax, SECTOR_SIZE-1
    mov ebx, SECTOR_SIZE
    sub ebx, eax
    cmp ebx, ecx
    jbe .n
    mov ebx, ecx
.n:
    push ecx
    push esi
    lea edi, [FS_SEC+eax]
    mov esi, ebp
    mov ecx, ebx
    rep movsb
    pop esi
    pop ecx
    push ebx
    push ecx
    push esi
    mov ebx, FS_DEV
    mov ecx, [fs_xfer_lba]
    mov esi, FS_SEC
    call dev_bwrite
    pop esi
    pop ecx
    pop ebx
    jc .fail
    add ebp, ebx
    add [edx+FD_POS], ebx
    sub ecx, ebx
    mov eax, [edx+FD_POS]
    cmp eax, [esi+DE_SIZE]
    jbe .chunk
    mov [esi+DE_SIZE], eax
    jmp .chunk
.done:
    call fs_flush_dir
    jc .fail
    mov eax, [fs_xfer_total]
    mov [esp+28], eax
    popad
    ret
.fail:
    popad
    mov eax, -1
    ret

; ---------- shell commands ----------

; ls: FS listing with sizes, or the ROM table when no FS is mounted
fs_list:
    cmp byte [fs_mounted], 0
    je rom_list
    mov esi, fs_header
    call puts
    mov ebx, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [ebx], 0
    je .n
    mov esi, ebx
    call puts
    mov al, 18
    call puts_pad
    mov eax, [ebx+DE_SIZE]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
.n:
    add ebx, FS_DIRENT
    loop .l
    ret

; cat <name>
fs_cat:
    cmp byte [fs_mounted], 0
    je rom_cat
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .nf
    mov ebx, eax
    mov byte [fs_cat_last], 10
.r:
    mov edi, FS_CATBUF
    mov ecx, 255
    call fs_read
    test eax, eax
    jle .end
    mov byte [FS_CATBUF+eax], 0
    mov dl, [FS_CATBUF+eax-1]
    mov [fs_cat_last], dl
    mov esi, FS_CATBUF
    call puts
    jmp .r
.end:
    call fs_close
    cmp byte [fs_cat_last], 10  ; finish an unterminated last line
    je .nl
    mov al, 10
    call putc
.nl:
    ret
.nf:
    mov esi, notfound
    call puts
    ret
FS_CATBUF equ KSCRATCH+0x1800

; Splits the first word off esi: returns esi = word (zero-terminated in
; place), edi = rest of the line (leading spaces skipped).
next_word:
.skip:
    cmp byte [esi], ' '
    jne .start
    inc esi
    jmp .skip
.start:
    mov edi, esi
.w:
    cmp byte [edi], 0
    je .end
    cmp byte [edi], ' '
    je .cut
    inc edi
    jmp .w
.cut:
    mov byte [edi], 0
    inc edi
.sk2:
    cmp byte [edi], ' '
    jne .end
    inc edi
    jmp .sk2
.end:
    ret

; Prints "ok" or "error" from eax (0 / -1)
fs_report:
    mov esi, fs_ok
    test eax, eax
    jz .p
    mov esi, fs_err
.p:
    call puts
    ret

; Most commands need a mounted FS
fs_need:
    cmp byte [fs_mounted], 0
    jne .ok
    mov esi, fs_msg_nofs
    call puts
    stc
    ret
.ok:
    clc
    ret

; put <name> <text>: append text and a newline (creating the file)
cmd_put_run:
    call fs_need
    jc .r
    call next_word
    push edi
    mov ecx, O_CREATE|O_APPEND
    call fs_open
    pop esi
    cmp eax, -1
    je .err
    mov ebx, eax
    call strlen
    mov ecx, eax
    mov byte [esi+ecx], 10      ; the command line has room past the text
    inc ecx
    call fs_write
    mov edx, eax
    call fs_close
    mov eax, edx
    cmp eax, -1
    je .err
    xor eax, eax
.err:
    call fs_report
.r:
    ret

; mk <name>
cmd_mk_run:
    call fs_need
    jc .r
    call next_word
    call fs_create
    call fs_report
.r:
    ret

; rm <name>
cmd_rm_run:
    call fs_need
    jc .r
    call next_word
    call fs_delete
    call fs_report
.r:
    ret

; mv <old> <new>
cmd_mv_run:
    call fs_need
    jc .r
    call next_word
    push esi
    mov esi, edi
    call next_word
    mov edi, esi
    pop esi
    call fs_rename
    call fs_report
.r:
    ret

; format: wipe the data disk and reseed the built-in files
cmd_format_run:
    cmp dword [FS_DEV+DEV_SIZE], FS_DATA_LBA+2
    jb .nodisk
    call fs_format
    mov eax, 0
    jnc .rep
    mov eax, -1
.rep:
    call fs_report
    ret
.nodisk:
    mov esi, blk_nodisk
    call puts
    ret

; fstest: create, write across a sector boundary, grow, reopen, read back,
; rename, delete. Prints PASS/FAIL.
cmd_fstest_run:
    call fs_need
    jc .r
    mov dword [st_fail], 0
    mov esi, ft_a
    call fs_delete              ; leftovers from an earlier run
    mov esi, ft_b
    call fs_delete
    ; pattern buffer: 1300 bytes, byte i = i * 3
    mov edi, FT_BUF
    xor eax, eax
.fill:
    mov edx, eax
    imul edx, 3
    mov [edi+eax], dl
    inc eax
    cmp eax, FT_LEN
    jb .fill
    mov esi, ft_a
    mov ecx, O_CREATE
    call fs_open
    mov [ft_fd_tmp], eax
    cmp eax, -1
    je .fail
    ; write in two pieces: 700 + 600 (the second forces growth to 3 sectors)
    mov ebx, eax
    mov esi, FT_BUF
    mov ecx, 700
    call fs_write
    cmp eax, 700
    call st_check
    mov ebx, [ft_fd_tmp]
    mov esi, FT_BUF+700
    mov ecx, FT_LEN-700
    call fs_write
    cmp eax, FT_LEN-700
    call st_check
    mov ebx, [ft_fd_tmp]
    call fs_close
    ; read back after reopen
    mov esi, ft_a
    xor ecx, ecx
    call fs_open
    mov ebx, eax
    mov edi, FT_BUF2
    mov ecx, FT_LEN+50          ; ask for more than the file holds
    call fs_read
    cmp eax, FT_LEN
    call st_check
    push ebx
    mov esi, FT_BUF
    mov edi, FT_BUF2
    mov ecx, FT_LEN
    repe cmpsb
    pop ebx
    call st_check
    call fs_read                ; at EOF -> 0
    test eax, eax
    call st_check
    call fs_close
    ; rename, then the old name is gone and the new one has the data
    mov esi, ft_a
    mov edi, ft_b
    call fs_rename
    test eax, eax
    call st_check
    mov esi, ft_a
    call fs_lookup
    test edi, edi
    call st_check
    mov esi, ft_b
    call fs_lookup
    cmp dword [edi+DE_SIZE], FT_LEN
    call st_check
    ; delete
    mov esi, ft_b
    call fs_delete
    test eax, eax
    call st_check
    mov esi, ft_b
    call fs_lookup
    test edi, edi
    call st_check
    mov esi, ft_pass
    cmp dword [st_fail], 0
    je .out
.fail:
    mov esi, ft_failmsg
.out:
    call puts
.r:
    ret

FT_LEN  equ 1300
FT_BUF  equ KSCRATCH+0x2000
FT_BUF2 equ KSCRATCH+0x2800

fs_mounted db 0
fs_cat_last db 0
fs_total dd 0
fs_xfer_total dd 0
fs_xfer_lba dd 0
ft_fd_tmp dd 0
fs_fds times FS_MAXFD*4 dd 0
ft_a db 'fstest.a', 0
ft_b db 'fstest.b', 0
ft_pass db 'fstest: PASS', 10, 0
ft_failmsg db 'fstest: FAIL', 10, 0
fs_ok db 'ok', 10, 0
fs_err db 'error', 10, 0
fs_msg_formatted db 'Data disk was blank: formatted SQFS and added the built-in files.', 10, 0
fs_msg_foreign db 'Data disk is not SQFS; type format to erase it.', 10, 0
fs_msg_nofs db 'No file system mounted (attach a data disk).', 10, 0
