; Squirrel-OS/2 — calculus calculator (diff), 1.0.7
; Included from pm.asm. Original code.
;
; Numerical calculus on top of the scientific evaluator (sci.asm): the
; function is an ordinary sci expression in the variable x, evaluated again
; for every sample point. No symbolic rules and no second math library.
;
;   d <f(x)> at <x0>      derivative, central difference
;
; Angles are always radians here. See documentation/apps/calculators.md.

run_diff:
    call cls
    mov esi, diff_banner
    call puts
    mov esi, diff_help
    call puts
.prompt:
    mov esi, diff_prompt
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
    mov al, [sci_deg]           ; sin(x) and friends take radians here
    push eax
    mov byte [sci_deg], 0
    call diff_command
    pop ebx
    mov [sci_deg], bl
    jc .error
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
.quit:
    call app_home
    xor eax, eax
    ret

; esi = command line (skipped) -> st0 = result, or CF with calc_errmsg set.
diff_command:
    fninit
    mov edi, diff_kw_d
    call calc_match
    jnc diff_deriv
    jmp calc_syntax

; "d f at x0": (f(x0+h) - f(x0-h)) / 2h with h = 1e-5 * max(1, |x0|).
; The error of the central difference shrinks with h^2; with the FPU's
; 64-bit mantissa, rounding stays far below the 10 digits sci_fmt prints.
diff_deriv:
    call diff_split
    jc .r
    fld qword [diff_x0]
    fabs
    fld1
    fcom st1
    fnstsw ax
    sahf
    jae .small                  ; |x0| <= 1: use 1
    fxch st1
.small:
    fstp st1
    fmul qword [diff_hrel]
    fstp qword [diff_h]
    fld qword [diff_x0]
    fadd qword [diff_h]
    call diff_f_at
    jc .r
    fstp qword [diff_t]
    fld qword [diff_x0]
    fsub qword [diff_h]
    call diff_f_at
    jc .r
    fsubr qword [diff_t]        ; f(x0+h) - f(x0-h)
    fdiv qword [diff_h]
    fmul qword [diff_half]
    jmp diff_status
.r:
    ret

; Splits "f at x0" at the word "at": the function stays in place, ended
; by a 0, and x0 is evaluated into diff_x0. CF with calc_errmsg on error.
diff_split:
    mov [diff_f], esi
.scan:
    mov al, [esi]
    test al, al
    jz .none
    cmp al, ' '
    jne .next
    cmp word [esi+1], 'at'
    jne .next
    mov al, [esi+3]
    cmp al, ' '
    je .found
    test al, al
    je .found
.next:
    inc esi
    jmp .scan
.found:
    mov byte [esi], 0           ; ends the function text
    add esi, 3
    call sci_expr               ; x0 may not use x
    jc .r
    call calc_skip
    cmp byte [esi], 0
    jne calc_syntax
    fstp qword [diff_x0]
    clc
.r:
    ret
.none:
    jmp calc_syntax             ; points at the end of the line

; st0 = x -> st0 = f(x). CF with calc_errmsg on a syntax error.
diff_f_at:
    fstp qword [sci_x]
    push esi
    mov esi, [diff_f]
    mov byte [sci_xok], 1
    call sci_expr
    mov byte [sci_xok], 0
    jc .r
    call calc_skip
    cmp byte [esi], 0
    je .ok
    call calc_syntax
    jmp .r
.ok:
    clc
.r:
    pop esi
    ret

; Turns the FPU's sticky exception flags into an error, as sci does.
diff_status:
    fnstsw ax
    test al, FPU_ZE
    jnz calc_div0
    test al, FPU_IE
    jnz sci_domain
    test al, FPU_OE
    jnz calc_overflow
    clc
    ret

diff_banner db 'Calculus Calculator (Esc to exit)', 10, 0
diff_help db 'd <f(x)> at <x0>   derivative, e.g.  d sin(x) at 0', 10
          db 'f(x) is a sci expression in x; angles are radians. q quits', 10, 0
diff_help_len equ $ - diff_help - 1
diff_prompt db 'diff> ', 0
diff_kw_d db 'd', 0

align 8
diff_hrel dq 1.0e-5
diff_half dq 0.5
diff_x0 dq 0.0
diff_h dq 0.0
diff_t dq 0.0
diff_f dd 0
