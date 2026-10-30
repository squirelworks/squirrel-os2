; Squirrel-OS/2 boot sector
; Loads the 64 KB kernel image (sectors 1..128) to 0x8000 with the BIOS
; extended read (int 0x13, AH=0x42), in two 64-sector reads because some
; firmware caps one read at 127 sectors, and jumps to it.
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
    ; dl holds the boot drive from the firmware; keep it for the second read
    mov [boot_drive], dl
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .fail
    ; second half: sectors 65..128 to 0x1000:0x0000 (0x10000)
    mov word [dap+4], 0x0000
    mov word [dap+6], 0x1000
    mov dword [dap+8], 1+KERNEL_SECTORS
    mov dl, [boot_drive]
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc .fail
    jmp 0x0000:0x8000
.fail:
    hlt
    jmp .fail

boot_drive db 0
dap:
    db 0x10, 0                  ; packet size, reserved
    dw KERNEL_SECTORS
    dw 0x8000, 0x0000           ; offset, segment
    dq 1                        ; starting LBA

times 510-($-$$) db 0
dw 0xAA55
