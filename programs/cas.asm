; Squirrel-OS/2 — CAS: computer algebra in a window (C.5, OS2-APPS)
; Original code. run cas   |   run cas test
;
; A console: type a command, Enter shows the answer under it.
;   simplify(e)       (or e alone)  like terms and powers collected
;   expand(e)         products and whole powers multiplied out
;   factor(p)         a polynomial in x over the rationals
;   solve(p) solve(a = b)   x exactly for polynomials (rational roots,
;                     then the quadratic formula, complex as a + b*i),
;                     numerically otherwise (x ~ ...)
;   diff(e) diff(e, n)      derivative (n-th) in x
;   integrate(e)  int(e)    an antiderivative in x (+ C)
;   int(e, a, b)      definite integral: exact if an antiderivative is
;                     found, otherwise numeric (Simpson)
;   limit(e, a)       a may be inf or -inf; l'Hopital for 0/0
;   series(e, a, n)   Taylor polynomial about a to degree n (a = 0,
;                     n = 5 if left out)
; Expressions: numbers (exact rationals; 2.5 is 5/2), x and other
; single letters, pi, e, ans (the last answer), + - * / ^, implicit
; products (2x, 3(x+1)), and sin cos tan asin acos atan exp ln (log)
; sqrt abs. Constant results that are not rational also show "~ 1.23".
;
; Keys: Enter run, Backspace, Up/Down earlier inputs, PgUp/PgDn scroll,
; Esc quit. "run cas test" checks every command against known answers
; and prints "cas: PASS". See documentation/apps/cas.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

POOL_N      equ 32768                   ; expression nodes (16 bytes)
LIST_N      equ 16384                   ; work lists
POLY_DEG    equ 31
POLY_SZ     equ 8 + (POLY_DEG + 1) * 8
IMAX        equ 120                     ; an input line
OUT_MAX     equ 1000
HIST        equ 160                     ; console lines
COLS        equ 52
NHIST_IN    equ 12

N_NUM       equ 1                       ; node types (also their order)
N_FLT       equ 2
N_CON       equ 3
N_VAR       equ 4
N_POW       equ 5
N_FN        equ 6
N_MUL       equ 7
N_ADD       equ 8
N_UNDEF     equ 9

F_SIN       equ 1                       ; functions
F_COS       equ 2
F_TAN       equ 3
F_EXP       equ 4
F_LN        equ 5
F_ABS       equ 6
F_ASIN      equ 7
F_ACOS      equ 8
F_ATAN      equ 9

C_PI        equ 0                       ; constants
C_E         equ 1

TX          equ 5                       ; the console
TY          equ WIN_TITLE_H + 3
STAT_Y      equ SCR_H - CELL_H - 2
IN_Y        equ STAT_Y - CELL_H - 3
VROWS       equ (IN_Y - TY - 2) / CELL_H

RBUF equ 3000

%macro NP 2                             ; reg = node at index
    mov %1, %2
    shl %1, 4
    add %1, [pool]
%endmacro

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    mov eax, SYS_SBRK
    mov ebx, POOL_N * 16 + LIST_N * 4 * 3
    int 0x80
    cmp eax, -1
    je .nogfx
    mov [pool], eax
    add eax, POOL_N * 16
    mov [list], eax
    add eax, LIST_N * 4
    mov [fb], eax
    add eax, LIST_N * 4
    mov [fe], eax
    call gui_open
    jc .nogfx
    mov esi, [arg]
    test esi, esi
    jz .hello
    cmp dword [esi], 'test'
    jne .hello
    cmp byte [esi+4], 0
    je selftest
.hello:
    mov esi, m_hello
    call add_line
    mov esi, m_hello2
    call add_line
    mov esi, m_hello3
    call add_line
.draw:
    call draw
.key:
    call gui_getkey
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- console ----------
; eax = key -> CF to quit
key:
    pushad
    movzx ebx, ah
    mov ecx, [ilen]
    cmp bl, K_ESC
    je .quit
    cmp bl, K_ENTER
    je .run
    cmp bl, K_BKSP
    je .bs
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    test eax, 1 << 16
    jnz .ok
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    cmp ecx, IMAX
    jae .ok
    mov [ibuf+ecx], al
    inc ecx
    mov byte [ibuf+ecx], 0
    mov [ilen], ecx
    jmp .ok
.bs:
    test ecx, ecx
    jz .ok
    dec ecx
    mov byte [ibuf+ecx], 0
    mov [ilen], ecx
    jmp .ok
.quit:
    popad
    stc
    ret
.up:                            ; an earlier input
    mov eax, [hpick]
    inc eax
    cmp eax, [nin]
    jae .ok
    mov [hpick], eax
    jmp .recall
.down:
    mov eax, [hpick]
    test eax, eax
    jle .clear
    dec eax
    mov [hpick], eax
.recall:
    mov ecx, [nin]              ; the newest is at nin - 1
    sub ecx, eax
    dec ecx
    imul esi, ecx, IMAX + 4
    add esi, inhist
    mov edi, ibuf
    call scopy
    sub edi, ibuf
    mov [ilen], edi
    jmp .ok
.clear:
    mov dword [hpick], -1
    mov byte [ibuf], 0
    mov dword [ilen], 0
    jmp .ok
.pgup:
    add dword [scroll], VROWS - 1
    mov eax, [nlines]
    sub eax, VROWS
    jns .pu
    xor eax, eax
.pu:
    cmp [scroll], eax
    jbe .ok
    mov [scroll], eax
    jmp .ok
.pgdn:
    sub dword [scroll], VROWS - 1
    jns .ok
    mov dword [scroll], 0
    jmp .ok
.run:
    test ecx, ecx
    jz .ok
    call remember
    mov edi, line               ; "> input"
    mov ax, '> '
    stosw
    mov esi, ibuf
    call scopy
    mov esi, line
    call add_line
    mov esi, ibuf
    call run_command
    mov esi, outbuf
    call add_line
    mov byte [ibuf], 0
    mov dword [ilen], 0
    mov dword [scroll], 0
    mov dword [hpick], -1
.ok:
    popad
    clc
    ret

; ibuf -> the input history (the oldest dropped when full)
remember:
    pushad
    mov eax, [nin]
    cmp eax, NHIST_IN
    jb .room
    mov edi, inhist
    lea esi, [edi+IMAX+4]
    mov ecx, (NHIST_IN - 1) * (IMAX + 4)
    rep movsb
    dec dword [nin]
.room:
    mov eax, [nin]
    imul edi, eax, IMAX + 4
    add edi, inhist
    mov esi, ibuf
    call scopy
    inc dword [nin]
    popad
    ret

; esi = text -> console lines, wrapped at COLS
add_line:
    pushad
.l:
    cmp dword [nlines], HIST
    jb .room
    mov edi, hist               ; the oldest line goes
    push esi
    lea esi, [edi+COLS+2]
    mov ecx, (HIST - 1) * (COLS + 2)
    rep movsb
    pop esi
    dec dword [nlines]
.room:
    mov eax, [nlines]
    imul edi, eax, COLS + 2
    add edi, hist
    mov ecx, COLS
.c:
    lodsb
    test al, al
    jz .end
    stosb
    loop .c
    mov byte [edi], 0
    inc dword [nlines]
    cmp byte [esi], 0
    jne .l
    jmp .r
.end:
    mov byte [edi], 0
    inc dword [nlines]
.r:
    popad
    ret

draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    mov eax, 3
    mov ebx, TY - 1
    mov ecx, SCR_W - 6
    mov edx, IN_Y - TY - 1
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_bg], C_WHITE
    mov eax, [nlines]           ; the last lines (less what is scrolled)
    sub eax, VROWS
    sub eax, [scroll]
    jns .f
    xor eax, eax
.f:
    xor ebp, ebp
.row:
    cmp ebp, VROWS
    jae .input
    cmp eax, [nlines]
    jae .input
    imul esi, eax, COLS + 2
    add esi, hist
    mov byte [gui_ink], C_BLACK
    cmp word [esi], '> '
    jne .o
    mov byte [gui_ink], C_BLUE
.o:
    push eax
    imul ebx, ebp, CELL_H
    add ebx, TY
    mov eax, TX
    call gui_text
    pop eax
    inc eax
    inc ebp
    jmp .row
.input:
    mov eax, 3
    mov ebx, IN_Y - 1
    mov ecx, SCR_W - 6
    mov edx, CELL_H + 2
    mov byte [gui_ink], C_YELLOW
    call gui_fill
    mov byte [gui_bg], C_YELLOW
    mov byte [gui_ink], C_BLACK
    mov edi, line
    mov ax, '> '
    stosw
    mov esi, ibuf               ; its end, if long
    mov eax, [ilen]
    sub eax, COLS - 3
    jbe .i
    add esi, eax
.i:
    call scopy
    mov ax, '_'
    stosw
    mov esi, line
    mov eax, TX
    mov ebx, IN_Y
    call gui_text
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov esi, s_keys
    call gui_textn
    call gui_flip
    popad
    ret

; ---------- commands ----------
; esi = input -> outbuf: the answer, or an error
run_command:
    pushad
    mov [err_sp], esp
    fninit
    mov dword [nfree], 0
    mov dword [ltop], 0
    mov dword [ftop], 0
    mov byte [asc], 0
    mov byte [set_ans], 0
    mov dword [outp], outbuf
    mov byte [outbuf], 0
    call make_consts
    call do_command
    mov eax, [outp]
    mov byte [eax], 0
    cmp byte [set_ans], 0
    je .r
    mov esi, ansout             ; the answer becomes "ans"
    mov edi, ans_buf
    call scopy
.r:
    popad
    ret
; any routine: esi = message -> the command stops with it
cas_error:
    mov esp, [err_sp]
    fninit
    mov edi, outbuf
    push esi
    mov esi, s_error
    call scopy
    pop esi
    call scopy
    mov byte [edi], 0
    popad
    ret

make_consts:
    xor eax, eax
    call mk_int
    mov [n_zero], eax
    mov eax, 1
    call mk_int
    mov [n_one], eax
    mov eax, -1
    call mk_int
    mov [n_mone], eax
    mov eax, 1
    mov edx, 2
    call mk_rat
    mov [n_half], eax
    mov bl, N_VAR
    mov cl, 'x'
    call mk_leaf
    mov [n_x], eax
    mov bl, N_UNDEF
    xor ecx, ecx
    call mk_leaf
    mov [n_undef], eax
    ret

; esi = the input line
do_command:
    call skip_sp
    mov [cmd_start], esi
    call name_len               ; a command word and "("?
    test ecx, ecx
    jz .expr
    cmp byte [esi+ecx], '('
    jne .expr
    mov edi, cmd_words
    xor ebx, ebx
.w:
    cmp byte [edi], 0
    je .expr
    push esi
    push edi
    push ecx
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    jne .nw
    cmp byte [edi+ecx], 0
    je .found
.nw:
    inc edi
    cmp byte [edi-1], 0
    jne .nw
    inc ebx
    jmp .w
.found:
    add esi, ecx                ; at "("
    push ebx
    call split_args
    pop ebx
    jmp [cmd_tab+ebx*4]
.expr:                          ; an expression alone: simplified
    mov esi, [cmd_start]
    mov [args], esi
    mov dword [nargs], 1
    jmp cmd_simplify

; esi at "(": the arguments (split at commas outside brackets, up to
; the matching ")") -> argbuf 0..2, args, nargs
split_args:
    inc esi
    xor ebx, ebx                ; argument
    xor edx, edx                ; depth
    mov edi, argbuf
    mov [args], edi
.c:
    lodsb
    test al, al
    jz .bad
    cmp al, '('
    jne .c1
    inc edx
.c1:
    cmp al, ')'
    jne .c2
    dec edx
    js .end
.c2:
    test edx, edx
    jnz .put
    cmp al, ','
    jne .put
    mov byte [edi], 0
    inc ebx
    cmp ebx, 3
    jae .bad
    imul edi, ebx, IMAX + 4
    add edi, argbuf
    mov [args+ebx*4], edi
    jmp .c
.put:
    stosb
    jmp .c
.end:
    mov byte [edi], 0
    inc ebx
    mov [nargs], ebx
    call skip_sp
    cmp byte [esi], 0
    jne .bad
    ret
.bad:
    mov esi, e_syntax
    jmp cas_error

; argument ebx -> eax = it parsed (not simplified)
parse_arg:
    mov esi, [args+ebx*4]
    jmp parse_all

; argument ebx (or eax = default if there is none) -> eax = an integer
; from 0 to 30
int_arg:
    cmp ebx, [nargs]
    jae .def
    push eax
    call parse_arg
    call simp
    pop edx
    NP edi, eax
    cmp byte [edi], N_NUM
    jne .bad
    cmp dword [edi+8], 1
    jne .bad
    mov eax, [edi+4]
    cmp eax, 30
    ja .bad
    ret
.def:
    ret
.bad:
    mov esi, e_count
    jmp cas_error

; nargs must be between al and ah
nargs_in:
    movzx ecx, al
    cmp [nargs], ecx
    jb .bad
    movzx ecx, ah
    cmp [nargs], ecx
    ja .bad
    ret
.bad:
    mov esi, e_args
    jmp cas_error

; eax = node -> outbuf (and it becomes ans), with "~ value" if it is a
; constant that is not rational
answer:
    push eax
    call print_top
    mov edi, [outp]
    mov byte [edi], 0
    mov esi, outbuf
    mov edi, ansout
    call scopy
    mov byte [set_ans], 1
    pop eax
    jmp approx

; eax = node: "  ~ value" after the output if it is a constant that is
; not a plain number
approx:
    call has_x
    jnz .r
    NP edi, eax
    cmp byte [edi], N_NUM
    je .r
    cmp byte [edi], N_FLT
    je .r
    call has_var
    jnz .r
    mov byte [nan], 0
    call numval
    cmp byte [nan], 0
    jne .pop
    fstp qword [numv]
    mov esi, s_approx
    call emit_str
    call emit_full
.r:
    ret
.pop:
    fstp st0
    ret

cmd_simplify:
    mov ax, 0x0101
    call nargs_in
    xor ebx, ebx
    call parse_arg
    call simp
    jmp answer

cmd_expand:
    mov ax, 0x0101
    call nargs_in
    xor ebx, ebx
    call parse_arg
    call expand
    jmp answer

cmd_diff:
    mov ax, 0x0201
    call nargs_in
    mov ebx, 1
    mov eax, 1
    call int_arg
    mov ebp, eax
    xor ebx, ebx
    call parse_arg
    call simp
.n:
    test ebp, ebp
    jz .done
    call diff
    call simp
    dec ebp
    jmp .n
.done:
    jmp answer

cmd_integrate:
    mov ax, 0x0301
    call nargs_in
    cmp dword [nargs], 2
    je .bad
    xor ebx, ebx
    call parse_arg
    call simp
    mov [fnode], eax
    call antideriv
    jc .nf
    cmp dword [nargs], 3
    je .definite
    call answer
    mov esi, s_plusc
    jmp emit_str
.nf:
    cmp dword [nargs], 3
    je .numeric
    mov esi, m_noint
    jmp emit_str
.definite:                      ; F(b) - F(a), or Simpson
    mov [gnode], eax
    mov ebx, 2
    call parse_arg
    call simp
    mov edx, eax
    mov eax, [gnode]
    call subst
    call simp
    push eax
    mov ebx, 1
    call parse_arg
    call simp
    mov edx, eax
    mov eax, [gnode]
    call subst
    call simp
    call neg
    pop edx
    call add2
    call has_undef
    jnz .numeric
    jmp answer
.numeric:
    mov ebx, 1
    call num_arg
    fstp qword [lo]
    mov ebx, 2
    call num_arg
    fstp qword [hi]
    mov eax, [fnode]
    call simpson
    cmp byte [nan], 0
    jne .nonum
    call mk_flt
    mov esi, s_tilde
    call emit_str
    call print_top
    ret
.nonum:
    mov esi, e_numint
    jmp cas_error
.bad:
    mov esi, e_args
    jmp cas_error

; argument ebx -> st0 = its value (a constant)
num_arg:
    call parse_arg
    call simp
    mov byte [nan], 0
    call numval
    cmp byte [nan], 0
    jne .bad
    ret
.bad:
    fstp st0
    mov esi, e_const
    jmp cas_error

cmd_factor:
    mov ax, 0x0101
    call nargs_in
    xor ebx, ebx
    call parse_arg
    call expand
    mov [fnode], eax
    mov edi, polyA
    call poly_of
    jc .notpoly
    cmp dword [polyA], 1
    jl .same
    call factor_poly
    jmp answer
.same:
    mov eax, [fnode]
    jmp answer
.notpoly:
    mov esi, e_notpoly
    jmp cas_error

cmd_solve:
    mov ax, 0x0101
    call nargs_in
    mov esi, [args]             ; "a = b": a - b
    xor edx, edx
.f:
    mov al, [esi]
    test al, al
    jz .noeq
    cmp al, '('
    jne .f1
    inc edx
.f1:
    cmp al, ')'
    jne .f2
    dec edx
.f2:
    cmp al, '='
    jne .f3
    test edx, edx
    jz .eq
.f3:
    inc esi
    jmp .f
.eq:
    mov byte [esi], 0
    inc esi
    push esi
    mov esi, [args]
    call parse_all
    pop esi
    push eax
    call parse_all
    call neg
    pop edx
    call add2
    jmp .have
.noeq:
    xor ebx, ebx
    call parse_arg
.have:
    call expand
    mov [fnode], eax
    call has_x
    jnz .x
    cmp eax, [n_zero]
    mov esi, m_always
    NP edi, eax
    cmp byte [edi], N_NUM
    jne .nox
    cmp dword [edi+4], 0
    je .say
.nox:
    mov esi, m_never
.say:
    jmp emit_str
.x:
    mov eax, [fnode]
    mov edi, polyA
    call poly_of
    jc .numeric
    jmp solve_poly
.numeric:
    jmp solve_numeric

cmd_limit:
    mov ax, 0x0202
    call nargs_in
    xor ebx, ebx
    call parse_arg
    call simp
    mov [fnode], eax
    mov esi, [args+4]           ; inf, +inf, -inf?
    call skip_sp
    xor ecx, ecx
    cmp byte [esi], '+'
    jne .s1
    inc esi
.s1:
    cmp byte [esi], '-'
    jne .s2
    inc esi
    inc ecx
.s2:
    cmp dword [esi], 'inf'
    je .inf
    mov ebx, 1
    call parse_arg
    call simp
    call has_x
    jnz .bad
    mov [anode], eax
    jmp limit_at
.inf:
    mov [sign], ecx
    jmp limit_inf
.bad:
    mov esi, e_const
    jmp cas_error

cmd_series:
    mov ax, 0x0301
    call nargs_in
    mov eax, [n_zero]
    cmp dword [nargs], 2
    jb .a
    mov ebx, 1
    call parse_arg
    call simp
    call has_x
    jnz .bad
.a:
    mov [anode], eax
    mov ebx, 2
    mov eax, 5
    call int_arg
    cmp eax, 12
    ja .big
    mov ebp, eax
    xor ebx, ebx
    call parse_arg
    call simp
    mov [fnode], eax
    mov eax, [n_mone]           ; x - a (or x)
    mov edx, [anode]
    call mul2
    mov edx, [n_x]
    call add2
    mov [gnode], eax
    mov eax, [n_one]
    mov [fact], eax             ; 1/k!
    mov eax, [n_zero]
    mov [sum], eax
    xor ebx, ebx                ; k
.k:
    mov eax, [fnode]
    mov edx, [anode]
    call subst
    call simp
    call has_undef
    jnz .undef
    mov edx, [fact]
    call mul2
    push eax
    mov eax, ebx
    call mk_int
    mov edx, eax
    mov eax, [gnode]
    call pow2
    pop edx
    call mul2
    mov edx, [sum]
    mov byte [asc], 1
    call add2
    mov [sum], eax
    cmp ebx, ebp
    jae .done
    inc ebx
    mov eax, ebx                ; 1/k! for the next
    call mk_int
    mov edx, -1
    push eax
    mov eax, edx
    call mk_int
    mov edx, eax
    pop eax
    call pow2
    mov edx, [fact]
    call mul2
    mov [fact], eax
    mov eax, [fnode]
    call diff
    call simp
    mov [fnode], eax
    jmp .k
.done:
    mov eax, [sum]
    jmp answer
.undef:
    mov esi, e_undefat
    jmp cas_error
.bad:
    mov esi, e_const
    jmp cas_error
.big:
    mov esi, e_count
    jmp cas_error

; ---------- solving ----------
; polyA -> outbuf: exact rational roots, then the quadratic formula,
; then numeric roots of what is left
solve_poly:
    mov dword [nroots], 0
    mov dword [nsol], 0
    call rational_roots         ; roots, polyA what is left
    xor ebx, ebx                ; the rational ones, in order
.r:
    cmp ebx, [nroots]
    jae .rest
    mov eax, [root_n+ebx*4]
    mov edx, [root_d+ebx*4]
    call mk_rat
    call say_root
    inc ebx
    jmp .r
.rest:
    mov eax, [polyA]
    cmp eax, 1
    jl .end
    je .lin
    cmp eax, 2
    je .quad
    call poly_numeric
    jmp .end
.lin:                           ; -c0/c1
    lea esi, [polyA+8]
    call coef_node
    push eax
    lea esi, [polyA+16]
    call coef_node
    mov edx, [n_mone]
    call pow2
    pop edx
    call mul2
    call neg
    call say_root
    jmp .end
.quad:
    call quadratic
.end:
    cmp dword [nsol], 0
    jne .r2
    mov esi, m_noreal
    call emit_str
.r2:
    ret

; eax = a root: ", x = root" (the first without the comma)
say_root:
    push eax
    cmp dword [nsol], 0
    je .f
    mov esi, s_comma
    call emit_str
.f:
    mov esi, s_xeq
    call emit_str
    pop eax
    inc dword [nsol]
    jmp print_node

; st0 (popped) as a numeric root
say_numroot:
    fstp qword [numv]
    cmp dword [nsol], 0
    je .f
    mov esi, s_comma
    call emit_str
.f:
    mov esi, s_xapprox
    call emit_str
    inc dword [nsol]
    jmp emit_full

; polyA of degree 2: (-b +- sqrt(D)) / 2a, complex with i if D < 0
quadratic:
    lea esi, [polyA+8+16]       ; a
    call coef_node
    mov [qa_], eax
    lea esi, [polyA+8+8]
    call coef_node
    mov [qb_], eax
    lea esi, [polyA+8]
    call coef_node
    mov [qc_], eax
    mov eax, [qb_]              ; D = b^2 - 4ac
    mov edx, eax
    call mul2
    push eax
    mov eax, -4
    call mk_int
    mov edx, [qa_]
    call mul2
    mov edx, [qc_]
    call mul2
    pop edx
    call add2
    mov [qd_], eax
    mov eax, [qa_]              ; 1/(2a)
    mov edx, 2
    push eax
    mov eax, edx
    call mk_int
    pop edx
    call mul2
    mov edx, [n_mone]
    call pow2
    mov [q2a], eax
    mov edx, [qb_]              ; -b/(2a)
    call mul2
    call neg
    mov [qm], eax
    NP edi, [qd_]
    cmp dword [edi+4], 0
    jl .complex
    mov eax, [qd_]              ; sqrt(D)/(2a)
    mov edx, [n_half]
    call pow2
    mov edx, [q2a]
    call mul2
    mov [qs], eax
    NP edi, [qd_]               ; D = 0: one root
    cmp dword [edi+4], 0
    je .one
    call order_pm
    mov eax, [qm]
    mov edx, [qs]
    call neg_if_first
    call add2
    call say_root
    mov eax, [qm]
    mov edx, [qs]
    call neg_if_second
    call add2
    jmp say_root
.one:
    mov eax, [qm]
    jmp say_root
.complex:                       ; -b/2a -+ sqrt(-D)/2a * i
    mov eax, [qd_]
    call neg
    mov edx, [n_half]
    call pow2
    mov edx, [q2a]
    call mul2
    call abs_node
    push eax
    mov bl, N_VAR
    mov cl, 'i'
    call mk_leaf
    pop edx
    call mul2
    mov [qs], eax
    mov eax, [qs]
    call neg
    mov edx, [qm]
    call add2
    call say_root
    mov eax, [qs]
    mov edx, [qm]
    call add2
    jmp say_root

; qs: the smaller root first (qs is +-sqrt(D)/2a: its sign is 2a's)
order_pm:
    mov byte [pm_swap], 0
    NP edi, [qa_]
    cmp dword [edi+4], 0
    jg .r
    mov byte [pm_swap], 1
.r:
    ret
neg_if_first:                   ; eax, edx -> eax + (-edx), first root
    push eax
    mov eax, edx
    cmp byte [pm_swap], 0
    jne .k
    call neg
.k:
    pop edx
    ret
neg_if_second:
    push eax
    mov eax, edx
    cmp byte [pm_swap], 0
    je .k
    call neg
.k:
    pop edx
    ret

; eax = numeric node -> its absolute value
abs_node:
    push edi
    NP edi, eax
    cmp byte [edi], N_NUM
    jne .t
    cmp dword [edi+4], 0
    jge .r
    pop edi
    jmp neg
.t:
    push eax
    mov byte [nan], 0
    call numval
    ftst
    fnstsw ax
    fstp st0
    sahf
    pop eax
    jae .r
    pop edi
    jmp neg
.r:
    pop edi
    ret

; polyA (degree >= 3) -> its real roots numerically
poly_numeric:
    mov eax, [fnode]            ; (the whole of it: roots already said
    mov [pnode], eax            ;  are found again only as exact ones)
    call poly_tree
    mov [pnode], eax
    call cauchy                 ; st0 = a bound for the roots
    fld st0
    fchs
    fstp qword [lo]
    fstp qword [hi]
    mov eax, [pnode]
    jmp scan_roots

; polyA -> st0 = 1 + max |ci / cn|
cauchy:
    mov ecx, [polyA]
    lea esi, [polyA+8+ecx*8]
    fild dword [esi]
    fidiv dword [esi+4]
    fld1
    xor ebx, ebx
.c:
    cmp ebx, ecx
    jae .d
    fild dword [polyA+8+ebx*8]
    fidiv dword [polyA+12+ebx*8]
    fdiv st0, st2
    fabs
    fcomi st0, st1
    jbe .s
    fxch
.s:
    fstp st0
    inc ebx
    jmp .c
.d:
    fld1
    faddp st1, st0
    fstp st1
    ret

; eax = f(x): its real roots in lo..hi, numerically (sign changes on
; 4000 steps, then bisection)
scan_roots:
    mov [snode], eax
    fld qword [hi]
    fsub qword [lo]
    fidiv dword [i_steps]
    fstp qword [step]
    fld qword [lo]
    fst qword [xa]
    call f_at
    fstp qword [fa]
    xor ebp, ebp
.s:
    inc ebp
    cmp ebp, [i_steps]
    ja .done
    mov [tmpi], ebp
    fild dword [tmpi]
    fmul qword [step]
    fadd qword [lo]
    fst qword [xb]
    call f_at
    fstp qword [fb_]
    cmp byte [nan], 0
    jne .next
    fld qword [fb_]             ; exactly 0 at xb?
    ftst
    fnstsw ax
    fstp st0
    sahf
    je .exact
    fld qword [fa]
    fmul qword [fb_]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jae .next
    call bisect
    jmp .next
.exact:
    fld qword [xb]
    call root_found
.next:
    fld qword [xb]
    fstp qword [xa]
    fld qword [fb_]
    fstp qword [fa]
    cmp dword [nsol], 8
    jb .s
.done:
    ret

; st0 (popped) = a root, unless it is the last one again
root_found:
    cmp dword [nsol], 0
    je .say
    fld st0
    fsub qword [lastroot]
    fabs
    fcomp qword [f_same]
    fnstsw ax
    sahf
    jb .drop
.say:
    fst qword [lastroot]
    jmp say_numroot
.drop:
    fstp st0
    ret

; xa..xb holds a sign change of snode -> its root, if f gets small
bisect:
    mov ecx, 80
.b:
    fld qword [xa]
    fadd qword [xb]
    fmul qword [f_half]
    fst qword [xm]
    call f_at
    fstp qword [fm]
    fld qword [fa]
    fmul qword [fm]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jae .right
    fld qword [xm]
    fstp qword [xb]
    jmp .n
.right:
    fld qword [xm]
    fstp qword [xa]
    fld qword [fm]
    fstp qword [fa]
.n:
    loop .b
    fld qword [fm]              ; a pole changes sign too: only if small
    fabs
    fcomp qword [f_small]
    fnstsw ax
    sahf
    ja .no
    fld qword [xm]
    jmp root_found
.no:
    ret

; st0 = x (popped) -> st0 = snode at x (nan set if undefined)
f_at:
    fstp qword [xval]
    mov byte [nan], 0
    mov eax, [snode]
    jmp numval

solve_numeric:
    mov dword [nsol], 0
    fld qword [f_m100]
    fstp qword [lo]
    fld qword [f_100]
    fstp qword [hi]
    mov eax, [fnode]
    call scan_roots
    cmp dword [nsol], 0
    jne .r
    mov esi, m_nonefound
    call emit_str
.r:
    ret

; ---------- limits ----------
limit_at:
    mov ecx, 8                  ; l'Hopital at most this often
.try:
    push ecx
    mov eax, [fnode]
    mov edx, [anode]
    call subst
    call simp
    pop ecx
    call has_undef
    jz .value
    push ecx
    mov eax, [fnode]            ; num / den?
    call split_frac
    pop ecx
    jc .numeric
    push ecx
    mov eax, [lnum]
    mov edx, [anode]
    call subst
    call simp
    mov [vnum], eax
    mov eax, [lden]
    mov edx, [anode]
    call subst
    call simp
    mov [vden], eax
    pop ecx
    mov eax, [vden]
    call is_zero
    jnz .numeric
    mov eax, [vnum]
    call is_zero
    jnz .infinite
    dec ecx
    jz .numeric
    push ecx
    mov eax, [lnum]             ; 0/0: f'/g'
    call diff
    call simp
    push eax
    mov eax, [lden]
    call diff
    call simp
    mov edx, [n_mone]
    call pow2
    pop edx
    call mul2
    mov [fnode], eax
    pop ecx
    jmp .try
.value:
    jmp answer
.infinite:                      ; c/0: by the values either side
.numeric:
    call side_values
    jmp limit_numeric

; fnode near anode: st values at a - h and a + h for smaller h ->
; lval, rval (h = 1e-7), nan set if undefined
side_values:
    mov eax, [anode]
    mov byte [nan], 0
    call numval
    fstp qword [aval]
    fld qword [aval]
    fsub qword [f_h]
    call fn_at
    fstp qword [lval]
    fld qword [aval]
    fadd qword [f_h]
    call fn_at
    fstp qword [rval]
    fld qword [aval]
    fsub qword [f_h2]
    call fn_at
    fstp qword [lval2]
    fld qword [aval]
    fadd qword [f_h2]
    call fn_at
    fstp qword [rval2]
    ret

; st0 = x (popped) -> fnode at x
fn_at:
    fstp qword [xval]
    mov eax, [fnode]
    jmp numval

; lval, rval (h) and lval2, rval2 (10 h): a limit, infinity, or none
limit_numeric:
    cmp byte [nan], 0
    jne .none
    fld qword [lval]            ; both large, the same sign: infinite
    fabs
    fcomp qword [f_large]
    fnstsw ax
    sahf
    jb .finite
    fld qword [rval]
    fabs
    fcomp qword [f_large]
    fnstsw ax
    sahf
    jb .none
    fld qword [lval]
    fmul qword [rval]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jb .none
    fld qword [rval]
    ftst
    fnstsw ax
    fstp st0
    sahf
    mov esi, s_inf
    ja .say
    mov esi, s_minf
.say:
    jmp emit_str
.finite:                        ; the two sides agree, and nearer agrees more
    fld qword [lval]
    fsub qword [rval]
    fabs
    fld qword [rval]
    fabs
    fld1
    faddp st1, st0
    fmul qword [f_agree]
    fcomip st0, st1
    fstp st0
    jb .none
    fld qword [lval]
    fadd qword [rval]
    fmul qword [f_half]
    call nice_num
    jmp answer
.none:
    mov esi, m_nolimit
    jmp emit_str

; x -> inf (sign 0) or -inf (1): rational functions by their degrees,
; others numerically
limit_inf:
    mov eax, [fnode]
    call split_frac
    jc .numeric
    mov eax, [lnum]
    call expand
    mov edi, polyA
    call poly_of
    jc .numeric
    mov eax, [lden]
    call expand
    mov edi, polyB
    call poly_of
    jc .numeric
    mov eax, [polyA]
    mov ecx, [polyB]
    cmp eax, ecx
    jl .zero
    mov eax, [polyA]            ; the leading coefficients' ratio
    lea esi, [polyA+8+eax*8]
    call coef_node
    push eax
    mov eax, [polyB]
    lea esi, [polyB+8+eax*8]
    call coef_node
    mov edx, [n_mone]
    call pow2
    pop edx
    call mul2
    mov ecx, [polyA]
    cmp ecx, [polyB]
    je answer
    NP edi, eax                 ; infinite: the sign
    mov eax, [edi+4]
    mov ecx, [polyA]
    sub ecx, [polyB]
    and ecx, [sign]             ; odd power at -inf turns it
    jz .s
    neg eax
.s:
    mov esi, s_inf
    test eax, eax
    jg .say
    mov esi, s_minf
.say:
    jmp emit_str
.zero:
    mov eax, [n_zero]
    jmp answer
.numeric:                       ; f at 1e6 and 1e7 (times the sign)
    fld qword [f_1e6]
    cmp dword [sign], 0
    je .p
    fchs
.p:
    fst qword [lval]
    call fn_at
    fstp qword [lval2]
    fld qword [lval]
    fmul qword [f_10]
    call fn_at
    fstp qword [rval]
    cmp byte [nan], 0
    jne .none
    fld qword [rval]
    fabs
    fcomp qword [f_large]
    fnstsw ax
    sahf
    jae .big
    fld qword [lval2]
    fsub qword [rval]
    fabs
    fld qword [rval]
    fabs
    fld1
    faddp st1, st0
    fmul qword [f_agree]
    fcomip st0, st1
    fstp st0
    jb .none
    fld qword [rval]
    call nice_num
    jmp answer
.big:
    fld qword [rval]
    ftst
    fnstsw ax
    fstp st0
    sahf
    mov esi, s_inf
    ja .say
    mov esi, s_minf
    jmp .say
.none:
    mov esi, m_nolimit
    jmp emit_str

; st0 (popped) -> eax = a rational node if it is p/q (q <= 1000) to
; within 1e-9, otherwise a float node
nice_num:
    fstp qword [numv]
    mov ecx, 1
.q:
    mov [tmpi], ecx
    fld qword [numv]
    fimul dword [tmpi]
    frndint
    fld st0
    fidiv dword [tmpi]
    fsub qword [numv]
    fabs
    fld qword [numv]
    fabs
    fld1
    faddp st1, st0
    fmul qword [f_recon]
    fcomip st0, st1
    fstp st0
    jae .got
    fstp st0
    inc ecx
    cmp ecx, 1000
    jbe .q
    fld qword [numv]
    jmp mk_flt
.got:
    fld st0
    fabs
    fcomp qword [f_2p31]
    fnstsw ax
    sahf
    jae .flt
    fistp dword [tmpi]
    mov eax, [tmpi]
    mov edx, ecx
    jmp mk_rat
.flt:
    fstp st0
    fld qword [numv]
    jmp mk_flt

; eax = a simplified node -> lnum, lden: the factors with positive and
; negative powers; CF if there is no denominator
split_frac:
    pushad
    mov ebp, [ltop]
    call push_factors
    mov eax, [n_one]
    mov [lnum], eax
    mov [lden], eax
    mov byte [hasden], 0
    mov ebx, ebp
.f:
    cmp ebx, [ltop]
    jae .d
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    NP edi, eax
    cmp byte [edi], N_POW
    jne .num
    mov esi, [edi+8]
    NP esi, esi
    cmp byte [esi], N_NUM
    jne .num
    cmp dword [esi+4], 0
    jge .num
    push eax                    ; base ^ -e into the denominator
    mov eax, [edi+8]
    call neg
    mov edx, eax
    mov eax, [edi+4]
    call pow2
    mov edx, [lden]
    call mul2
    mov [lden], eax
    pop eax
    mov byte [hasden], 1
    jmp .n
.num:
    mov edx, [lnum]
    call mul2
    mov [lnum], eax
.n:
    inc ebx
    jmp .f
.d:
    mov [ltop], ebp
    cmp byte [hasden], 0
    je .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ---------- antiderivatives ----------
; eax = simplified f -> eax = F, or CF (expanded once if need be)
antideriv:
    mov [ifn], eax
    call integ
    jnc .r
    mov eax, [ifn]
    call expand
    call integ
.r:
    ret

; eax -> eax = an antiderivative (simplified), or CF
integ:
    pushad
    mov ebp, [ltop]
    call push_terms
    mov eax, [n_zero]
    mov [isum], eax
    mov ebx, ebp
.t:
    cmp ebx, [ltop]
    jae .done
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    push ebx
    call integ_term
    pop ebx
    jc .fail
    mov edx, [isum]
    call add2
    mov [isum], eax
    inc ebx
    jmp .t
.done:
    mov [ltop], ebp
    mov eax, [isum]
    mov [esp+28], eax
    popad
    clc
    ret
.fail:
    mov [ltop], ebp
    popad
    stc
    ret

; eax = a term -> eax = its antiderivative, or CF
integ_term:
    pushad
    mov ebp, [ltop]             ; constant factors and the rest
    call push_factors
    mov eax, [n_one]
    mov [ic], eax
    mov dword [irest], 0
    mov ebx, ebp
.f:
    cmp ebx, [ltop]
    jae .split
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    call has_x
    jnz .x
    mov edx, [ic]
    call mul2
    mov [ic], eax
    jmp .n
.x:
    cmp dword [irest], 0
    jne .two
    mov [irest], eax
    jmp .n
.two:                           ; two factors with x: x*sin(x) etc. no
    mov [ltop], ebp
    jmp .fail
.n:
    inc ebx
    jmp .f
.split:
    mov [ltop], ebp
    mov eax, [irest]
    test eax, eax
    jnz .rest
    mov eax, [n_x]              ; c -> c x
    jmp .times_c
.rest:
    NP edi, eax
    movzx ecx, byte [edi]
    cmp ecx, N_VAR
    je .var
    cmp ecx, N_POW
    je .pow
    cmp ecx, N_FN
    je .fn
    jmp .fail
.var:                           ; x -> x^2/2
    mov eax, 2
    call mk_int
    mov edx, eax
    mov eax, [n_x]
    call pow2
    mov edx, [n_half]
    call mul2
    jmp .times_c
.pow:
    mov eax, [edi+8]
    call has_x
    jnz .expo
    mov eax, [edi+4]            ; u^n, u linear
    call linear
    jc .fail
    mov [ia], eax
    mov eax, [edi+8]
    call is_mone
    jnz .log
    mov eax, [edi+8]            ; u^(n+1) / ((n+1) a)
    mov edx, [n_one]
    call add2
    mov [in1], eax
    mov edx, eax
    mov eax, [edi+4]
    call pow2
    push eax
    mov eax, [in1]
    mov edx, [ia]
    call mul2
    mov edx, [n_mone]
    call pow2
    pop edx
    call mul2
    jmp .times_c
.log:                           ; ln(abs(u)) / a
    mov eax, [edi+4]
    mov bl, F_ABS
    call mk_fn
    mov bl, F_LN
    call mk_fn
.over_a:
    push eax
    mov eax, [ia]
    mov edx, [n_mone]
    call pow2
    pop edx
    call mul2
    jmp .times_c
.expo:                          ; c^u, u linear, c constant: c^u/(a ln c)
    mov eax, [edi+4]
    call has_x
    jnz .fail
    mov eax, [edi+8]
    call linear
    jc .fail
    mov [ia], eax
    mov eax, [edi+4]
    mov bl, F_LN
    call mk_fn
    call simp
    mov edx, [ia]
    call mul2
    mov edx, [n_mone]
    call pow2
    mov edx, eax
    NP edi, [irest]
    mov eax, [irest]
    call mul2
    jmp .times_c
.fn:
    mov eax, [edi+4]
    call linear
    jc .fail
    mov [ia], eax
    movzx ecx, byte [edi+1]
    mov eax, [edi+4]
    cmp ecx, F_SIN
    je .sin
    cmp ecx, F_COS
    je .cos
    cmp ecx, F_EXP
    je .exp
    cmp ecx, F_TAN
    je .tan
    cmp ecx, F_LN
    je .ln
    jmp .fail
.sin:                           ; -cos(u)/a
    mov bl, F_COS
    call mk_fn
    call neg
    jmp .over_a
.cos:
    mov bl, F_SIN
    call mk_fn
    jmp .over_a
.exp:
    mov bl, F_EXP
    call mk_fn
    jmp .over_a
.tan:                           ; -ln(abs(cos(u)))/a
    mov bl, F_COS
    call mk_fn
    mov bl, F_ABS
    call mk_fn
    mov bl, F_LN
    call mk_fn
    call neg
    jmp .over_a
.ln:                            ; (u ln(u) - u)/a
    push eax
    mov bl, F_LN
    call mk_fn
    pop edx
    push edx
    call mul2
    pop edx
    push eax
    mov eax, edx
    call neg
    pop edx
    call add2
    jmp .over_a
.times_c:
    mov edx, [ic]
    call mul2
    call simp
    mov [esp+28], eax
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; eax = u -> eax = a, if u = a x + b with a, b free of x (a not 0); CF
; otherwise
linear:
    push edx
    push eax
    call diff
    call simp
    call has_x
    jnz .no
    call is_zero
    jnz .no
    add esp, 4
    pop edx
    clc
    ret
.no:
    pop eax
    pop edx
    stc
    ret

; eax = f, lo..hi -> st0 = Simpson's rule (1000 steps); nan if undefined
simpson:
    mov [snode], eax
    mov byte [nan], 0
    fld qword [hi]
    fsub qword [lo]
    fidiv dword [i_simp]
    fstp qword [step]
    fldz
    fstp qword [ssum]
    xor ebp, ebp
.s:
    mov [tmpi], ebp
    fild dword [tmpi]
    fmul qword [step]
    fadd qword [lo]
    call f_at
    mov eax, 2                  ; weights 1 4 2 4 ... 4 1
    test ebp, 1
    jz .w
    mov eax, 4
.w:
    test ebp, ebp
    jz .w1
    cmp ebp, [i_simp]
    jne .w2
.w1:
    mov eax, 1
.w2:
    mov [tmpi], eax
    fimul dword [tmpi]
    fadd qword [ssum]
    fstp qword [ssum]
    inc ebp
    cmp ebp, [i_simp]
    jbe .s
    fld qword [ssum]
    fmul qword [step]
    fdiv qword [f_3]
    ret

; ---------- factoring ----------
; polyA (degree >= 1) -> eax = the factored form
factor_poly:
    call rational_roots
    mov eax, [lc_n]             ; K = lc / prod q^m, then the rest's content
    mov edx, [lc_d]
    call mk_rat
    mov [kc], eax
    mov eax, [n_one]
    mov [prod], eax
    xor ebx, ebx
.r:
    cmp ebx, [nroots]
    jae .rest
    mov eax, [root_d+ebx*4]     ; (q x - p)^m
    call mk_int
    mov edx, [n_x]
    call mul2
    push eax
    mov eax, [root_n+ebx*4]
    neg eax
    call mk_int
    pop edx
    call add2
    push eax
    mov eax, [root_m+ebx*4]
    call mk_int
    mov edx, eax
    pop eax
    call pow2
    mov edx, [prod]
    call mul_raw
    mov [prod], eax
    mov eax, [root_d+ebx*4]     ; K / q^m
    neg dword [root_m+ebx*4]
    push eax
    mov eax, [root_m+ebx*4]
    call mk_int
    mov edx, eax
    pop eax
    call mk_int
    call pow2
    mov edx, [kc]
    call mul2
    mov [kc], eax
    inc ebx
    jmp .r
.rest:
    cmp dword [polyA], 0
    jle .k
    call primitive              ; polyA = content * primitive
    mov edx, [kc]
    call mul2
    mov [kc], eax
    mov eax, [polyA]            ; the primitive rest as a polynomial
    call poly_tree
    mov edx, [prod]
    call mul_raw
    mov [prod], eax
.k:
    mov eax, [kc]               ; K first, unless 1
    call is_one
    jnz .nok
    mov eax, [kc]
    call is_mone
    jz .kk
    mov eax, [prod]
    jmp neg_raw
.kk:
    mov eax, [kc]
    mov edx, [prod]
    jmp mul_front
.nok:
    mov eax, [prod]
    ret

; eax, edx -> MUL(edx, eax) without simplifying (edx 1: eax alone)
mul_raw:
    push eax
    mov eax, edx
    call is_one
    pop eax
    jnz .alone
    push ebx
    mov bl, N_MUL
    xchg eax, edx
    call mk2
    pop ebx
.alone:
    ret

; eax = K, edx = product -> MUL(K, product) as a printed coefficient
mul_front:
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    ret
; eax -> MUL(-1, eax) unsimplified
neg_raw:
    mov edx, eax
    mov eax, [n_mone]
    jmp mul_front

; polyA (rational) -> polyA primitive (integer, positive leading
; coefficient), eax = the content it had (a rational node)
primitive:
    pushad
    mov ecx, [polyA]
    fld1                        ; L = lcm of the denominators
    xor ebx, ebx
.l:
    cmp ebx, ecx
    ja .ld
    fild dword [polyA+12+ebx*8]
    call lcm_st
    inc ebx
    jmp .l
.ld:
    fstp qword [lcmv]
    fldz                        ; g = gcd of L * ci
    xor ebx, ebx
.g:
    cmp ebx, ecx
    ja .gd
    fild dword [polyA+8+ebx*8]
    fmul qword [lcmv]
    fidiv dword [polyA+12+ebx*8]
    fabs
    call gcd_st
    inc ebx
    jmp .g
.gd:
    mov eax, [polyA+8+ecx*8]    ; the sign of the leading one
    test eax, eax
    jns .pos
    fchs
.pos:
    fstp qword [gv]
    xor ebx, ebx                ; ci * L / g
.d:
    cmp ebx, ecx
    ja .dd
    fild dword [polyA+8+ebx*8]
    fmul qword [lcmv]
    fidiv dword [polyA+12+ebx*8]
    fdiv qword [gv]
    fistp dword [polyA+8+ebx*8]
    mov dword [polyA+12+ebx*8], 1
    inc ebx
    jmp .d
.dd:
    fld qword [gv]              ; content g / L
    fld qword [lcmv]
    call rat_make
    jc .big
    mov eax, [rn]
    mov edx, [rd]
    call mk_rat
    mov [esp+28], eax
    popad
    ret
.big:
    mov esi, e_big
    jmp cas_error

; st1 = a, st0 = b (integers) -> st0 = gcd (popped one)
gcd_st:
.g:
    ftst
    fnstsw ax
    sahf
    je .d
    fxch
.p:
    fprem
    fnstsw ax
    test ah, 4
    jnz .p
    fabs
    jmp .g
.d:
    fstp st0
    fabs
    ret
; st1 = a, st0 = b -> st0 = lcm(a, b)
lcm_st:
    fld st1
    fld st1
    call gcd_st                 ; st0 = g, st1 = b, st2 = a
    fdivp st1, st0              ; b / g
    fmulp st1, st0
    fabs
    ret

; polyA -> its rational roots (root_n, root_d, root_m; ascending) taken
; out of polyA; lc_n/lc_d its leading coefficient
rational_roots:
    pushad
    mov dword [nroots], 0
    mov eax, [polyA]
    mov ecx, [polyA+8+eax*8]
    mov [lc_n], ecx
    mov ecx, [polyA+12+eax*8]
    mov [lc_d], ecx
.zero:                          ; x itself
    cmp dword [polyA], 1
    jl .done
    cmp dword [polyA+8], 0
    jne .cands
    mov dword [xn], 0
    mov dword [xd], 1
    call take_root
    jmp .zero
.cands:                         ; p | a0 * L, q | an * L
    call int_ends
    jc .done
    mov eax, [end0]
    mov edi, divs0
    call divisors
    mov [ndiv0], ecx
    mov eax, [endn]
    mov edi, divsn
    call divisors
    mov [ndivn], ecx
    xor esi, esi
.p:
    cmp esi, [ndiv0]
    jae .done
    xor edi, edi
.q:
    cmp edi, [ndivn]
    jae .pn
    mov eax, [divs0+esi*4]
    mov edx, [divsn+edi*4]
    mov [xn], eax
    mov [xd], edx
    call try_root
    neg dword [xn]
    call try_root
    inc edi
    jmp .q
.pn:
    inc esi
    jmp .p
.done:
    call sort_roots
    popad
    ret

; rn/rd -> taken out of polyA (as often as it is a root)
try_root:
    pushad
    fild dword [xn]             ; in lowest terms
    fild dword [xd]
    call rat_make
    mov eax, [rn]
    mov [xn], eax
    mov eax, [rd]
    mov [xd], eax
.t:
    cmp dword [polyA], 1
    jl .r
    call poly_at
    jc .r
    cmp dword [vn], 0
    jne .r
    call take_root
    jmp .t
.r:
    popad
    ret

; rn/rd is a root: polyA / (x - r), the root counted
take_root:
    pushad
    mov ecx, [nroots]           ; already there? one more
    xor ebx, ebx
.f:
    cmp ebx, ecx
    jae .new
    mov eax, [xn]
    cmp [root_n+ebx*4], eax
    jne .nf
    mov eax, [xd]
    cmp [root_d+ebx*4], eax
    jne .nf
    inc dword [root_m+ebx*4]
    jmp .div
.nf:
    inc ebx
    jmp .f
.new:
    cmp ecx, 32
    jae .div
    mov eax, [xn]
    mov [root_n+ecx*4], eax
    mov eax, [xd]
    mov [root_d+ecx*4], eax
    mov dword [root_m+ecx*4], 1
    inc dword [nroots]
.div:                           ; synthetic division
    mov ecx, [polyA]
    mov eax, [polyA+8+ecx*8]
    mov [qn], eax
    mov eax, [polyA+12+ecx*8]
    mov [qd], eax
.s:
    dec ecx
    js .sd
    mov eax, [polyA+8+ecx*8]    ; new c[i] = old c[i+1]'s carry: b = c + b r
    push dword [qn]
    push dword [qd]
    mov edx, [xn]
    mov [bn], edx
    mov edx, [xd]
    mov [bd], edx
    mov edx, [qn]
    mov [an], edx
    mov edx, [qd]
    mov [ad], edx
    call rat_mul
    jc .ovf
    mov edx, [rn_]
    mov [an], edx
    mov edx, [rd_]
    mov [ad], edx
    mov edx, [polyA+8+ecx*8]
    mov [bn], edx
    mov edx, [polyA+12+ecx*8]
    mov [bd], edx
    call rat_add
    jc .ovf
    pop edx                     ; the quotient's coefficient
    mov [polyA+12+ecx*8], edx
    pop edx
    mov [polyA+8+ecx*8], edx
    mov edx, [rn_]
    mov [qn], edx
    mov edx, [rd_]
    mov [qd], edx
    jmp .s
.sd:                            ; b[i] are in place: the remainder (0) goes
.shd:
    dec dword [polyA]
    popad
    ret
.ovf:
    mov esi, e_big
    jmp cas_error

; polyA at rn/rd -> vn/vd (Horner); CF on overflow
poly_at:
    pushad
    mov ecx, [polyA]
    mov eax, [polyA+8+ecx*8]
    mov [vn], eax
    mov eax, [polyA+12+ecx*8]
    mov [vd], eax
.h:
    dec ecx
    js .r
    mov eax, [vn]
    mov [an], eax
    mov eax, [vd]
    mov [ad], eax
    mov eax, [xn]
    mov [bn], eax
    mov eax, [xd]
    mov [bd], eax
    call rat_mul
    jc .no
    mov eax, [rn_]
    mov [an], eax
    mov eax, [rd_]
    mov [ad], eax
    mov eax, [polyA+8+ecx*8]
    mov [bn], eax
    mov eax, [polyA+12+ecx*8]
    mov [bd], eax
    call rat_add
    jc .no
    mov eax, [rn_]
    mov [vn], eax
    mov eax, [rd_]
    mov [vd], eax
    jmp .h
.r:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; polyA -> end0 = |c0 L|, endn = |cn L| (L the denominators' lcm); CF
; if too large
int_ends:
    mov ecx, [polyA]
    fld1
    xor ebx, ebx
.l:
    cmp ebx, ecx
    ja .ld
    fild dword [polyA+12+ebx*8]
    call lcm_st
    inc ebx
    jmp .l
.ld:
    fld st0
    fimul dword [polyA+8]
    fidiv dword [polyA+12]
    fabs
    fcom qword [f_maxdiv]
    fnstsw ax
    sahf
    ja .big2
    fistp dword [end0]
    fimul dword [polyA+8+ecx*8]
    fidiv dword [polyA+12+ecx*8]
    fabs
    fcom qword [f_maxdiv]
    fnstsw ax
    sahf
    ja .big1
    fistp dword [endn]
    clc
    ret
.big2:
    fstp st0
.big1:
    fstp st0
    stc
    ret

; eax = n > 0, edi = array -> its divisors, ecx = how many (at most 64)
divisors:
    push ebx
    push edx
    push esi
    mov esi, eax
    xor ecx, ecx
    mov ebx, 1
.d:
    mov eax, ebx
    mul ebx
    cmp eax, esi
    ja .r
    mov eax, esi
    xor edx, edx
    div ebx
    test edx, edx
    jnz .n
    cmp ecx, 62
    jae .r
    mov [edi+ecx*4], ebx
    inc ecx
    cmp eax, ebx
    je .n
    mov [edi+ecx*4], eax
    inc ecx
.n:
    inc ebx
    jmp .d
.r:
    pop esi
    pop edx
    pop ebx
    ret

; the roots in ascending order
sort_roots:
    pushad
    mov ecx, [nroots]
.o:
    xor edx, edx                ; a swap made
    xor ebx, ebx
.i:
    lea eax, [ebx+1]
    cmp eax, ecx
    jae .e
    fild dword [root_n+ebx*4]   ; r[b] > r[b+1]?
    fidiv dword [root_d+ebx*4]
    fild dword [root_n+eax*4]
    fidiv dword [root_d+eax*4]
    fcomip st0, st1
    fstp st0
    jae .ni
    mov esi, [root_n+ebx*4]
    xchg esi, [root_n+eax*4]
    mov [root_n+ebx*4], esi
    mov esi, [root_d+ebx*4]
    xchg esi, [root_d+eax*4]
    mov [root_d+ebx*4], esi
    mov esi, [root_m+ebx*4]
    xchg esi, [root_m+eax*4]
    mov [root_m+ebx*4], esi
    inc edx
.ni:
    inc ebx
    jmp .i
.e:
    test edx, edx
    jnz .o
    popad
    ret

; esi = a coefficient (num, den) -> eax = its node
coef_node:
    mov eax, [esi]
    mov edx, [esi+4]
    jmp mk_rat

; eax = degree of polyA -> eax = the polynomial as a (simplified) tree
poly_tree:
    pushad
    mov ebx, [polyA]
    mov eax, [n_zero]
    mov [ptree], eax
.t:
    test ebx, ebx
    js .d
    lea esi, [polyA+8+ebx*8]
    call coef_node
    push eax
    mov eax, ebx
    call mk_int
    mov edx, eax
    mov eax, [n_x]
    call pow2
    pop edx
    call mul2
    mov edx, [ptree]
    call add2
    mov [ptree], eax
    dec ebx
    jmp .t
.d:
    mov eax, [ptree]
    mov [esp+28], eax
    popad
    ret

; eax = an expanded, simplified node, edi = a polynomial -> its
; coefficients in x; CF if it is not a polynomial with exact numbers
poly_of:
    pushad
    mov [polyp], edi
    mov ecx, (POLY_SZ) / 4
    push edi
    xor eax, eax
    rep stosd
    pop edi
    mov eax, [esp+28]
    mov ecx, POLY_DEG           ; every denominator 1
.z:
    mov dword [edi+12+ecx*8], 1
    dec ecx
    jns .z
    mov dword [edi], 0
    mov ebp, [ltop]
    call push_terms
    mov ebx, ebp
.t:
    cmp ebx, [ltop]
    jae .done
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    call split_coef             ; eax = coefficient, edx = rest (0: none)
    NP esi, eax
    cmp byte [esi], N_NUM
    jne .no
    xor ecx, ecx                ; the power of x
    test edx, edx
    jz .add
    cmp edx, [n_x]
    je .one
    NP edi, edx
    cmp byte [edi], N_VAR
    jne .pw
    cmp byte [edi+1], 'x'
    jne .no
.one:
    mov ecx, 1
    jmp .add
.pw:
    cmp byte [edi], N_POW
    jne .no
    mov eax, [edi+4]
    NP eax, eax
    cmp byte [eax], N_VAR
    jne .no
    cmp byte [eax+1], 'x'
    jne .no
    mov eax, [edi+8]
    NP eax, eax
    cmp byte [eax], N_NUM
    jne .no
    cmp dword [eax+8], 1
    jne .no
    mov ecx, [eax+4]
    cmp ecx, POLY_DEG
    ja .no
.add:
    mov edi, [polyp]
    mov eax, [esi+4]
    mov [an], eax
    mov eax, [esi+8]
    mov [ad], eax
    mov eax, [edi+8+ecx*8]
    mov [bn], eax
    mov eax, [edi+12+ecx*8]
    mov [bd], eax
    call rat_add
    jc .no
    mov eax, [rn_]
    mov [edi+8+ecx*8], eax
    mov eax, [rd_]
    mov [edi+12+ecx*8], eax
    cmp ecx, [edi]
    jbe .n
    mov [edi], ecx
.n:
    inc ebx
    jmp .t
.done:
    mov [ltop], ebp
    mov edi, [polyp]            ; the degree: the last non-zero
.dg:
    mov ecx, [edi]
    test ecx, ecx
    js .r
    cmp dword [edi+8+ecx*8], 0
    jne .r
    dec dword [edi]
    jmp .dg
.r:
    popad
    clc
    ret
.no:
    mov [ltop], ebp
    popad
    stc
    ret

; ---------- rationals (exact in the FPU's 64-bit mantissa) ----------
; st1 = n, st0 = d (integers) -> rn, rd in lowest terms (d > 0); both
; popped; CF if d = 0 or a result does not fit 31 bits
rat_make:
    push eax
    ftst
    fnstsw ax
    sahf
    je .bad
    jae .pos
    fchs
    fxch
    fchs
    fxch
.pos:
    fld st1
    fabs
    fld st1
    call gcd_st                 ; st0 = g, st1 = d, st2 = n
    ftst
    fnstsw ax
    sahf
    jne .g
    fstp st0
    fld1
.g:
    fdiv st1, st0
    fdivp st2, st0              ; st0 = d, st1 = n
    fld st0
    fabs
    fcomp qword [f_2p31]
    fnstsw ax
    sahf
    jae .bad
    fld st1
    fabs
    fcomp qword [f_2p31]
    fnstsw ax
    sahf
    jae .bad
    fistp dword [rd]
    fistp dword [rn]
    pop eax
    clc
    ret
.bad:
    fstp st0
    fstp st0
    pop eax
    stc
    ret

; an/ad + bn/bd -> rn_/rd_ (CF on overflow)
rat_add:
    fild dword [an]
    fimul dword [bd]
    fild dword [bn]
    fimul dword [ad]
    faddp st1, st0
    fild dword [ad]
    fimul dword [bd]
    jmp rat_out
rat_mul:
    fild dword [an]
    fimul dword [bn]
    fild dword [ad]
    fimul dword [bd]
rat_out:
    call rat_make
    jc .r
    push eax
    mov eax, [rn]
    mov [rn_], eax
    mov eax, [rd]
    mov [rd_], eax
    pop eax
.r:
    ret

; ---------- nodes ----------
; bl = type -> eax = a new node, edi = it (zeroed)
new_node:
    mov eax, [nfree]
    cmp eax, POOL_N
    jae .full
    inc dword [nfree]
    mov edi, eax
    shl edi, 4
    add edi, [pool]
    mov dword [edi], 0
    mov dword [edi+4], 0
    mov dword [edi+8], 0
    mov dword [edi+12], 0
    mov [edi], bl
    ret
.full:
    mov esi, e_big
    jmp cas_error

; eax = n -> eax = the integer node
mk_int:
    push edx
    mov edx, 1
    call mk_rat
    pop edx
    ret
; eax = num, edx = den (lowest terms, den > 0) -> eax
mk_rat:
    push ebx
    push edi
    push eax
    mov bl, N_NUM
    call new_node
    pop dword [edi+4]
    mov [edi+8], edx
    pop edi
    pop ebx
    ret
; st0 (popped) -> eax = a float node
mk_flt:
    push ebx
    push edi
    mov bl, N_FLT
    call new_node
    fstp qword [edi+8]
    pop edi
    pop ebx
    ret
; bl = type, cl = sub -> eax
mk_leaf:
    push edi
    call new_node
    mov [edi+1], cl
    pop edi
    ret
; bl = type, eax = a, edx = b -> eax
mk2:
    push edi
    push eax
    call new_node
    pop dword [edi+4]
    mov [edi+8], edx
    pop edi
    ret
; bl = function, eax = argument -> eax (not simplified)
mk_fn:
    push ebx
    push edi
    push eax
    push ebx
    mov bl, N_FN
    call new_node
    pop ebx
    mov [edi+1], bl
    pop dword [edi+4]
    pop edi
    pop ebx
    ret

; eax, edx -> eax = simp(a + b) / simp(a * b) / simp(a ^ b) / -a
add2:
    push ebx
    mov bl, N_ADD
    call mk2
    pop ebx
    jmp add_simp
mul2:
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    jmp mul_simp
pow2:
    jmp pow_simp
neg:
    mov edx, [n_mone]
    jmp mul2

; eax -> ZF clear (jnz) if it is the number 0 / 1 / -1
is_zero:
    push edi
    NP edi, eax
    cmp byte [edi], N_NUM
    jne .no
    cmp dword [edi+4], 0
    jne .no
    pop edi
    test esp, esp               ; ZF clear
    ret
.no:
    pop edi
    cmp eax, eax                ; ZF set
    ret
is_one:
    push edi
    NP edi, eax
    cmp byte [edi], N_NUM
    jne is_zero.no
    cmp dword [edi+4], 1
    jne is_zero.no
    cmp dword [edi+8], 1
    jne is_zero.no
    pop edi
    test esp, esp               ; ZF clear
    ret
is_mone:
    push edi
    NP edi, eax
    cmp byte [edi], N_NUM
    jne is_zero.no
    cmp dword [edi+4], -1
    jne is_zero.no
    cmp dword [edi+8], 1
    jne is_zero.no
    pop edi
    test esp, esp               ; ZF clear
    ret

; eax -> ZF clear (jnz) if x / any variable / undefined is in it
has_x:
    push ecx
    mov cl, 1
    call find_in
    pop ecx
    ret
has_var:
    push ecx
    mov cl, 2
    call find_in
    pop ecx
    ret
has_undef:
    push ecx
    mov cl, 3
    call find_in
    pop ecx
    ret
find_in:                        ; cl: 1 x, 2 a variable, 3 undefined
    pushad
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_VAR
    jne .u
    cmp cl, 2
    je .yes
    cmp cl, 1
    jne .no
    cmp byte [edi+1], 'x'
    je .yes
    jmp .no
.u:
    cmp ebx, N_UNDEF
    jne .k
    cmp cl, 3
    je .yes
    jmp .no
.k:
    cmp ebx, N_FN
    je .one
    cmp ebx, N_POW
    jb .no
.two:
    mov eax, [edi+8]
    call find_in
    jnz .yes
.one:
    mov eax, [edi+4]
    call find_in
    jnz .yes
.no:
    popad
    cmp eax, eax
    ret
.yes:
    popad
    or esp, esp                 ; ZF clear (esp is not 0)
    ret

; eax = node, edx = a value -> eax = a copy with x replaced by it
subst:
    pushad
    mov [sub_val], edx
    call sub_rec
    mov [esp+28], eax
    popad
    ret
sub_rec:
    push ebx
    push edi
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_VAR
    jne .k
    cmp byte [edi+1], 'x'
    jne .r
    mov eax, [sub_val]
    jmp .r
.k:
    cmp ebx, N_FN
    je .fn
    cmp ebx, N_POW
    jb .r
    cmp ebx, N_UNDEF
    je .r
    push edx
    mov eax, [edi+4]
    call sub_rec
    push eax
    mov eax, [edi+8]
    call sub_rec
    mov edx, eax
    pop eax
    call mk2                    ; bl = the type
    pop edx
    jmp .r
.fn:
    mov eax, [edi+4]
    call sub_rec
    push ebx
    mov bl, [edi+1]
    call mk_fn
    pop ebx
.r:
    pop edi
    pop ebx
    ret

; ---------- ordering ----------
; eax, edx -> eax = -1, 0, 1 (a before, equal to, after b)
compare:
    pushad
    NP esi, eax
    NP edi, edx
    movzx ecx, byte [esi]
    movzx ebx, byte [edi]
    cmp ecx, ebx
    jne .bytype
    cmp ecx, N_NUM
    je .num
    cmp ecx, N_FLT
    je .flt
    cmp ecx, N_POW
    jb .sub                     ; CON, VAR: their letter / id
    cmp ecx, N_FN
    je .fn
    cmp ecx, N_UNDEF
    je .eq
    mov eax, [esi+4]            ; POW, MUL, ADD: a, then b
    mov edx, [edi+4]
    call compare
    test eax, eax
    jnz .out
    mov eax, [esi+8]
    mov edx, [edi+8]
    call compare
    jmp .out
.fn:
    mov al, [esi+1]
    cmp al, [edi+1]
    jb .lt
    ja .gt
    mov eax, [esi+4]
    mov edx, [edi+4]
    call compare
    jmp .out
.sub:
    mov al, [esi+1]
    cmp al, [edi+1]
    jb .lt
    ja .gt
    jmp .eq
.num:
    fild dword [esi+4]
    fimul dword [edi+8]
    fild dword [edi+4]
    fimul dword [esi+8]
    jmp .fc
.flt:
    fld qword [esi+8]
    fld qword [edi+8]
.fc:
    fcomip st0, st1
    fstp st0
    ja .lt
    jb .gt
.eq:
    xor eax, eax
    jmp .out
.bytype:
    jb .lt
.gt:
    mov eax, 1
    jmp .out
.lt:
    mov eax, -1
.out:
    mov [esp+28], eax
    popad
    ret

; eax -> st0 = its degree in x (for ordering terms)
degree:
    push edi
    NP edi, eax
    movzx eax, byte [edi]
    cmp eax, N_VAR
    je .var
    cmp eax, N_POW
    je .pow
    cmp eax, N_MUL
    je .mul
    cmp eax, N_ADD
    je .add
    cmp eax, N_FN
    je .fn
.zero:
    fldz
    jmp .r
.var:
    cmp byte [edi+1], 'x'
    jne .zero
    fld1
    jmp .r
.fn:
    mov eax, [edi+4]
    call has_x
    jz .zero
    fld qword [f_half]
    jmp .r
.pow:
    mov eax, [edi+8]
    NP eax, eax
    cmp byte [eax], N_NUM
    jne .pz
    mov eax, [edi+4]
    call degree
    NP eax, [edi+8]
    fimul dword [eax+4]
    fidiv dword [eax+8]
    jmp .r
.pz:
    mov eax, [edi+4]
    call degree
    jmp .r
.mul:
    mov eax, [edi+4]
    call degree
    mov eax, [edi+8]
    call degree
    faddp st1, st0
    jmp .r
.add:
    mov eax, [edi+4]
    call degree
    mov eax, [edi+8]
    call degree
    fcomi st0, st1
    jae .m
    fxch
.m:
    fstp st1
.r:
    pop edi
    ret

; ---------- lists ----------
; eax -> on the work list
lpush:
    push ecx
    mov ecx, [ltop]
    cmp ecx, LIST_N
    jae .full
    push edx
    mov edx, [list]
    mov [edx+ecx*4], eax
    pop edx
    inc dword [ltop]
    pop ecx
    ret
.full:
    mov esi, e_big
    jmp cas_error

; eax -> its factors (a product's, flattened) on the list
push_factors:
    push edi
    NP edi, eax
    cmp byte [edi], N_MUL
    jne .one
    mov eax, [edi+4]
    call push_factors
    mov eax, [edi+8]
    call push_factors
    pop edi
    ret
.one:
    pop edi
    jmp lpush
; eax -> its terms (a sum's, flattened) on the list
push_terms:
    push edi
    NP edi, eax
    cmp byte [edi], N_ADD
    jne .one
    mov eax, [edi+4]
    call push_terms
    mov eax, [edi+8]
    call push_terms
    pop edi
    ret
.one:
    pop edi
    jmp lpush

; eax = a term -> eax = its numeric coefficient, edx = the rest (0 if
; none)
split_coef:
    push ebx
    push ecx
    push edi
    push ebp
    mov [sc_term], eax
    NP edi, eax
    cmp byte [edi], N_NUM
    je .num
    cmp byte [edi], N_FLT
    je .num
    cmp byte [edi], N_MUL
    jne .plain
    mov ebp, [ltop]
    call push_factors
    mov ecx, [list]
    mov eax, [ecx+ebp*4]
    NP edi, eax
    cmp byte [edi], N_NUM
    je .c
    cmp byte [edi], N_FLT
    je .c
    mov [ltop], ebp
    mov eax, [sc_term]
    jmp .plain0
.c:
    mov [sc_coef], eax
    lea ebx, [ebp+1]            ; the others, as a product
    mov eax, [ecx+ebx*4]
    inc ebx
.r:
    cmp ebx, [ltop]
    jae .rd
    mov edx, [ecx+ebx*4]
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    inc ebx
    jmp .r
.rd:
    mov [ltop], ebp
    mov edx, eax
    mov eax, [sc_coef]
    jmp .out
.plain0:
.plain:
    mov edx, eax
    mov eax, [n_one]
    jmp .out
.num:
    xor edx, edx
.out:
    pop ebp
    pop edi
    pop ecx
    pop ebx
    ret

; ---------- simplifying ----------
; eax -> eax = simplified
simp:
    push ebx
    push ecx
    push edx
    push edi
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_POW
    je .pow
    cmp ebx, N_FN
    je .fn
    cmp ebx, N_MUL
    je .mul
    cmp ebx, N_ADD
    je .add
    jmp .r
.pow:
    mov eax, [edi+4]
    call simp
    push eax
    mov eax, [edi+8]
    call simp
    mov edx, eax
    pop eax
    call pow_simp
    jmp .r
.fn:
    movzx ecx, byte [edi+1]
    mov eax, [edi+4]
    call simp
    call fn_simp
    jmp .r
.mul:
    call mul_simp
    jmp .r
.add:
    call add_simp
.r:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; eax = a product -> eax = it simplified: one numeric coefficient first,
; then each base once with its powers added, in order
mul_simp:
    pushad
    mov ebp, [ltop]
    call gather_mul
    push dword [ftop]
    push dword 3                ; passes left
    push dword [n_one]          ; the coefficient
.pass:
    mov ecx, [esp+8]            ; the factor table from here
    mov [ftop], ecx
    mov ebx, ebp
.f:
    cmp ebx, [ltop]
    jae .built
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    NP edi, eax
    movzx ecx, byte [edi]
    cmp ecx, N_UNDEF
    je .undef
    cmp ecx, N_NUM
    je .numf
    cmp ecx, N_FLT
    je .numf
    cmp ecx, N_POW
    jne .base1
    mov eax, [edi+4]
    mov edx, [edi+8]
    jmp .tab
.base1:
    mov edx, [n_one]
.tab:
    mov ecx, [esp+8]            ; the same base already?
.s:
    cmp ecx, [ftop]
    jae .new
    push edx
    mov edx, [fb]
    mov edx, [edx+ecx*4]
    push eax
    call compare
    test eax, eax
    pop eax
    pop edx
    je .same
    inc ecx
    jmp .s
.same:
    push eax
    mov eax, [fe]
    mov eax, [eax+ecx*4]
    call add2
    mov edx, [fe]
    mov [edx+ecx*4], eax
    pop eax
    jmp .nf
.new:
    mov ecx, [ftop]
    cmp ecx, LIST_N
    jae .full
    mov edi, [fb]
    mov [edi+ecx*4], eax
    mov edi, [fe]
    mov [edi+ecx*4], edx
    inc dword [ftop]
    jmp .nf
.numf:
    mov edx, [esp]
    call num_mul
    mov [esp], eax
.nf:
    inc ebx
    jmp .f
.built:                         ; each base ^ its power
    mov [ltop], ebp
    mov byte [again], 0
    mov ebx, [esp+8]
.b:
    cmp ebx, [ftop]
    jae .bd
    mov eax, [fb]
    mov eax, [eax+ebx*4]
    mov edx, [fe]
    mov edx, [edx+ebx*4]
    call pow_simp
    NP edi, eax
    movzx ecx, byte [edi]
    cmp ecx, N_NUM
    je .bnum
    cmp ecx, N_FLT
    je .bnum
    cmp ecx, N_MUL
    jne .bput
    call push_factors           ; came apart: once more
    mov byte [again], 1
    jmp .bn
.bnum:
    mov edx, [esp]
    call num_mul
    mov [esp], eax
    jmp .bn
.bput:
    call lpush
.bn:
    inc ebx
    jmp .b
.bd:
    cmp byte [again], 0
    je .order
    dec dword [esp+4]
    jnz .pass
.order:
    mov eax, [esp]              ; 0 times anything
    call is_zero
    jnz .zero
    call sort_factors
    mov eax, [esp]              ; the coefficient first, unless 1
    call is_one
    jz .withc
    mov ebx, ebp
    cmp ebx, [ltop]
    jae .justone
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    inc ebx
    jmp .chain
.withc:
    mov eax, [esp]
    mov ebx, ebp
.chain:
    cmp ebx, [ltop]
    jae .done
    mov ecx, [list]
    mov edx, [ecx+ebx*4]
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    inc ebx
    jmp .chain
.justone:
    mov eax, [n_one]
    jmp .done
.zero:
    mov eax, [esp]
    jmp .done
.undef:
    mov eax, [n_undef]
.done:
    add esp, 8
    pop dword [ftop]
    mov [ltop], ebp
    mov [esp+28], eax
    popad
    ret
.full:
    mov esi, e_big
    jmp cas_error

; eax -> its factors, each simplified, on the list (products flattened)
gather_mul:
    push edi
    NP edi, eax
    cmp byte [edi], N_MUL
    jne .one
    mov eax, [edi+4]
    call gather_mul
    mov eax, [edi+8]
    call gather_mul
    pop edi
    ret
.one:
    pop edi
    call simp
    jmp push_factors
gather_add:
    push edi
    NP edi, eax
    cmp byte [edi], N_ADD
    jne .one
    mov eax, [edi+4]
    call gather_add
    mov eax, [edi+8]
    call gather_add
    pop edi
    ret
.one:
    pop edi
    call simp
    jmp push_terms

; the list from ebp up: factors in order (by base, then power)
sort_factors:
    pushad
    mov esi, [list]
    lea ebx, [ebp+1]
.o:
    cmp ebx, [ltop]
    jae .r
    mov ecx, ebx
.i:
    cmp ecx, ebp
    jbe .n
    mov eax, [esi+ecx*4-4]
    mov edx, [esi+ecx*4]
    call factor_cmp
    cmp eax, 0
    jle .n
    mov eax, [esi+ecx*4-4]
    xchg eax, [esi+ecx*4]
    mov [esi+ecx*4-4], eax
    dec ecx
    jmp .i
.n:
    inc ebx
    jmp .o
.r:
    popad
    ret

; eax, edx = factors -> eax = their order: by base, then by power
factor_cmp:
    push ebx
    push ecx
    push edi
    mov ebx, [n_one]
    mov ecx, ebx
    NP edi, eax
    cmp byte [edi], N_POW
    jne .a
    mov ebx, [edi+8]
    mov eax, [edi+4]
.a:
    NP edi, edx
    cmp byte [edi], N_POW
    jne .b
    mov ecx, [edi+8]
    mov edx, [edi+4]
.b:
    call compare
    test eax, eax
    jnz .r
    mov eax, ebx
    mov edx, ecx
    call compare
.r:
    pop edi
    pop ecx
    pop ebx
    ret

; eax = a sum -> eax = it simplified: like terms added, in order
add_simp:
    pushad
    mov ebp, [ltop]
    call gather_add
    push dword [ftop]
    push dword [n_zero]         ; the constant term
    mov edi, [ltop]
    mov ebx, ebp
.t:
    cmp ebx, edi
    jae .built
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    NP esi, eax
    cmp byte [esi], N_UNDEF
    je .undef
    call split_coef
    test edx, edx
    jnz .term
    mov edx, [esp]
    call num_add
    mov [esp], eax
    jmp .n
.term:
    mov ecx, [esp+4]            ; the same rest already?
.s:
    cmp ecx, [ftop]
    jae .new
    push eax
    push edx
    mov eax, [fb]
    mov eax, [eax+ecx*4]
    call compare
    test eax, eax
    pop edx
    pop eax
    je .same
    inc ecx
    jmp .s
.same:
    mov edx, [fe]
    mov edx, [edx+ecx*4]
    call num_add
    mov edx, [fe]
    mov [edx+ecx*4], eax
    jmp .n
.new:
    mov ecx, [ftop]
    cmp ecx, LIST_N
    jae .full
    mov esi, [fb]
    mov [esi+ecx*4], edx
    mov esi, [fe]
    mov [esi+ecx*4], eax
    inc dword [ftop]
.n:
    inc ebx
    jmp .t
.built:                         ; coefficient * rest, each
    mov [ltop], ebp
    mov ebx, [esp+4]
.b:
    cmp ebx, [ftop]
    jae .bd
    mov eax, [fe]
    mov eax, [eax+ebx*4]
    call is_zero
    jnz .bn
    mov edx, [fb]
    mov edx, [edx+ebx*4]
    call is_one
    jz .times
    mov eax, edx
    jmp .put
.times:
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    call mul_simp
.put:
    call lpush
.bn:
    inc ebx
    jmp .b
.bd:
    mov eax, [esp]
    call is_zero
    jnz .noc
    call lpush
.noc:
    call sort_terms
    mov ebx, ebp
    cmp ebx, [ltop]
    jae .none
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    inc ebx
.chain:
    cmp ebx, [ltop]
    jae .done
    mov edx, [ecx+ebx*4]
    push ebx
    mov bl, N_ADD
    call mk2
    pop ebx
    inc ebx
    jmp .chain
.none:
    mov eax, [n_zero]
    jmp .done
.undef:
    mov eax, [n_undef]
.done:
    add esp, 4
    pop dword [ftop]
    mov [ltop], ebp
    mov [esp+28], eax
    popad
    ret
.full:
    mov esi, e_big
    jmp cas_error

; the list from ebp up: terms by degree (falling, or rising if asc),
; then in order
sort_terms:
    pushad
    mov esi, [list]
    lea ebx, [ebp+1]
.o:
    cmp ebx, [ltop]
    jae .r
    mov ecx, ebx
.i:
    cmp ecx, ebp
    jbe .n
    mov eax, [esi+ecx*4-4]
    mov edx, [esi+ecx*4]
    call term_cmp
    cmp eax, 0
    jle .n
    mov eax, [esi+ecx*4-4]
    xchg eax, [esi+ecx*4]
    mov [esi+ecx*4-4], eax
    dec ecx
    jmp .i
.n:
    inc ebx
    jmp .o
.r:
    popad
    ret

; eax, edx = terms -> eax > 0 if they are out of order
term_cmp:
    push eax
    call degree
    mov eax, edx
    call degree                 ; st0 = deg b, st1 = deg a
    pop eax
    cmp byte [asc], 0
    je .desc
    fxch
.desc:
    fcomip st0, st1             ; (desc: b > a is out of order)
    fstp st0
    ja .out
    jb .in
    push edx                    ; the same degree: their order
    call split_coef
    mov eax, edx
    pop edx
    push eax
    mov eax, edx
    call split_coef
    pop eax
    test eax, eax
    jz .in
    test edx, edx
    jz .out
    jmp compare
.out:
    mov eax, 1
    ret
.in:
    mov eax, -1
    ret

; eax, edx = numbers -> eax = their sum / product (exact while it fits)
num_add:
    push ecx
    mov cl, 0
    jmp num_op
num_mul:
    push ecx
    mov cl, 1
num_op:
    push esi
    push edi
    NP esi, eax
    NP edi, edx
    cmp byte [esi], N_NUM
    jne .flt
    cmp byte [edi], N_NUM
    jne .flt
    mov eax, [esi+4]
    mov [an], eax
    mov eax, [esi+8]
    mov [ad], eax
    mov eax, [edi+4]
    mov [bn], eax
    mov eax, [edi+8]
    mov [bd], eax
    test cl, cl
    jnz .m
    call rat_add
    jmp .e
.m:
    call rat_mul
.e:
    jc .flt
    mov eax, [rn_]
    mov edx, [rd_]
    call mk_rat
    jmp .r
.flt:
    call fval_esi
    call fval_edi
    test cl, cl
    jnz .fm
    faddp st1, st0
    jmp .fd
.fm:
    fmulp st1, st0
.fd:
    call mk_flt
.r:
    pop edi
    pop esi
    pop ecx
    ret
fval_esi:
    cmp byte [esi], N_NUM
    jne .f
    fild dword [esi+4]
    fidiv dword [esi+8]
    ret
.f:
    fld qword [esi+8]
    ret
fval_edi:
    cmp byte [edi], N_NUM
    jne .f
    fild dword [edi+4]
    fidiv dword [edi+8]
    ret
.f:
    fld qword [edi+8]
    ret

; eax = base, edx = power (both simplified) -> eax
pow_simp:
    pushad
    NP esi, eax
    NP edi, edx
    cmp byte [esi], N_UNDEF
    je .undef
    cmp byte [edi], N_UNDEF
    je .undef
    xchg eax, edx
    call is_zero                ; ^0
    xchg eax, edx
    jnz .one
    xchg eax, edx
    call is_one                 ; ^1
    xchg eax, edx
    jnz .out
    call is_one                 ; 1^
    jnz .out
    call is_zero                ; 0^
    jz .nz
    cmp byte [edi], N_NUM
    jne .keep
    cmp dword [edi+4], 0
    jg .out
    jmp .undef
.nz:
    cmp byte [esi], N_CON       ; e^u: exp(u)
    jne .ne
    cmp byte [esi+1], C_E
    jne .ne
    mov eax, edx
    mov ecx, F_EXP
    call fn_simp
    jmp .out
.ne:
    cmp byte [esi], N_FLT       ; numbers, inexact
    je .fnum
    cmp byte [edi], N_FLT
    jne .exact
    cmp byte [esi], N_NUM
    je .fnum
    jmp .keep
.exact:
    cmp byte [edi], N_NUM
    jne .notnum
    cmp byte [esi], N_NUM
    je .numnum
    cmp dword [edi+8], 1        ; integer powers of powers and products
    jne .keep
    cmp byte [esi], N_POW
    je .powpow
    cmp byte [esi], N_MUL
    je .mulpow
    jmp .keep
.powpow:                        ; (u^a)^n = u^(a n)
    push edx
    mov eax, [esi+8]
    call mul2
    mov edx, eax
    mov eax, [esi+4]
    call pow_simp
    pop edx
    jmp .out
.mulpow:                        ; (u v)^n = u^n v^n
    mov ebx, edx
    mov ebp, [ltop]
    call push_factors
    mov eax, [n_one]
    mov [pw_acc], eax
    mov ecx, ebp
.mp:
    cmp ecx, [ltop]
    jae .mpd
    mov eax, [list]
    mov eax, [eax+ecx*4]
    mov edx, ebx
    call pow_simp
    push ebx
    push ecx
    mov edx, [pw_acc]
    call mul2
    pop ecx
    pop ebx
    mov [pw_acc], eax
    inc ecx
    jmp .mp
.mpd:
    mov [ltop], ebp
    mov eax, [pw_acc]
    jmp .out
.notnum:
    jmp .keep
.numnum:                        ; rational ^ rational
    cmp dword [edi+8], 1
    je .intpow
    call root_pow
    jmp .out
.intpow:
    mov ecx, [edi+4]
    call rat_pow
    jmp .out
.fnum:
    call fval_esi
    call fval_edi
    call fpow
    cmp byte [nan], 0
    jne .undef0
    call mk_flt
    jmp .out
.undef0:
    mov byte [nan], 0
    fstp st0
.undef:
    mov eax, [n_undef]
    jmp .out
.one:
    mov eax, [n_one]
    jmp .out
.keep:
    push ebx
    mov bl, N_POW
    call mk2
    pop ebx
.out:
    mov [esp+28], eax
    popad
    ret

; esi = a rational node, ecx = an integer -> eax = its power (exact if it
; fits, otherwise a float)
rat_pow:
    mov eax, [esi+4]
    mov edx, [esi+8]
    test ecx, ecx
    jns .p
    neg ecx
    test eax, eax               ; 1/(a/b) = b/a
    jz .zero
    xchg eax, edx
    test edx, edx
    jns .p
    neg eax
    neg edx
.p:
    mov [pbn], eax
    mov [pbd], edx
    mov dword [an], 1
    mov dword [ad], 1
    cmp ecx, 64
    ja .flt
.m:
    test ecx, ecx
    jz .done
    mov eax, [pbn]
    mov [bn], eax
    mov eax, [pbd]
    mov [bd], eax
    call rat_mul
    jc .flt
    mov eax, [rn_]
    mov [an], eax
    mov eax, [rd_]
    mov [ad], eax
    dec ecx
    jmp .m
.done:
    mov eax, [an]
    mov edx, [ad]
    jmp mk_rat
.zero:
    mov eax, [n_undef]
    ret
.flt:
    fild dword [esi+4]
    fidiv dword [esi+8]
    fld st0
    fstp qword [numv]
    fstp st0
    fld qword [numv]
    mov [tmpi], ecx
    fild dword [tmpi]
    call fpow
    jmp mk_flt

; esi = n/d, edi = p/q (q > 1) -> eax = (n/d)^(p/q): exact roots, and
; square roots with their square factors taken out
root_pow:
    mov ecx, [edi+8]            ; q
    cmp dword [esi+4], 0
    jl .keep
    mov eax, [esi+4]
    call int_root
    jc .notexact
    mov [rootn], eax
    mov eax, [esi+8]
    call int_root
    jc .notexact
    mov [rootd], eax
    mov eax, [rootn]            ; (root)^p
    mov edx, [rootd]
    call mk_rat
    NP esi, eax
    mov ecx, [edi+4]
    jmp rat_pow
.notexact:
    cmp ecx, 2                  ; sqrt(n/d)^p: p = +-1
    jne .keep
    mov eax, [edi+4]
    cmp eax, 1
    je .sq
    cmp eax, -1
    jne .keep
.sq:
    mov eax, [esi+4]            ; m = n d
    mul dword [esi+8]
    test edx, edx
    jnz .keep
    test eax, eax
    js .keep
    call square_part            ; m = k^2 m'
    mov [sqm], eax
    mov [sqk], ecx
    mov eax, [sqm]              ; sqrt(m')
    call mk_int
    mov edx, [n_half]
    push ebx
    mov bl, N_POW
    call mk2
    pop ebx
    mov [sqr], eax
    cmp dword [edi+4], 1
    jne .inv
    mov eax, [sqk]              ; k/d sqrt(m')
    mov edx, [esi+8]
    call reduce_rat
    jmp .times
.inv:                           ; d/(k m') sqrt(m')
    mov eax, [esi+8]
    mov ecx, [sqk]
    imul ecx, [sqm]
    mov edx, ecx
    call reduce_rat
.times:
    mov edx, [sqr]
    call is_one
    jnz .alone
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    ret
.alone:
    mov eax, edx
    ret
.keep:
    mov eax, esi
    sub eax, [pool]
    shr eax, 4
    mov edx, edi
    sub edx, [pool]
    shr edx, 4
    push ebx
    mov bl, N_POW
    call mk2
    pop ebx
    ret

; eax = n >= 0, ecx = q -> eax = its exact q-th root, or CF
int_root:
    push edx
    push ecx
    push ebx
    mov ebx, eax                ; n
    cmp eax, 1
    jbe .yes
    mov [tmpi], eax
    fild dword [tmpi]
    fld1
    mov [tmpi], ecx
    fidiv dword [tmpi]
    call fpow
    frndint
    fistp dword [tmpi]
    mov eax, [tmpi]             ; check: root^q == n
    mov edx, 1
.c:
    imul edx, eax
    jo .no
    loop .c
    cmp edx, ebx
    jne .no
.yes:
    pop ebx
    pop ecx
    pop edx
    clc
    ret
.no:
    pop ebx
    pop ecx
    pop edx
    stc
    ret

; eax = m > 0 -> eax = m' (square-free part), ecx = k (m = k^2 m')
square_part:
    push ebx
    push edx
    mov ecx, 1
    mov ebx, 2
.f:
    push eax
    mov eax, ebx
    mul ebx
    mov edx, eax
    pop eax
    cmp edx, eax
    ja .r
    push eax
    xor edx, edx
    div ebx
    test edx, edx
    jnz .n0
    push eax
    xor edx, edx
    div ebx
    test edx, edx
    pop edx
    jnz .n1
    add esp, 4                  ; b^2 divides m
    imul ecx, ebx
    jmp .f
.n1:
    mov eax, edx
.n0:
    pop eax
    inc ebx
    jmp .f
.r:
    pop edx
    pop ebx
    ret

; eax = a, edx = b > 0 -> eax = the node a/b in lowest terms
reduce_rat:
    mov [tmpi], eax
    fild dword [tmpi]
    mov [tmpi], edx
    fild dword [tmpi]
    call rat_make
    mov eax, [rn]
    mov edx, [rd]
    jmp mk_rat

; ecx = function, eax = argument (simplified) -> eax
fn_simp:
    pushad
    NP esi, eax
    cmp byte [esi], N_UNDEF
    je .out
    cmp byte [esi], N_FLT
    je .float
    cmp ecx, F_EXP
    je .exp
    cmp ecx, F_LN
    je .ln
    cmp ecx, F_ABS
    je .abs
    cmp ecx, F_ATAN
    ja .keep
    call is_zero
    jz .nz
    cmp ecx, F_COS              ; f(0)
    je .one
    cmp ecx, F_ACOS
    je .halfpi
    jmp .zero
.nz:
    cmp ecx, F_ASIN
    jae .inv
    push eax
    push ecx
    call pi_multiple            ; sin, cos, tan of k pi
    pop ecx
    jc .pk
    add esp, 4
    jmp .out
.pk:
    pop eax
    jmp .keep
.inv:
    call is_one                 ; asin(1), acos(1), atan(1)
    jz .keep
    cmp ecx, F_ACOS
    je .zero
    mov eax, 1
    mov edx, 2
    cmp ecx, F_ASIN
    je .pik
    mov edx, 4
.pik:
    call mk_rat
    push eax
    mov bl, N_CON
    mov cl, C_PI
    call mk_leaf
    pop edx
    call mul2
    jmp .out
.halfpi:
    mov eax, 1
    mov edx, 2
    jmp .pik
.exp:
    call is_zero
    jnz .one
    cmp byte [esi], N_FN
    jne .keep
    cmp byte [esi+1], F_LN
    jne .keep
    mov eax, [esi+4]
    jmp .out
.ln:
    call is_one
    jnz .zero
    cmp byte [esi], N_CON
    jne .ln1
    cmp byte [esi+1], C_E
    je .one
.ln1:
    cmp byte [esi], N_FN
    jne .ln2
    cmp byte [esi+1], F_EXP
    jne .keep
    mov eax, [esi+4]
    jmp .out
.ln2:
    cmp byte [esi], N_NUM
    jne .keep
    cmp dword [esi+4], 0
    jle .undef
    jmp .keep
.abs:
    cmp byte [esi], N_NUM
    jne .keep
    cmp dword [esi+4], 0
    jge .out
    call neg
    jmp .out
.float:
    push ecx
    mov byte [nan], 0
    fld qword [esi+8]
    call fn_eval
    pop ecx
    cmp byte [nan], 0
    jne .undef0
    call mk_flt
    jmp .out
.undef0:
    fstp st0
    mov byte [nan], 0
.undef:
    mov eax, [n_undef]
    jmp .out
.zero:
    mov eax, [n_zero]
    jmp .out
.one:
    mov eax, [n_one]
    jmp .out
.keep:
    mov bl, cl
    call mk_fn
.out:
    mov [esp+28], eax
    popad
    ret

; esi = argument node, ecx = sin/cos/tan -> eax = the exact value at
; k pi (k a multiple of 1/6 or 1/4), or CF
pi_multiple:
    cmp byte [esi], N_CON       ; pi alone: k = 1
    jne .m
    cmp byte [esi+1], C_PI
    jne .no
    mov eax, 1
    mov edx, 1
    jmp .k
.m:
    cmp byte [esi], N_MUL       ; k * pi
    jne .no
    mov eax, [esi+8]
    NP eax, eax
    cmp byte [eax], N_CON
    jne .no
    cmp byte [eax+1], C_PI
    jne .no
    mov eax, [esi+4]
    NP eax, eax
    cmp byte [eax], N_NUM
    jne .no
    mov edx, [eax+8]
    mov eax, [eax+4]
.k:                             ; k = eax/edx: in twelfths of a turn
    imul eax, 12
    push ecx
    mov ecx, edx
    cdq
    idiv ecx
    pop ecx
    test edx, edx
    jnz .no
    cdq                         ; mod 24 (one turn = 2 pi)
    push ecx
    mov ecx, 24
    idiv ecx
    pop ecx
    test edx, edx
    jns .pos
    add edx, 24
.pos:
    cmp ecx, F_COS              ; cos(t) = sin(t + pi/2)
    jne .s
    add edx, 6
    cmp edx, 24
    jb .s
    sub edx, 24
.s:
    cmp ecx, F_TAN
    je .tan
    movsx eax, byte [sin12+edx] ; 2 sin, if a sixth or a half
    cmp eax, 9
    je .no
    mov edx, 2
    test eax, 1
    jnz .h
    sar eax, 1
    mov edx, 1
.h:
    jmp mk_rat
.tan:
    movsx eax, byte [tan12+edx]
    cmp eax, 9
    je .no
    jmp mk_int
.no:
    stc
    ret

; ---------- derivatives ----------
; eax (simplified) -> eax = d/dx, not simplified
diff:
    pushad
    call has_x
    jz .zero
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_VAR
    je .one
    cmp ebx, N_ADD
    je .add
    cmp ebx, N_MUL
    je .mul
    cmp ebx, N_POW
    je .pow
    cmp ebx, N_FN
    je .fn
.zero:
    mov eax, [n_zero]
    jmp .out
.one:
    mov eax, [n_one]
    jmp .out
.add:
    mov eax, [edi+4]
    call diff
    push eax
    mov eax, [edi+8]
    call diff
    pop edx
    mov bl, N_ADD
    call mk2
    jmp .out
.mul:                           ; a' b + a b'
    mov eax, [edi+4]
    call diff
    mov edx, [edi+8]
    mov bl, N_MUL
    call mk2
    push eax
    mov eax, [edi+8]
    call diff
    mov edx, eax
    mov eax, [edi+4]
    mov bl, N_MUL
    call mk2
    pop edx
    mov bl, N_ADD
    call mk2
    jmp .out
.pow:
    mov eax, [edi+8]
    call has_x
    jnz .general
    mov eax, [edi+8]            ; n u^(n-1) u'
    mov edx, [n_mone]
    mov bl, N_ADD
    call mk2
    mov edx, eax
    mov eax, [edi+4]
    mov bl, N_POW
    call mk2
    mov edx, [edi+8]
    mov bl, N_MUL
    call mk2
    push eax
    mov eax, [edi+4]
    call diff
    pop edx
    mov bl, N_MUL
    call mk2
    jmp .out
.general:                       ; u^v (v' ln u + v u'/u)
    mov eax, [edi+8]
    call diff
    push eax
    mov eax, [edi+4]
    push ebx
    mov bl, F_LN
    call mk_fn
    pop ebx
    pop edx
    mov bl, N_MUL
    call mk2
    push eax
    mov eax, [edi+4]
    call diff
    mov edx, [edi+8]
    mov bl, N_MUL
    call mk2
    push eax
    mov eax, [edi+4]
    mov edx, [n_mone]
    mov bl, N_POW
    call mk2
    pop edx
    mov bl, N_MUL
    call mk2
    pop edx
    mov bl, N_ADD
    call mk2
    mov edx, edi
    sub edx, [pool]
    shr edx, 4
    mov bl, N_MUL
    call mk2
    jmp .out
.fn:
    mov eax, [edi+4]            ; f'(u) u'
    call diff
    push eax
    movzx ecx, byte [edi+1]
    mov esi, [edi+4]            ; u
    call fn_deriv
    pop edx
    mov bl, N_MUL
    call mk2
.out:
    mov [esp+28], eax
    popad
    ret

; ecx = function, esi = u -> eax = f'(u)
fn_deriv:
    mov eax, esi
    cmp ecx, F_SIN
    je .sin
    cmp ecx, F_COS
    je .cos
    cmp ecx, F_TAN
    je .tan
    cmp ecx, F_EXP
    je .exp
    cmp ecx, F_LN
    je .ln
    cmp ecx, F_ABS
    je .abs
    cmp ecx, F_ASIN
    je .asin
    cmp ecx, F_ACOS
    je .acos
.atan:                          ; 1/(1 + u^2)
    mov edx, 2
    call .sq
    mov edx, [n_one]
    mov bl, N_ADD
    call mk2
    mov edx, [n_mone]
    jmp .pw
.sin:
    mov bl, F_COS
    jmp mk_fn
.cos:
    mov bl, F_SIN
    call mk_fn
    mov edx, [n_mone]
    mov bl, N_MUL
    jmp mk2
.tan:                           ; cos(u)^-2
    mov bl, F_COS
    call mk_fn
    push eax
    mov eax, -2
    call mk_int
    mov edx, eax
    pop eax
    mov bl, N_POW
    jmp mk2
.exp:
    mov bl, F_EXP
    jmp mk_fn
.ln:
    mov edx, [n_mone]
.pw:
    mov bl, N_POW
    jmp mk2
.abs:                           ; u / abs(u)
    push eax
    mov bl, F_ABS
    call mk_fn
    mov edx, [n_mone]
    mov bl, N_POW
    call mk2
    pop edx
    mov bl, N_MUL
    jmp mk2
.asin:                          ; (1 - u^2)^(-1/2)
    call .one_minus_sq
    jmp .rsqrt
.acos:
    call .one_minus_sq
    call .rsqrt
    mov edx, [n_mone]
    mov bl, N_MUL
    jmp mk2
.one_minus_sq:
    mov edx, 2
    call .sq
    mov edx, [n_mone]
    mov bl, N_MUL
    call mk2
    mov edx, [n_one]
    mov bl, N_ADD
    jmp mk2
.rsqrt:
    push eax
    mov eax, -1
    mov edx, 2
    call mk_rat
    mov edx, eax
    pop eax
    mov bl, N_POW
    jmp mk2
.sq:                            ; eax ^ edx (an integer)
    push eax
    mov eax, edx
    call mk_int
    mov edx, eax
    pop eax
    mov bl, N_POW
    jmp mk2

; ---------- expanding ----------
; eax -> eax = expanded and simplified
expand:
    call simp
    call exp_rec
    jmp simp
exp_rec:
    pushad
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_ADD
    je .add
    cmp ebx, N_MUL
    je .mul
    cmp ebx, N_POW
    je .pow
    cmp ebx, N_FN
    je .fn
    jmp .out
.add:
    mov eax, [edi+4]
    call exp_rec
    push eax
    mov eax, [edi+8]
    call exp_rec
    pop edx
    call add2
    jmp .out
.fn:
    mov eax, [edi+4]
    call exp_rec
    call simp
    movzx ecx, byte [edi+1]
    call fn_simp
    jmp .out
.mul:
    mov eax, [edi+4]
    call exp_rec
    push eax
    mov eax, [edi+8]
    call exp_rec
    pop edx
    call distribute
    jmp .out
.pow:
    mov eax, [edi+4]
    call exp_rec
    mov esi, eax
    mov eax, [edi+8]            ; a whole power 2..30 of a sum
    NP edx, eax
    cmp byte [edx], N_NUM
    jne .keep
    cmp dword [edx+8], 1
    jne .keep
    mov ecx, [edx+4]
    cmp ecx, 2
    jl .keep
    cmp ecx, 30
    jg .keep
    NP edx, esi
    cmp byte [edx], N_ADD
    jne .keep
    mov eax, esi
    dec ecx
.p:
    mov edx, esi
    call distribute
    loop .p
    jmp .out
.keep:
    mov edx, [edi+8]
    mov eax, esi
    call pow_simp
.out:
    mov [esp+28], eax
    popad
    ret

; eax, edx -> eax = their product, multiplied out (simplified)
distribute:
    pushad
    push dword [dsum]
    mov ebp, [ltop]
    call push_terms             ; a's terms
    mov esi, [ltop]
    mov eax, edx
    call push_terms             ; b's terms
    mov edi, [ltop]
    mov eax, [n_zero]
    mov [dsum], eax
    mov ebx, ebp
.i:
    cmp ebx, esi
    jae .d
    mov ecx, esi
.j:
    cmp ecx, edi
    jae .ni
    push ecx
    mov eax, [list]
    mov edx, [eax+ecx*4]
    mov eax, [eax+ebx*4]
    call mul2
    mov edx, [dsum]
    push ebx
    mov bl, N_ADD
    call mk2
    pop ebx
    mov [dsum], eax
    pop ecx
    inc ecx
    jmp .j
.ni:
    inc ebx
    jmp .i
.d:
    mov [ltop], ebp
    mov eax, [dsum]
    call add_simp
    pop dword [dsum]
    mov [esp+28], eax
    popad
    ret

; ---------- numbers ----------
; eax -> st0 = its value at x = xval (nan set if it has none)
numval:
    pushad
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_NUM
    je .num
    cmp ebx, N_FLT
    je .flt
    cmp ebx, N_CON
    je .con
    cmp ebx, N_VAR
    je .var
    cmp ebx, N_ADD
    je .add
    cmp ebx, N_MUL
    je .mul
    cmp ebx, N_POW
    je .pow
    cmp ebx, N_FN
    je .fn
.bad:
    mov byte [nan], 1
    fldz
    jmp .out
.num:
    fild dword [edi+4]
    fidiv dword [edi+8]
    jmp .out
.flt:
    fld qword [edi+8]
    jmp .out
.con:
    cmp byte [edi+1], C_PI
    jne .e
    fldpi
    jmp .out
.e:
    fld1
    call f_exp
    jmp .out
.var:
    cmp byte [edi+1], 'x'
    jne .bad
    fld qword [xval]
    jmp .out
.add:
    call .two
    faddp st1, st0
    jmp .out
.mul:
    call .two
    fmulp st1, st0
    jmp .out
.pow:
    call .two
    call fpow
    jmp .out
.fn:
    mov eax, [edi+4]
    call numval
    movzx ecx, byte [edi+1]
    call fn_eval
    jmp .out
.two:                           ; st1 = a, st0 = b (b computed with a saved)
    mov eax, [edi+4]
    call numval
    sub esp, 8
    fstp qword [esp]
    mov eax, [edi+8]
    call numval
    fld qword [esp]
    add esp, 8
    fxch
    ret
.out:
    popad
    ret

; st0 = u, ecx = function -> st0 = f(u) (nan set outside its domain)
fn_eval:
    cmp ecx, F_SIN
    je .sin
    cmp ecx, F_COS
    je .cos
    cmp ecx, F_TAN
    je .tan
    cmp ecx, F_EXP
    je f_exp
    cmp ecx, F_LN
    je .ln
    cmp ecx, F_ABS
    je .abs
    cmp ecx, F_ATAN
    je .atan
    fld st0                     ; asin, acos: |u| <= 1
    fabs
    fld1
    fcomip st0, st1
    fstp st0
    jb .bad
    fld st0                     ; sqrt(1 - u^2)
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    cmp ecx, F_ASIN
    jne .acos
    fpatan                      ; atan2(u, sqrt)
    ret
.acos:
    fxch
    fpatan                      ; atan2(sqrt, u)
    ret
.sin:
    fsin
    ret
.cos:
    fcos
    ret
.tan:
    fptan
    fstp st0
    ret
.ln:
    ftst
    fnstsw ax
    sahf
    jbe .bad
    fldln2
    fxch
    fyl2x
    ret
.abs:
    fabs
    ret
.atan:
    fld1
    fpatan
    ret
.bad:
    mov byte [nan], 1
    ret

; st0 -> e^st0
f_exp:
    fldl2e
    fmulp st1, st0
    jmp pow2_st
; st0 = y -> 2^y
pow2_st:
    fld st0
    frndint
    fsub st1, st0
    fxch
    f2xm1
    fld1
    faddp st1, st0
    fscale
    fstp st1
    ret

; st1 = base, st0 = power -> st0 = base^power (nan if not real)
fpow:
    fxch
    ftst
    fnstsw ax
    sahf
    je .zero
    ja .pos
    fld st1                     ; negative base: a whole power only
    frndint
    fcomp st2
    fnstsw ax
    sahf
    jne .bad
    fabs
    fyl2x
    call pow2_st
    fld st0                     ; odd: negative
    fstp qword [numv]
    sub esp, 8
    fstp qword [esp]
    fld st0
    fmul qword [f_half]
    fld st0
    frndint
    fcomip st0, st1
    fstp st0
    fstp st0
    fld qword [esp]
    add esp, 8
    je .r
    fchs
.r:
    ret
.pos:
    fyl2x
    jmp pow2_st
.zero:
    fstp st0
    ftst
    fnstsw ax
    sahf
    jbe .bad1
    fstp st0
    fldz
    ret
.bad:
    fstp st0
.bad1:
    mov byte [nan], 1
    ret

; ---------- printing ----------
; al -> output
emit_char:
    push edi
    mov edi, [outp]
    cmp edi, outbuf + OUT_MAX - 2
    jae .r
    mov [edi], al
    inc dword [outp]
.r:
    pop edi
    ret
; esi -> output
emit_str:
    push eax
    push esi
.c:
    lodsb
    test al, al
    jz .r
    call emit_char
    jmp .c
.r:
    pop esi
    pop eax
    ret
; numv -> output, as sci prints it
emit_full:
    pushad
    fld qword [numv]
    fstp qword [ev+GE_X]
    mov dword [ev+GE_EXPR], s_x
    mov dword [ev+GE_FLAGS], GEF_X
    mov dword [ev+GE_TEXT], nbuf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    mov esi, nbuf
    call emit_str
    popad
    ret
; eax -> output (signed decimal)
emit_int:
    pushad
    mov edi, nbuf
    call gui_itoa
    mov esi, nbuf
    call emit_str
    popad
    ret

print_top:
print_node:
    push ecx
    xor ecx, ecx
    call print
    pop ecx
    ret

; eax = node -> its level (2 sum, 3 negative, 4 product or quotient,
; 6 power, 8 atom)
level:
    push edi
    NP edi, eax
    movzx eax, byte [edi]
    cmp eax, N_ADD
    je .sum
    cmp eax, N_NUM
    je .num
    cmp eax, N_FLT
    je .flt
    cmp eax, N_MUL
    je .mul
    cmp eax, N_POW
    je .pow
    mov eax, 8
    jmp .r
.sum:
    mov eax, 2
    jmp .r
.num:
    mov eax, 3
    cmp dword [edi+4], 0
    jl .r
    mov eax, 4
    cmp dword [edi+8], 1
    jne .r
    mov eax, 8
    jmp .r
.flt:
    fld qword [edi+8]
    ftst
    fnstsw ax
    fstp st0
    sahf
    mov eax, 3
    jb .r
    mov eax, 8
    jmp .r
.mul:
    mov eax, edi
    sub eax, [pool]
    shr eax, 4
    call is_neg
    mov eax, 3
    jnz .r
    mov eax, 4
    jmp .r
.pow:
    mov eax, [edi+8]
    NP eax, eax
    cmp byte [eax], N_NUM
    jne .p6
    cmp dword [eax+4], 0
    jl .p4
    cmp dword [eax+4], 1        ; ^(1/2): sqrt( )
    jne .p6
    cmp dword [eax+8], 2
    jne .p6
    mov eax, 8
    jmp .r
.p4:
    mov eax, 4
    jmp .r
.p6:
    mov eax, 6
.r:
    pop edi
    ret

; eax -> ZF clear (jnz) if it prints with a leading minus
is_neg:
    push edi
    push eax
.l:
    NP edi, eax
    cmp byte [edi], N_MUL
    jne .leaf
    mov eax, [edi+4]
    jmp .l
.leaf:
    cmp byte [edi], N_NUM
    je .num
    cmp byte [edi], N_FLT
    jne .no
    fld qword [edi+8]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jb .yes
    jmp .no
.num:
    cmp dword [edi+4], 0
    jl .yes
.no:
    pop eax
    pop edi
    cmp eax, eax
    ret
.yes:
    pop eax
    pop edi
    or esp, esp
    ret

; eax = node, ecx = the context's level -> output, in brackets if its
; own level is lower
print:
    pushad
    push eax
    call level
    mov ebx, eax
    pop eax
    cmp ebx, ecx
    jae .bare
    push eax
    mov al, '('
    call emit_char
    pop eax
    call print_inner
    mov al, ')'
    call emit_char
    popad
    ret
.bare:
    call print_inner
    popad
    ret

print_inner:
    pushad
    NP edi, eax
    movzx ebx, byte [edi]
    cmp ebx, N_NUM
    je .num
    cmp ebx, N_FLT
    je .flt
    cmp ebx, N_CON
    je .con
    cmp ebx, N_VAR
    je .var
    cmp ebx, N_FN
    je .fn
    cmp ebx, N_POW
    je .pow
    cmp ebx, N_MUL
    je .mul
    cmp ebx, N_ADD
    je .add
    mov esi, s_undef
    call emit_str
    jmp .r
.num:
    mov eax, [edi+4]
    call emit_int
    cmp dword [edi+8], 1
    je .r
    mov al, '/'
    call emit_char
    mov eax, [edi+8]
    call emit_int
    jmp .r
.flt:
    fld qword [edi+8]
    fstp qword [numv]
    call emit_full
    jmp .r
.con:
    mov esi, s_pi
    cmp byte [edi+1], C_PI
    je .s
    mov esi, s_e
.s:
    call emit_str
    jmp .r
.var:
    mov al, [edi+1]
    call emit_char
    jmp .r
.fn:
    movzx ebx, byte [edi+1]
    mov esi, [fn_names+ebx*4]
    call emit_str
    mov al, '('
    call emit_char
    mov eax, [edi+4]
    xor ecx, ecx
    call print
    mov al, ')'
    call emit_char
    jmp .r
.pow:
    mov edx, [edi+8]
    NP esi, edx
    cmp byte [esi], N_NUM
    jne .pgen
    cmp dword [esi+4], 0
    jl .mul                     ; a negative power: as a quotient
    cmp dword [esi+4], 1
    jne .pgen
    cmp dword [esi+8], 2
    jne .pgen
    mov esi, s_sqrt
    call emit_str
    mov eax, [edi+4]
    xor ecx, ecx
    call print
    mov al, ')'
    call emit_char
    jmp .r
.pgen:
    mov eax, [edi+4]
    mov ecx, 7
    call print
    mov al, '^'
    call emit_char
    mov eax, edx
    mov ecx, 7
    call print
    jmp .r
.add:
    mov ebp, [ltop]
    call push_terms
    mov ebx, ebp
    mov ecx, [list]
    mov eax, [ecx+ebx*4]
    push ecx
    mov ecx, 2
    call print
    pop ecx
.at:
    inc ebx
    cmp ebx, [ltop]
    jae .ad
    mov eax, [ecx+ebx*4]
    call is_neg
    jnz .minus
    mov esi, s_plus
    call emit_str
    jmp .at1
.minus:
    mov esi, s_minus
    call emit_str
    call neg
.at1:
    push ecx
    mov ecx, 3
    call print
    pop ecx
    jmp .at
.ad:
    mov [ltop], ebp
    jmp .r
.mul:
    call print_product
.r:
    popad
    ret

; eax = a product (or a negative power) -> output: [-]numerator[/den]
print_product:
    pushad
    push dword [pnum0]          ; (a factor may print a product itself)
    push dword [pden0]
    push dword [pcoef]
    push dword [pq]
    mov ebp, [ltop]
    call push_factors
    mov [pnum0], ebp            ; numerator from ebp, then denominator
    mov eax, [n_one]
    mov [pcoef], eax
    mov esi, [list]
    mov eax, [esi+ebp*4]        ; a coefficient first?
    NP edi, eax
    cmp byte [edi], N_NUM
    je .c
    cmp byte [edi], N_FLT
    jne .nc
.c:
    mov [pcoef], eax
    mov dword [esi+ebp*4], 0
.nc:
    mov eax, [pcoef]            ; its sign
    call is_neg
    jz .pos
    mov al, '-'
    call emit_char
    mov eax, [pcoef]
    call neg
    mov [pcoef], eax
.pos:
    mov edi, [ltop]             ; the numerator's and denominator's lists
    mov [pden0], edi
    NP edx, [pcoef]             ; p and q
    mov dword [pq], 0
    cmp byte [edx], N_NUM
    jne .cf
    cmp dword [edx+8], 1
    je .cf
    mov eax, [edx+8]
    call mk_int
    mov [pq], eax
    mov eax, [edx+4]
    call mk_int
    mov [pcoef], eax
.cf:
    mov ebx, ebp                ; split
    mov ecx, [pden0]
.s:
    cmp ebx, ecx
    jae .sd
    mov esi, [list]
    mov eax, [esi+ebx*4]
    test eax, eax
    jz .sn
    NP edi, eax
    cmp byte [edi], N_POW
    jne .sn
    mov edx, [edi+8]
    NP edx, edx
    cmp byte [edx], N_NUM
    jne .sn
    cmp dword [edx+4], 0
    jge .sn
    mov eax, [edi+8]            ; to the denominator: base^-n
    call neg
    mov edx, eax
    mov eax, [edi+4]
    push ebx
    mov bl, N_POW
    call mk2_or_base
    pop ebx
    call lpush
    mov esi, [list]
    mov dword [esi+ebx*4], 0
.sn:
    inc ebx
    jmp .s
.sd:
    mov eax, [pq]               ; q into the denominator, first
    test eax, eax
    jz .num
    call lpush
    mov esi, [list]             ; (moved to the front of it)
    mov ecx, [ltop]
    dec ecx
.qf:
    cmp ecx, [pden0]
    jbe .num
    mov eax, [esi+ecx*4-4]
    xchg eax, [esi+ecx*4]
    mov [esi+ecx*4-4], eax
    dec ecx
    jmp .qf
.num:                           ; the numerator
    xor edx, edx                ; items printed
    mov eax, [pcoef]
    call is_one
    jnz .items
    mov ecx, 5
    call print
    inc edx
.items:
    mov ebx, ebp
.it:
    cmp ebx, [pden0]
    jae .itd
    mov esi, [list]
    mov eax, [esi+ebx*4]
    test eax, eax
    jz .itn
    test edx, edx
    jz .first
    push eax
    mov al, '*'
    call emit_char
    pop eax
.first:
    mov ecx, 5
    call print
    inc edx
.itn:
    inc ebx
    jmp .it
.itd:
    test edx, edx
    jnz .den
    mov al, '1'
    call emit_char
.den:
    mov ecx, [ltop]
    sub ecx, [pden0]
    jz .done
    mov al, '/'
    call emit_char
    cmp ecx, 1
    je .one
    mov al, '('
    call emit_char
.one:
    mov ebx, [pden0]
.dn:
    cmp ebx, [ltop]
    jae .dd
    cmp ebx, [pden0]
    je .d1
    mov al, '*'
    call emit_char
.d1:
    mov esi, [list]
    mov eax, [esi+ebx*4]
    push ecx
    mov ecx, 5
    cmp dword [esp], 1          ; one alone: a product needs brackets
    je .d2
    mov ecx, 5
.d2:
    call print
    pop ecx
    inc ebx
    jmp .dn
.dd:
    cmp ecx, 1
    je .done
    mov al, ')'
    call emit_char
.done:
    mov [ltop], ebp
    pop dword [pq]
    pop dword [pcoef]
    pop dword [pden0]
    pop dword [pnum0]
    popad
    ret

; eax = base, edx = power: base alone if the power is 1
mk2_or_base:
    xchg eax, edx
    call is_one
    xchg eax, edx
    jnz .base
    jmp mk2
.base:
    ret

; ---------- parsing ----------
; esi = text -> eax = the expression (not simplified)
parse_all:
    mov [pp], esi
    call p_expr
    mov esi, [pp]
    call skip_sp
    cmp byte [esi], 0
    jne p_bad
    ret
p_bad:
    mov esi, e_syntax
    jmp cas_error

p_expr:
    call p_term
.l:
    call p_peek2
    cmp dl, '+'
    je .plus
    cmp dl, '-'
    je .minus
    ret
.plus:
    inc dword [pp]
    push eax
    call p_term
    mov edx, eax
    pop eax
    jmp .add
.minus:
    inc dword [pp]
    push eax
    call p_term
    mov edx, [n_mone]
    xchg eax, edx
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    mov edx, eax
    pop eax
.add:
    push ebx
    mov bl, N_ADD
    call mk2
    pop ebx
    jmp .l

p_term:
    call p_unary
.l:
    call p_peek2
    cmp dl, '*'
    je .mul
    cmp dl, '/'
    je .div
    cmp dl, '('                 ; implicit: 2x, 3(x+1), x sin(x)
    je .imp
    push eax
    mov al, dl
    call is_letter
    pop eax
    je .imp
    ret
.mul:
    inc dword [pp]
.imp:
    push eax
    call p_unary
    mov edx, eax
    pop eax
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    jmp .l
.div:
    inc dword [pp]
    push eax
    call p_unary
    mov edx, [n_mone]
    push ebx
    mov bl, N_POW
    call mk2
    pop ebx
    mov edx, eax
    pop eax
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    jmp .l

p_unary:
    call p_peek
    cmp al, '-'
    je .neg
    cmp al, '+'
    jne p_power
    inc dword [pp]
    jmp p_unary
.neg:
    inc dword [pp]
    call p_unary
    mov edx, eax
    mov eax, [n_mone]
    push ebx
    mov bl, N_MUL
    call mk2
    pop ebx
    ret

p_power:
    call p_atom
    push eax
    call p_peek
    cmp al, '^'
    pop eax
    jne .r
    inc dword [pp]
    push eax
    call p_unary
    mov edx, eax
    pop eax
    push ebx
    mov bl, N_POW
    call mk2
    pop ebx
.r:
    ret

p_atom:
    call p_peek
    cmp al, '('
    je .br
    cmp al, '.'
    je .num
    cmp al, '0'
    jb .name
    cmp al, '9'
    jbe .num
.name:
    call is_letter
    jne p_bad
    mov esi, [pp]
    call name_len
    mov [pname], esi
    mov [plen], ecx
    add esi, ecx
    mov [pp], esi
    call skip_sp
    cmp byte [esi], '('
    je .func
    cmp ecx, 1
    je .var
    mov esi, [pname]            ; pi, e, ans
    cmp ecx, 2
    jne .n3
    cmp word [esi], 'pi'
    jne p_unknown
    mov cl, C_PI
    jmp .con
.n3:
    cmp ecx, 3
    jne p_unknown
    cmp word [esi], 'an'
    jne p_unknown
    cmp byte [esi+2], 's'
    jne p_unknown
    cmp byte [ans_buf], 0       ; the last answer, parsed
    je p_noans
    push dword [pp]
    mov esi, ans_buf
    call parse_all
    pop dword [pp]
    ret
.var:
    mov esi, [pname]
    mov cl, [esi]
    cmp cl, 'e'
    jne .v
    mov cl, C_E
.con:
    push ebx
    mov bl, N_CON
    call mk_leaf
    pop ebx
    ret
.v:
    push ebx
    mov bl, N_VAR
    call mk_leaf
    pop ebx
    ret
.func:
    inc esi                     ; past "("
    mov [pp], esi
    mov edi, fn_words
    xor ebx, ebx
.fw:
    cmp byte [edi], 0
    je p_unknown
    mov esi, [pname]
    mov ecx, [plen]
    push edi
    repe cmpsb
    pop edi
    jne .fn
    mov ecx, [plen]
    cmp byte [edi+ecx], 0
    je .ff
.fn:
    inc edi
    cmp byte [edi-1], 0
    jne .fn
    inc ebx
    jmp .fw
.ff:
    movzx ebx, byte [fn_ids+ebx]
    push ebx
    call p_expr
    call p_close
    pop ebx
    cmp ebx, 99                 ; sqrt: ^(1/2)
    je .sqrt
    jmp mk_fn
.sqrt:
    mov edx, [n_half]
    mov bl, N_POW
    jmp mk2
.br:
    inc dword [pp]
    call p_expr
    jmp p_close
.num:                           ; digits [. digits]: exact if it fits
    mov esi, [pp]
    xor eax, eax                ; value
    mov ecx, 1                  ; 10^decimals
    xor edx, edx                ; digits
    mov byte [pdot], 0
    fldz
.d:
    mov bl, [esi]
    cmp bl, '.'
    jne .dg
    cmp byte [pdot], 0
    jne .dd
    mov byte [pdot], 1
    inc esi
    jmp .d
.dg:
    sub bl, '0'
    cmp bl, 9
    ja .dd
    fimul dword [i_ten]
    movzx ebx, bl
    mov [tmpi], ebx
    fiadd dword [tmpi]
    cmp byte [pdot], 0
    je .nd
    cmp ecx, 100000000
    jae .nd2
    imul ecx, 10
    jmp .nd
.nd2:
    mov byte [pdot], 2          ; too many decimals: inexact
.nd:
    inc edx
    inc esi
    jmp .d
.dd:
    mov [pp], esi
    test edx, edx
    jz p_bad
    cmp edx, 9
    ja .inexact
    cmp byte [pdot], 2
    je .inexact
    fistp dword [tmpi]
    mov eax, [tmpi]
    mov edx, ecx
    jmp reduce_rat
.inexact:
    mov [tmpi], ecx
    fidiv dword [tmpi]
    jmp mk_flt

p_close:
    push eax
    call p_peek
    cmp al, ')'
    pop eax
    jne p_bad
    inc dword [pp]
    ret
p_unknown:
    mov esi, e_unknown
    jmp cas_error
p_noans:
    mov esi, e_noans
    jmp cas_error

; -> al = the next character after spaces (pp moved to it)
p_peek:
    push esi
    mov esi, [pp]
    call skip_sp
    mov [pp], esi
    mov al, [esi]
    pop esi
    ret
; -> dl = the same, eax kept
p_peek2:
    push eax
    call p_peek
    mov dl, al
    pop eax
    ret

; al -> ZF set if a letter
is_letter:
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
    or esp, esp
    pop eax
    ret

; esi -> esi at the first non-space
skip_sp:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip_sp
.r:
    ret

; esi -> ecx = the length of the name there (a letter, then letters and
; digits)
name_len:
    xor ecx, ecx
    mov al, [esi]
    call is_letter
    jne .r
.c:
    inc ecx
    mov al, [esi+ecx]
    call is_letter
    je .c
    cmp al, '0'
    jb .r
    cmp al, '9'
    jbe .c
.r:
    ret

; esi -> edi, edi ends on the zero
scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
    ret

; ---------- self-check ----------
selftest:
    mov esi, tests
    mov byte [bad], 'a'
    mov dword [rptr], rbuf
    mov byte [rbuf], 0
.t:
    cmp byte [esi], 0
    je .end
    push esi
    call run_command
    pop esi
.skip:
    lodsb
    test al, al
    jnz .skip
    mov edi, outbuf             ; the answer as expected?
    push esi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .fail
    inc esi
    inc edi
    test al, al
    jnz .c
    pop esi
    jmp .next
.fail:
    pop esi
    mov edi, [rptr]             ; the letter and what came out
    cmp edi, rbuf + RBUF - COLS - 8
    jae .next
    mov al, [bad]
    stosb
    mov al, ' '
    stosb
    push esi
    mov esi, outbuf
    call scopy
    pop esi
    mov al, 10
    stosb
    mov byte [edi], 0
    mov [rptr], edi
.next:
    lodsb                       ; past the expected answer
    test al, al
    jnz .next
    inc byte [bad]
    jmp .t
.end:
    call gui_close
    cmp byte [rbuf], 0
    jne .failed
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.failed:
    mov esi, fail
    call gui_puts
    mov esi, nl
    call gui_puts
    mov esi, rbuf
    call gui_puts
    mov eax, 1
    ret

; ---------- data ----------
title db 'CAS', 0
s_x db 'x', 0
s_keys db 'Enter: run  Up/Down: earlier  PgUp/PgDn  Esc: quit', 0
m_hello db 'Type an expression, or a command:', 0
m_hello2 db 'simplify expand factor solve diff integrate', 0
m_hello3 db 'int limit series     (ans: the last answer)', 0
        db 0
s_error db 'Error: ', 0
s_approx db '  ~ ', 0
s_tilde db '~ ', 0
s_plusc db ' + C', 0
s_comma db ', ', 0
s_xeq db 'x = ', 0
s_xapprox db 'x ~ ', 0
s_inf db 'inf', 0
s_minf db '-inf', 0
s_plus db ' + ', 0
s_minus db ' - ', 0
s_pi db 'pi', 0
s_e db 'e', 0
s_sqrt db 'sqrt(', 0
s_undef db 'undefined', 0
m_always db 'true for every x', 0
m_never db 'no solution', 0
m_noreal db 'no real solutions', 0
m_nonefound db 'no solutions found from -100 to 100', 0
m_nolimit db 'no limit (or not found)', 0
m_noint db 'no antiderivative found; int(f, a, b) gives a number', 0
e_syntax db 'syntax', 0
e_unknown db 'unknown name or function', 0
e_noans db 'no answer yet for ans', 0
e_args db 'wrong number of arguments', 0
e_count db 'the count must be a whole number 0 to 12', 0
e_const db 'that must be a number', 0
e_notpoly db 'factor needs a polynomial in x', 0
e_big db 'too large', 0
e_undefat db 'not defined there', 0
e_numint db 'the integral has no value there', 0
m_nogfx db 'cas: no graphics', 10, 0
pass db 'cas: PASS', 10, 0
fail db 'cas: FAIL ', 0
bad db '?', ' ', 0
nl db 10, 0
cmd_words db 'simplify', 0, 'expand', 0, 'factor', 0, 'solve', 0, 'diff', 0
          db 'integrate', 0, 'int', 0, 'limit', 0, 'series', 0, 0
cmd_tab dd cmd_simplify, cmd_expand, cmd_factor, cmd_solve, cmd_diff
        dd cmd_integrate, cmd_integrate, cmd_limit, cmd_series
fn_words db 'sin', 0, 'cos', 0, 'tan', 0, 'exp', 0, 'ln', 0, 'log', 0
         db 'abs', 0, 'asin', 0, 'acos', 0, 'atan', 0, 'sqrt', 0, 0
fn_ids db F_SIN, F_COS, F_TAN, F_EXP, F_LN, F_LN, F_ABS, F_ASIN, F_ACOS
       db F_ATAN, 99
fn_names dd 0, n_sin, n_cos, n_tan, n_exp, n_ln, n_abs, n_asin, n_acos
         dd n_atan
n_sin db 'sin', 0
n_cos db 'cos', 0
n_tan db 'tan', 0
n_exp db 'exp', 0
n_ln db 'ln', 0
n_abs db 'abs', 0
n_asin db 'asin', 0
n_acos db 'acos', 0
n_atan db 'atan', 0
; 2 sin(k pi / 12) where it is 0, +-1 or +-2 (9: not exact)
sin12 db 0, 9, 1, 9, 9, 9, 2, 9, 9, 9, 1, 9
      db 0, 9, -1, 9, 9, 9, -2, 9, 9, 9, -1, 9
tan12 db 0, 9, 9, 1, 9, 9, 9, 9, 9, -1, 9, 9
      db 0, 9, 9, 1, 9, 9, 9, 9, 9, -1, 9, 9
; the self-check: an input, then the answer expected
tests:
    db 'simplify(x + x + 2*x*3)', 0, '8*x', 0
    db '2/4 + 1/3', 0, '5/6', 0
    db 'sqrt(12)', 0, '2*sqrt(3)  ~ 3.464101615', 0
    db 'x*x^2', 0, 'x^3', 0
    db '(x^2)^3', 0, 'x^6', 0
    db 'sin(pi/6)', 0, '1/2', 0
    db 'cos(pi)', 0, '-1', 0
    db 'tan(pi/4)', 0, '1', 0
    db 'asin(1)', 0, 'pi/2  ~ 1.570796327', 0
    db 'ln(e)', 0, '1', 0
    db 'exp(ln(x))', 0, 'x', 0
    db '(x+1)/(x+1)', 0, '1', 0
    db '1/0', 0, 'undefined', 0
    db '0.5 + 1/2', 0, '1', 0
    db '1.25', 0, '5/4', 0
    db 'x^2 + 3*x - x^2', 0, '3*x', 0
    db 'expand((x+2)^3)', 0, 'x^3 + 6*x^2 + 12*x + 8', 0
    db 'expand((a+b)^2)', 0, 'a^2 + b^2 + 2*a*b', 0
    db 'expand(3*(x+1) - 3*x)', 0, '3', 0
    db 'factor(x^2 + 5*x + 6)', 0, '(x + 3)*(x + 2)', 0
    db 'factor(2*x^2 - 8)', 0, '2*(x + 2)*(x - 2)', 0
    db 'factor(x^3 - 6*x^2 + 11*x - 6)', 0, '(x - 1)*(x - 2)*(x - 3)', 0
    db 'factor(x^4 - 1)', 0, '(x + 1)*(x - 1)*(x^2 + 1)', 0
    db 'solve(x^2 - 4 = 0)', 0, 'x = -2, x = 2', 0
    db 'solve(2*x + 3 = 7)', 0, 'x = 2', 0
    db 'solve(x^2 + x - 1 = 0)', 0, 'x = -1/2 - sqrt(5)/2, x = -1/2 + sqrt(5)/2', 0
    db 'solve(x^2 + 1 = 0)', 0, 'x = -i, x = i', 0
    db 'solve(x^3 - x = 0)', 0, 'x = -1, x = 0, x = 1', 0
    db 'solve(cos(x) = x)', 0, 'x ~ 0.7390851332', 0
    db 'solve(exp(x) = 2)', 0, 'x ~ 0.6931471806', 0
    db 'diff(sin(x)*x)', 0, 'x*cos(x) + sin(x)', 0
    db 'diff(exp(2*x))', 0, '2*exp(2*x)', 0
    db 'diff(sqrt(x))', 0, '1/(2*sqrt(x))', 0
    db 'diff(x^x)', 0, 'x^x*(ln(x) + 1)', 0
    db 'diff(x^4, 2)', 0, '12*x^2', 0
    db 'integrate(3*x^2 + 2*x + 1)', 0, 'x^3 + x^2 + x + C', 0
    db 'integrate(exp(3*x))', 0, 'exp(3*x)/3 + C', 0
    db 'integrate(1/x)', 0, 'ln(abs(x)) + C', 0
    db 'integrate(sin(2*x))', 0, '-cos(2*x)/2 + C', 0
    db 'integrate(x*exp(x))', 0, 'no antiderivative found; int(f, a, b) gives a number', 0
    db 'int(x^2, 0, 3)', 0, '9', 0
    db 'int(sin(x), 0, pi)', 0, '2', 0
    db 'int(exp(-x^2), 0, 1)', 0, '~ 0.7468241328', 0
    db 'limit(sin(x)/x, 0)', 0, '1', 0
    db 'limit((x^2-1)/(x-1), 1)', 0, '2', 0
    db 'limit((2*x^2+1)/(x^2+3), inf)', 0, '2', 0
    db 'series(exp(x), 0, 4)', 0, '1 + x + x^2/2 + x^3/6 + x^4/24', 0
    db 'series(sin(x), 0, 5)', 0, 'x - x^3/6 + x^5/120', 0
    db 'series(1/(1-x), 0, 4)', 0, '1 + x + x^2 + x^3 + x^4', 0
    db 'foo(x)', 0, 'Error: unknown name or function', 0
    db '2 +', 0, 'Error: syntax', 0
    db 0
i_ten dd 10
i_steps dd 4000
i_simp dd 1000
align 8
f_half dq 0.5
f_3 dq 3.0
f_10 dq 10.0
f_100 dq 100.0
f_m100 dq -100.0
f_2p31 dq 2147483647.0
f_maxdiv dq 1000000000.0
f_same dq 1.0e-6
f_small dq 1.0e-6
f_h dq 1.0e-7
f_h2 dq 1.0e-5
f_large dq 1.0e7
f_agree dq 1.0e-4
f_recon dq 1.0e-9
f_1e6 dq 1.0e6

SQX_BSS
GUI_BSS
alignb 8
numv resq 1
xval resq 1
lo resq 1
hi resq 1
step resq 1
xa resq 1
xb resq 1
xm resq 1
fa resq 1
fb_ resq 1
fm resq 1
lastroot resq 1
aval resq 1
lval resq 1
rval resq 1
lval2 resq 1
rval2 resq 1
ssum resq 1
lcmv resq 1
gv resq 1
arg resd 1
pool resd 1
list resd 1
fb resd 1
fe resd 1
nfree resd 1
ltop resd 1
ftop resd 1
err_sp resd 1
err_save resd 1
outp resd 1
pp resd 1
pname resd 1
plen resd 1
tmpi resd 1
an resd 1
ad resd 1
bn resd 1
bd resd 1
rn resd 1
xn resd 1
xd resd 1
rd resd 1
rn_ resd 1
rd_ resd 1
vn resd 1
vd resd 1
qn resd 1
qd resd 1
pbn resd 1
pbd resd 1
n_zero resd 1
n_one resd 1
n_mone resd 1
n_half resd 1
n_x resd 1
n_undef resd 1
args resd 3
nargs resd 1
cmd_start resd 1
fnode resd 1
gnode resd 1
anode resd 1
pnode resd 1
snode resd 1
sign resd 1
fact resd 1
sum resd 1
nsol resd 1
nroots resd 1
root_n resd 32
root_d resd 32
root_m resd 32
lc_n resd 1
lc_d resd 1
end0 resd 1
endn resd 1
ndiv0 resd 1
ndivn resd 1
divs0 resd 64
divsn resd 64
kc resd 1
prod resd 1
polyp resd 1
ptree resd 1
qa_ resd 1
qb_ resd 1
qc_ resd 1
qd_ resd 1
q2a resd 1
qm resd 1
qs resd 1
lnum resd 1
lden resd 1
vnum resd 1
vden resd 1
ifn resd 1
isum resd 1
ic resd 1
irest resd 1
ia resd 1
in1 resd 1
sub_val resd 1
sc_coef resd 1
sc_term resd 1
rptr resd 1
rbuf resb RBUF
pw_acc resd 1
rootn resd 1
rootd resd 1
sqm resd 1
sqk resd 1
sqr resd 1
dsum resd 1
pcoef resd 1
pq resd 1
pnum0 resd 1
pden0 resd 1
nlines resd 1
scroll resd 1
ilen resd 1
nin resd 1
hpick resd 1
ev resb GE_SIZE
nan resb 1
asc resb 1
again resb 1
hasden resb 1
pm_swap resb 1
pdot resb 1
set_ans resb 1
alignb 4
polyA resb POLY_SZ
polyB resb POLY_SZ
nbuf resb 40
line resb 160
ibuf resb IMAX + 4
argbuf resb 3 * (IMAX + 4)
outbuf resb OUT_MAX
ansout resb OUT_MAX
ans_buf resb OUT_MAX
inhist resb NHIST_IN * (IMAX + 4)
hist resb HIST * (COLS + 2)
SQX_END
