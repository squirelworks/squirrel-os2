; Squirrel-OS/2 — calculus calculator (diff), 1.0.7; integrals 1.0.8; ODEs 1.0.10
; Included from pm.asm. Original code.
;
; Numerical calculus on top of the scientific evaluator (sci.asm): the
; function is an ordinary sci expression in the variable x, evaluated again
; for every sample point. No symbolic rules and no second math library.
;
;   d <f(x)> at <x0>          derivative, central difference
;   i <f(x)> from <a> to <b>  integral, composite Simpson rule
;   euler <f(x,y)> from <x0> to <x1> y0 <y0> step <h>
;                             y' = f(x, y), Euler's method
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
    mov esi, [lstr+LS_CALC_ERRPRE*4]
    call puts
    mov esi, [calc_errmsg]
    call puts
    lcmp calc_errmsg, LS_CALC_E_SYNTAX
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
    mov byte [diff_vars], 1     ; f may use x; euler also allows y
    mov edi, diff_kw_d
    call calc_match
    jnc diff_deriv
    mov edi, diff_kw_i
    call calc_match
    jnc diff_integ
    mov edi, diff_kw_euler
    call calc_match
    jnc diff_euler
    jmp calc_syntax

; "d f at x0": (f(x0+h) - f(x0-h)) / 2h with h = 1e-5 * max(1, |x0|).
; The error of the central difference shrinks with h^2; with the FPU's
; 64-bit mantissa, rounding stays far below the 10 digits sci_fmt prints.
diff_deriv:
    mov [diff_f], esi
    mov edi, diff_kw_at
    call diff_cut
    jc .r
    call diff_value             ; x0 may not use x
    jc .r
    fstp qword [diff_x0]
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

; "i f from a to b": composite Simpson rule on DIFF_N (even) panels,
; (h/3) * (f0 + 4 f1 + 2 f2 + ... + 4 f(n-1) + fn). The error shrinks with
; h^4, so smooth functions come out right to the 10 digits printed.
; b < a gives the negative integral, a = b gives 0.
diff_integ:
    mov [diff_f], esi
    mov edi, diff_kw_from
    call diff_cut
    jc .r
    push esi                    ; a's text
    mov edi, diff_kw_to
    call diff_cut
    pop ebx
    jc .r
    push esi                    ; b's text
    mov esi, ebx
    call diff_value
    pop esi
    jc .r
    fstp qword [diff_x0]        ; a
    call diff_value
    jc .r
    fsub qword [diff_x0]
    fidiv dword [diff_n]
    fstp qword [diff_h]         ; h = (b - a) / n
    fldz
    fstp qword [diff_t]         ; running sum
    xor ecx, ecx
.panel:
    mov [diff_i], ecx           ; x = a + i*h, not a running sum
    fild dword [diff_i]
    fmul qword [diff_h]
    fadd qword [diff_x0]
    push ecx
    call diff_f_at
    pop ecx
    jc .r
    ; weight 1 at the ends, else 4 for odd i and 2 for even i
    test ecx, ecx
    jz .add
    cmp ecx, [diff_n]
    je .add
    fadd st0, st0               ; x2
    test ecx, 1
    jz .add
    fadd st0, st0               ; x4
.add:
    fadd qword [diff_t]
    fstp qword [diff_t]
    inc ecx
    cmp ecx, [diff_n]
    jbe .panel
    fld qword [diff_t]
    fmul qword [diff_h]
    fdiv qword [diff_three]
    jmp diff_status
.r:
    ret

; "euler f from x0 to x1 y0 v step h": y' = f(x, y) with y(x0) = v, by
; Euler's method, y += h * f(x, y). The step is adjusted so that a whole
; number n = round(|x1 - x0| / h) of steps lands exactly on x1 (at least
; one step when x1 differs from x0); x = x0 + i*h, not a running sum.
diff_euler:
    mov byte [diff_vars], 2
    mov [diff_f], esi
    mov edi, diff_kw_from
    call diff_cut
    jc .r
    mov [diff_tx0], esi
    mov edi, diff_kw_to
    call diff_cut
    jc .r
    mov [diff_tx1], esi
    mov edi, diff_kw_y0
    call diff_cut
    jc .r
    mov [diff_ty0], esi
    mov edi, diff_kw_step
    call diff_cut
    jc .r
    call diff_value             ; h
    jc .r
    fstp qword [diff_h]
    mov esi, [diff_ty0]
    call diff_value
    jc .r
    fstp qword [sci_y]
    mov esi, [diff_tx1]
    call diff_value
    jc .r
    mov esi, [diff_tx0]
    call diff_value
    jc .r
    fst qword [diff_x0]
    fsubp st1, st0              ; x1 - x0
    fldz
    fcomp qword [diff_h]
    fnstsw ax
    sahf
    jae .badstep                ; h <= 0 (or not a number)
    fld st0
    fabs
    fdiv qword [diff_h]
    fcom qword [diff_maxn]
    fnstsw ax
    sahf
    ja .many
    frndint
    fistp dword [diff_n2]
    cmp dword [diff_n2], 0
    jne .n
    ftst                        ; x1 = x0: no step; else one step
    fnstsw ax
    sahf
    je .n
    mov dword [diff_n2], 1
.n:
    cmp dword [diff_n2], 0
    je .done
    fidiv dword [diff_n2]
    fstp qword [diff_h]         ; signed step that lands on x1
    xor ecx, ecx
.step:
    mov [diff_i], ecx
    fild dword [diff_i]
    fmul qword [diff_h]
    fadd qword [diff_x0]        ; x
    push ecx
    call diff_f_at              ; f(x, y)
    pop ecx
    jc .r
    fmul qword [diff_h]
    fadd qword [sci_y]
    fstp qword [sci_y]
    inc ecx
    cmp ecx, [diff_n2]
    jb .step
    fldz
.done:
    fstp st0
    fld qword [sci_y]
    jmp diff_status
.badstep:
    mov dword [calc_errmsg], diff_e_step
    stc
    ret
.many:
    mov dword [calc_errmsg], diff_e_many
    stc
.r:
    ret

; Finds the word edi (" at ", " from ", ...) at or after esi, ends the
; text before it with a 0, and returns esi just after the word. CF with
; a syntax error at the end of the line when the word is missing.
diff_cut:
.scan:
    mov al, [esi]
    test al, al
    jz calc_syntax
    cmp al, ' '
    jne .next
    push esi
    push edi
    inc esi
.cmp:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .cmp
.end:
    mov al, [esi]
    cmp al, ' '
    je .found
    test al, al
    je .found
.no:
    pop edi
    pop esi
.next:
    inc esi
    jmp .scan
.found:
    pop edi
    pop eax
    mov byte [eax], 0           ; ends the text before the word
    clc
    ret

; esi = a whole ASCIIZ sci expression without x -> st0, or CF.
diff_value:
    call sci_expr
    jc .r
    call calc_skip
    cmp byte [esi], 0
    jne calc_syntax
    clc
.r:
    ret

; st0 = x -> st0 = f(x). CF with calc_errmsg on a syntax error.
diff_f_at:
    fstp qword [sci_x]
    push esi
    mov esi, [diff_f]
    mov al, [diff_vars]
    mov [sci_xok], al
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
diff_help db 'd <f(x)> at <x0>            derivative, e.g.  d sin(x) at 0', 10
          db 'i <f(x)> from <a> to <b>    integral,   e.g.  i x^2 from 0 to 3', 10
          db "euler <f(x,y)> from <x0> to <x1> y0 <y> step <h>   ODE y' = f, Euler", 10
          db 'f is a sci expression in x (and y); angles are radians. q quits', 10, 0
diff_help_len equ $ - diff_help - 1
diff_prompt db 'diff> ', 0
diff_kw_d db 'd', 0
diff_kw_i db 'i', 0
diff_kw_at db 'at', 0
diff_kw_from db 'from', 0
diff_kw_to db 'to', 0
diff_kw_euler db 'euler', 0
diff_kw_y0 db 'y0', 0
diff_kw_step db 'step', 0
diff_e_step db 'step must be greater than 0', 0
diff_e_many db 'more than 100000 steps', 0

align 8
diff_hrel dq 1.0e-5
diff_half dq 0.5
diff_three dq 3.0
diff_x0 dq 0.0
diff_h dq 0.0
diff_t dq 0.0
diff_f dd 0
DIFF_N equ 1000
diff_n dd DIFF_N                ; Simpson panels, even
diff_i dd 0
diff_vars db 1                  ; sci_xok while f is evaluated
align 4
diff_n2 dd 0                    ; Euler steps
diff_tx0 dd 0                   ; texts of x0, x1 and y0
diff_tx1 dd 0
diff_ty0 dd 0
align 8
diff_maxn dq 100000.0
