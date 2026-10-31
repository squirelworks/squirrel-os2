; elfhello — a static ELF32 executable written by hand, to exercise the
; loader's ELF path without a cross linker. Original code.
; Build: nasm -f bin elfhello.asm -o elfhello
BITS 32
PROG_BASE equ 0x30000
org PROG_BASE

ehdr:
    db 0x7F, 'ELF', 1, 1, 1, 0      ; ELF32, little-endian, version 1
    times 8 db 0
    dw 2                            ; e_type: ET_EXEC
    dw 3                            ; e_machine: EM_386
    dd 1                            ; e_version
    dd main                         ; e_entry
    dd phdr - ehdr                  ; e_phoff
    dd 0                            ; e_shoff
    dd 0                            ; e_flags
    dw ehdr_size                    ; e_ehsize
    dw 32                           ; e_phentsize
    dw 1                            ; e_phnum
    dw 0, 0, 0                      ; e_shentsize, e_shnum, e_shstrndx
ehdr_size equ $ - ehdr

phdr:
    dd 1                            ; PT_LOAD
    dd 0                            ; p_offset
    dd PROG_BASE                    ; p_vaddr
    dd PROG_BASE                    ; p_paddr
    dd file_end - ehdr              ; p_filesz
    dd mem_end - ehdr               ; p_memsz (adds a zeroed counter)
    dd 7                            ; p_flags: rwx
    dd 0x1000                       ; p_align

main:
    mov eax, 1                      ; SYS_PUTS
    mov ebx, msg
    int 0x80
    cmp dword [counter], 0          ; bss must arrive zeroed
    jne .bad
    xor eax, eax
    ret
.bad:
    mov eax, 1
    mov ebx, badmsg
    int 0x80
    mov eax, 2
    ret

msg db 'Hello from an ELF program!', 10, 0
badmsg db 'bss was not zeroed', 10, 0
file_end:
absolute file_end
counter resd 1
mem_end:
