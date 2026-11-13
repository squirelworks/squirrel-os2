; Squirrel-OS/2 — AHCI (SATA) disk driver, H.3 (OS2-HW)
; Included from pm.asm (high image). Original code, written from the
; Serial ATA AHCI 1.3.1 specification.
;
; Finds the first AHCI controller (PCI class 01/06/01), takes every port
; that has a SATA disk attached and registers the first AHCI_MAX of them
; as block devices sd0, sd1 in the device table, beside the ATA hd0/hd1.
; One command slot per port, one 512-byte sector per command, polled: the
; same model as the ATA PIO driver, so the file system and SYS_DEVREAD
; use these disks the same way. Each port owns one page of DMA memory:
;   0x000 command list (32 headers, only slot 0 used)
;   0x400 received-FIS area
;   0x500 command table (FIS + one PRD entry)
;   0x600 512-byte bounce buffer: callers' buffers may be in a program's
;         address space, which is not identity-mapped, so data goes
;         through here and is copied.
; See documentation/kernel/hardware.md.

AHCI_MAX        equ 2
AHCI_CLASS      equ 0x010601
AHCI_ABAR       equ 0x24            ; BAR5
AHCI_MAP        equ 0x2000          ; registers: 0x100 + 32 ports * 0x80
; HBA registers
AHCI_CAP        equ 0x00
AHCI_GHC        equ 0x04
AHCI_PI         equ 0x0C
AHCI_GHC_AE     equ 0x80000000
; port registers (port base = ABAR + 0x100 + port * 0x80)
AP_CLB          equ 0x00
AP_CLBU         equ 0x04
AP_FB           equ 0x08
AP_FBU          equ 0x0C
AP_IS           equ 0x10
AP_IE           equ 0x14
AP_CMD          equ 0x18
AP_TFD          equ 0x20
AP_SIG          equ 0x24
AP_SSTS         equ 0x28
AP_SERR         equ 0x30
AP_CI           equ 0x38
APC_ST          equ 0x0001
APC_FRE         equ 0x0010
APC_FR          equ 0x4000
APC_CR          equ 0x8000
AHCI_SIG_ATA    equ 0x00000101
AHCI_IS_TFES    equ 0x40000000
; page layout
AHCI_PG_CL      equ 0x000
AHCI_PG_FIS     equ 0x400
AHCI_PG_CT      equ 0x500
AHCI_PG_BUF     equ 0x600
; unit record
AU_PORT         equ 0               ; port register base (virtual = physical)
AU_PAGE         equ 4
AU_SECTORS      equ 8
AU_NUM          equ 12              ; port number, for the boot message
AU_SIZE         equ 16

ATA_CMD_IDENTIFY    equ 0xEC
ATA_CMD_READ_EXT    equ 0x25
ATA_CMD_WRITE_EXT   equ 0x35

; Finds the controller and registers its disks. Call after dev_init.
ahci_init:
    pushad
    mov eax, AHCI_CLASS
    xor ecx, ecx
    call pci_find_class
    jc .out
    mov ebx, eax
    mov edx, AHCI_ABAR
    call pci_bar_mem
    jc .out
    mov [ahci_abar], eax
    mov ecx, AHCI_MAP
    call hw_map_mmio
    jc .out
    mov eax, ebx
    call pci_enable
    mov esi, [ahci_abar]
    or dword [esi+AHCI_GHC], AHCI_GHC_AE
    mov edx, [esi+AHCI_PI]          ; implemented ports
    xor ecx, ecx                    ; port number
.port:
    cmp dword [ahci_count], AHCI_MAX
    jae .reg
    bt edx, ecx
    jnc .next
    push ecx
    push edx
    call ahci_port_init
    pop edx
    pop ecx
.next:
    inc ecx
    cmp ecx, 32
    jb .port
.reg:
    xor ecx, ecx
.r:
    cmp ecx, [ahci_count]
    jae .out
    mov esi, [ahci_devs+ecx*4]
    call dev_register
    inc ecx
    jmp .r
.out:
    popad
    ret

; ecx = port number, esi = ABAR: if a SATA disk is there, set the port up,
; IDENTIFY it and add a unit. Clobbers eax, ebx, ecx, edx, edi.
ahci_port_init:
    mov edi, ecx
    shl edi, 7
    lea edi, [esi+edi+0x100]        ; port registers
    mov eax, [edi+AP_SSTS]
    and eax, 0x0F
    cmp eax, 3                      ; device present, link up
    jne .no
    cmp dword [edi+AP_SIG], AHCI_SIG_ATA
    jne .no                         ; ATAPI, port multiplier, ...: not a disk
    push ecx
    call ahci_stop
    pop ecx
    jc .no
    call pg_alloc
    test eax, eax
    jz .no
    mov ebx, [ahci_count]
    shl ebx, 4
    add ebx, ahci_units
    mov [ebx+AU_PORT], edi
    mov [ebx+AU_PAGE], eax
    mov [ebx+AU_NUM], ecx
    mov [edi+AP_CLB], eax
    mov dword [edi+AP_CLBU], 0
    lea edx, [eax+AHCI_PG_FIS]
    mov [edi+AP_FB], edx
    mov dword [edi+AP_FBU], 0
    mov dword [edi+AP_IE], 0
    mov dword [edi+AP_SERR], -1     ; clear stale errors (write 1 to clear)
    mov dword [edi+AP_IS], -1
    or dword [edi+AP_CMD], APC_FRE
    or dword [edi+AP_CMD], APC_ST
    ; IDENTIFY DEVICE into the bounce buffer
    push esi
    mov al, ATA_CMD_IDENTIFY
    xor ecx, ecx
    xor edx, edx                    ; device to host
    call ahci_issue
    pop esi
    jc .no
    mov edx, [ebx+AU_PAGE]
    add edx, AHCI_PG_BUF
    mov eax, [edx+200]              ; words 100-101: LBA48 sector count
    cmp dword [edx+204], 0
    je .lo
    mov eax, -1                     ; more than 2^32 sectors: the device table holds 32 bits
.lo:
    test eax, eax
    jnz .size
    mov eax, [edx+120]              ; words 60-61: 28-bit LBA count
.size:
    test eax, eax
    jz .no
    mov [ebx+AU_SECTORS], eax
    inc dword [ahci_count]
.no:
    ret

; edi = port registers: clear ST and FRE and wait for the engines to stop.
; CF if they do not.
ahci_stop:
    and dword [edi+AP_CMD], ~(APC_ST|APC_FRE)
    mov ecx, 500000
.w:
    test dword [edi+AP_CMD], APC_CR|APC_FR
    jz .ok
    out 0x80, al
    loop .w
    stc
    ret
.ok:
    clc
    ret

; Issues one command on slot 0 and polls for its end.
; ebx = unit, al = ATA command, ecx = LBA, edx = 1 for host-to-device
; (data from the bounce buffer) or 0 -> CF on error or time-out.
; Keeps registers.
ahci_issue:
    pushad
    mov esi, [ebx+AU_PAGE]
    mov edi, [ebx+AU_PORT]
    ; command header 0: 5-dword FIS, one PRD, W if writing
    mov ebp, 5 | (1 << 16)
    test edx, edx
    jz .hd
    or ebp, 1 << 6
.hd:
    mov [esi+AHCI_PG_CL], ebp
    mov dword [esi+AHCI_PG_CL+4], 0          ; PRD byte count
    lea ebp, [esi+AHCI_PG_CT]
    mov [esi+AHCI_PG_CL+8], ebp
    mov dword [esi+AHCI_PG_CL+12], 0
    ; command FIS: register host to device
    mov dword [ebp], 0x00008027              ; type 27h, C bit
    mov [ebp+2], al
    mov eax, ecx
    and eax, 0x00FFFFFF
    or eax, 0x40000000                       ; LBA mode
    mov [ebp+4], eax
    mov eax, ecx
    shr eax, 24                              ; LBA 31:24, 47:32 = 0
    mov [ebp+8], eax
    mov dword [ebp+12], 1                    ; one sector
    mov dword [ebp+16], 0
    ; PRD 0: the bounce buffer, 512 bytes
    lea eax, [esi+AHCI_PG_BUF]
    mov [ebp+0x80], eax
    mov dword [ebp+0x84], 0
    mov dword [ebp+0x88], 0
    mov dword [ebp+0x8C], 511
    ; wait until the device is not busy, then issue slot 0
    mov ecx, 1000000
.idle:
    test dword [edi+AP_TFD], 0x88            ; BSY, DRQ
    jz .go
    out 0x80, al
    loop .idle
    jmp .fail
.go:
    mov dword [edi+AP_IS], -1
    mov dword [edi+AP_CI], 1
    mov ecx, 5000000
.poll:
    test dword [edi+AP_IS], AHCI_IS_TFES
    jnz .fail
    test dword [edi+AP_CI], 1
    jz .done
    out 0x80, al
    loop .poll
    jmp .fail
.done:
    test dword [edi+AP_TFD], 1               ; ERR
    jnz .fail
    popad
    clc
    ret
.fail:
    ; recover the port for the next command: restart the engine
    call ahci_stop
    mov dword [edi+AP_SERR], -1
    mov dword [edi+AP_IS], -1
    or dword [edi+AP_CMD], APC_FRE
    or dword [edi+AP_CMD], APC_ST
    popad
    stc
    ret

; ---------- device-table operations ----------

; ebx = descriptor -> DEV_SIZE = sectors; CF if the unit was not found
ahci_dev_probe:
    push eax
    mov eax, [ebx+DEV_UNIT]
    shl eax, 4
    mov eax, [ahci_units+eax+AU_SECTORS]
    mov [ebx+DEV_SIZE], eax
    cmp eax, 1
    pop eax
    ret

; ebx = descriptor, ecx = sector, edi = buffer -> CF on error
ahci_dev_read:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov ebx, [ebx+DEV_UNIT]
    shl ebx, 4
    add ebx, ahci_units
    mov al, ATA_CMD_READ_EXT
    xor edx, edx
    call ahci_issue
    jc .fail
    mov esi, [ebx+AU_PAGE]
    add esi, AHCI_PG_BUF
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
ahci_dev_write:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov ebx, [ebx+DEV_UNIT]
    shl ebx, 4
    add ebx, ahci_units
    mov edi, [ebx+AU_PAGE]
    add edi, AHCI_PG_BUF
    push ecx
    mov ecx, 128
    rep movsd
    pop ecx
    mov al, ATA_CMD_WRITE_EXT
    mov edx, 1
    call ahci_issue
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

align 4
dev_sd0:
    db 'sd0', 0, 0, 0, 0, 0
    dd DEV_BLOCK, ahci_dev_probe, ahci_dev_read, ahci_dev_write, 0, 0, 0, 0
dev_sd1:
    db 'sd1', 0, 0, 0, 0, 0
    dd DEV_BLOCK, ahci_dev_probe, ahci_dev_read, ahci_dev_write, 1, 0, 0, 0
ahci_devs dd dev_sd0, dev_sd1
ahci_abar dd 0
ahci_count dd 0
ahci_units times AHCI_MAX*AU_SIZE db 0
