; Squirrel-OS/2 boot sector
; Loads the 32 KB kernel image (sectors 1..64) to 0x8000 with the BIOS
; extended read (int 0x13, AH=0x42) and jumps to it.
; Original code.

KERNEL_SECTORS equ 64

BITS 16
ORG 0x7C00
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    ; dl still holds the boot drive from the firmware
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .fail
    jmp 0x0000:0x8000
.fail:
    hlt
    jmp .fail

dap:
    db 0x10, 0                  ; packet size, reserved
    dw KERNEL_SECTORS
    dw 0x8000, 0x0000           ; offset, segment
    dq 1                        ; starting LBA

times 510-($-$$) db 0
dw 0xAA55
