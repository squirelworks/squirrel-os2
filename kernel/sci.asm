; Squirrel-OS/2 — scientific calculator (sci), 0.3.4
; Included from pm.asm. Original code.
;
; Floating-point expressions on the x87 FPU: + - * / ^, parentheses,
; unary minus, constants pi and e, ans, and the functions sin cos tan
; asin acos atan sqrt ln log exp abs. Degree or radian mode.
; See documentation/apps/calculators.md.
;
; Values travel in st0. A binary operator parks its left operand on the
; CPU stack, so the FPU stack never holds more than a few entries however
; deep the expression nests. Errors come back with CF set.

; FPU status word exception bits (all exceptions stay masked)
FPU_IE      equ 0x01
FPU_ZE      equ 0x04
FPU_OE      equ 0x08

; Enables the FPU (CR0: MP and NE set, EM and TS clear) and resets it.
fpu_init:
    mov eax, cr0
    and eax, ~((1 << 2) | (1 << 3))
    or eax, (1 << 1) | (1 << 5)
    mov cr0, eax
    fninit
    ret

run_sci:
    call cls
    mov esi, sci_banner
    call puts
    mov esi, sci_help
    call puts
.prompt:
    call sci_show_mode
    mov esi, sci_prompt
    call puts
    call calc_readline
    jc .quit
    mov esi, calc_line
    call calc_skip
    cmp byte [esi], 0
    je .prompt
    mov edi, calc_kw_q
    call streq
    je .quit
    mov edi, calc_kw_quit
    call streq
    je .quit
    mov edi, sci_kw_deg
    call streq
    je .deg
    mov edi, sci_kw_rad
    call streq
    je .rad
    call sci_line_eval
    jc .error
    fst qword [sci_ans]
    mov esi, calc_eq
    call puts
    call sci_fmt                ; pops st0
    mov esi, sci_out
    call puts
    mov al, 10
    call putc
    jmp .prompt
.error:
    fninit
    mov esi, calc_errpre
    call puts
    mov esi, [calc_errmsg]
    call puts
    cmp dword [calc_errmsg], calc_e_syntax
    jne .errnl
    mov eax, [calc_errpos]
    sub eax, calc_line
    inc eax
    call itoa
    mov esi, num_buf
    call puts
.errnl:
    mov al, 10
    call putc
    jmp .prompt
.deg:
    mov byte [sci_deg], 1
    jmp .prompt
.rad:
    mov byte [sci_deg], 0
    jmp .prompt
.quit:
    call cls
    mov esi, banner
    call puts
    xor eax, eax
    ret

sci_show_mode:
    mov esi, sci_m_rad
    cmp byte [sci_deg], 0
    je .p
    mov esi, sci_m_deg
.p:
    jmp puts

; Evaluates calc_line -> st0, or CF with calc_errmsg / calc_errpos set.
sci_line_eval:
    fninit
    mov esi, calc_line
    call sci_expr
    jc .r
    call calc_skip
    cmp byte [esi], 0
    jne calc_syntax
    ; a masked exception means the result is not a usable number
    fnstsw ax
    test al, FPU_ZE
    jnz calc_div0
    test al, FPU_IE
    jnz sci_domain
    test al, FPU_OE
    jnz calc_overflow
    clc
.r:
    ret

sci_domain:
    mov dword [calc_errmsg], sci_e_domain
    stc
    ret

; ---------- recursive descent ----------
; expr  := term { (+|-) term }
; term  := unary { (*|/) unary }
; unary := (-|+) unary | power
; power := primary [ ^ unary ]
; primary := number | pi | e | ans | func ( expr ) | ( expr )

sci_expr:
    call sci_term
    jc .r
.more:
    call calc_skip
    mov al, [esi]
    cmp al, '+'
    je .op
    cmp al, '-'
    je .op
    clc
.r:
    ret
.op:
    inc esi
    sub esp, 8
    fstp qword [esp]
    push eax
    call sci_term
    pop eax
    jc .fail
    cmp al, '+'
    je .add
    fsubr qword [esp]           ; left - right
    jmp .done
.add:
    fadd qword [esp]
.done:
    add esp, 8
    jmp .more
.fail:
    lea esp, [esp+8]            ; keeps CF
    ret

sci_term:
    call sci_unary
    jc .r
.more:
    call calc_skip
    mov al, [esi]
    cmp al, '*'
    je .op
    cmp al, '/'
    je .op
    clc
.r:
    ret
.op:
    inc esi
    sub esp, 8
    fstp qword [esp]
    push eax
    call sci_unary
    pop eax
    jc .fail
    cmp al, '*'
    je .mul
    ftst                        ; right operand zero?
    fnstsw ax
    sahf
    je .div0
    fdivr qword [esp]           ; left / right
    jmp .done
.mul:
    fmul qword [esp]
.done:
    add esp, 8
    jmp .more
.div0:
    add esp, 8
    jmp calc_div0
.fail:
    lea esp, [esp+8]
    ret

sci_unary:
    call calc_skip
    cmp byte [esi], '-'
    je .neg
    cmp byte [esi], '+'
    jne sci_power
    inc esi
    jmp sci_unary
.neg:
    inc esi
    call sci_unary
    jc .r
    fchs
.r:
    ret

sci_power:
    call sci_primary
    jc .r
    call calc_skip
    cmp byte [esi], '^'
    jne .ok
    inc esi
    sub esp, 8
    fstp qword [esp]            ; base
    call sci_unary              ; exponent (right-associative)
    jc .fail
    fld qword [esp]
    add esp, 8
    jmp sci_pow                 ; st0 = base, st1 = exponent
.ok:
    clc
.r:
    ret
.fail:
    lea esp, [esp+8]
    ret

sci_primary:
    call calc_skip
    mov al, [esi]
    cmp al, '('
    je .paren
    cmp al, '.'
    je .num
    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .num
.word:
    mov ebx, sci_funcs
.f:
    mov edi, [ebx]
    test edi, edi
    jz .consts
    call calc_match
    jnc .func
    add ebx, 8
    jmp .f
.func:
    call calc_skip
    cmp byte [esi], '('
    jne calc_syntax
    push ebx
    call .paren
    pop ebx
    jc .r
    jmp [ebx+4]
.consts:
    mov edi, sci_kw_pi
    call calc_match
    jc .notpi
    fldpi
    clc
    ret
.notpi:
    mov edi, calc_kw_ans
    call calc_match
    jc .note
    fld qword [sci_ans]
    clc
    ret
.note:
    mov edi, sci_kw_e
    call calc_match
    jc calc_syntax
    fldl2e                      ; e = 2^(log2 e)
    jmp sci_exp2
.paren:
    inc esi
    call sci_expr
    jc .r
    call calc_skip
    cmp byte [esi], ')'
    jne calc_syntax
    inc esi
    clc
.r:
    ret
.num:
    jmp sci_number

; number := digits [. digits] [e [+|-] digits]  -> st0
sci_number:
    fldz
    xor ecx, ecx                ; digits after the point
    xor edx, edx                ; 1 once a digit was seen
.int:
    movzx eax, byte [esi]
    sub eax, '0'
    cmp eax, 9
    ja .point
    call .digit
    inc esi
    jmp .int
.point:
    cmp byte [esi], '.'
    jne .exp
    inc esi
.frac:
    movzx eax, byte [esi]
    sub eax, '0'
    cmp eax, 9
    ja .exp
    call .digit
    inc ecx
    inc esi
    jmp .frac
.exp:
    test edx, edx
    jz .bad                     ; a lone "."
    neg ecx                     ; decimal exponent so far
    cmp byte [esi], 'e'
    jne .scale
    mov al, [esi+1]             ; "e" not followed by a number is the constant
    cmp al, '-'
    je .esign
    cmp al, '+'
    je .esign
    sub al, '0'
    cmp al, 9
    ja .scale
    inc esi
    jmp .edig
.esign:
    mov al, [esi+2]
    sub al, '0'
    cmp al, 9
    ja .scale
    inc esi
.edig:
    xor ebx, ebx
    mov ah, [esi]               ; sign character or first digit
    cmp ah, '-'
    je .es
    cmp ah, '+'
    jne .ed
.es:
    inc esi
.ed:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .eend
    imul ebx, ebx, 10
    add ebx, edx
    cmp ebx, 9999
    ja .big
    inc esi
    jmp .ed
.eend:
    cmp ah, '-'
    jne .eadd
    neg ebx
.eadd:
    add ecx, ebx
.scale:
    test ecx, ecx
    jz .ok
    push ecx
    call sci_pow10              ; st0 = 10^ecx, st1 = mantissa
    pop ecx
    fmulp st1, st0
.ok:
    clc
    ret
.digit:                         ; st0 = st0 * 10 + eax
    mov edx, 1
    fmul dword [sci_ten]
    push eax
    fiadd dword [esp]
    pop eax
    ret
.bad:
    fstp st0
    jmp calc_syntax
.big:
    fstp st0
    jmp calc_overflow

; ecx = integer -> pushes 10^ecx
sci_pow10:
    push ecx
    fild dword [esp]
    pop ecx
    fldl2t
    fmulp st1, st0
    jmp sci_exp2

; st0 = t -> st0 = 2^t (any t; out-of-range results overflow to inf)
sci_exp2:
    fld st0
    frndint                     ; st0 = n, st1 = t
    fsub st1, st0               ; st1 = t - n, |t - n| <= 0.5
    fxch                        ; st0 = f, st1 = n
    f2xm1
    fld1
    faddp st1, st0              ; st0 = 2^f
    fscale                      ; st0 = 2^f * 2^n
    fstp st1
    clc
    ret

; st0 = base x, st1 = exponent y -> st0 = x^y
sci_pow:
    ftst
    fnstsw ax
    sahf
    je .zero
    jb .neg
    fyl2x                       ; y * log2 x
    jmp sci_exp2
.zero:                          ; 0^y: 0 for y > 0, otherwise undefined
    fstp st0
    ftst
    fnstsw ax
    sahf
    fstp st0
    jbe sci_domain
    fldz
    clc
    ret
.neg:                           ; negative base: only whole exponents
    fabs
    fld st1
    frndint
    fcomp st2
    fnstsw ax
    sahf
    jne .nonint
    ; parity of y: y/2 whole means even
    fld st1
    fmul dword [sci_half]
    fld st0
    frndint
    fcompp
    fnstsw ax
    sahf
    pushf
    fyl2x
    call sci_exp2
    popf
    je .even
    fchs
.even:
    clc
    ret
.nonint:
    fstp st0
    fstp st0
    jmp sci_domain

; ---------- functions: argument in st0 ----------
sci_to_rad:
    cmp byte [sci_deg], 0
    je .r
    fldpi
    fmulp st1, st0
    fdiv dword [sci_180]
.r:
    ret

sci_from_rad:
    cmp byte [sci_deg], 0
    je .r
    fmul dword [sci_180]
    fldpi
    fdivp st1, st0
.r:
    clc
    ret

sci_f_sin:
    call sci_to_rad
    fsin
    clc
    ret
sci_f_cos:
    call sci_to_rad
    fcos
    clc
    ret
sci_f_tan:
    call sci_to_rad
    fptan
    fstp st0                    ; fptan pushes 1.0
    clc
    ret
sci_f_atan:
    fld1
    fpatan                      ; atan(st1 / 1)
    jmp sci_from_rad
sci_f_asin:                     ; atan2(x, sqrt(1 - x^2))
    call sci_unit
    jc .r
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fpatan
    jmp sci_from_rad
.r:
    ret
sci_f_acos:                     ; atan2(sqrt(1 - x^2), x)
    call sci_unit
    jc .r
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fxch
    fpatan
    jmp sci_from_rad
.r:
    ret
sci_f_sqrt:
    ftst
    fnstsw ax
    sahf
    jb .bad
    fsqrt
    clc
    ret
.bad:
    fstp st0
    jmp sci_domain
sci_f_ln:
    fldln2
    jmp sci_log
sci_f_log:
    fldlg2
sci_log:                        ; st0 = log base constant, st1 = x
    fxch
    ftst
    fnstsw ax
    sahf
    jbe .bad
    fyl2x                       ; c * log2 x
    clc
    ret
.bad:
    fstp st0
    fstp st0
    jmp sci_domain
sci_f_exp:
    fldl2e
    fmulp st1, st0
    jmp sci_exp2
sci_f_abs:
    fabs
    clc
    ret

; CF + domain error unless -1 <= st0 <= 1
sci_unit:
    fld1
    fld st1
    fabs
    fcompp                      ; |x| against 1
    fnstsw ax
    sahf
    ja .bad
    clc
    ret
.bad:
    fstp st0
    jmp sci_domain

; ---------- output ----------
; Formats st0 (popped) into sci_out: up to 10 significant digits, plain
; notation for 1e-6 <= |x| < 1e15, otherwise d.ddddddddde[-]n.
sci_fmt:
    pushad
    mov edi, sci_out
    ftst
    fnstsw ax
    sahf
    jne .nz
    fstp st0
    mov word [edi], '0'
    jmp .out
.nz:
    jae .pos
    mov byte [edi], '-'
    inc edi
    fabs
.pos:
    ; e = floor(log10 x): round, then correct against 10^e
    fldlg2
    fld st1
    fyl2x
    fistp dword [sci_tmp]
    mov ecx, [sci_tmp]
    call sci_cmp10
    jnc .notlow
    dec ecx
    jmp .ehave
.notlow:
    inc ecx
    call sci_cmp10
    jc .back
    jmp .ehave
.back:
    dec ecx
.ehave:
    cmp ecx, -6
    jl .sci
    cmp ecx, 15
    jl .plain
.sci:
    push ecx
    neg ecx
    call sci_pow10
    fmulp st1, st0              ; mantissa in [1, 10)
    pop ecx
    mov ebx, 9
    call sci_round
    ; rounding may give 10.000000000: 10^10 = 0x2540BE400
    cmp dword [sci_int+4], 2
    jb .mant
    ja .carry
    cmp dword [sci_int], 0x540BE400
    jb .mant
.carry:
    mov eax, [sci_int]
    mov edx, [sci_int+4]
    push ebx
    call sci_div10
    pop ebx
    mov [sci_int], eax
    mov [sci_int+4], edx
    inc ecx
.mant:
    call sci_emit
    mov byte [edi], 'e'
    inc edi
    mov eax, ecx
    push edi
    call itoa
    pop edi
    mov esi, num_buf
.ecopy:
    lodsb
    stosb
    test al, al
    jnz .ecopy
    jmp .out
.plain:
    mov ebx, 9
    sub ebx, ecx                ; decimals for 10 significant digits
    jns .dec
    xor ebx, ebx
.dec:
    call sci_round
    call sci_emit
.out:
    popad
    ret

; x (st0) against 10^ecx; st0 is kept. CF set when x < 10^ecx.
sci_cmp10:
    push ecx
    call sci_pow10
    pop ecx
    fcomp st1                   ; 10^ecx against x
    fnstsw ax
    sahf
    ja .low
    clc
    ret
.low:
    stc
    ret

; st0 = x (popped), ebx = decimals -> sci_int = round(x * 10^ebx)
sci_round:
    push ecx
    mov ecx, ebx
    call sci_pow10
    fmulp st1, st0
    fistp qword [sci_int]
    pop ecx
    ret

; edx:eax / 10 -> edx:eax quotient, ebx remainder
sci_div10:
    push ecx
    mov ecx, eax
    mov eax, edx
    xor edx, edx
    div dword [sci_ten_i]
    xchg eax, ecx               ; ecx = high quotient, eax = low half
    div dword [sci_ten_i]
    mov ebx, edx
    mov edx, ecx
    pop ecx
    ret

; Writes sci_int with ebx implied decimals at edi (advanced, zero
; terminated); trailing fraction zeros and a bare point are dropped.
sci_emit:
    push ecx
    push esi
    mov esi, ebx                ; decimals
    mov eax, [sci_int]
    mov edx, [sci_int+4]
    xor ecx, ecx
.dg:                            ; digits, least significant first
    push ebx
    call sci_div10
    add bl, '0'
    mov [sci_digs+ecx], bl
    pop ebx
    inc ecx
    mov ebx, eax
    or ebx, edx
    jnz .dg
.pad:                           ; at least one digit before the point
    cmp ecx, esi
    ja .int
    mov byte [sci_digs+ecx], '0'
    inc ecx
    jmp .pad
.int:
    mov al, [sci_digs+ecx-1]
    stosb
    dec ecx
    cmp ecx, esi
    ja .int
    ; ecx = decimals left; skip trailing zeros
    xor ebx, ebx
.tz:
    cmp ebx, ecx
    jae .end
    cmp byte [sci_digs+ebx], '0'
    jne .frac
    inc ebx
    jmp .tz
.frac:
    mov al, '.'
    stosb
.fd:
    mov al, [sci_digs+ecx-1]
    stosb
    dec ecx
    cmp ecx, ebx
    ja .fd
.end:
    mov byte [edi], 0
    pop esi
    pop ecx
    ret

sci_funcs:
    dd sci_n_sin, sci_f_sin
    dd sci_n_cos, sci_f_cos
    dd sci_n_tan, sci_f_tan
    dd sci_n_asin, sci_f_asin
    dd sci_n_acos, sci_f_acos
    dd sci_n_atan, sci_f_atan
    dd sci_n_sqrt, sci_f_sqrt
    dd sci_n_ln, sci_f_ln
    dd sci_n_log, sci_f_log
    dd sci_n_exp, sci_f_exp
    dd sci_n_abs, sci_f_abs
    dd 0, 0
sci_n_sin db 'sin', 0
sci_n_cos db 'cos', 0
sci_n_tan db 'tan', 0
sci_n_asin db 'asin', 0
sci_n_acos db 'acos', 0
sci_n_atan db 'atan', 0
sci_n_sqrt db 'sqrt', 0
sci_n_ln db 'ln', 0
sci_n_log db 'log', 0
sci_n_exp db 'exp', 0
sci_n_abs db 'abs', 0
sci_kw_pi db 'pi', 0
sci_kw_e db 'e', 0
sci_kw_deg db 'deg', 0
sci_kw_rad db 'rad', 0

sci_banner db 'Scientific Calculator', 10, 0
sci_help db 'Numbers like 2.5 or 6.02e23; + - * / ^ ( ); pi e ans', 10
         db 'sin cos tan asin acos atan sqrt ln log exp abs', 10
         db 'deg / rad switch angle mode; q or Esc quits', 10, 0
sci_help_len equ $ - sci_help - 1
sci_prompt db 'sci> ', 0
sci_m_rad db '[rad] ', 0
sci_m_deg db '[deg] ', 0
sci_e_domain db 'outside the function domain', 0

align 4
sci_ten dd 10.0
sci_half dd 0.5
sci_180 dd 180.0
sci_ten_i dd 10
sci_tmp dd 0
sci_deg db 0
align 8
sci_ans dq 0.0
sci_int dq 0
sci_digs times 24 db 0
sci_out times 40 db 0
