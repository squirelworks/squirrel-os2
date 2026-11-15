; dbgelf — a hand-made ELF32 program with a .symtab, for the debugger's
; ELF symbols (A.4). Original code. Build: nasm -f bin dbgelf.asm -o dbgelf
BITS 32
PROG_BASE equ 0x30000
org PROG_BASE

ehdr:
    db 0x7F, 'ELF', 1, 1, 1, 0
    times 8 db 0
    dw 2                            ; ET_EXEC
    dw 3                            ; EM_386
    dd 1
    dd start                        ; e_entry
    dd phdr - ehdr                  ; e_phoff
    dd shdrs - ehdr                 ; e_shoff
    dd 0
    dw 52                           ; e_ehsize
    dw 32, 1                        ; e_phentsize, e_phnum
    dw 40, 3, 0                     ; e_shentsize, e_shnum, e_shstrndx (none)

phdr:
    dd 1, 0, PROG_BASE, PROG_BASE
    dd code_end - ehdr, code_end - ehdr
    dd 7, 0x1000

start:
    mov ecx, 3
loop_top:
    add dword [value], ecx
    loop loop_top
    mov eax, 1                      ; SYS_PUTS
    mov ebx, msg
    int 0x80
    mov eax, [value]                ; 3 + 2 + 1
    ret
value dd 0
msg db 'dbgelf done', 10, 0
code_end:

symtab:
    times 16 db 0                   ; the null symbol
    dd s_start - strtab, start, 0
    db 0x12, 0                      ; global FUNC
    dw 1
    dd s_loop - strtab, loop_top, 0
    db 0x00, 0                      ; local NOTYPE
    dw 1
    dd s_value - strtab, value, 4
    db 0x11, 0                      ; global OBJECT
    dw 1
    dd s_undef - strtab, 0, 0
    db 0x10, 0                      ; undefined: left out
    dw 0
symtab_end:
strtab:
    db 0
s_start db 'start', 0
s_loop db 'loop_top', 0
s_value db 'value', 0
s_undef db 'printf', 0
strtab_end:

align 4
shdrs:
    times 40 db 0
    ; .symtab: name, type, flags, addr, offset, size, link, info, align, entsize
    dd 0, 2, 0, 0, symtab - ehdr, symtab_end - symtab, 2, 1, 4, 16
    ; .strtab
    dd 0, 3, 0, 0, strtab - ehdr, strtab_end - strtab, 0, 0, 1, 0
