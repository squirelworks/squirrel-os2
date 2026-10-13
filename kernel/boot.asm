; Squirrel-OS/2 — 0.0.3 protected-mode transition
; Boot sector loads a small second stage that enters protected mode.
; Original Squirrel-OS/2 code.
;
; Build:
;   nasm -f bin boot.asm -o boot.bin
;   nasm -f bin pm.asm -o pm.bin
;   cat boot.bin pm.bin > squirrel.bin
; Run:
;   qemu-system-i386 -drive format=raw,file=squirrel.bin

BITS 16
ORG 0x7C00

start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; Load second stage (pm.bin) to 0x8000
    mov ah, 0x02
    mov al, 4             ; 4 sectors
    mov ch, 0
    mov cl, 2             ; start at sector 2
    mov dh, 0
    mov bx, 0x8000
    int 0x13
    jc disk_error

    ; Jump to second stage
    jmp 0x0000:0x8000

disk_error:
    mov si, err
    call print
.halt:
    hlt
    jmp .halt

print:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp print
.done:
    ret

err db 'Disk error', 0

times 510-($-$$) db 0
dw 0xAA55
