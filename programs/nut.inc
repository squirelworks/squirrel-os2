; Squirrel-OS/2 — Nut, a small scripting language (C.8, OS2-APPS).
; Original code. Included by programs/notebook.asm; see
; documentation/apps/nut.md for the language.
;
;   x = 3                      # a variable (let x = 3 too); # starts a comment
;   print "x is", x * 2        # values separated by spaces
;   if x > 2 then ... elif ... else ... end
;   while x < 10 do ... end    for i = 1 to 10 step 2 do ... end
;   fn sq(a) return a * a end  break  return
;   numbers (doubles) and strings ("text"; + joins a string and anything)
;   and or not  == != < > <= >=  + - * / % ^   true false
;   sin cos tan asin acos atan sqrt abs ln exp floor ceil round min max
;   len str num rnd  and pi
;
; Host interface:
;   nut_init       once: memory (CF if there is none)
;   nut_reset      forget every variable, function and output
;   nut_run        esi = program text -> CF on an error (nut_errmsg);
;                  print output is added to nut_out
;   nut_compile    esi = expression text -> eax = its first token, or CF
;   nut_eval_x     eax = first token, qword [nut_x] = x -> st0, or CF
;                  (x is a global variable while it runs)
;   nut_eval       eax = first token -> eax = V_NUM (st0) or V_STR
;                  (edx, ecx), or CF
;   nut_setvar     esi, ecx = a name, eax = V_NUM (st0) or V_STR (edx,
;                  ebx = length) -> a global variable, or CF
;   nut_getnum     esi, ecx = a name -> st0 = that global number, or CF
;   n_numtext      st0 (popped) -> esi = its text (the FPU is reset)
; Values are numbers in st0 or strings (edx = text, ecx = length); eax
; says which (V_NUM, V_STR). The left side of an operator is spilled to
; the CPU stack while the right side is worked out, so the FPU never
; holds more than a few values.

NUT_TOKS    equ 16384           ; tokens of a whole notebook run
NUT_ATOMS   equ 32768           ; names and string literals, copied
NUT_SHEAP   equ 131072          ; strings made while running
NUT_OUT     equ 16384           ; print output
NUT_VARS    equ 256
NUT_FNS     equ 64
NUT_PARAMS  equ 8
NUT_STEPS   equ 500000
NUT_DEPTH   equ 100

TK_EOF      equ 0
TK_NL       equ 1
TK_NUM      equ 2
TK_STR      equ 3
TK_NAME     equ 4
TK_OP       equ 5
TK_KW       equ 6
; token: +0 type, +1 op / keyword, +2 line (word), +4 text, +8 length or
; the number (qword)
TK_SIZE     equ 16

OP_PLUS     equ 1
OP_MINUS    equ 2
OP_STAR     equ 3
OP_SLASH    equ 4
OP_CARET    equ 5
OP_PCT      equ 6
OP_LP       equ 7
OP_RP       equ 8
OP_COMMA    equ 9
OP_SET      equ 10
OP_EQ       equ 11
OP_NE       equ 12
OP_LT       equ 13
OP_GT       equ 14
OP_LE       equ 15
OP_GE       equ 16

KW_LET      equ 1
KW_IF       equ 2
KW_THEN     equ 3
KW_ELSE     equ 4
KW_ELIF     equ 5
KW_END      equ 6
KW_WHILE    equ 7
KW_DO       equ 8
KW_FOR      equ 9
KW_TO       equ 10
KW_STEP     equ 11
KW_FN       equ 12
KW_RETURN   equ 13
KW_PRINT    equ 14
KW_AND      equ 15
KW_OR       equ 16
KW_NOT      equ 17
KW_BREAK    equ 18
KW_TRUE     equ 19
KW_FALSE    equ 20

V_NUM       equ 0
V_STR       equ 1

; variable: +0 name, +4 name length, +8 type, +12 string length,
; +16 number (qword) or string text
VR_SIZE     equ 24
; function: +0 name, +4 length, +8 parameters, +12 body token,
; +16 parameter tokens (NUT_PARAMS dwords)
FN_SIZE     equ 16 + NUT_PARAMS * 4

; reg = the token at index idx
%macro TOKP 2
    mov %1, %2
    shl %1, 4
    add %1, [nut_toks]
%endmacro

nut_init:
    mov eax, SYS_SBRK
    mov ebx, NUT_TOKS * TK_SIZE + NUT_ATOMS + NUT_SHEAP + NUT_OUT
    int 0x80
    cmp eax, -1
    je .no
    mov [nut_toks], eax
    add eax, NUT_TOKS * TK_SIZE
    mov [nut_atoms], eax
    add eax, NUT_ATOMS
    mov [nut_sheap], eax
    add eax, NUT_SHEAP
    mov [nut_out], eax
    call nut_reset
    clc
    ret
.no:
    stc
    ret

nut_reset:
    mov dword [nut_ntok], 0
    mov dword [nut_atop], 0
    mov dword [nut_stop], 0
    mov dword [nut_olen], 0
    mov eax, [nut_out]
    mov byte [eax], 0
    mov dword [nut_vtop], 0
    mov dword [nut_gend], 0
    mov dword [nut_nfn], 0
    mov dword [nut_errmsg], 0
    mov dword [nut_seed], 12345
    ret

; ---------- running ----------
nut_run:
    pushad
    mov [nut_sp], esp
    call nut_lex                ; -> eax = its first token
    jc .r
    mov [nut_pos], eax
    mov byte [nut_skip], 0
    mov byte [nut_ret], 0
    mov byte [nut_brk], 0
    mov dword [nut_steps], 0
    mov dword [nut_depth], 0
    mov eax, [nut_vtop]
    mov [nut_fbase], eax
    mov [nut_gend], eax
    call n_block
    call n_tok                  ; anything left over: an end too many
    cmp byte [edi], TK_EOF
    je .ok
    mov esi, ne_stray
    jmp nut_error
.ok:
    mov eax, [nut_vtop]
    mov [nut_gend], eax
    popad
    clc
    ret
.r:
    popad
    stc
    ret

; esi = an error message: the run stops (back to nut_run's caller)
nut_error:
    mov [nut_errmsg], esi
    mov eax, [nut_pos]
    cmp eax, [nut_ntok]
    jb .l
    mov eax, [nut_ntok]
    dec eax
.l:
    xor ecx, ecx
    test eax, eax
    js .set
    TOKP edi, eax
    movzx ecx, word [edi+2]
.set:
    mov [nut_errline], ecx
    mov esp, [nut_sp]
    fninit
    mov eax, [nut_gend]         ; whatever the run made is dropped
    mov [nut_vtop], eax
    popad
    stc
    ret

; -> edi = the current token
n_tok:
    mov edi, [nut_pos]
    shl edi, 4
    add edi, [nut_toks]
    ret
n_next:
    inc dword [nut_pos]
    ret

; al = keyword -> ZF if the current token is it
n_iskw:
    push edi
    call n_tok
    cmp byte [edi], TK_KW
    jne .r
    cmp [edi+1], al
.r:
    pop edi
    ret
; al = operator -> ZF if the current token is it
n_isop:
    push edi
    call n_tok
    cmp byte [edi], TK_OP
    jne .r
    cmp [edi+1], al
.r:
    pop edi
    ret
; al = keyword: it must come next (consumed)
n_wantkw:
    call n_iskw
    jne .bad
    jmp n_next
.bad:
    movzx eax, al
    mov esi, [nk_want+eax*4]
    jmp nut_error
; al = operator: it must come next
n_wantop:
    call n_isop
    jne .bad
    jmp n_next
.bad:
    mov esi, ne_syntax
    cmp al, OP_RP
    jne .e
    mov esi, ne_rp
.e:
    jmp nut_error

n_skipnl:
    call n_tok
    cmp byte [edi], TK_NL
    jne .r
    call n_next
    jmp n_skipnl
.r:
    ret

; statements until end, else, elif or the end of the text
n_block:
.s:
    call n_skipnl
    call n_tok
    cmp byte [edi], TK_EOF
    je .r
    cmp byte [edi], TK_KW
    jne .st
    mov al, [edi+1]
    cmp al, KW_END
    je .r
    cmp al, KW_ELSE
    je .r
    cmp al, KW_ELIF
    je .r
.st:
    call n_stmt
    jmp .s
.r:
    ret

; skip = saved | returning | breaking
%macro RESKIP 1
    mov al, %1
    or al, [nut_ret]
    or al, [nut_brk]
    mov [nut_skip], al
%endmacro

n_count:
    inc dword [nut_steps]
    cmp dword [nut_steps], NUT_STEPS
    jb .r
    mov esi, ne_steps
    jmp nut_error
.r:
    ret

n_stmt:
    call n_count
    call n_tok
    cmp byte [edi], TK_KW
    jne .name
    movzx eax, byte [edi+1]
    cmp eax, KW_LET
    je .let
    cmp eax, KW_PRINT
    je n_print
    cmp eax, KW_IF
    je n_if
    cmp eax, KW_WHILE
    je n_while
    cmp eax, KW_FOR
    je n_for
    cmp eax, KW_FN
    je n_fndef
    cmp eax, KW_RETURN
    je n_return
    cmp eax, KW_BREAK
    je n_break
    jmp .expr
.let:
    call n_next
    call n_tok
    cmp byte [edi], TK_NAME
    jne .bad
.name:
    cmp byte [edi], TK_NAME     ; name = expr?
    jne .expr
    mov eax, [nut_pos]
    inc eax
    TOKP esi, eax
    cmp byte [esi], TK_OP
    jne .expr
    cmp byte [esi+1], OP_SET
    jne .expr
    push edi
    call n_next
    call n_next
    call n_expr
    pop edi
    cmp byte [nut_skip], 0
    jne .drop
    call n_assign
    jmp .eos
.expr:                          ; an expression (a call) alone
    call n_expr
.drop:
    call n_drop
.eos:                           ; then the end of the statement
    call n_tok
    cmp byte [edi], TK_NL
    je n_next
    cmp byte [edi], TK_EOF
    je .r
    cmp byte [edi], TK_KW       ; (one line: if c then x = 1 end print x)
    je .r
.bad:
    mov esi, ne_syntax
    jmp nut_error
.r:
    ret

; a value nobody wants
n_drop:
    cmp eax, V_NUM
    jne .r
    fstp st0
.r:
    ret

; print a, b, ...
n_print:
    call n_next
    xor ebx, ebx                ; items so far
.i:
    call n_tok
    cmp byte [edi], TK_NL
    je .nl
    cmp byte [edi], TK_EOF
    je .nl
    cmp byte [edi], TK_KW
    jne .item
    cmp byte [edi+1], KW_END
    je .nl
    cmp byte [edi+1], KW_ELSE
    je .nl
    cmp byte [edi+1], KW_ELIF
    je .nl
.item:
    push ebx
    call n_expr
    pop ebx
    cmp byte [nut_skip], 0
    jne .sk
    test ebx, ebx
    jz .first
    push eax
    mov al, ' '
    call nut_putc
    pop eax
.first:
    call n_show
.sk1:
    inc ebx
    mov al, OP_COMMA
    call n_isop
    jne .nl
    call n_next
    jmp .i
.sk:
    call n_drop
    jmp .sk1
.nl:
    cmp byte [nut_skip], 0
    jne n_stmt.eos
    mov al, 10
    call nut_putc
    jmp n_stmt.eos

; eax / st0 / edx, ecx -> the output
n_show:
    cmp eax, V_STR
    je .s
    call n_numtext              ; -> esi
    jmp nut_puts
.s:
    jecxz .r
.c:
    mov al, [edx]
    call nut_putc
    inc edx
    loop .c
.r:
    ret

; al -> the output
nut_putc:
    push edi
    mov edi, [nut_olen]
    cmp edi, NUT_OUT - 2
    jae .r
    add edi, [nut_out]
    mov [edi], al
    mov byte [edi+1], 0
    inc dword [nut_olen]
.r:
    pop edi
    ret
nut_puts:
    push eax
.c:
    lodsb
    test al, al
    jz .r
    call nut_putc
    jmp .c
.r:
    pop eax
    ret

; st0 (popped) -> esi = its text, as sci prints it (the FPU is reset)
n_numtext:
    pushad
    fstp qword [nut_ev+GE_X]
    mov dword [nut_ev+GE_EXPR], ns_x
    mov dword [nut_ev+GE_FLAGS], GEF_X
    mov dword [nut_ev+GE_TEXT], nut_nbuf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, nut_ev
    int 0x80
    popad
    mov esi, nut_nbuf
    ret

; if c then ... elif c then ... else ... end
n_if:
    movzx eax, byte [nut_skip]
    push eax                    ; saved skip
    push dword 0                ; a branch was taken
    call n_next
.cond:
    call n_expr
    call n_truth                ; -> ZF if false (nothing when skipping)
    setnz bl
    push ebx
    mov al, KW_THEN
    call n_wantkw
    pop ebx
    cmp byte [nut_skip], 0
    jne .no
    test bl, bl
    jz .no
    mov dword [esp], 1
    jmp .body
.no:
    mov byte [nut_skip], 1
.body:
    call n_block
    mov al, [esp+4]             ; back to the saved skip
    RESKIP al
    mov al, KW_ELIF
    call n_iskw
    jne .else
    call n_next
    cmp dword [esp], 0          ; one was taken: the rest are skipped
    je .cond
    mov byte [nut_skip], 1
    jmp .cond
.else:
    mov al, KW_ELSE
    call n_iskw
    jne .end
    call n_next
    cmp dword [esp], 0
    je .eb
    mov byte [nut_skip], 1
.eb:
    call n_block
    mov al, [esp+4]
    RESKIP al
.end:
    mov al, KW_END
    call n_wantkw
    add esp, 4
    pop eax
    RESKIP al
    jmp n_stmt.eos

; eax / value -> ZF if it is false (0 or ""); the value is gone. When
; skipping: ZF clear, nothing tested.
n_truth:
    cmp byte [nut_skip], 0
    jne .skip
    cmp eax, V_STR
    je .s
    ftst
    fnstsw ax
    fstp st0
    sahf
    ret
.s:
    test ecx, ecx
    ret
.skip:
    call n_drop
    or esp, esp
    ret

; while c do ... end
n_while:
    movzx eax, byte [nut_skip]
    push eax
    call n_next
    push dword [nut_pos]        ; the condition
.loop:
    call n_count
    mov eax, [esp]
    mov [nut_pos], eax
    call n_expr
    call n_truth
    setnz bl
    mov al, KW_DO
    call n_wantkw
    cmp byte [nut_skip], 0
    jne .last
    test bl, bl
    jz .last
    call n_block
    mov al, KW_END
    call n_wantkw
    cmp byte [nut_brk], 0
    jne .broke
    cmp byte [nut_ret], 0
    jne .out
    jmp .loop
.last:                          ; skip the body to its end
    mov byte [nut_skip], 1
    call n_block
    mov al, KW_END
    call n_wantkw
    jmp .out
.broke:
    mov byte [nut_brk], 0
.out:
    add esp, 4
    pop eax
    RESKIP al
    jmp n_stmt.eos

; for v = a to b [step s] do ... end
n_for:
    movzx eax, byte [nut_skip]
    push eax
    call n_next
    call n_tok
    cmp byte [edi], TK_NAME
    jne n_stmt.bad
    push edi                    ; the variable's token
    call n_next
    mov al, OP_SET
    call n_wantop
    call n_num
    sub esp, 8
    fstp qword [esp]            ; from
    mov al, KW_TO
    call n_wantkw
    call n_num
    sub esp, 8
    fstp qword [esp]            ; to
    fld1
    mov al, KW_STEP
    call n_iskw
    jne .nostep
    fstp st0
    call n_next
    call n_num
.nostep:
    sub esp, 8
    fstp qword [esp]            ; step
    mov al, KW_DO
    call n_wantkw
    push dword [nut_pos]        ; the body
    ; [esp] body, +4 step, +12 to, +20 from, +28 variable token, +32 skip
    cmp byte [nut_skip], 0
    jne .last
    fld qword [esp+20]          ; v = from
    mov edi, [esp+28]
    mov eax, V_NUM
    call n_assign
.loop:
    call n_count
    mov edi, [esp+28]           ; v within the range?
    call n_lookup
    jc .last
    cmp dword [ebx+8], V_NUM
    jne .last
    fld qword [ebx+16]
    fld qword [esp+12]
    fld qword [esp+4]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jb .down
    fcomip st0, st1             ; to >= v
    fstp st0
    jb .last
    jmp .body
.down:
    fcomip st0, st1             ; to <= v
    fstp st0
    ja .last
.body:
    mov eax, [esp]
    mov [nut_pos], eax
    call n_block
    mov al, KW_END
    call n_wantkw
    cmp byte [nut_brk], 0
    jne .broke
    cmp byte [nut_ret], 0
    jne .out
    mov edi, [esp+28]           ; v += step
    call n_lookup
    jc .out
    fld qword [ebx+16]
    fadd qword [esp+4]
    fstp qword [ebx+16]
    jmp .loop
.last:
    mov eax, [esp]
    mov [nut_pos], eax
    mov byte [nut_skip], 1
    call n_block
    mov al, KW_END
    call n_wantkw
    jmp .out
.broke:
    mov byte [nut_brk], 0
.out:
    add esp, 32
    pop eax
    RESKIP al
    jmp n_stmt.eos

; fn name(a, b) ... end: kept, the body skipped
n_fndef:
    movzx eax, byte [nut_skip]
    push eax
    call n_next
    call n_tok
    cmp byte [edi], TK_NAME
    jne n_stmt.bad
    mov ebx, [nut_nfn]          ; a new one (or the same name again)
    push edi
    call n_findfn
    pop edi
    jnc .have
    cmp dword [nut_nfn], NUT_FNS
    jae .full
    mov ebx, [nut_nfn]
    imul ebx, FN_SIZE
    add ebx, nut_fns
    cmp byte [nut_skip], 0
    jne .have
    inc dword [nut_nfn]
.have:
    mov ecx, nut_fnscratch      ; skipped: written nowhere that counts
    cmp byte [nut_skip], 0
    jne .w
    mov ecx, ebx
.w:
    mov eax, [edi+4]
    mov [ecx], eax
    mov eax, [edi+8]
    mov [ecx+4], eax
    mov dword [ecx+8], 0
    call n_next
    mov al, OP_LP
    call n_wantop
    mov al, OP_RP
    call n_isop
    je .pd
.p:
    call n_tok
    cmp byte [edi], TK_NAME
    jne n_stmt.bad
    mov eax, [ecx+8]
    cmp eax, NUT_PARAMS
    jae .many
    mov edx, [nut_pos]
    mov [ecx+16+eax*4], edx
    inc dword [ecx+8]
    call n_next
    mov al, OP_COMMA
    call n_isop
    jne .pd
    call n_next
    jmp .p
.pd:
    mov al, OP_RP
    call n_wantop
    mov eax, [nut_pos]
    mov [ecx+12], eax
    mov byte [nut_skip], 1      ; the body runs only when called
    call n_block
    mov al, KW_END
    call n_wantkw
    pop eax
    RESKIP al
    jmp n_stmt.eos
.full:
    mov esi, ne_fns
    jmp nut_error
.many:
    mov esi, ne_params
    jmp nut_error

; edi = name token -> ebx = its function, or CF
n_findfn:
    push ecx
    xor ecx, ecx
.f:
    cmp ecx, [nut_nfn]
    jae .no
    imul ebx, ecx, FN_SIZE
    add ebx, nut_fns
    push esi
    push edi
    mov esi, [ebx]
    mov eax, [ebx+4]
    call n_samename
    pop edi
    pop esi
    je .yes
    inc ecx
    jmp .f
.no:
    pop ecx
    stc
    ret
.yes:
    pop ecx
    clc
    ret

; esi = name, eax = its length, edi = name token -> ZF if the same
n_samename:
    cmp eax, [edi+8]
    jne .r
    push ecx
    mov ecx, eax
    mov edi, [edi+4]
    repe cmpsb
    pop ecx
.r:
    ret

n_return:
    call n_next
    call n_tok                  ; a value, or none (0)
    cmp byte [edi], TK_NL
    je .zero
    cmp byte [edi], TK_EOF
    je .zero
    cmp byte [edi], TK_KW
    jne .val
    cmp byte [edi+1], KW_END
    je .zero
    cmp byte [edi+1], KW_ELSE
    je .zero
    cmp byte [edi+1], KW_ELIF
    je .zero
.val:
    call n_expr
    jmp .have
.zero:
    fldz
    mov eax, V_NUM
.have:
    cmp byte [nut_skip], 0
    jne .sk
    cmp dword [nut_depth], 0
    je .top
    mov [nut_rtype], eax
    cmp eax, V_STR
    je .s
    fstp qword [nut_rnum]
    jmp .set
.s:
    mov [nut_rnum], edx
    mov [nut_rnum+4], ecx
.set:
    mov byte [nut_ret], 1
    mov byte [nut_skip], 1
    jmp n_stmt.eos
.top:
    mov esi, ne_rettop
    jmp nut_error
.sk:
    call n_drop
    jmp n_stmt.eos

n_break:
    call n_next
    cmp byte [nut_skip], 0
    jne n_stmt.eos
    mov byte [nut_brk], 1
    mov byte [nut_skip], 1
    jmp n_stmt.eos

; ---------- variables ----------
; edi = name token -> ebx = its variable, or CF: a local of this call,
; else a global
n_lookup:
    push eax
    push ecx
    push esi
    mov ecx, [nut_vtop]
.l:
    cmp ecx, [nut_fbase]
    jbe .g
    dec ecx
    call .cmp
    je .yes
    jmp .l
.g:
    mov ecx, [nut_gend]
    cmp dword [nut_depth], 0
    jne .gl
    mov ecx, [nut_vtop]         ; at the top level all are global
.gl:
    test ecx, ecx
    jz .no
    dec ecx
    call .cmp
    je .yes
    jmp .gl
.no:
    pop esi
    pop ecx
    pop eax
    stc
    ret
.yes:
    imul ebx, ecx, VR_SIZE
    add ebx, nut_vars
    pop esi
    pop ecx
    pop eax
    clc
    ret
.cmp:
    imul ebx, ecx, VR_SIZE
    add ebx, nut_vars
    mov esi, [ebx]
    mov eax, [ebx+4]
    push edi
    call n_samename
    pop edi
    ret

; edi = name token, eax / value -> stored (a new variable if needed)
n_assign:
    push eax
    call n_lookup
    jnc .have
    mov ebx, [nut_vtop]
    cmp ebx, NUT_VARS
    jae .full
    inc dword [nut_vtop]
    imul ebx, VR_SIZE
    add ebx, nut_vars
    mov eax, [edi+4]
    mov [ebx], eax
    mov eax, [edi+8]
    mov [ebx+4], eax
.have:
    pop eax
    mov [ebx+8], eax
    cmp eax, V_STR
    je .s
    fstp qword [ebx+16]
    ret
.s:
    mov [ebx+16], edx
    mov [ebx+12], ecx
    ret
.full:
    mov esi, ne_vars
    jmp nut_error

; ---------- expressions ----------
; a number is wanted -> st0
n_num:
    call n_expr
    cmp eax, V_NUM
    je .r
    cmp byte [nut_skip], 0
    jne .z
    mov esi, ne_notnum
    jmp nut_error
.z:
    fldz
.r:
    ret

; spill the value (eax / st0 / edx, ecx) to the stack: 12 bytes
%macro SPILL 0
    sub esp, 12
    mov [esp], eax
    cmp eax, V_STR
    je %%s
    fstp qword [esp+4]
    jmp %%d
%%s:
    mov [esp+4], edx
    mov [esp+8], ecx
%%d:
%endmacro

n_expr:
    call n_and
.l:
    push eax
    mov al, KW_OR
    call n_iskw
    pop eax
    jne .r
    call n_next
    call n_truth01
    SPILL
    call n_and
    call n_truth01
    fld qword [esp+4]
    add esp, 12
    fadd                        ; either: the sum is not 0
    call n_bool
    jmp .l
.r:
    ret
n_and:
    call n_not
.l:
    push eax
    mov al, KW_AND
    call n_iskw
    pop eax
    jne .r
    call n_next
    call n_truth01
    SPILL
    call n_not
    call n_truth01
    fld qword [esp+4]
    add esp, 12
    fmul
    call n_bool
    jmp .l
.r:
    ret
n_not:
    mov al, KW_NOT
    call n_iskw
    jne n_cmp
    call n_next
    call n_not
    call n_truth01
    fld1
    fsubrp st1, st0             ; 1 - t
    mov eax, V_NUM
    ret

; value -> st0 = 1 or 0 (a number)
n_truth01:
    cmp eax, V_STR
    je .s
    fldz
    fcomip st0, st1
    fstp st0
    je .zero
    fld1
    jmp .r
.s:
    test ecx, ecx
    jz .zero
    fld1
    jmp .r
.zero:
    fldz
.r:
    mov eax, V_NUM
    ret
; st0 -> 1 if not 0
n_bool:
    call n_truth01
    ret

n_cmp:
    call n_add
.l:
    call n_tok
    cmp byte [edi], TK_OP
    jne .r
    movzx ebx, byte [edi+1]
    cmp ebx, OP_EQ
    jb .r
    cmp ebx, OP_GE
    ja .r
    push ebx
    call n_next
    SPILL
    call n_add
    mov ebx, [esp+12]
    cmp byte [nut_skip], 0
    jne .skip
    cmp eax, [esp]
    jne .mixed
    cmp eax, V_STR
    je .str
    fld qword [esp+4]           ; left, right
    fcomip st0, st1             ; left ? right
    fstp st0
    jmp .flags
.str:                           ; compared byte by byte, then by length
    mov esi, [esp+4]
    mov edi, edx
    mov eax, [esp+8]            ; left length
    push ecx
    cmp eax, ecx
    jbe .m
    mov eax, ecx
.m:
    mov ecx, eax
    cmp eax, eax                ; (equal when there is nothing to compare)
    repe cmpsb
    pop ecx
    jne .flags
    cmp [esp+8], ecx
    jmp .flags
.mixed:                         ; a number and a string: only != holds
    call n_drop
    mov eax, [esp]
    cmp eax, V_STR
    je .md
    fld qword [esp+4]
    fstp st0
.md:
    xor eax, eax
    cmp ebx, OP_NE
    sete al
    jmp .res
.flags:                         ; CF, ZF as for unsigned left ? right
    setb al                     ; <
    seta ah                     ; >
    sete dl                     ; ==
    cmp ebx, OP_EQ
    je .eq
    cmp ebx, OP_NE
    je .ne
    cmp ebx, OP_LT
    je .lt
    cmp ebx, OP_GT
    je .gt
    cmp ebx, OP_LE
    je .le
    mov al, ah                  ; >=
    or al, dl
    jmp .res0
.eq:
    mov al, dl
    jmp .res0
.ne:
    mov al, dl
    xor al, 1
    jmp .res0
.lt:
    jmp .res0
.gt:
    mov al, ah
    jmp .res0
.le:
    or al, dl
.res0:
    movzx eax, al
.res:
    add esp, 16
    mov [nut_tmpi], eax
    fild dword [nut_tmpi]
    mov eax, V_NUM
    jmp .l
.skip:
    call n_drop
    add esp, 16
    fldz
    mov eax, V_NUM
    jmp .l
.r:
    ret

n_add:
    call n_mul
.l:
    call n_tok
    cmp byte [edi], TK_OP
    jne .r
    movzx ebx, byte [edi+1]
    cmp ebx, OP_PLUS
    je .op
    cmp ebx, OP_MINUS
    jne .r
.op:
    push ebx
    call n_next
    SPILL
    call n_mul
    mov ebx, [esp+12]
    cmp byte [nut_skip], 0
    jne .skip
    cmp eax, V_STR
    je .join
    cmp dword [esp], V_STR
    je .join
    fld qword [esp+4]           ; left, right
    cmp ebx, OP_PLUS
    jne .sub
    fadd
    jmp .done
.sub:
    fsubrp st1, st0             ; left - right
.done:
    add esp, 16
    mov eax, V_NUM
    jmp .l
.join:                          ; text: left then right
    cmp ebx, OP_PLUS
    jne .nostr
    call n_join
    add esp, 16
    jmp .l
.nostr:
    mov esi, ne_strop
    jmp nut_error
.skip:
    call n_drop
    add esp, 16
    fldz
    mov eax, V_NUM
    jmp .l
.r:
    ret

; [esp+4..] = the left value (12 bytes), eax.. = the right -> a string
n_join:
    push ebp
    lea ebp, [esp+8]            ; the left value
    cmp eax, V_STR              ; the right as text, kept
    je .rs
    call n_numtext
    mov edx, esi
    mov ecx, 0
.rl:
    cmp byte [esi+ecx], 0
    je .rk
    inc ecx
    jmp .rl
.rk:
    call n_keep                 ; -> edx (copied)
.rs:
    push edx
    push ecx
    cmp dword [ebp], V_STR      ; the left as text
    je .ls
    fld qword [ebp+4]
    call n_numtext
    mov edx, esi
    xor ecx, ecx
.ll:
    cmp byte [esi+ecx], 0
    je .lk
    inc ecx
    jmp .ll
.lk:
    jmp .both
.ls:
    mov edx, [ebp+4]
    mov ecx, [ebp+8]
.both:                          ; edx, ecx left; [esp] right length, [esp+4] text
    mov eax, ecx
    add eax, [esp]
    call n_alloc                ; -> edi
    push edi
    mov esi, edx
    rep movsb
    mov esi, [esp+8]
    mov ecx, [esp+4]
    rep movsb
    pop edx
    mov ecx, edi
    sub ecx, edx
    add esp, 8
    mov eax, V_STR
    pop ebp
    ret

; edx, ecx = text -> a copy in the string memory (edx)
n_keep:
    push eax
    push esi
    push edi
    mov eax, ecx
    call n_alloc
    push edi
    mov esi, edx
    push ecx
    rep movsb
    pop ecx
    pop edx
    pop edi
    pop esi
    pop eax
    ret

; eax = bytes -> edi = room for them
n_alloc:
    mov edi, [nut_stop]
    add eax, edi
    cmp eax, NUT_SHEAP
    ja .full
    mov [nut_stop], eax
    add edi, [nut_sheap]
    ret
.full:
    mov esi, ne_strmem
    jmp nut_error

n_mul:
    call n_unary
.l:
    call n_tok
    cmp byte [edi], TK_OP
    jne .r
    movzx ebx, byte [edi+1]
    cmp ebx, OP_STAR
    je .op
    cmp ebx, OP_SLASH
    je .op
    cmp ebx, OP_PCT
    jne .r
.op:
    push ebx
    call n_next
    call n_numck
    SPILL
    call n_unary
    call n_numck
    mov ebx, [esp+12]
    fld qword [esp+4]           ; left, right
    add esp, 16
    cmp ebx, OP_STAR
    je .m
    cmp byte [nut_skip], 0
    jne .zero
    fldz
    fcomip st0, st2
    je .div0
    cmp ebx, OP_PCT
    je .mod
    fdivrp st1, st0             ; left / right
    jmp .l
.m:
    fmul
    jmp .l
.mod:                           ; left - right * floor(left / right)
    fld st0
    fdiv st0, st2
    call n_floor
    fmul st0, st2
    fsubp st1, st0
    fstp st1
    jmp .l
.zero:
    fstp st0
    fstp st0
    fldz
    mov eax, V_NUM
    jmp .l
.div0:
    mov esi, ne_div0
    jmp nut_error
.r:
    ret

; a number, or an error (when not skipping; skipped strings become 0)
n_numck:
    cmp eax, V_NUM
    je .r
    cmp byte [nut_skip], 0
    jne .z
    mov esi, ne_notnum
    jmp nut_error
.z:
    fldz
    mov eax, V_NUM
.r:
    ret

n_unary:
    mov al, OP_MINUS
    call n_isop
    je .neg
    mov al, OP_PLUS
    call n_isop
    jne n_pow
    call n_next
    jmp n_unary
.neg:
    call n_next
    call n_unary
    call n_numck
    fchs
    ret

; a ^ b (right to left: 2^3^2 = 2^9)
n_pow:
    call n_atom
    push eax
    mov al, OP_CARET
    call n_isop
    pop eax
    jne .r
    call n_next
    call n_numck
    SPILL
    call n_unary
    call n_numck
    fld qword [esp+4]
    add esp, 12
    cmp byte [nut_skip], 0
    jne .sk
    fxch                        ; st0 = exponent, st1 = base
    call n_fpow
    mov eax, V_NUM
.r:
    ret
.sk:
    fstp st0
    fstp st0
    fldz
    mov eax, V_NUM
    ret

n_atom:
    call n_tok
    movzx eax, byte [edi]
    cmp eax, TK_NUM
    je .num
    cmp eax, TK_STR
    je .str
    cmp eax, TK_NAME
    je .name
    cmp eax, TK_KW
    je .kw
    cmp eax, TK_OP
    jne .bad
    cmp byte [edi+1], OP_LP
    jne .bad
    call n_next
    call n_expr
    push eax
    mov al, OP_RP
    call n_wantop
    pop eax
    ret
.num:
    fld qword [edi+8]
    call n_next
    mov eax, V_NUM
    ret
.str:
    mov edx, [edi+4]
    mov ecx, [edi+8]
    call n_next
    mov eax, V_STR
    ret
.kw:
    cmp byte [edi+1], KW_TRUE
    je .one
    cmp byte [edi+1], KW_FALSE
    jne .bad
    call n_next
    fldz
    mov eax, V_NUM
    ret
.one:
    call n_next
    fld1
    mov eax, V_NUM
    ret
.bad:
    cmp eax, TK_EOF
    je .end
    cmp eax, TK_NL
    je .end
    mov esi, ne_syntax
    jmp nut_error
.end:
    mov esi, ne_more
    jmp nut_error
.name:
    mov eax, [nut_pos]          ; a call?
    inc eax
    TOKP esi, eax
    cmp byte [esi], TK_OP
    jne .var
    cmp byte [esi+1], OP_LP
    je n_call
.var:
    call n_next
    cmp byte [nut_skip], 0
    jne .zero
    call n_lookup
    jc .pi
    mov eax, [ebx+8]
    cmp eax, V_STR
    je .vs
    fld qword [ebx+16]
    ret
.vs:
    mov edx, [ebx+16]
    mov ecx, [ebx+12]
    ret
.pi:
    mov esi, ns_pi
    mov eax, 2
    call n_samename
    jne .unknown
    fldpi
    mov eax, V_NUM
    ret
.unknown:
    mov esi, ne_unknown
    jmp nut_error
.zero:
    fldz
    mov eax, V_NUM
    ret

; name(arguments): a function of the program, or a built-in one
n_call:
    push edi                    ; the name token
    call n_next
    call n_next                 ; past "("
    xor ebx, ebx                ; arguments, spilled
.a:
    mov al, OP_RP
    call n_isop
    je .ad
    push ebx
    call n_expr
    pop ebx
    SPILL
    inc ebx
    cmp ebx, NUT_PARAMS
    ja .many
    mov al, OP_COMMA
    call n_isop
    jne .ad
    call n_next
    jmp .a
.ad:
    push ebx
    mov al, OP_RP
    call n_wantop
    pop ebx
    imul eax, ebx, 12
    mov edi, [esp+eax]          ; the name token
    cmp byte [nut_skip], 0
    jne .skip
    push ebx
    push edi
    call n_findfn
    mov ecx, ebx
    pop edi
    pop ebx
    jnc .user
    call n_builtin              ; ebx arguments at [esp+4..]
    jmp .drop
.user:
    call n_calluser             ; ecx = the function
.drop:                          ; the result stays; arguments and name go
    imul ebx, 12
    add esp, ebx
    add esp, 4
    ret
.skip:
    fldz
    mov eax, V_NUM
    jmp .drop
.many:
    mov esi, ne_params
    jmp nut_error

; ecx = function, ebx = arguments at [esp+4] (the last first) -> value
n_calluser:
    cmp ebx, [ecx+8]
    je .n
    mov esi, ne_nargs
    jmp nut_error
.n:
    cmp dword [nut_depth], NUT_DEPTH
    jb .d
    mov esi, ne_deep
    jmp nut_error
.d:
    push dword [nut_fbase]
    push dword [nut_pos]
    mov eax, [nut_vtop]
    cmp dword [nut_depth], 0    ; the globals: all there are so far
    jne .nest
    mov [nut_gend], eax
.nest:
    mov [nut_fbase], eax
    inc dword [nut_depth]
    ; parameters: argument k is at [esp + 12 + (n - 1 - k) * 12]
    xor edx, edx
.p:
    cmp edx, ebx
    jae .run
    mov eax, ebx
    sub eax, edx
    dec eax
    imul eax, 12
    lea esi, [esp+12+eax]
    push edx
    push ecx
    mov eax, [ecx+16+edx*4]     ; the parameter's token
    TOKP edi, eax
    mov ebp, [nut_vtop]         ; always a new local
    cmp ebp, NUT_VARS
    jae .full
    inc dword [nut_vtop]
    imul ebp, VR_SIZE
    add ebp, nut_vars
    mov eax, [edi+4]
    mov [ebp], eax
    mov eax, [edi+8]
    mov [ebp+4], eax
    mov eax, [esi]
    mov [ebp+8], eax
    mov eax, [esi+4]
    mov [ebp+16], eax
    mov eax, [esi+8]
    mov [ebp+20], eax
    mov [ebp+12], eax           ; (a string's length: the same dword)
    pop ecx
    pop edx
    inc edx
    jmp .p
.run:
    movzx eax, byte [nut_skip]
    push eax
    push ebx
    mov eax, [ecx+12]
    mov [nut_pos], eax
    mov byte [nut_skip], 0
    mov byte [nut_ret], 0
    call n_block
    mov al, KW_END
    call n_iskw
    jne .noend
    pop ebx
    pop eax
    mov [nut_skip], al
    mov eax, V_NUM
    cmp byte [nut_ret], 0
    je .zero
    mov byte [nut_ret], 0
    mov eax, [nut_rtype]
    cmp eax, V_STR
    je .s
    fld qword [nut_rnum]
    jmp .back
.s:
    mov edx, [nut_rnum]
    mov ecx, [nut_rnum+4]
    jmp .back
.zero:
    fldz
.back:
    dec dword [nut_depth]
    mov esi, [nut_fbase]
    mov [nut_vtop], esi
    pop dword [nut_pos]
    pop dword [nut_fbase]
    ret
.noend:
    mov esi, ne_noend
    jmp nut_error
.full:
    mov esi, ne_vars
    jmp nut_error

; edi = name token, ebx = arguments at [esp+4] -> value
n_builtin:
    mov esi, nb_names
    xor edx, edx
.f:
    cmp byte [esi], 0
    je .unknown
    movzx eax, byte [esi]       ; length, then the name
    inc esi
    push esi
    push edi
    call n_samename
    pop edi
    pop esi
    je .got
    movzx eax, byte [esi-1]
    add esi, eax
    inc edx
    jmp .f
.unknown:
    mov esi, ne_nofn
    jmp nut_error
.got:
    movzx eax, byte [nb_args+edx]
    cmp eax, 9                  ; 9: one or more
    je .any
    cmp eax, ebx
    je .call
    mov esi, ne_nargs
    jmp nut_error
.any:
    test ebx, ebx
    jnz .call
    mov esi, ne_nargs
    jmp nut_error
.call:
    jmp [nb_code+edx*4]

; the argument k (from the last, 0) of a built-in -> st0, or an error
%macro BARG 1
    cmp dword [esp+4+%1*12], V_NUM
    jne n_argnum
    fld qword [esp+8+%1*12]
%endmacro
n_argnum:
    mov esi, ne_notnum
    jmp nut_error

nb_sin:
    BARG 0
    fsin
    jmp nb_num
nb_cos:
    BARG 0
    fcos
    jmp nb_num
nb_tan:
    BARG 0
    fptan
    fstp st0
    jmp nb_num
nb_atan:
    BARG 0
    fld1
    fpatan
    jmp nb_num
nb_asin:                        ; atan(x / sqrt(1 - x^2))
    BARG 0
    call nb_dom1
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fpatan
    jmp nb_num
nb_acos:                        ; atan(sqrt(1 - x^2) / x)
    BARG 0
    call nb_dom1
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fxch
    fpatan
    jmp nb_num
nb_sqrt:
    BARG 0
    ftst
    fnstsw ax
    sahf
    jb nb_domain
    fsqrt
    jmp nb_num
nb_abs:
    BARG 0
    fabs
    jmp nb_num
nb_ln:
    BARG 0
    ftst
    fnstsw ax
    sahf
    jbe nb_domain
    fldln2
    fxch
    fyl2x
    jmp nb_num
nb_exp:
    BARG 0
    fldl2e
    fmul
    call n_pow2
    jmp nb_num
nb_floor:
    BARG 0
    call n_floor
    jmp nb_num
nb_ceil:
    BARG 0
    fchs
    call n_floor
    fchs
    jmp nb_num
nb_round:
    BARG 0
    fadd qword [nf_half]
    call n_floor
    jmp nb_num
nb_min:
    mov ecx, 0
    mov dl, 1
    jmp nb_mm
nb_max:
    xor ecx, ecx
    mov dl, 0
nb_mm:                          ; over all the arguments
    BARG 0
.l:
    inc ecx
    cmp ecx, ebx
    jae nb_num
    imul eax, ecx, 12
    cmp dword [esp+4+eax], V_NUM
    jne n_argnum
    fld qword [esp+8+eax]
    test dl, dl
    jz .mx
    fcomi st0, st1
    jb .take
    fstp st0
    jmp .l
.mx:
    fcomi st0, st1
    ja .take
    fstp st0
    jmp .l
.take:
    fstp st1
    jmp .l
nb_len:
    cmp dword [esp+4], V_STR
    jne .n
    fild dword [esp+12]
    jmp nb_num
.n:
    fld qword [esp+8]
    call n_numtext
    xor ecx, ecx
.c:
    cmp byte [esi+ecx], 0
    je .d
    inc ecx
    jmp .c
.d:
    mov [nut_tmpi], ecx
    fild dword [nut_tmpi]
    jmp nb_num
nb_str:
    cmp dword [esp+4], V_STR
    jne .n
    mov edx, [esp+8]
    mov ecx, [esp+12]
    mov eax, V_STR
    ret
.n:
    fld qword [esp+8]
    call n_numtext
    mov edx, esi
    xor ecx, ecx
.c:
    cmp byte [esi+ecx], 0
    je .d
    inc ecx
    jmp .c
.d:
    call n_keep
    mov eax, V_STR
    ret
nb_num:
    mov eax, V_NUM
    ret
nb_tonum:                       ; num("2.5") with the sci engine
    cmp dword [esp+4], V_NUM
    jne .s
    fld qword [esp+8]
    jmp nb_num
.s:
    mov ecx, [esp+12]
    cmp ecx, 60
    jae nb_domain
    mov esi, [esp+8]
    mov edi, nut_nbuf2
    rep movsb
    mov byte [edi], 0
    mov dword [nut_ev+GE_EXPR], nut_nbuf2
    mov dword [nut_ev+GE_FLAGS], 0
    mov dword [nut_ev+GE_TEXT], 0
    push ebx
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, nut_ev
    int 0x80
    pop ebx
    test eax, eax
    jnz nb_domain
    fld qword [nut_ev+GE_RESULT]
    jmp nb_num
nb_rnd:                         ; 0 <= rnd() < 1
    mov eax, [nut_seed]
    imul eax, 1103515245
    add eax, 12345
    mov [nut_seed], eax
    shr eax, 8
    mov [nut_tmpi], eax
    fild dword [nut_tmpi]
    fmul qword [nf_2m24]
    jmp nb_num
; |st0| must be at most 1
nb_dom1:
    fld st0
    fabs
    fld1
    fcomip st0, st1
    fstp st0
    jb nb_domain
    ret
nb_domain:
    mov esi, ne_domain
    jmp nut_error

; st0 -> floor(st0)
n_floor:
    sub esp, 4
    fnstcw [esp]
    mov ax, [esp]
    and ax, 0xF3FF
    or ax, 0x0400               ; round down
    mov [esp+2], ax
    fldcw [esp+2]
    frndint
    fldcw [esp]
    add esp, 4
    ret
; st0 -> 2^st0
n_pow2:
    fld st0
    frndint
    fsub st1, st0
    fxch
    f2xm1
    fld1
    fadd
    fscale
    fstp st1
    ret
; st1 = base, st0 = exponent -> st0 = base^exponent
n_fpow:
    fxch                        ; st0 = base
    ftst
    fnstsw ax
    sahf
    je .zero
    ja .pos
    fld st1                     ; a negative base: a whole exponent only
    frndint
    fcomp st2
    fnstsw ax
    sahf
    jne .bad
    fld st1                     ; odd?
    fmul qword [nf_half]
    fld st0
    frndint
    fcomip st0, st1
    fstp st0
    setne dl
    fabs
    fyl2x
    call n_pow2
    test dl, dl
    jz .r
    fchs
.r:
    ret
.pos:
    fyl2x
    jmp n_pow2
.zero:                          ; 0^e: 0, or 1 for e = 0
    fstp st0
    ftst
    fnstsw ax
    fstp st0
    sahf
    je .one
    jb .bad
    fldz
    ret
.one:
    fld1
    ret
.bad:
    fstp st0
    fstp st0
    jmp nb_domain

; ---------- the lexer ----------
; esi = text -> its tokens added (eax = the first), or CF with the error
nut_lex:
    mov eax, [nut_ntok]
    mov [nut_first], eax
    mov dword [nut_line], 1
.t:
    mov al, [esi]
    cmp al, ' '
    je .sp
    cmp al, 9
    je .sp
    cmp al, 13
    je .sp
    cmp al, '#'
    je .comment
    test al, al
    jz .eof
    cmp al, 10
    je .nl
    cmp al, ';'
    je .semi
    cmp al, '"'
    je .str
    cmp al, '.'
    je .num
    cmp al, '0'
    jb .op
    cmp al, '9'
    jbe .num
    call n_letter
    je .name
.op:
    mov edi, nl_ops             ; two characters first, then one
.o:
    cmp byte [edi], 0
    je .bad
    mov ax, [edi]
    cmp ah, ' '
    je .o1
    cmp ax, [esi]
    jne .on
    call .newtok
    mov al, [edi+2]
    mov byte [ebx], TK_OP
    mov [ebx+1], al
    add esi, 2
    jmp .t
.o1:
    cmp al, [esi]
    jne .on
    call .newtok
    mov al, [edi+2]
    mov byte [ebx], TK_OP
    mov [ebx+1], al
    inc esi
    jmp .t
.on:
    add edi, 3
    jmp .o
.sp:
    inc esi
    jmp .t
.comment:
    inc esi
    cmp byte [esi], 0
    je .eof
    cmp byte [esi], 10
    jne .comment
    jmp .t
.semi:
    call .newtok
    mov byte [ebx], TK_NL
    inc esi
    jmp .t
.nl:
    call .newtok
    mov byte [ebx], TK_NL
    inc esi
    inc dword [nut_line]
    jmp .t
.str:
    inc esi
    xor ecx, ecx
.sc:
    mov al, [esi+ecx]
    test al, al
    jz .unterm
    cmp al, 10
    je .unterm
    cmp al, '"'
    je .sd
    inc ecx
    jmp .sc
.sd:
    call .newtok
    mov byte [ebx], TK_STR
    call .atom
    lea esi, [esi+ecx+1]
    jmp .t
.num:                           ; digits [. digits] [e [+-] digits]
    xor ecx, ecx
.nd:
    mov al, [esi+ecx]
    cmp al, '.'
    je .nn
    cmp al, '0'
    jb .ne
    cmp al, '9'
    ja .ne
.nn:
    inc ecx
    jmp .nd
.ne:
    or al, 0x20
    cmp al, 'e'
    jne .nv
    mov al, [esi+ecx+1]
    cmp al, '+'
    je .es
    cmp al, '-'
    je .es
    cmp al, '0'
    jb .nv
    cmp al, '9'
    ja .nv
    inc ecx
    jmp .nd
.es:
    add ecx, 2
    jmp .nd
.nv:                            ; the value, by the sci engine
    cmp ecx, 60
    jae .bad
    push esi
    mov edi, nut_nbuf2
    push ecx
    rep movsb
    pop ecx
    mov byte [edi], 0
    pop esi
    pushad
    mov dword [nut_ev+GE_EXPR], nut_nbuf2
    mov dword [nut_ev+GE_FLAGS], 0
    mov dword [nut_ev+GE_TEXT], 0
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, nut_ev
    int 0x80
    mov [esp+28], eax
    popad
    test eax, eax
    jnz .badnum
    call .newtok
    mov byte [ebx], TK_NUM
    fld qword [nut_ev+GE_RESULT]
    fstp qword [ebx+8]
    add esi, ecx
    jmp .t
.name:
    xor ecx, ecx
.nc:
    mov al, [esi+ecx]
    call n_letter
    je .nc1
    cmp al, '0'
    jb .nd2
    cmp al, '9'
    ja .nd2
.nc1:
    inc ecx
    jmp .nc
.nd2:
    mov edi, nl_kws             ; a keyword?
    mov edx, 1
.k:
    cmp byte [edi], 0
    je .nk
    movzx eax, byte [edi]
    cmp eax, ecx
    jne .kn
    push esi
    push edi
    push ecx
    inc edi
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    je .kw
.kn:
    movzx eax, byte [edi]
    lea edi, [edi+eax+1]
    inc edx
    jmp .k
.kw:
    call .newtok
    mov byte [ebx], TK_KW
    mov [ebx+1], dl
    add esi, ecx
    jmp .t
.nk:
    call .newtok
    mov byte [ebx], TK_NAME
    call .atom
    add esi, ecx
    jmp .t
.eof:
    call .newtok
    mov byte [ebx], TK_EOF
    mov eax, [nut_first]
    clc
    ret
.bad:
    mov esi, ne_char
    jmp .err
.badnum:
    mov esi, ne_number
    jmp .err
.unterm:
    mov esi, ne_quote
.err:
    mov [nut_errmsg], esi
    mov eax, [nut_line]
    mov [nut_errline], eax
    mov eax, [nut_first]        ; the tokens made so far are dropped
    mov [nut_ntok], eax
    stc
    ret
; -> ebx = a new token (the line set)
.newtok:
    mov ebx, [nut_ntok]
    cmp ebx, NUT_TOKS - 1
    jae .full
    inc dword [nut_ntok]
    shl ebx, 4
    add ebx, [nut_toks]
    mov dword [ebx], 0
    mov dword [ebx+4], 0
    mov dword [ebx+8], 0
    mov dword [ebx+12], 0
    mov eax, [nut_line]
    mov [ebx+2], ax
    ret
.full:
    add esp, 4
    mov esi, ne_toolong
    jmp .err
; esi = text, ecx = length -> a copy, at [ebx+4], length [ebx+8]
.atom:
    push esi
    push edi
    push ecx
    mov edi, [nut_atop]
    lea eax, [edi+ecx]
    cmp eax, NUT_ATOMS
    ja .afull
    mov [nut_atop], eax
    add edi, [nut_atoms]
    mov [ebx+4], edi
    mov [ebx+8], ecx
    rep movsb
    pop ecx
    pop edi
    pop esi
    ret
.afull:
    add esp, 16
    mov esi, ne_toolong
    jmp .err

; al -> ZF if a letter or _
n_letter:
    cmp al, '_'
    je .r
    push eax
    or al, 0x20
    cmp al, 'a'
    jb .no
    cmp al, 'z'
    ja .no
    cmp al, al
    pop eax
    ret
.no:
    test esp, esp
    pop eax
.r:
    ret

; ---------- for the host ----------
; esi = an expression -> eax = its first token, or CF
nut_compile:
    call nut_lex
    ret

; eax = an expression's first token, [nut_x] = x -> st0, or CF
; (eax = V_NUM; x is left as a global variable)
nut_eval_x:
    pushad
    mov [nut_sp], esp
    mov [nut_pos], eax
    call n_evinit
    fld qword [nut_x]           ; x is a global
    mov edi, nt_x
    mov eax, V_NUM
    call n_assign
    mov eax, [nut_vtop]
    mov [nut_gend], eax
    call n_num
    mov eax, V_NUM
    jmp n_evtail

; eax = an expression's first token -> eax = V_NUM (st0) or V_STR
; (edx = text, ecx = length), or CF (nut_errmsg)
nut_eval:
    pushad
    mov [nut_sp], esp
    mov [nut_pos], eax
    call n_evinit
    call n_expr
n_evtail:
    mov [nut_vtype], eax
    mov [nut_vstr], edx
    mov [nut_vlen], ecx
    call n_tok
    cmp byte [edi], TK_EOF
    je .ok
    cmp byte [edi], TK_NL
    je .ok
    cmp eax, V_STR
    je .bad
    fstp st0
.bad:
    mov esi, ne_syntax
    jmp nut_error
.ok:
    cmp eax, V_STR
    je .s
    fstp qword [nut_x2]
    popad
    mov eax, V_NUM
    fld qword [nut_x2]
    clc
    ret
.s:
    popad
    mov eax, V_STR
    mov edx, [nut_vstr]
    mov ecx, [nut_vlen]
    clc
    ret

n_evinit:
    mov byte [nut_skip], 0
    mov byte [nut_ret], 0
    mov byte [nut_brk], 0
    mov dword [nut_depth], 0
    mov dword [nut_steps], 0
    mov eax, [nut_vtop]
    mov [nut_fbase], eax
    mov [nut_gend], eax
    ret

; esi = a name, ecx = its length, eax = V_NUM (st0, popped) or V_STR
; (edx = text, ebx = length): a global variable is set. The name and a
; string are copied. CF when there is no room.
nut_setvar:
    pushad
    mov [nut_sp], esp
    push eax
    call n_evinit
    pop eax
    call n_hold                 ; esi, ecx -> esi = the copy
    jc .full
    mov [nut_ftok+4], esi
    mov [nut_ftok+8], ecx
    mov byte [nut_ftok], TK_NAME
    cmp eax, V_STR
    jne .set
    mov esi, edx
    mov ecx, ebx
    call n_hold
    jc .full
    mov edx, esi
.set:
    mov edi, nut_ftok
    call n_assign
    mov eax, [nut_vtop]
    mov [nut_gend], eax
    popad
    clc
    ret
.full:
    cmp eax, V_STR
    je .f2
    fstp st0
.f2:
    mov dword [nut_errmsg], ne_toolong
    popad
    stc
    ret

; esi = a name, ecx = its length -> st0 = the global number of that
; name, or CF (none, or a string)
nut_getnum:
    pushad
    mov [nut_ftok+4], esi
    mov [nut_ftok+8], ecx
    mov byte [nut_ftok], TK_NAME
    mov dword [nut_depth], 0
    mov eax, [nut_vtop]
    mov [nut_fbase], eax
    mov edi, nut_ftok
    call n_lookup
    jc .no
    cmp dword [ebx+8], V_NUM
    jne .no
    fld qword [ebx+16]
    fstp qword [nut_x2]
    popad
    fld qword [nut_x2]
    clc
    ret
.no:
    popad
    stc
    ret

; esi = text, ecx = length -> esi = a copy among the atoms, or CF
n_hold:
    push edi
    push ecx
    mov edi, [nut_atop]
    add edi, ecx
    cmp edi, NUT_ATOMS
    ja .no
    xchg edi, [nut_atop]
    add edi, [nut_atoms]
    push edi
    rep movsb
    pop esi
    pop ecx
    pop edi
    clc
    ret
.no:
    pop ecx
    pop edi
    stc
    ret

; ---------- data ----------
nt_x db TK_NAME, 0, 0, 0
     dd ns_x, 1
     dd 0, 0
ns_x db 'x', 0
ns_pi db 'pi'
align 8
nf_half dq 0.5
nf_2m24 dq 5.9604644775390625e-8
; operators: two characters (or one and a space), the id
nl_ops db '==', OP_EQ, '!=', OP_NE, '<>', OP_NE, '<=', OP_LE, '>=', OP_GE
       db '+ ', OP_PLUS, '- ', OP_MINUS, '* ', OP_STAR, '/ ', OP_SLASH
       db '^ ', OP_CARET, '% ', OP_PCT, '( ', OP_LP, ') ', OP_RP
       db ', ', OP_COMMA, '= ', OP_SET, '< ', OP_LT, '> ', OP_GT, 0
nl_kws db 3, 'let', 2, 'if', 4, 'then', 4, 'else', 4, 'elif', 3, 'end'
       db 5, 'while', 2, 'do', 3, 'for', 2, 'to', 4, 'step', 2, 'fn'
       db 6, 'return', 5, 'print', 3, 'and', 2, 'or', 3, 'not'
       db 5, 'break', 4, 'true', 5, 'false', 0
nb_names db 3, 'sin', 3, 'cos', 3, 'tan', 4, 'atan', 4, 'asin', 4, 'acos'
         db 4, 'sqrt', 3, 'abs', 2, 'ln', 3, 'exp', 5, 'floor', 4, 'ceil'
         db 5, 'round', 3, 'min', 3, 'max', 3, 'len', 3, 'str', 3, 'num'
         db 3, 'rnd', 0
nb_args db 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 9, 9, 1, 1, 1, 0
align 4
nb_code dd nb_sin, nb_cos, nb_tan, nb_atan, nb_asin, nb_acos, nb_sqrt
        dd nb_abs, nb_ln, nb_exp, nb_floor, nb_ceil, nb_round, nb_min
        dd nb_max, nb_len, nb_str, nb_tonum, nb_rnd
nk_want dd ne_syntax, ne_syntax, ne_syntax, ne_then, ne_syntax, ne_syntax
        dd ne_end, ne_syntax, ne_do, ne_syntax, ne_to, ne_syntax
ne_syntax db 'this cannot be read here', 0
ne_rp db 'a ) is missing', 0
ne_then db 'then is missing', 0
ne_do db 'do is missing', 0
ne_to db 'to is missing', 0
ne_end db 'end is missing', 0
ne_noend db 'the function has no end', 0
ne_stray db 'an end, else or elif without a start', 0
ne_more db 'something is missing at the end', 0
ne_steps db 'too many steps (a loop that never ends?)', 0
ne_deep db 'calls too deep', 0
ne_fns db 'too many functions', 0
ne_vars db 'too many variables', 0
ne_params db 'too many parameters', 0
ne_nargs db 'the wrong number of arguments', 0
ne_rettop db 'return outside a function', 0
ne_notnum db 'a number is needed', 0
ne_strop db 'strings can only be joined with +', 0
ne_strmem db 'out of string memory', 0
ne_div0 db 'division by zero', 0
ne_unknown db 'unknown variable', 0
ne_nofn db 'unknown function', 0
ne_domain db 'outside the function domain', 0
ne_char db 'a character that means nothing here', 0
ne_number db 'a number that cannot be read', 0
ne_quote db 'a string without its closing quote', 0
ne_toolong db 'the program is too long', 0

; zeroed data: put NUT_BSS after SQX_BSS
%macro NUT_BSS 0
alignb 8
nut_x       resq 1
nut_x2      resq 1
nut_rnum    resq 1
nut_toks    resd 1
nut_atoms   resd 1
nut_sheap   resd 1
nut_out     resd 1
nut_ntok    resd 1
nut_first   resd 1
nut_atop    resd 1
nut_stop    resd 1
nut_olen    resd 1
nut_pos     resd 1
nut_sp      resd 1
nut_line    resd 1
nut_steps   resd 1
nut_depth   resd 1
nut_vtop    resd 1
nut_gend    resd 1
nut_fbase   resd 1
nut_nfn     resd 1
nut_rtype   resd 1
nut_tmpi    resd 1
nut_seed    resd 1
nut_errmsg  resd 1
nut_errline resd 1
nut_vtype   resd 1
nut_vstr    resd 1
nut_vlen    resd 1
nut_ftok    resb TK_SIZE
nut_skip    resb 1
nut_ret     resb 1
nut_brk     resb 1
alignb 4
nut_ev      resb GE_SIZE
nut_nbuf    resb 48
nut_nbuf2   resb 64
nut_fnscratch resb FN_SIZE
nut_vars    resb NUT_VARS * VR_SIZE
nut_fns     resb NUT_FNS * FN_SIZE
%endmacro
