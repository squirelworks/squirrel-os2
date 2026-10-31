; Squirrel-OS/2 — installer, step I.1: the target disk and its partition table
; Included from pm.asm. Original code.
;
;   install        list the disks and pick the target
;   install part   write an MBR with one Squirrel-OS/2 partition to the
;                  target, after a y/n question
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
INS_ENTRY     equ 446           ; first partition entry in sector 0
INS_HEADS     equ 255           ; CHS geometry for the table's CHS fields
INS_SPT       equ 63
INS_OUT       equ blk_buf_out   ; the sector being written (ata.asm)
INS_IN        equ blk_buf_in    ; a sector read back
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
    mov esi, ins_ask2
    call puts
    push ebx
    call kbd_getchar            ; (does not keep ebx)
    pop ebx
    cmp al, ' '
    jb .noecho
    call putc
.noecho:
    cmp al, 'y'
    je .yes
    cmp al, 'Y'
    je .yes
    mov esi, ins_msg_kept
    call puts
    ret
.yes:
    mov al, 10
    call putc
    call ins_mbr
    mov esi, INS_OUT
    xor ecx, ecx
    call ata_write
    jc .fail
    ; read the table back from the disk and show it
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
    mov esi, ins_msg_written
    call puts
    call ins_show_part
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
; with the running kernel's code). A disk that cannot be read counts
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
    push ebx
    mov eax, [ata_sectors+ebx*4]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sectors
    call puts
    pop ebx
    push ebx
    mov eax, [ata_sectors+ebx*4]
    shr eax, 11
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ins_mib
    call puts
    pop ebx
    ret

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
    mov [INS_OUT+440], eax
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

cmd_install db 'install', 0
cmd_install_part db 'install part', 0
ins_title db 'Installer step I.1: the target disk', 10, 0
ins_mib db ' MiB)  ', 0
ins_k_boot db 'boot disk, not touched', 10, 0
ins_k_data db 'data disk, not touched', 10, 0
ins_k_blank db 'blank', 10, 0
ins_k_used db 'not blank', 10, 0
ins_k_ours db 'has a Squirrel-OS/2 partition', 10, 0
ins_k_unread db 'cannot be read', 10, 0
ins_msg_target db 'Target: disk ', 0
ins_msg_next db '. Type install part to write its partition table.', 10, 0
ins_msg_notarget db 'No target disk. Attach one as secondary master or slave.', 10, 0
ins_msg_small db 'The target disk is smaller than 2 MiB.', 10, 0
ins_ask1 db 'Write a new partition table to disk ', 0
ins_ask2 db 10, 'Everything on that disk is lost. Write it? (y/n) ', 0
ins_msg_kept db 10, 'Nothing was written.', 10, 0
ins_msg_written db 'Partition table written and read back.', 10, 0
ins_msg_fail db 'Write failed: the table did not read back.', 10, 0
ins_msg_part db 'Partition 1: type 7F, start ', 0
ins_msg_psize db ', ', 0
