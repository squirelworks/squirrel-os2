; Squirrel-OS/2 — matrix calculator (matrix), 0.3.4
; Included from pm.asm. Original code.
;
; Up to 6x6 matrices of doubles in variables A-Z plus ans. Literals
; [1 2; 3 4], + - *, scalar multiples, det, trans, inv (Gauss-Jordan
; with partial pivoting). Numbers print through the sci formatter.
; See documentation/apps/calculators.md.
;
; A matrix is: rows dd, cols dd, then rows*cols doubles, row-major.
; Every intermediate result is a fresh temporary from a pool that is
; reset at the start of each line.

MX_MAXN     equ 6
MX_SIZE     equ 8 + MX_MAXN*MX_MAXN*8   ; 296
MX_STRIDE   equ 304
MX_VARS     equ 0x50000                 ; 27 variables: A-Z, ans
MX_ANS      equ 26
MX_TEMP     equ 0x53000
MX_TMAX     equ 64
MX_ROWS     equ 0
MX_COLS     equ 4
MX_DATA     equ 8

run_matrix:
    call cls
    mov esi, mx_banner
    call puts
    mov esi, mx_help
    call puts
    cmp byte [mx_ready], 0
    jne .prompt
    call mx_clear_all
    mov byte [mx_ready], 1
.prompt:
    mov esi, mx_prompt
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
    mov edi, calc_kw_clear
    call streq
    je .clear
    mov edi, mx_kw_list
    call streq
    je .list
    call mx_line
    jnc .prompt
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
.clear:
    call mx_clear_all
    mov esi, calc_cleared
    call puts
    jmp .prompt
.list:
    call mx_list
    jmp .prompt
.quit:
    call app_home
    xor eax, eax
    ret

mx_clear_all:
    mov edi, MX_VARS
    mov ecx, 27*MX_STRIDE/4
    xor eax, eax
    rep stosd
    ret

; "[NAME =] expr": evaluates, stores (NAME or ans) and prints
mx_line:
    fninit
    mov dword [mx_tnext], 0
    mov dword [mx_target], MX_ANS
    ; assignment?
    mov al, [esi]
    sub al, 'A'
    cmp al, 25
    ja .expr
    mov edi, esi
    inc edi
.sp:
    cmp byte [edi], ' '
    jne .eq
    inc edi
    jmp .sp
.eq:
    cmp byte [edi], '='
    jne .expr
    movzx eax, al
    mov [mx_target], eax
    lea esi, [edi+1]
.expr:
    call mx_expr
    jc .r
    call calc_skip
    cmp byte [esi], 0
    jne calc_syntax
    ; copy into the variable and show it
    mov esi, eax
    mov edi, [mx_target]
    imul edi, MX_STRIDE
    add edi, MX_VARS
    push edi
    mov ecx, MX_SIZE/4
    rep movsd
    pop esi
    mov eax, [mx_target]
    call mx_show
    clc
.r:
    ret

; eax = variable index, esi = matrix -> prints "NAME =" and the rows
mx_show:
    push esi
    call mx_putname
    mov esi, mx_m_eq
    call puts
    pop esi
    cmp dword [esi+MX_ROWS], 1
    jne .rows
    cmp dword [esi+MX_COLS], 1
    jne .rows
    fld qword [esi+MX_DATA]     ; a 1x1 result reads as a number
    call sci_fmt
    mov esi, sci_out
    call puts
    mov al, 10
    jmp putc
.rows:
    mov al, 10
    call putc
    lea ebx, [esi+MX_DATA]
    mov edx, [esi+MX_ROWS]
.row:
    mov ecx, [esi+MX_COLS]
.col:
    fld qword [ebx]
    fld st0                     ; show rounding noise (|x| < 1e-10) as 0
    fabs
    fcomp qword [mx_snap]
    fnstsw ax
    sahf
    jae .keep
    fstp st0
    fldz
.keep:
    call sci_fmt
    push esi
    mov esi, sci_out
    call strlen
    mov ah, 13                  ; right-align in 13 columns
    sub ah, al
    jg .pad
    mov ah, 1
.pad:
    mov al, ' '
    call putc
    dec ah
    jnz .pad
    call puts
    pop esi
    add ebx, 8
    loop .col
    mov al, 10
    call putc
    dec edx
    jnz .row
    ret

; eax = variable index -> prints its name
mx_putname:
    cmp eax, MX_ANS
    je .ans
    add al, 'A'
    jmp putc
.ans:
    push esi
    mov esi, calc_kw_ans
    call puts
    pop esi
    ret

; prints every defined variable with its size
mx_list:
    pushad
    xor eax, eax
    mov ebx, MX_VARS
    xor edx, edx
.l:
    cmp dword [ebx+MX_ROWS], 0
    je .n
    inc edx
    push eax
    call mx_putname
    mov al, ' '
    call putc
    mov eax, [ebx+MX_ROWS]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 'x'
    call putc
    mov eax, [ebx+MX_COLS]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    pop eax
.n:
    add ebx, MX_STRIDE
    inc eax
    cmp eax, 27
    jb .l
    test edx, edx
    jnz .out
    mov esi, mx_m_none
    call puts
.out:
    popad
    ret

; ---------- temporaries ----------
; -> eax = fresh matrix, or CF (pool exhausted)
mx_alloc:
    mov eax, [mx_tnext]
    cmp eax, MX_TMAX
    jae .full
    inc dword [mx_tnext]
    imul eax, MX_STRIDE
    add eax, MX_TEMP
    clc
    ret
.full:
    mov dword [calc_errmsg], mx_e_complex
    stc
    ret

; ebx = matrix -> eax = new matrix of the same size (contents undefined)
mx_alloc_like:
    call mx_alloc
    jc .r
    push ecx
    mov ecx, [ebx+MX_ROWS]
    mov [eax+MX_ROWS], ecx
    mov ecx, [ebx+MX_COLS]
    mov [eax+MX_COLS], ecx
    pop ecx
.r:
    ret

; ebx = matrix -> ecx = element count
mx_count:
    mov ecx, [ebx+MX_ROWS]
    imul ecx, [ebx+MX_COLS]
    ret

mx_mismatch:
    mov dword [calc_errmsg], mx_e_size
    stc
    ret
mx_notsquare:
    mov dword [calc_errmsg], mx_e_square
    stc
    ret

; ---------- recursive descent: esi = cursor, eax = matrix, CF = error ----------
; expr   := term { (+|-) term }
; term   := factor { * factor }
; factor := - factor | det factor | trans factor | inv factor
;         | ( expr ) | [ literal ] | number | A-Z | ans

mx_expr:
    call mx_term
    jc .r
.more:
    call calc_skip
    mov dl, [esi]
    cmp dl, '+'
    je .op
    cmp dl, '-'
    je .op
    clc
.r:
    ret
.op:
    inc esi
    push edx
    push eax
    call mx_term
    mov ecx, eax                ; right
    pop ebx                     ; left
    pop edx
    jc .r
    call mx_addsub
    jc .r
    jmp .more

mx_term:
    call mx_factor
    jc .r
.more:
    call calc_skip
    cmp byte [esi], '*'
    je .op
    clc
.r:
    ret
.op:
    inc esi
    push eax
    call mx_factor
    mov ecx, eax
    pop ebx
    jc .r
    call mx_mul
    jc .r
    jmp .more

mx_factor:
    call calc_skip
    mov al, [esi]
    cmp al, '-'
    je .neg
    cmp al, '('
    je .paren
    cmp al, '['
    je mx_literal
    cmp al, '.'
    je .num
    cmp al, '0'
    jb .word
    cmp al, '9'
    jbe .num
.word:
    mov edi, mx_kw_det
    call calc_match
    jnc .det
    mov edi, mx_kw_trans
    call calc_match
    jnc .trans
    mov edi, mx_kw_inv
    call calc_match
    jnc .inv
    mov edi, calc_kw_ans
    call calc_match
    jnc .ans
    mov al, [esi]
    sub al, 'A'
    cmp al, 25
    ja calc_syntax
    mov dl, [esi+1]             ; a single capital, not part of a word
    or dl, 0x20
    cmp dl, 'a'
    jb .var
    cmp dl, 'z'
    jbe calc_syntax
.var:
    movzx eax, al
    inc esi
    jmp .load
.ans:
    mov eax, MX_ANS
.load:
    imul eax, MX_STRIDE
    add eax, MX_VARS
    cmp dword [eax+MX_ROWS], 0
    jne .ok
    mov dword [calc_errmsg], mx_e_undef
    stc
    ret
.ok:
    clc
    ret
.neg:
    inc esi
    call mx_factor
    jc .r
    mov ebx, eax
    call mx_alloc_like
    jc .r
    call mx_count
    xor edx, edx
.nl:
    fld qword [ebx+MX_DATA+edx*8]
    fchs
    fstp qword [eax+MX_DATA+edx*8]
    inc edx
    loop .nl
    clc
.r:
    ret
.paren:
    inc esi
    call mx_expr
    jc .r
    call calc_skip
    cmp byte [esi], ')'
    jne calc_syntax
    inc esi
    clc
    ret
.num:
    call sci_number
    jc .r
    call mx_alloc
    jc .r
    mov dword [eax+MX_ROWS], 1
    mov dword [eax+MX_COLS], 1
    fstp qword [eax+MX_DATA]
    clc
    ret
.det:
    call mx_factor
    jc .r
    jmp mx_det
.trans:
    call mx_factor
    jc .r
    jmp mx_trans
.inv:
    call mx_factor
    jc .r
    jmp mx_inv

; "[ a b ; c d ]" -> eax
mx_literal:
    inc esi
    call mx_alloc
    jc .r
    mov edi, eax
    xor ebx, ebx                ; elements so far
    xor ecx, ecx                ; elements in the current row
    xor edx, edx                ; rows completed
    mov dword [edi+MX_COLS], 0
.item:
    call calc_skip
    mov al, [esi]
    cmp al, ','
    je .comma
    cmp al, ';'
    je .rowend
    cmp al, ']'
    je .close
    ; one number, optionally signed
    push eax
    cmp al, '-'
    jne .unsigned
    inc esi
.unsigned:
    mov al, [esi]
    cmp al, '.'
    je .digit
    sub al, '0'
    cmp al, 9
    ja .bad
.digit:
    push ebx
    push ecx
    push edx
    push edi
    call sci_number
    pop edi
    pop edx
    pop ecx
    pop ebx
    jc .badpop
    pop eax
    cmp al, '-'
    jne .store
    fchs
.store:
    cmp ecx, MX_MAXN
    jae .toobig
    cmp ebx, MX_MAXN*MX_MAXN
    jae .toobig
    fstp qword [edi+MX_DATA+ebx*8]
    inc ebx
    inc ecx
    jmp .item
.comma:
    inc esi
    jmp .item
.rowend:
    inc esi
    call .endrow
    jc .r
    jmp .item
.close:
    inc esi
    test ecx, ecx
    jnz .last
    test edx, edx
    jz calc_syntax              ; [] is empty
    jmp .done
.last:
    call .endrow
    jc .r
.done:
    mov [edi+MX_ROWS], edx
    mov eax, edi
    clc
.r:
    ret
.endrow:                        ; closes a row of ecx elements
    test ecx, ecx
    jz .synt
    cmp dword [edi+MX_COLS], 0
    jne .samecols
    mov [edi+MX_COLS], ecx
.samecols:
    cmp [edi+MX_COLS], ecx
    jne .ragged
    inc edx
    cmp edx, MX_MAXN
    ja .toobig2
    xor ecx, ecx
    clc
    ret
.synt:
    add esp, 4                  ; drop .endrow's return address
    jmp calc_syntax
.ragged:
    mov dword [calc_errmsg], mx_e_ragged
    stc
    ret
.toobig2:
    mov dword [calc_errmsg], mx_e_big
    stc
    ret
.bad:
    pop eax
    jmp calc_syntax
.badpop:
    pop eax
    stc
    ret
.toobig:
    fstp st0
    mov dword [calc_errmsg], mx_e_big
    stc
    ret

; ---------- operations: ebx = left, ecx = right -> eax ----------

; dl = '+' or '-'
mx_addsub:
    mov eax, [ebx+MX_ROWS]
    cmp eax, [ecx+MX_ROWS]
    jne mx_mismatch
    mov eax, [ebx+MX_COLS]
    cmp eax, [ecx+MX_COLS]
    jne mx_mismatch
    call mx_alloc_like
    jc .r
    push ecx
    mov edi, ecx
    call mx_count
    push edx
    xor edx, edx
.l:
    fld qword [ebx+MX_DATA+edx*8]
    cmp byte [esp], '+'
    je .add
    fsub qword [edi+MX_DATA+edx*8]
    jmp .st
.add:
    fadd qword [edi+MX_DATA+edx*8]
.st:
    fstp qword [eax+MX_DATA+edx*8]
    inc edx
    loop .l
    pop edx
    pop ecx
    clc
.r:
    ret

mx_mul:
    cmp dword [ebx+MX_ROWS], 1
    jne .lnot1
    cmp dword [ebx+MX_COLS], 1
    jne .lnot1
    fld qword [ebx+MX_DATA]     ; scalar * matrix
    mov ebx, ecx
    jmp mx_scale
.lnot1:
    cmp dword [ecx+MX_ROWS], 1
    jne .product
    cmp dword [ecx+MX_COLS], 1
    jne .product
    fld qword [ecx+MX_DATA]     ; matrix * scalar
    jmp mx_scale
.product:
    mov eax, [ebx+MX_COLS]
    cmp eax, [ecx+MX_ROWS]
    jne mx_mismatch
    call mx_alloc
    jc .r
    push ebp
    push esi
    mov edi, eax
    mov eax, [ebx+MX_ROWS]
    mov [edi+MX_ROWS], eax
    mov eax, [ecx+MX_COLS]
    mov [edi+MX_COLS], eax
    ; out[i][j] = sum_k a[i][k] * b[k][j]
    xor esi, esi                ; i
.i:
    xor edx, edx                ; j
.j:
    fldz
    xor ebp, ebp                ; k
.k:
    mov eax, esi
    imul eax, [ebx+MX_COLS]
    add eax, ebp
    fld qword [ebx+MX_DATA+eax*8]
    mov eax, ebp
    imul eax, [ecx+MX_COLS]
    add eax, edx
    fmul qword [ecx+MX_DATA+eax*8]
    faddp st1, st0
    inc ebp
    cmp ebp, [ebx+MX_COLS]
    jb .k
    mov eax, esi
    imul eax, [edi+MX_COLS]
    add eax, edx
    fstp qword [edi+MX_DATA+eax*8]
    inc edx
    cmp edx, [edi+MX_COLS]
    jb .j
    inc esi
    cmp esi, [edi+MX_ROWS]
    jb .i
    pop esi
    pop ebp
    mov eax, edi
    clc
.r:
    ret

; st0 = factor (popped), ebx = matrix -> eax = factor * matrix
mx_scale:
    call mx_alloc_like
    jc .fail
    push ecx
    call mx_count
    xor edx, edx
.l:
    fld qword [ebx+MX_DATA+edx*8]
    fmul st0, st1
    fstp qword [eax+MX_DATA+edx*8]
    inc edx
    loop .l
    pop ecx
    fstp st0
    clc
    ret
.fail:
    fstp st0
    stc
    ret

; ebx -> eax = transpose (eax in, from mx_factor)
mx_trans:
    mov ebx, eax
    call mx_alloc
    jc .r
    mov ecx, [ebx+MX_ROWS]
    mov [eax+MX_COLS], ecx
    mov ecx, [ebx+MX_COLS]
    mov [eax+MX_ROWS], ecx
    push esi
    xor esi, esi                ; source index
    xor ecx, ecx                ; i
.i:
    xor edx, edx                ; j
.j:
    ; dest[j][i] = src[i][j]
    mov edi, edx
    imul edi, [eax+MX_COLS]
    add edi, ecx
    fld qword [ebx+MX_DATA+esi*8]
    fstp qword [eax+MX_DATA+edi*8]
    inc esi
    inc edx
    cmp edx, [ebx+MX_COLS]
    jb .j
    inc ecx
    cmp ecx, [ebx+MX_ROWS]
    jb .i
    pop esi
    clc
.r:
    ret

; eax = square matrix -> eax = 1x1 determinant
mx_det:
    mov ebx, eax
    mov ecx, [ebx+MX_ROWS]
    cmp ecx, [ebx+MX_COLS]
    jne mx_notsquare
    call mx_alloc_like
    jc .r
    mov edi, eax
    push esi
    mov esi, ebx
    push edi
    mov ecx, MX_SIZE/4
    rep movsd                   ; work on a copy
    pop edi
    pop esi
    mov byte [mx_want_inv], 0
    call mx_eliminate           ; st0 = determinant
    jc .r
    mov dword [edi+MX_ROWS], 1
    mov dword [edi+MX_COLS], 1
    fstp qword [edi+MX_DATA]
    mov eax, edi
    clc
.r:
    ret

; eax = square matrix -> eax = inverse
mx_inv:
    mov ebx, eax
    mov ecx, [ebx+MX_ROWS]
    cmp ecx, [ebx+MX_COLS]
    jne mx_notsquare
    call mx_alloc_like
    jc .r
    mov edi, eax
    push esi
    mov esi, ebx
    push edi
    mov ecx, MX_SIZE/4
    rep movsd
    pop edi
    pop esi
    call mx_alloc_like          ; the identity becomes the inverse
    jc .r
    mov [mx_aug], eax
    push edi
    push eax
    lea edi, [eax+MX_DATA]
    mov ecx, MX_MAXN*MX_MAXN*2
    xor eax, eax
    rep stosd
    pop eax
    pop edi
    mov ecx, [ebx+MX_ROWS]
    lea edx, [ecx+1]            ; diagonal step
    shl edx, 3
    lea ebx, [eax+MX_DATA]
.id:
    fld1
    fstp qword [ebx]
    add ebx, edx
    loop .id
    mov byte [mx_want_inv], 1
    call mx_eliminate
    jc .r
    ; |det| tiny means singular
    fabs
    fcomp qword [mx_eps]
    fnstsw ax
    sahf
    jbe mx_singular
    mov eax, [mx_aug]
    clc
.r:
    ret

mx_singular:
    mov dword [calc_errmsg], mx_e_singular
    stc
    ret

; Gaussian elimination with partial pivoting on edi (n x n). With
; mx_want_inv set, the same row operations run on [mx_aug] and the
; elimination continues to reduced form, leaving the inverse there.
; -> st0 = determinant (0 when a pivot vanishes)
mx_eliminate:
    pushad
    mov ecx, [edi+MX_ROWS]
    mov [mx_n], ecx
    fld1                        ; determinant
    xor ebx, ebx                ; column / pivot row
.col:
    cmp ebx, [mx_n]
    jae .done
    ; pivot: largest |a[r][col]| for r >= col
    mov edx, ebx
    mov esi, ebx
    mov eax, ebx
    call .at
    fld qword [edi+MX_DATA+eax*8]
    fabs
.p:
    inc esi
    cmp esi, [mx_n]
    jae .pivoted
    mov eax, ebx
    call .at
    fld qword [edi+MX_DATA+eax*8]
    fabs
    fcomp st1
    fnstsw ax
    sahf
    jbe .p
    fstp st0
    mov eax, ebx
    call .at
    fld qword [edi+MX_DATA+eax*8]
    fabs
    mov edx, esi
    jmp .p
.pivoted:
    fcomp qword [mx_eps]
    fnstsw ax
    sahf
    ja .nonzero
    fstp st0                    ; singular: determinant 0
    fldz
    jmp .done
.nonzero:
    cmp edx, ebx
    je .noswap
    mov esi, ebx
    call .swap                  ; rows ebx <-> edx
    fchs
.noswap:
    ; det *= pivot; scale the pivot row by 1/pivot
    mov eax, ebx
    mov esi, ebx
    call .at
    fld qword [edi+MX_DATA+eax*8]
    fmul st1, st0
    fld1
    fdivrp st1, st0             ; 1 / pivot
    mov esi, ebx
    call .scalerow
    ; eliminate the column from the other rows
    xor esi, esi
.r:
    cmp esi, [mx_n]
    jae .next
    cmp esi, ebx
    je .rn
    cmp byte [mx_want_inv], 0
    jne .elim
    cmp esi, ebx
    jb .rn                      ; determinant only needs rows below
.elim:
    mov eax, ebx
    call .at                    ; factor = a[r][col]
    fld qword [edi+MX_DATA+eax*8]
    call .subrow                ; row r -= factor * row col
.rn:
    inc esi
    jmp .r
.next:
    inc ebx
    jmp .col
.done:
    fstp qword [mx_detval]
    popad
    fld qword [mx_detval]
    clc
    ret

; esi = row, eax = column -> eax = index (row * n + column)
.at:
    push edx
    push eax
    mov eax, esi
    imul eax, [mx_n]
    pop edx
    add eax, edx
    pop edx
    ret

; st0 = factor (popped): row esi *= factor, in edi and the augment
.scalerow:
    push ecx
    push eax
    xor eax, eax
    call .at
    mov ecx, [mx_n]
.sr:
    fld qword [edi+MX_DATA+eax*8]
    fmul st0, st1
    fstp qword [edi+MX_DATA+eax*8]
    cmp byte [mx_want_inv], 0
    je .sr2
    push edx
    mov edx, [mx_aug]
    fld qword [edx+MX_DATA+eax*8]
    fmul st0, st1
    fstp qword [edx+MX_DATA+eax*8]
    pop edx
.sr2:
    inc eax
    loop .sr
    fstp st0
    pop eax
    pop ecx
    ret

; st0 = factor (popped): row esi -= factor * row ebx
.subrow:
    push ecx
    push edx
    push ebp
    xor eax, eax
    call .at                    ; eax = start of row esi
    mov ebp, eax
    push esi
    mov esi, ebx
    xor eax, eax
    call .at                    ; eax = start of row ebx
    pop esi
    mov ecx, [mx_n]
.sb:
    fld qword [edi+MX_DATA+eax*8]
    fmul st0, st1
    fsubr qword [edi+MX_DATA+ebp*8]
    fstp qword [edi+MX_DATA+ebp*8]
    cmp byte [mx_want_inv], 0
    je .sb2
    mov edx, [mx_aug]
    fld qword [edx+MX_DATA+eax*8]
    fmul st0, st1
    fsubr qword [edx+MX_DATA+ebp*8]
    fstp qword [edx+MX_DATA+ebp*8]
.sb2:
    inc eax
    inc ebp
    loop .sb
    fstp st0
    pop ebp
    pop edx
    pop ecx
    ret

; swaps rows esi and edx in edi and the augment
.swap:
    push eax
    push ecx
    push ebp
    xor eax, eax
    call .at
    mov ebp, eax
    push esi
    mov esi, edx
    xor eax, eax
    call .at
    pop esi
    mov ecx, [mx_n]
.sw:
    fld qword [edi+MX_DATA+eax*8]
    fld qword [edi+MX_DATA+ebp*8]
    fstp qword [edi+MX_DATA+eax*8]
    fstp qword [edi+MX_DATA+ebp*8]
    cmp byte [mx_want_inv], 0
    je .sw2
    push edx
    mov edx, [mx_aug]
    fld qword [edx+MX_DATA+eax*8]
    fld qword [edx+MX_DATA+ebp*8]
    fstp qword [edx+MX_DATA+eax*8]
    fstp qword [edx+MX_DATA+ebp*8]
    pop edx
.sw2:
    inc eax
    inc ebp
    loop .sw
    pop ebp
    pop ecx
    pop eax
    ret

mx_banner db 'Matrix Calculator', 10, 0
mx_help db 'A = [1 2; 3 4] defines A (A-Z, up to 6x6); ans holds the last result', 10
        db '+ - *, number * A, det A, trans A, inv A, ( ); list, clear, q or Esc', 10, 0
mx_help_len equ $ - mx_help - 1
mx_prompt db 'matrix> ', 0
mx_m_eq db ' = ', 0
mx_m_none db 'No matrices defined', 10, 0
mx_kw_list db 'list', 0
mx_kw_det db 'det', 0
mx_kw_trans db 'trans', 0
mx_kw_inv db 'inv', 0
mx_e_size db 'matrix sizes do not match', 0
mx_e_square db 'matrix is not square', 0
mx_e_singular db 'matrix is singular', 0
mx_e_ragged db 'rows have different lengths', 0
mx_e_big db 'larger than 6x6', 0
mx_e_complex db 'expression too complex', 0
mx_e_undef db 'undefined matrix', 0

align 8
mx_eps dq 1.0e-12
mx_snap dq 1.0e-10
mx_detval dq 0.0
mx_tnext dd 0
mx_target dd 0
mx_n dd 0
mx_aug dd 0
mx_want_inv db 0
mx_ready db 0
