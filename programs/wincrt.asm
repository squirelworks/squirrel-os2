; wincrt — a Win32 console program using the C runtime (msvcrt.dll), PE32
; written by hand (P.5). Original code. Checks what compiler start-up code
; needs from winrun: the TEB through FS, __getmainargs, printf formats,
; sprintf, malloc, fopen/fputs/fgets, strcmp, atexit and exit.
;   run wincrt acorn   ->  crt: -5 acorn 00ab x  |  ...  wincrt: PASS
; Build: nasm -f bin wincrt.asm -o wincrt
BITS 32

IMAGEBASE   equ 0x400000
SECT_RVA    equ 0x1000
%define RVA(x) ((x) - sect + SECT_RVA)
%define VA(x)  (RVA(x) + IMAGEBASE)

%assign NFIX 0
%macro FIX 0                    ; after an instruction ending in an address
fix_%[NFIX] equ $ - 4
%assign NFIX NFIX+1
%endmacro
%macro FIXAT 1                  ; the address is %1 bytes into a 7-byte instruction
fix_%[NFIX] equ $ - 7 + %1
%assign NFIX NFIX+1
%endmacro
%macro CALLI 1                  ; call an import through the IAT
    call [VA(iat_%1)]
    FIX
%endmacro
%macro PUSHA_ 1                 ; push the address of a label
    push VA(%1)
    FIX
%endmacro
%macro STEP 1
    mov byte [VA(step)], %1
    FIXAT 2
%endmacro

mz:
    dw 'MZ'
    times 0x3A db 0
    dd pe - mz
pe:
    db 'PE', 0, 0
    dw 0x14C, 1
    dd 0, 0, 0
    dw opt_end - opt, 0x0102
opt:
    dw 0x10B
    db 1, 0
    dd sect_end - sect, 0, 0
    dd RVA(start)
    dd SECT_RVA, SECT_RVA
    dd IMAGEBASE
    dd 0x1000, 0x200
    dw 4, 0, 0, 0, 4, 0
    dd 0
    dd SECT_RVA + ((sect_end - sect + 0xFFF) & ~0xFFF)
    dd sect - mz
    dd 0
    dw 3, 0x0040
    dd 0x100000, 0x1000, 0x100000, 0x1000
    dd 0, 16
    dd 0, 0
    dd RVA(imports), imports_end - imports
    dd 0, 0, 0, 0, 0, 0
    dd RVA(relocs), relocs_end - relocs
    times 10 dd 0, 0
opt_end:
    db '.text', 0, 0, 0
    dd sect_end - sect, SECT_RVA, sect_file_end - sect, sect - mz
    dd 0, 0, 0
    dd 0xE0000060
    times 0x200 - ($ - mz) db 0

sect:
start:
    STEP 'a'                        ; the TEB: Self at fs:[0x18], a PEB
    mov eax, [fs:0x18]
    test eax, eax
    jz fail
    cmp [eax+0x18], eax
    jne fail
    cmp dword [eax+0x30], 0
    je fail
    cmp dword [fs:0], -1            ; no exception handlers yet
    jne fail
    STEP 'b'                        ; arguments
    push VA(startinfo)
    FIX
    push 0
    PUSHA_ envp
    PUSHA_ argv
    PUSHA_ argc
    CALLI __getmainargs
    add esp, 20
    cmp dword [VA(argc)], 2
    FIXAT 2
    jne fail
    mov eax, [VA(argv)]
    FIX
    mov esi, [eax+4]                ; argv[1]
    STEP 'c'                        ; printf with flags and widths
    push VA(s_x)
    FIX
    push 0xab
    push esi
    push -5
    PUSHA_ fmt1
    CALLI printf
    add esp, 20
    STEP 'd'                        ; sprintf into malloc'd memory
    push 16
    CALLI malloc
    add esp, 4
    test eax, eax
    jz fail
    mov ebx, eax
    push 42
    PUSHA_ fmt2
    push ebx
    CALLI sprintf
    add esp, 12
    cmp eax, 4
    jne fail
    PUSHA_ s_n42
    push ebx
    CALLI strcmp
    add esp, 8
    test eax, eax
    jnz fail
    STEP 'e'                        ; a file through FILE*
    PUSHA_ s_w
    PUSHA_ fname
    CALLI fopen
    add esp, 8
    test eax, eax
    jz fail
    mov ebx, eax
    push ebx
    PUSHA_ s_line
    CALLI fputs
    add esp, 8
    push ebx
    CALLI fclose
    add esp, 4
    PUSHA_ s_r
    PUSHA_ fname
    CALLI fopen
    add esp, 8
    test eax, eax
    jz fail
    mov ebx, eax
    push ebx
    push 40
    PUSHA_ buf
    CALLI fgets
    add esp, 12
    test eax, eax
    jz fail
    push ebx
    CALLI fclose
    add esp, 4
    PUSHA_ s_line
    PUSHA_ buf
    CALLI strcmp
    add esp, 8
    test eax, eax
    jnz fail
    STEP 'f'                        ; exit runs the atexit list
    PUSHA_ at_exit
    CALLI atexit
    add esp, 4
    push 0
    CALLI exit

at_exit:
    PUSHA_ pass
    CALLI printf
    add esp, 4
    ret

fail:
    PUSHA_ failmsg
    CALLI printf
    add esp, 4
    push 1
    CALLI exit

fmt1 db 'crt: %d %s %04x %-3s|', 10, 0
fmt2 db 'n=%u', 0
s_n42 db 'n=42', 0
s_x db 'x', 0
s_w db 'w', 0
s_r db 'r', 0
fname db 'crt.txt', 0
s_line db 'through stdio', 10, 0
pass db 'wincrt: PASS', 10, 0
failmsg db 'wincrt: FAIL '
step db '?', 10, 0
align 4
argc dd 0
argv dd 0
envp dd 0
startinfo dd 0
buf times 40 db 0

; ---------- imports: two DLLs ----------
%macro THUNKS 1-*               ; lookup or address table for these names
%rep %0
    dd RVA(hn_%1)
%rotate 1
%endrep
    dd 0
%endmacro
%macro IATS 1-*
%rep %0
iat_%1: dd RVA(hn_%1)
%rotate 1
%endrep
    dd 0
%endmacro
%macro NAMES 1-*
%rep %0
hn_%1: dw 0
    db %str(%1), 0
    align 2, db 0
%rotate 1
%endrep
%endmacro
%define CRT_FUNCS __getmainargs, printf, malloc, sprintf, strcmp, fopen, fputs, fclose, fgets, atexit, exit
%define K32_FUNCS GetStdHandle

    align 4, db 0
imports:
    dd RVA(ilt_crt), 0, 0, RVA(dll_crt), RVA(iat_crt)
    dd RVA(ilt_k32), 0, 0, RVA(dll_k32), RVA(iat_k32)
    dd 0, 0, 0, 0, 0
imports_end:
ilt_crt: THUNKS CRT_FUNCS
ilt_k32: THUNKS K32_FUNCS
iat_crt: IATS CRT_FUNCS
iat_k32: IATS K32_FUNCS
NAMES CRT_FUNCS
NAMES K32_FUNCS
dll_crt db 'msvcrt.dll', 0
dll_k32 db 'KERNEL32.dll', 0

    align 4, db 0
relocs:
    dd SECT_RVA, relocs_end - relocs
%assign i 0
%rep NFIX
    dw 0x3000 | (fix_%[i] - sect)
%assign i i+1
%endrep
    align 4, db 0
relocs_end:
%if relocs_end - sect > 0x1000
%error the section outgrew the single relocation block
%endif
sect_end:
    times (0x200 - ($ - sect) % 0x200) % 0x200 db 0
sect_file_end:
