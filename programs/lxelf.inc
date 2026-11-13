; lxelf.inc — header for hand-written Linux i386 static ELF32 test programs
; (P.1). Original code. EI_OSABI = 3 (ELFOSABI_LINUX) asks the loader for
; the Linux personality: int 0x80 takes Linux call numbers, and the
; program starts at _start with argc/argv/envp/auxv on the stack.
;
;     %include "lxelf.inc"
;     LX_ELF_HEADER _start
;     _start: ...
;     LX_ELF_BSS             ; zeroed data (resb/resd) after this
;     LX_ELF_END
BITS 32
PROG_BASE equ 0x30000

; Linux i386 call numbers used by the tests
LX_EXIT     equ 1
LX_READ     equ 3
LX_WRITE    equ 4
LX_OPEN     equ 5
LX_CLOSE    equ 6
LX_LSEEK    equ 19
LX_GETPID   equ 20
LX_BRK      equ 45
LX_MUNMAP   equ 91
LX_MMAP2    equ 192
LX_EXIT_GROUP equ 252
LX_O_RDONLY equ 0
LX_O_WRONLY equ 1
LX_O_RDWR   equ 2
LX_O_CREAT  equ 0x40
LX_O_TRUNC  equ 0x200
LX_PROT_RW  equ 3
LX_MAP_PRIVATE_ANON equ 0x22

%macro LX_ELF_HEADER 1-2 3         ; entry, EI_OSABI (3 Linux, 9 FreeBSD)
    org PROG_BASE
lx_ehdr:
    db 0x7F, 'ELF', 1, 1, 1, %2     ; ELF32, LSB, version 1, OS ABI
    times 8 db 0
    dw 2                            ; ET_EXEC
    dw 3                            ; EM_386
    dd 1
    dd %1                           ; e_entry
    dd lx_phdr - lx_ehdr            ; e_phoff
    dd 0, 0                         ; e_shoff, e_flags
    dw 52, 32, 1                    ; e_ehsize, e_phentsize, e_phnum
    dw 0, 0, 0
lx_phdr:
    dd 1, 0, PROG_BASE, PROG_BASE   ; PT_LOAD of the whole file
    dd lx_file_end - lx_ehdr
    dd lx_mem_end - lx_ehdr
    dd 7, 0x1000
%endmacro

%macro LX_ELF_BSS 0
lx_file_end:
absolute lx_file_end
%endmacro

%macro LX_ELF_END 0
lx_mem_end:
%endmacro
