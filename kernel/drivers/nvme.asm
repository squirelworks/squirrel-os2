; Squirrel-OS/2 — NVMe disk driver, H.4 (OS2-HW)
; Included from pm.asm (high image). Original code, written from the
; NVM Express Base 1.4 specification.
;
; Finds the first NVMe controller (PCI class 01/08/02), sets up the admin
; queues and one I/O queue pair, reads namespace 1 and registers it as the
; block device nv0. One 512-byte sector per command, polled, through a
; bounce page (callers' buffers may be in a program's address space).
; Namespaces formatted with another block size are left alone.
; Pages of DMA memory (all from pg_alloc, identity-mapped):
;   nvme_asq/acq   admin submission/completion queues
;   nvme_iosq/iocq I/O submission/completion queues
;   nvme_buf       IDENTIFY data and the sector bounce buffer
; See documentation/kernel/hardware.md.

NVME_CLASS      equ 0x010802
NVME_MAP        equ 0x2000          ; registers + the doorbells we use
NVME_QSIZE      equ 16              ; entries in each queue
; controller registers
NV_CAP          equ 0x00            ; 64-bit
NV_CC           equ 0x14
NV_CSTS         equ 0x1C
NV_AQA          equ 0x24
NV_ASQ          equ 0x28            ; 64-bit
NV_ACQ          equ 0x30            ; 64-bit
NV_DBS          equ 0x1000          ; doorbells
NV_CC_EN        equ 1
NV_CC_SET       equ (6 << 16) | (4 << 20)   ; 64-byte SQ entries, 16-byte CQ entries
; commands
NVA_DEL_SQ      equ 0x00
NVA_CREATE_SQ   equ 0x01
NVA_CREATE_CQ   equ 0x05
NVA_IDENTIFY    equ 0x06
NVM_WRITE       equ 0x01
NVM_READ        equ 0x02

nvme_init:
    pushad
    mov eax, NVME_CLASS
    xor ecx, ecx
    call pci_find_class
    jc .out
    mov ebx, eax
    xor edx, edx
    add edx, PCI_REG_BAR0
    call pci_bar_mem
    jc .out
    mov [nvme_regs], eax
    mov ecx, NVME_MAP
    call hw_map_mmio
    jc .out
    mov eax, ebx
    call pci_enable
    mov esi, [nvme_regs]
    ; doorbell stride: 4 << CAP.DSTRD (bits 35:32)
    mov eax, [esi+NV_CAP+4]
    and eax, 0x0F
    mov ecx, eax
    mov eax, 4
    shl eax, cl
    mov [nvme_dstrd], eax
    shl eax, 2                      ; doorbells of queue 1 must fit the map
    add eax, NV_DBS
    cmp eax, NVME_MAP
    ja .out
    ; the controller must take 4 KB pages (CAP.MPSMIN = 0)
    test dword [esi+NV_CAP+4], 0x000F0000
    jnz .out
    ; reset: disable and wait for CSTS.RDY = 0
    and dword [esi+NV_CC], ~NV_CC_EN
    mov ecx, 0
    call nvme_wait_rdy
    jc .out
    ; queues
    mov edi, nvme_asq
    mov ecx, 5
.alloc:
    call pg_alloc
    test eax, eax
    jz .out
    stosd
    loop .alloc
    mov eax, [nvme_asq]
    mov [nvme_q], eax
    mov eax, [nvme_acq]
    mov [nvme_q+4], eax
    mov eax, [nvme_iosq]
    mov [nvme_q+16], eax
    mov eax, [nvme_iocq]
    mov [nvme_q+20], eax
    mov dword [esi+NV_AQA], ((NVME_QSIZE-1) << 16) | (NVME_QSIZE-1)
    mov eax, [nvme_asq]
    mov [esi+NV_ASQ], eax
    mov dword [esi+NV_ASQ+4], 0
    mov eax, [nvme_acq]
    mov [esi+NV_ACQ], eax
    mov dword [esi+NV_ACQ+4], 0
    mov dword [esi+NV_CC], NV_CC_SET | NV_CC_EN
    mov ecx, 1
    call nvme_wait_rdy
    jc .out
    ; IDENTIFY namespace 1 (CNS 0) into nvme_buf
    call nvme_clear_cmd
    mov dword [nvme_cmd], NVA_IDENTIFY
    mov dword [nvme_cmd+4], 1       ; NSID
    mov eax, [nvme_buf]
    mov [nvme_cmd+24], eax          ; PRP1
    mov dword [nvme_cmd+40], 0      ; CNS 0: namespace
    xor ebx, ebx                    ; admin queue
    call nvme_submit
    jc .out
    mov edx, [nvme_buf]
    mov eax, [edx+0]                ; NSZE, low half
    cmp dword [edx+4], 0
    je .sz
    mov eax, -1                     ; the device table holds 32 bits
.sz:
    test eax, eax
    jz .out
    movzx ecx, byte [edx+26]        ; FLBAS: format in use
    and ecx, 0x0F
    mov ecx, [edx+128+ecx*4]        ; LBA format: LBADS in bits 23:16
    shr ecx, 16
    cmp cl, 9                       ; 512-byte blocks only
    jne .out
    mov [nvme_sectors], eax
    ; I/O completion queue 1, then submission queue 1, both physically
    ; contiguous, interrupts off
    call nvme_clear_cmd
    mov dword [nvme_cmd], NVA_CREATE_CQ
    mov eax, [nvme_iocq]
    mov [nvme_cmd+24], eax
    mov dword [nvme_cmd+40], ((NVME_QSIZE-1) << 16) | 1
    mov dword [nvme_cmd+44], 1      ; physically contiguous
    xor ebx, ebx
    call nvme_submit
    jc .out
    call nvme_clear_cmd
    mov dword [nvme_cmd], NVA_CREATE_SQ
    mov eax, [nvme_iosq]
    mov [nvme_cmd+24], eax
    mov dword [nvme_cmd+40], ((NVME_QSIZE-1) << 16) | 1
    mov dword [nvme_cmd+44], (1 << 16) | 1  ; CQ 1, physically contiguous
    xor ebx, ebx
    call nvme_submit
    jc .out
    mov esi, dev_nv0
    call dev_register
.out:
    popad
    ret

; ecx = wanted CSTS.RDY (0 or 1), esi = registers -> CF on time-out or
; a fatal controller status
nvme_wait_rdy:
    push eax
    push edx
    mov edx, 20000000
.w:
    mov eax, [esi+NV_CSTS]
    test eax, 2                     ; CFS
    jnz .bad
    and eax, 1
    cmp eax, ecx
    je .ok
    out 0x80, al
    dec edx
    jnz .w
.bad:
    pop edx
    pop eax
    stc
    ret
.ok:
    pop edx
    pop eax
    clc
    ret

nvme_clear_cmd:
    push eax
    push ecx
    push edi
    mov edi, nvme_cmd
    mov ecx, 16
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret

; Puts nvme_cmd on queue ebx (0 admin, 1 I/O), rings its doorbell and
; polls its completion queue -> CF if the command failed or timed out.
; Keeps registers.
nvme_submit:
    pushad
    mov ebp, ebx
    shl ebp, 4
    add ebp, nvme_q                 ; queue state: sq, cq, tail, head/phase
    ; command id = the slot's tail, so completions can be matched
    mov eax, [ebp+8]
    mov edx, eax
    shl edx, 16
    or [nvme_cmd], edx
    mov edi, [ebp]
    shl eax, 6
    add edi, eax
    mov esi, nvme_cmd
    mov ecx, 16
    rep movsd
    mov eax, [ebp+8]
    inc eax
    and eax, NVME_QSIZE-1
    mov [ebp+8], eax
    ; SQ y tail doorbell: NV_DBS + (2y) * stride
    mov esi, [nvme_regs]
    mov ecx, [nvme_dstrd]
    imul edx, ebx, 2
    imul edx, ecx
    add edx, NV_DBS
    mov [esi+edx], eax
    ; wait for the completion entry whose phase bit matches
    mov edi, 20000000
.poll:
    mov eax, [ebp+12]               ; head index | expected phase << 16
    movzx edx, ax
    shl edx, 4
    add edx, [ebp+4]
    mov ecx, [edx+12]               ; status | phase (bit 16) | command id
    shr eax, 16
    mov ebx, ecx
    shr ebx, 16
    and ebx, 1
    cmp ebx, eax
    je .got
    out 0x80, al
    dec edi
    jnz .poll
    jmp .fail
.got:
    ; advance the head (flip the phase on wrap) and ring the CQ doorbell
    mov eax, [ebp+12]
    inc ax
    cmp ax, NVME_QSIZE
    jb .nowrap
    xor ax, ax
    xor eax, 0x10000
.nowrap:
    mov [ebp+12], eax
    movzx eax, ax
    mov ebx, ebp
    sub ebx, nvme_q
    shr ebx, 4                      ; queue number again
    imul edx, ebx, 2
    inc edx
    imul edx, [nvme_dstrd]
    add edx, NV_DBS
    mov esi, [nvme_regs]
    mov [esi+edx], eax
    shr ecx, 17                     ; status code and type
    test ecx, 0x7FFF
    jnz .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ecx = LBA, al = opcode: one-block I/O command through nvme_buf -> CF
nvme_rw:
    call nvme_clear_cmd
    movzx eax, al
    mov [nvme_cmd], eax
    mov dword [nvme_cmd+4], 1       ; NSID
    mov eax, [nvme_buf]
    mov [nvme_cmd+24], eax          ; PRP1: one 512-byte block in one page
    mov [nvme_cmd+40], ecx          ; SLBA low
    mov dword [nvme_cmd+44], 0
    mov dword [nvme_cmd+48], 0      ; NLB - 1 = 0
    push ebx
    mov ebx, 1
    call nvme_submit
    pop ebx
    ret

; ---------- device-table operations ----------

nvme_dev_probe:
    push eax
    mov eax, [nvme_sectors]
    mov [ebx+DEV_SIZE], eax
    cmp eax, 1
    pop eax
    ret

; ebx = descriptor, ecx = sector, edi = buffer -> CF on error
nvme_dev_read:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov al, NVM_READ
    call nvme_rw
    jc .fail
    mov esi, [nvme_buf]
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
nvme_dev_write:
    pushad
    cmp ecx, [ebx+DEV_SIZE]
    jae .fail
    mov edi, [nvme_buf]
    push ecx
    mov ecx, 128
    rep movsd
    pop ecx
    mov al, NVM_WRITE
    call nvme_rw
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

align 4
dev_nv0:
    db 'nv0', 0, 0, 0, 0, 0
    dd DEV_BLOCK, nvme_dev_probe, nvme_dev_read, nvme_dev_write, 0, 0, 0, 0
nvme_regs dd 0
nvme_dstrd dd 4
nvme_sectors dd 0
; pages, in this order (nvme_init allocates them in one loop)
nvme_asq dd 0
nvme_acq dd 0
nvme_iosq dd 0
nvme_iocq dd 0
nvme_buf dd 0
; per queue: submission base, completion base, SQ tail, CQ head | phase << 16
nvme_q:
    dd 0, 0, 0, 0x10000             ; admin: filled in by nvme_init
    dd 0, 0, 0, 0x10000             ; I/O queue 1
nvme_cmd times 16 dd 0
