; Squirrel-OS/2 — installer steps I.1 to I.4: the target disk, its
; partition table, its file system, the system copied onto it, and the
; boot code
; Included from pm.asm. Original code.
;
;   install         list the disks and pick the target
;   install part    write an MBR with one Squirrel-OS/2 partition to the
;                   target, after a y/n question (I.1)
;   install format  format SQFS with an empty root in that partition,
;                   after a y/n question (I.2)
;   install ls      list the root of that file system (I.2)
;   install copy    copy the kernel and the data disk's root files (I.3)
;   install boot    write the boot code and mark the partition active (I.4)
;
; The target is the first disk that is present, is not the data disk
; (drive 1, which the file system mounts) and is not the disk the kernel
; was loaded from. The boot disk is recognised by its sector 1: it starts
; with the running kernel's first instructions (stage2 up to gdt, which
; nothing writes to), still in memory at 0x8000. Nothing is written
; before the question is answered with y.
; See documentation/guides/install.md.

INS_PART_LBA  equ 2048          ; the partition starts at 1 MiB
INS_MIN       equ INS_PART_LBA+2048 ; smallest target: 2 MiB
INS_PTYPE     equ 0x7F          ; MBR type for alternative-OS development
INS_DPSTART   equ DEV_DESC-4    ; dev_inst/dev_sys: the partition's first sector
INS_SIG       equ 440           ; disk signature in sector 0
INS_ENTRY     equ 446           ; first partition entry in sector 0
INS_HEADS     equ 255           ; CHS geometry for the table's CHS fields
INS_SPT       equ 63
INS_OUT       equ blk_buf_out   ; the sector being written (ata.asm)
INS_IN        equ blk_buf_in    ; a sector read back
INS_KSECTS    equ KERNEL_SIZE/SECTOR_SIZE ; the kernel image, from sector 1
INS_FILEMAX   equ 0x10000       ; largest file install copy takes (LD_STAGE)
INS_BOOTCMP   equ gdt-stage2    ; bytes of sector 1 compared with 0x8000
%if INS_BOOTCMP < 64 || INS_BOOTCMP > 512
%error the boot-disk check needs 64 to 512 bytes of code before gdt
%endif

; install: one line per disk, then the target
cmd_install_run:
    mov esi, ins_title
    call puts
    xor ebx, ebx
.d:
    mov esi, disk_label
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sep
    call puts
    mov eax, [ata_sectors+ebx*4]
    test eax, eax
    jnz .present
    mov esi, disk_none
    call puts
    jmp .next
.present:
    call ins_size
    call ins_kind               ; esi = what is on it
    call puts
.next:
    inc ebx
    cmp ebx, ATA_NDRIVES
    jb .d
    call ins_target
    jc .none
    mov esi, ins_msg_target
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_msg_next
    call puts
    ret
.none:
    mov esi, ins_msg_notarget
    call puts
    ret

; install part: the y/n question, then sector 0 of the target
cmd_install_part_run:
    call ins_target
    jc .none
    mov eax, [ata_sectors+ebx*4]
    cmp eax, INS_MIN
    jb .small
    mov esi, ins_ask1
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sep
    call puts
    call ins_size
    call ins_confirm
    jc .r
    call ins_do_part
    jc .fail
    mov esi, ins_msg_written
    call puts
    call ins_show_part
.r:
    ret
.fail:
    mov esi, ins_msg_fail
    call puts
    ret
.small:
    mov esi, ins_msg_small
    call puts
    ret
.none:
    mov esi, ins_msg_notarget
    call puts
    ret

; ebx = target: writes the MBR and reads it back into INS_IN. CF on error.
ins_do_part:
    pushad
    call ins_mbr
    mov esi, INS_OUT
    xor ecx, ecx
    call ata_write
    jc .fail
    mov edi, INS_IN
    push edi
    mov ecx, SECTOR_SIZE/4
    xor eax, eax
    rep stosd
    pop edi
    xor ecx, ecx
    call ata_read
    jc .fail
    mov esi, INS_OUT
    mov edi, INS_IN
    mov ecx, SECTOR_SIZE
    repe cmpsb
    jne .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; dev_inst set up (ins_open_part): SQFS with an empty root there. CF on error.
ins_do_format:
    call ins_fs_target
    call fs_format_empty
    pushfd
    call ins_fs_back
    popfd
    ret

; Prints "Everything on that disk is lost. Write it? (y/n)" and waits for
; a key. -> CF clear for y; otherwise CF set and "Nothing was written."
; Keeps ebx.
ins_confirm:
    mov esi, ins_ask2
; esi = the question, ending in (y/n): the same
ins_ask:
    call puts
    push ebx
    call kbd_getchar            ; (does not keep ebx)
    pop ebx
    cmp al, ' '
    jb .noecho
    call putc
.noecho:
    or al, 0x20                 ; Y -> y
    cmp al, 'y'
    je .yes
    mov esi, ins_msg_kept
    call puts
    stc
    ret
.yes:
    mov al, 10
    call putc
    clc
    ret

; install format (I.2): SQFS with an empty root inside partition 1
cmd_install_format_run:
    call ins_target
    jc ins_say_notarget
    call ins_open_part
    jc ins_say_nopart
    mov esi, ins_ask_fmt
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sep
    call puts
    mov eax, [dev_inst+DEV_SIZE]
    call ins_print_size
    call ins_confirm
    jc .r
    call ins_do_format
    mov esi, ins_msg_fmtfail
    jc .say
    mov esi, ins_msg_formatted
.say:
    call puts
.r:
    ret

; install ls (I.2): the root of the file system in partition 1
cmd_install_ls_run:
    call ins_target
    jc ins_say_notarget
    call ins_open_part
    jc ins_say_nopart
    call ins_mount_target
    jc .nofs
    xor dl, dl
    call fs_list_dir
    ; count what is in the root
    xor eax, eax
    mov ebx, FS_DIR
    mov ecx, FS_MAXFILES
.c:
    cmp byte [ebx], 0
    je .n
    cmp byte [ebx+DE_PARENT], 0
    jne .n
    inc eax
.n:
    add ebx, FS_DIRENT
    loop .c
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_msg_inroot
    call puts
    jmp ins_fs_back
.nofs:
    mov esi, ins_msg_nofs
    jmp puts

; install copy (I.3): the kernel from the boot disk to sectors 1 to
; INS_KSECTS of the target, then every file in the root of the data disk
; into the root of the target's file system
cmd_install_copy_run:
    call ins_target
    jc ins_say_notarget
    mov [ins_tgt], ebx
    call ins_open_part
    jc ins_say_nopart
    call ins_mount_target       ; is there a file system to copy into?
    jc .nofs
    call ins_fs_back
    cmp byte [fs_mounted], 0
    je .nodata
    call ins_find_boot          ; where the kernel is read from
    jnc .bfound
    mov esi, ins_msg_noboot
    jmp puts
.bfound:
    mov [ins_src], ebx
    mov ebx, [ins_tgt]
    mov esi, ins_ask_copy
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_ask_copy2
    call ins_ask
    jc .r
    call ins_do_kernel
    jc .kfail
    mov esi, ins_msg_kcopied
    call puts
    call ins_do_files
    mov eax, [ins_ncopied]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_msg_copied
    jmp puts
.kfail:
    mov esi, ins_msg_kfail
    jmp puts
.nofs:
    mov esi, ins_msg_nofs
    jmp puts
.nodata:
    mov esi, blk_nodisk
    jmp puts
.r:
    ret

; Sectors 1 to INS_KSECTS from [ins_src] to [ins_tgt], each read back.
; CF on error.
ins_do_kernel:
    pushad
    mov ecx, 1
.k:
    mov ebx, [ins_src]
    mov edi, INS_IN
    call ata_read
    jc .fail
    mov ebx, [ins_tgt]
    mov esi, INS_IN
    call ata_write
    jc .fail
    mov edi, INS_OUT
    call ata_read
    jc .fail
    push ecx
    mov esi, INS_IN
    mov edi, INS_OUT
    mov ecx, SECTOR_SIZE
    repe cmpsb
    pop ecx
    jne .fail
    inc ecx
    cmp ecx, INS_KSECTS
    jbe .k
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Every file in the root of the mounted file system to the root of the
; target's (dev_inst). One line per file unless ins_quiet. ins_ncopied =
; how many; CF when one failed.
ins_do_files:
    pushad
    mov byte [ins_ffailed], 0
    ; the names, before switching
    mov edi, ins_names
    xor edx, edx                ; how many
    mov ebx, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [ebx], 0
    je .ln
    cmp byte [ebx+DE_PARENT], 0
    jne .ln
    cmp byte [ebx+DE_KIND], DK_FILE
    jne .ln
    push ecx
    mov esi, ebx
    mov ecx, FS_NAMELEN/4
    rep movsd
    pop ecx
    mov eax, [ebx+DE_SIZE]
    stosd
    inc edx
.ln:
    add ebx, FS_DIRENT
    loop .l
    mov [ins_nfiles], edx
    mov dword [ins_ncopied], 0
    mov ebp, ins_names
.f:
    cmp dword [ins_nfiles], 0
    je .done
    dec dword [ins_nfiles]
    mov esi, ebp
    call ins_say
    cmp dword [ebp+FS_NAMELEN], INS_FILEMAX
    ja .big
    call ins_copy_file
    mov esi, ins_msg_ffail
    jc .bad
    inc dword [ins_ncopied]
    mov esi, ins_msg_fok
.say:
    call ins_say
    add ebp, FS_NAMELEN+4
    jmp .f
.bad:
    mov byte [ins_ffailed], 1
    jmp .say
.big:
    mov esi, ins_msg_fbig
    jmp .say
.done:
    popad
    cmp byte [ins_ffailed], 1
    cmc                         ; CF = a file failed
    ret

; esi = text: puts unless ins_quiet
ins_say:
    cmp byte [ins_quiet], 0
    jne .r
    call puts
.r:
    ret

; ebp = a name in ins_names: reads that file from the data disk's root
; into LD_STAGE and writes it to the target's root. CF on error. The data
; disk is the file system again afterwards.
ins_copy_file:
    pushad
    mov edi, ins_path           ; "/name": the root, whatever cd says
    mov byte [edi], '/'
    inc edi
    mov esi, ebp
    mov ecx, FS_NAMELEN
    rep movsb
    mov esi, ins_path
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov edi, LD_STAGE
    mov ecx, INS_FILEMAX
    call fs_read
    mov [ins_fsize], eax
    call fs_close
    cmp dword [ins_fsize], -1
    je .fail
    call ins_mount_target
    jc .fail
    mov esi, ins_path
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .back
    mov ebx, eax
    mov esi, LD_STAGE
    mov ecx, [ins_fsize]
    call fs_write
    push eax
    call fs_close
    pop eax
    cmp eax, [ins_fsize]
    jne .back
    call ins_fs_back
    popad
    clc
    ret
.back:
    call ins_fs_back
.fail:
    popad
    stc
    ret

; install boot (I.4): the boot code from the boot disk's sector 0 into
; the target's, keeping its signature and table, and partition 1 active
cmd_install_boot_run:
    call ins_target
    jc ins_say_notarget
    mov [ins_tgt], ebx
    call ins_open_part
    jc ins_say_nopart
    ; the kernel must be there (I.3): its sector 1 is the running kernel's
    mov edi, INS_IN
    mov ecx, 1
    call ata_read
    jc .nokernel
    mov esi, stage2
    mov edi, INS_IN
    mov ecx, INS_BOOTCMP
    repe cmpsb
    jne .nokernel
    call ins_find_boot
    jc .noboot
    mov [ins_src], ebx
    mov ebx, [ins_tgt]
    mov esi, ins_ask_boot
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_ask_boot2
    call ins_ask
    jc .r
    call ins_do_boot
    jc .fail
    mov esi, ins_msg_booted
    jmp puts
.nokernel:
    mov esi, ins_msg_nokernel
    jmp puts
.noboot:
    mov esi, ins_msg_noboot
    jmp puts
.fail:
    mov esi, ins_msg_bfail
    jmp puts
.r:
    ret

; The boot code of [ins_src]'s sector 0 over [ins_tgt]'s, keeping its
; signature and table, partition 1 active, read back. CF on error.
ins_do_boot:
    pushad
    mov ebx, [ins_tgt]
    mov edi, INS_OUT
    xor ecx, ecx
    call ata_read
    jc .fail
    mov ebx, [ins_src]
    mov edi, INS_IN
    call ata_read
    jc .fail
    mov esi, INS_IN
    mov edi, INS_OUT
    mov ecx, INS_SIG
    rep movsb
    mov byte [INS_OUT+INS_ENTRY], 0x80  ; active: the BIOS boots it
    mov ebx, [ins_tgt]
    mov esi, INS_OUT
    xor ecx, ecx
    call ata_write
    jc .fail
    mov edi, INS_IN
    call ata_read
    jc .fail
    mov esi, INS_OUT
    mov edi, INS_IN
    mov ecx, SECTOR_SIZE
    repe cmpsb
    jne .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; -> ebx = the boot disk (an IDE disk that holds the running kernel), or CF
ins_find_boot:
    xor ebx, ebx
.b:
    cmp dword [ata_sectors+ebx*4], INS_KSECTS+1
    jb .n
    call ins_is_boot
    jnc .r
.n:
    inc ebx
    cmp ebx, ATA_NDRIVES
    jb .b
    stc
.r:
    ret

; At boot, after fs_mount_boot: with no data disk at all, a boot disk with
; a Squirrel-OS/2 partition holding SQFS (an installed system, I.4) gives
; the file system, through dev_sys.
ins_mount_system:
    pushad
    cmp byte [fs_mounted], 0
    jne .r
    cmp dword [FS_DEV+DEV_SIZE], 0
    jne .r                      ; a data disk is attached: it decides
    call ins_find_boot
    jc .r
    push ebx
    call ins_open_part          ; fills dev_inst; copy it to dev_sys
    pop ebx
    jc .r
    mov esi, dev_inst
    mov edi, dev_sys+DEV_TYPE
    add esi, DEV_TYPE
    mov ecx, (DEV_DESC-DEV_TYPE)/4
    rep movsd
    mov ebx, dev_sys
    xor ecx, ecx
    mov edi, FS_SB
    call dev_bread
    jc .r
    cmp dword [FS_SB+SB_MAGIC], FS_MAGIC
    jne .r
    mov dword [fs_dev], dev_sys
    call fs_load
    jnc .ok
    mov dword [fs_dev], FS_DEV
    jmp .r
.ok:
    mov esi, ins_msg_sysfs
    call puts
.r:
    popad
    ret

; run install (I.5): the whole installation in one go, with one question
; first. Its text follows lang (localization/*/strings.txt, inst_*).
run_install:
    call cls
    mov esi, [lstr+LS_INST_TITLE*4]
    call lputs_nl
    mov al, 10
    call putc
    call ins_target
    jc .notarget
    cmp dword [ata_sectors+ebx*4], INS_MIN
    jb .notarget
    mov [ins_tgt], ebx
    call ins_find_boot
    jc .noboot
    mov [ins_src], ebx
    cmp byte [fs_mounted], 0
    je .nofs
    ; "Target disk: 2 (16 MiB)"
    mov esi, [lstr+LS_INST_TARGET*4]
    call puts
    mov al, ' '
    call putc
    mov eax, [ins_tgt]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_paren
    call puts
    mov ebx, [ins_tgt]
    mov eax, [ata_sectors+ebx*4]
    shr eax, 11
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_mibp
    call puts
    mov esi, [lstr+LS_INST_ERASE*4]
    call lputs_nl
    mov esi, [lstr+LS_INST_CONFIRM*4]
    call lputs_nl
.key:
    call fb_waitkey
    cmp al, 0x01                ; Esc
    je .cancel
    cmp al, 0x1C                ; Enter
    jne .key
    mov byte [ins_quiet], 1
    mov al, 10
    call putc
    mov esi, [lstr+LS_INST_PART*4]
    call ins_step
    mov ebx, [ins_tgt]
    call ins_do_part
    call ins_result
    jc .failed
    mov esi, [lstr+LS_INST_FORMAT*4]
    call ins_step
    mov ebx, [ins_tgt]
    call ins_open_part
    jc .sfail
    call ins_do_format
    call ins_result
    jc .failed
    mov esi, [lstr+LS_INST_COPY*4]
    call ins_step
    call ins_do_kernel
    jc .sfail
    call ins_do_files
    call ins_result
    jc .failed
    mov esi, [lstr+LS_INST_BOOT*4]
    call ins_step
    call ins_do_boot
    call ins_result
    jc .failed
    mov esi, [lstr+LS_INST_DONE*4]
    jmp .end
.sfail:
    stc
    call ins_result
.failed:
    mov esi, [lstr+LS_INST_FAILED*4]
    jmp .end
.cancel:
    mov esi, [lstr+LS_INST_CANCEL*4]
    jmp .end
.notarget:
    mov esi, [lstr+LS_INST_NOTARGET*4]
    jmp .end
.noboot:
    mov esi, [lstr+LS_INST_NOBOOT*4]
    jmp .end
.nofs:
    mov esi, [lstr+LS_FE_NOFS*4]
.end:
    mov byte [ins_quiet], 0
    call lputs_nl
    mov esi, [lstr+LS_INST_ANYKEY*4]
    call lputs_nl
    call fb_waitkey
    ret

; esi = a step's name: prints it and " ... "
ins_step:
    call puts
    mov esi, ins_dots
    jmp puts

; CF from the step: prints done or failed and a newline, keeping CF
ins_result:
    pushfd
    mov esi, [lstr+LS_INST_OK*4]
    jnc .p
    mov esi, [lstr+LS_INST_FAIL*4]
.p:
    call lputs_nl
    popfd
    ret

; Points the file system at the target partition and loads it, at its
; root. CF (and the data disk again) when the partition has no SQFS.
ins_mount_target:
    call ins_fs_target
    pushad
    mov ebx, dev_inst
    xor ecx, ecx
    mov edi, FS_SB
    call dev_bread
    jc .no
    cmp dword [FS_SB+SB_MAGIC], FS_MAGIC
    jne .no
    call fs_load
    jc .no
    mov byte [fs_cwd], 0
    popad
    clc
    ret
.no:
    popad
    call ins_fs_back
    stc
    ret

ins_say_notarget:
    mov esi, ins_msg_notarget
    jmp puts
ins_say_nopart:
    mov esi, ins_msg_nopart
    jmp puts

; ebx = target drive: reads its sector 0 and, when partition 1 is a
; Squirrel-OS/2 partition inside the disk, sets up dev_inst to reach it.
; CF when there is none. Keeps ebx.
ins_open_part:
    pushad
    mov edi, INS_IN
    xor ecx, ecx
    call ata_read
    jc .no
    cmp word [INS_IN+510], 0xAA55
    jne .no
    cmp byte [INS_IN+INS_ENTRY+4], INS_PTYPE
    jne .no
    mov eax, [INS_IN+INS_ENTRY+8]   ; start
    mov edx, [INS_IN+INS_ENTRY+12]  ; size
    cmp edx, FS_DATA_LBA+2
    jb .no
    test eax, eax
    jz .no                      ; never over the MBR
    mov ecx, eax
    add ecx, edx
    jc .no
    cmp ecx, [ata_sectors+ebx*4]
    ja .no
    mov [dev_inst+INS_DPSTART], eax
    mov [dev_inst+DEV_SIZE], edx
    mov [dev_inst+DEV_UNIT], ebx
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; Points the file system at dev_inst, keeping what it had for ins_fs_back.
ins_fs_target:
    pushad
    mov al, [fs_mounted]
    mov [ins_was_mounted], al
    mov al, [fs_cwd]
    mov [ins_was_cwd], al
    mov esi, fs_fds
    mov edi, ins_was_fds
    mov ecx, FS_MAXFD
    rep movsd
    mov eax, [fs_dev]
    mov [ins_was_dev], eax
    mov dword [fs_dev], dev_inst
    mov byte [fs_mounted], 0
    popad
    ret

; Points the file system back at the device it had (the data disk, or
; dev_sys on an installed system) and loads it again.
ins_fs_back:
    pushad
    mov ebx, [ins_was_dev]
    mov [fs_dev], ebx
    mov byte [fs_mounted], 0
    cmp byte [ins_was_mounted], 0
    je .r
    xor ecx, ecx
    mov edi, FS_SB
    call dev_bread
    jc .r
    call fs_load
    jc .r
    mov al, [ins_was_cwd]
    mov [fs_cwd], al
    mov esi, ins_was_fds
    mov edi, fs_fds
    mov ecx, FS_MAXFD
    rep movsd
.r:
    popad
    ret

; dev_inst operations: sectors of partition 1 of the target.
; ebx = dev_inst, ecx = sector in the partition -> CF on error
ins_inst_read:
    cmp ecx, [ebx+DEV_SIZE]
    jae .bad
    push ebx
    push ecx
    add ecx, [ebx+INS_DPSTART]
    mov ebx, [ebx+DEV_UNIT]
    call ata_read
    pop ecx
    pop ebx
    ret
.bad:
    stc
    ret

ins_inst_write:
    cmp ecx, [ebx+DEV_SIZE]
    jae .bad
    push ebx
    push ecx
    add ecx, [ebx+INS_DPSTART]
    mov ebx, [ebx+DEV_UNIT]
    call ata_write
    pop ecx
    pop ebx
    ret
.bad:
    stc
    ret

; -> ebx = target drive, or CF when there is none
ins_target:
    xor ebx, ebx
.d:
    cmp dword [ata_sectors+ebx*4], 0
    je .next
    cmp ebx, 1                  ; the data disk
    je .next
    call ins_is_boot
    jc .found                   ; CF: not the boot disk
.next:
    inc ebx
    cmp ebx, ATA_NDRIVES
    jb .d
    stc
    ret
.found:
    clc
    ret

; ebx = drive -> CF clear when it is the boot disk (its sector 1 starts
; with the running kernel's code, and the end of its sector 0 matches the
; boot sector in memory). A disk that cannot be read counts
; as the boot disk, so it is never picked.
ins_is_boot:
    pushad
    mov edi, INS_IN
    mov ecx, 1
    call ata_read
    jc .yes
    mov esi, stage2
    mov edi, INS_IN
    mov ecx, INS_BOOTCMP
    repe cmpsb
    jne .no
    ; and its sector 0 ends like the boot sector still in memory at 0x7C00:
    ; the same disk signature and partition table (none on a release
    ; image). A target that holds a copy of the kernel (I.3) differs here.
    mov edi, INS_IN
    xor ecx, ecx
    call ata_read
    jc .yes
    mov esi, 0x7C00+INS_SIG
    mov edi, INS_IN+INS_SIG
    mov ecx, SECTOR_SIZE-INS_SIG
    repe cmpsb
    jne .no
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ebx = drive (present) -> esi = a line saying what it is; reads sector 0
ins_kind:
    mov esi, ins_k_data
    cmp ebx, 1
    je .r
    mov esi, ins_k_boot
    call ins_is_boot
    jnc .r
    push ebx
    mov edi, INS_IN
    xor ecx, ecx
    call ata_read
    pop ebx
    mov esi, ins_k_unread
    jc .r
    mov esi, INS_IN
    mov ecx, SECTOR_SIZE/4
.z:
    lodsd
    test eax, eax
    jnz .used
    loop .z
    mov esi, ins_k_blank
.r:
    ret
.used:
    mov esi, ins_k_used
    cmp word [INS_IN+510], 0xAA55
    jne .r
    cmp byte [INS_IN+INS_ENTRY+4], INS_PTYPE
    jne .r
    mov esi, ins_k_ours
    ret

; ebx = drive: prints "N sectors (M MiB)  "
ins_size:
    mov eax, [ata_sectors+ebx*4]
; eax = sectors: the same
ins_print_size:
    push eax
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sectors
    call puts
    pop eax
    shr eax, 11
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_mib
    jmp puts

; ebx = drive: builds sector 0 in INS_OUT. No boot code yet (I.4), one
; partition from INS_PART_LBA to the end of the disk, not active.
ins_mbr:
    pushad
    mov edi, INS_OUT
    mov ecx, SECTOR_SIZE/4
    xor eax, eax
    rep stosd
    mov eax, [ticks]            ; disk signature: any value but 0
    or eax, 0x53510000
    mov [INS_OUT+INS_SIG], eax
    mov edi, INS_OUT+INS_ENTRY
    mov eax, INS_PART_LBA
    lea edx, [edi+1]
    call ins_chs
    mov byte [edi+4], INS_PTYPE
    mov eax, [ata_sectors+ebx*4]
    dec eax                     ; last sector of the disk
    lea edx, [edi+5]
    call ins_chs
    mov dword [edi+8], INS_PART_LBA
    mov eax, [ata_sectors+ebx*4]
    sub eax, INS_PART_LBA
    mov [edi+12], eax
    mov word [INS_OUT+510], 0xAA55
    popad
    ret

; eax = LBA, edx = where the 3 CHS bytes go (head, sector, cylinder).
; Past cylinder 1023 the bytes are FE FF FF, as tools expect.
ins_chs:
    push eax
    push ebx
    push ecx
    push edx
    mov ecx, edx
    xor edx, edx
    mov ebx, INS_HEADS*INS_SPT
    div ebx                     ; eax = cylinder, edx = LBA within it
    cmp eax, 1023
    ja .big
    push eax
    mov eax, edx
    xor edx, edx
    mov ebx, INS_SPT
    div ebx                     ; eax = head, edx = sector - 1
    mov [ecx], al
    inc edx
    pop eax
    mov [ecx+2], al             ; cylinder bits 0-7
    shr eax, 2
    and al, 0xC0                ; cylinder bits 8-9 in bits 6-7
    or al, dl
    mov [ecx+1], al
    jmp .r
.big:
    mov byte [ecx], 0xFE
    mov word [ecx+1], 0xFFFF
.r:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; prints the first partition entry of the sector in INS_IN
ins_show_part:
    mov esi, ins_msg_part
    call puts
    mov eax, [INS_IN+INS_ENTRY+8]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_msg_psize
    call puts
    mov eax, [INS_IN+INS_ENTRY+12]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sectors
    call puts
    mov eax, [INS_IN+INS_ENTRY+12]
    shr eax, 11
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_mib
    call puts
    ret

; the target partition as a block device. It is not in the device table,
; so programs cannot find it; only the file system uses it, through fs_dev.
align 4
dev_inst:
    db 'inst', 0, 0, 0, 0
    dd DEV_BLOCK, dev_probe_yes, ins_inst_read, ins_inst_write, 0, DEVF_UP, 0, 0
; the same for partition 1 of the boot disk, when the system runs from an
; installed disk (I.4): the file system there, for good
dev_sys:
    db 'sys', 0, 0, 0, 0, 0
    dd DEV_BLOCK, dev_probe_yes, ins_inst_read, ins_inst_write, 0, DEVF_UP, 0, 0
ins_was_dev dd FS_DEV
ins_tgt dd 0
ins_src dd 0
ins_nfiles dd 0
ins_ncopied dd 0
ins_fsize dd 0
ins_quiet db 0
ins_ffailed db 0
ins_names times FS_MAXFILES*(FS_NAMELEN+4) db 0 ; name, then size
ins_path times FS_NAMELEN+2 db 0
ins_was_fds times FS_MAXFD dd 0
ins_was_mounted db 0
ins_was_cwd db 0

ins_paren db ' (', 0
ins_mibp db ' MiB)', 10, 0
ins_dots db ' ... ', 0
cmd_install db 'install', 0
cmd_install_part db 'install part', 0
cmd_install_format db 'install format', 0
cmd_install_ls db 'install ls', 0
cmd_install_copy db 'install copy', 0
cmd_install_boot db 'install boot', 0
ins_title db 'Installer: the target disk', 10, 0
ins_mib db ' MiB)  ', 0
ins_k_boot db 'boot disk, not touched', 10, 0
ins_k_data db 'data disk, not touched', 10, 0
ins_k_blank db 'blank', 10, 0
ins_k_used db 'not blank', 10, 0
ins_k_ours db 'has a Squirrel-OS/2 partition', 10, 0
ins_k_unread db 'cannot be read', 10, 0
ins_msg_target db 'Target: disk ', 0
ins_msg_next db '. Steps: install part, install format, install copy, install boot.', 10, 0
ins_msg_notarget db 'No target disk. Attach one as secondary master or slave.', 10, 0
ins_msg_small db 'The target disk is smaller than 2 MiB.', 10, 0
ins_ask1 db 'Write a new partition table to disk ', 0
ins_ask2 db 10, 'Everything on that disk is lost. Write it? (y/n) ', 0
ins_msg_kept db 10, 'Nothing was written.', 10, 0
ins_msg_written db 'Partition table written and read back.', 10, 0
ins_msg_fail db 'Write failed: the table did not read back.', 10, 0
ins_msg_part db 'Partition 1: type 7F, start ', 0
ins_msg_nopart db 'The target has no Squirrel-OS/2 partition. Type install part first.', 10, 0
ins_ask_fmt db 'Format partition 1 of disk ', 0
ins_msg_formatted db 'Formatted SQFS with an empty root. Type install ls to see it.', 10, 0
ins_msg_fmtfail db 'Format failed.', 10, 0
ins_msg_nofs db 'Partition 1 has no SQFS. Type install format.', 10, 0
ins_ask_copy db 'Copy the kernel and the files in the root of the data disk to disk ', 0
ins_msg_noboot db 'The boot disk is not an IDE disk, so the kernel cannot be read back.', 10, 0
ins_ask_copy2 db '?', 10, 'Files with the same names there are replaced. Copy? (y/n) ', 0
ins_msg_kcopied db 'Kernel copied and read back.', 10, 0
ins_msg_kfail db 'Copying the kernel failed.', 10, 0
ins_msg_fok db ' copied', 10, 0
ins_msg_ffail db ' failed', 10, 0
ins_msg_fbig db ' skipped: larger than 64 KB', 10, 0
ins_msg_copied db ' files copied.', 10, 0
ins_ask_boot db 'Write the boot code to disk ', 0
ins_ask_boot2 db ' and mark partition 1 active?', 10, 'The PC can then boot from that disk. Write it? (y/n) ', 0
ins_msg_booted db 'Boot code written and read back; partition 1 is active.', 10, 'The disk now boots on its own.', 10, 0
ins_msg_nokernel db 'The target has no kernel yet. Type install copy first.', 10, 0
ins_msg_bfail db 'Writing the boot code failed.', 10, 0
ins_msg_sysfs db 'File system: partition 1 of the boot disk (an installed system).', 10, 0
ins_msg_inroot db ' entries in the root of partition 1.', 10, 0
ins_msg_psize db ', ', 0
