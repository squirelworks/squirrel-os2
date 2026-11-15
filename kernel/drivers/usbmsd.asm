; Squirrel-OS/2 — USB mass storage, H.6 (OS2-HW)
; Included from pm.asm (high image). Original code, written from the USB
; Mass Storage Class Bulk-Only Transport 1.0 specification and the SCSI
; block commands (SBC) READ CAPACITY(10), READ(10), WRITE(10).
;
; xhci.asm hands over a bulk-only SCSI device (class 8/6/50h). We
; configure it, wait until LUN 0 is ready, read its capacity and register
; it as the block device ud0 (512-byte blocks only). Each sector is one
; command block wrapper (bulk OUT), one 512-byte data stage and one
; command status wrapper (bulk IN), through the device's data page.
; See documentation/kernel/hardware.md.

CBW_SIG         equ 0x43425355      ; 'USBC'
CSW_SIG         equ 0x53425355      ; 'USBS'

; ebx = device record -> CF if it could not be set up
usbmsd_attach:
    cmp dword [usbmsd_dev], 0
    jne .no                         ; one stick for now
    call xhci_configure
    jc .no
    mov [usbmsd_dev], ebx
    ; TEST UNIT READY until it is (a fresh device reports a unit attention
    ; first), with REQUEST SENSE after each failure
    mov esi, 10
.tur:
    call usbmsd_cdb_clear
    xor eax, eax
    mov ecx, 6
    xor edx, edx
    call usbmsd_command
    jnc .ready
    call usbmsd_cdb_clear
    mov byte [usbmsd_cdb], 0x03     ; REQUEST SENSE
    mov byte [usbmsd_cdb+4], 18
    mov eax, 18
    mov ecx, 6
    mov edx, 1
    call usbmsd_command
    dec esi
    jnz .tur
    jmp .fail
.ready:
    call usbmsd_cdb_clear
    mov byte [usbmsd_cdb], 0x25     ; READ CAPACITY(10)
    mov eax, 8
    mov ecx, 10
    mov edx, 1
    call usbmsd_command
    jc .fail
    mov edi, [ebx+XD_DATA]
    mov eax, [edi+XDP_SECTOR]       ; last LBA, big-endian
    bswap eax
    mov edx, [edi+XDP_SECTOR+4]     ; block length
    bswap edx
    cmp edx, 512
    jne .fail
    inc eax
    jz .fail
    mov [usbmsd_sectors], eax
    mov esi, dev_ud0
    call dev_register
    clc
    ret
.fail:
    mov dword [usbmsd_dev], 0
.no:
    stc
    ret

usbmsd_cdb_clear:
    mov dword [usbmsd_cdb], 0
    mov dword [usbmsd_cdb+4], 0
    mov dword [usbmsd_cdb+8], 0
    mov dword [usbmsd_cdb+12], 0
    ret

; One bulk-only command with usbmsd_cdb: ebx = device, eax = data
; length (0 or up to 512, in the data page at XDP_SECTOR), ecx = CDB
; length, edx = 1 for data in, 0 for out -> CF unless the status is good
usbmsd_command:
    pushad
    mov esi, eax                    ; data length
    mov edi, [ebx+XD_DATA]
    add edi, XDP_CBW
    mov dword [edi], CBW_SIG
    inc dword [usbmsd_tag]
    mov eax, [usbmsd_tag]
    mov [edi+4], eax
    mov [edi+8], esi
    xor eax, eax
    test edx, edx
    jz .fl
    mov al, 0x80
.fl:
    mov [edi+12], al                ; flags
    mov byte [edi+13], 0            ; LUN 0
    mov [edi+14], cl                ; CDB length
    mov eax, [usbmsd_cdb]
    mov [edi+15], eax
    mov eax, [usbmsd_cdb+4]
    mov [edi+19], eax
    mov eax, [usbmsd_cdb+8]
    mov [edi+23], eax
    mov eax, [usbmsd_cdb+12]
    mov [edi+27], eax
    mov [usbmsd_dir], edx
    ; command block wrapper: bulk OUT
    lea ebp, [ebx+XD_EPB]
    mov ecx, [ebx+XD_DCIB]
    mov eax, edi
    mov edx, 31
    call xhci_bulk
    jnc .data
    call xhci_ep_recover
    jmp .fail
.data:
    test esi, esi
    jz .status
    mov eax, [ebx+XD_DATA]
    add eax, XDP_SECTOR
    mov edx, esi
    lea ebp, [ebx+XD_EPB]
    mov ecx, [ebx+XD_DCIB]
    cmp dword [usbmsd_dir], 0
    je .dgo
    lea ebp, [ebx+XD_EPA]
    mov ecx, [ebx+XD_DCIA]
.dgo:
    call xhci_bulk
    jnc .status
    call xhci_ep_recover            ; a stalled data stage: still read the status
.status:
    mov edi, 2                      ; tries: once more after a stall
.csw:
    mov eax, [ebx+XD_DATA]
    add eax, XDP_CSW
    mov dword [eax], 0
    mov edx, 13
    lea ebp, [ebx+XD_EPA]
    mov ecx, [ebx+XD_DCIA]
    call xhci_bulk
    jnc .check
    call xhci_ep_recover
    dec edi
    jnz .csw
    jmp .fail
.check:
    mov eax, [ebx+XD_DATA]
    cmp dword [eax+XDP_CSW], CSW_SIG
    jne .fail
    mov edx, [usbmsd_tag]
    cmp [eax+XDP_CSW+4], edx
    jne .fail
    cmp byte [eax+XDP_CSW+12], 0
    jne .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ecx = LBA, al = 0x28 READ(10) or 0x2A WRITE(10) of one block -> CF
usbmsd_rw:
    push ebx
    push ecx
    push edx
    mov ebx, [usbmsd_dev]
    call usbmsd_cdb_clear
    mov [usbmsd_cdb], al
    bswap ecx
    mov [usbmsd_cdb+2], ecx
    mov byte [usbmsd_cdb+8], 1      ; one block
    xor edx, edx
    cmp al, 0x28
    jne .w
    inc edx
.w:
    mov eax, 512
    mov ecx, 10
    call usbmsd_command
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- device-table operations ----------

usbmsd_dev_probe:
    push eax
    mov eax, [usbmsd_sectors]
    mov [ebx+DEV_SIZE], eax
    cmp eax, 1
    pop eax
    ret

; ebx = descriptor, ecx = sector, edi = buffer -> CF on error
usbmsd_dev_read:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov al, 0x28
    call usbmsd_rw
    jc .fail
    mov esi, [usbmsd_dev]
    mov esi, [esi+XD_DATA]
    add esi, XDP_SECTOR
    mov ecx, 128
    rep movsd
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ebx = descriptor, ecx = sector, esi = buffer -> CF on error
usbmsd_dev_write:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov edi, [usbmsd_dev]
    mov edi, [edi+XD_DATA]
    add edi, XDP_SECTOR
    push ecx
    mov ecx, 128
    rep movsd
    pop ecx
    mov al, 0x2A
    call usbmsd_rw
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

align 4
dev_ud0:
    db 'ud0', 0, 0, 0, 0, 0
    dd DEV_BLOCK, usbmsd_dev_probe, usbmsd_dev_read, usbmsd_dev_write, 0, 0, 0, 0
usbmsd_dev dd 0
usbmsd_sectors dd 0
usbmsd_tag dd 0
usbmsd_dir dd 0
usbmsd_cdb times 16 db 0
