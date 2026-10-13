; Squirrel-OS/2 second stage — protected mode entry (0.0.3)
; Loaded at 0x8000 by the boot sector.
; Enters 32-bit protected mode, sets up a minimal GDT, writes UwU, and beeps.

BITS 16
ORG 0x8000

stage2:
    cli
    ; Set up GDT
    lgdt [gdt_desc]

    ; Enter protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; Far jump to flush pipeline and load CS
    jmp 0x08:pm_entry

BITS 32
pm_entry:
    ; Load data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    ; Write UwU to VGA text memory (0xB8000)
    mov edi, 0xB8000
    mov esi, msg
    mov ecx, msg_len
.write:
    lodsb
    mov ah, 0x0F
    stosw
    loop .write

    ; Simple beep via PIT channel 2 (no IRQ yet in this stage)
    call beep

.halt:
    hlt
    jmp .halt

; Short beep
beep:
    mov al, 0xB6
    out 0x43, al
    mov ax, 1193
    out 0x42, al
    mov al, ah
    out 0x42, al
    in al, 0x61
    or al, 0x03
    out 0x61, al
    ; crude delay
    mov ecx, 0x00FFFFFF
.delay:
    loop .delay
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

msg db 'UwU'
msg_len equ $ - msg

; GDT
align 8
gdt:
    dq 0                          ; null
    ; code segment: base=0, limit=4GB, 32-bit, executable/readable
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00
    ; data segment: base=0, limit=4GB, 32-bit, writable
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

times 2048-($-$$) db 0   ; pad to 4 sectors
