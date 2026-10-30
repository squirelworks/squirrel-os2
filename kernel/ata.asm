; Squirrel-OS/2 — ATA PIO block device driver (0.2.0)
; Included from pm.asm. Original code.
;
; Primary channel only, LBA28, one 512-byte sector per call, polled.
; Drive 0 = primary master (boot disk), drive 1 = primary slave (data disk).
; See documentation/kernel/block-device.md.

ATA_DATA     equ 0x1F0
ATA_ERROR    equ 0x1F1
ATA_COUNT    equ 0x1F2
ATA_LBA0     equ 0x1F3
ATA_LBA1     equ 0x1F4
ATA_LBA2     equ 0x1F5
ATA_DRIVE    equ 0x1F6
ATA_STATUS   equ 0x1F7          ; read
ATA_COMMAND  equ 0x1F7          ; write
ATA_ALTSTAT  equ 0x3F6

ATA_SR_ERR   equ 0x01
ATA_SR_DRQ   equ 0x08
ATA_SR_DF    equ 0x20
ATA_SR_BSY   equ 0x80

ATA_CMD_READ     equ 0x20
ATA_CMD_WRITE    equ 0x30
ATA_CMD_FLUSH    equ 0xE7
ATA_CMD_IDENTIFY equ 0xEC

ATA_TIMEOUT  equ 0x100000       ; polling iterations before giving up

SECTOR_SIZE  equ 512

; scratch buffers live in the kernel scratch area, outside the image
ata_idbuf    equ KSCRATCH
blk_buf_out  equ KSCRATCH+0x200
blk_buf_in   equ KSCRATCH+0x400

; Probes both drives on the primary channel and records their size.
ata_init:
    mov dword [ata_sectors], 0
    mov dword [ata_sectors+4], 0
    xor ebx, ebx
    call ata_identify
    mov ebx, 1
    call ata_identify
    ret

; ebx = drive (0/1). Fills ata_sectors[drive] with the LBA28 sector
; count, or leaves 0 when there is no ATA disk (absent, or ATAPI).
ata_identify:
    pushad
    mov al, bl
    shl al, 4
    or al, 0xA0
    mov dx, ATA_DRIVE
    out dx, al
    call ata_delay
    xor al, al
    mov dx, ATA_COUNT
    out dx, al
    mov dx, ATA_LBA0
    out dx, al
    mov dx, ATA_LBA1
    out dx, al
    mov dx, ATA_LBA2
    out dx, al
    mov al, ATA_CMD_IDENTIFY
    mov dx, ATA_COMMAND
    out dx, al
    mov dx, ATA_STATUS
    in al, dx
    test al, al
    jz .none                    ; floating bus: nothing attached
    cmp al, 0xFF
    je .none
    call ata_wait_bsy
    jc .none
    mov dx, ATA_LBA1            ; ATAPI/SATA signatures are not plain disks
    in al, dx
    mov ah, al
    mov dx, ATA_LBA2
    in al, dx
    or al, ah
    jnz .none
    call ata_wait_drq
    jc .none
    mov edi, ata_idbuf
    mov ecx, 256
    mov dx, ATA_DATA
    rep insw
    mov eax, [ata_idbuf+60*2]   ; words 60-61: LBA28 sector count
    mov [ata_sectors+ebx*4], eax
.none:
    popad
    ret

; ebx = drive, ecx = LBA, edi = 512-byte buffer -> CF set on error
ata_read:
    pushad
    mov al, ATA_CMD_READ
    call ata_setup
    jc .fail
    call ata_wait_drq
    jc .fail
    mov ecx, 256
    mov dx, ATA_DATA
    rep insw
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ebx = drive, ecx = LBA, esi = 512-byte buffer -> CF set on error
ata_write:
    pushad
    mov al, ATA_CMD_WRITE
    call ata_setup
    jc .fail
    call ata_wait_drq
    jc .fail
    mov ecx, 256
    mov dx, ATA_DATA
.w:
    lodsw                       ; outsw is too fast for some controllers
    out dx, ax
    loop .w
    mov al, ATA_CMD_FLUSH
    mov dx, ATA_COMMAND
    out dx, al
    call ata_wait_bsy
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; al = command, ebx = drive, ecx = LBA. Checks the drive exists and the
; LBA is in range, selects it and issues the command. CF set on error.
ata_setup:
    cmp ebx, 1
    ja .bad
    cmp ecx, [ata_sectors+ebx*4]
    jae .bad                    ; also rejects an absent drive (0 sectors)
    push eax
    call ata_wait_bsy
    jc .busy
    mov eax, ecx
    shr eax, 24
    and al, 0x0F
    or al, 0xE0                 ; LBA mode
    mov ah, bl
    shl ah, 4
    or al, ah
    mov dx, ATA_DRIVE
    out dx, al
    call ata_delay
    mov al, 1
    mov dx, ATA_COUNT
    out dx, al
    mov eax, ecx
    mov dx, ATA_LBA0
    out dx, al
    shr eax, 8
    mov dx, ATA_LBA1
    out dx, al
    shr eax, 8
    mov dx, ATA_LBA2
    out dx, al
    pop eax
    mov dx, ATA_COMMAND
    out dx, al
    clc
    ret
.busy:
    pop eax
.bad:
    stc
    ret

; Waits for BSY to clear. CF set on timeout or error/fault.
ata_wait_bsy:
    push ecx
    push edx
    mov ecx, ATA_TIMEOUT
    mov dx, ATA_STATUS
.l:
    in al, dx
    test al, ATA_SR_BSY
    jz .done
    loop .l
    jmp .err
.done:
    test al, ATA_SR_ERR|ATA_SR_DF
    jnz .err
    pop edx
    pop ecx
    clc
    ret
.err:
    pop edx
    pop ecx
    stc
    ret

; Waits for BSY clear and DRQ set. CF set on timeout or error.
ata_wait_drq:
    push ecx
    push edx
    mov ecx, ATA_TIMEOUT
    mov dx, ATA_STATUS
.l:
    in al, dx
    test al, ATA_SR_ERR|ATA_SR_DF
    jnz .err
    test al, ATA_SR_BSY
    jnz .next
    test al, ATA_SR_DRQ
    jnz .ok
.next:
    loop .l
.err:
    pop edx
    pop ecx
    stc
    ret
.ok:
    pop edx
    pop ecx
    clc
    ret

; ~400 ns settle after drive select: four reads of the alt status port
ata_delay:
    push eax
    push edx
    mov dx, ATA_ALTSTAT
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    pop edx
    pop eax
    ret

; ---------- shell commands ----------
; disk: show the detected drives
cmd_disk_run:
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
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_sectors
    call puts
    mov eax, [ata_sectors+ebx*4]
    shr eax, 11                 ; sectors -> MiB
    call itoa
    mov esi, num_buf
    call puts
    mov esi, disk_mib
    call puts
.next:
    inc ebx
    cmp ebx, 2
    jb .d
    ret

; blktest: write a pattern to the last sector of the data disk, read it
; back into a cleared buffer and compare.
cmd_blktest_run:
    mov ebx, 1
    mov ecx, [ata_sectors+4]
    test ecx, ecx
    jz .nodisk
    dec ecx
    ; pattern: byte i = (i * 7 + ticks) & 0xFF, so each run differs
    mov edi, blk_buf_out
    xor eax, eax
    mov edx, [ticks]
.fill:
    mov [edi+eax], dl
    add edx, 7
    inc eax
    cmp eax, SECTOR_SIZE
    jb .fill
    mov esi, blk_buf_out
    call ata_write
    jc .fail
    mov edi, blk_buf_in
    push ecx
    mov ecx, SECTOR_SIZE/4
    xor eax, eax
    rep stosd
    pop ecx
    mov edi, blk_buf_in
    call ata_read
    jc .fail
    mov esi, blk_buf_out
    mov edi, blk_buf_in
    push ecx
    mov ecx, SECTOR_SIZE
    repe cmpsb
    pop ecx
    jne .fail
    mov esi, blk_pass
    call puts
    ret
.fail:
    mov esi, blk_fail
    call puts
    ret
.nodisk:
    mov esi, blk_nodisk
    call puts
    ret

ata_sectors dd 0, 0
disk_label db 'disk ', 0
disk_sep db ': ', 0
disk_none db 'none', 10, 0
disk_sectors db ' sectors (', 0
disk_mib db ' MiB)', 10, 0
blk_pass db 'blktest: PASS', 10, 0
blk_fail db 'blktest: FAIL', 10, 0
blk_nodisk db 'blktest: no data disk (attach one as primary slave)', 10, 0
