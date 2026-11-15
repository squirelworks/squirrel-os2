; winhello — a Win32 console program, PE32 written by hand (P.5).
; Original code. Exercises winrun: the PE headers, one section, base
; relocations (ImageBase 0x400000 is never where winrun puts it), KERNEL32
; imports, console and file handles, the heap and GetLastError.
;   run winhello            ->  Hello from Win32 land! ... winhello: PASS
;   run winhello beep       ->  calls Beep, which winrun does not offer
; Build: nasm -f bin winhello.asm -o winhello
BITS 32

IMAGEBASE   equ 0x400000
SECT_RVA    equ 0x1000
%define RVA(x) ((x) - sect + SECT_RVA)
%define VA(x)  (RVA(x) + IMAGEBASE)

; FIX after an instruction whose last four bytes are an absolute address
; records the spot for the base relocation table.
%assign NFIX 0
%macro FIX 0
fix_%[NFIX] equ $ - 4
%assign NFIX NFIX+1
%endmacro
; CALLK name: call a KERNEL32 import through the IAT
%macro CALLK 1
    call [VA(iat_%1)]
    FIX
%endmacro
%macro STEP 1
    mov byte [VA(step)], %1
    FIX_AT 2
%endmacro
%macro FIX_AT 1                 ; the address sits %1 bytes into the
fix_%[NFIX] equ $ - 7 + %1      ; 7-byte "mov byte [abs], imm8"
%assign NFIX NFIX+1
%endmacro

; ---------- DOS header and stub-less PE headers ----------
mz:
    dw 'MZ'
    times 0x3A db 0
    dd pe - mz                      ; e_lfanew
pe:
    db 'PE', 0, 0
    dw 0x14C                        ; i386
    dw 1                            ; one section
    dd 0, 0, 0                      ; time stamp, symbols
    dw opt_end - opt                ; SizeOfOptionalHeader
    dw 0x0102                       ; executable, 32-bit machine
opt:
    dw 0x10B                        ; PE32
    db 1, 0                         ; linker version
    dd sect_end - sect, 0, 0        ; code, data, bss sizes
    dd RVA(start)                   ; AddressOfEntryPoint
    dd SECT_RVA, SECT_RVA           ; BaseOfCode, BaseOfData
    dd IMAGEBASE
    dd 0x1000, 0x200                ; section and file alignment
    dw 4, 0, 0, 0, 4, 0             ; OS, image, subsystem versions
    dd 0
    dd SECT_RVA + ((sect_end - sect + 0xFFF) & ~0xFFF)  ; SizeOfImage
    dd sect - mz                    ; SizeOfHeaders
    dd 0                            ; checksum
    dw 3                            ; IMAGE_SUBSYSTEM_WINDOWS_CUI
    dw 0x0040                       ; DLL characteristics: can move
    dd 0x100000, 0x1000, 0x100000, 0x1000   ; stack and heap
    dd 0, 16                        ; loader flags, NumberOfRvaAndSizes
    dd 0, 0                         ; 0 export
    dd RVA(imports), imports_end - imports   ; 1 import
    dd 0, 0, 0, 0, 0, 0             ; 2 resource, 3 exception, 4 security
    dd RVA(relocs), relocs_end - relocs      ; 5 base relocations
    times 10 dd 0, 0                ; 6..15
opt_end:
    db '.text', 0, 0, 0
    dd sect_end - sect              ; VirtualSize
    dd SECT_RVA
    dd sect_file_end - sect         ; SizeOfRawData
    dd sect - mz                    ; PointerToRawData
    dd 0, 0, 0
    dd 0xE0000060                   ; code, data, read, write, execute
    times 0x200 - ($ - mz) db 0

; ---------- the one section ----------
sect:
start:
    STEP 'a'                        ; console output
    push -11                        ; STD_OUTPUT_HANDLE
    CALLK GetStdHandle
    cmp eax, -1
    je fail
    mov ebx, eax
    push 0
    push VA(written)
    FIX
    push hello_len
    push VA(hello)
    FIX
    push ebx
    CALLK WriteFile
    test eax, eax
    jz fail
    mov eax, [VA(written)]
    FIX
    cmp eax, hello_len
    jne fail
    STEP 'b'                        ; relocations: our own address
    push 0
    CALLK GetModuleHandleA
    mov edx, IMAGEBASE
    FIX
    cmp eax, edx
    jne fail
    cmp eax, IMAGEBASE
    je fail                         ; winrun always moves the image
    STEP 'c'                        ; the command line
    CALLK GetCommandLineA
    mov esi, eax
    push VA(cmdmsg)
    FIX
    call print
    push esi
    call print
    push VA(nl)
    FIX
    call print
    STEP 'd'                        ; a file: create, write, close
    push 0
    push 0
    push 2                          ; CREATE_ALWAYS
    push 0
    push 0
    push 0x40000000                 ; GENERIC_WRITE
    push VA(fname)
    FIX
    CALLK CreateFileA
    cmp eax, -1
    je fail
    mov ebx, eax
    push 0
    push VA(written)
    FIX
    push ftext_len
    push VA(ftext)
    FIX
    push ebx
    CALLK WriteFile
    test eax, eax
    jz fail
    push ebx
    CALLK CloseHandle
    test eax, eax
    jz fail
    STEP 'e'                        ; open it again, seek, read
    push 0
    push 0
    push 3                          ; OPEN_EXISTING
    push 0
    push 0
    push 0x80000000                 ; GENERIC_READ
    push VA(fname)
    FIX
    CALLK CreateFileA
    cmp eax, -1
    je fail
    mov ebx, eax
    push 0                          ; FILE_BEGIN
    push 0
    push 6
    push ebx
    CALLK SetFilePointer
    cmp eax, 6
    jne fail
    push 0
    push VA(written)
    FIX
    push 64
    push VA(buf)
    FIX
    push ebx
    CALLK ReadFile
    test eax, eax
    jz fail
    cmp dword [VA(written)], ftext_len - 6
    FIX_AT 2
    jne fail
    mov esi, VA(buf)
    FIX
    mov edi, VA(ftext) + 6
    FIX
    mov ecx, ftext_len - 6
    repe cmpsb
    jne fail
    push ebx
    CALLK CloseHandle
    STEP 'f'                        ; a missing file and GetLastError
    push 0
    push 0
    push 3
    push 0
    push 0
    push 0x80000000
    push VA(missing)
    FIX
    CALLK CreateFileA
    cmp eax, -1
    jne fail
    CALLK GetLastError
    cmp eax, 2                      ; ERROR_FILE_NOT_FOUND
    jne fail
    STEP 'g'                        ; heap and pages
    CALLK GetProcessHeap
    push 100
    push 0
    push eax
    CALLK HeapAlloc
    test eax, eax
    jz fail
    cmp dword [eax+96], 0
    jne fail
    mov dword [eax+96], -1
    push 4                          ; PAGE_READWRITE
    push 0x3000                     ; MEM_COMMIT | MEM_RESERVE
    push 5000
    push 0
    CALLK VirtualAlloc
    test eax, eax
    jz fail
    test eax, 0xFFF
    jnz fail
    mov dword [eax+4996], 1
    STEP 'h'                        ; "beep" calls an import with no shim
    CALLK GetCommandLineA
.word:
    cmp byte [eax], 0
    je .pass
    cmp dword [eax], 'beep'
    je .beep
    inc eax
    jmp .word
.beep:
    push 100
    push 440
    CALLK Beep
    jmp fail
.pass:
    push VA(pass)
    FIX
    call print
    push 0
    CALLK ExitProcess
fail:
    push VA(failmsg)
    FIX
    call print
    push 1
    CALLK ExitProcess

; print(ASCIIZ) to standard output through WriteFile; keeps registers
print:
    pushad
    push -11
    CALLK GetStdHandle
    mov esi, [esp+36]
    xor ecx, ecx
.len:
    cmp byte [esi+ecx], 0
    je .go
    inc ecx
    jmp .len
.go:
    push 0
    push 0
    push ecx
    push esi
    push eax
    CALLK WriteFile
    popad
    ret 4

hello db 'Hello from Win32 land!', 10
hello_len equ $ - hello
cmdmsg db 'command line: ', 0
nl db 10, 0
fname db 'win.txt', 0
missing db 'nosuchfile', 0
ftext db 'Windows wrote this', 10
ftext_len equ $ - ftext
pass db 'winhello: PASS', 10, 0
failmsg db 'winhello: FAIL '
step db '?', 10, 0
align 4
written dd 0
buf times 64 db 0

; ---------- imports: KERNEL32.dll ----------
%macro IMPORTS 0-*
    align 4
imports:
    dd RVA(ilt), 0, 0, RVA(dllname), RVA(iat)
    dd 0, 0, 0, 0, 0
imports_end:
ilt:
%rep %0
    dd RVA(hn_%1)
%rotate 1
%endrep
    dd 0
iat:
%rep %0
iat_%1: dd RVA(hn_%1)
%rotate 1
%endrep
    dd 0
%rep %0
hn_%1: dw 0
    db %str(%1), 0
    align 2, db 0
%rotate 1
%endrep
dllname db 'KERNEL32.dll', 0
%endmacro
IMPORTS GetStdHandle, WriteFile, GetModuleHandleA, GetCommandLineA, CreateFileA, CloseHandle, SetFilePointer, ReadFile, GetLastError, GetProcessHeap, HeapAlloc, VirtualAlloc, Beep, ExitProcess

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
