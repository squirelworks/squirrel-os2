; winlib — acorn.dll, a Win32 DLL written by hand (P.6). Original code.
; Loaded by winrun's DLL loader for programs/windll.asm: exports by name and
; by ordinal (Base 1: AcornAdd, AcornHello, AcornCount, AcornLastErr), a
; data export, a forwarder to KERNEL32.GetLastError, its own KERNEL32
; import, and a DllMain that counts its calls. ImageBase 0x10000000, so
; winrun always relocates it.
; Build: nasm -f bin winlib.asm -o acorn.dll
BITS 32

IMAGEBASE   equ 0x10000000
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
    dw 0x2102                       ; a DLL, 32-bit, executable
opt:
    dw 0x10B
    db 1, 0
    dd sect_end - sect, 0, 0
    dd RVA(DllMain)
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
    dd RVA(exports), exports_end - exports
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
; BOOL WINAPI DllMain(hinst, reason, reserved)
DllMain:
    cmp dword [esp+8], 1            ; DLL_PROCESS_ATTACH
    jne .r
    inc dword [VA(AcornCount)]
    FIX
    mov eax, [esp+4]                ; hinst is where it was loaded
    mov [VA(hinst)], eax
    FIX
    push 0
    CALLI SetLastError              ; its own import, bound by winrun
.r:
    mov eax, 1
    ret 12

; int WINAPI AcornAdd(a, b)
AcornAdd:
    mov eax, [esp+4]
    add eax, [esp+8]
    ret 8

; const char *WINAPI AcornHello(void)
AcornHello:
    mov eax, VA(hello)
    FIX
    ret

hello db 'Hello from acorn.dll', 0
    align 4, db 0
AcornCount dd 0
hinst dd 0

; ---------- exports ----------
exports:
    dd 0, 0, 0, RVA(e_name), 1, 4, 4, RVA(e_funcs), RVA(e_names), RVA(e_ords)
e_funcs:
    dd RVA(AcornAdd), RVA(AcornHello), RVA(AcornCount), RVA(e_fwd)
e_names:                            ; sorted, as the format asks
    dd RVA(s_add), RVA(s_count), RVA(s_hello), RVA(s_lasterr)
e_ords:
    dw 0, 2, 1, 3
e_name db 'acorn.dll', 0
s_add db 'AcornAdd', 0
s_count db 'AcornCount', 0
s_hello db 'AcornHello', 0
s_lasterr db 'AcornLastErr', 0
e_fwd db 'KERNEL32.GetLastError', 0
exports_end:

; ---------- imports ----------
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
    dd 0, 0, 0, 0, 0
imports_end:
DLL k, SetLastError
n_k db 'KERNEL32.dll', 0

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
