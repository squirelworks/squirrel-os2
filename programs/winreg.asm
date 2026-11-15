; winreg — a Win32 console program, PE32 written by hand (P.6). Original
; code. Exercises winrun's registry emulation (ADVAPI32 over registry.dat):
; RegCreateKeyExA, Set/Query/DeleteValue, ERROR_MORE_DATA, a missing key,
; and values that outlive the program.
;   run winreg          writes HKCU\Software\Acorn, checks it, "winreg: PASS"
;   run winreg again    reads count back and stores it plus one
; Build: nasm -f bin winreg.asm -o winreg
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

HKCU equ 0x80000001

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
    CALLI GetCommandLineA           ; "again" anywhere: the persistence run
    mov esi, eax
.scan:
    cmp byte [esi], 0
    je .first
    cmp dword [esi], 'agai'
    je .again
    inc esi
    jmp .scan

.first:
    mov byte [VA(step)], 'a'        ; create the key (new or existing)
    FIXB 1
    PUSHV disp
    PUSHV hkey
    push 0
    push 0xF003F                    ; KEY_ALL_ACCESS
    push 0
    push 0
    push 0
    PUSHV keyname
    push HKCU
    CALLI RegCreateKeyExA
    test eax, eax
    jnz fail
    mov eax, [VA(disp)]
    FIX
    cmp eax, 1
    jb fail
    cmp eax, 2
    ja fail
    mov byte [VA(step)], 'b'        ; a DWORD and a string
    FIXB 1
    mov dword [VA(dval)], 1
    FIXB 4
    push 4
    PUSHV dval
    push 4                          ; REG_DWORD
    push 0
    PUSHV v_count
    push dword [VA(hkey)]
    FIX
    CALLI RegSetValueExA
    test eax, eax
    jnz fail
    push str_len
    PUSHV sval
    push 1                          ; REG_SZ
    push 0
    PUSHV v_name
    push dword [VA(hkey)]
    FIX
    CALLI RegSetValueExA
    test eax, eax
    jnz fail
    mov byte [VA(step)], 'c'        ; read the string back
    FIXB 1
    mov dword [VA(vsize)], 64
    FIXB 4
    PUSHV vsize
    PUSHV buf
    PUSHV vtype
    push 0
    PUSHV v_name
    push dword [VA(hkey)]
    FIX
    CALLI RegQueryValueExA
    test eax, eax
    jnz fail
    cmp dword [VA(vtype)], 1
    FIXB 1
    jne fail
    cmp dword [VA(vsize)], str_len
    FIXB 1
    jne fail
    cmp dword [VA(buf)], 'Squi'
    FIXB 4
    jne fail
    mov byte [VA(step)], 'd'        ; too small a buffer: ERROR_MORE_DATA
    FIXB 1
    mov dword [VA(vsize)], 3
    FIXB 4
    PUSHV vsize
    PUSHV buf
    push 0
    push 0
    PUSHV v_name
    push dword [VA(hkey)]
    FIX
    CALLI RegQueryValueExA
    cmp eax, 234
    jne fail
    cmp dword [VA(vsize)], str_len
    FIXB 1
    jne fail
    mov byte [VA(step)], 'e'        ; delete a value, then it is gone
    FIXB 1
    PUSHV v_name
    push dword [VA(hkey)]
    FIX
    CALLI RegDeleteValueA
    test eax, eax
    jnz fail
    PUSHV vsize
    push 0
    push 0
    push 0
    PUSHV v_name
    push dword [VA(hkey)]
    FIX
    CALLI RegQueryValueExA
    cmp eax, 2                      ; ERROR_FILE_NOT_FOUND
    jne fail
    push dword [VA(hkey)]
    FIX
    CALLI RegCloseKey
    mov byte [VA(step)], 'f'        ; a key that is not there
    FIXB 1
    PUSHV hkey
    push 0x20019                    ; KEY_READ
    push 0
    PUSHV nokey
    push HKCU
    CALLI RegOpenKeyExA
    cmp eax, 2
    jne fail
    jmp pass

.again:
    mov byte [VA(step)], 'g'        ; open the key again, count 1 -> 2
    FIXB 1
    PUSHV hkey
    push 0x20019
    push 0
    PUSHV keyname
    push HKCU
    CALLI RegOpenKeyExA
    test eax, eax
    jnz fail
    mov dword [VA(vsize)], 4
    FIXB 4
    PUSHV vsize
    PUSHV dval
    PUSHV vtype
    push 0
    PUSHV v_count
    push dword [VA(hkey)]
    FIX
    CALLI RegQueryValueExA
    test eax, eax
    jnz fail
    cmp dword [VA(vtype)], 4
    FIXB 1
    jne fail
    inc dword [VA(dval)]
    FIX
    push 4
    PUSHV dval
    push 4
    push 0
    PUSHV v_count
    push dword [VA(hkey)]
    FIX
    CALLI RegSetValueExA
    test eax, eax
    jnz fail
    push dword [VA(dval)]
    FIX
    PUSHV countfmt
    CALLI printf
    add esp, 8
    push dword [VA(hkey)]
    FIX
    CALLI RegCloseKey
pass:
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

keyname db 'Software\Acorn', 0
nokey db 'Software\NoSuchKey', 0
v_count db 'count', 0
v_name db 'name', 0
sval db 'Squirrel', 0
str_len equ $ - sval
countfmt db 'winreg: count %d', 10, 0
passmsg db 'winreg: PASS', 10, 0
failmsg db 'winreg: FAIL '
step db '?', 10, 0
    align 4, db 0
hkey dd 0
disp dd 0
dval dd 0
vtype dd 0
vsize dd 0
buf times 64 db 0

; ---------- imports: three DLLs ----------
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
    dd 0, 0, 0, 0, 0
imports_end:
DLL k, ExitProcess, GetCommandLineA
DLL m, printf
DLL a, RegCreateKeyExA, RegOpenKeyExA, RegCloseKey, RegSetValueExA, RegQueryValueExA, RegDeleteValueA
n_k db 'KERNEL32.dll', 0
n_m db 'msvcrt.dll', 0
n_a db 'ADVAPI32.dll', 0

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
