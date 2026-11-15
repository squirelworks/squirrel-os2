; windll — a Win32 console program that uses a DLL, PE32 written by hand
; (P.6). Original code. Exercises winrun's DLL loader with acorn.dll
; (programs/winlib.asm): imports by name and by ordinal, a data import, a
; forwarded export, DllMain, LoadLibraryA, GetModuleHandleA,
; GetProcAddress, and an import from a DLL that is not on the disk.
;   run windll         checks it all, "windll: PASS"
;   run windll gone    calls nothere.dll's Gone: "not implemented: Gone"
; Build: nasm -f bin windll.asm -o windll
BITS 32

IMAGEBASE   equ 0x400000
SECT_RVA    equ 0x1000
%define RVA(x) ((x) - sect + SECT_RVA)
%define VA(x)  (RVA(x) + IMAGEBASE)

%assign NFIX 0
%macro FIX 0                    ; the last four bytes are an absolute address
fix_%[NFIX] equ $ - 4
%assign NFIX NFIX+1
%endmacro
%macro FIXB 1                   ; ... with %1 bytes after them
fix_%[NFIX] equ $ - 4 - %1
%assign NFIX NFIX+1
%endmacro
%macro CALLI 1                  ; call an import through the IAT
    call [VA(iat_%1)]
    FIX
%endmacro
%macro PUSHV 1                  ; push the address of a label
    push VA(%1)
    FIX
%endmacro

mz:
    dw 'MZ'
    times 0x3A db 0
    dd pe - mz
pe:
    db 'PE', 0, 0
    dw 0x14C, 1
    dd 0, 0, 0
    dw opt_end - opt
    dw 0x0102
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
    dw 3                            ; IMAGE_SUBSYSTEM_WINDOWS_CUI
    dw 0x0040
    dd 0x100000, 0x1000, 0x100000, 0x1000
    dd 0, 16
    dd 0, 0
    dd RVA(imports), imports_end - imports
    dd 0, 0, 0, 0, 0, 0
    dd RVA(relocs), relocs_end - relocs
    times 10 dd 0, 0
opt_end:
    db '.text', 0, 0, 0
    dd sect_end - sect
    dd SECT_RVA
    dd sect_file_end - sect
    dd sect - mz
    dd 0, 0, 0
    dd 0xE0000060
    times 0x200 - ($ - mz) db 0

sect:
start:
    CALLI GetCommandLineA           ; "gone": call the missing DLL's import
    mov esi, eax
.scan:
    cmp byte [esi], 0
    je .go
    cmp dword [esi], 'gone'
    je .gone
    inc esi
    jmp .scan
.gone:
    CALLI Gone
.go:
    mov byte [VA(step)], 'a'        ; by name
    FIXB 1
    push 3
    push 2
    CALLI AcornAdd
    cmp eax, 5
    jne fail
    mov byte [VA(step)], 'b'        ; the data import: DllMain ran once
    FIXB 1
    mov eax, [VA(iat_AcornCount)]
    FIX
    cmp dword [eax], 1
    jne fail
    mov byte [VA(step)], 'c'        ; by ordinal: 2 is AcornHello
    FIXB 1
    mov eax, [VA(iat_ord2)]
    FIX
    cmp eax, [VA(iat_AcornHello)]
    FIX
    jne fail
    call eax
    push eax
    PUSHV fmt_s
    CALLI printf
    add esp, 8
    mov byte [VA(step)], 'd'        ; the forwarder reaches GetLastError
    FIXB 1
    push 42
    CALLI SetLastError
    CALLI AcornLastErr
    cmp eax, 42
    jne fail
    mov byte [VA(step)], 'e'        ; LoadLibrary finds the loaded DLL
    FIXB 1
    PUSHV n_acorn
    CALLI LoadLibraryA
    test eax, eax
    jz fail
    mov ebx, eax
    PUSHV n_acorn_up
    CALLI GetModuleHandleA
    cmp eax, ebx
    jne fail
    PUSHV s_add
    push ebx
    CALLI GetProcAddress
    cmp eax, [VA(iat_AcornAdd)]
    FIX
    jne fail
    mov eax, [VA(iat_AcornCount)]   ; and DllMain did not run again
    FIX
    cmp dword [eax], 1
    jne fail
    mov byte [VA(step)], 'f'        ; a shim DLL through GetProcAddress
    FIXB 1
    PUSHV n_k32
    CALLI LoadLibraryA
    test eax, eax
    jz fail
    PUSHV s_gle
    push eax
    CALLI GetProcAddress
    test eax, eax
    jz fail
    call eax
    cmp eax, 42
    jne fail
    mov byte [VA(step)], 'g'        ; no such DLL: 0, ERROR_MOD_NOT_FOUND
    FIXB 1
    PUSHV n_none
    CALLI LoadLibraryA
    test eax, eax
    jnz fail
    CALLI GetLastError
    cmp eax, 126
    jne fail
    mov byte [VA(step)], 'h'        ; no such export: ERROR_PROC_NOT_FOUND
    FIXB 1
    PUSHV s_none
    push ebx
    CALLI GetProcAddress
    test eax, eax
    jnz fail
    CALLI GetLastError
    cmp eax, 127
    jne fail
    PUSHV passmsg
    CALLI printf
    add esp, 4
    push 0
    CALLI ExitProcess
fail:
    PUSHV failmsg
    CALLI printf
    add esp, 4
    push 1
    CALLI ExitProcess

n_acorn db 'acorn.dll', 0
n_acorn_up db 'ACORN.DLL', 0
n_k32 db 'kernel32.dll', 0
n_none db 'nosuch.dll', 0
s_add db 'AcornAdd', 0
s_gle db 'GetLastError', 0
s_none db 'AcornNope', 0
fmt_s db 'windll: %s', 10, 0
passmsg db 'windll: PASS', 10, 0
failmsg db 'windll: FAIL '
step db '?', 10, 0

; ---------- imports: four DLLs, one of them missing ----------
%macro DLL 2-*                      ; tag, functions...
%define DLLTAG %1
%rotate 1
ilt_%[DLLTAG]:
%rep %0-1
    dd RVA(hn_%1)
%rotate 1
%endrep
%rotate 1                       ; past the tag
    dd 0
iat_start_%[DLLTAG]:
%rep %0-1
iat_%1: dd RVA(hn_%1)
%rotate 1
%endrep
%rotate 1                       ; past the tag
    dd 0
%rep %0-1
hn_%1: dw 0
    db %str(%1), 0
    align 2, db 0
%rotate 1
%endrep
%rotate 1                       ; past the tag
%endmacro
    align 4, db 0
imports:
    dd RVA(ilt_k), 0, 0, RVA(n_k), RVA(iat_start_k)
    dd RVA(ilt_m), 0, 0, RVA(n_m), RVA(iat_start_m)
    dd RVA(ilt_a), 0, 0, RVA(n_a), RVA(iat_start_a)
    dd RVA(ilt_x), 0, 0, RVA(n_x), RVA(iat_start_x)
    dd 0, 0, 0, 0, 0
imports_end:
DLL k, ExitProcess, GetCommandLineA, LoadLibraryA, GetModuleHandleA, GetProcAddress, SetLastError, GetLastError
DLL m, printf
DLL x, Gone
ilt_a:                              ; ACORN.DLL by hand: names and an ordinal
    dd RVA(hn_AcornAdd), RVA(hn_AcornHello), RVA(hn_AcornCount), RVA(hn_AcornLastErr), 0x80000002, 0
iat_start_a:
iat_AcornAdd: dd RVA(hn_AcornAdd)
iat_AcornHello: dd RVA(hn_AcornHello)
iat_AcornCount: dd RVA(hn_AcornCount)
iat_AcornLastErr: dd RVA(hn_AcornLastErr)
iat_ord2: dd 0x80000002
    dd 0
hn_AcornAdd: dw 0
    db 'AcornAdd', 0
hn_AcornHello: dw 0
    db 'AcornHello', 0
hn_AcornCount: dw 0
    db 'AcornCount', 0
hn_AcornLastErr: dw 0
    db 'AcornLastErr', 0
n_k db 'KERNEL32.dll', 0
n_m db 'msvcrt.dll', 0
n_a db 'ACORN.DLL', 0
n_x db 'nothere.dll', 0

; ---------- base relocations: one block for the section's first page ----------
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
