; Squirrel-OS/2 0.0.6 — simple bump allocator
; Extends 0.0.5 with a kernel bump allocator and a small demo.
BITS 16
ORG 0x7C00
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov bx, 0x8000
    int 0x13
    jc .fail
    jmp 0x0000:0x8000
.fail:
    hlt
    jmp .fail
times 510-($-$$) db 0
dw 0xAA55
