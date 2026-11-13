; Squirrel-OS/2 — sqmath, the expression engine v2 (C.1, OS2-APPS).
; Original code. Real and complex numbers, long decimals, units,
; variables and user functions, for any program to include. See
; documentation/apps/sqmath.md.
;
;   2 + 3i          (1+2i)/(3-4i)        sqrt(-4)       e^(i*pi)
;   3 [km] + 200 [m]     9.8 [m/s^2] * 70 [kg]     a to [km/h]
;   a = 5           f(x) = x^2 + 1       f(a)           ans
;   digits 50       (decimals with 50 places; digits 0: back to doubles)
;   30!             2^100                abs re im conj arg sqrt exp ln
;   log sin cos tan asin acos atan floor ceil round
;
; Host interface:
;   sqm_init      once: memory (CF if there is none)
;   sqm_reset     forget every variable and function; doubles again
;   sqm_line      esi = a line -> CF on an error (sqm_err = message), or
;                 sqm_out = what to show and sqm_kind: SK_VALUE (sqm_out
;                 is the value), SK_SET (a = value), SK_DEF, SK_DIGITS,
;                 SK_NONE (an empty line or a comment)
;   [sqm_get]     0, or a routine: esi = a name (ecx = its length) ->
;                 st0, or CF. Asked for a name sqmath does not know.
;   [sqm_set]     0, or a routine: esi, ecx = a name, st0 (popped) =
;                 a real value just given to it
; A value is 128 bytes on the engine's value stack: a type (real, complex,
; decimal), the powers of the seven SI base units, the real and
; imaginary parts (doubles), and a decimal's sign and magnitude (24
; dwords, a binary integer that is the value times 10^F).

SQ_BL       equ 24                  ; a decimal's dwords
SQ_VSIZE    equ 128
SQ_VSN      equ 64                  ; the value stack
SQ_NV       equ 48                  ; variables
SQ_VREC     equ 16 + SQ_VSIZE       ; name, value
SQ_NF       equ 16                  ; user functions
SQ_FREC     equ 256                 ; name 16, 4 parameters of 16, count, body
SQ_FNP      equ 16
SQ_FNN      equ 80
SQ_FBODY    equ 84
SQ_BODYMAX  equ SQ_FREC - SQ_FBODY - 1
SQ_DEPTH    equ 16
SQ_TMP      equ 2 * SQ_BL + 4       ; a temporary: dwords
SQ_DIGMAX   equ 150

V_T         equ 0                   ; a value
V_DIM       equ 1                   ; 7 signed bytes: m kg s A K mol cd
V_RE        equ 8
V_IM        equ 16
V_BS        equ 24
V_BM        equ 28
ST_R        equ 0
ST_C        equ 1
ST_D        equ 2

SK_VALUE    equ 0
SK_SET      equ 1
SK_DEF      equ 2
SK_DIGITS   equ 3
SK_NONE     equ 4

sqm_init:
    mov eax, SYS_SBRK
    mov ebx, SQ_VSN * SQ_VSIZE + SQ_NV * SQ_VREC + SQ_NF * SQ_FREC + 8 * SQ_TMP * 4
    int 0x80
    cmp eax, -1
    je .no
    mov [sq_vs], eax
    add eax, SQ_VSN * SQ_VSIZE
    mov [sq_vars], eax
    add eax, SQ_NV * SQ_VREC
    mov [sq_fns], eax
    add eax, SQ_NF * SQ_FREC
    mov ecx, 8
    mov edi, sq_t
.t:
    stosd
    add eax, SQ_TMP * 4
    loop .t
    call sqm_reset
    clc
    ret
.no:
    stc
    ret

sqm_reset:
    mov dword [sq_nv], 0
    mov dword [sq_nf], 0
    mov dword [sq_digits], 0
    ret

; ---------- a line ----------
sqm_line:
    pushad
    mov [sq_sp], esp
    mov [sq_pos], esi
    mov [sq_line0], esi
    mov dword [sq_vn], 0
    mov dword [sq_depth], 0
    mov dword [sqm_kind], SK_NONE
    mov byte [sqm_out], 0
    mov dword [sq_op], sqm_out
    fninit
    call sq_peek
    test al, al
    jz .ok
    cmp al, '#'
    je .ok
    call sq_name
    test eax, eax
    jz .expr
    mov esi, sq_nm
    mov edi, sw_digits
    call sq_streq
    je .digits
    call sq_peek
    cmp al, '('
    je .def
    cmp al, '='
    jne .expr
    mov esi, [sq_pos]
    cmp byte [esi+1], '='
    je .expr
    call sq_take                ; name = value
    mov esi, sq_nm
    mov edi, sq_lhs
    call sq_scopy
    call sq_expr
    call sq_isto
    je .setto
    call sq_end
    call sq_top
    call sq_finite
    call sq_keepvar
    mov esi, sq_lhs
    call sq_puts
    mov esi, sw_eq
    call sq_puts
    call sq_vtext
    mov dword [sqm_kind], SK_SET
    jmp .ok
.setto:                         ; a = value to [unit]: kept in SI, shown
    call sq_unitval             ; in the unit
    call sq_2
    call sq_dimeq
    jne sq_e_units
    call sq_end
    call sq_drop                ; the value, then the unit again
    call sq_top
    call sq_finite
    call sq_keepvar
    inc dword [sq_vn]
    mov esi, sq_lhs
    call sq_puts
    mov esi, sw_eq
    call sq_puts
    call sq_showto
    mov dword [sqm_kind], SK_SET
    jmp .ok
.def:
    call sq_tryfn
    jnc .defd
.expr:
    mov eax, [sq_line0]
    mov [sq_pos], eax
    call sq_expr
    call sq_isto
    jne .plain
    call sq_unitval             ; a value to [unit]
    call sq_2
    call sq_dimeq
    jne sq_e_units
    call sq_end
    call sq_showto
    mov dword [sqm_kind], SK_VALUE
    jmp .ok
.plain:
    call sq_end
    call sq_top
    call sq_finite
    mov dword [sq_lhs], 'ans'
    call sq_keepvar
    call sq_vtext
    mov dword [sqm_kind], SK_VALUE
    jmp .ok
.digits:                        ; digits n
    call sq_peek
    cmp al, '0'
    jb sq_e_digits
    cmp al, '9'
    ja sq_e_digits
    xor ebx, ebx
.dn:
    call sq_peek
    cmp al, '0'
    jb .dd
    cmp al, '9'
    ja .dd
    call sq_take
    imul ebx, 10
    sub al, '0'
    movzx eax, al
    add ebx, eax
    cmp ebx, 1000
    ja sq_e_digits
    jmp .dn
.dd:
    call sq_end
    cmp ebx, SQ_DIGMAX
    ja sq_e_digits
    mov eax, ebx
    call sq_setdigits
    mov esi, sw_digs
    call sq_puts
    mov eax, [sq_digits]
    test eax, eax
    jz .off
    mov edi, sq_nb
    call gui_utoa
    mov esi, sq_nb
    call sq_puts
    jmp .dk
.off:
    mov esi, sw_off
    call sq_puts
.dk:
    mov dword [sqm_kind], SK_DIGITS
    jmp .ok
.defd:
    mov dword [sqm_kind], SK_DEF
.ok:
    popad
    clc
    ret

; a value, then a unit with its powers, on top -> the value in that
; unit shown, with the unit as written
sq_showto:
    call sq_2
    call v_div
    call sq_drop
    call sq_top
    call sq_finite
    mov byte [edi+V_DIM], 0
    mov dword [edi+V_DIM+1], 0
    mov word [edi+V_DIM+5], 0
    call sq_vtext
    mov esi, sw_sp
    call sq_puts
    mov esi, sq_ubuf
    jmp sq_puts

; esi = an error message: the line stops
sq_fail:
    mov [sqm_err], esi
    mov esp, [sq_sp]
    fninit
    popad
    stc
    ret
sq_e_syntax:
    mov esi, se_syntax
    jmp sq_fail
sq_e_units:
    mov esi, se_units
    jmp sq_fail
sq_e_digits:
    mov esi, se_digits
    jmp sq_fail
sq_e_div0:
    mov esi, se_div0
    jmp sq_fail
sq_e_domain:
    mov esi, se_domain
    jmp sq_fail
sq_e_big:
    mov esi, se_big
    jmp sq_fail
sq_e_plain:
    mov esi, se_plain
    jmp sq_fail
sq_e_cplx:
    mov esi, se_cplx
    jmp sq_fail

; nothing more on the line (a # comment may follow)
sq_end:
    call sq_peek
    test al, al
    jz .r
    cmp al, '#'
    jne sq_e_syntax
.r:
    ret

; -> ZF if "to" comes next (taken)
sq_isto:
    call sq_peek
    mov esi, [sq_pos]
    cmp word [esi], 'to'
    jne .r
    mov al, [esi+2]
    call sq_wordc
    je .no
    add dword [sq_pos], 2
    cmp al, al
    ret
.no:
    test esp, esp
.r:
    ret

; f(a, b) = body -> the function kept, or CF (not a definition: the
; position is left for the caller to start again)
sq_tryfn:
    mov esi, sq_nm
    mov edi, sq_lhs
    call sq_scopy
    call sq_take                ; (
    xor ebx, ebx                ; parameters
.p:
    push ebx
    call sq_name
    pop ebx
    test eax, eax
    jz .no
    cmp ebx, 4
    jae .no
    mov esi, sq_nm
    mov edi, ebx
    shl edi, 4
    add edi, sq_par
    call sq_scopy
    inc ebx
    call sq_peek
    cmp al, ','
    jne .cl
    call sq_take
    jmp .p
.cl:
    cmp al, ')'
    jne .no
    call sq_take
    call sq_peek
    cmp al, '='
    jne .no
    call sq_take
    call sq_peek
    test al, al
    jz sq_e_syntax
    mov esi, sq_lhs             ; find it, or a new one
    call sq_findfn
    jnc .have
    mov eax, [sq_nf]
    cmp eax, SQ_NF
    jae .full
    inc dword [sq_nf]
    imul edi, eax, SQ_FREC
    add edi, [sq_fns]
.have:
    push edi
    mov esi, sq_lhs
    call sq_scopy
    pop edi
    mov [edi+SQ_FNN], ebx
    push edi
    lea edi, [edi+SQ_FNP]
    mov esi, sq_par
    mov ecx, 64 / 4
    rep movsd
    pop edi
    mov esi, [sq_pos]           ; the body, as text
    push edi
    lea edi, [edi+SQ_FBODY]
    mov ecx, SQ_BODYMAX
.b:
    lodsb
    stosb
    test al, al
    jz .bd
    loop .b
    mov esi, se_long
    jmp sq_fail
.bd:
    pop edi
    mov esi, [sq_line0]         ; shown as written
    call sq_puts
    clc
    ret
.no:
    stc
    ret
.full:
    mov esi, se_fns
    jmp sq_fail

; esi = a name -> edi = its function, or CF
sq_findfn:
    push eax
    xor eax, eax
.f:
    cmp eax, [sq_nf]
    jae .no
    imul edi, eax, SQ_FREC
    add edi, [sq_fns]
    call sq_streq
    je .yes
    inc eax
    jmp .f
.yes:
    pop eax
    clc
    ret
.no:
    pop eax
    stc
    ret

; the value on top -> the variable sq_lhs (and the host's, if real)
sq_keepvar:
    pushad
    mov esi, sq_lhs
    xor eax, eax
.f:
    cmp eax, [sq_nv]
    jae .new
    imul edi, eax, SQ_VREC
    add edi, [sq_vars]
    call sq_streq
    je .set
    inc eax
    jmp .f
.new:
    cmp eax, SQ_NV
    jae .full
    inc dword [sq_nv]
    imul edi, eax, SQ_VREC
    add edi, [sq_vars]
    push edi
    call sq_scopy
    pop edi
.set:
    add edi, 16
    push edi
    call sq_top
    mov esi, edi
    pop edi
    mov ecx, SQ_VSIZE / 4
    rep movsd
    mov eax, [sqm_set]
    test eax, eax
    jz .r
    call sq_top
    cmp byte [edi], ST_C
    je .r
    call sq_real                ; -> st0
    mov esi, sq_lhs
    call sq_slen
    mov ecx, eax
    call [sqm_set]
.r:
    popad
    ret
.full:
    mov esi, se_vars
    jmp sq_fail

; ---------- scanning ----------
sq_peek:
    push esi
    mov esi, [sq_pos]
.l:
    mov al, [esi]
    cmp al, ' '
    je .n
    cmp al, 9
    jne .r
.n:
    inc esi
    jmp .l
.r:
    mov [sq_pos], esi
    pop esi
    ret
sq_take:
    inc dword [sq_pos]
    ret
; dl = a character: it must come next
sq_want:
    call sq_peek
    cmp al, dl
    jne .no
    jmp sq_take
.no:
    mov esi, se_rp
    cmp dl, ')'
    je .e
    mov esi, se_rb
.e:
    jmp sq_fail

; al -> ZF for a letter, a digit or _
sq_wordc:
    cmp al, '0'
    jb .l
    cmp al, '9'
    jbe .y
.l:
    cmp al, '_'
    je .y
    push eax
    or al, 0x20
    cmp al, 'a'
    jb .n
    cmp al, 'z'
    ja .n
    pop eax
    cmp al, al
    ret
.n:
    pop eax
    test esp, esp
    ret
.y:
    cmp al, al
    ret

; a name (it starts with a letter) -> sq_nm, eax = its length (0: none)
sq_name:
    call sq_peek
    cmp al, '0'
    jb .s
    cmp al, '9'
    jbe .none
.s:
    call sq_wordc
    jne .none
    push esi
    push ecx
    mov esi, [sq_pos]
    xor ecx, ecx
.c:
    mov al, [esi]
    call sq_wordc
    jne .e
    inc esi
    cmp ecx, 15
    jae .c
    mov [sq_nm+ecx], al
    inc ecx
    jmp .c
.e:
    mov byte [sq_nm+ecx], 0
    mov [sq_pos], esi
    mov eax, ecx
    pop ecx
    pop esi
    ret
.none:
    xor eax, eax
    ret

; esi, edi = names -> ZF if the same
sq_streq:
    push eax
    push esi
    push edi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .r
    inc esi
    inc edi
    test al, al
    jnz .c
.r:
    pop edi
    pop esi
    pop eax
    ret
sq_scopy:
    push eax
.c:
    lodsb
    stosb
    test al, al
    jnz .c
    pop eax
    ret
sq_slen:
    xor eax, eax
.c:
    cmp byte [esi+eax], 0
    je .r
    inc eax
    jmp .c
.r:
    ret

; esi -> appended to sqm_out
sq_puts:
    push eax
    push esi
    push edi
    mov edi, [sq_op]
.c:
    lodsb
    test al, al
    jz .r
    cmp edi, sqm_out + 300
    jae .c
    stosb
    jmp .c
.r:
    mov byte [edi], 0
    mov [sq_op], edi
    pop edi
    pop esi
    pop eax
    ret

; ---------- the value stack ----------
; -> edi = a new value on top, zero (a real 0 with no unit)
sq_push:
    mov edi, [sq_vn]
    cmp edi, SQ_VSN
    jae .deep
    inc dword [sq_vn]
    imul edi, SQ_VSIZE
    add edi, [sq_vs]
    push eax
    push ecx
    push edi
    xor eax, eax
    mov ecx, SQ_VSIZE / 4
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret
.deep:
    mov esi, se_deep
    jmp sq_fail
sq_top:
    mov edi, [sq_vn]
    dec edi
    imul edi, SQ_VSIZE
    add edi, [sq_vs]
    ret
; -> edi = the value under the top, esi = the top
sq_2:
    call sq_top
    mov esi, edi
    sub edi, SQ_VSIZE
    ret
sq_drop:
    dec dword [sq_vn]
    ret

; ---------- the grammar ----------
sq_expr:
    call sq_term
.l:
    call sq_peek
    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    ret
.add:
    call sq_take
    call sq_term
    call sq_2
    call v_add
    call sq_drop
    jmp .l
.sub:
    call sq_take
    call sq_term
    call sq_2
    call v_neg2
    call v_add
    call sq_drop
    jmp .l

sq_term:
    call sq_unary
.l:
    call sq_peek
    cmp al, '*'
    je .mul
    cmp al, '/'
    je .div
    cmp al, '('
    je .imp
    cmp al, '.'
    je .imp
    cmp al, '0'                 ; 2 3 is not 6
    jb .w
    cmp al, '9'
    jbe .r
.w:
    call sq_wordc               ; 2pi, 3x, 2i: an unwritten *
    jne .r
    mov esi, [sq_pos]
    cmp word [esi], 'to'
    jne .imp
    mov al, [esi+2]
    call sq_wordc
    jne .r
.imp:
    call sq_unary
    jmp .m
.mul:
    call sq_take
    call sq_unary
.m:
    call sq_2
    call v_mul
    call sq_drop
    jmp .l
.div:
    call sq_take
    call sq_unary
    call sq_2
    call v_div
    call sq_drop
    jmp .l
.r:
    ret

sq_unary:
    call sq_peek
    cmp al, '-'
    je .neg
    cmp al, '+'
    je .pos
    jmp sq_power
.neg:
    call sq_take
    call sq_unary
    call sq_top
    jmp v_neg
.pos:
    call sq_take
    jmp sq_unary

sq_power:
    call sq_postfix
    call sq_peek
    cmp al, '^'
    jne .r
    call sq_take
    call sq_unary
    call sq_2
    call v_pow
    call sq_drop
.r:
    ret

sq_postfix:                     ; n!, and a unit: 2 [s] binds first
    call sq_primary
.l:
    call sq_peek
    cmp al, '['
    je .unit
    cmp al, '!'
    jne .r
    call sq_take
    call sq_top
    call v_fact
    jmp .l
.unit:
    call sq_unitval
    call sq_2
    call v_mul
    call sq_drop
    jmp .l
.r:
    ret

sq_primary:
    call sq_peek
    cmp al, '('
    je .paren
    cmp al, '['
    je sq_unitval
    cmp al, '.'
    je sq_number
    cmp al, '0'
    jb .name
    cmp al, '9'
    jbe sq_number
.name:
    call sq_name
    test eax, eax
    jz sq_e_syntax
    call sq_peek
    cmp al, '('
    je .call
    jmp sq_lookup
.paren:
    call sq_take
    call sq_expr
    mov dl, ')'
    jmp sq_want
.call:
    mov esi, sq_nm
    mov edi, sq_fnames
    call sq_index
    jnc .builtin
    call sq_findfn
    jc .nofn
    jmp sq_call
.nofn:
    mov esi, se_nofn
    jmp sq_fail
.builtin:
    push eax
    call sq_take
    call sq_expr
    mov dl, ')'
    call sq_want
    call sq_top
    pop eax
    jmp [sq_fcode+eax*4]

; esi = a word, edi = a list (zero-ended words, then 0) -> eax = its
; place, or CF
sq_index:
    push edi
    xor eax, eax
.w:
    cmp byte [edi], 0
    je .no
    call sq_streq
    je .yes
.n:
    cmp byte [edi], 0
    je .n2
    inc edi
    jmp .n
.n2:
    inc edi
    inc eax
    jmp .w
.yes:
    pop edi
    clc
    ret
.no:
    pop edi
    stc
    ret

; a number: a decimal when digits are set, else a double (read by sci)
sq_number:
    mov esi, [sq_pos]
    mov edi, sq_nb
    xor ecx, ecx
.d:
    mov al, [esi]
    cmp al, '.'
    je .k
    cmp al, '0'
    jb .x
    cmp al, '9'
    ja .x
.k:
    call .put
    jmp .d
.x:
    mov al, [esi]
    or al, 0x20
    cmp al, 'e'
    jne .done
    mov al, [esi+1]             ; 1e5, 2e-3 (not 2e: that is 2 * e)
    cmp al, '-'
    je .sg
    cmp al, '+'
    jne .ed
.sg:
    mov al, [esi+2]
.ed:
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    mov al, 'e'
    call .put
    mov al, [esi]
    cmp al, '-'
    je .s2
    cmp al, '+'
    jne .e
.s2:
    call .put
.e:
    mov al, [esi]
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
    call .put
    jmp .e
.done:
    mov byte [edi], 0
    mov [sq_pos], esi
    call sq_push
    cmp dword [sq_digits], 0
    jne d_parse
    push edi
    mov esi, sq_nb              ; sci reads it, up to an e
    xor edx, edx
.fe:
    lodsb
    test al, al
    jz .ev
    cmp al, 'e'
    jne .fe
    mov byte [esi-1], 0
    mov edx, esi
.ev:
    mov dword [sq_ev+GE_EXPR], sq_nb
    mov dword [sq_ev+GE_FLAGS], 0
    mov dword [sq_ev+GE_TEXT], 0
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, sq_ev
    int 0x80
    pop edi
    test eax, eax
    jnz sq_e_syntax
    fld qword [sq_ev+GE_RESULT]
    test edx, edx               ; then times 10^n
    jz .st
    mov esi, edx
    xor ecx, ecx
    xor ebx, ebx
    cmp byte [esi], '+'
    je .es
    cmp byte [esi], '-'
    jne .en
    inc ebx
.es:
    inc esi
.en:
    lodsb
    sub al, '0'
    cmp al, 9
    ja .ex
    imul ecx, 10
    movzx eax, al
    add ecx, eax
    cmp ecx, 1000
    jb .en
.ex:
    jecxz .st
.em:
    test ebx, ebx
    jnz .ediv
    fmul qword [sq_f10]
    loop .em
    jmp .st
.ediv:
    fdiv qword [sq_f10]
    loop .em
.st:
    fstp qword [edi+V_RE]
    ret
.put:
    cmp ecx, 60
    jae sq_e_syntax
    stosb
    inc ecx
    inc esi
    ret

; sq_nm -> its value pushed: a parameter, a variable, a constant, or the
; host's
sq_lookup:
    mov ecx, [sq_depth]
    jecxz .vars
    mov ebx, [sq_frame+ecx*8-8]     ; the function
    mov edx, [sq_frame+ecx*8-4]     ; its first argument's place
    xor eax, eax
.p:
    cmp eax, [ebx+SQ_FNN]
    jae .vars
    mov edi, eax
    shl edi, 4
    lea edi, [ebx+SQ_FNP+edi]
    mov esi, sq_nm
    call sq_streq
    je .par
    inc eax
    jmp .p
.par:
    add eax, edx
    imul esi, eax, SQ_VSIZE
    add esi, [sq_vs]
    jmp .copy
.vars:
    xor eax, eax
    mov esi, sq_nm
.v:
    cmp eax, [sq_nv]
    jae .const
    imul edi, eax, SQ_VREC
    add edi, [sq_vars]
    call sq_streq
    je .var
    inc eax
    jmp .v
.var:
    lea esi, [edi+16]
.copy:
    call sq_push
    mov ecx, SQ_VSIZE / 4
    push edi
    rep movsd
    pop edi
    ret
.const:
    mov edi, sq_consts
    call sq_index
    jc .host
    push eax
    call sq_push
    pop eax
    cmp eax, 1
    je .e
    ja .i
    cmp dword [sq_digits], 0    ; pi
    jne d_pi
    fldpi
    fstp qword [edi+V_RE]
    ret
.e:
    cmp dword [sq_digits], 0
    jne d_e
    fld1
    call f_exp
    fstp qword [edi+V_RE]
    ret
.i:
    mov byte [edi+V_T], ST_C
    fld1
    fstp qword [edi+V_IM]
    ret
.host:
    mov eax, [sqm_get]
    test eax, eax
    jz .unknown
    mov esi, sq_nm
    call sq_slen
    mov ecx, eax
    call [sqm_get]
    jc .unknown
    call sq_push
    fstp qword [edi+V_RE]
    cmp dword [sq_digits], 0
    jne d_from_r
    ret
.unknown:
    mov esi, se_name
    jmp sq_fail

; edi = a user function: its arguments, then its body worked out with
; them; the result replaces them
sq_call:
    mov ebx, edi
    call sq_take                ; (
    mov edx, [sq_vn]            ; the first argument's place
    xor ecx, ecx
    call sq_peek
    cmp al, ')'
    je .end
.a:
    push ebx
    push ecx
    push edx
    call sq_expr
    pop edx
    pop ecx
    pop ebx
    inc ecx
    call sq_peek
    cmp al, ','
    jne .end
    call sq_take
    jmp .a
.end:
    push ebx
    push ecx
    push edx
    mov dl, ')'
    call sq_want
    pop edx
    pop ecx
    pop ebx
    cmp ecx, [ebx+SQ_FNN]
    jne .count
    mov eax, [sq_depth]
    cmp eax, SQ_DEPTH
    jae .deep
    mov [sq_frame+eax*8], ebx
    mov [sq_frame+eax*8+4], edx
    inc dword [sq_depth]
    push dword [sq_pos]
    push edx
    lea eax, [ebx+SQ_FBODY]
    mov [sq_pos], eax
    call sq_expr
    call sq_peek
    test al, al
    jnz sq_e_syntax
    pop edx
    pop dword [sq_pos]
    dec dword [sq_depth]
    call sq_top                 ; the result -> the first argument's place
    mov esi, edi
    imul edi, edx, SQ_VSIZE
    add edi, [sq_vs]
    mov ecx, SQ_VSIZE / 4
    rep movsd
    inc edx
    mov [sq_vn], edx
    ret
.count:
    mov esi, se_args
    jmp sq_fail
.deep:
    mov esi, se_calls
    jmp sq_fail

; [unit] -> its value pushed: the scale in SI, with the unit's powers.
; The text inside is kept in sq_ubuf.
sq_unitval:
    call sq_peek
    call sq_take                ; [
    call sq_push
    fld1
    fstp qword [edi+V_RE]
    mov esi, [sq_pos]           ; the text, for "to"
    push edi
    mov edi, sq_ubuf
    mov ecx, 30
.t:
    mov al, [esi]
    test al, al
    jz .tz
    cmp al, ']'
    je .tz
    stosb
    inc esi
    loop .t
.tz:
    mov byte [edi], 0
    pop edi
    mov dword [sq_usign], 1
.l:
    call sq_peek
    cmp al, ']'
    je .done
    cmp al, '*'
    je .mul
    cmp al, '/'
    je .div
    push edi
    call sq_name
    pop edi
    test eax, eax
    jz .bad
    push edi
    call sq_unit                ; -> st0 = scale, sq_udim
    pop edi
    jc .unk
    mov ebx, 1                  ; ^n
    call sq_peek
    cmp al, '^'
    jne .pw
    call sq_take
    xor edx, edx
    call sq_peek
    cmp al, '-'
    jne .pd
    call sq_take
    inc edx
.pd:
    call sq_peek
    sub al, '0'
    cmp al, 9
    ja .bad
    call sq_take
    movzx ebx, al
    test edx, edx
    jz .pw
    neg ebx
.pw:
    imul ebx, [sq_usign]
    mov dword [sq_usign], 1
    mov ecx, ebx                ; scale^n
    fld1
    test ecx, ecx
    jz .sd
    jns .sp
    neg ecx
.sp:
    fmul st0, st1
    loop .sp
    test ebx, ebx
    jns .sd
    fld1
    fdivrp st1, st0
.sd:
    fmul qword [edi+V_RE]
    fstp qword [edi+V_RE]
    fstp st0
    xor ecx, ecx                ; the powers
.dm:
    movsx eax, byte [sq_udim+ecx]
    imul eax, ebx
    add [edi+V_DIM+ecx], al
    inc ecx
    cmp ecx, 7
    jb .dm
    jmp .l
.mul:
    call sq_take
    jmp .l
.div:
    call sq_take
    mov dword [sq_usign], -1
    jmp .l
.done:
    call sq_take
    cmp dword [sq_digits], 0
    jne d_from_r
    ret
.bad:
    mov esi, se_unit
    jmp sq_fail
.unk:
    mov esi, se_nounit
    jmp sq_fail

; sq_nm -> st0 = its scale in SI and sq_udim its powers, or CF. A
; prefix (k M G c m u n) may come before a unit's name.
sq_unit:
    mov esi, sq_nm
    call .find
    jnc .r
    mov al, [sq_nm]             ; a prefix?
    mov edi, sq_pfx
.p:
    cmp byte [edi], 0
    je .no
    cmp al, [edi]
    je .pf
    add edi, 9
    jmp .p
.pf:
    cmp byte [sq_nm+1], 0
    je .no
    push edi
    lea esi, [sq_nm+1]
    call .find
    pop edi
    jc .no
    fmul qword [edi+1]
.r:
    clc
    ret
.no:
    stc
    ret
.find:                          ; esi = a name -> st0, sq_udim, or CF
    mov edi, sq_units
.f:
    cmp byte [edi], 0
    je .fno
    call sq_streq
    je .fy
    add edi, 24
    jmp .f
.fy:
    fld qword [edi+8]
    mov eax, [edi+16]
    mov [sq_udim], eax
    mov eax, [edi+20]
    mov [sq_udim+4], eax
    clc
    ret
.fno:
    stc
    ret

; ---------- types and units ----------
; edi, esi = values -> ZF if their units are the same
sq_dimeq:
    push eax
    push ecx
    xor ecx, ecx
.c:
    mov al, [edi+V_DIM+ecx]
    cmp al, [esi+V_DIM+ecx]
    jne .r
    inc ecx
    cmp ecx, 7
    jb .c
.r:
    pop ecx
    pop eax
    ret
; edi = a value -> ZF if it has no unit
sq_plain:
    push eax
    mov eax, [edi]
    and eax, 0xFFFFFF00
    or eax, [edi+4]
    pop eax
    ret

; edi = a value -> a double (a decimal is turned into one)
sq_toR:
    cmp byte [edi+V_T], ST_D
    jne .r
    call d_to_r
.r:
    ret
; edi = a value -> complex
sq_toC:
    call sq_toR
    mov byte [edi+V_T], ST_C
    ret
; edi -> st0 = its real part as a double (the value is not changed)
sq_real:
    cmp byte [edi+V_T], ST_D
    je .d
    fld qword [edi+V_RE]
    ret
.d:
    push edi
    push esi
    mov esi, edi
    mov edi, sq_vtmp
    push ecx
    mov ecx, SQ_VSIZE / 4
    rep movsd
    pop ecx
    mov edi, sq_vtmp
    call d_to_r
    fld qword [edi+V_RE]
    pop esi
    pop edi
    ret

; edi = a, esi = b: both of one type (complex wins; then decimal)
sq_unify:
    mov al, [edi+V_T]
    mov ah, [esi+V_T]
    cmp al, ah
    je .r
    cmp al, ST_C
    je .c
    cmp ah, ST_C
    je .c
    cmp dword [sq_digits], 0    ; doubles now: the decimal is one too
    je .rr
    cmp al, ST_D                ; a decimal and a double
    je .bd
    jmp d_from_r                ; a is the double
.rr:
    call sq_toR
    push edi
    mov edi, esi
    call sq_toR
    pop edi
    ret
.bd:
    push edi
    mov edi, esi
    call d_from_r
    pop edi
.r:
    ret
.c:
    call sq_toC
    push edi
    mov edi, esi
    call sq_toC
    pop edi
    ret

; edi -> CF clear, or the line stops if a part is not finite
sq_finite:
    cmp byte [edi+V_T], ST_D
    je .r
    mov eax, [edi+V_RE+4]
    and eax, 0x7FF00000
    cmp eax, 0x7FF00000
    je sq_e_big
    mov eax, [edi+V_IM+4]
    and eax, 0x7FF00000
    cmp eax, 0x7FF00000
    je sq_e_big
.r:
    ret

; ---------- arithmetic: edi = a, esi = b; the result in a ----------
v_add:
    call sq_dimeq
    jne sq_e_units
    call sq_unify
    cmp byte [edi+V_T], ST_D
    je d_add
    fld qword [edi+V_RE]
    fadd qword [esi+V_RE]
    fstp qword [edi+V_RE]
    fld qword [edi+V_IM]
    fadd qword [esi+V_IM]
    fstp qword [edi+V_IM]
    ret

; b = -b (esi)
v_neg2:
    push edi
    mov edi, esi
    call v_neg
    pop edi
    ret
; edi = -edi
v_neg:
    cmp byte [edi+V_T], ST_D
    je .d
    fld qword [edi+V_RE]
    fchs
    fstp qword [edi+V_RE]
    cmp byte [edi+V_T], ST_C    ; a real keeps its +0
    jne .r
    fld qword [edi+V_IM]
    fchs
    fstp qword [edi+V_IM]
.r:
    ret
.d:
    xor byte [edi+V_BS], 1
    jmp d_fixzero

v_mul:
    xor ecx, ecx
.d:
    mov al, [esi+V_DIM+ecx]
    add [edi+V_DIM+ecx], al
    inc ecx
    cmp ecx, 7
    jb .d
    call sq_unify
    cmp byte [edi+V_T], ST_D
    je d_mul
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    fmul qword [esi+V_RE]
    fstp qword [edi+V_RE]
    ret
.c:
    fld qword [edi+V_RE]        ; ac - bd
    fmul qword [esi+V_RE]
    fld qword [edi+V_IM]
    fmul qword [esi+V_IM]
    fsubp st1, st0
    fld qword [edi+V_RE]        ; ad + bc
    fmul qword [esi+V_IM]
    fld qword [edi+V_IM]
    fmul qword [esi+V_RE]
    faddp st1, st0
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    ret

v_div:
    xor ecx, ecx
.d:
    mov al, [esi+V_DIM+ecx]
    sub [edi+V_DIM+ecx], al
    inc ecx
    cmp ecx, 7
    jb .d
    call sq_unify
    cmp byte [edi+V_T], ST_D
    je d_div
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [esi+V_RE]
    ftst
    fnstsw ax
    sahf
    je .zero
    fdivr qword [edi+V_RE]
    fstp qword [edi+V_RE]
    ret
.zero:
    jmp sq_e_div0
.c:
    fld qword [esi+V_RE]        ; |b|^2
    fmul st0, st0
    fld qword [esi+V_IM]
    fmul st0, st0
    faddp st1, st0
    ftst
    fnstsw ax
    sahf
    je .zero
    fld qword [edi+V_RE]        ; (ac + bd) / |b|^2
    fmul qword [esi+V_RE]
    fld qword [edi+V_IM]
    fmul qword [esi+V_IM]
    faddp st1, st0
    fdiv st0, st1
    fld qword [edi+V_IM]        ; (bc - ad) / |b|^2
    fmul qword [esi+V_RE]
    fld qword [edi+V_RE]
    fmul qword [esi+V_IM]
    fsubp st1, st0
    fdiv st0, st2
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    fstp st0
    ret

; a ^ b
v_pow:
    push edi
    mov edi, esi
    call sq_plain
    pop edi
    jne .unitexp
    cmp byte [esi+V_T], ST_C
    je .general
    push edi                    ; a whole power?
    mov edi, esi
    call sq_real
    pop edi
    fld st0
    frndint
    fcomip st1
    jne .notint
    fld st0
    fabs
    fld qword [sq_f1e6]
    fcomip st1
    fstp st0
    jb .notint
    fistp dword [sq_n]
    mov eax, [sq_n]             ; the units, times n
    xor ecx, ecx
.dm:
    movsx edx, byte [edi+V_DIM+ecx]
    imul edx, eax
    mov [edi+V_DIM+ecx], dl
    inc ecx
    cmp ecx, 7
    jb .dm
    cmp byte [edi+V_T], ST_D
    je d_powi
    cmp byte [edi+V_T], ST_C
    je .cint
    fld1                        ; a real: by squaring
    fld qword [edi+V_RE]
    mov eax, [sq_n]
    test eax, eax
    jns .rl
    neg eax
.rl:
    test eax, eax
    jz .rd
    shr eax, 1
    jnc .rs
    fmul st1, st0
.rs:
    fmul st0, st0
    jmp .rl
.rd:
    fstp st0
    cmp dword [sq_n], 0
    jge .rp
    ftst
    fnstsw ax
    sahf
    je .zero
    fld1
    fdivrp st1, st0
.rp:
    fstp qword [edi+V_RE]
    ret
.zero:
    jmp sq_e_div0
.cint:                          ; complex: by squaring, in sq_ca (base)
    fld qword [edi+V_RE]        ; and the result in a
    fstp qword [sq_cr]
    fld qword [edi+V_IM]
    fstp qword [sq_ci]
    fld1
    fstp qword [edi+V_RE]
    fldz
    fstp qword [edi+V_IM]
    mov eax, [sq_n]
    test eax, eax
    jns .cl
    neg eax
.cl:
    test eax, eax
    jz .cd
    shr eax, 1
    jnc .cs
    push eax                    ; a *= base
    fld qword [edi+V_RE]
    fmul qword [sq_cr]
    fld qword [edi+V_IM]
    fmul qword [sq_ci]
    fsubp st1, st0
    fld qword [edi+V_RE]
    fmul qword [sq_ci]
    fld qword [edi+V_IM]
    fmul qword [sq_cr]
    faddp st1, st0
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    pop eax
.cs:
    fld qword [sq_cr]           ; base *= base
    fmul st0, st0
    fld qword [sq_ci]
    fmul st0, st0
    fsubp st1, st0
    fld qword [sq_cr]
    fmul qword [sq_ci]
    fadd st0, st0
    fstp qword [sq_ci]
    fstp qword [sq_cr]
    jmp .cl
.cd:
    cmp dword [sq_n], 0
    jge .cr
    fld qword [edi+V_RE]        ; 1 / a = conj(a) / |a|^2
    fmul st0, st0
    fld qword [edi+V_IM]
    fmul st0, st0
    faddp st1, st0
    ftst
    fnstsw ax
    sahf
    je .zero
    fld qword [edi+V_RE]
    fdiv st0, st1
    fstp qword [edi+V_RE]
    fld qword [edi+V_IM]
    fdiv st0, st1
    fchs
    fstp qword [edi+V_IM]
    fstp st0
.cr:
    ret
.notint:
    fstp st0
.general:                       ; e^(b ln a)
    call sq_plain
    jne .unitexp
    cmp byte [edi+V_T], ST_C
    je .gc
    cmp byte [esi+V_T], ST_C
    je .gc
    call sq_toR
    push edi
    mov edi, esi
    call sq_toR
    pop edi
    fld qword [edi+V_RE]        ; a real a >= 0: real
    ftst
    fnstsw ax
    sahf
    jb .gc2
    je .z
    call f_ln
    fmul qword [esi+V_RE]
    call f_exp
    fstp qword [edi+V_RE]
    ret
.z:
    fstp st0                    ; 0 ^ b
    fld qword [esi+V_RE]
    ftst
    fnstsw ax
    sahf
    fstp st0
    jbe sq_e_domain
    ret
.gc2:
    fstp st0
.gc:
    call sq_toC
    push edi
    mov edi, esi
    call sq_toC
    pop edi
    fld qword [edi+V_RE]        ; |a| = 0?
    fabs
    fld qword [edi+V_IM]
    fabs
    faddp st1, st0
    ftst
    fnstsw ax
    sahf
    fstp st0
    je sq_e_domain
    call c_ln                   ; a = ln a
    call v_mul                  ; a = b ln a
    jmp c_exp
.unitexp:
    mov esi, se_unitpow
    jmp sq_fail

; edi = n! (a whole number from 0)
v_fact:
    call sq_plain
    jne sq_e_plain
    cmp byte [edi+V_T], ST_C
    je sq_e_cplx
    call sq_real
    fld st0
    frndint
    fcomip st1
    jne .bad
    fldz
    fcomip st1
    ja .bad
    fistp dword [sq_n]
    cmp dword [sq_n], 3000
    ja sq_e_big
    cmp byte [edi+V_T], ST_D
    je .d
    fld1
    mov ecx, [sq_n]
    jecxz .r
.m:
    mov [sq_n], ecx
    fimul dword [sq_n]
    loop .m
.r:
    fstp qword [edi+V_RE]
    ret
.d:
    mov ecx, [sq_n]
    push edi
    lea esi, [sq_ts]            ; 1, scaled
    mov esi, [esi]
    lea edi, [edi+V_BM]
    push ecx
    mov ecx, SQ_BL
    call bm_copy
    pop ecx
    jecxz .dd
.dl:
    mov ebx, ecx
    xor eax, eax
    push ecx
    mov ecx, SQ_BL
    call bm_mulsmall
    pop ecx
    test eax, eax
    jnz sq_e_big
    loop .dl
.dd:
    pop edi
    mov dword [edi+V_BS], 0
    ret
.bad:
    fstp st0
    jmp sq_e_domain

; ---------- functions: edi = the argument (on top) ----------
fn_sqrt:
    xor ecx, ecx                ; the units are halved
.h:
    mov al, [edi+V_DIM+ecx]
    sar al, 1
    jc sq_e_unitroot
    mov [edi+V_DIM+ecx], al
    inc ecx
    cmp ecx, 7
    jb .h
    cmp byte [edi+V_T], ST_D
    jne .nd
    cmp dword [edi+V_BS], 0
    je d_sqrt
    call d_to_r
.nd:
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    ftst
    fnstsw ax
    sahf
    jb .neg
    fsqrt
    fstp qword [edi+V_RE]
    ret
.neg:
    fchs
    fsqrt
    fstp qword [edi+V_IM]
    fldz
    fstp qword [edi+V_RE]
    mov byte [edi+V_T], ST_C
    ret
.c:                             ; re = sqrt((r + x) / 2), im = +-sqrt((r - x) / 2)
    call c_abs                  ; st0 = r
    fld st0
    fadd qword [edi+V_RE]
    fmul qword [sq_fhalf]
    fsqrt
    fxch
    fsub qword [edi+V_RE]
    fmul qword [sq_fhalf]
    fsqrt
    test byte [edi+V_IM+7], 0x80
    jz .pos
    fchs
.pos:
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    ret
sq_e_unitroot:
    mov esi, se_unitpow
    jmp sq_fail

fn_abs:
    cmp byte [edi+V_T], ST_D
    je .d
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    fabs
    fstp qword [edi+V_RE]
    ret
.d:
    mov dword [edi+V_BS], 0
    ret
.c:
    call c_abs
    jmp sq_setreal

; edi = complex -> st0 = |a|
c_abs:
    fld qword [edi+V_RE]
    fmul st0, st0
    fld qword [edi+V_IM]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    ret
; st0 (popped) -> edi = that real
sq_setreal:
    fstp qword [edi+V_RE]
    fldz
    fstp qword [edi+V_IM]
    mov byte [edi+V_T], ST_R
    ret

; a plain number is wanted: edi -> a double or complex
sq_wantplain:
    call sq_plain
    jne sq_e_plain
    jmp sq_toR

fn_exp:
    call sq_wantplain
    cmp byte [edi+V_T], ST_C
    je c_exp
    fld qword [edi+V_RE]
    call f_exp
    fstp qword [edi+V_RE]
    ret
fn_ln:
    call sq_wantplain
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    ftst
    fnstsw ax
    sahf
    fstp st0
    je sq_e_domain
    jb .c
    fld qword [edi+V_RE]
    call f_ln
    fstp qword [edi+V_RE]
    ret
.c:
    call sq_toC
    fld qword [edi+V_RE]
    fabs
    fld qword [edi+V_IM]
    fabs
    faddp st1, st0
    ftst
    fnstsw ax
    sahf
    fstp st0
    je sq_e_domain
    jmp c_ln
fn_log:
    call fn_ln
    cmp byte [edi+V_T], ST_C
    je sq_e_cplx
    fld qword [edi+V_RE]
    fdiv qword [sq_fln10]
    fstp qword [edi+V_RE]
    ret
fn_sin:
    call sq_wantplain
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    fsin
    fstp qword [edi+V_RE]
    ret
.c:                             ; sin x cosh y + i cos x sinh y
    call c_coshsinh             ; st0 = cosh y, st1 = sinh y
    fld qword [edi+V_RE]
    fsin
    fmulp st1, st0
    fxch
    fld qword [edi+V_RE]
    fcos
    fmulp st1, st0
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    ret
fn_cos:
    call sq_wantplain
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    fcos
    fstp qword [edi+V_RE]
    ret
.c:                             ; cos x cosh y - i sin x sinh y
    call c_coshsinh
    fld qword [edi+V_RE]
    fcos
    fmulp st1, st0
    fxch
    fld qword [edi+V_RE]
    fsin
    fmulp st1, st0
    fchs
    fstp qword [edi+V_IM]
    fstp qword [edi+V_RE]
    ret
fn_tan:
    call sq_realarg
    fptan
    fstp st0
    fstp qword [edi+V_RE]
    ret
fn_asin:                        ; atan2(x, sqrt(1 - x^2))
    call sq_unitarg
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fpatan
    fstp qword [edi+V_RE]
    ret
fn_acos:                        ; atan2(sqrt(1 - x^2), x)
    call sq_unitarg
    fld st0
    fmul st0, st0
    fld1
    fsubrp st1, st0
    fsqrt
    fxch
    fpatan
    fstp qword [edi+V_RE]
    ret
fn_atan:
    call sq_realarg
    fld1
    fpatan
    fstp qword [edi+V_RE]
    ret
fn_re:
    call sq_toR
    fld qword [edi+V_RE]
    jmp sq_setreal
fn_im:
    call sq_toR
    fld qword [edi+V_IM]
    jmp sq_setreal
fn_conj:
    cmp byte [edi+V_T], ST_C
    jne .r
    fld qword [edi+V_IM]
    fchs
    fstp qword [edi+V_IM]
.r:
    ret
fn_arg:
    call sq_toR
    fld qword [edi+V_IM]
    fld qword [edi+V_RE]
    fpatan
    jmp sq_setreal
fn_floor:
    call sq_realarg
    call sq_ffloor
    fstp qword [edi+V_RE]
    ret
fn_ceil:
    call sq_realarg
    fchs
    call sq_ffloor
    fchs
    fstp qword [edi+V_RE]
    ret
fn_round:                       ; halves away from 0
    call sq_realarg
    ftst
    fnstsw ax
    sahf
    jb .neg
    fadd qword [sq_fhalf]
    call sq_ffloor
    fstp qword [edi+V_RE]
    ret
.neg:
    fchs
    fadd qword [sq_fhalf]
    call sq_ffloor
    fchs
    fstp qword [edi+V_RE]
    ret

; edi = a plain real -> st0 (a double), or the line stops
sq_realarg:
    call sq_wantplain
    cmp byte [edi+V_T], ST_C
    je sq_e_cplx
    fld qword [edi+V_RE]
    ret
; as sq_realarg, from -1 to 1
sq_unitarg:
    call sq_realarg
    fld st0
    fabs
    fld1
    fcomip st1
    fstp st0
    jb sq_e_domain
    ret

; st0 -> floor(st0)
sq_ffloor:
    fld st0
    frndint
    fcomi st0, st1
    fstp st1
    jbe .r
    fld1
    fsubp st1, st0
.r:
    ret
; st0 = x -> e^x
f_exp:
    fldl2e
    fmulp st1, st0
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
; st0 = x (> 0) -> ln x
f_ln:
    fldln2
    fxch
    fyl2x
    ret
; edi = complex -> st0 = cosh y, st1 = sinh y
c_coshsinh:
    fld qword [edi+V_IM]
    call f_exp                  ; e^y
    fld1
    fdiv st0, st1               ; e^-y, e^y
    fld st1
    fsub st0, st1
    fmul qword [sq_fhalf]       ; sinh, e^-y, e^y
    fxch st2
    faddp st1, st0
    fmul qword [sq_fhalf]       ; cosh, sinh
    ret
; edi = complex -> ln: (ln |a|, arg a)
c_ln:
    fld qword [edi+V_IM]
    fld qword [edi+V_RE]
    fpatan
    call c_abs
    call f_ln
    fstp qword [edi+V_RE]
    fstp qword [edi+V_IM]
    ret
; edi = complex -> e^a
c_exp:
    fld qword [edi+V_RE]
    call f_exp
    fld qword [edi+V_IM]
    fsincos                     ; cos, sin, e^x
    fmul st0, st2
    fstp qword [edi+V_RE]
    fmulp st1, st0
    fstp qword [edi+V_IM]
    ret

; ---------- text ----------
; edi = a value -> appended to sqm_out, with its unit
sq_vtext:
    pushad
    cmp byte [edi+V_T], ST_D
    je .d
    cmp byte [edi+V_T], ST_C
    je .c
    fld qword [edi+V_RE]
    call sq_num
    jmp .u
.d:
    call d_text
    jmp .u
.c:                             ; a + bi; a part far below the other is 0
    fld qword [edi+V_RE]
    fabs
    fld1
    fcomi st0, st1
    fcmovb st0, st1
    fstp st1
    fmul qword [sq_ftiny]       ; the size that counts as nothing
    fld qword [edi+V_IM]
    fabs
    fcomip st1
    fstp st0
    ja .imok
    fldz
    fstp qword [edi+V_IM]
.imok:
    fld qword [edi+V_IM]
    fabs
    fld1
    fcomi st0, st1
    fcmovb st0, st1
    fstp st1
    fmul qword [sq_ftiny]
    fld qword [edi+V_RE]
    fabs
    fcomip st1
    fstp st0
    ja .reok
    fldz
    fstp qword [edi+V_RE]
.reok:
    fld qword [edi+V_IM]
    ftst
    fnstsw ax
    sahf
    fstp st0
    jne .ci
    fld qword [edi+V_RE]
    call sq_num
    jmp .u
.ci:
    fld qword [edi+V_RE]
    ftst
    fnstsw ax
    sahf
    je .onlyi
    call sq_num
    mov esi, sw_plus
    test byte [edi+V_IM+7], 0x80
    jz .pm
    mov esi, sw_minus
.pm:
    call sq_puts
    fld qword [edi+V_IM]
    fabs
    jmp .imag
.onlyi:
    fstp st0
    fld qword [edi+V_IM]
.imag:                          ; st0 -> "bi" ("i" for 1, "-i" for -1)
    fld1
    fcomi st0, st1
    fstp st0
    je .one
    fld1
    fchs
    fcomi st0, st1
    fstp st0
    jne .num
    fstp st0
    mov esi, sw_minus1
    call sq_puts
    jmp .i
.one:
    fstp st0
    jmp .i
.num:
    call sq_num
.i:
    mov esi, sw_i
    call sq_puts
.u:
    call sq_plain
    je .r
    mov esi, sw_sp
    call sq_puts
    call sq_unittext
.r:
    popad
    ret

; st0 (popped) -> its text appended, as sci prints it
sq_num:
    push eax
    push ebx
    push ecx
    push esi
    fstp qword [sq_ev+GE_X]
    mov dword [sq_ev+GE_EXPR], sw_x
    mov dword [sq_ev+GE_FLAGS], GEF_X
    mov dword [sq_ev+GE_TEXT], sq_nb
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, sq_ev
    int 0x80
    mov esi, sq_nb
    call sq_puts
    pop esi
    pop ecx
    pop ebx
    pop eax
    ret

; edi = a value -> its unit's text appended: a named unit (N, J, ...),
; or the base units: kg*m^2/s^2
sq_unittext:
    pushad
    mov esi, sq_named
.n:
    cmp byte [esi], 0
    je .base
    push esi
    push edi
    lea eax, [esi+4]
    lea ecx, [edi+V_DIM]
    xor edx, edx
.cb:
    mov bl, [eax+edx]
    cmp bl, [ecx+edx]
    jne .ne
    inc edx
    cmp edx, 7
    jb .cb
    pop edi
    pop esi
    call sq_puts                ; its name (first 4 bytes, zero-ended)
    popad
    ret
.ne:
    pop edi
    pop esi
    add esi, 12
    jmp .n
.base:
    mov byte [sq_first], 1
    xor ebx, ebx                ; positive powers
.p:
    movsx eax, byte [edi+V_DIM+ebx]
    cmp eax, 0
    jle .pn
    call .one
.pn:
    inc ebx
    cmp ebx, 7
    jb .p
    cmp byte [sq_first], 0      ; nothing above: 1/s
    je .den
    mov esi, sw_one
    call sq_puts
.den:
    xor ebx, ebx                ; negative powers, after a /
    mov byte [sq_slash], 0
.q:
    movsx eax, byte [edi+V_DIM+ebx]
    cmp eax, 0
    jge .qn
    cmp byte [sq_slash], 0
    jne .q2
    mov esi, sw_slash
    call sq_puts
    mov byte [sq_slash], 1
    mov byte [sq_first], 1
.q2:
    neg eax
    call .one
.qn:
    inc ebx
    cmp ebx, 7
    jb .q
    popad
    ret
.one:                           ; ebx = base unit, eax = power > 0
    cmp byte [sq_first], 0
    jne .nf
    mov esi, sw_star
    call sq_puts
.nf:
    mov byte [sq_first], 0
    imul esi, ebx, 4
    add esi, sq_bases
    call sq_puts
    cmp eax, 1
    je .r1
    mov esi, sw_caret
    call sq_puts
    push edi
    mov edi, sq_nb
    call gui_utoa
    pop edi
    mov esi, sq_nb
    call sq_puts
.r1:
    ret

; ---------- decimals ----------
; eax = places (0: doubles again) -> F = places + 5, 10^F made
sq_setdigits:
    pushad
    push eax
    xor ecx, ecx                ; decimals kept so far become doubles
.v:
    cmp ecx, [sq_nv]
    jae .vd
    imul edi, ecx, SQ_VREC
    add edi, [sq_vars]
    add edi, 16
    call sq_toR
    inc ecx
    jmp .v
.vd:
    pop eax
    mov [sq_digits], eax
    test eax, eax
    jz .r
    add eax, 5
    mov [sq_F], eax
    mov edi, [sq_ts]
    mov ecx, SQ_BL
    call bm_zero
    mov dword [edi], 1
    mov ecx, [sq_F]
    fld1
.m:
    push ecx
    mov ebx, 10
    xor eax, eax
    mov ecx, SQ_BL
    call bm_mulsmall
    pop ecx
    fmul qword [sq_f10]
    loop .m
    fstp qword [sq_p10F]
.r:
    popad
    ret

; edi = a value whose double (V_RE) becomes a decimal
d_from_r:
    pushad
    fld qword [edi+V_RE]
    mov eax, [edi+V_RE+4]
    shr eax, 31
    mov [edi+V_BS], eax
    mov byte [edi+V_T], ST_D
    lea ebp, [edi+V_BM]
    push edi
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_zero
    pop edi
    fabs
    ftst
    fnstsw ax
    sahf
    je .zero
    fxtract                     ; significand, exponent
    fmul qword [sq_f2p52]
    fistp qword [sq_q]          ; a whole number below 2^53
    fistp dword [sq_n]
    mov eax, [sq_q]
    mov [ebp], eax
    mov eax, [sq_q+4]
    mov [ebp+4], eax
    mov ecx, [sq_F]             ; times 10^F
.m:
    push ecx
    mov edi, ebp
    mov ebx, 10
    xor eax, eax
    mov ecx, SQ_BL
    call bm_mulsmall
    pop ecx
    test eax, eax
    jnz sq_e_big
    loop .m
    mov ecx, [sq_n]             ; times 2^(e - 52)
    sub ecx, 52
    jz .done
    js .right
.l:
    push ecx
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_shl1
    pop ecx
    jc sq_e_big
    loop .l
    jmp .done
.right:
    neg ecx
.rr:
    push ecx
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_shr1
    pop ecx
    loop .rr
.done:
    popad
    jmp d_fixzero
.zero:
    fstp st0
    mov dword [edi+V_BS], 0
    popad
    ret

; edi = a decimal -> a double
d_to_r:
    pushad
    fldz
    mov ecx, SQ_BL
.l:
    fmul qword [sq_f2p32]
    mov eax, [edi+V_BM+ecx*4-4]
    mov [sq_q], eax
    mov dword [sq_q+4], 0
    fild qword [sq_q]
    faddp st1, st0
    loop .l
    fdiv qword [sq_p10F]
    cmp dword [edi+V_BS], 0
    je .p
    fchs
.p:
    fstp qword [edi+V_RE]
    fldz
    fstp qword [edi+V_IM]
    mov byte [edi+V_T], ST_R
    popad
    ret

; sq_nb = a number's text, edi = a new value -> it as a decimal
d_parse:
    pushad
    mov byte [edi+V_T], ST_D
    lea ebp, [edi+V_BM]
    mov esi, sq_nb
    xor edx, edx                ; places after the point
    xor ebx, ebx                ; a point seen
.c:
    lodsb
    cmp al, '.'
    je .pt
    cmp al, '0'
    jb .x
    cmp al, '9'
    ja .x
    sub al, '0'
    movzx eax, al
    push ebx
    mov edi, ebp
    mov ebx, 10
    mov ecx, SQ_BL
    call bm_mulsmall
    pop ebx
    test eax, eax
    jnz sq_e_big
    add edx, ebx
    jmp .c
.pt:
    mov ebx, 1
    jmp .c
.x:
    cmp al, 'e'                 ; e-3, e+4, e5
    jne .scale
    xor ecx, ecx
    xor ebx, ebx
    mov al, [esi]
    cmp al, '+'
    je .es
    cmp al, '-'
    jne .ed
    inc ebx
.es:
    inc esi
.ed:
    lodsb
    sub al, '0'
    cmp al, 9
    ja .ee
    imul ecx, 10
    movzx eax, al
    add ecx, eax
    cmp ecx, 1000
    ja sq_e_big
    jmp .ed
.ee:
    test ebx, ebx
    jz .ep
    neg ecx
.ep:
    sub edx, ecx
.scale:                         ; times 10^(F - places)
    mov ecx, [sq_F]
    sub ecx, edx
    jz .r
    js .down
.up:
    push ecx
    mov edi, ebp
    mov ebx, 10
    xor eax, eax
    mov ecx, SQ_BL
    call bm_mulsmall
    pop ecx
    test eax, eax
    jnz sq_e_big
    loop .up
    jmp .r
.down:
    neg ecx
.dn:
    push ecx
    mov edi, ebp
    mov ebx, 10
    mov ecx, SQ_BL
    call bm_divsmall
    pop ecx
    loop .dn
.r:
    popad
    ret

; edi = a decimal: no "-0"
d_fixzero:
    push ecx
    push edi
    lea edi, [edi+V_BM]
    mov ecx, SQ_BL
    call bm_iszero
    pop edi
    pop ecx
    jne .r
    mov dword [edi+V_BS], 0
.r:
    ret

; a += b (decimals)
d_add:
    pushad
    lea ebp, [edi+V_BM]
    lea edx, [esi+V_BM]
    mov eax, [edi+V_BS]
    cmp eax, [esi+V_BS]
    jne .diff
    push esi
    mov esi, edx
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_add
    pop esi
    jc sq_e_big
    popad
    ret
.diff:
    push esi
    push edi
    mov esi, edx
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_cmp                 ; |b| ? |a|
    pop edi
    pop esi
    ja .bigger
    push esi
    mov esi, edx
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_sub
    pop esi
    popad
    jmp d_fixzero
.bigger:                        ; a = b - a, with b's sign
    mov eax, [esi+V_BS]
    mov [edi+V_BS], eax
    push edi
    mov esi, edx
    mov edi, [sq_t]
    mov ecx, SQ_BL
    call bm_copy
    mov esi, ebp
    call bm_sub
    mov esi, edi
    mov edi, ebp
    call bm_copy
    pop edi
    popad
    jmp d_fixzero

; a *= b (decimals): (|a| |b|) / 10^F
d_mul:
    pushad
    mov eax, [esi+V_BS]
    xor [edi+V_BS], eax
    push edi
    lea esi, [esi+V_BM]
    lea ebx, [edi+V_BM]
    mov edi, [sq_t]
    call bm_mul
    call d_unscale              ; edi = 2 BL dwords / 10^F
    pop edi
    call d_takelow
    popad
    jmp d_fixzero

; a /= b (decimals): (|a| 10^F) / |b|
d_div:
    pushad
    push edi
    mov edi, esi
    lea edi, [edi+V_BM]
    mov ecx, SQ_BL
    call bm_iszero
    pop edi
    je sq_e_div0
    mov eax, [esi+V_BS]
    xor [edi+V_BS], eax
    push edi
    push esi
    lea esi, [edi+V_BM]
    mov ebx, [sq_ts]
    mov edi, [sq_t]
    call bm_mul                 ; t0 = |a| 10^F
    pop esi
    lea esi, [esi+V_BM]
    mov edi, [sq_t]
    call bm_div                 ; -> t1 = t0 / |b|
    pop edi
    push dword [sq_t]
    mov eax, [sq_t+4]
    mov [sq_t], eax
    call d_takelow
    pop dword [sq_t]
    popad
    jmp d_fixzero

; [sq_t] (2 BL dwords) -> edi's magnitude, if it fits
d_takelow:
    push esi
    push edi
    push ecx
    mov esi, [sq_t]
    lea edi, [esi+SQ_BL*4]
    mov ecx, SQ_BL
    call bm_iszero
    jne sq_e_big
    mov edi, [esp+4]
    lea edi, [edi+V_BM]
    call bm_copy
    pop ecx
    pop edi
    pop esi
    ret

; edi = 2 BL dwords -> divided by 10^F
d_unscale:
    pushad
    mov edx, [sq_F]
.n:
    cmp edx, 9
    jb .last
    mov ebx, 1000000000
    mov ecx, 2 * SQ_BL
    push edx
    call bm_divsmall
    pop edx
    sub edx, 9
    jmp .n
.last:
    test edx, edx
    jz .r
    mov ebx, 1
.p:
    imul ebx, 10
    dec edx
    jnz .p
    mov ecx, 2 * SQ_BL
    call bm_divsmall
.r:
    popad
    ret

; edi = a decimal, [sq_n] = a whole power
d_powi:
    pushad
    mov ebp, edi
    mov esi, edi                ; the base -> sq_vb
    mov edi, sq_vb
    mov ecx, SQ_VSIZE / 4
    rep movsd
    mov edi, ebp                ; a = 1
    lea edi, [edi+V_BM]
    mov esi, [sq_ts]
    mov ecx, SQ_BL
    call bm_copy
    mov dword [ebp+V_BS], 0
    mov eax, [sq_n]
    test eax, eax
    jns .l
    neg eax
.l:
    test eax, eax
    jz .d
    shr eax, 1
    jnc .s
    push eax
    mov edi, ebp
    mov esi, sq_vb
    call d_mul
    pop eax
.s:
    test eax, eax
    jz .d
    push eax
    mov edi, sq_vb
    mov esi, sq_vb2
    push edi
    push esi
    mov esi, edi
    mov edi, sq_vb2
    mov ecx, SQ_VSIZE / 4
    rep movsd
    pop esi
    pop edi
    call d_mul
    pop eax
    jmp .l
.d:
    cmp dword [sq_n], 0
    jge .r
    mov esi, ebp                ; 1 / a
    mov edi, sq_vb2
    mov ecx, SQ_VSIZE / 4
    rep movsd
    mov edi, ebp
    lea edi, [edi+V_BM]
    mov esi, [sq_ts]
    mov ecx, SQ_BL
    call bm_copy
    mov dword [ebp+V_BS], 0
    mov edi, ebp
    mov esi, sq_vb2
    call d_div
.r:
    popad
    ret

; edi = a decimal >= 0 -> its square root (Newton's method from the
; double's root)
d_sqrt:
    pushad
    mov ebp, edi
    mov esi, edi                ; a -> sq_va
    mov edi, sq_va
    mov ecx, SQ_VSIZE / 4
    rep movsd
    mov edi, ebp
    lea edi, [edi+V_BM]
    mov ecx, SQ_BL
    call bm_iszero
    je .r
    mov edi, ebp
    call sq_real
    fsqrt
    fstp qword [ebp+V_RE]
    call d_from_r               ; x0
    mov ecx, 8
.it:                            ; x = (x + a / x) / 2
    push ecx
    mov esi, sq_va
    mov edi, sq_vb
    mov ecx, SQ_VSIZE / 4
    rep movsd
    mov edi, sq_vb
    mov esi, ebp
    call d_div
    mov edi, ebp
    mov esi, sq_vb
    call d_add
    lea edi, [ebp+V_BM]
    mov ebx, 2
    mov ecx, SQ_BL
    call bm_divsmall
    pop ecx
    loop .it
.r:
    mov byte [ebp+V_T], ST_D
    popad
    ret

; edi = a new value -> pi as a decimal: 16 atan(1/5) - 4 atan(1/239)
d_pi:
    pushad
    mov byte [edi+V_T], ST_D
    mov ebp, edi
    mov ebx, 5
    call d_atan_inv             ; -> [sq_t+8]
    mov edi, [sq_t+8]
    mov ebx, 16
    xor eax, eax
    mov ecx, SQ_BL
    call bm_mulsmall
    lea edi, [ebp+V_BM]
    mov esi, [sq_t+8]
    call bm_copy
    mov ebx, 239
    call d_atan_inv
    mov edi, [sq_t+8]
    mov ebx, 4
    xor eax, eax
    mov ecx, SQ_BL
    call bm_mulsmall
    mov esi, edi
    lea edi, [ebp+V_BM]
    call bm_sub
    popad
    ret

; ebx = x -> [sq_t+8] = atan(1/x) times 10^F
; (1/x - 1/(3x^3) + 1/(5x^5) - ...)
d_atan_inv:
    pushad
    mov esi, [sq_ts]            ; term = 10^F / x
    mov edi, [sq_t+12]
    mov ecx, SQ_BL
    call bm_copy
    call bm_divsmall
    mov esi, edi
    mov edi, [sq_t+8]           ; sum = term
    call bm_copy
    mov eax, ebx
    mul ebx
    mov [sq_n], eax             ; x^2
    mov ebp, 1                  ; k
.k:
    mov edi, [sq_t+12]
    mov ebx, [sq_n]
    mov ecx, SQ_BL
    call bm_divsmall
    call bm_iszero
    je .r
    mov esi, edi                ; term / (2k + 1)
    mov edi, [sq_t+16]
    call bm_copy
    lea ebx, [ebp*2+1]
    call bm_divsmall
    mov esi, edi
    mov edi, [sq_t+8]
    test ebp, 1
    jz .add
    call bm_sub
    jmp .n
.add:
    call bm_add
.n:
    inc ebp
    jmp .k
.r:
    popad
    ret

; edi = a new value -> e as a decimal: 1 + 1 + 1/2! + ...
d_e:
    pushad
    mov byte [edi+V_T], ST_D
    lea ebp, [edi+V_BM]
    mov esi, [sq_ts]
    mov edi, ebp
    mov ecx, SQ_BL
    call bm_copy
    mov edi, [sq_t+12]
    call bm_copy
    mov ebx, 1
.k:
    mov edi, [sq_t+12]
    call bm_divsmall
    call bm_iszero
    je .r
    mov esi, edi
    mov edi, ebp
    call bm_add
    inc ebx
    jmp .k
.r:
    popad
    ret

; edi = a decimal -> its text appended: rounded to [sq_digits] places,
; trailing zeros dropped
d_text:
    pushad
    mov ebp, edi
    lea esi, [edi+V_BM]
    mov edi, [sq_t+12]
    mov ecx, SQ_BL
    call bm_copy
    mov ebx, 10
    xor edx, edx                ; digits, lowest first, in sq_db
.d:
    push edx
    call bm_divsmall
    mov eax, edx
    pop edx
    add al, '0'
    mov [sq_db+edx], al
    inc edx
    cmp edx, 400
    jae .got
    cmp edx, [sq_F]
    jbe .d
    call bm_iszero
    jne .d
.got:
    mov ecx, edx                ; whole digits = n - F
    sub ecx, [sq_F]
    mov edi, sq_dt
    mov byte [edi], '0'         ; room for a carry
    inc edi
    mov ebx, edx
.w:                             ; the whole part
    dec ebx
    mov al, [sq_db+ebx]
    stosb
    cmp ebx, [sq_F]
    ja .w
    mov [sq_n], edi             ; where the point goes
    mov ecx, [sq_digits]        ; the places kept
.f:
    dec ebx
    mov al, [sq_db+ebx]
    stosb
    loop .f
    mov byte [edi], 0
    cmp byte [sq_db+ebx-1], '5' ; the next digit: round
    jb .rounded
    mov esi, edi
.up:
    dec esi
    cmp byte [esi], '9'
    jne .inc
    mov byte [esi], '0'
    jmp .up
.inc:
    inc byte [esi]
.rounded:
    dec edi                     ; drop zeros at the end
.z:
    cmp edi, [sq_n]
    jb .nz
    cmp byte [edi], '0'
    jne .nz
    mov byte [edi], 0
    dec edi
    jmp .z
.nz:
    mov esi, sq_dt              ; a leading 0 unless the carry used it
    cmp byte [esi], '0'
    jne .s
    inc esi
.s:
    mov edi, sq_dt2             ; with the sign and the point
    mov eax, esi
    cmp dword [ebp+V_BS], 0
    je .cp
    cmp byte [esi], '0'         ; "-0" is 0
    jne .neg
    cmp byte [esi+1], 0
    je .cp
.neg:
    mov byte [edi], '-'
    inc edi
.cp:
    cmp esi, [sq_n]
    jne .c1
    cmp byte [esi], 0
    je .end
    mov byte [edi], '.'
    inc edi
.c1:
    lodsb
    test al, al
    jz .end
    stosb
    jmp .cp
.end:
    mov byte [edi], 0
    mov esi, sq_dt2
    call sq_puts
    popad
    ret

; ---------- magnitudes: little-endian dwords ----------
; edi, ecx dwords -> 0
bm_zero:
    push eax
    push ecx
    push edi
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret
; esi -> edi, ecx dwords
bm_copy:
    push ecx
    push esi
    push edi
    rep movsd
    pop edi
    pop esi
    pop ecx
    ret
; edi -> ZF if 0 (ecx dwords)
bm_iszero:
    push eax
    push ecx
    push edi
    xor eax, eax
    repe scasd
    pop edi
    pop ecx
    pop eax
    ret
; edi += esi (ecx dwords) -> CF out
bm_add:
    push eax
    push ebx
    push ecx
    xor ebx, ebx
    clc
.l:
    mov eax, [esi+ebx*4]
    adc [edi+ebx*4], eax
    inc ebx
    dec ecx
    jnz .l
    pop ecx
    pop ebx
    pop eax
    ret
; edi -= esi (ecx dwords) -> CF out
bm_sub:
    push eax
    push ebx
    push ecx
    xor ebx, ebx
    clc
.l:
    mov eax, [esi+ebx*4]
    sbb [edi+ebx*4], eax
    inc ebx
    dec ecx
    jnz .l
    pop ecx
    pop ebx
    pop eax
    ret
; esi ? edi (ecx dwords) -> the flags of an unsigned compare
bm_cmp:
    push eax
    push ecx
.l:
    dec ecx
    js .eq
    mov eax, [esi+ecx*4]
    cmp eax, [edi+ecx*4]
    je .l
    pop ecx
    pop eax
    ret
.eq:
    xor eax, eax
    cmp eax, eax
    pop ecx
    pop eax
    ret
; edi = edi * ebx + eax (ecx dwords) -> eax = what did not fit
bm_mulsmall:
    push ecx
    push edx
    push esi
    push edi
    mov esi, eax
.l:
    mov eax, [edi]
    mul ebx
    add eax, esi
    adc edx, 0
    mov [edi], eax
    mov esi, edx
    add edi, 4
    dec ecx
    jnz .l
    mov eax, esi
    pop edi
    pop esi
    pop edx
    pop ecx
    ret
; edi = edi / ebx (ecx dwords) -> edx = the remainder
bm_divsmall:
    push eax
    push ecx
    xor edx, edx
.l:
    mov eax, [edi+ecx*4-4]
    div ebx
    mov [edi+ecx*4-4], eax
    dec ecx
    jnz .l
    pop ecx
    pop eax
    ret
; edi <<= 1 (ecx dwords) -> CF out
bm_shl1:
    push ebx
    push ecx
    xor ebx, ebx
    clc
.l:
    rcl dword [edi+ebx*4], 1
    inc ebx
    dec ecx
    jnz .l
    pop ecx
    pop ebx
    ret
; edi >>= 1 (ecx dwords)
bm_shr1:
    push ecx
    clc
.l:
    rcr dword [edi+ecx*4-4], 1
    dec ecx
    jnz .l
    pop ecx
    ret
; esi, ebx = BL dwords each -> edi = their product (2 BL dwords)
bm_mul:
    pushad
    mov ecx, 2 * SQ_BL
    call bm_zero
    xor ebp, ebp
.i:
    cmp ebp, SQ_BL
    jae .r
    mov eax, [esi+ebp*4]
    test eax, eax
    jz .ni
    mov [sq_mi], eax
    lea eax, [edi+ebp*4]
    mov [sq_mp], eax
    mov dword [sq_mc], 0
    xor ecx, ecx
.j:
    mov eax, [ebx+ecx*4]
    mul dword [sq_mi]
    add eax, [sq_mc]
    adc edx, 0
    push edi
    mov edi, [sq_mp]
    add [edi+ecx*4], eax
    adc edx, 0
    pop edi
    mov [sq_mc], edx
    inc ecx
    cmp ecx, SQ_BL
    jb .j
    mov eax, [sq_mp]
    mov edx, [sq_mc]
    mov [eax+SQ_BL*4], edx
.ni:
    inc ebp
    jmp .i
.r:
    popad
    ret
; edi = 2 BL dwords, esi = BL dwords (not 0) -> [sq_t+4] = the quotient
; (2 BL dwords), by shifting and subtracting
bm_div:
    pushad
    mov [sq_dn], edi
    mov [sq_dd], esi
    mov edi, [sq_t+4]
    mov ecx, 2 * SQ_BL
    call bm_zero
    mov edi, [sq_t+20]          ; the remainder: BL + 1 dwords
    mov ecx, SQ_BL + 1
    call bm_zero
    mov ebp, 2 * SQ_BL          ; the top dword that is not 0
.t:
    dec ebp
    js .r
    mov eax, [sq_dn]
    cmp dword [eax+ebp*4], 0
    je .t
.dw:
    mov edx, 31
.bit:
    mov edi, [sq_t+20]          ; r = r * 2 + the bit
    mov ecx, SQ_BL + 1
    xor ebx, ebx
    mov eax, [sq_dn]
    bt dword [eax+ebp*4], edx
.sh:
    rcl dword [edi+ebx*4], 1
    inc ebx
    dec ecx
    jnz .sh
    cmp dword [edi+SQ_BL*4], 0  ; r >= d?
    jne .sub
    mov esi, edi
    mov edi, [sq_dd]
    mov ecx, SQ_BL
    call bm_cmp
    jb .next
    mov edi, esi
.sub:
    mov esi, [sq_dd]
    mov ecx, SQ_BL
    call bm_sub
    sbb dword [edi+SQ_BL*4], 0
    mov eax, [sq_t+4]
    bts dword [eax+ebp*4], edx
.next:
    dec edx
    jns .bit
    dec ebp
    jns .dw
.r:
    popad
    ret

; ---------- data ----------
align 8
sq_f10   dq 10.0
sq_f1e6  dq 1e6
sq_fhalf dq 0.5
sq_ftiny dq 1e-12
sq_fln10 dq 2.302585092994045684
sq_f2p52 dq 4503599627370496.0
sq_f2p32 dq 4294967296.0
sq_fcode dd fn_sqrt, fn_abs, fn_exp, fn_ln, fn_log, fn_sin, fn_cos, fn_tan
         dd fn_asin, fn_acos, fn_atan, fn_re, fn_im, fn_conj, fn_arg
         dd fn_floor, fn_ceil, fn_round
sq_fnames db 'sqrt', 0, 'abs', 0, 'exp', 0, 'ln', 0, 'log', 0, 'sin', 0
          db 'cos', 0, 'tan', 0, 'asin', 0, 'acos', 0, 'atan', 0, 're', 0
          db 'im', 0, 'conj', 0, 'arg', 0, 'floor', 0, 'ceil', 0, 'round', 0, 0
sq_consts db 'pi', 0, 'e', 0, 'i', 0, 0
; units: name (8), scale, the powers of m kg s A K mol cd (and a pad)
%macro SQU 3-9 0, 0, 0, 0, 0, 0
    db %1
    times 8 - %strlen(%1) db 0
    dq %2
    db %3, %4, %5, %6, %7, %8, %9, 0
%endmacro
sq_units:
    SQU 'm', 1.0, 1
    SQU 'g', 0.001, 0, 1
    SQU 's', 1.0, 0, 0, 1
    SQU 'A', 1.0, 0, 0, 0, 1
    SQU 'K', 1.0, 0, 0, 0, 0, 1
    SQU 'mol', 1.0, 0, 0, 0, 0, 0, 1
    SQU 'cd', 1.0, 0, 0, 0, 0, 0, 0, 1
    SQU 'min', 60.0, 0, 0, 1
    SQU 'h', 3600.0, 0, 0, 1
    SQU 'day', 86400.0, 0, 0, 1
    SQU 'Hz', 1.0, 0, 0, -1
    SQU 'N', 1.0, 1, 1, -2
    SQU 'J', 1.0, 2, 1, -2
    SQU 'W', 1.0, 2, 1, -3
    SQU 'Pa', 1.0, -1, 1, -2
    SQU 'C', 1.0, 0, 0, 1, 1
    SQU 'V', 1.0, 2, 1, -3, -1
    SQU 'ohm', 1.0, 2, 1, -3, -2
    SQU 'L', 0.001, 3
    SQU 't', 1000.0, 0, 1
    SQU 'in', 0.0254, 1
    SQU 'ft', 0.3048, 1
    SQU 'yd', 0.9144, 1
    SQU 'mi', 1609.344, 1
    SQU 'lb', 0.45359237, 0, 1
    SQU 'eV', 1.602176634e-19, 2, 1, -2
    SQU 'cal', 4.184, 2, 1, -2
    SQU 'atm', 101325.0, -1, 1, -2
    SQU 'bar', 100000.0, -1, 1, -2
    db 0
; prefixes: the letter, the factor
sq_pfx:
    db 'k'
    dq 1e3
    db 'M'
    dq 1e6
    db 'G'
    dq 1e9
    db 'c'
    dq 1e-2
    db 'm'
    dq 1e-3
    db 'u'
    dq 1e-6
    db 'n'
    dq 1e-9
    db 0
; units shown by name: 4 bytes of name, 7 powers, a pad
sq_named:
    db 'N', 0, 0, 0, 1, 1, -2, 0, 0, 0, 0, 0
    db 'J', 0, 0, 0, 2, 1, -2, 0, 0, 0, 0, 0
    db 'W', 0, 0, 0, 2, 1, -3, 0, 0, 0, 0, 0
    db 'Pa', 0, 0, -1, 1, -2, 0, 0, 0, 0, 0
    db 'Hz', 0, 0, 0, 0, -1, 0, 0, 0, 0, 0
    db 'V', 0, 0, 0, 2, 1, -3, -1, 0, 0, 0, 0
    db 0
sq_bases db 'm', 0, 0, 0, 'kg', 0, 0, 's', 0, 0, 0, 'A', 0, 0, 0, 'K', 0, 0, 0
         db 'mol', 0, 'cd', 0, 0
sw_digits db 'digits', 0
sw_digs  db 'digits: ', 0
sw_off   db 'off (doubles)', 0
sw_eq    db ' = ', 0
sw_sp    db ' ', 0
sw_plus  db ' + ', 0
sw_minus db ' - ', 0
sw_minus1 db '-', 0
sw_i     db 'i', 0
sw_x     db 'x', 0
sw_one   db '1', 0
sw_slash db '/', 0
sw_star  db '*', 0
sw_caret db '^', 0
se_syntax db 'this cannot be read here', 0
se_rp    db 'a ) is missing', 0
se_rb    db 'a ] is missing', 0
se_units db 'the units do not match', 0
se_unitpow db 'this power does not suit the unit', 0
se_digits db 'digits: a number of places from 0 to 150', 0
se_div0  db 'division by zero', 0
se_domain db 'outside the function domain', 0
se_big   db 'the number is too large', 0
se_plain db 'a number without a unit is wanted', 0
se_cplx  db 'not for complex numbers', 0
se_name  db 'unknown name', 0
se_nofn  db 'unknown function', 0
se_args  db 'the wrong number of arguments', 0
se_calls db 'calls too deep', 0
se_deep  db 'the expression is too deep', 0
se_long  db 'the function is too long', 0
se_fns   db 'too many functions', 0
se_vars  db 'too many variables', 0
se_unit  db 'a unit is written [km], [m/s^2], [kg*m]', 0
se_nounit db 'unknown unit', 0

; zeroed data: put SQM_BSS after SQX_BSS
%macro SQM_BSS 0
alignb 8
sq_q        resq 1
sq_cr       resq 1
sq_ci       resq 1
sq_p10F     resq 1
sq_vtmp     resb SQ_VSIZE
sq_va       resb SQ_VSIZE
sq_vb       resb SQ_VSIZE
sq_vb2      resb SQ_VSIZE
sq_vs       resd 1
sq_vars     resd 1
sq_fns      resd 1
sq_t        resd 8
sq_ts       equ sq_t + 28
sq_vn       resd 1
sq_nv       resd 1
sq_nf       resd 1
sq_pos      resd 1
sq_line0    resd 1
sq_sp       resd 1
sq_op       resd 1
sq_depth    resd 1
sq_frame    resd SQ_DEPTH * 2
sq_digits   resd 1
sq_F        resd 1
sq_n        resd 1
sq_usign    resd 1
sq_mi       resd 1
sq_mp       resd 1
sq_mc       resd 1
sq_dn       resd 1
sq_dd       resd 1
sqm_kind    resd 1
sqm_err     resd 1
sqm_get     resd 1
sqm_set     resd 1
sq_ev       resb GE_SIZE
sq_udim     resb 8
sq_first    resb 1
sq_slash    resb 1
sq_nm       resb 16
sq_lhs      resb 16
sq_par      resb 64
sq_nb       resb 64
sq_ubuf     resb 32
sq_db       resb 404
sq_dt       resb 404
sq_dt2      resb 408
sqm_out     resb 304
%endmacro
