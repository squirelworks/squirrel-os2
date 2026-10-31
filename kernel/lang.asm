; Squirrel-OS/2 — localization runtime (0.8.1)
; Included from pm.asm. Original code.
;
; The texts of localization/<code>/strings.txt are built into the kernel
; (strings.inc, made by tools/mkstrings.py). lstr holds the current
; language's text for every key, with English where a translation is
; missing; code prints [lstr+LS_<KEY>*4]. "lang <code>" switches.
; See documentation/kernel/localization.md.

%include "strings.inc"

; eax = language index: fills lstr
lang_select:
    pushad
    mov [lang_cur], eax
    mov esi, [lang_tables+eax*4]
    mov ebx, [lang_tables]          ; English
    xor ecx, ecx
.k:
    mov eax, [esi+ecx*4]
    test eax, eax
    jnz .have
    mov eax, [ebx+ecx*4]
.have:
    mov [lstr+ecx*4], eax
    inc ecx
    cmp ecx, LS_COUNT
    jb .k
    popad
    ret

; esi = language code -> CF if there is no such language
lang_set_code:
    pushad
    mov edi, lang_codes
    xor edx, edx
.l:
    call streq                  ; (clobbers eax)
    je .found
    add edi, 4
    inc edx
    cmp edx, LANG_COUNT
    jb .l
    popad
    stc
    ret
.found:
    mov eax, edx
    call lang_select
    popad
    clc
    ret

; The banner's first line in the current language, the version, then the
; command list in the current language.
show_banner:
    push eax
    push esi
    mov esi, [lstr+LS_BANNER*4]
    call puts
    mov esi, banner_rest
.ver:
    lodsb
    call putc
    cmp al, 10
    jne .ver
    mov esi, [lstr+LS_COMMANDS*4]
    call puts
    pop esi
    pop eax
    ret

; lset dest, key: point the dword dest at a key's text; flags kept
%macro lset 2
    push eax
    mov eax, [lstr+%2*4]
    mov [%1], eax
    pop eax
%endmacro

; lcmp dest, key: compare the dword dest with a key's text
%macro lcmp 2
    push eax
    mov eax, [lstr+%2*4]
    cmp [%1], eax
    pop eax
%endmacro

; esi = key's text: prints it and a newline
lputs_nl:
    call puts
    push eax
    mov al, 10
    call putc
    pop eax
    ret

; lang [code]: without a code, shows the current and the available ones
cmd_lang_run:
    call next_word
    cmp byte [esi], 0
    je .show
    call lang_set_code
    jnc .r
    mov esi, [lstr+LS_LANG_BAD*4]
    call puts
    mov esi, lang_m_open
    call puts
    jmp .list
.show:
    mov esi, [lstr+LS_LANG_NOW*4]
    call puts
    mov al, ' '
    call putc
    mov eax, [lang_cur]
    lea esi, [lang_codes+eax*4]
    call puts
    mov esi, lang_m_open
    call puts
.list:
    xor ecx, ecx
.c:
    lea esi, [lang_codes+ecx*4]
    call puts
    inc ecx
    cmp ecx, LANG_COUNT
    jae .end
    mov al, ' '
    call putc
    jmp .c
.end:
    mov esi, lang_m_close
    call puts
.r:
    ret

lang_m_open db ' (', 0

lang_m_close db ')', 10, 0

align 4
lang_cur dd 0
lstr times LS_COUNT dd 0
