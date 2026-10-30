; Squirrel-OS/2 — x86 early kernel
; Protected-mode entry, VGA banner, halt.
; Original code. Formal home for the early path currently in pm.asm.
;
; Build (from kernel/):
;   nasm -f bin arch/x86/early.asm -o early-x86.bin
; Run:
;   qemu-system-i386 -drive format=raw,file=early-x86.bin

BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm

BITS 32
pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x9F000

    ; Clear screen and write banner
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0F20
    rep stosw

    mov esi, banner
    mov edi, 0xB8000
    mov ah, 0x0F
.print:
    lodsb
    test al, al
    jz .halt
    stosw
    jmp .print

.halt:
    hlt
    jmp .halt

banner db 'Squirrel-OS/2 x86 early', 0

gdt:
    dq 0
    dq 0x00CF9A000000FFFF   ; code
    dq 0x00CF92000000FFFF   ; data
gdt_desc:
    dw $ - gdt - 1
    dd gdt

times 510-($-$$) db 0
dw 0xAA55
