; hello64 — static ELF64 that greets through syscall/sysret (2.9-syscall64).
; Original code. Build: nasm -f bin hello64.asm -o hello64
; run hello64           -> hello64: PASS
; run hello64 badptr    -> hello64-badptr: PASS  (SYS_PUTS of kernel VA → -1)
BITS 64
PROG_BASE equ 0x30000
org PROG_BASE

SYS_PUTS    equ 1
SYS_EXIT    equ 5

ehdr:
    db 0x7F, 'ELF', 2, 1, 1, 0      ; ELF64, little-endian, version 1
    times 8 db 0
    dw 2                            ; e_type: ET_EXEC
    dw 62                           ; e_machine: EM_X86_64
    dd 1                            ; e_version
    dq main                         ; e_entry
    dq phdr - ehdr                  ; e_phoff
    dq 0                            ; e_shoff
    dd 0                            ; e_flags
    dw ehdr_size                    ; e_ehsize
    dw 56                           ; e_phentsize
    dw 1                            ; e_phnum
    dw 0, 0, 0                      ; e_shentsize, e_shnum, e_shstrndx
ehdr_size equ $ - ehdr

phdr:
    dd 1                            ; PT_LOAD
    dd 7                            ; p_flags: rwx
    dq 0                            ; p_offset
    dq PROG_BASE                    ; p_vaddr
    dq PROG_BASE                    ; p_paddr
    dq file_end - ehdr              ; p_filesz
    dq mem_end - ehdr               ; p_memsz
    dq 0x1000                       ; p_align

main:
    ; rdi = arg string (loader); also at [rsp+8] like 32-bit programs
    mov rsi, rdi
    test rsi, rsi
    jz .hello
    cmp byte [rsi], 'b'
    jne .hello
    ; badptr: SYS_PUTS of a kernel address must return -1
    mov eax, SYS_PUTS
    mov edi, 0x8000
    syscall
    cmp eax, -1                 ; ABI returns 32-bit status in eax
    jne .fail
    mov eax, SYS_PUTS
    lea rdi, [rel badpass]
    syscall
    xor eax, eax
    ret
.hello:
    mov eax, SYS_PUTS
    lea rdi, [rel msg]
    syscall
    xor eax, eax
    ret
.fail:
    mov eax, SYS_PUTS
    lea rdi, [rel badfail]
    syscall
    mov eax, 1
    ret

msg db 'hello64: PASS', 10, 0
badpass db 'hello64-badptr: PASS', 10, 0
badfail db 'hello64-badptr: FAIL', 10, 0
file_end:
absolute file_end
mem_end:
