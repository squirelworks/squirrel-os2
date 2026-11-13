; Squirrel-OS/2 — high kernel image loader (2.4)
; Included from pm.asm, still in 16-bit real mode. Original code.
;
; The boot sector loads only the 96 KB low image (sectors 1..192) to
; 0x8000. Everything assembled into section .high follows it on the disk,
; from sector KHIGH_LBA, and runs at KHIGH_BASE (1 MB). stage2 calls
; load_high (A20 already on): it reads the high image in chunks into
; KSCRATCH with the BIOS (extended reads on hard disks, one sector at a
; time by CHS on floppies or when extended reads fail, as the boot sector
; does) and copies each chunk above 1 MB in "unreal" mode: a moment in
; protected mode gives DS and ES 4 GB limits, which stay when real mode
; comes back. The last dword of the image must be KHIGH_SIG.
; See documentation/kernel/kernel-image.md.

BITS 16

LD_CHUNK    equ 64                  ; sectors per extended read (32 KB)
LD_BUF_SEG  equ KSCRATCH >> 4       ; chunks land at KSCRATCH

load_high:
    mov dword [ld_lba], KHIGH_LBA
    mov dword [ld_dst], KHIGH_BASE
    mov word [ld_left], KHIGH_SECTS
    test byte [ld_drive], 0x80
    jz .use_chs                     ; a floppy: no extended reads
.chunk:
    mov cx, [ld_left]
    test cx, cx
    jz .check
    cmp byte [ld_ext], 0
    je .one
    cmp cx, LD_CHUNK
    jbe .ext
    mov cx, LD_CHUNK
.ext:
    mov [ld_dap+2], cx
    mov word [ld_dap+4], 0
    mov word [ld_dap+6], LD_BUF_SEG
    mov eax, [ld_lba]
    mov [ld_dap+8], eax
    push cx
    mov si, ld_dap
    mov dl, [ld_drive]
    mov ah, 0x42
    int 0x13
    pop cx
    jnc .copy
.use_chs:                           ; this firmware or drive: CHS from here
    mov byte [ld_ext], 0
    call ld_geometry
    jmp .chunk
.one:
    mov cx, 1
    call ld_chs_read
.copy:
    ; cx sectors at KSCRATCH -> [ld_dst]
    mov [ld_last], cx
    movzx ecx, cx
    shl ecx, 7                      ; dwords
    call ld_copy
    movzx eax, word [ld_last]
    add [ld_lba], eax
    shl eax, 9
    add [ld_dst], eax
    mov ax, [ld_last]
    sub [ld_left], ax
    jmp .chunk
.check:
    ; the last chunk is still at KSCRATCH: its last dword is the signature
    push es
    mov ax, LD_BUF_SEG
    mov es, ax
    mov bx, [ld_last]
    shl bx, 9
    cmp dword [es:bx-4], KHIGH_SIG
    pop es
    jne ld_fail
    ret

; Sectors per track and heads of [ld_drive], or the failure message.
ld_geometry:
    push es
    mov dl, [ld_drive]
    mov ah, 0x08
    xor di, di
    mov es, di
    int 0x13
    pop es
    jc ld_fail
    and cx, 0x3F
    jz ld_fail
    mov [ld_spt], cx
    movzx ax, dh
    inc ax
    mov [ld_heads], ax
    ret

; One sector, LBA [ld_lba] (below 65536), to KSCRATCH by CHS, three tries.
ld_chs_read:
    pusha
    push es
    mov ax, LD_BUF_SEG
    mov es, ax
    mov byte [ld_tries], 3
.again:
    mov ax, [ld_lba]
    xor dx, dx
    div word [ld_spt]               ; ax = track, dx = sector - 1
    mov cl, dl
    inc cl
    xor dx, dx
    div word [ld_heads]             ; ax = cylinder, dx = head
    mov ch, al
    shl ah, 6                       ; cylinder bits 8-9 into cl bits 6-7
    or cl, ah
    mov dh, dl
    mov dl, [ld_drive]
    xor bx, bx
    mov ax, 0x0201
    int 0x13
    jnc .ok
    xor ah, ah                      ; reset the drive and try again
    mov dl, [ld_drive]
    int 0x13
    dec byte [ld_tries]
    jnz .again
    jmp ld_fail
.ok:
    pop es
    popa
    ret

; ecx dwords from KSCRATCH to [ld_dst], through unreal mode.
ld_copy:
    push ds
    push es
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp short .pm
.pm:
    mov bx, 0x10                    ; flat data: 4 GB limit into the caches
    mov ds, bx
    mov es, bx
    and al, 0xFE
    mov cr0, eax
    jmp short .rm
.rm:
    xor bx, bx                      ; real-mode bases again, the limits stay
    mov ds, bx
    mov es, bx
    mov esi, KSCRATCH
    mov edi, [ld_dst]
    cld
    a32 rep movsd
    pop es
    pop ds
    sti
    ret

ld_fail:
    mov si, msg_nohigh
    jmp stage2.say

msg_nohigh db 'Squirrel-OS/2: cannot read the high kernel image from the boot disk', 13, 10, 0
ld_drive db 0
ld_ext   db 1
ld_tries db 0
ld_spt   dw 0
ld_heads dw 0
ld_left  dw 0
ld_last  dw 0
align 4
ld_lba   dd 0
ld_dst   dd 0
ld_dap:
    db 0x10, 0                      ; packet size, reserved
    dw 0                            ; sectors
    dw 0, 0                         ; offset, segment
    dq 0                            ; starting LBA
