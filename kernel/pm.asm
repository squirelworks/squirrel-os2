; Squirrel-OS/2 — in-memory FS + app stubs
; Commands: ls, cat <name>, run <name>
BITS 16
ORG 0x8000
stage2:
    cli
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

    ; (IDT, PIC, PIT, console, keyboard, FS, and app code as implemented locally)
    ; See full source in the working tree.
    hlt
