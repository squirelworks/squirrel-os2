; winreg.inc — registry emulation for winrun (P.6): the ADVAPI32 Reg*
; calls over one text file. Original code. Included by winrun.asm.
;
; The registry is the file "registry.dat" in the root of the data disk,
; one line per value: KEY|NAME|TYPE|HEXDATA, for example
;   HKCU\Software\Acorn|count|4|07000000
; A key with no values is a line with an empty name and type 0. The file
; is read on the first Reg call and written again after every change, so
; the values outlive the program. Key names compare without case.
; The predefined roots are HKCR, HKCU, HKLM and HKU; open keys are handles
; 0x7000 + n, each remembering its full path.

RG_MAX      equ 48              ; values (lines) in memory
RG_PATH     equ 64
RG_NAME     equ 32
RG_DATA     equ 64
RG_REC      equ RG_PATH + RG_NAME + 8 + RG_DATA   ; path, name, type, length, data
RG_KEYS     equ 8               ; open keys
RG_HBASE    equ 0x7000
RG_FILEMAX  equ RG_MAX*(RG_PATH+RG_NAME+16+RG_DATA*2)
ERROR_MORE_DATA equ 234

; the file into rg_recs, once
rg_load:
    cmp byte [rg_loaded], 0
    jne .r
    pushad
    mov byte [rg_loaded], 1
    mov eax, SYS_SBRK
    mov ebx, RG_FILEMAX + RG_MAX*RG_REC
    int 0x80
    cmp eax, -1
    je .done
    mov [rg_text], eax
    add eax, RG_FILEMAX
    mov [rg_recs], eax
    mov eax, SYS_OPEN
    mov ebx, rg_file
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .done
    mov ebx, eax
    push ebx
    mov eax, SYS_READ
    mov ecx, [rg_text]
    mov edx, RG_FILEMAX - 1
    int 0x80
    pop ebx
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop ecx
    cmp ecx, -1
    je .done
    mov esi, [rg_text]
    mov byte [esi+ecx], 0
    ; parse: KEY|NAME|TYPE|HEX per line
.line:
    cmp byte [esi], 0
    je .done
    mov eax, [rg_n]
    cmp eax, RG_MAX
    jae .done
    imul edi, eax, RG_REC
    add edi, [rg_recs]
    push edi
    mov ecx, RG_PATH-1
    call .field
    pop edi
    push edi
    add edi, RG_PATH
    mov ecx, RG_NAME-1
    call .field
    pop edi
    call .num                   ; the type
    mov [edi+RG_PATH+RG_NAME], eax
    xor ecx, ecx                ; the data, two hex digits a byte
.hex:
    call .digit
    jc .hd
    mov bl, al
    call .digit
    jc .hd
    shl bl, 4
    or al, bl
    cmp ecx, RG_DATA
    jae .hex
    mov [edi+RG_PATH+RG_NAME+8+ecx], al
    inc ecx
    jmp .hex
.hd:
    mov [edi+RG_PATH+RG_NAME+4], ecx
    inc dword [rg_n]
.eol:
    lodsb                       ; to the next line
    test al, al
    jz .done
    cmp al, 10
    jne .eol
    jmp .line
.done:
    popad
.r:
    ret
; esi -> up to '|', newline or the end into edi (at most ecx), past the '|'
.field:
    lodsb
    cmp al, '|'
    je .fz
    cmp al, 10
    je .fe
    test al, al
    jz .fe
    jecxz .field
    stosb
    dec ecx
    jmp .field
.fe:
    dec esi
.fz:
    mov byte [edi], 0
    ret
.num:                           ; decimal up to '|' -> eax
    xor eax, eax
.n:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .nz
    imul eax, 10
    add eax, edx
    inc esi
    jmp .n
.nz:
    cmp byte [esi], '|'
    jne .nr
    inc esi
.nr:
    ret
.digit:                         ; esi -> al = 0..15, or CF (not moved)
    movzx eax, byte [esi]
    sub al, '0'
    cmp al, 9
    jbe .dk
    movzx eax, byte [esi]
    or al, 0x20
    sub al, 'a'
    cmp al, 5
    ja .dno
    add al, 10
.dk:
    inc esi
    clc
    ret
.dno:
    stc
    ret

; every record back into the file
rg_save:
    pushad
    mov edi, [rg_text]
    test edi, edi
    jz .r
    mov esi, [rg_recs]
    xor ebp, ebp
.rec:
    cmp ebp, [rg_n]
    jae .write
    push esi
    call .str                   ; key
    mov al, '|'
    stosb
    add esi, RG_PATH
    call .str                   ; name
    mov al, '|'
    stosb
    pop esi
    push esi
    mov eax, [esi+RG_PATH+RG_NAME]
    call .dec
    mov al, '|'
    stosb
    mov ecx, [esi+RG_PATH+RG_NAME+4]
    lea esi, [esi+RG_PATH+RG_NAME+8]
.h:
    jecxz .hd
    lodsb
    push eax
    shr al, 4
    call .hx
    pop eax
    call .hx
    dec ecx
    jmp .h
.hd:
    mov al, 10
    stosb
    pop esi
    add esi, RG_REC
    inc ebp
    jmp .rec
.write:
    mov ecx, edi
    sub ecx, [rg_text]
    push ecx
    mov eax, SYS_OPEN
    mov ebx, rg_file
    mov ecx, O_CREATE|O_TRUNC
    int 0x80
    pop edx
    cmp eax, -1
    je .r
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, [rg_text]
    int 0x80
    mov eax, SYS_CLOSE
    int 0x80
.r:
    popad
    ret
.str:                           ; ASCIIZ at esi -> edi (esi kept)
    push esi
.s:
    lodsb
    test al, al
    jz .sz
    stosb
    jmp .s
.sz:
    pop esi
    ret
.dec:                           ; eax -> decimal at edi
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d1:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d1
.d2:
    pop eax
    add al, '0'
    stosb
    loop .d2
    pop edx
    pop ecx
    pop ebx
    ret
.hx:
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .hs
    add al, 'a' - '0' - 10
.hs:
    stosb
    ret

; eax = an open key or a root, esi = a subkey (or 0) -> rg_path holds the
; full path; CF if the handle is unknown
rg_build:
    push edi
    push esi
    push ecx
    mov edi, rg_path
    cmp eax, 0x80000000
    jb .open
    sub eax, 0x80000000
    cmp eax, 3
    ja .bad
    mov esi, [rg_roots+eax*4]
    jmp .copy
.open:
    sub eax, RG_HBASE
    cmp eax, RG_KEYS
    jae .bad
    imul esi, eax, RG_PATH
    add esi, rg_keys
    cmp byte [esi], 0
    je .bad
.copy:
    mov ecx, RG_PATH-1
.c:
    lodsb
    test al, al
    jz .sub
    stosb
    loop .c
.sub:
    mov esi, [esp+4]            ; the subkey
    test esi, esi
    jz .end
    cmp byte [esi], 0
    je .end
    jecxz .end
    mov al, '\'
    stosb
    dec ecx
.s:
    jecxz .end
    lodsb
    test al, al
    jz .end
    stosb
    dec ecx
    jmp .s
.end:
    mov byte [edi], 0
    pop ecx
    pop esi
    pop edi
    clc
    ret
.bad:
    pop ecx
    pop esi
    pop edi
    stc
    ret

; esi, edi = ASCIIZ -> ZF when equal, ignoring case
rg_same:
    push esi
    push edi
    push eax
.c:
    mov al, [esi]
    mov ah, [edi]
    cmp al, 'A'
    jb .a
    cmp al, 'Z'
    ja .a
    or al, 0x20
.a:
    cmp ah, 'A'
    jb .b
    cmp ah, 'Z'
    ja .b
    or ah, 0x20
.b:
    cmp al, ah
    jne .r
    test al, al
    jz .r
    inc esi
    inc edi
    jmp .c
.r:
    pop eax
    pop edi
    pop esi
    ret

; rg_path, esi = value name -> edi = its record, or CF
rg_find:
    push ecx
    push ebx
    mov ebx, esi
    mov edi, [rg_recs]
    xor ecx, ecx
.f:
    cmp ecx, [rg_n]
    jae .no
    mov esi, rg_path
    call rg_same
    jne .n
    push edi
    add edi, RG_PATH
    mov esi, ebx
    call rg_same
    pop edi
    je .yes
.n:
    add edi, RG_REC
    inc ecx
    jmp .f
.no:
    mov esi, ebx
    pop ebx
    pop ecx
    stc
    ret
.yes:
    mov esi, ebx
    pop ebx
    pop ecx
    clc
    ret

; rg_path -> ZF when some record lives in that key
rg_key_exists:
    push esi
    push edi
    push ecx
    mov edi, [rg_recs]
    xor ecx, ecx
.f:
    cmp ecx, [rg_n]
    jae .no
    mov esi, rg_path
    call rg_same
    je .r
    add edi, RG_REC
    inc ecx
    jmp .f
.no:
    or ecx, 1                   ; ZF clear
.r:
    pop ecx
    pop edi
    pop esi
    ret

; rg_path -> eax = a new handle for it, or 0 when they are all open
rg_open_handle:
    push esi
    push edi
    push ecx
    mov edi, rg_keys
    xor eax, eax
.f:
    cmp byte [edi], 0
    je .free
    add edi, RG_PATH
    inc eax
    cmp eax, RG_KEYS
    jb .f
    xor eax, eax
    jmp .r
.free:
    add eax, RG_HBASE
    mov esi, rg_path
    mov ecx, RG_PATH
    rep movsb
.r:
    pop ecx
    pop edi
    pop esi
    ret

; esi = name, rg_path -> edi = a new record (path and name set), or CF
rg_new:
    mov eax, [rg_n]
    cmp eax, RG_MAX
    jae .no
    inc dword [rg_n]
    imul edi, eax, RG_REC
    add edi, [rg_recs]
    push esi
    push edi
    mov esi, rg_path
    mov ecx, RG_PATH
    rep movsb
    pop edi
    pop esi
    push esi
    push edi
    add edi, RG_PATH
    mov ecx, RG_NAME-1
.n:
    lodsb
    stosb
    test al, al
    jz .nd
    loop .n
    mov byte [edi], 0
.nd:
    pop edi
    pop esi
    mov dword [edi+RG_PATH+RG_NAME], 0
    mov dword [edi+RG_PATH+RG_NAME+4], 0
    clc
    ret
.no:
    stc
    ret

; LONG RegOpenKeyExA(hKey, subkey, options, sam, *result)
a_RegOpenKeyExA:
    pushad
    call rg_load
    mov eax, PA(0)
    mov esi, PA(1)
    call rg_build
    jc .bad
    mov esi, PA(1)              ; no subkey: the key itself, always there
    test esi, esi
    jz .there
    cmp byte [esi], 0
    je .there
    call rg_key_exists
    jne .nf
.there:
    call rg_open_handle
    test eax, eax
    jz .bad
    mov ecx, PA(4)
    mov [ecx], eax
    mov dword [esp+28], 0
    popad
    ret 20
.nf:
    mov dword [esp+28], E_FILE_NOT_FOUND
    popad
    ret 20
.bad:
    mov dword [esp+28], E_INVALID_HANDLE
    popad
    ret 20

; LONG RegCreateKeyExA(hKey, subkey, reserved, class, options, sam,
;                      security, *result, *disposition)
a_RegCreateKeyExA:
    pushad
    call rg_load
    mov eax, PA(0)
    mov esi, PA(1)
    call rg_build
    jc .bad
    mov ebx, 2                  ; REG_OPENED_EXISTING_KEY
    call rg_key_exists
    je .open
    mov esi, rg_empty           ; a key with no values: its marker line
    call rg_new
    jc .bad
    call rg_save
    mov ebx, 1                  ; REG_CREATED_NEW_KEY
.open:
    call rg_open_handle
    test eax, eax
    jz .bad
    mov ecx, PA(7)
    mov [ecx], eax
    mov ecx, PA(8)
    jecxz .nd
    mov [ecx], ebx
.nd:
    mov dword [esp+28], 0
    popad
    ret 36
.bad:
    mov dword [esp+28], E_INVALID_HANDLE
    popad
    ret 36

; LONG RegCloseKey(hKey)
a_RegCloseKey:
    mov eax, [esp+4]
    sub eax, RG_HBASE
    cmp eax, RG_KEYS
    jae .r
    imul eax, RG_PATH
    mov byte [rg_keys+eax], 0
.r:
    xor eax, eax
    ret 4

; LONG RegSetValueExA(hKey, name, reserved, type, *data, size)
a_RegSetValueExA:
    pushad
    call rg_load
    mov eax, PA(0)
    xor esi, esi
    call rg_build
    jc .bad
    mov esi, PA(1)
    test esi, esi
    jnz .nm
    mov esi, rg_empty           ; the default value
.nm:
    call rg_find
    jnc .have
    call rg_new
    jc .bad
.have:
    mov eax, PA(3)
    mov [edi+RG_PATH+RG_NAME], eax
    mov ecx, PA(5)
    cmp ecx, RG_DATA
    jbe .len
    mov ecx, RG_DATA
.len:
    mov [edi+RG_PATH+RG_NAME+4], ecx
    mov esi, PA(4)
    add edi, RG_PATH+RG_NAME+8
    rep movsb
    call rg_save
    mov dword [esp+28], 0
    popad
    ret 24
.bad:
    mov dword [esp+28], E_INVALID_HANDLE
    popad
    ret 24

; LONG RegQueryValueExA(hKey, name, reserved, *type, *data, *size)
a_RegQueryValueExA:
    pushad
    call rg_load
    mov eax, PA(0)
    xor esi, esi
    call rg_build
    jc .bad
    mov esi, PA(1)
    test esi, esi
    jnz .nm
    mov esi, rg_empty
.nm:
    call rg_find
    jc .nf
    mov ecx, PA(3)
    jecxz .nt
    mov eax, [edi+RG_PATH+RG_NAME]
    mov [ecx], eax
.nt:
    mov eax, [edi+RG_PATH+RG_NAME+4]
    mov ebx, PA(5)
    mov edx, PA(4)
    test edx, edx
    jz .size                    ; no buffer: the size alone
    test ebx, ebx
    jz .bad
    cmp eax, [ebx]
    ja .more
    mov ecx, eax
    lea esi, [edi+RG_PATH+RG_NAME+8]
    mov edi, edx
    rep movsb
.size:
    test ebx, ebx
    jz .ok
    mov [ebx], eax
.ok:
    mov dword [esp+28], 0
    popad
    ret 24
.more:
    mov [ebx], eax
    mov dword [esp+28], ERROR_MORE_DATA
    popad
    ret 24
.nf:
    mov dword [esp+28], E_FILE_NOT_FOUND
    popad
    ret 24
.bad:
    mov dword [esp+28], E_INVALID_HANDLE
    popad
    ret 24

; LONG RegDeleteValueA(hKey, name)
a_RegDeleteValueA:
    pushad
    call rg_load
    mov eax, PA(0)
    xor esi, esi
    call rg_build
    jc .bad
    mov esi, PA(1)
    call rg_find
    jc .nf
    ; the last record moves into its place
    mov esi, [rg_n]
    dec esi
    mov [rg_n], esi
    imul esi, RG_REC
    add esi, [rg_recs]
    mov ecx, RG_REC
    rep movsb
    call rg_save
    mov dword [esp+28], 0
    popad
    ret 8
.nf:
    mov dword [esp+28], E_FILE_NOT_FOUND
    popad
    ret 8
.bad:
    mov dword [esp+28], E_INVALID_HANDLE
    popad
    ret 8

%macro A 1
    dd a_%1
    db %str(%1), 0
%endmacro
%macro WINREG_TABLE 0
    A RegOpenKeyExA
    A RegCreateKeyExA
    A RegCloseKey
    A RegSetValueExA
    A RegQueryValueExA
    A RegDeleteValueA
%endmacro

rg_file db 'registry.dat', 0
rg_empty db 0
rg_roots dd rg_hkcr, rg_hkcu, rg_hklm, rg_hku
rg_hkcr db 'HKCR', 0
rg_hkcu db 'HKCU', 0
rg_hklm db 'HKLM', 0
rg_hku db 'HKU', 0

%macro WINREG_BSS 0
alignb 4
rg_text resd 1
rg_recs resd 1
rg_n resd 1
rg_path resb RG_PATH
rg_keys resb RG_KEYS*RG_PATH
rg_loaded resb 1
%endmacro
