; Squirrel-OS/2 — basic calculator (calc), polished for 0.3.1
; Included from pm.asm. Original code.
;
; Signed 32-bit integer expressions with precedence and parentheses,
; percentages, previous-result recall (ans), chaining from the previous
; result, overflow/syntax/division errors and a history file.
; See documentation/apps/calculators.md.

CALC_LINE     equ 60

run_calc:
    call cls
    mov esi, [lstr+LS_CALC*4]   ; title in the current language (1.0.6)
    call puts
    mov esi, calc_banner
    call puts
    mov esi, calc_help
    call puts
.prompt:
    mov esi, calc_prompt
    call puts
    call calc_readline
    jc .quit                    ; Esc
    mov esi, calc_line
    call calc_skip
    cmp byte [esi], 0
    je .prompt
    mov edi, calc_kw_quit
    call streq
    je .quit
    mov edi, calc_kw_q
    call streq
    je .quit
    mov edi, calc_kw_clear
    call streq
    je .clear
    mov edi, calc_kw_hist
    call streq
    je .hist
    call calc_line_eval
    jc .error
    mov [calc_ans], eax
    inc dword [calc_count]
    mov esi, calc_eq
    call puts
    mov eax, [calc_ans]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    call calc_log
    jmp .prompt
.error:
    mov esi, calc_errpre
    call puts
    mov esi, [calc_errmsg]
    call puts
    cmp dword [calc_errmsg], calc_e_syntax
    jne .errnl
    mov eax, [calc_errpos]
    sub eax, calc_line
    inc eax                     ; 1-based column
    call itoa
    mov esi, num_buf
    call puts
.errnl:
    mov al, 10
    call putc
    jmp .prompt
.clear:
    mov dword [calc_ans], 0
    mov dword [calc_count], 0
    mov esi, calc_cleared
    call puts
    jmp .prompt
.hist:
    mov esi, calc_histname
    call fs_cat
    jmp .prompt
.quit:
    call app_home
    xor eax, eax
    ret

; Reads a line into calc_line with echo and Backspace. CF set on Esc.
calc_readline:
    xor ecx, ecx
    cmp byte [in_on], 0
    jne .redir
.k:
    mov byte [calc_line+ecx], 0
    call fb_waitkey
    cmp al, 0x01
    je .esc
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .bs
    call kbd_ascii
    test al, al
    jz .k
    cmp ecx, CALC_LINE
    jae .k
    mov [calc_line+ecx], al
    inc ecx
    call putc
    jmp .k
.bs:
    test ecx, ecx
    jz .k
    dec ecx
    mov al, 8
    call putc
    jmp .k
.enter:
    mov al, 10
    call putc
    clc
    ret
.esc:
    stc
    ret
.redir:                         ; a line from redirected input, echoed
    mov byte [calc_line+ecx], 0
    call in_getc
    cmp eax, -1
    je .rend
    cmp al, 13
    je .redir
    cmp al, 10
    je .enter
    cmp ecx, CALC_LINE
    jae .redir
    mov [calc_line+ecx], al
    inc ecx
    call putc
    jmp .redir
.rend:                          ; end of input: last line, then quit
    test ecx, ecx
    jz .esc
    jmp .enter

; Evaluates calc_line -> eax, or CF with calc_errmsg / calc_errpos set.
; A line starting with + * / % (or "- ") continues from ans.
calc_line_eval:
    mov esi, calc_line
    call calc_skip
    mov al, [esi]
    cmp al, '*'
    je .chain_term
    cmp al, '/'
    je .chain_term
    cmp al, '%'
    je .chain_term
    cmp al, '+'
    je .chain_expr
    cmp al, '-'
    jne .fresh
    cmp byte [esi+1], ' '
    je .chain_expr
.fresh:
    call calc_expr
    jc .r
    jmp .end
.chain_term:
    mov eax, [calc_ans]
    call calc_term_cont
    jc .r
    call calc_expr_cont
    jc .r
    jmp .end
.chain_expr:
    mov eax, [calc_ans]
    call calc_expr_cont
    jc .r
.end:
    call calc_skip
    cmp byte [esi], 0
    jne calc_syntax
    clc
.r:
    ret

; ---------- recursive descent: esi = cursor, eax = value, CF = error ----------
; expr   := term { (+|-) term }
; term   := factor { (*|/|%) factor }
; factor := -factor | number | ans | ( expr ) , optionally followed by a
;           postfix % (a percentage of the left operand)

calc_expr:
    call calc_term
    jc .r
    cmp byte [calc_pct], 0      ; lone "15%" -> 15 / 100
    je .go
    mov ebx, 1
    mov ecx, 100
    call calc_muldiv
    jc .r
.go:
    jmp calc_expr_cont
.r:
    ret

calc_expr_cont:                 ; eax = left value
    call calc_skip
    mov dl, [esi]
    cmp dl, '+'
    je .op
    cmp dl, '-'
    je .op
    clc
    ret
.op:
    inc esi
    push eax
    push edx
    call calc_term
    pop edx
    pop ebx                     ; ebx = left, eax = right
    jc .r
    cmp byte [calc_pct], 0
    je .plain
    push edx                    ; a +/- b%  ->  a +/- a*b/100
    push ebx
    xchg eax, ebx
    mov ecx, 100
    call calc_muldiv
    pop ebx
    pop edx
    jc .r
.plain:
    cmp dl, '+'
    je .add
    sub ebx, eax
    jo calc_overflow
    mov eax, ebx
    jmp calc_expr_cont
.add:
    add eax, ebx
    jo calc_overflow
    jmp calc_expr_cont
.r:
    ret

calc_term:
    call calc_factor
    jc .r
    jmp calc_term_cont_keep
.r:
    ret

calc_term_cont:                 ; eax = left value (not a percentage)
    mov byte [calc_pct], 0
calc_term_cont_keep:            ; keeps the factor's percent flag if no op follows
    call calc_skip
    mov dl, [esi]
    cmp dl, '*'
    je .op
    cmp dl, '/'
    je .op
    cmp dl, '%'
    je .op
    clc
    ret
.op:
    inc esi
    push eax
    push edx
    call calc_factor
    pop edx
    pop ebx                     ; ebx = left, eax = right
    jc .r
    mov dh, [calc_pct]          ; right operand was a percentage
    mov byte [calc_pct], 0
    cmp dl, '*'
    je .mul
    cmp dl, '/'
    je .div
    ; binary %: a % b = a * b / 100
    xchg eax, ebx
    mov ecx, 100
    call calc_muldiv
    jc .r
    jmp calc_term_cont_keep
.mul:
    test dh, dh
    jnz .mulpct
    imul eax, ebx
    jo calc_overflow
    jmp calc_term_cont_keep
.mulpct:                        ; a * b% = a * b / 100
    xchg eax, ebx
    mov ecx, 100
    call calc_muldiv
    jc .r
    jmp calc_term_cont_keep
.div:
    test dh, dh
    mov ecx, eax                ; divisor
    mov eax, ebx
    jz .divplain
    test ecx, ecx               ; a / b% = a * 100 / b
    jz calc_div0
    mov ebx, 100
    call calc_muldiv
    jc .r
    jmp calc_term_cont_keep
.divplain:
    mov ebx, 1
    call calc_muldiv
    jc .r
    jmp calc_term_cont_keep
.r:
    ret

calc_factor:
    call calc_skip
    mov byte [calc_pct], 0
    mov al, [esi]
    cmp al, '-'
    je .neg
    cmp al, '('
    je .paren
    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .num
.word:
    mov edi, calc_kw_ans
    call calc_match
    jc calc_syntax
    mov eax, [calc_ans]
    jmp .post
.neg:
    inc esi
    call calc_factor
    jc .r
    neg eax
    jo calc_overflow
    clc
    ret                         ; keeps the inner factor's percent flag
.paren:
    inc esi
    call calc_expr
    jc .r
    call calc_skip
    cmp byte [esi], ')'
    jne calc_syntax
    inc esi
    jmp .post
.num:
    xor eax, eax
.d:
    movzx ebx, byte [esi]
    sub ebx, '0'
    cmp ebx, 9
    ja .post
    imul eax, 10
    jo calc_toolarge
    add eax, ebx
    jo calc_toolarge
    inc esi
    jmp .d
.post:
    ; a % right after a value is a postfix percent when it ends the term
    ; (followed by the end, ')' or an operator); otherwise it is binary
    push esi
    call calc_skip
    cmp byte [esi], '%'
    jne .nopct
    inc esi
    call calc_skip
    mov bl, [esi]
    test bl, bl
    jz .pct
    cmp bl, ')'
    je .pct
    cmp bl, '+'
    je .pct
    cmp bl, '-'
    je .pct
    cmp bl, '*'
    je .pct
    cmp bl, '/'
    je .pct
.nopct:
    pop esi
    clc
    ret
.pct:
    add esp, 4
    mov byte [calc_pct], 1
    clc
.r:
    ret

; eax * ebx / ecx with a 64-bit intermediate -> eax, CF on overflow or /0
calc_muldiv:
    test ecx, ecx
    jz calc_div0
    imul ebx
    jo calc_overflow            ; product must fit 32 bits before dividing
    cmp ecx, -1
    je .neg
    cdq
    idiv ecx
    clc
    ret
.neg:
    neg eax
    jo calc_overflow
    clc
    ret

calc_skip:
    cmp byte [esi], ' '
    jne .d
    inc esi
    jmp calc_skip
.d:
    ret

; edi = keyword: matches it at esi if not followed by a letter
calc_match:
    push esi
.c:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .c
.end:
    mov al, [esi]
    cmp al, 'a'
    jb .yes
    cmp al, 'z'
    jbe .no
.yes:
    add esp, 4
    clc
    ret
.no:
    pop esi
    stc
    ret

calc_syntax:
    mov [calc_errpos], esi
    mov dword [calc_errmsg], calc_e_syntax
    stc
    ret
calc_overflow:
    mov dword [calc_errmsg], calc_e_overflow
    stc
    ret
calc_toolarge:
    mov dword [calc_errmsg], calc_e_large
    stc
    ret
calc_div0:
    mov dword [calc_errmsg], calc_e_div0
    stc
    ret

; Appends "line = result" to calc.hist when a disk is mounted.
calc_log:
    pushad
    cmp byte [fs_mounted], 0
    je .out
    mov esi, calc_histname
    mov ecx, O_CREATE|O_APPEND
    call fs_open
    cmp eax, -1
    je .out
    mov ebx, eax
    mov esi, calc_line
    call strlen
    mov ecx, eax
    call fs_write
    mov esi, calc_eq_sp
    mov ecx, 3
    call fs_write
    mov eax, [calc_ans]
    call itoa
    mov esi, num_buf
    call strlen
    mov byte [esi+eax], 10      ; num_buf has room for the newline
    lea ecx, [eax+1]
    call fs_write
    call fs_close
.out:
    popad
    ret

calc_ans dd 0
calc_count dd 0
calc_pct db 0
calc_errmsg dd 0
calc_errpos dd 0
calc_line times CALC_LINE+1 db 0
calc_banner db ' (Esc to exit)', 10, 0
calc_help db 'Integers: + - * / ( )  percent: 100 + 15%  200 * 15%  200 % 15', 10
          db 'ans = last result; start with an operator to continue from it (* 2)', 10
          db 'Commands: clear  hist  q', 10, 0
calc_prompt db 'calc> ', 0
calc_eq db '= ', 0
calc_eq_sp db ' = ', 0
calc_errpre db 'Error: ', 0
calc_e_syntax db 'syntax at column ', 0
calc_e_overflow db 'overflow', 0
calc_e_large db 'number too large', 0
calc_e_div0 db 'division by zero', 0
calc_cleared db 'ans cleared', 10, 0
calc_kw_ans db 'ans', 0
calc_kw_quit db 'quit', 0
calc_kw_q db 'q', 0
calc_kw_clear db 'clear', 0
calc_kw_hist db 'hist', 0
calc_histname db '/calc.hist', 0   ; in the root, wherever calc runs (0.9.3)
