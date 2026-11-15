; Squirrel-OS/2 — shared runtime for the games (G.x). Original code.
;
; Include after sqx.inc and SQX_HEADER, in the code part of a game:
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     %include "games.inc"
;
; Every routine keeps all registers except the ones it names as results.
; The games are line-oriented: they print their board with SYS_PUTC /
; SYS_PUTS and read one command line at a time, so they work on the text
; console, through pipes and redirection, and in tools/regress.sh.

; ---------- output ----------

g_putc:                         ; al = character
    push eax
    push ebx
    movzx ebx, al
    mov eax, SYS_PUTC
    int 0x80
    pop ebx
    pop eax
    ret

g_puts:                         ; esi = ASCIIZ string
    push eax
    push ebx
    mov ebx, esi
    mov eax, SYS_PUTS
    int 0x80
    pop ebx
    pop eax
    ret

g_nl:
    push eax
    mov al, 10
    call g_putc
    pop eax
    ret

g_spaces:                       ; ecx = count (may be 0 or negative)
    push eax
    push ecx
    mov al, ' '
.l: cmp ecx, 0
    jle .d
    call g_putc
    dec ecx
    jmp .l
.d: pop ecx
    pop eax
    ret

; eax = signed number -> printed in decimal
g_putdec:
    push eax
    push ecx
    push ebx
    push edx
    push edi
    sub esp, 16
    mov edi, esp
    add edi, 15
    mov byte [edi], 0
    xor ecx, ecx
    test eax, eax
    jns .pos
    neg eax
    mov ecx, 1
.pos:
    push ecx                    ; 1 = negative
    mov ebx, 10
.dig:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .dig
    pop ecx
    test ecx, ecx
    jz .print
    dec edi
    mov byte [edi], '-'
.print:
    mov ecx, esp
    add ecx, 15
    sub ecx, edi
    push esi
    mov esi, edi
    call g_puts
    pop esi
    add esp, 16
    pop edi
    pop edx
    pop ebx
    pop ecx
    pop eax
    ret

; eax = number, ecx = field width: right-aligned decimal
g_putdec_w:
    push eax
    push ecx
    push edx
    mov edx, ecx
    ; count digits
    push eax
    xor ecx, ecx
    test eax, eax
    jns .p
    inc ecx
    neg eax
.p: push ebx
    mov ebx, 10
.c: inc ecx
    push edx
    xor edx, edx
    div ebx
    pop edx
    test eax, eax
    jnz .c
    pop ebx
    pop eax
    sub edx, ecx
    mov ecx, edx
    call g_spaces
    call g_putdec
    pop edx
    pop ecx
    pop eax
    ret

; ---------- input ----------

; Reads one line into g_line (echoed, Backspace edits). Returns eax =
; length, or -1 when the input ended (end of a redirected file) or Esc
; was pressed on an empty line. g_line is ASCIIZ, lower-cased.
G_LINEMAX equ 60
g_readline:
    push ebx
    push ecx
    push edi
    mov edi, g_line
    xor ecx, ecx
.key:
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .eof
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, 27
    je .esc
    cmp al, 8
    je .bs
    cmp al, ' '
    jb .key
    cmp ecx, G_LINEMAX
    jae .key
    cmp al, 'A'
    jb .store
    cmp al, 'Z'
    ja .store
    add al, 'a'-'A'
.store:
    mov [edi+ecx], al
    inc ecx
    call g_putc
    jmp .key
.bs:
    test ecx, ecx
    jz .key
    dec ecx
    call g_putc
    jmp .key
.esc:
    test ecx, ecx
    jnz .key
.eof:
    mov byte [edi], 0
    call g_nl
    mov eax, -1
    jmp .r
.done:
    mov byte [edi+ecx], 0
    call g_nl
    mov eax, ecx
.r: pop edi
    pop ecx
    pop ebx
    ret

; esi -> first non-blank character
g_skipsp:
.l: cmp byte [esi], ' '
    jne .r
    inc esi
    jmp .l
.r: ret

; esi = text: skips blanks, reads an unsigned decimal number.
; -> eax = number, esi past it, CF set (and esi unchanged) when none
g_parsenum:
    push ebx
    push edx
    call g_skipsp
    mov edx, esi
    xor eax, eax
    movzx ebx, byte [esi]
    sub ebx, '0'
    cmp ebx, 9
    ja .none
.l: movzx ebx, byte [esi]
    sub ebx, '0'
    cmp ebx, 9
    ja .ok
    imul eax, 10
    add eax, ebx
    inc esi
    jmp .l
.ok:
    clc
    jmp .r
.none:
    mov esi, edx
    stc
.r: pop edx
    pop ebx
    ret

; esi = text, edi = word (ASCIIZ): CF clear and esi past the word when
; the text, after blanks, starts with that word followed by a blank or
; the end; otherwise CF set and esi unchanged.
g_word:
    push eax
    push edx
    push edi
    call g_skipsp
    mov edx, esi
.l: mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, ' '
    je .yes
.no:
    mov esi, edx
    stc
    jmp .r
.yes:
    clc
.r: pop edi
    pop edx
    pop eax
    ret

; ---------- random numbers (xorshift32, seeded) ----------

; eax = seed (0 picks one from the time-stamp counter)
g_srand:
    push edx
    test eax, eax
    jnz .s
    rdtsc
    xor eax, edx
    test eax, eax
    jnz .s
    mov eax, 0x5EED1234
.s: mov [g_seed], eax
    pop edx
    ret

; -> eax = next 32-bit random number
g_rand:
    mov eax, [g_seed]
    push edx
    mov edx, eax
    shl edx, 13
    xor eax, edx
    mov edx, eax
    shr edx, 17
    xor eax, edx
    mov edx, eax
    shl edx, 5
    xor eax, edx
    mov [g_seed], eax
    pop edx
    ret

; ecx = n (> 0) -> eax = random number in 0..n-1
g_randn:
    push edx
    call g_rand
    xor edx, edx
    div ecx
    mov eax, edx
    pop edx
    ret

; edi = byte array, ecx = length: Fisher-Yates shuffle with g_rand
g_shuffle:
    push eax
    push ebx
    push ecx
    push edx
.l: cmp ecx, 1
    jbe .d
    call g_randn                ; 0..ecx-1
    dec ecx
    mov bl, [edi+ecx]
    mov dl, [edi+eax]
    mov [edi+ecx], dl
    mov [edi+eax], bl
    jmp .l
.d: pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------- self-test helpers ----------

; Compares eax with the expected value in ebx; on a mismatch prints
; "<g_name>: check <g_check> failed" once and marks the run failed.
; g_check counts the checks so a failure names the one that broke.
g_expect:
    inc dword [g_check]
    cmp eax, ebx
    je .r
    cmp byte [g_failed], 0
    jne .r
    mov byte [g_failed], 1
    push esi
    push eax
    mov esi, [g_name]
    call g_puts
    mov esi, g_m_check
    call g_puts
    mov eax, [g_check]
    call g_putdec
    mov esi, g_m_failed
    call g_puts
    pop eax
    pop esi
.r: ret

; Prints "<g_name>: PASS" or "<g_name>: FAIL" -> eax = 0 or 1 (exit code)
g_report:
    push esi
    mov esi, [g_name]
    call g_puts
    xor eax, eax
    mov esi, g_m_pass
    cmp byte [g_failed], 0
    je .p
    mov esi, g_m_fail
    inc eax
.p: call g_puts
    pop esi
    ret

g_m_check db ': check ', 0
g_m_failed db ' failed', 10, 0
g_m_pass db ': PASS', 10, 0
g_m_fail db ': FAIL', 10, 0
g_w_test db 'test', 0
g_w_gui db 'gui', 0
g_w_quit db 'q', 0
g_w_new db 'n', 0
g_w_help db '?', 0

; Common start of a game's main: esi = argument. Sets the seed from a
; number in the argument (or the clock) and returns CF set when the
; argument is "test". "gui" before the number sets g_gui to 1 (the
; graphical front end); esi is left after what was read.
g_start:
    push eax
    mov [g_name], ebx
    mov esi, [esp+12]           ; main's argument (caller's [esp+4])
    mov edi, g_w_test
    call g_word
    jnc .test
    mov byte [g_gui], 0
    mov edi, g_w_gui
    call g_word
    jc .num
    mov byte [g_gui], 1
.num:
    call g_parsenum
    jnc .seed
    xor eax, eax
.seed:
    call g_srand
    clc
    pop eax
    ret
.test:
    stc
    pop eax
    ret

; Put G_BSS after SQX_BSS in every game: the runtime's own variables.
%macro G_BSS 0
g_line resb G_LINEMAX+4
g_seed resd 1
g_check resd 1
g_name resd 1
g_failed resb 1
g_gui resb 1
alignb 4
%endmacro
