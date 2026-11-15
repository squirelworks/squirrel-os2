; Squirrel-OS/2 — Matrices: a linear-algebra calculator in a window
; (C.9, OS2-APPS). Original code. run matrixgui   |   run matrixgui test
;
; Two matrices, A and B, up to 4 x 4, edited in a grid; results appear
; under it. Entries are any sci expression (2, -1.5, sqrt(2), pi/4),
; evaluated by the kernel's sci engine (SYS_GUI GUI_EVAL).
;
;   arrows          move between entries   Tab        edit A <-> B
;   a digit, - . (  starts typing an entry, Enter or an arrow keeps it,
;   or Enter        Esc drops it
;   Ctrl+arrows     fewer / more rows and columns (1 to 4)
;   +  -  *         A + B, A - B, A * B
;   d  i  t  k      determinant, inverse, transpose, rank of the matrix
;                   being edited
;   s               solves A X = B
;   c               copies the result into the matrix being edited
;   Esc             quit
;
; Determinant, inverse, solve and rank use Gauss-Jordan elimination with
; partial pivoting; a pivot below 1e-12 counts as 0 (singular), and
; entries below 1e-10 show as 0.
; "run matrixgui test" checks each operation on A = [1 2; 3 4] and
; B = [5 6; 7 8] and the error cases, and prints "matrixgui: PASS".
; See documentation/apps/topology.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

N           equ 4               ; largest size
MSIZE       equ N * N * 8       ; a matrix of doubles, rows of N
WCOLS       equ 2 * N           ; the work matrix: [M | I] or [A | B]
GX          equ 6               ; the editor grid
GY          equ 1 + WIN_TITLE_H + 14
CELL        equ 50              ; 8 characters and a margin
CROW        equ CELL_H + 4
RX          equ 6               ; the result grid
RY          equ GY + N * CROW + 20
OPS_X       equ GX + N * CELL + 8
EMAX        equ 40

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    call gui_open
    jc .nogfx
    mov dword [rows_a], 2
    mov dword [cols_a], 2
    mov dword [rows_b], 2
    mov dword [cols_b], 2
    mov dword [rows_r], -1      ; no result yet
    mov esi, [arg]
    cmp dword [esi], 'test'
    je selftest
.draw:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .key
    mov dword [msg], 0
    mov ebx, eax
    shr ebx, 8                  ; bl = scancode
    cmp byte [editing], 0
    jne .editkey
    test eax, 1 << 16
    jnz .resize
    cmp bl, K_ESC
    je .quit
    cmp bl, K_TAB
    je .tab
    cmp bl, K_ENTER
    je .startedit
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    cmp bl, K_DOWN
    je .d
    cmp al, '0'
    jb .notdigit
    cmp al, '9'
    jbe .starttyped
.notdigit:
    cmp al, '.'
    je .starttyped
    cmp al, '('
    je .starttyped
    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    cmp al, '*'
    je .mul
    cmp al, 'd'
    je .det
    cmp al, 'i'
    je .inv
    cmp al, 't'
    je .trans
    cmp al, 'k'
    je .rank
    cmp al, 's'
    je .solve
    cmp al, 'c'
    je .copy
    jmp .key
.starttyped:                    ; the key is the entry's first character
    mov [ebuf], al
    mov byte [ebuf+1], 0
    mov dword [elen], 1
    mov byte [editing], 1
    jmp .draw
.startedit:
    mov dword [elen], 0
    mov byte [ebuf], 0
    mov byte [editing], 1
    jmp .draw
.editkey:
    cmp bl, K_ESC
    je .cancel
    cmp bl, K_ENTER
    je .commit
    cmp bl, K_BKSP
    je .ebs
    cmp bl, K_LEFT
    je .cmove
    cmp bl, K_RIGHT
    je .cmove
    cmp bl, K_UP
    je .cmove
    cmp bl, K_DOWN
    je .cmove
    cmp al, ' '
    jb .key
    cmp al, '~'
    ja .key
    mov ecx, [elen]
    cmp ecx, EMAX
    jae .key
    mov [ebuf+ecx], al
    inc ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .draw
.ebs:
    mov ecx, [elen]
    test ecx, ecx
    jz .key
    dec ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .draw
.cancel:
    mov byte [editing], 0
    jmp .draw
.commit:
    call commit
    jmp .draw
.cmove:                         ; keep the entry, then move
    push ebx
    call commit
    pop ebx
    cmp byte [editing], 0
    jne .draw
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    jmp .d
.l:
    dec dword [ccol]
    jmp .clamp
.r:
    inc dword [ccol]
    jmp .clamp
.u:
    dec dword [crow]
    jmp .clamp
.d:
    inc dword [crow]
.clamp:
    call clamp_cursor
    jmp .draw
.resize:
    call cur_dims               ; esi = &rows, edi = &cols
    cmp bl, K_LEFT
    je .cminus
    cmp bl, K_RIGHT
    je .cplus
    cmp bl, K_UP
    je .rminus
    cmp bl, K_DOWN
    jne .key
    cmp dword [esi], N
    jae .key
    inc dword [esi]
    jmp .clamp
.rminus:
    cmp dword [esi], 1
    jbe .key
    dec dword [esi]
    jmp .clamp
.cplus:
    cmp dword [edi], N
    jae .key
    inc dword [edi]
    jmp .clamp
.cminus:
    cmp dword [edi], 1
    jbe .key
    dec dword [edi]
    jmp .clamp
.tab:
    xor byte [which], 1
    call clamp_cursor
    jmp .draw
.click:                         ; a click on an entry of the grid
    mov eax, [gui_mx]
    sub eax, GX
    jb .key
    mov ebx, [gui_my]
    sub ebx, GY
    jb .key
    xor edx, edx
    mov ecx, CELL
    div ecx
    push eax
    mov eax, ebx
    xor edx, edx
    mov ecx, CROW
    div ecx
    pop ecx
    mov [crow], eax
    mov [ccol], ecx
    call clamp_cursor
    jmp .draw
.add:
    call op_add
    jmp .draw
.sub:
    call op_sub
    jmp .draw
.mul:
    call op_mul
    jmp .draw
.det:
    call op_det
    jmp .draw
.inv:
    call op_inv
    jmp .draw
.trans:
    call op_trans
    jmp .draw
.rank:
    call op_rank
    jmp .draw
.solve:
    call op_solve
    jmp .draw
.copy:
    call op_copy
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; -> esi = &rows, edi = &cols, ebx = the matrix being edited
cur_dims:
    cmp byte [which], 0
    jne .b
    mov esi, rows_a
    mov edi, cols_a
    mov ebx, mat_a
    ret
.b:
    mov esi, rows_b
    mov edi, cols_b
    mov ebx, mat_b
    ret

clamp_cursor:
    pushad
    call cur_dims
    mov eax, [crow]
    test eax, eax
    jns .r0
    xor eax, eax
.r0:
    cmp eax, [esi]
    jb .r1
    mov eax, [esi]
    dec eax
.r1:
    mov [crow], eax
    mov eax, [ccol]
    test eax, eax
    jns .c0
    xor eax, eax
.c0:
    cmp eax, [edi]
    jb .c1
    mov eax, [edi]
    dec eax
.c1:
    mov [ccol], eax
    popad
    ret

; ebuf -> the entry under the cursor, through the sci engine. On an error
; the editor stays open with the message.
commit:
    pushad
    cmp dword [elen], 0
    je .done
    mov dword [ev+GE_EXPR], ebuf
    mov dword [ev+GE_FLAGS], 0
    mov dword [ev+GE_TEXT], etext
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    test eax, eax
    jnz .err
    call cur_dims
    mov eax, [crow]
    shl eax, 2
    add eax, [ccol]
    fld qword [ev+GE_RESULT]
    fstp qword [ebx+eax*8]
.done:
    mov byte [editing], 0
    popad
    ret
.err:
    mov dword [msg], etext_msg
    mov edi, etext_msg
    mov esi, s_error
    call scopy
    mov esi, etext
    call scopy
    cmp byte [edi-1], ' '
    jne .r
    mov eax, [ev+GE_COL]
    call gui_utoa
.r:
    popad
    ret

; ---------- operations: results in mat_r (rows_r x cols_r), or a number
; in val with rows_r = 0; rlabel names it; msg on an error ----------
op_add:
    mov dword [rlabel], s_add
    mov byte [sign], 0
    jmp addsub
op_sub:
    mov dword [rlabel], s_sub
    mov byte [sign], 1
addsub:
    mov eax, [rows_a]
    cmp eax, [rows_b]
    jne sizes
    mov ecx, [cols_a]
    cmp ecx, [cols_b]
    jne sizes
    mov [rows_r], eax
    mov [cols_r], ecx
    xor esi, esi
.i:
    cmp esi, N * N
    jae .done
    fld qword [mat_a+esi*8]
    fld qword [mat_b+esi*8]
    cmp byte [sign], 0
    je .p
    fchs
.p:
    faddp st1, st0
    fstp qword [mat_r+esi*8]
    inc esi
    jmp .i
.done:
    ret

op_mul:
    mov dword [rlabel], s_mul
    mov eax, [cols_a]
    cmp eax, [rows_b]
    jne sizes
    mov eax, [rows_a]
    mov [rows_r], eax
    mov eax, [cols_b]
    mov [cols_r], eax
    xor esi, esi                ; row of A
.r:
    cmp esi, [rows_a]
    jae .done
    xor edi, edi                ; column of B
.c:
    cmp edi, [cols_b]
    jae .nr
    fldz
    xor ecx, ecx
.k:
    cmp ecx, [cols_a]
    jae .put
    lea eax, [esi*4+ecx]
    fld qword [mat_a+eax*8]
    lea eax, [ecx*4+edi]
    fmul qword [mat_b+eax*8]
    faddp st1, st0
    inc ecx
    jmp .k
.put:
    lea eax, [esi*4+edi]
    fstp qword [mat_r+eax*8]
    inc edi
    jmp .c
.nr:
    inc esi
    jmp .r
.done:
    ret

sizes:
    mov dword [msg], m_sizes
    mov dword [rows_r], -1
    ret

op_trans:
    call cur_dims
    mov dword [rlabel], s_trans_a
    cmp byte [which], 0
    je .l
    mov dword [rlabel], s_trans_b
.l:
    mov eax, [esi]
    mov [cols_r], eax
    mov eax, [edi]
    mov [rows_r], eax
    xor ecx, ecx
.r:
    cmp ecx, [esi]
    jae .done
    xor edx, edx
.c:
    cmp edx, [edi]
    jae .nr
    lea eax, [ecx*4+edx]
    fld qword [ebx+eax*8]
    lea eax, [edx*4+ecx]
    fstp qword [mat_r+eax*8]
    inc edx
    jmp .c
.nr:
    inc ecx
    jmp .r
.done:
    ret

; The matrix being edited -> work (its columns only); edx = its rows,
; ecx = its columns
load_work:
    call cur_dims
    mov edx, [esi]
    mov ecx, [edi]
    push ecx
    push edx
    call clear_work
    xor esi, esi
.r:
    cmp esi, edx
    jae .done
    xor edi, edi
.c:
    cmp edi, ecx
    jae .nr
    lea eax, [esi*4+edi]
    fld qword [ebx+eax*8]
    lea eax, [esi*WCOLS+edi]
    fstp qword [work+eax*8]
    inc edi
    jmp .c
.nr:
    inc esi
    jmp .r
.done:
    pop edx
    pop ecx
    ret

clear_work:
    push eax
    push ecx
    push edi
    mov edi, work
    mov ecx, N * WCOLS * 2
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret

op_det:
    mov dword [rlabel], s_det_a
    cmp byte [which], 0
    je .l
    mov dword [rlabel], s_det_b
.l:
    call load_work
    cmp edx, ecx
    jne square
    mov [wrows], edx
    mov [wcols], ecx
    mov [pcols], ecx
    call gauss_jordan
    mov dword [rows_r], 0       ; a number
    fld qword [det]
    mov eax, [rank]
    cmp eax, [wrows]
    je .v
    fstp st0
    fldz
.v:
    fstp qword [val]
    ret

square:
    mov dword [msg], m_square
    mov dword [rows_r], -1
    ret

op_rank:
    mov dword [rlabel], s_rank_a
    cmp byte [which], 0
    je .l
    mov dword [rlabel], s_rank_b
.l:
    call load_work
    mov [wrows], edx
    mov [wcols], ecx
    mov [pcols], ecx
    call gauss_jordan
    mov dword [rows_r], 0
    fild dword [rank]
    fstp qword [val]
    ret

op_inv:
    mov dword [rlabel], s_inv_a
    cmp byte [which], 0
    je .l
    mov dword [rlabel], s_inv_b
.l:
    call load_work
    cmp edx, ecx
    jne square
    ; [M | I]
    xor esi, esi
.i:
    cmp esi, edx
    jae .go
    lea eax, [esi*WCOLS+esi]
    add eax, ecx
    fld1
    fstp qword [work+eax*8]
    inc esi
    jmp .i
.go:
    mov [wrows], edx
    lea eax, [ecx+ecx]
    mov [wcols], eax
    mov [pcols], ecx
    call gauss_jordan
    mov eax, [rank]
    cmp eax, [wrows]
    jne singular
    mov eax, [pcols]
    jmp right_half

singular:
    mov dword [msg], m_singular
    mov dword [rows_r], -1
    ret

; solve A X = B: [A | B]
op_solve:
    mov dword [rlabel], s_solve
    mov eax, [rows_a]
    cmp eax, [cols_a]
    jne square
    cmp eax, [rows_b]
    jne sizes
    mov byte [which], 0
    call load_work
    mov byte [which], 0
    xor esi, esi
.r:
    cmp esi, [rows_b]
    jae .go
    xor edi, edi
.c:
    cmp edi, [cols_b]
    jae .nr
    lea eax, [esi*4+edi]
    fld qword [mat_b+eax*8]
    lea eax, [esi*WCOLS+edi]
    add eax, [cols_a]
    fstp qword [work+eax*8]
    inc edi
    jmp .c
.nr:
    inc esi
    jmp .r
.go:
    mov eax, [rows_a]
    mov [wrows], eax
    mov eax, [cols_a]
    add eax, [cols_b]
    mov [wcols], eax
    mov eax, [cols_a]
    mov [pcols], eax
    call gauss_jordan
    mov eax, [rank]
    cmp eax, [wrows]
    jne singular
    mov eax, [cols_a]
    ; the right part of work -> the result
right_half:                     ; eax = first column of it
    mov ecx, [wcols]
    sub ecx, eax
    mov [cols_r], ecx
    mov edx, [wrows]
    mov [rows_r], edx
    xor esi, esi
.r:
    cmp esi, edx
    jae .done
    xor edi, edi
.c:
    cmp edi, ecx
    jae .nr
    push eax
    lea eax, [esi*WCOLS+eax]
    add eax, edi
    fld qword [work+eax*8]
    lea eax, [esi*4+edi]
    fstp qword [mat_r+eax*8]
    pop eax
    inc edi
    jmp .c
.nr:
    inc esi
    jmp .r
.done:
    ret

; The result into the matrix being edited.
op_copy:
    cmp dword [rows_r], 0
    jle .no
    call cur_dims
    mov eax, [rows_r]
    mov [esi], eax
    mov eax, [cols_r]
    mov [edi], eax
    mov esi, mat_r
    mov edi, ebx
    mov ecx, MSIZE / 4
    rep movsd
    call clamp_cursor
    ret
.no:
    mov dword [msg], m_nocopy
    ret

; Gauss-Jordan on work (wrows x wcols) over its first pcols columns, with
; partial pivoting: rank = pivots found, det = their product with the
; sign of the row swaps (for a square left part with rank = rows).
gauss_jordan:
    pushad
    fld1
    fstp qword [det]
    xor ebx, ebx                ; rank: the next pivot row
    xor esi, esi                ; column
.col:
    cmp esi, [pcols]
    jae .done
    cmp ebx, [wrows]
    jae .done
    ; the row with the largest |entry| in this column, from row ebx
    mov edx, ebx
    mov ecx, ebx
    fldz
.f:
    cmp ecx, [wrows]
    jae .found
    lea eax, [ecx*WCOLS+esi]
    fld qword [work+eax*8]
    fabs
    fcomi st0, st1
    jbe .small
    fstp st1
    mov edx, ecx
    jmp .nf
.small:
    fstp st0
.nf:
    inc ecx
    jmp .f
.found:
    fld qword [f_pivot]
    fcomip st0, st1
    fstp st0
    jae .next                   ; no pivot: the column is dependent
    cmp edx, ebx                ; swap rows edx and ebx
    je .noswap
    xor ecx, ecx
.sw:
    lea eax, [edx*WCOLS+ecx]
    lea edi, [ebx*WCOLS+ecx]
    fld qword [work+eax*8]
    fld qword [work+edi*8]
    fstp qword [work+eax*8]
    fstp qword [work+edi*8]
    inc ecx
    cmp ecx, WCOLS
    jb .sw
    fld qword [det]
    fchs
    fstp qword [det]
.noswap:
    ; det *= pivot; the pivot row / pivot
    lea eax, [ebx*WCOLS+esi]
    fld qword [work+eax*8]
    fld st0
    fmul qword [det]
    fstp qword [det]
    xor ecx, ecx
.div:
    lea eax, [ebx*WCOLS+ecx]
    fld qword [work+eax*8]
    fdiv st0, st1
    fstp qword [work+eax*8]
    inc ecx
    cmp ecx, WCOLS
    jb .div
    fstp st0
    ; every other row: row -= entry * pivot row
    xor edx, edx
.row:
    cmp edx, [wrows]
    jae .rows_done
    cmp edx, ebx
    je .nrow
    lea eax, [edx*WCOLS+esi]
    fld qword [work+eax*8]      ; the factor
    xor ecx, ecx
.e:
    lea eax, [ebx*WCOLS+ecx]
    fld qword [work+eax*8]
    fmul st0, st1
    lea eax, [edx*WCOLS+ecx]
    fsubr qword [work+eax*8]
    fstp qword [work+eax*8]
    inc ecx
    cmp ecx, WCOLS
    jb .e
    fstp st0
.nrow:
    inc edx
    jmp .row
.rows_done:
    inc ebx
.next:
    inc esi
    jmp .col
.done:
    mov [rank], ebx
    popad
    ret

; ---------- drawing ----------
draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    ; "Editing A (2 x 3)"
    call cur_dims
    mov eax, [esi]
    mov [g_rows], eax
    mov eax, [edi]
    mov [g_cols], eax
    mov edi, line
    mov esi, s_editing
    call scopy
    mov al, 'A'
    add al, [which]
    stosb
    mov ax, ' ('
    stosw
    mov eax, [g_rows]
    call gui_utoa
    mov esi, s_by
    call scopy
    mov eax, [g_cols]
    call gui_utoa
    mov al, ')'
    stosb
    mov byte [edi], 0
    mov eax, GX
    mov ebx, GY - CELL_H - 3
    mov esi, line
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    ; the grid being edited
    call cur_dims
    mov ebp, ebx
    mov eax, GX
    mov ebx, GY
    mov ecx, [esi]
    mov edx, [edi]
    mov byte [editgrid], 1
    call grid
    mov byte [editgrid], 0
    ; the result
    cmp dword [msg], 0
    jne .msg
    mov eax, [rows_r]
    test eax, eax
    js .ops
    mov esi, [rlabel]
    mov eax, RX
    mov ebx, RY - CELL_H - 3
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    cmp dword [rows_r], 0
    jne .rgrid
    call gui_textw              ; a number: after the label
    lea edi, [eax+RX+CELL_W]
    fld qword [val]
    fstp qword [cellv]
    call cell_text
    mov esi, line
    mov eax, edi
    call gui_text
    jmp .ops
.rgrid:
    mov ebp, mat_r
    mov eax, RX
    mov ebx, RY
    mov ecx, [rows_r]
    mov edx, [cols_r]
    call grid
    jmp .ops
.msg:
    mov esi, [msg]
    mov eax, RX
    mov ebx, RY - CELL_H - 3
    mov byte [gui_ink], C_RED
    mov byte [gui_bg], C_LGREY
    call gui_text
.ops:
    ; the keys, on the right
    mov esi, ops_help
    mov eax, OPS_X
    mov ebx, GY
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
.oh:
    cmp byte [esi], 0
    je .ohd
    call gui_text
.skip:
    inc esi
    cmp byte [esi-1], 0
    jne .skip
    add ebx, CELL_H + 1
    jmp .oh
.ohd:
    mov esi, s_help
    mov eax, GX
    mov ebx, SCR_H - CELL_H - 3
    call gui_text
    call gui_flip
    popad
    ret

; ebp = a matrix, eax, ebx = where, ecx = rows, edx = columns: white
; cells with the values; with editgrid the cursor's cell is blue (and
; shows the text being typed).
grid:
    pushad
    mov [g_x], eax
    mov [g_y], ebx
    mov [g_rows], ecx
    mov [g_cols], edx
    xor esi, esi                ; row
.r:
    cmp esi, [g_rows]
    jae .done
    xor edi, edi                ; column
.c:
    cmp edi, [g_cols]
    jae .nr
    imul eax, edi, CELL
    add eax, [g_x]
    imul ebx, esi, CROW
    add ebx, [g_y]
    mov ecx, CELL - 2
    mov edx, CROW - 2
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_WHITE
    mov byte [g_cur], 0
    cmp byte [editgrid], 0
    je .f
    cmp esi, [crow]
    jne .f
    cmp edi, [ccol]
    jne .f
    mov byte [g_cur], 1
    mov byte [gui_ink], C_BLUE
    mov byte [gui_bg], C_BLUE
.f:
    call gui_fill
    push eax
    push ebx
    lea eax, [esi*4+edi]
    fld qword [ebp+eax*8]
    fstp qword [cellv]
    call cell_text              ; -> line
    cmp byte [g_cur], 0
    je .t
    cmp byte [editing], 0
    je .t
    push esi                    ; the text being typed, its end shown
    push edi
    mov esi, ebuf
    mov eax, [elen]
    sub eax, 7
    jbe .whole
    add esi, eax
.whole:
    mov edi, line
    call scopy
    mov ax, '_'
    stosw
    pop edi
    pop esi
.t:
    pop ebx
    pop eax
    add eax, 2
    add ebx, 2
    mov byte [gui_ink], C_BLACK
    cmp byte [g_cur], 0
    je .ink
    mov byte [gui_ink], C_WHITE
.ink:
    push esi
    mov esi, line
    mov ecx, CELL - 4
    call gui_textn
    pop esi
    inc edi
    jmp .c
.nr:
    inc esi
    jmp .r
.done:
    popad
    ret

; cellv -> line: the value in at most 8 characters. It is rounded to 4
; decimals, then fewer while the text is longer; noise below 1e-10 is 0.
cell_text:
    pushad
    fld qword [cellv]
    fabs
    fld qword [f_noise]
    fcomip st0, st1
    fstp st0
    jbe .go
    fldz
    fstp qword [cellv]
.go:
    mov ebp, 4                  ; decimals
.try:
    fld qword [cellv]
    fld qword [pow10+ebp*8]
    fmul st1, st0
    fxch
    frndint
    fdivrp st1, st0             ; round(v * 10^d) / 10^d
    fstp qword [ev+GE_X]
    mov dword [ev+GE_EXPR], s_x
    mov dword [ev+GE_FLAGS], GEF_X
    mov dword [ev+GE_TEXT], line
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    mov esi, line
    call strlen
    cmp eax, 8
    jbe .r
    dec ebp
    jns .try
    mov dword [line], '####'    ; too wide even as a whole number
    mov dword [line+4], 0
.r:
    popad
    ret

; esi -> eax = its length
strlen:
    xor eax, eax
.c:
    cmp byte [esi+eax], 0
    je .r
    inc eax
    jmp .c
.r:
    ret

; edi -> edi at its zero
strend:
    cmp byte [edi], 0
    je .r
    inc edi
    jmp strend
.r:
    ret

scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
    ret

; ---------- self-check ----------
; esi = expected doubles (row by row), ecx = rows, edx = columns: CF
; unless mat_r has that size and those values (to 1e-9).
expect_r:
    pushad
    cmp [rows_r], ecx
    jne .no
    cmp [cols_r], edx
    jne .no
    xor ebx, ebx
.r:
    cmp ebx, ecx
    jae .yes
    xor edi, edi
.c:
    cmp edi, edx
    jae .nr
    lea eax, [ebx*4+edi]
    fld qword [mat_r+eax*8]
    fsub qword [esi]
    fabs
    fld qword [f_check]
    fcomip st0, st1
    fstp st0
    jbe .no
    add esi, 8
    inc edi
    jmp .c
.nr:
    inc ebx
    jmp .r
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = 4 doubles -> the 2 x 2 matrix ebx (rows of N)
set22:
    pushad
    fld qword [esi]
    fstp qword [ebx]
    fld qword [esi+8]
    fstp qword [ebx+8]
    fld qword [esi+16]
    fstp qword [ebx+32]
    fld qword [esi+24]
    fstp qword [ebx+40]
    popad
    ret

selftest:
    mov esi, t_a
    mov ebx, mat_a
    call set22
    mov esi, t_b
    mov ebx, mat_b
    call set22
    mov byte [bad], '*'
    call op_mul
    mov esi, t_ab
    mov ecx, 2
    mov edx, 2
    call expect_r
    jc .fail
    mov byte [bad], '+'
    call op_add
    mov esi, t_apb
    call expect_r
    jc .fail
    mov byte [bad], 'd'         ; det A = -2
    mov byte [which], 0
    call op_det
    fld qword [val]
    fadd qword [f_two]
    fabs
    fld qword [f_check]
    fcomip st0, st1
    fstp st0
    jbe .fail
    mov byte [bad], 'i'
    call op_inv
    mov esi, t_inva
    mov ecx, 2
    mov edx, 2
    call expect_r
    jc .fail
    mov byte [bad], 's'         ; A X = B
    call op_solve
    mov esi, t_x
    call expect_r
    jc .fail
    mov byte [bad], 't'
    call op_trans
    mov esi, t_ta
    call expect_r
    jc .fail
    mov byte [bad], 'k'         ; rank [1 2; 2 4] = 1, and it is singular
    mov esi, t_sing
    mov ebx, mat_a
    call set22
    call op_rank
    fld qword [val]
    fld1
    fcomip st0, st1
    fstp st0
    jne .fail
    mov byte [bad], 'z'
    call op_inv
    cmp dword [msg], m_singular
    jne .fail
    mov byte [bad], 'm'         ; A 2 x 2 + B 2 x 3: sizes do not match
    mov dword [msg], 0
    mov dword [cols_b], 3
    call op_add
    cmp dword [msg], m_sizes
    jne .fail
    mov byte [bad], 'e'         ; an entry typed as an expression
    mov dword [msg], 0
    mov byte [which], 0
    mov dword [crow], 1
    mov dword [ccol], 1
    mov esi, t_expr
    mov edi, ebuf
    call scopy
    mov dword [elen], 7
    call commit
    fld qword [mat_a+40]
    fsub qword [f_two]
    fabs
    fld qword [f_check]
    fcomip st0, st1
    fstp st0
    jbe .fail
    call gui_close
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.fail:
    call gui_close
    mov esi, fail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov eax, 1
    ret

; ---------- data ----------
align 8
pow10 dq 1.0, 10.0, 100.0, 1000.0, 10000.0
f_pivot dq 1.0e-12
f_noise dq 1.0e-10
f_check dq 1.0e-9
f_two dq 2.0
t_a dq 1.0, 2.0, 3.0, 4.0
t_b dq 5.0, 6.0, 7.0, 8.0
t_ab dq 19.0, 22.0, 43.0, 50.0
t_apb dq 6.0, 8.0, 10.0, 12.0
t_inva dq -2.0, 1.0, 1.5, -0.5
t_x dq -3.0, -4.0, 4.0, 5.0
t_ta dq 1.0, 3.0, 2.0, 4.0
t_sing dq 1.0, 2.0, 2.0, 4.0
t_expr db 'sqrt(4)', 0
title db 'Matrices', 0
s_x db 'x', 0
s_by db ' x ', 0
s_editing db 'Editing ', 0
s_add db 'A + B =', 0
s_sub db 'A - B =', 0
s_mul db 'A * B =', 0
s_det_a db 'det A =', 0
s_det_b db 'det B =', 0
s_rank_a db 'rank A =', 0
s_rank_b db 'rank B =', 0
s_inv_a db 'inv A =', 0
s_inv_b db 'inv B =', 0
s_trans_a db 'trans A =', 0
s_trans_b db 'trans B =', 0
s_solve db 'X with A X = B:', 0
s_error db 'Error: ', 0
m_sizes db 'The sizes do not match', 0
m_square db 'The matrix is not square', 0
m_singular db 'The matrix is singular', 0
m_nocopy db 'No matrix result to copy', 0
ops_help:
    db '+ - *  A+B A-B AB', 0
    db 'd  determinant', 0
    db 'i  inverse', 0
    db 't  transpose', 0
    db 'k  rank', 0
    db 's  solve A X = B', 0
    db 'c  result here', 0
    db 'Tab  A <-> B', 0
    db 'Ctrl+arrows size', 0
    db 0
s_help db 'Type an entry (sqrt(2) works)  Esc: quit', 0
m_nogfx db 'matrixgui: no graphics', 10, 0
pass db 'matrixgui: PASS', 10, 0
fail db 'matrixgui: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 8
mat_a resq N * N
mat_b resq N * N
mat_r resq N * N
work resq N * WCOLS
det resq 1
val resq 1
cellv resq 1
arg resd 1
rows_a resd 1
cols_a resd 1
rows_b resd 1
cols_b resd 1
rows_r resd 1
cols_r resd 1
crow resd 1
ccol resd 1
elen resd 1
msg resd 1
rlabel resd 1
wrows resd 1
wcols resd 1
pcols resd 1
rank resd 1
g_x resd 1
g_y resd 1
g_rows resd 1
g_cols resd 1
which resb 1
editing resb 1
editgrid resb 1
sign resb 1
g_cur resb 4
ev resb GE_SIZE
etext resb 40
etext_msg resb 64
ebuf resb EMAX + 2
line resb 128
SQX_END
