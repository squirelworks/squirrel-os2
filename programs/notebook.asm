; Squirrel-OS/2 — Notebook: pages of notes, Nut code, graphs, tables
; and geometry that work together (C.8, OS2-APPS). Original code.
; run notebook [file]  |  run notebook test
;
; A notebook is a list of cells, run from the top. Every cell shares the
; Nut variables (programs/nut.inc, documentation/apps/nut.md):
;   note    text; a line that starts with "# " is a heading
;   code    a Nut program; what it prints is shown under it
;   graph   one curve a line (an expression in x, "y =" may come
;           first); "x: a b" and "y: a b" set the ranges (y is found
;           from the values when it is not given)
;   table   rows of cells split by |: a number, text, or =expression.
;           Each cell is the variable A1, B1, ... (column, row), for the
;           cells after it and for the cells below the table
;   geo     A = (x, y) points; seg A B, line A B, circle A B (through B),
;           circle A r, poly A B C ...; dist A B, angle A B C (at B,
;           degrees), area A B C ... are measured ("d = dist A B" also
;           makes d a variable)
;
;   Up / Down: the cell before / after   PgUp / PgDn, Home / End
;   Enter (or a click on the chosen cell): edit it; Esc ends the edit
;   and runs the notebook again
;   N C G T O: a new note, code, graph, table or geometry cell after
;   this one   Del: remove the cell   Ctrl+Up / Ctrl+Down: move it
;   Ctrl+R: run all   Ctrl+S: save   Esc: quit
;
; The file is text: each cell starts with a line "%% kind".
; "run notebook test" checks the Nut language and a notebook (every kind
; of cell, editing, moving, saving and loading); it prints
; "notebook: PASS". See documentation/apps/notebook.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

MAXCELL     equ 32
SLOT        equ 2048                    ; a cell's text
SRCMAX      equ SLOT - 1
OUTPOOL     equ 32768                   ; what the cells show
GPOOL       equ 32768                   ; graph values, geometry shapes
FBUF        equ MAXCELL * (SLOT + 16) + 16
NAME_MAX    equ 60

C_KIND      equ 0                       ; a cell
C_LEN       equ 4
C_SRC       equ 8
C_OUT       equ 12                      ; its output: offset, length
C_OLEN      equ 16
C_G         equ 20                      ; its graph / shapes (-1: none)
C_H         equ 24                      ; pixels, from layout
C_Y         equ 28
CSIZE       equ 32

K_NOTE      equ 0
K_CODE      equ 1
K_GRAPH     equ 2
K_TABLE     equ 3
K_GEO       equ 4
K_MATH      equ 5

X0          equ 8                       ; the page
COLS        equ 51
VY0         equ WIN_TITLE_H + 2
STAT_Y      equ SCR_H - CELL_H - 2
VH          equ STAT_Y - 1 - VY0
ER          equ VH / CELL_H             ; editor rows
PAD         equ 2
GAP         equ 3
GW          equ 300                     ; a graph / figure box
GH          equ 72
GEOH        equ 96
NCURVE      equ 4
GHDR        equ 48                      ; graph: n, -, xa, xb, ya, yb
GOHDR       equ 32                      ; figure: n, -, cx, cy, scale
PSIZE       equ 48                      ; a shape: type, -, name, 4 numbers
P_PT        equ 1
P_SEG       equ 2
P_LINE      equ 3
P_CIRC      equ 4
GPTMAX      equ 32                      ; points of one figure
GPT_SIZE    equ 24                      ; name (8), x, y
TCOLMAX     equ 6
TROWMAX     equ 40

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    call nut_init
    jc .nomem
    call sqm_init
    jc .nomem
    mov dword [sqm_get], nut_getnum
    mov dword [sqm_set], math_set
    mov eax, SYS_SBRK
    mov ebx, MAXCELL * SLOT + OUTPOOL + GPOOL + FBUF
    int 0x80
    cmp eax, -1
    je .nomem
    mov [slots], eax
    add eax, MAXCELL * SLOT
    mov [opool], eax
    add eax, OUTPOOL
    mov [gpool], eax
    add eax, GPOOL
    mov [fbuf], eax
    call init_cells
    mov esi, s_default
    mov edi, fname
    call scopy
    mov esi, [arg]
    test esi, esi
    jz .open
    cmp dword [esi], 'test'
    jne .file
    cmp byte [esi+4], 0
    je selftest
.file:
    cmp byte [esi], 0
    je .open
    mov edi, fname
    call copy_name
    call load
.open:
    call gui_open
    jc .nogfx
    call run_all
    call ensure_vis
.loop:
    call draw
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .loop
    call key
    jnc .loop
    call gui_close
    xor eax, eax
    ret
.click:
    call click
    jmp .loop
.nogfx:
    mov esi, m_nogfx
    call gui_puts
.nomem:
    mov eax, 1
    ret

; ---------- cells ----------
; Every record owns a text slot, also past ncell; inserting and removing
; move the records and hand the slots round.
init_cells:
    pushad
    mov edi, cells
    mov edx, [slots]
    mov ebx, MAXCELL
.c:
    push edi
    xor eax, eax
    mov ecx, CSIZE / 4
    rep stosd
    pop edi
    mov [edi+C_SRC], edx
    mov dword [edi+C_G], -1
    mov byte [edx], 0
    add edx, SLOT
    add edi, CSIZE
    dec ebx
    jnz .c
    mov dword [ncell], 0
    mov dword [sel], -1
    mov dword [scroll], 0
    mov dword [doch], 0
    popad
    ret

; eax = index -> ebp = its record
cell_ptr:
    mov ebp, eax
    shl ebp, 5
    add ebp, cells
    ret

; eax = where, ecx = kind -> ebp = a new empty cell there, or CF (full)
insert_cell:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov edx, [ncell]
    cmp edx, MAXCELL
    jae .full
    push eax
    mov eax, edx
    call cell_ptr
    mov ebx, [ebp+C_SRC]        ; the spare slot
    pop eax
    mov ecx, edx
.s:
    cmp ecx, eax
    jbe .put
    push eax
    mov eax, ecx
    call cell_ptr
    lea esi, [ebp-CSIZE]
    mov edi, ebp
    push ecx
    mov ecx, CSIZE / 4
    rep movsd
    pop ecx
    pop eax
    dec ecx
    jmp .s
.put:
    call cell_ptr
    mov edi, ebp
    push eax
    xor eax, eax
    mov ecx, CSIZE / 4
    rep stosd
    pop eax
    mov ecx, [esp+12]
    mov [ebp+C_KIND], cl
    mov [ebp+C_SRC], ebx
    mov byte [ebx], 0
    mov dword [ebp+C_G], -1
    inc dword [ncell]
    clc
    jmp .r
.full:
    stc
.r:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; eax = index: the cell goes; its slot moves to the end
delete_cell:
    pushad
    call cell_ptr
    mov ebx, [ebp+C_SRC]
    mov ecx, [ncell]
    dec ecx
    mov [ncell], ecx
.s:
    cmp eax, ecx
    jae .last
    call cell_ptr
    lea esi, [ebp+CSIZE]
    mov edi, ebp
    push ecx
    mov ecx, CSIZE / 4
    rep movsd
    pop ecx
    inc eax
    jmp .s
.last:
    call cell_ptr
    mov [ebp+C_SRC], ebx
    popad
    ret

; eax = index: the cell and the next change places
swap_cells:
    pushad
    call cell_ptr
    mov ecx, CSIZE / 4
.s:
    mov edx, [ebp]
    xchg edx, [ebp+CSIZE]
    mov [ebp], edx
    add ebp, 4
    loop .s
    popad
    ret

; ---------- running ----------
run_all:
    pushad
    fninit
    call nut_reset
    call sqm_reset
    mov dword [opos], 0
    mov dword [gpos], 0
    xor eax, eax
.c:
    cmp eax, [ncell]
    jae .done
    push eax
    call cell_ptr
    mov ecx, [opos]
    mov [ebp+C_OUT], ecx
    mov [ostart], ecx
    mov dword [ebp+C_G], -1
    mov dword [lno], 0
    movzx ebx, byte [ebp+C_KIND]
    call [run_fn+ebx*4]
    fninit
    mov ecx, [opos]
    sub ecx, [ebp+C_OUT]
    mov [ebp+C_OLEN], ecx
    pop eax
    inc eax
    jmp .c
.done:
    call layout
    popad
    ret
run_none:
    ret

; ebp = a math cell: each line through sqmath
run_math:
    pushad
    mov eax, [ebp+C_SRC]
    mov [lp], eax
.l:
    call src_line
    jc .r
    mov esi, lbuf
    call skipsp
    push esi
    call sqm_line
    pop esi
    jc .err
    mov eax, [sqm_kind]
    cmp eax, SK_NONE
    je .l
    cmp eax, SK_VALUE
    jne .show
    call out_s                  ; "the line = its value"
    mov esi, s_eq
    call out_s
.show:
    mov esi, sqm_out
    call out_s
    mov al, 10
    call out_c
    jmp .l
.err:
    mov esi, [sqm_err]
    call out_err
    jmp .l
.r:
    popad
    ret

; esi, ecx = a name, st0 = a value from a math cell: a Nut variable too
math_set:
    push eax
    mov eax, V_NUM
    call nut_setvar
    pop eax
    ret

; ebp = a code cell
run_code:
    pushad
    mov dword [nut_olen], 0
    mov eax, [nut_out]
    mov byte [eax], 0
    mov esi, [ebp+C_SRC]
    call nut_run
    pushfd
    mov esi, [nut_out]
    mov ecx, [nut_olen]
    call out_n
    popfd
    jnc .r
    mov eax, [nut_errline]
    mov [lno], eax
    mov esi, [nut_errmsg]
    call out_err
.r:
    popad
    ret

; ebp = a graph cell: every curve worked out at GW values of x
run_graph:
    pushad
    mov eax, [ebp+C_SRC]
    mov [lp], eax
    fld qword [f_m10]
    fstp qword [gxa]
    fld qword [f_10]
    fstp qword [gxb]
    mov byte [yauto], 1
    mov dword [ncurve], 0
.l:
    call src_line
    jc .eval
    mov esi, lbuf
    call skipsp
    mov al, [esi]
    test al, al
    jz .l
    cmp al, '#'
    je .l
    or al, 0x20
    cmp byte [esi+1], ':'
    jne .curve
    cmp al, 'x'
    je .xr
    cmp al, 'y'
    je .yr
    jmp .curve
.xr:
    add esi, 2
    call two_nums
    jc .err
    call range_ok
    jc .l
    fld qword [t1]
    fstp qword [gxa]
    fld qword [t2]
    fstp qword [gxb]
    jmp .l
.yr:
    add esi, 2
    call two_nums
    jc .err
    call range_ok
    jc .l
    fld qword [t1]
    fstp qword [gya]
    fld qword [t2]
    fstp qword [gyb]
    mov byte [yauto], 0
    jmp .l
.err:
    mov esi, [nut_errmsg]
    call out_err
    jmp .l
.curve:
    cmp al, 'y'                 ; "y = ..." -> the expression
    jne .c2
    push esi
    inc esi
    call skipsp
    cmp byte [esi], '='
    jne .ny
    cmp byte [esi+1], '='
    je .ny
    inc esi
    call skipsp
    add esp, 4
    jmp .c2
.ny:
    pop esi
.c2:
    cmp dword [ncurve], NCURVE
    jae .many
    push esi
    call nut_compile
    pop esi
    jc .err
    mov ecx, [ncurve]
    mov [ctok+ecx*4], eax
    inc dword [ncurve]
    push esi
    mov esi, s_yeq
    call out_s
    pop esi
    call out_s
    mov al, 10
    call out_c
    jmp .l
.many:
    mov esi, m_four
    call out_err
    jmp .l
.eval:
    mov dword [lno], 0
    mov ecx, [ncurve]
    imul eax, ecx, GW * 4
    add eax, GHDR
    mov edx, [gpos]
    add eax, edx
    cmp eax, GPOOL
    ja .full
    mov [gpos], eax
    mov [ebp+C_G], edx
    add edx, [gpool]
    mov [gptr], edx
    mov [edx], ecx
    fld qword [gxb]
    fsub qword [gxa]
    mov dword [tmpi], GW - 1
    fidiv dword [tmpi]
    fstp qword [gdx]
    lea edi, [edx+GHDR]
    xor ebx, ebx                ; the curve
.cv:
    cmp ebx, [ncurve]
    jae .scale
    mov dword [gdef], 0
    mov dword [nut_errmsg], 0
    xor esi, esi                ; the column
.pt:
    cmp esi, GW
    jae .cdone
    mov [tmpi], esi
    fild dword [tmpi]
    fmul qword [gdx]
    fadd qword [gxa]
    fstp qword [nut_x]
    mov eax, [ctok+ebx*4]
    call nut_eval_x
    jc .nan
    fstp dword [edi]
    mov eax, [edi]
    and eax, 0x7F800000
    cmp eax, 0x7F800000
    je .pn
    inc dword [gdef]
    jmp .pn
.nan:
    mov dword [edi], 0x7FC00000
.pn:
    add edi, 4
    inc esi
    jmp .pt
.cdone:
    cmp dword [gdef], 0         ; not one value: say why
    jne .cn
    call out_nlfix
    mov esi, s_bangc
    call out_s
    lea eax, [ebx+1]
    call out_dec
    mov esi, s_colon
    call out_s
    mov esi, [nut_errmsg]
    test esi, esi
    jnz .cm
    mov esi, m_nopts
.cm:
    call out_s
    mov al, 10
    call out_c
.cn:
    inc ebx
    jmp .cv
.scale:
    cmp byte [yauto], 0
    je .store
    call auto_y
.store:
    mov edx, [gptr]
    fld qword [gxa]
    fstp qword [edx+8]
    fld qword [gxb]
    fstp qword [edx+16]
    fld qword [gya]
    fstp qword [edx+24]
    fld qword [gyb]
    fstp qword [edx+32]
    mov esi, s_xr               ; "x: a .. b   y: c .. d"
    call out_s
    fld qword [gxa]
    call out_num
    mov esi, s_to
    call out_s
    fld qword [gxb]
    call out_num
    mov esi, s_yr
    call out_s
    fld qword [gya]
    call out_num
    mov esi, s_to
    call out_s
    fld qword [gyb]
    call out_num
    mov al, 10
    call out_c
    popad
    ret
.full:
    mov esi, m_nomem
    call out_err
    popad
    ret

; [t1] < [t2], or CF with the error shown
range_ok:
    fld qword [t2]
    fld qword [t1]
    fcomip st1
    fstp st0
    jb .ok
    push esi
    mov esi, m_range
    call out_err
    pop esi
    stc
    ret
.ok:
    clc
    ret

; gya, gyb from the values at [gptr]: rounded out to a tenth of the
; power of ten below their spread
auto_y:
    pushad
    mov esi, [gptr]
    add esi, GHDR
    imul ecx, [ncurve], GW
    mov byte [gany], 0
    jecxz .none
.s:
    mov eax, [esi]
    and eax, 0x7F800000
    cmp eax, 0x7F800000
    je .sn
    fld dword [esi]
    cmp byte [gany], 0
    jne .cmp
    fst qword [gya]
    fstp qword [gyb]
    mov byte [gany], 1
    jmp .sn
.cmp:
    fld qword [gya]
    fcomip st1
    jbe .a
    fst qword [gya]
.a:
    fld qword [gyb]
    fcomip st1
    jae .b
    fst qword [gyb]
.b:
    fstp st0
.sn:
    add esi, 4
    loop .s
.none:
    cmp byte [gany], 0
    jne .wid
    fld1
    fchs
    fstp qword [gya]
    fld1
    fstp qword [gyb]
    jmp .r
.wid:
    fld qword [gyb]
    fsub qword [gya]
    fldz
    fcomip st1
    jb .nice
    fstp st0                    ; flat: one either side
    fld qword [gya]
    fld1
    fsubp st1, st0
    fstp qword [gya]
    fld qword [gyb]
    fld1
    faddp st1, st0
    fstp qword [gyb]
    jmp .r
.nice:                          ; st0 = spread
    fldlg2
    fxch
    fyl2x                       ; log10
    call ffloor
    fistp dword [tmpi]
    dec dword [tmpi]
    call pow10                  ; st0 = the step
    fld qword [gya]
    fdiv st0, st1
    call ffloor
    fmul st0, st1
    fstp qword [gya]
    fld qword [gyb]
    fdiv st0, st1
    call fceil
    fmul st0, st1
    fstp qword [gyb]
    fstp st0
.r:
    popad
    ret

; st0 -> floor(st0) / ceil(st0)
ffloor:
    fld st0
    frndint
    fcomi st0, st1
    fstp st1
    jbe .r
    fld1
    fsubp st1, st0
.r:
    ret
fceil:
    fld st0
    frndint
    fcomi st0, st1
    fstp st1
    jae .r
    fld1
    faddp st1, st0
.r:
    ret

; [tmpi] = n -> st0 = 10^n
pow10:
    push ecx
    fld1
    mov ecx, [tmpi]
    test ecx, ecx
    jz .r
    js .neg
.m:
    fmul qword [f_10]
    loop .m
    jmp .r
.neg:
    neg ecx
.d:
    fdiv qword [f_10]
    loop .d
.r:
    pop ecx
    ret

; esi = "a b" -> [t1], [t2], or CF (nut_errmsg)
two_nums:
    call skipsp
    mov edi, ebuf
.a:
    lodsb
    cmp al, ' '
    je .b
    cmp al, 9
    je .b
    test al, al
    jz .bad
    stosb
    jmp .a
.b:
    mov byte [edi], 0
    push esi
    mov esi, ebuf
    call evaluate_num
    pop esi
    jc .r
    fstp qword [t1]
    call skipsp
    cmp byte [esi], 0
    je .bad
    call evaluate_num
    jc .r
    fstp qword [t2]
    clc
.r:
    ret
.bad:
    mov dword [nut_errmsg], m_two
    stc
    ret

; ebp = a table cell: each row worked out, as text
run_table:
    pushad
    mov dword [errlen], 0
    mov eax, [ebp+C_SRC]
    mov [lp], eax
    mov dword [tcols], 0
.p1:                            ; how many columns
    call src_line
    jc .hdr
    cmp byte [lbuf], 0
    je .p1
    mov esi, lbuf
    mov ecx, 1
.cnt:
    lodsb
    test al, al
    jz .cm
    cmp al, '|'
    jne .cnt
    inc ecx
    jmp .cnt
.cm:
    cmp ecx, [tcols]
    jbe .p1
    mov [tcols], ecx
    jmp .p1
.hdr:
    cmp dword [tcols], 0
    je .r
    cmp dword [tcols], TCOLMAX
    jbe .h
    mov dword [tcols], TCOLMAX
.h:
    mov edi, tbuf
    mov al, ' '
    mov ecx, 3
    rep stosb
    xor edx, edx
.hc:
    mov al, ' '
    mov ecx, 6
    rep stosb
    lea eax, [edx+'A']
    stosb
    mov al, ' '
    stosb
    inc edx
    cmp edx, [tcols]
    jb .hc
    call out_row
    mov eax, [ebp+C_SRC]        ; the rows
    mov [lp], eax
    mov dword [lno], 0
    mov dword [trow], 0
.p2:
    call src_line
    jc .r
    cmp byte [lbuf], 0
    je .p2
    inc dword [trow]
    cmp dword [trow], TROWMAX
    ja .r
    mov edi, tbuf
    mov eax, [trow]
    cmp eax, 10
    jae .two
    mov byte [edi], ' '
    inc edi
.two:
    call gui_utoa
    mov byte [edi], ' '
    inc edi
    mov esi, lbuf
    mov dword [tcol], 0
.cell:
    push edi                    ; one cell -> cbuf, trimmed
    call skipsp
    mov edi, cbuf
    xor ecx, ecx
.cc:
    lodsb
    test al, al
    jz .ce
    cmp al, '|'
    je .ce
    cmp ecx, 120
    jae .cc
    stosb
    inc ecx
    jmp .cc
.ce:
    mov [tlast], al
    test al, al
    jnz .ct
    dec esi
.ct:
    cmp edi, cbuf               ; trailing spaces
    je .cz
    cmp byte [edi-1], ' '
    jne .cz
    dec edi
    jmp .ct
.cz:
    mov byte [edi], 0
    pop edi
    cmp dword [tcol], TCOLMAX
    jae .next
    push esi
    call table_cell
    pop esi
.next:
    inc dword [tcol]
    cmp byte [tlast], 0
    jne .cell
    call out_row
    mov esi, errbuf             ; this row's errors
    mov ecx, [errlen]
    call out_n
    mov dword [errlen], 0
    jmp .p2
.r:
    popad
    ret

; tbuf .. edi -> a line of the output (trailing spaces dropped)
out_row:
    cmp edi, tbuf
    je .z
    cmp byte [edi-1], ' '
    jne .z
    dec edi
    jmp out_row
.z:
    mov byte [edi], 0
    push esi
    mov esi, tbuf
    call out_s
    pop esi
    mov al, 10
    jmp out_c

; cbuf = a table cell's text, [tcol], [trow] -> its 8 characters at edi
; (edi after them); the variable set
table_cell:
    mov al, 'A'
    add al, [tcol]
    mov [vname], al
    mov eax, [trow]
    push edi
    mov edi, vname + 1
    call gui_utoa
    sub edi, vname
    mov [vlen], edi
    pop edi
    mov esi, cbuf
    cmp byte [esi], 0
    je .blank
    cmp byte [esi], '='
    je .formula
    call looks_num
    jne .text
    push edi
    call evaluate
    pop edi
    jc .text
    jmp .val
.formula:
    inc esi
    push edi
    call evaluate
    pop edi
    jc .err
.val:
    cmp eax, V_STR
    je .sval
    fld st0
    push edi
    mov esi, vname
    mov ecx, [vlen]
    mov eax, V_NUM
    call nut_setvar
    pop edi
    jc .err
    call n_numtext              ; -> esi
    call strlen
    cmp eax, 7
    jbe .rj
    mov eax, 7
.rj:
    mov ecx, 7
    sub ecx, eax
    push eax
    mov al, ' '
    rep stosb
    pop ecx
    rep movsb
    mov al, ' '
    stosb
    ret
.text:                          ; "quoted" or not
    mov edx, cbuf
    mov esi, edx
    call strlen
    mov ecx, eax
    cmp byte [edx], '"'
    jne .sval
    cmp ecx, 2
    jb .sval
    cmp byte [edx+ecx-1], '"'
    jne .sval
    inc edx
    sub ecx, 2
.sval:                          ; edx, ecx
    push edi
    push ecx
    push edx
    mov ebx, ecx
    mov esi, vname
    mov ecx, [vlen]
    mov eax, V_STR
    call nut_setvar
    pop esi
    pop ecx
    pop edi
    jc .err
    cmp ecx, 7
    jbe .lj
    mov ecx, 7
.lj:
    mov edx, 8
    sub edx, ecx
    rep movsb
    mov ecx, edx
    mov al, ' '
    rep stosb
    ret
.blank:
    mov ecx, 8
    mov al, ' '
    rep stosb
    ret
.err:
    fninit
    mov esi, s_err
    mov ecx, 8
    rep movsb
    push edi                    ; "! A1: message" for after the row
    mov edi, [errlen]
    cmp edi, 400
    ja .e2
    add edi, errbuf
    mov ax, '! '
    stosw
    mov esi, vname
    call scopy
    mov ax, ': '
    stosw
    mov esi, [nut_errmsg]
    test esi, esi
    jnz .em
    mov esi, m_nopts
.em:
    mov ecx, 60
.ec:
    lodsb
    test al, al
    jz .ee
    stosb
    loop .ec
.ee:
    mov al, 10
    stosb
    sub edi, errbuf
    mov [errlen], edi
.e2:
    pop edi
    ret

; esi -> ZF if it starts like a number
looks_num:
    push esi
    mov al, [esi]
    cmp al, '-'
    je .s
    cmp al, '+'
    jne .d
.s:
    inc esi
    mov al, [esi]
.d:
    cmp al, '.'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    ja .n
.y:
    cmp al, al
    pop esi
    ret
.n:
    test esp, esp
    pop esi
    ret

; ebp = a geometry cell: its points and shapes, and the measurements
run_geo:
    pushad
    mov eax, [ebp+C_SRC]
    mov [lp], eax
    mov dword [npts], 0
    mov byte [gany], 0
    mov edx, [gpos]
    lea eax, [edx+GOHDR]
    cmp eax, GPOOL
    ja .full
    mov [gpos], eax
    mov [ebp+C_G], edx
    add edx, [gpool]
    mov [gptr], edx
    mov dword [edx], 0
.l:
    fninit
    call src_line
    jc .fin
    mov esi, lbuf
    call skipsp
    mov al, [esi]
    test al, al
    jz .l
    cmp al, '#'
    je .l
    mov [lstart], esi
    mov byte [nmbuf], 0
    call getword
    test eax, eax
    jz .unk
    push esi
    call skipsp
    cmp byte [esi], '='
    jne .plain
    cmp byte [esi+1], '='
    je .plain
    add esp, 4
    inc esi
    push esi
    mov esi, wbuf
    mov edi, nmbuf
    call scopy
    pop esi
    call skipsp
    cmp byte [esi], '('
    je .point
    call getword
    test eax, eax
    jz .unk
    jmp .cmd
.plain:
    pop esi
.cmd:
    push esi
    mov esi, wbuf
    mov edi, g_cmds
    call word_index
    pop esi
    jc .unk
    jmp [g_code+eax*4]
.unk:
    mov esi, m_unkcmd
    call out_err
    jmp .l
.everr:
    mov esi, [nut_errmsg]
    call out_err
    jmp .l
.badpt:
    mov esi, m_badpt
    call out_err
    jmp .l
.nomore:
    mov esi, m_manypts
    call out_err
    jmp .l
.full:
    mov esi, m_nomem
    call out_err
    popad
    ret
.point:                         ; N = (x, y)
    inc esi
    mov edi, esi
    call strend
.rp:
    cmp edi, esi
    jbe .badpt
    dec edi
    cmp byte [edi], ')'
    jne .rp
    mov byte [edi], 0
    call split_comma            ; -> ebx = the comma
    test ebx, ebx
    jz .badpt
    mov byte [ebx], 0
    push ebx
    call evaluate_num
    pop ebx
    jc .everr
    fstp qword [px]
    lea esi, [ebx+1]
    call evaluate_num
    jc .everr
    fstp qword [py]
    call add_point
    jc .nomore
    mov eax, P_PT
    call new_prim
    jc .full
    mov esi, nmbuf
    lea edi, [edi+8]
    mov ecx, 7
.pn:
    lodsb
    stosb
    test al, al
    jz .pd
    loop .pn
.pd:
    mov edi, [lastprim]
    fld qword [px]
    fstp qword [edi+16]
    fld qword [py]
    fstp qword [edi+24]
    call bbox_pt
    jmp .l
.seg:
    mov dword [ptype], P_SEG
    jmp .two
.line:
    mov dword [ptype], P_LINE
.two:
    call get_pt
    jc .l
    mov [pa], eax
    call get_pt
    jc .l
    mov [pb], eax
    call shape2
    jc .full
    jmp .l
.circle:
    call get_pt
    jc .l
    mov [pa], eax
    call skipsp
    mov [tptr], esi
    call getword                ; through a point, or a radius
    test eax, eax
    jz .rad
    call find_pt
    jc .rad
    mov [pb], eax
    call skipsp
    cmp byte [esi], 0
    jne .rad
    mov eax, [pa]
    mov ebx, [pb]
    call pt_dist
    jmp .cput
.rad:
    mov esi, [tptr]
    call evaluate_num
    jc .everr
.cput:
    fabs
    mov eax, P_CIRC
    call new_prim
    jc .full
    fstp qword [edi+32]
    mov eax, [pa]
    call pt_rec
    fld qword [esi+8]
    fstp qword [edi+16]
    fld qword [esi+16]
    fstp qword [edi+24]
    fld qword [edi+16]          ; its box
    fsub qword [edi+32]
    fstp qword [px]
    fld qword [edi+24]
    fsub qword [edi+32]
    fstp qword [py]
    call bbox_pt
    fld qword [edi+16]
    fadd qword [edi+32]
    fstp qword [px]
    fld qword [edi+24]
    fadd qword [edi+32]
    fstp qword [py]
    call bbox_pt
    jmp .l
.poly:
    call get_list
    jc .l
    cmp dword [pn], 2
    jb .few
    mov dword [ptype], P_SEG
    xor ebx, ebx
.pp:
    mov eax, [plist+ebx*4]
    mov [pa], eax
    lea ecx, [ebx+1]
    cmp ecx, [pn]
    jb .pq
    xor ecx, ecx
.pq:
    mov eax, [plist+ecx*4]
    mov [pb], eax
    push ebx
    call shape2
    pop ebx
    jc .full
    inc ebx
    mov ecx, [pn]
    cmp ecx, 2
    jne .pr
    dec ecx                     ; two points: one side
.pr:
    cmp ebx, ecx
    jb .pp
    jmp .l
.few:
    mov esi, m_few
    call out_err
    jmp .l
.dist:
    call get_pt
    jc .l
    mov [pa], eax
    call get_pt
    jc .l
    mov ebx, eax
    mov eax, [pa]
    call pt_dist
    jmp .meas
.angle:
    call get_list
    jc .l
    cmp dword [pn], 3
    jne .three
    mov eax, [plist+4]          ; at B: BA, BC
    call pt_rec
    mov edi, esi
    mov eax, [plist]
    call pt_rec
    fld qword [esi+8]
    fsub qword [edi+8]
    fstp qword [px]             ; a = A - B
    fld qword [esi+16]
    fsub qword [edi+16]
    fstp qword [py]
    mov eax, [plist+8]
    call pt_rec
    fld qword [esi+8]
    fsub qword [edi+8]
    fstp qword [t1]             ; c = C - B
    fld qword [esi+16]
    fsub qword [edi+16]
    fstp qword [t2]
    fld qword [px]              ; cross = ax cy - ay cx
    fmul qword [t2]
    fld qword [py]
    fmul qword [t1]
    fsubp st1, st0
    fabs
    fld qword [px]              ; dot = ax cx + ay cy
    fmul qword [t1]
    fld qword [py]
    fmul qword [t2]
    faddp st1, st0
    fpatan
    fmul qword [f_180]
    fldpi
    fdivp st1, st0
    jmp .meas
.three:
    mov esi, m_three
    call out_err
    jmp .l
.area:
    call get_list
    jc .l
    cmp dword [pn], 3
    jb .few
    fldz
    xor ebx, ebx
.ar:
    mov eax, [plist+ebx*4]
    call pt_rec
    mov edi, esi
    lea ecx, [ebx+1]
    cmp ecx, [pn]
    jb .aq
    xor ecx, ecx
.aq:
    mov eax, [plist+ecx*4]
    call pt_rec
    fld qword [edi+8]           ; xi y(i+1) - x(i+1) yi
    fmul qword [esi+16]
    fld qword [esi+8]
    fmul qword [edi+16]
    fsubp st1, st0
    faddp st1, st0
    inc ebx
    cmp ebx, [pn]
    jb .ar
    fabs
    fmul qword [f_half]
.meas:                          ; st0 = the value
    call out_nlfix
    cmp byte [nmbuf], 0
    je .anon
    fld st0
    mov esi, nmbuf
    call strlen
    mov ecx, eax
    mov eax, V_NUM
    call nut_setvar
    mov esi, nmbuf
    call out_s
    jmp .eq
.anon:
    mov esi, [lstart]
    call out_s
.eq:
    mov esi, s_eq
    call out_s
    call out_num
    mov al, 10
    call out_c
    jmp .l
.fin:                           ; the view: centre and scale
    mov edx, [gptr]
    cmp byte [gany], 0
    jne .fit
    fldz
    fst qword [edx+8]
    fstp qword [edx+16]
    fld qword [f_10]
    fstp qword [edx+24]
    jmp .r
.fit:
    fld qword [bminx]
    fadd qword [bmaxx]
    fmul qword [f_half]
    fstp qword [edx+8]
    fld qword [bminy]
    fadd qword [bmaxy]
    fmul qword [f_half]
    fstp qword [edx+16]
    mov dword [tmpi], GW - 16
    fild dword [tmpi]
    fld qword [bmaxx]
    fsub qword [bminx]
    call fmax_tiny
    fdivp st1, st0
    mov dword [tmpi], GEOH - 26
    fild dword [tmpi]
    fld qword [bmaxy]
    fsub qword [bminy]
    call fmax_tiny
    fdivp st1, st0
    fcomi st0, st1              ; the smaller
    jb .sm
    fxch
.sm:
    fstp st1
    fld qword [f_big]
    fcomip st1
    ja .ok
    fstp st0
    fld qword [f_10]
.ok:
    fstp qword [edx+24]
.r:
    popad
    ret

; st0 -> at least 1e-9
fmax_tiny:
    fld qword [f_tiny]
    fcomi st0, st1
    jb .r
    fstp st1
    ret
.r:
    fstp st0
    ret

; [pa], [pb] -> a shape of [ptype] from one to the other, or CF
shape2:
    mov eax, [ptype]
    call new_prim
    jc .r
    mov eax, [pa]
    call pt_rec
    fld qword [esi+8]
    fstp qword [edi+16]
    fld qword [esi+16]
    fstp qword [edi+24]
    mov eax, [pb]
    call pt_rec
    fld qword [esi+8]
    fstp qword [edi+32]
    fld qword [esi+16]
    fstp qword [edi+40]
    clc
.r:
    ret

; eax = type -> edi = a new zeroed shape of the figure at [gptr], or CF
new_prim:
    push eax
    push ecx
    mov ecx, [gpos]
    add ecx, PSIZE
    cmp ecx, GPOOL
    ja .no
    mov [gpos], ecx
    mov edi, [gptr]
    mov ecx, [edi]
    inc dword [edi]
    imul ecx, PSIZE
    lea edi, [edi+GOHDR+ecx]
    push edi
    xor eax, eax
    mov ecx, PSIZE / 4
    rep stosd
    pop edi
    mov eax, [esp+4]
    mov [edi], eax
    mov [lastprim], edi
    pop ecx
    pop eax
    clc
    ret
.no:
    pop ecx
    pop eax
    stc
    ret

; nmbuf, [px], [py] -> the point (a new one, or the same name moved);
; CF when there are too many
add_point:
    pushad
    mov esi, nmbuf
    mov edi, wbuf
    call scopy
    call find_pt
    jnc .set
    mov eax, [npts]
    cmp eax, GPTMAX
    jae .no
    inc dword [npts]
    push eax
    imul edi, eax, GPT_SIZE
    add edi, gpts
    mov esi, nmbuf
    mov ecx, 7
.c:
    lodsb
    stosb
    test al, al
    jz .z
    loop .c
    mov byte [edi], 0
.z:
    pop eax
.set:
    call pt_rec
    fld qword [px]
    fstp qword [esi+8]
    fld qword [py]
    fstp qword [esi+16]
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; wbuf = a name -> eax = its point, or CF
find_pt:
    push ecx
    push esi
    push edi
    xor eax, eax
.f:
    cmp eax, [npts]
    jae .no
    imul esi, eax, GPT_SIZE
    add esi, gpts
    mov edi, wbuf
.c:
    mov cl, [esi]
    cmp cl, [edi]
    jne .n
    inc esi
    inc edi
    test cl, cl
    jnz .c
    pop edi
    pop esi
    pop ecx
    clc
    ret
.n:
    inc eax
    jmp .f
.no:
    pop edi
    pop esi
    pop ecx
    stc
    ret

; eax = a point -> esi = its record
pt_rec:
    imul esi, eax, GPT_SIZE
    add esi, gpts
    ret

; eax, ebx = points -> st0 = the distance between them
pt_dist:
    push esi
    push edi
    call pt_rec
    mov edi, esi
    mov eax, ebx
    call pt_rec
    fld qword [esi+8]
    fsub qword [edi+8]
    fmul st0, st0
    fld qword [esi+16]
    fsub qword [edi+16]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    pop edi
    pop esi
    ret

; esi -> a point's name read (eax = the point), or CF with the error
; shown
get_pt:
    call getword
    test eax, eax
    jz .none
    call find_pt
    jc .unknown
    ret
.none:
    push esi
    mov esi, m_ptname
    call out_err
    pop esi
    stc
    ret
.unknown:
    push esi
    push edi
    mov esi, m_nopt
    mov edi, tbuf
    call scopy
    mov esi, wbuf
    call scopy
    mov esi, tbuf
    call out_err
    pop edi
    pop esi
    stc
    ret

; esi -> points to the end of the line: plist, pn; or CF (shown)
get_list:
    mov dword [pn], 0
.p:
    call skipsp
    cmp byte [esi], 0
    je .r
    call get_pt
    jc .e
    mov ecx, [pn]
    cmp ecx, 16
    jae .p
    mov [plist+ecx*4], eax
    inc dword [pn]
    jmp .p
.r:
    clc
.e:
    ret

; [px], [py] -> the figure's box
bbox_pt:
    cmp byte [gany], 0
    jne .u
    fld qword [px]
    fst qword [bminx]
    fstp qword [bmaxx]
    fld qword [py]
    fst qword [bminy]
    fstp qword [bmaxy]
    mov byte [gany], 1
    ret
.u:
    fld qword [px]
    fld qword [bminx]
    fcomip st1
    jbe .a
    fst qword [bminx]
.a:
    fld qword [bmaxx]
    fcomip st1
    jae .b
    fst qword [bmaxx]
.b:
    fstp st0
    fld qword [py]
    fld qword [bminy]
    fcomip st1
    jbe .c
    fst qword [bminy]
.c:
    fld qword [bmaxy]
    fcomip st1
    jae .d
    fst qword [bmaxy]
.d:
    fstp st0
    ret

; esi -> ebx = the first comma outside brackets and quotes, or 0
split_comma:
    push esi
    push ecx
    xor ecx, ecx
.c:
    mov al, [esi]
    test al, al
    jz .no
    cmp al, '"'
    je .q
    cmp al, '('
    je .o
    cmp al, ')'
    je .cl
    cmp al, ','
    jne .n
    test ecx, ecx
    jnz .n
    mov ebx, esi
    pop ecx
    pop esi
    ret
.o:
    inc ecx
    jmp .n
.cl:
    dec ecx
    jmp .n
.q:
    inc esi
    cmp byte [esi], 0
    je .no
    cmp byte [esi], '"'
    jne .q
.n:
    inc esi
    jmp .c
.no:
    xor ebx, ebx
    pop ecx
    pop esi
    ret

; ---------- expressions ----------
; esi = an expression (to its zero) -> eax = V_NUM (st0) or V_STR (edx,
; ecx), or CF (nut_errmsg)
evaluate:
    push ebx
    push esi
    push edi
    push ebp
    call nut_compile
    pop ebp
    pop edi
    pop esi
    pop ebx
    jc .r
    call nut_eval
.r:
    ret
; as evaluate, but a number is wanted -> st0
evaluate_num:
    call evaluate
    jc .r
    cmp eax, V_NUM
    je .r
    mov dword [nut_errmsg], m_wantnum
    stc
.r:
    ret

; ---------- the output pool ----------
out_c:
    push edi
    mov edi, [opos]
    cmp edi, OUTPOOL - 1
    jae .r
    add edi, [opool]
    mov [edi], al
    inc dword [opos]
.r:
    pop edi
    ret
out_s:
    push esi
    push eax
.c:
    lodsb
    test al, al
    jz .r
    call out_c
    jmp .c
.r:
    pop eax
    pop esi
    ret
out_n:
    pushad
    jecxz .r
.c:
    lodsb
    call out_c
    loop .c
.r:
    popad
    ret
; st0 (popped; the FPU is reset) -> its text
out_num:
    push esi
    call n_numtext
    call out_s
    pop esi
    ret
; eax -> its digits
out_dec:
    push esi
    push edi
    mov edi, nbuf
    call gui_utoa
    mov esi, nbuf
    call out_s
    pop edi
    pop esi
    ret
; a line ends before something new starts
out_nlfix:
    push eax
    mov eax, [opos]
    cmp eax, [ostart]
    je .r
    add eax, [opool]
    cmp byte [eax-1], 10
    je .r
    mov al, 10
    call out_c
.r:
    pop eax
    ret
; esi = a message -> "! line N: message" ([lno], when not 0)
out_err:
    push eax
    push esi
    call out_nlfix
    mov esi, s_bang
    call out_s
    mov eax, [lno]
    test eax, eax
    jz .m
    mov esi, s_line
    call out_s
    call out_dec
    mov esi, s_colon
    call out_s
.m:
    pop esi
    call out_s
    mov al, 10
    call out_c
    pop eax
    ret

; [lp] -> the next line of a cell's text in lbuf (trimmed), [lno] + 1;
; CF at the end
src_line:
    push eax
    push ecx
    push esi
    push edi
    mov esi, [lp]
    cmp byte [esi], 0
    je .end
    inc dword [lno]
    mov edi, lbuf
    xor ecx, ecx
.c:
    lodsb
    test al, al
    jz .z
    cmp al, 10
    je .e
    cmp al, 13
    je .c
    cmp al, 9
    jne .k
    mov al, ' '
.k:
    cmp ecx, 250
    jae .c
    stosb
    inc ecx
    jmp .c
.z:
    dec esi
.e:
    mov [lp], esi
.t:
    cmp edi, lbuf
    je .d
    cmp byte [edi-1], ' '
    jne .d
    dec edi
    jmp .t
.d:
    mov byte [edi], 0
    pop edi
    pop esi
    pop ecx
    pop eax
    clc
    ret
.end:
    pop edi
    pop esi
    pop ecx
    pop eax
    stc
    ret

skipsp:
    cmp byte [esi], ' '
    je .n
    cmp byte [esi], 9
    jne .r
.n:
    inc esi
    jmp skipsp
.r:
    ret

; esi -> a word (letters, digits, _) in wbuf, eax = its length; esi
; after it
getword:
    call skipsp
    push ecx
    xor ecx, ecx
.c:
    mov al, [esi]
    call is_wordc
    jne .e
    inc esi
    cmp ecx, 15
    jae .c
    mov [wbuf+ecx], al
    inc ecx
    jmp .c
.e:
    mov byte [wbuf+ecx], 0
    mov eax, ecx
    pop ecx
    ret
; al -> ZF for a letter, digit or _
is_wordc:
    cmp al, '0'
    jb .l
    cmp al, '9'
    ja .l
    cmp al, al
    ret
.l:
    jmp n_letter

; esi = a word, edi = a list of words (each zero-ended, then a zero) ->
; eax = its place in the list, or CF
word_index:
    push ebx
    push esi
    push edi
    xor eax, eax
.w:
    cmp byte [edi], 0
    je .no
    mov ebx, esi
.c:
    mov dl, [ebx]
    or dl, 0x20
    mov dh, [edi]
    or dh, 0x20
    cmp dl, dh
    jne .n
    cmp byte [edi], 0
    je .yes
    inc ebx
    inc edi
    jmp .c
.n:
    cmp byte [edi], 0           ; to the next word
    je .n2
    inc edi
    jmp .n
.n2:
    inc edi
    inc eax
    jmp .w
.yes:
    cmp byte [ebx], 0
    jne .n
    pop edi
    pop esi
    pop ebx
    clc
    ret
.no:
    pop edi
    pop esi
    pop ebx
    stc
    ret

; ---------- layout and drawing ----------
; every cell's height and place on the page (a dry draw)
layout:
    pushad
    mov byte [dry], 1
    xor ebx, ebx
    xor eax, eax
.c:
    cmp eax, [ncell]
    jae .d
    push eax
    call cell_ptr
    mov [ebp+C_Y], ebx
    push ebx
    call draw_cell
    pop ecx
    mov edx, ebx
    sub edx, ecx
    mov [ebp+C_H], edx
    add ebx, GAP
    pop eax
    inc eax
    jmp .c
.d:
    mov [doch], ebx
    mov byte [dry], 0
    popad
    ret

; ebp = a cell, ebx = its top -> ebx = its bottom (drawn unless [dry])
draw_cell:
    pushad
    add ebx, PAD
    movzx eax, byte [ebp+C_KIND]
    mov [tkind], eax
    mov dword [ccount], 0
    cmp eax, K_NOTE
    je .note
    cmp eax, K_CODE
    je .code
    cmp eax, K_GRAPH
    je .graph
    cmp eax, K_TABLE
    je .table
    cmp eax, K_MATH
    je .math
    call draw_geo
    add ebx, GEOH + 2
    jmp .out
.graph:
    call draw_graph
    add ebx, GH + 2
    jmp .out
.table:
    cmp dword [ebp+C_OLEN], 0
    jne .out
    mov esi, s_etable
    jmp .ph
.math:
    cmp dword [ebp+C_OLEN], 0
    jne .out
    mov esi, s_emath
    jmp .ph
.note:
    mov esi, [ebp+C_SRC]
    mov ecx, [ebp+C_LEN]
    jecxz .enote
    mov edx, COLS
    mov byte [tmode], 0
    call draw_lines
    jmp .end
.enote:
    mov esi, s_enote
.ph:                            ; a grey hint
    call strlen
    mov ecx, eax
    xor edx, edx
    mov byte [tmode], 3
    call draw_lines
    jmp .end
.code:
    mov esi, [ebp+C_SRC]
    mov ecx, [ebp+C_LEN]
    mov al, [dry]               ; its height first, for the shading
    push eax
    mov byte [dry], 1
    push ebx
    xor edx, edx
    call draw_lines
    mov edx, ebx
    pop ebx
    pop eax
    mov [dry], al
    sub edx, ebx
    jnz .shade
    mov edx, CELL_H
.shade:
    cmp byte [dry], 0
    jne .src
    push ebx
    push edx
    mov eax, X0 - 2
    dec ebx
    mov ecx, COLS * CELL_W + 4
    add edx, 2
    mov byte [gui_ink], C_LGREY
    call gui_fill
    pop edx
    pop ebx
.src:
    push edx
    mov byte [tmode], 1
    push ebx
    mov esi, [ebp+C_SRC]
    mov ecx, [ebp+C_LEN]
    xor edx, edx
    call draw_lines
    pop ebx
    pop edx
    add ebx, edx
    add ebx, 3
.out:
    mov esi, [opool]
    add esi, [ebp+C_OUT]
    mov ecx, [ebp+C_OLEN]
    mov edx, COLS
    mov byte [tmode], 2
    call draw_lines
.end:
    add ebx, PAD
    mov [esp+16], ebx
    popad
    ret

; esi = text, ecx = its length, edx = wrap width (0: none), ebx = y ->
; the lines drawn ([tmode] colours them), ebx below them
draw_lines:
    push eax
    push ecx
    push esi
    push edi
    lea edi, [esi+ecx]
    mov [dl_start], esi
.l:
    call line_next
    jc .r
    push eax
    cmp byte [dry], 0
    jne .n
    call draw_line
.n:
    pop esi
    add ebx, CELL_H
    jmp .l
.r:
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

; esi = where, edi = the end, edx = wrap width -> esi .. +ecx = a line,
; eax = where the next starts; CF at the end
line_next:
    cmp esi, edi
    jae .end
    mov eax, esi
.s:
    cmp eax, edi
    jae .got
    cmp byte [eax], 10
    je .got
    inc eax
    jmp .s
.got:
    mov ecx, eax
    sub ecx, esi
    test edx, edx
    jz .nw
    cmp ecx, edx
    jbe .nw
    mov ecx, edx                ; too long: break at the last space
.b:
    cmp byte [esi+ecx], ' '
    je .sp
    dec ecx
    jnz .b
    mov ecx, edx
    lea eax, [esi+edx]
    clc
    ret
.sp:
    lea eax, [esi+ecx+1]
    clc
    ret
.nw:
    cmp eax, edi
    jae .last
    inc eax
.last:
    clc
    ret
.end:
    stc
    ret

; esi, ecx = a line, ebx = y: drawn at X0 in its colours
draw_line:
    pushad
    cmp esi, [dl_start]
    je .first
    cmp byte [esi-1], 10
    jne .go
.first:
    call pick_colour
.go:
    cmp ecx, COLS
    jbe .w
    mov ecx, COLS
.w:
    mov al, [lcol]
    mov [gui_ink], al
    mov al, [lbg]
    mov [gui_bg], al
    mov eax, X0
    call textn
    popad
    ret

; esi, ecx = the start of a line -> lcol, lbg (a heading's "# " is
; skipped)
pick_colour:
    mov byte [lbg], C_WHITE
    mov byte [lcol], C_BLACK
    movzx eax, byte [tmode]
    cmp eax, 1
    je .src
    cmp eax, 3
    je .hint
    cmp eax, 2
    je .out
    cmp ecx, 2                  ; a note
    jb .r
    cmp word [esi], '# '
    jne .r
    mov byte [lcol], C_BLUE
    add esi, 2
    sub ecx, 2
    ret
.src:
    mov byte [lbg], C_LGREY
    ret
.hint:
    mov byte [lcol], C_DGREY
    ret
.out:
    cmp byte [esi], '!'
    je .red
    mov eax, [tkind]
    cmp eax, K_CODE
    je .green
    cmp eax, K_TABLE
    je .tab
    cmp eax, K_GRAPH
    jne .r
    cmp word [esi], 'x:'
    je .hint
    mov eax, [ccount]
    inc dword [ccount]
    and eax, NCURVE - 1
    mov al, [curve_col+eax]
    mov [lcol], al
    ret
.tab:
    cmp esi, [dl_start]
    jne .r
    mov byte [lcol], C_BLUE
    ret
.green:
    mov byte [lcol], C_GREEN
    ret
.red:
    mov byte [lcol], C_RED
.r:
    ret

; eax = x, ebx = y, esi = text, ecx = how many characters
textn:
    pushad
    jecxz .r
.c:
    mov dl, [esi]
    call gui_char
    add eax, CELL_W
    inc esi
    loop .c
.r:
    popad
    ret

; ebx = the top of a box GW x edx: drawing is clipped to inside it (and
; to the page)
clip_box:
    push eax
    mov dword [gui_clx0], X0 + 1
    mov dword [gui_clx1], X0 + GW - 1
    lea eax, [ebx+1]
    cmp eax, VY0
    jge .a
    mov eax, VY0
.a:
    mov [gui_cly0], eax
    lea eax, [ebx+edx-1]
    cmp eax, VY0 + VH
    jle .b
    mov eax, VY0 + VH
.b:
    mov [gui_cly1], eax
    pop eax
    ret
; drawing is clipped to the page
clip_page:
    push eax
    push ebx
    push ecx
    push edx
    xor eax, eax
    mov ebx, VY0
    mov ecx, SCR_W
    mov edx, VH
    call gui_clip
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ebp = a graph cell, ebx = the box's top
draw_graph:
    cmp byte [dry], 0
    jne .r0
    pushad
    mov [boxy], ebx
    mov eax, X0
    mov ecx, GW
    mov edx, GH
    mov byte [gui_ink], C_DGREY
    call gui_box
    mov eax, [ebp+C_G]
    cmp eax, -1
    je .r
    add eax, [gpool]
    mov [gptr], eax
    call clip_box
    mov esi, eax                ; k = (GH - 5) / (yb - ya)
    mov dword [tmpi], GH - 5
    fild dword [tmpi]
    fld qword [esi+32]
    fsub qword [esi+24]
    fdivp st1, st0
    fstp qword [gk]
    mov dword [tmpi], GW - 1    ; kx = (GW - 1) / (xb - xa)
    fild dword [tmpi]
    fld qword [esi+16]
    fsub qword [esi+8]
    fdivp st1, st0
    fstp qword [gkx]
    mov byte [gui_ink], C_LGREY ; the axes
    fldz
    fld qword [esi+8]
    fcomip st1
    jae .noy
    fld qword [esi+16]
    fcomip st1
    jbe .noy
    fsub qword [esi+8]          ; x = 0
    fmul qword [gkx]
    fistp dword [tmpi]
    mov eax, X0
    add eax, [tmpi]
    mov ecx, eax
    mov ebx, [boxy]
    lea edx, [ebx+GH-1]
    call gui_line
    fldz
.noy:
    fld qword [esi+24]
    fcomip st1
    jae .nox
    fld qword [esi+32]
    fcomip st1
    jbe .nox
    call y_pix                  ; y = 0
    mov ebx, eax
    mov edx, eax
    mov eax, X0
    mov ecx, X0 + GW - 1
    call gui_line
    fldz
.nox:
    fstp st0
    xor ebx, ebx                ; the curves
.cv:
    cmp ebx, [esi]
    jae .r
    mov al, [curve_col+ebx]
    mov [gui_ink], al
    imul edi, ebx, GW * 4
    lea edi, [esi+edi+GHDR]
    mov byte [gprev], 0
    xor ecx, ecx
.pt:
    cmp ecx, GW
    jae .cn
    mov eax, [edi+ecx*4]
    and eax, 0x7F800000
    cmp eax, 0x7F800000
    je .gap
    fld dword [edi+ecx*4]
    call y_pix
    lea edx, [ecx+X0]
    cmp byte [gprev], 0
    je .first
    pushad                      ; a line from the last point, unless it
    mov ebx, eax                ; jumps right across the box
    mov edx, [boxy]
    cmp dword [gpy], edx
    jge .j1
    add edx, GH
    cmp ebx, edx
    jge .skip
    jmp .ln
.j1:
    add edx, GH
    cmp [gpy], edx
    jl .ln
    sub edx, GH
    cmp ebx, edx
    jl .skip
.ln:
    mov eax, [gpx]
    mov ebx, [gpy]
    mov ecx, [esp+20]           ; this x (edx)
    mov edx, [esp+28]           ; this y (eax)
    call gui_line
.skip:
    popad
    jmp .keep
.first:
    push ecx
    push ebx
    push eax
    mov ebx, eax
    mov eax, edx
    mov cl, [gui_ink]
    call gui_pset
    pop eax
    pop ebx
    pop ecx
.keep:
    mov [gpx], edx
    mov [gpy], eax
    mov byte [gprev], 1
    jmp .pn
.gap:
    mov byte [gprev], 0
.pn:
    inc ecx
    jmp .pt
.cn:
    inc ebx
    jmp .cv
.r:
    call clip_page
    popad
.r0:
    ret

; st0 (popped) = y, esi = the graph -> eax = its row on the screen
; (kept within a few thousand pixels)
y_pix:
    fsub qword [esi+24]
    fmul qword [gk]
    call fclamp
    fistp dword [tmpi]
    mov eax, [boxy]
    add eax, GH - 3
    sub eax, [tmpi]
    ret

; st0 -> within -3000 .. 3000
fclamp:
    fld qword [f_3000]
    fcomi st0, st1
    jae .lo
    fstp st1
    ret
.lo:
    fchs
    fcomi st0, st1
    jbe .ok
    fstp st1
    ret
.ok:
    fstp st0
    ret

; ebp = a geometry cell, ebx = the box's top
draw_geo:
    cmp byte [dry], 0
    jne .r0
    pushad
    mov [boxy], ebx
    mov eax, X0
    mov ecx, GW
    mov edx, GEOH
    mov byte [gui_ink], C_DGREY
    call gui_box
    mov eax, [ebp+C_G]
    cmp eax, -1
    je .r
    add eax, [gpool]
    mov [gptr], eax
    mov edx, GEOH
    call clip_box
    mov esi, eax
    mov ebx, 1                  ; shapes first, then the points
.pass:
    mov ecx, [esi]
    lea edi, [esi+GOHDR]
.p:
    test ecx, ecx
    jz .np
    push ecx
    push ebx
    mov eax, [edi]
    cmp eax, P_PT
    je .pt
    cmp ebx, 1
    jne .nx
    cmp eax, P_SEG
    je .seg
    cmp eax, P_LINE
    je .line
    call g_circle
    jmp .nx
.seg:
    mov byte [gui_ink], C_BLUE
    call g_seg
    jmp .nx
.line:
    call g_line
    jmp .nx
.pt:
    cmp ebx, 2
    jne .nx
    call g_point
.nx:
    pop ebx
    pop ecx
    add edi, PSIZE
    dec ecx
    jmp .p
.np:
    inc ebx
    cmp ebx, 2
    jbe .pass
.r:
    call clip_page
    popad
.r0:
    ret

; [edi+16], [edi+24] (world) -> eax, ebx (screen); esi = the figure
w2s:
    fld qword [edi+24]
    fld qword [edi+16]
w2s_st:                         ; st0 = x, st1 = y (both popped)
    fsub qword [esi+8]
    fmul qword [esi+24]
    call fclamp
    fistp dword [tmpi]
    mov eax, X0 + GW / 2
    add eax, [tmpi]
    fsub qword [esi+16]
    fmul qword [esi+24]
    call fclamp
    fistp dword [tmpi]
    mov ebx, [boxy]
    add ebx, GEOH / 2
    sub ebx, [tmpi]
    ret

g_seg:
    pushad
    fld qword [edi+40]
    fld qword [edi+32]
    call w2s_st
    mov ecx, eax
    mov edx, ebx
    fld qword [edi+24]
    fld qword [edi+16]
    call w2s_st
    call gui_line
    popad
    ret

; a line through two points, drawn well past the box both ways
g_line:
    pushad
    mov byte [gui_ink], C_CYAN
    fld qword [edi+32]          ; d = b - a
    fsub qword [edi+16]
    fld qword [edi+40]
    fsub qword [edi+24]         ; dy, dx
    fld st1
    fmul st0, st0
    fld st1
    fmul st0, st0
    faddp st1, st0
    fsqrt                       ; |d|, dy, dx
    fldz
    fcomip st1
    jae .zero
    mov dword [tmpi], 2 * GW    ; L / |d| in world units
    fild dword [tmpi]
    fdiv qword [esi+24]
    fdivrp st1, st0             ; f = L / |d|, dy, dx
    fmul st2, st0
    fmulp st1, st0              ; dy f, dx f
    fld st0
    fadd qword [edi+24]
    fld st2
    fadd qword [edi+16]
    call w2s_st                 ; a + d f
    mov ecx, eax
    mov edx, ebx
    fld qword [edi+24]
    fsub st0, st1
    fld qword [edi+16]
    fsub st0, st3
    call w2s_st                 ; a - d f
    call gui_line
.zero:
    fninit
    popad
    ret

g_circle:
    pushad
    mov byte [gui_ink], C_GREEN
    xor ecx, ecx
.s:
    mov [tmpi], ecx             ; t = 2 pi i / 48
    fild dword [tmpi]
    fldpi
    fmulp st1, st0
    fdiv qword [f_24]
    fsincos                     ; cos, sin
    fmul qword [edi+32]
    fadd qword [edi+16]         ; x
    fxch
    fmul qword [edi+32]
    fadd qword [edi+24]         ; y, x
    fxch
    call w2s_st
    test ecx, ecx
    jz .first
    push ecx
    mov ecx, [gpx]
    mov edx, [gpy]
    mov [gpx], eax
    mov [gpy], ebx
    call gui_line
    pop ecx
    jmp .n
.first:
    mov [gpx], eax
    mov [gpy], ebx
.n:
    inc ecx
    cmp ecx, 48
    jbe .s
    popad
    ret

g_point:
    pushad
    call w2s
    push eax
    push ebx
    dec eax
    dec ebx
    mov ecx, 3
    mov edx, 3
    mov byte [gui_ink], C_RED
    call gui_fill
    pop ebx
    pop eax
    add eax, 3
    sub ebx, CELL_H + 1
    lea esi, [edi+8]
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    call gui_text
    popad
    ret

draw:
    cmp byte [editing], 0
    jne draw_edit
draw_view:
    pushad
    mov edi, tbuf
    mov esi, s_title
    call scopy
    mov esi, fname
    call scopy
    cmp byte [dirty], 0
    je .t
    mov byte [edi], '*'
    inc edi
.t:
    mov byte [edi], 0
    call window
    call clip_page
    cmp dword [ncell], 0
    jne .cells
    mov byte [gui_ink], C_DGREY
    mov byte [gui_bg], C_WHITE
    mov eax, X0
    mov ebx, VY0 + 8
    mov esi, s_hint1
    call gui_text
    add ebx, CELL_H * 2
    mov esi, s_hint2
    call gui_text
    jmp .st
.cells:
    xor eax, eax
.c:
    cmp eax, [ncell]
    jae .st
    push eax
    call cell_ptr
    mov ebx, [ebp+C_Y]
    sub ebx, [scroll]
    add ebx, VY0
    mov ecx, ebx
    add ecx, [ebp+C_H]
    cmp ecx, VY0
    jl .skip
    cmp ebx, VY0 + VH
    jge .skip
    push ebx
    call draw_cell
    pop ebx
    mov eax, [esp]
    cmp eax, [sel]
    jne .skip
    mov eax, 3                  ; the chosen cell
    mov ecx, 3
    mov edx, [ebp+C_H]
    mov byte [gui_ink], C_BLUE
    call gui_fill
.skip:
    pop eax
    inc eax
    jmp .c
.st:
    call gui_noclip
    call status_view
    call gui_flip
    popad
    ret

; tbuf = the title: the window, with a white page
window:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, tbuf
    call gui_window
    mov eax, 1
    mov ebx, VY0 - 1
    mov ecx, SCR_W - 2
    mov edx, VH + 2
    mov byte [gui_ink], C_WHITE
    call gui_fill
    popad
    ret

; esi = the text of the status row
status:
    pushad
    push esi
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov byte [gui_bg], C_LGREY
    mov byte [gui_ink], C_BLACK
    pop esi
    call gui_textn
    popad
    ret

status_view:
    pushad
    mov esi, [msg]
    test esi, esi
    jnz .out
    mov esi, s_keys0
    mov eax, [sel]
    cmp eax, -1
    je .out
    mov edi, tbuf
    inc eax
    call gui_utoa
    mov byte [edi], '/'
    inc edi
    mov eax, [ncell]
    call gui_utoa
    mov byte [edi], ' '
    inc edi
    mov eax, [sel]
    call cell_ptr
    movzx eax, byte [ebp+C_KIND]
    call kind_name
    call scopy
    mov esi, s_keys
    call scopy
    mov esi, tbuf
.out:
    call status
    popad
    ret

; eax = a kind -> esi = its name
kind_name:
    mov esi, kind_names
.k:
    test eax, eax
    jz .r
.s:
    cmp byte [esi], 0
    je .n
    inc esi
    jmp .s
.n:
    inc esi
    dec eax
    jmp .k
.r:
    ret

; ---------- keys ----------
; eax = a key -> CF to quit
key:
    cmp byte [editing], 0
    jne ekey
    pushad
    mov dword [msg], 0
    movzx ebx, ah
    test eax, 1 << 16
    jnz .ctrl
    cmp bl, K_ESC
    je .quit
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_HOME
    je .home
    cmp bl, K_END
    je .end
    cmp bl, K_DEL
    je .del
    cmp bl, K_ENTER
    je .edit
    cmp al, 13
    je .edit
    mov dl, al
    or dl, 0x20
    mov ecx, K_NOTE
    cmp dl, 'n'
    je .new
    mov ecx, K_CODE
    cmp dl, 'c'
    je .new
    mov ecx, K_GRAPH
    cmp dl, 'g'
    je .new
    mov ecx, K_TABLE
    cmp dl, 't'
    je .new
    mov ecx, K_GEO
    cmp dl, 'o'
    je .new
    mov ecx, K_MATH
    cmp dl, 'm'
    je .new
    jmp .ok
.ctrl:
    cmp bl, K_UP
    je .mvup
    cmp bl, K_DOWN
    je .mvdn
    and al, 0xDF
    cmp al, 'S'
    jne .r1
    call save
    jmp .ok
.r1:
    cmp al, 'R'
    jne .ok
    call run_all
    mov dword [msg], m_ran
    jmp .vis
.up:
    mov eax, [sel]
    test eax, eax
    jle .vis
    dec dword [sel]
    jmp .vis
.down:
    mov eax, [sel]
    inc eax
    cmp eax, [ncell]
    jae .vis
    mov [sel], eax
    jmp .vis
.home:
    cmp dword [ncell], 0
    je .ok
    mov dword [sel], 0
    jmp .vis
.end:
    mov eax, [ncell]
    dec eax
    mov [sel], eax
    jmp .vis
.pgup:
    sub dword [scroll], VH / 2
    jmp .clamp
.pgdn:
    add dword [scroll], VH / 2
.clamp:
    call clamp_scroll
    jmp .ok
.del:
    mov eax, [sel]
    cmp eax, -1
    je .ok
    call delete_cell
    mov byte [dirty], 1
    mov eax, [ncell]
    cmp [sel], eax
    jb .rerun
    dec eax
    mov [sel], eax
.rerun:
    call run_all
    jmp .vis
.new:
    mov eax, [sel]
    inc eax
    call insert_cell
    jc .full
    mov [sel], eax
    mov byte [dirty], 1
    call run_all
    call ensure_vis
    call start_edit
    jmp .ok
.full:
    mov dword [msg], m_full
    jmp .ok
.edit:
    cmp dword [sel], -1
    je .ok
    call start_edit
    jmp .ok
.mvup:
    mov eax, [sel]
    test eax, eax
    jle .ok
    dec eax
    call swap_cells
    mov [sel], eax
    jmp .moved
.mvdn:
    mov eax, [sel]
    cmp eax, -1
    je .ok
    lea ecx, [eax+1]
    cmp ecx, [ncell]
    jae .ok
    call swap_cells
    mov [sel], ecx
.moved:
    mov byte [dirty], 1
    call run_all
.vis:
    call ensure_vis
.ok:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; the chosen cell is brought into view
ensure_vis:
    pushad
    mov eax, [sel]
    cmp eax, -1
    je .clamp
    cmp eax, [ncell]
    jae .clamp
    call cell_ptr
    mov eax, [ebp+C_Y]
    mov ecx, [ebp+C_H]
    cmp eax, [scroll]
    jge .b
    mov [scroll], eax
    jmp .clamp
.b:
    lea edx, [eax+ecx]
    sub edx, VH
    cmp edx, [scroll]
    jle .clamp
    cmp edx, eax
    jle .s
    mov edx, eax                ; taller than the page: its top
.s:
    mov [scroll], edx
.clamp:
    call clamp_scroll
    popad
    ret

clamp_scroll:
    push eax
    mov eax, [doch]
    sub eax, VH
    jge .m
    xor eax, eax
.m:
    cmp [scroll], eax
    jle .z
    mov [scroll], eax
.z:
    cmp dword [scroll], 0
    jge .r
    mov dword [scroll], 0
.r:
    pop eax
    ret

; a left click on the page: choose a cell; on the chosen one, edit it
click:
    pushad
    cmp byte [editing], 0
    jne .r
    mov ebx, [gui_my]
    cmp ebx, VY0
    jl .r
    cmp ebx, VY0 + VH
    jge .r
    sub ebx, VY0
    add ebx, [scroll]
    xor eax, eax
.c:
    cmp eax, [ncell]
    jae .r
    call cell_ptr
    mov ecx, [ebp+C_Y]
    add ecx, [ebp+C_H]
    add ecx, GAP
    cmp ebx, ecx
    jl .hit
    inc eax
    jmp .c
.hit:
    cmp eax, [sel]
    je .edit
    mov [sel], eax
    mov dword [msg], 0
    jmp .r
.edit:
    call start_edit
.r:
    popad
    ret

; ---------- the editor ----------
start_edit:
    pushad
    mov eax, [sel]
    call cell_ptr
    mov [ecell], ebp
    mov eax, [ebp+C_LEN]
    mov [ecur], eax
    mov dword [etop], 0
    mov byte [editing], 1
    mov dword [msg], 0
    call e_adjust
    popad
    ret

; eax = a key, while editing -> CF clear
ekey:
    pushad
    mov ebp, [ecell]
    mov esi, [ebp+C_SRC]
    movzx ebx, ah
    test eax, 1 << 16
    jnz .r
    cmp bl, K_ESC
    je .done
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_HOME
    je .home
    cmp bl, K_END
    je .end
    cmp bl, K_BKSP
    je .bksp
    cmp bl, K_DEL
    je .del
    cmp bl, K_ENTER
    je .nl
    cmp bl, K_TAB
    je .tab
    cmp al, 13
    je .nl
    cmp al, 8
    je .bksp
    cmp al, ' '
    jb .r
    cmp al, '~'
    ja .r
    call e_insert
    jmp .r
.tab:
    mov al, ' '
    call e_insert
    call e_insert
    jmp .r
.nl:
    mov al, 10
    call e_insert
    jmp .r
.bksp:
    cmp dword [ecur], 0
    je .r
    dec dword [ecur]
.del:
    call e_delete
    jmp .r
.left:
    cmp dword [ecur], 0
    je .r
    dec dword [ecur]
    jmp .r
.right:
    mov eax, [ecur]
    cmp eax, [ebp+C_LEN]
    jae .r
    inc dword [ecur]
    jmp .r
.home:
    mov eax, [ecur]
    call e_lstart
    mov [ecur], eax
    jmp .r
.end:
    mov eax, [ecur]
    call e_lend
    mov [ecur], eax
    jmp .r
.up:
    mov eax, [ecur]
    call e_lstart
    test eax, eax
    jz .r
    mov ecx, [ecur]
    sub ecx, eax                ; the column
    lea edx, [eax-1]            ; the end of the line above
    mov eax, edx
    call e_lstart
    jmp .col
.down:
    mov eax, [ecur]
    call e_lend
    cmp byte [esi+eax], 0
    je .r
    push eax
    mov eax, [ecur]
    call e_lstart
    mov ecx, [ecur]
    sub ecx, eax
    pop eax
    inc eax                     ; the next line's start
    push eax
    call e_lend
    mov edx, eax
    pop eax
.col:                           ; eax = a line's start, edx its end,
    add ecx, eax                ; ecx the column wanted
    cmp ecx, edx
    jbe .set
    mov ecx, edx
.set:
    mov [ecur], ecx
    jmp .r
.done:
    mov byte [editing], 0
    mov byte [dirty], 1
    call run_all
    call ensure_vis
    popad
    clc
    ret
.r:
    call e_adjust
    popad
    clc
    ret

; eax = a place in the text at esi -> eax = its line's start / end
e_lstart:
    test eax, eax
    jz .r
    cmp byte [esi+eax-1], 10
    je .r
    dec eax
    jmp e_lstart
.r:
    ret
e_lend:
    cmp byte [esi+eax], 0
    je .r
    cmp byte [esi+eax], 10
    je .r
    inc eax
    jmp e_lend
.r:
    ret

; al -> put in at the cursor (ebp = the cell)
e_insert:
    pushad
    mov ecx, [ebp+C_LEN]
    cmp ecx, SRCMAX
    jae .r
    mov esi, [ebp+C_SRC]
    mov edx, [ecur]
.m:
    mov ah, [esi+ecx]
    mov [esi+ecx+1], ah
    cmp ecx, edx
    je .put
    dec ecx
    jmp .m
.put:
    mov [esi+edx], al
    inc dword [ebp+C_LEN]
    inc dword [ecur]
.r:
    popad
    ret

; the character at the cursor goes (ebp = the cell)
e_delete:
    pushad
    mov ecx, [ebp+C_LEN]
    mov edx, [ecur]
    cmp edx, ecx
    jae .r
    mov esi, [ebp+C_SRC]
.m:
    mov al, [esi+edx+1]
    mov [esi+edx], al
    inc edx
    cmp edx, ecx
    jb .m
    dec dword [ebp+C_LEN]
.r:
    popad
    ret

; the cursor's line and column; the view follows it
e_adjust:
    pushad
    mov ebp, [ecell]
    mov esi, [ebp+C_SRC]
    mov ecx, [ecur]
    xor eax, eax
    xor edx, edx
    xor ebx, ebx
.s:
    cmp ebx, ecx
    jae .d
    inc edx
    cmp byte [esi+ebx], 10
    jne .n
    inc eax
    xor edx, edx
.n:
    inc ebx
    jmp .s
.d:
    mov [cline], eax
    mov [ccol], edx
    cmp eax, [etop]
    jge .t
    mov [etop], eax
.t:
    mov ecx, [etop]
    add ecx, ER
    cmp eax, ecx
    jl .h
    sub eax, ER - 1
    mov [etop], eax
.h:
    sub edx, COLS - 1
    jge .ho
    xor edx, edx
.ho:
    mov [hoff], edx
    popad
    ret

draw_edit:
    pushad
    mov ebp, [ecell]
    mov edi, tbuf
    mov esi, s_edit
    call scopy
    movzx eax, byte [ebp+C_KIND]
    call kind_name
    call scopy
    mov esi, s_edit2
    call scopy
    call window
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    mov esi, [ebp+C_SRC]
    xor edx, edx                ; the line
    mov ebx, VY0 + 1
.ln:
    mov eax, esi                ; its end
.e:
    cmp byte [eax], 0
    je .got
    cmp byte [eax], 10
    je .got
    inc eax
    jmp .e
.got:
    mov edi, eax
    cmp edx, [etop]
    jb .next
    mov ecx, [etop]
    add ecx, ER
    cmp edx, ecx
    jae .cur
    mov ecx, edi
    sub ecx, esi
    sub ecx, [hoff]
    jle .down
    cmp ecx, COLS
    jbe .dr
    mov ecx, COLS
.dr:
    push esi
    add esi, [hoff]
    mov eax, X0
    call textn
    pop esi
.down:
    add ebx, CELL_H
.next:
    inc edx
    cmp byte [edi], 0
    je .cur
    lea esi, [edi+1]
    jmp .ln
.cur:                           ; the cursor: the character, inverted
    mov esi, [ebp+C_SRC]
    mov ecx, [ecur]
    mov dl, [esi+ecx]
    cmp dl, ' '
    jae .ch
    mov dl, ' '
.ch:
    mov eax, [ccol]
    sub eax, [hoff]
    imul eax, CELL_W
    add eax, X0
    mov ebx, [cline]
    sub ebx, [etop]
    shl ebx, 3
    add ebx, VY0 + 1
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLUE
    call gui_char
    mov edi, tbuf               ; "line 3, col 5 ..."
    mov esi, s_lnum
    call scopy
    mov eax, [cline]
    inc eax
    call gui_utoa
    mov esi, s_cnum
    call scopy
    mov eax, [ccol]
    inc eax
    call gui_utoa
    mov esi, s_ekeys
    call scopy
    mov esi, tbuf
    call status
    call gui_flip
    popad
    ret

; ---------- files ----------
save:
    pushad
    mov edi, [fbuf]
    xor eax, eax
.c:
    cmp eax, [ncell]
    jae .write
    push eax
    call cell_ptr
    mov esi, s_hdr
    call scopy
    movzx eax, byte [ebp+C_KIND]
    call kind_name
    call scopy
    mov al, 10
    stosb
    mov esi, [ebp+C_SRC]
    mov ecx, [ebp+C_LEN]
    rep movsb
    mov al, 10
    stosb
    pop eax
    inc eax
    jmp .c
.write:
    sub edi, [fbuf]
    mov [flen], edi
    mov eax, SYS_OPEN
    mov ebx, fname
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, [fbuf]
    mov edx, [flen]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [flen]
    jne .fail
    mov byte [dirty], 0
    mov dword [msg], m_saved
    popad
    clc
    ret
.fail:
    mov dword [msg], m_nosave
    popad
    stc
    ret

; fname -> the cells (none if there is no such file)
load:
    pushad
    call init_cells
    mov eax, SYS_OPEN
    mov ebx, fname
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .new
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, [fbuf]
    mov edx, FBUF - 1
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop ecx
    test ecx, ecx
    jns .got
    xor ecx, ecx
.got:
    mov esi, [fbuf]
    mov byte [esi+ecx], 0
    call parse_nb
    mov dword [msg], m_opened
    jmp .r
.new:
    mov dword [msg], m_newfile
.r:
    mov byte [dirty], 0
    popad
    ret

; esi = a notebook's text -> the cells
parse_nb:
    pushad
    call init_cells
    xor ebp, ebp                ; the cell being filled
.l:
    cmp byte [esi], 0
    je .done
    cmp word [esi], '%%'
    jne .text
    call .finish
    add esi, 2
    call getword
    push esi
    mov esi, wbuf
    mov edi, kind_names
    call word_index
    pop esi
    jnc .k
    xor eax, eax                ; not known: a note
.k:
    mov ecx, eax
    mov eax, [ncell]
    call insert_cell
    jnc .skip
    xor ebp, ebp
.skip:                          ; past the header line
    lodsb
    test al, al
    jz .end0
    cmp al, 10
    jne .skip
    jmp .l
.end0:
    dec esi
    jmp .l
.text:
    test ebp, ebp
    jnz .add
    mov edi, esi                ; text before any header: a note, unless
.bl:                            ; the line is blank
    mov al, [edi]
    cmp al, ' '
    je .bn
    cmp al, 13
    je .bn
    cmp al, 9
    je .bn
    cmp al, 10
    je .blank
    test al, al
    jz .blank
    mov eax, [ncell]
    xor ecx, ecx
    call insert_cell
    jnc .add
    xor ebp, ebp
    jmp .blank
.bn:
    inc edi
    jmp .bl
.blank:
    lodsb                       ; drop the line
    test al, al
    jz .end0
    cmp al, 10
    jne .blank
    jmp .l
.add:                           ; the line, with its newline
    lodsb
    test al, al
    jz .end0
    cmp al, 13
    je .add
    test ebp, ebp
    jz .a2
    mov edi, [ebp+C_LEN]
    cmp edi, SRCMAX
    jae .a2
    add edi, [ebp+C_SRC]
    mov [edi], al
    mov byte [edi+1], 0
    inc dword [ebp+C_LEN]
.a2:
    cmp al, 10
    jne .add
    jmp .l
.done:
    call .finish
    mov dword [sel], -1
    cmp dword [ncell], 0
    je .r
    mov dword [sel], 0
.r:
    popad
    ret
.finish:                        ; the newline before the next header
    test ebp, ebp
    jz .f
    mov edi, [ebp+C_LEN]
    test edi, edi
    jz .f
    add edi, [ebp+C_SRC]
    cmp byte [edi-1], 10
    jne .f
    mov byte [edi-1], 0
    dec dword [ebp+C_LEN]
.f:
    ret

; esi -> edi: a name (up to NAME_MAX, ends at a space or zero)
copy_name:
    mov ecx, NAME_MAX
.c:
    lodsb
    cmp al, ' '
    jbe .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    ret

; esi -> edi, edi ends on the zero
scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
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

%include "nut.inc"
%include "sqmath.inc"

; ---------- self-check ----------
; esi = keys: bytes; 0xE0 n = scancode n, 0xE1 n = Ctrl + scancode n,
; 0xE2 c = Ctrl + c
feed:
    pushad
.k:
    movzx eax, byte [esi]
    test eax, eax
    jz .r
    inc esi
    cmp al, 0xE0
    jb .send
    mov dl, al
    movzx eax, byte [esi]
    inc esi
    cmp dl, 0xE2
    je .ctrl
    shl eax, 8
    cmp dl, 0xE1
    jne .send
.ctrl:
    or eax, 1 << 16
.send:
    push esi
    call key
    pop esi
    jmp .k
.r:
    popad
    ret

; eax = a cell, esi = the output it should have -> CF (the output shown)
; unless it is that
want_out:
    pushad
    cmp eax, [ncell]
    jae .none
    call cell_ptr
    mov edi, [opool]
    add edi, [ebp+C_OUT]
    mov ecx, [ebp+C_OLEN]
    call strlen
    cmp eax, ecx
    jne .no
    repe cmpsb
    jne .no
    popad
    clc
    ret
.no:
    call gui_close              ; the text screen, for the report
    mov esi, m_got
    call gui_puts
    mov edi, tbuf
    mov esi, [opool]
    add esi, [ebp+C_OUT]
    mov ecx, [ebp+C_OLEN]
    cmp ecx, 120
    jbe .cp
    mov ecx, 120
.cp:
    rep movsb
    mov byte [edi], 0
    mov esi, tbuf
    call gui_puts
.n2:
    mov esi, nl
    call gui_puts
.none:
    popad
    stc
    ret

; ecx = colour, eax, ebx = a pixel -> CF unless that colour is within
; two pixels of it on the screen
ink_near:
    pushad
    mov esi, eax
    mov edi, ebx
    lea ebx, [edi-2]
.y:
    lea eax, [esi-2]
.x:
    push ecx
    call gui_peek
    cmp cl, [esp]
    pop ecx
    je .yes
    inc eax
    lea edx, [esi+2]
    cmp eax, edx
    jle .x
    inc ebx
    lea edx, [edi+2]
    cmp ebx, edx
    jle .y
    popad
    stc
    ret
.yes:
    popad
    clc
    ret

%macro WOUT 2                    ; cell, its output
    mov eax, %1
    mov esi, %%s
    call want_out
    jc .fail
    jmp %%e
%%s db %2, 0
%%e:
%endmacro
%macro FEED 1
    mov esi, %%k
    call feed
    jmp %%e
%%k db %1, 0
%%e:
%endmacro

selftest:
    mov byte [bad], 'a'
    mov esi, ntests
.t:
    cmp byte [esi], 0
    je .nb
    push esi
    call nut_reset
    call nut_run
    pop esi
    jnc .ran
    mov eax, [nut_errmsg]       ; an error: "!message"
    mov edi, [nut_out]
    add edi, [nut_olen]
    mov byte [edi], '!'
    inc edi
    push esi
    mov esi, eax
.cp:
    lodsb
    stosb
    test al, al
    jnz .cp
    pop esi
.ran:
.skip:
    lodsb
    test al, al
    jnz .skip
    mov edi, [nut_out]
    push esi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .nfail
    inc esi
    inc edi
    test al, al
    jnz .c
    pop esi
.n:
    lodsb
    test al, al
    jnz .n
    inc byte [bad]
    jmp .t
.nfail:
    pop esi
    push esi
    mov esi, m_nfail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov esi, [nut_out]
    call gui_puts
    mov esi, nl
    call gui_puts
    pop esi
    inc dword [nfail]
    jmp .n
.nb:                            ; sqmath, line by line (C.1)
    call sqm_reset
    mov byte [bad], 'a'
    mov esi, mtests
.m:
    cmp byte [esi], 0
    je .nb2
    push esi
    call sqm_line
    pop esi
    mov edi, sqm_out
    jnc .mr
    mov edi, tbuf
    mov byte [edi], '!'
    push esi
    mov esi, [sqm_err]
    inc edi
    call scopy
    pop esi
    mov edi, tbuf
.mr:
    lodsb                       ; past the line
    test al, al
    jnz .mr
    push esi
    push edi
.mc:
    mov al, [esi]
    cmp al, [edi]
    jne .mfail
    inc esi
    inc edi
    test al, al
    jnz .mc
    pop edi
    pop esi
.mn:
    lodsb
    test al, al
    jnz .mn
    inc byte [bad]
    jmp .m
.mfail:
    pop edi
    pop esi
    push esi
    mov esi, m_mfail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov esi, edi
    call gui_puts
    mov esi, nl
    call gui_puts
    pop esi
    inc dword [nfail]
    jmp .mn
.nb2:                           ; a notebook with every kind of cell
    call gui_open
    jc .nogfx
    mov byte [bad], 'A'
    mov esi, tnb
    call parse_nb
    cmp dword [ncell], 9
    jne .fail
    call run_all
    mov byte [bad], 'B'
    WOUT 0, ''
    WOUT 1, {'15', 10}
    WOUT 2, {'30', 10}
    mov byte [bad], 'C'         ; the graph of y = x on 0 .. 10
    WOUT 3, {'y = x', 10, 'x: 0 .. 10   y: 0 .. 10', 10}
    mov byte [bad], 'D'
    WOUT 4, {'         A       B       C', 10, ' 1       1       2       3', 10, ' 2      45 hi      hi!', 10}
    mov byte [bad], 'E'
    WOUT 5, {'d = 5', 10, 'area A B C = 6', 10, 'angle B A C = 90', 10}
    mov byte [bad], 'F'         ; variables from a table and a figure
    WOUT 6, {'8 45', 10}
    WOUT 7, {'! line 1: unknown variable', 10}
    WOUT 8, {'w = 10 m', 10, 's + w / [m] = 25', 10}
    mov byte [bad], 'G'         ; drawn: the line y = x through the
    call draw                   ; middle of its box
    mov eax, 3
    call cell_ptr
    mov ebx, [ebp+C_Y]
    add ebx, VY0 + PAD + GH / 2 - 1
    cmp ebx, VY0 + VH - 4
    jae .fail
    mov eax, X0 + GW / 2
    mov ecx, C_BLUE
    call ink_near
    jc .fail
    mov byte [bad], 'H'         ; the figure: B's label
    mov eax, 5
    call cell_ptr
    cmp dword [ebp+C_G], -1
    je .fail
    mov byte [bad], 'I'         ; edited: Enter, "+1", Esc
    mov dword [sel], 2
    FEED {0xE0, K_ENTER, '+1'}
    call draw
    FEED {0xE0, K_ESC}
    WOUT 2, {'31', 10}
    mov byte [bad], 'J'         ; the editor's keys
    FEED {0xE0, K_ENTER, 0xE0, K_HOME, 0xE0, K_DEL, 'p', 0xE0, K_END, 0xE0, K_BKSP, '2', 0xE0, K_ESC}
    WOUT 2, {'32', 10}
    mov byte [bad], 'K'         ; a new cell, two lines
    FEED {'c', 'print "hi"', 0xE0, K_ENTER, 'print 2', 0xE0, K_UP, 0xE0, K_END, '+1', 0xE0, K_ESC}
    cmp dword [ncell], 10
    jne .fail
    WOUT 3, {'hi1', 10, '2', 10}
    mov byte [bad], 'L'         ; removed again
    FEED {0xE0, K_DEL}
    cmp dword [ncell], 9
    jne .fail
    WOUT 3, {'y = x', 10, 'x: 0 .. 10   y: 0 .. 10', 10}
    mov byte [bad], 'M'         ; moved down past the graph and back
    mov dword [sel], 2
    FEED {0xE1, K_DOWN}
    cmp dword [sel], 3
    jne .fail
    WOUT 3, {'32', 10}
    WOUT 2, {'y = x', 10, 'x: 0 .. 10   y: 0 .. 10', 10}
    FEED {0xE1, K_UP}
    WOUT 2, {'32', 10}
    mov byte [bad], 'N'         ; to the end: the page scrolls
    FEED {0xE0, K_END}
    cmp dword [sel], 8
    jne .fail
    cmp dword [scroll], 0
    je .fail
    call draw
    mov byte [bad], 'O'         ; saved and loaded again
    mov esi, s_tfile
    mov edi, fname
    call scopy
    FEED {0xE2, 's'}
    cmp byte [dirty], 0
    jne .fail
    call init_cells
    call load
    cmp dword [ncell], 9
    jne .fail
    call run_all
    WOUT 2, {'32', 10}
    WOUT 5, {'d = 5', 10, 'area A B C = 6', 10, 'angle B A C = 90', 10}
    WOUT 6, {'8 45', 10}
    WOUT 8, {'w = 10 m', 10, 's + w / [m] = 25', 10}
    mov byte [bad], 'P'         ; errors in graphs, tables and figures
    mov esi, tbad
    call parse_nb
    call run_all
    WOUT 0, {'! line 1: the range must go from low to high', 10, 'y = sqrt(0-1-x*x)', 10, '! curve 1: outside the function domain', 10, 'x: -10 .. 10   y: -1 .. 1', 10}
    WOUT 1, {'         A       B', 10, ' 1 #ERR          1', 10, '! A1: unknown variable', 10}
    WOUT 2, {'! line 1: there is no point P', 10, '! line 2: unknown command', 10, '! line 3: a point is written N = (x, y)', 10}
    jmp .done
.fail:
    call gui_close
    mov esi, m_fail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov esi, nl
    call gui_puts
    inc dword [nfail]
.done:
    call gui_close
    cmp dword [nfail], 0
    jne .bad
    mov esi, m_pass
    call gui_puts
    xor eax, eax
    ret
.bad:
    mov esi, m_failall
    call gui_puts
    mov eax, 1
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- data ----------
align 8
f_10    dq 10.0
f_m10   dq -10.0
f_half  dq 0.5
f_180   dq 180.0
f_24    dq 24.0
f_3000  dq 3000.0
f_tiny  dq 1e-9
f_big   dq 1e6
run_fn  dd run_none, run_code, run_graph, run_table, run_geo, run_math
g_code  dd run_geo.seg, run_geo.line, run_geo.circle, run_geo.poly
        dd run_geo.dist, run_geo.angle, run_geo.area
g_cmds  db 'seg', 0, 'line', 0, 'circle', 0, 'poly', 0, 'dist', 0
        db 'angle', 0, 'area', 0, 0
kind_names db 'note', 0, 'code', 0, 'graph', 0, 'table', 0, 'geo', 0, 'math', 0, 0
curve_col db C_BLUE, C_RED, C_GREEN, C_MAGENTA
s_default db 'notebook.nb', 0
s_tfile db 'nbtest.nb', 0
s_title db 'Notebook - ', 0
s_edit  db 'Edit the ', 0
s_edit2 db ' cell', 0
s_hdr   db '%% ', 0
s_yeq   db 'y = ', 0
s_xr    db 'x: ', 0
s_yr    db '   y: ', 0
s_to    db ' .. ', 0
s_eq    db ' = ', 0
s_bang  db '! ', 0
s_bangc db '! curve ', 0
s_line  db 'line ', 0
s_colon db ': ', 0
s_err   db '#ERR    '
s_lnum  db 'line ', 0
s_cnum  db ', col ', 0
s_ekeys db '   Esc: done (the notebook runs)', 0
s_keys0 db 'N C G T O M: a new cell   Esc: quit', 0
s_keys  db '  Enter edit  NCGTOM new  Del', 0
s_hint1 db 'An empty notebook.', 0
s_hint2 db 'N note  C code  G graph  T table  O geo  M math', 0
s_enote db '(an empty note: Enter to write)', 0
s_etable db '(an empty table: Enter to fill)', 0
s_emath db '(empty math: Enter to write)', 0
m_nogfx db 'notebook: no graphics', 10, 0
m_saved db 'Saved.', 0
m_nosave db 'Could not save.', 0
m_opened db 'Opened.', 0
m_newfile db 'A new notebook.', 0
m_ran   db 'Ran every cell.', 0
m_full  db 'The notebook is full.', 0
m_range db 'the range must go from low to high', 0
m_two   db 'two numbers are wanted', 0
m_four  db 'four curves at most', 0
m_nopts db 'there is no value to draw', 0
m_nomem db 'no room for more shapes', 0
m_wantnum db 'a number is wanted', 0
m_unkcmd db 'unknown command', 0
m_badpt db 'a point is written N = (x, y)', 0
m_manypts db 'too many points', 0
m_ptname db 'a point name is missing', 0
m_nopt  db 'there is no point ', 0
m_few   db 'more points are wanted', 0
m_three db 'three points are wanted', 0
m_nfail db 'nut FAIL: ', 0
m_mfail db 'sqmath FAIL: ', 0
m_fail  db 'notebook FAIL: ', 0
m_got   db '  got: ', 0
m_pass  db 'notebook: PASS', 10, 0
m_failall db 'notebook: FAIL', 10, 0
nl      db 10, 0
bad     db '?', 0

tnb:
    db '%% note', 10, '# Test', 10, 'Some words.', 10
    db '%% code', 10, 's = 0', 10, 'for i = 1 to 5 do s = s + i end', 10, 'print s', 10
    db '%% code', 10, 'print s * 2', 10
    db '%% graph', 10, 'x: 0 10', 10, 'y: 0 10', 10, 'x', 10
    db '%% table', 10, '1 | 2 | =A1+B1', 10, '=C1*s | hi | =B2 + "!"', 10
    db '%% geo', 10, 'A = (0, 0)', 10, 'B = (4, 0)', 10, 'C = (0, 3)', 10
    db 'poly A B C', 10, 'd = dist B C', 10, 'area A B C', 10, 'angle B A C', 10
    db '%% code', 10, 'print d + C1, A2', 10
    db '%% code', 10, 'print zz', 10
    db '%% math', 10, 'w = d * 2 [m]', 10, 's + w / [m]', 10, 0
tbad:
    db '%% graph', 10, 'x: 3 1', 10, 'y = sqrt(0-1-x*x)', 10
    db '%% table', 10, '=nope | 1', 10
    db '%% geo', 10, 'seg P Q', 10, 'frob A', 10, 'N = (1, 2', 10, 0

mtests:
    db '1 + 2*3', 0, '7', 0
    db 'sqrt(-4)', 0, '2i', 0
    db '(1+2i)*(3-i)', 0, '5 + 5i', 0
    db '(1+2i)/(3-4i)', 0, '-0.2 + 0.4i', 0
    db 'abs(3+4i)', 0, '5', 0
    db 'e^(i*pi)', 0, '-1', 0
    db 'ln(-1)/pi', 0, 'i', 0
    db '2i^2', 0, '-2', 0
    db 'f(x) = x^2 + 1', 0, 'f(x) = x^2 + 1', 0
    db 'f(3)', 0, '10', 0
    db 'g(a, b) = a*b + f(a)', 0, 'g(a, b) = a*b + f(a)', 0
    db 'g(2, 5)', 0, '15', 0
    db 'a = 2 [km] + 300 [m]', 0, 'a = 2300 m', 0
    db 'a to [km]', 0, '2.3 km', 0
    db 'v = 90 [km/h] to [m/s]', 0, 'v = 25 m/s', 0
    db 'v * 2 [s]', 0, '50 m', 0
    db '9.8 [m/s^2] * 70 [kg]', 0, '686 N', 0
    db '1 [h] to [min]', 0, '60 min', 0
    db '3 [m] / 2 [s]', 0, '1.5 m/s', 0
    db '[m] + [s]', 0, '!the units do not match', 0
    db 'ans * 2 [s]', 0, '3 m', 0
    db '2e3 + 1.5e-1', 0, '2000.15', 0
    db 'digits 50', 0, 'digits: 50', 0
    db '1/3', 0, '0.33333333333333333333333333333333333333333333333333', 0
    db 'pi', 0, '3.14159265358979323846264338327950288419716939937511', 0
    db 'sqrt(2)', 0, '1.41421356237309504880168872420969807856967187537695', 0
    db '2^100', 0, '1267650600228229401496703205376', 0
    db '30!', 0, '265252859812191058636308480000000', 0
    db '0.1 + 0.2 - 0.3', 0, '0', 0
    db '-7/4', 0, '-1.75', 0
    db 'e', 0, '2.71828182845904523536028747135266249775724709369996', 0
    db 'digits 0', 0, 'digits: off (doubles)', 0
    db '1/0', 0, '!division by zero', 0
    db 'zz + 1', 0, '!unknown name', 0
    db 'sin(pi/2) + cos(0)', 0, '2', 0
    db 'asin(2)', 0, '!outside the function domain', 0
    db '(1 + 2', 0, '!a ) is missing', 0
    db 0

ntests:
    db 'print 1 + 2 * 3', 0, '7', 10, 0
    db 'x = 2', 10, 'print x ^ 3, "and", x % 3', 0, '8 and 2', 10, 0
    db 'if 3 > 2 then print "yes" else print "no" end', 0, 'yes', 10, 0
    db 'i = 0', 10, 's = 0', 10, 'while i < 5 do', 10, ' i = i + 1', 10, ' s = s + i', 10, 'end', 10, 'print s', 0, '15', 10, 0
    db 'for i = 1 to 3 do print i end', 0, '1', 10, '2', 10, '3', 10, 0
    db 'fn f(n)', 10, ' if n < 2 then return 1 end', 10, ' return n * f(n - 1)', 10, 'end', 10, 'print f(5)', 0, '120', 10, 0
    db 'print "a" + 1 + 2', 0, 'a12', 10, 0
    db 'print sqrt(16), abs(-3), floor(2.7), max(1, 5, 3)', 0, '4 3 2 5', 10, 0
    db 'for i = 10 to 1 step -3 do print i end', 0, '10', 10, '7', 10, '4', 10, '1', 10, 0
    db 'n = 0', 10, 'while true do', 10, ' n = n + 1', 10, ' if n == 4 then break end', 10, 'end', 10, 'print n', 0, '4', 10, 0
    db 'print 1 / 0', 0, '!division by zero', 0
    db 'print y', 0, '!unknown variable', 0
    db 'x = 1', 10, 'if x == 1 then', 10, 'print "one"', 10, 'elif x == 2 then', 10, 'print "two"', 10, 'else', 10, 'print "many"', 10, 'end', 0, 'one', 10, 0
    db 'x = 2', 10, 'if x == 1 then print "one" elif x == 2 then print "two" else print "many" end', 0, 'two', 10, 0
    db 'print "b" < "c", 2 >= 3, not 0, 1 and 0 or 1', 0, '1 0 1 1', 10, 0
    db 'g = 5', 10, 'fn add(a) return a + g end', 10, 'print add(1)', 0, '6', 10, 0
    db 'fn fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end', 10, 'print fib(15)', 0, '610', 10, 0
    db 'print len("acorn"), str(3) + "!"', 0, '5 3!', 10, 0
    db 'while 1 do end', 0, '!too many steps (a loop that never ends?)', 0
    db 'if 1 then print 2', 0, '2', 10, '!end is missing', 0
    db 0

SQX_BSS
arg     resd 1
slots   resd 1
opool   resd 1
gpool   resd 1
fbuf    resd 1
flen    resd 1
ncell   resd 1
sel     resd 1
scroll  resd 1
doch    resd 1
msg     resd 1
opos    resd 1
ostart  resd 1
gpos    resd 1
gptr    resd 1
lp      resd 1
lno     resd 1
lstart  resd 1
tptr    resd 1
ncurve  resd 1
ctok    resd NCURVE
gdef    resd 1
tmpi    resd 1
tcols   resd 1
tcol    resd 1
trow    resd 1
vlen    resd 1
errlen  resd 1
npts    resd 1
pa      resd 1
pb      resd 1
pn      resd 1
plist   resd 16
ptype   resd 1
lastprim resd 1
tkind   resd 1
ccount  resd 1
dl_start resd 1
boxy    resd 1
gpx     resd 1
gpy     resd 1
ecell   resd 1
ecur    resd 1
etop    resd 1
hoff    resd 1
cline   resd 1
ccol    resd 1
nfail   resd 1
alignb 8
gxa     resq 1
gxb     resq 1
gya     resq 1
gyb     resq 1
gdx     resq 1
gk      resq 1
gkx     resq 1
t1      resq 1
t2      resq 1
px      resq 1
py      resq 1
bminx   resq 1
bmaxx   resq 1
bminy   resq 1
bmaxy   resq 1
gpts    resb GPTMAX * GPT_SIZE
cells   resb MAXCELL * CSIZE
editing resb 1
dirty   resb 1
dry     resb 1
tmode   resb 1
lcol    resb 1
lbg     resb 1
yauto   resb 1
gany    resb 1
gprev   resb 1
tlast   resb 1
fname   resb NAME_MAX + 4
vname   resb 16
wbuf    resb 16
nmbuf   resb 16
nbuf    resb 16
lbuf    resb 256
ebuf    resb 256
cbuf    resb 128
tbuf    resb 256
errbuf  resb 512
GUI_BSS
NUT_BSS
SQM_BSS
SQX_END
