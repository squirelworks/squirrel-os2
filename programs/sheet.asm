; Squirrel-OS/2 — Sheet: a spreadsheet linked to charts (C.4, OS2-APPS)
; Original code. run sheet [file.csv]   |   run sheet test
;
; 26 columns (A-Z) by 99 rows. A cell holds a number (any sci expression
; that starts like one: 2.5, -3, (1/3)), text, or a formula that starts
; with "=": sci's operators and functions, cell references (B7, or $B$7
; to keep a part fixed when copied) and the range functions sum, avg,
; min, max and count over a block (sum(A1:C4)). Every cell is worked out
; again after each change: a cell that depends on itself shows #CYC, one
; that cannot be worked out #ERR (an empty cell counts as 0; text in a
; formula is an error, but range functions skip it).
;
;   arrows, Tab, PgUp, PgDn, Home   move (Ctrl+Home: A1)
;   typing                 start a new entry in the cell; Enter (down),
;                          Tab (right) or an arrow keeps it, Esc drops it
;   Enter, F2              change the cell's entry
;   Delete                 empty the cell, or every cell of the selection
;   F3                     start a selection at the cursor; moving the
;                          cursor extends it (a mouse drag selects too)
;   Ctrl+C, Ctrl+V         copy the cell or the selection; paste at the
;                          cursor, references moved along (not $ parts)
;   Ctrl+D, Ctrl+R         fill the selection down / right from its
;                          first row / column, references moved along
;   Ctrl+G                 a chart of the selection (each column a
;                          series; a first row of text names them); again
;                          without a selection: the next chart type (line,
;                          bar, scatter: the first column is x), then none.
;                          The chart follows the cells as they change.
;   Ctrl+S save (CSV)   Ctrl+N new   Esc  drop the selection, or quit
;
; Files are CSV: one line a row, the cells' entries (formulas as typed)
; separated by commas, quoted if they hold a comma or a quote.
; "run sheet test" checks formulas, ranges, cycles, copying and filling,
; the chart and a CSV round trip, and prints "sheet: PASS".
; See documentation/apps/sheet.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

NCOLS       equ 26
NROWS       equ 99
NCELLS      equ NCOLS * NROWS
CW          equ 48                      ; bytes of a cell's entry
EMAX        equ CW - 2
CLIP_MAX    equ 256                     ; cells Ctrl+C takes
FBUF        equ 65536                   ; a CSV file
DEPTH_MAX   equ 40                      ; formulas inside formulas
PASSES      equ 64                      ; recalc passes for longer chains
EXLEN       equ 240                     ; a formula with its values in
NAME_MAX    equ 60

ST_EMPTY    equ 0
ST_NUM      equ 1
ST_TEXT     equ 2
ST_ERR      equ 3
ST_CYC      equ 4
ST_BUSY     equ 5
ST_TODO     equ 6
ST_DEEP     equ 7                       ; (build: too deep, try again)

FY          equ WIN_TITLE_H + 3         ; the entry bar
GY          equ FY + CELL_H + 4         ; the grid's column letters
ROW_H       equ CELL_H + 1
RH_W        equ 3 * CELL_W + 2          ; row numbers
GX          equ 3 + RH_W                ; first column
COL_W       equ 7 * CELL_W + 3
VCOLS       equ 6
STAT_Y      equ SCR_H - CELL_H - 2
VROWS_ALL   equ (STAT_Y - GY - ROW_H - 2) / ROW_H
VROWS_CH    equ 8                       ; rows shown above a chart
CH_Y        equ GY + ROW_H * (VROWS_CH + 1) + 3
CH_X        equ 3
CH_W        equ SCR_W - 6
CH_H        equ STAT_Y - CH_Y - 2
PL_X        equ CH_X + 7 * CELL_W + 2   ; the plot inside the chart
PL_Y        equ CH_Y + CELL_H + 4
PL_W        equ CH_X + CH_W - 4 - PL_X
PL_H        equ CH_Y + CH_H - 3 - PL_Y

T_NONE      equ 0                       ; chart types
T_LINE      equ 1
T_BAR       equ 2
T_SCAT      equ 3

K_F3        equ 0x3D

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    mov eax, SYS_SBRK
    mov ebx, NCELLS * (CW + 8 + 1) + CLIP_MAX * CW + FBUF
    int 0x80
    cmp eax, -1
    je .nogfx
    mov [cells], eax
    add eax, NCELLS * CW
    mov [vals], eax
    add eax, NCELLS * 8
    mov [cst], eax
    add eax, NCELLS
    mov [clip], eax
    add eax, CLIP_MAX * CW
    mov [fbuf], eax
    mov esi, s_default
    mov edi, fname
    call scopy
    call clear_all
    call gui_open
    jc .nogfx
    mov esi, [arg]
    test esi, esi
    jz .draw
    cmp dword [esi], 'test'
    jne .file
    cmp byte [esi+4], 0
    je selftest
.file:
    cmp byte [esi], 0
    je .draw
    mov edi, fname
    call copy_name
    call load
.draw:
    call recalc
.redraw:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .drag
    call key
    jnc .redraw
    call gui_close
    xor eax, eax
    ret
.click:
    call commit_edit
    call cell_at_mouse
    jc .redraw
    mov [ccol], eax
    mov [crow], ebx
    mov dword [arow], -1
    jmp .draw
.drag:
    call cell_at_mouse
    jc .key
    cmp dword [arow], -1
    jne .d
    mov ecx, [ccol]
    mov [acol], ecx
    mov ecx, [crow]
    mov [arow], ecx
.d:
    mov [ccol], eax
    mov [crow], ebx
    call scroll
    jmp .redraw
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- keys ----------
; eax = a key -> CF to quit
key:
    pushad
    mov dword [msg], 0
    movzx ebx, ah
    cmp byte [editing], 0
    jne .edit
    test eax, 1 << 16
    jnz .ctrl
    cmp bl, K_ESC
    je .esc
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_TAB
    je .right
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_HOME
    je .home
    cmp bl, K_F3
    je .mark
    cmp bl, K_DEL
    je .del
    cmp bl, K_ENTER
    je .change
    cmp bl, K_F2
    je .change
    cmp al, ' '
    jbe .ok
    cmp al, '~'
    ja .ok
    mov [ebuf], al              ; a new entry
    mov byte [ebuf+1], 0
    mov dword [elen], 1
    mov byte [editing], 1
    jmp .ok
.ctrl:
    cmp bl, K_HOME
    je .a1
    and al, 0xDF
    cmp al, 'C'
    je .copy
    cmp al, 'V'
    je .paste
    cmp al, 'D'
    je .filld
    cmp al, 'R'
    je .fillr
    cmp al, 'G'
    je .chart
    cmp al, 'S'
    je .save
    cmp al, 'N'
    je .new
    jmp .ok
.esc:
    cmp dword [arow], -1
    je .quit
    mov dword [arow], -1
    jmp .ok
.quit:
    call ask_unsaved
    jc .ok
    popad
    stc
    ret
.up:
    mov ecx, -1
    jmp .vert
.down:
    mov ecx, 1
    jmp .vert
.pgup:
    mov ecx, -VROWS_CH
    jmp .vert
.pgdn:
    mov ecx, VROWS_CH
.vert:
    add ecx, [crow]
    jns .v1
    xor ecx, ecx
.v1:
    cmp ecx, NROWS
    jb .v2
    mov ecx, NROWS - 1
.v2:
    mov [crow], ecx
    jmp .ok
.left:
    cmp dword [ccol], 0
    je .ok
    dec dword [ccol]
    jmp .ok
.right:
    cmp dword [ccol], NCOLS - 1
    je .ok
    inc dword [ccol]
    jmp .ok
.home:
    mov dword [ccol], 0
    jmp .ok
.a1:
    mov dword [ccol], 0
    mov dword [crow], 0
    jmp .ok
.mark:
    mov ecx, [ccol]
    mov [acol], ecx
    mov ecx, [crow]
    mov [arow], ecx
    jmp .ok
.del:
    call sel_box
    call clear_box
    mov dword [arow], -1
    jmp .ok
.change:                        ; the entry as it is, to change
    call cur_idx
    call cell_ptr
    mov edi, ebuf
    call scopy
    sub edi, ebuf
    mov [elen], edi
    mov byte [editing], 1
    jmp .ok
.copy:
    call copy_sel
    jmp .ok
.paste:
    call paste
    jmp .ok
.filld:
    xor eax, eax
    call fill
    jmp .ok
.fillr:
    mov eax, 1
    call fill
    jmp .ok
.chart:
    call chart_key
    jmp .ok
.save:
    call save
    jmp .ok
.new:
    call ask_unsaved
    jc .ok
    call clear_all
    mov dword [ctype], T_NONE
    jmp .ok
.edit:                          ; typing an entry
    mov ecx, [elen]
    cmp bl, K_ESC
    je .drop
    cmp bl, K_ENTER
    je .e_down
    cmp bl, K_TAB
    je .e_right
    cmp bl, K_UP
    je .e_up
    cmp bl, K_DOWN
    je .e_down
    cmp bl, K_LEFT
    je .e_left
    cmp bl, K_RIGHT
    je .e_right
    cmp bl, K_BKSP
    je .bs
    test eax, 1 << 16
    jnz .ok
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    cmp ecx, EMAX
    jae .ok
    mov [ebuf+ecx], al
    inc ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .ok
.bs:
    test ecx, ecx
    jz .ok
    dec ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .ok
.drop:
    mov byte [editing], 0
    jmp .ok
.e_down:
    call commit_edit
    jmp .down
.e_up:
    call commit_edit
    jmp .up
.e_left:
    call commit_edit
    jmp .left
.e_right:
    call commit_edit
    jmp .right
.ok:
    call recalc
    call scroll
    popad
    clc
    ret

; The entry being typed goes into the cursor's cell (if typing)
commit_edit:
    pushad
    cmp byte [editing], 0
    je .r
    mov byte [editing], 0
    call cur_idx
    mov esi, ebuf
    call set_cell
    mov [err_idx], eax
    mov byte [lasterr], 0
    call recalc
    mov dword [err_idx], -1
    mov edx, [cst]
    cmp byte [edx+eax], ST_ERR
    jne .r
    cmp byte [lasterr], 0
    je .r
    mov dword [msg], s_errmsg
.r:
    popad
    ret

; The view follows the cursor
scroll:
    pushad
    mov eax, [ccol]
    cmp eax, [left]
    jae .c1
    mov [left], eax
.c1:
    sub eax, VCOLS - 1
    jbe .rows
    cmp eax, [left]
    jbe .rows
    mov [left], eax
.rows:
    call vrows
    mov ecx, eax
    mov eax, [crow]
    cmp eax, [top]
    jae .r1
    mov [top], eax
.r1:
    sub eax, ecx
    jb .r
    inc eax
    cmp eax, [top]
    jbe .r
    mov [top], eax
.r:
    popad
    ret

; -> eax = rows of the grid on the screen
vrows:
    mov eax, VROWS_ALL
    cmp dword [ctype], T_NONE
    je .r
    mov eax, VROWS_CH
.r:
    ret

; gui_mx, gui_my -> eax = column, ebx = row, or CF off the grid
cell_at_mouse:
    push ecx
    push edx
    mov eax, [gui_mx]
    sub eax, GX
    jb .no
    xor edx, edx
    mov ecx, COL_W
    div ecx
    cmp eax, VCOLS
    jae .no
    add eax, [left]
    cmp eax, NCOLS
    jae .no
    push eax
    mov eax, [gui_my]
    sub eax, GY + ROW_H
    jb .no1
    xor edx, edx
    mov ecx, ROW_H
    div ecx
    push eax
    call vrows
    mov ecx, eax
    pop eax
    cmp eax, ecx
    jae .no1
    add eax, [top]
    cmp eax, NROWS
    jae .no1
    mov ebx, eax
    pop eax
    pop edx
    pop ecx
    clc
    ret
.no1:
    pop eax
.no:
    pop edx
    pop ecx
    stc
    ret

; ---------- cells ----------
; -> eax = the cursor's cell
cur_idx:
    mov eax, [crow]
    imul eax, NCOLS
    add eax, [ccol]
    ret

; eax = cell -> esi = its entry
cell_ptr:
    imul esi, eax, CW
    add esi, [cells]
    ret

; eax = cell, esi = entry: stored (cut to EMAX), marked changed
set_cell:
    pushad
    push esi
    call cell_ptr
    mov edi, esi
    pop esi
    mov ecx, EMAX
.c:
    lodsb
    test al, al
    jz .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    mov byte [dirty], 1
    popad
    ret

clear_all:
    pushad
    mov edi, [cells]
    mov ecx, NCELLS * CW / 4
    xor eax, eax
    rep stosd
    mov dword [ccol], 0
    mov dword [crow], 0
    mov dword [top], 0
    mov dword [left], 0
    mov dword [arow], -1
    mov dword [err_idx], -1
    mov byte [dirty], 0
    mov byte [editing], 0
    call recalc
    popad
    ret

; -> eax, ebx = first column, row; ecx, edx = last: the selection, or the
; cursor's cell alone
sel_box:
    mov eax, [ccol]
    mov ebx, [crow]
    mov ecx, eax
    mov edx, ebx
    cmp dword [arow], -1
    je .r
    mov ecx, [acol]
    mov edx, [arow]
    cmp eax, ecx
    jbe .c
    xchg eax, ecx
.c:
    cmp ebx, edx
    jbe .r
    xchg ebx, edx
.r:
    ret

; eax, ebx, ecx, edx as sel_box: those cells emptied
clear_box:
    pushad
    mov esi, ebx
.row:
    mov edi, eax
.col:
    push eax
    imul eax, esi, NCOLS
    add eax, edi
    push esi
    call cell_ptr
    mov byte [esi], 0
    pop esi
    pop eax
    inc edi
    cmp edi, ecx
    jbe .col
    inc esi
    cmp esi, edx
    jbe .row
    mov byte [dirty], 1
    popad
    ret

; ---------- working out the cells ----------
recalc:
    pushad
    mov dword [depth], 0
    mov esi, [cells]
    mov edi, [cst]
    xor ecx, ecx
.mark:
    mov byte [edi+ecx], ST_EMPTY
    cmp byte [esi], 0
    je .m1
    mov byte [edi+ecx], ST_TODO
.m1:
    add esi, CW
    inc ecx
    cmp ecx, NCELLS
    jb .mark
    mov ebx, PASSES
.pass:                          ; row by row: a cell's upper neighbours first
    mov byte [deep_hit], 0
    xor eax, eax
.all:
    call eval_cell
    inc eax
    cmp eax, NCELLS
    jb .all
    cmp byte [deep_hit], 0
    je .r
    dec ebx
    jnz .pass
    xor eax, eax                ; still not done: too deep
.left:
    cmp byte [edi+eax], ST_TODO
    jne .l1
    mov byte [edi+eax], ST_ERR
.l1:
    inc eax
    cmp eax, NCELLS
    jb .left
.r:
    popad
    ret

; eax = cell: its state and value worked out (if not yet)
eval_cell:
    pushad
    mov edx, [cst]
    cmp byte [edx+eax], ST_TODO
    jne .r
    mov [cell_now], eax
    call cell_ptr
    cmp byte [esi], '='
    je .formula
    mov cl, [esi]               ; a number starts like one
    cmp cl, '('
    je .num
    cmp cl, '-'
    je .num
    cmp cl, '+'
    je .num
    cmp cl, '.'
    je .num
    cmp cl, '0'
    jb .text
    cmp cl, '9'
    ja .text
.num:
    call evaluate
    jc .text
    mov ecx, ST_NUM
    jmp .set
.text:
    mov ecx, ST_TEXT
    jmp .store
.formula:
    mov byte [edx+eax], ST_BUSY
    mov ecx, [depth]
    cmp ecx, DEPTH_MAX
    jae .deep
    inc dword [depth]
    imul edi, ecx, EXLEN
    add edi, exbuf
    push edi
    inc esi
    call build
    pop esi
    dec dword [depth]
    jc .bad                     ; ecx = the state a reference gave
    push eax
    call evaluate
    pop eax
    jc .err
    mov ecx, ST_NUM
    jmp .set
.deep:
    mov ecx, ST_DEEP
.bad:
    cmp ecx, ST_DEEP            ; too deep: later, from cells done by then
    jne .store
    mov byte [deep_hit], 1
    mov ecx, ST_TODO
    jmp .store
.err:
    mov ecx, ST_ERR
    cmp eax, [err_idx]
    jne .store
    push esi
    push edi
    mov esi, etext
    mov edi, lasterr
    call scopy
    pop edi
    pop esi
    jmp .store
.set:
    mov ebx, [vals]
    fld qword [val]
    fstp qword [ebx+eax*8]
.store:
    mov edx, [cst]
    mov [edx+eax], cl
.r:
    popad
    ret

; esi = formula after "=", edi = buffer (EXLEN) -> the expression with
; each reference and range function replaced by its value; or CF and
; ecx = ST_ERR / ST_CYC
build:
    push eax
    push ebx
    push edx
    push ebp
    lea ebp, [edi+EXLEN-2]      ; the end
    mov byte [prev], ' '
.c:
    mov al, [esi]
    test al, al
    jz .done
    mov dl, [prev]
    call is_alnum
    je .copy                    ; inside a word or number
    call parse_ref
    jnc .ref
    mov al, [esi]
    call is_alpha
    jne .copy
    call range_fn
    jnc .emit
    test ecx, ecx
    jnz .fail
.word:                          ; any other word: as it is, lower case
    mov al, [esi]
    mov dl, al
    call is_alnum
    jne .c
    call is_alpha
    jne .w2
    or al, 0x20
.w2:
    mov [prev], al
    inc esi
    cmp edi, ebp
    jae .long
    stosb
    jmp .word
.ref:                           ; eax = column, ebx = row
    imul eax, [rrow], NCOLS
    add eax, [rcol]
    call eval_cell
    mov edx, [cst]
    movzx ecx, byte [edx+eax]
    cmp ecx, ST_BUSY
    je .cyc
    cmp ecx, ST_CYC
    je .fail
    cmp ecx, ST_TODO
    je .deeper
    cmp ecx, ST_EMPTY
    je .zero
    cmp ecx, ST_NUM
    jne .err
    mov edx, [vals]
    fld qword [edx+eax*8]
    fstp qword [numv]
.emit:                          ; numv, in brackets
    call full_text
    push esi
    mov esi, nbuf
    call strlen
    lea ecx, [edi+eax+2]
    cmp ecx, ebp
    jae .long1
    mov al, '('
    stosb
    call scopy
    mov al, ')'
    stosb
    pop esi
    mov byte [prev], ')'
    jmp .c
.long1:
    pop esi
    jmp .long
.zero:
    fldz
    fstp qword [numv]
    jmp .emit
.copy:
    mov [prev], al
    inc esi
    cmp edi, ebp
    jae .long
    stosb
    jmp .c
.done:
    mov byte [edi], 0
    pop ebp
    pop edx
    pop ebx
    pop eax
    clc
    ret
.cyc:
    mov ecx, ST_CYC
    jmp .fail
.deeper:
    mov ecx, ST_DEEP
    jmp .fail
.long:
    mov dword [etext], 'too '
    mov dword [etext+4], 'long'
    mov byte [etext+8], 0
.err:
    mov ecx, ST_ERR
.fail:
    pop ebp
    pop edx
    pop ebx
    pop eax
    stc
    ret

; al, dl: ZF if al is a letter (is_alpha) / letter or digit or "." or "$"
; (is_alnum, for dl the character before)
is_alpha:
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
    test esp, esp               ; ZF clear
    pop eax
    ret
is_alnum:
    push eax
    mov al, dl
    cmp al, '.'
    je .y
    cmp al, '$'
    je .y
    cmp al, '_'
    je .y
    cmp al, '0'
    jb .a
    cmp al, '9'
    jbe .y
.a:
    call is_alpha
    pop eax
    ret
.y:
    cmp al, al
    pop eax
    ret

; esi = text -> a reference ([$]letter[$]digits, not followed by a letter,
; digit or "("): rcol, rrow, rabs (bit 0 column, bit 1 row), esi after
; it; or CF and esi as it was
parse_ref:
    push eax
    push ecx
    push edx
    push esi
    xor edx, edx                ; rabs
    cmp byte [esi], '$'
    jne .l
    or edx, 1
    inc esi
.l:
    movzx eax, byte [esi]
    or al, 0x20
    sub al, 'a'
    cmp al, 25
    ja .no
    mov [rcol], eax
    inc esi
    cmp byte [esi], '$'
    jne .d
    or edx, 2
    inc esi
.d:
    xor ecx, ecx                ; the row number
    movzx eax, byte [esi]
    sub al, '0'
    cmp al, 9
    ja .no
.dig:
    imul ecx, 10
    add ecx, eax
    cmp ecx, NROWS
    ja .no
    inc esi
    movzx eax, byte [esi]
    sub al, '0'
    cmp al, 9
    jbe .dig
    test ecx, ecx
    jz .no
    mov al, [esi]
    cmp al, '('
    je .no
    push edx
    mov dl, al
    call is_alnum
    pop edx
    je .no
    dec ecx
    mov [rrow], ecx
    mov [rabs], edx
    add esp, 4
    pop edx
    pop ecx
    pop eax
    clc
    ret
.no:
    pop esi
    pop edx
    pop ecx
    pop eax
    stc
    ret

; esi = a word: sum/avg/min/max/count "(" ref ":" ref ")" -> numv and esi
; after it; or CF with ecx = 0 (not one: esi as it was) or a state
range_fn:
    push eax
    push ebx
    push edx
    push edi
    push esi
    mov edi, fn_names
    xor ebx, ebx
.n:
    cmp byte [edi], 0
    je .none
    push esi
.cmp:
    mov al, [esi]
    or al, 0x20
    cmp al, [edi]
    jne .ne
    inc esi
    inc edi
    cmp byte [edi], 0
    jne .cmp
    cmp byte [esi], '('
    je .found
    add esp, 4
    jmp .none
.ne:
    pop esi
.skip:
    inc edi
    cmp byte [edi-1], 0
    jne .skip
    inc ebx
    jmp .n
.found:
    add esp, 4
    mov [fn_kind], ebx
    inc esi
    call parse_ref
    jc .none
    mov eax, [rcol]
    mov [r0c], eax
    mov eax, [rrow]
    mov [r0r], eax
    cmp byte [esi], ':'
    jne .none
    inc esi
    call parse_ref
    jc .none
    cmp byte [esi], ')'
    jne .none
    inc esi
    mov [esp], esi              ; esi after it, when done
    mov eax, [r0c]              ; the block, in order
    mov ecx, [rcol]
    cmp eax, ecx
    jbe .o1
    xchg eax, ecx
.o1:
    mov [r0c], eax
    mov [r1c], ecx
    mov eax, [r0r]
    mov ecx, [rrow]
    cmp eax, ecx
    jbe .o2
    xchg eax, ecx
.o2:
    mov [r0r], eax
    mov [r1r], ecx
    push dword [r0c]            ; nested range functions reuse these
    push dword [r1c]
    push dword [r0r]
    push dword [r1r]
    push dword [fn_kind]
    mov ebx, [r0r]              ; each cell worked out first
.er:
    mov eax, [esp+16]
.ec:
    push eax
    imul edx, ebx, NCOLS
    add eax, edx
    call eval_cell
    mov edx, [cst]
    movzx ecx, byte [edx+eax]
    pop eax
    cmp ecx, ST_BUSY
    je .rcyc
    cmp ecx, ST_TODO
    je .rdeep
    cmp ecx, ST_CYC
    je .rfail
    cmp ecx, ST_ERR
    je .rfail
    inc eax
    cmp eax, [esp+12]
    jbe .ec
    inc ebx
    cmp ebx, [esp+4]
    jbe .er
    pop dword [fn_kind]
    pop dword [r1r]
    pop dword [r0r]
    pop dword [r1c]
    pop dword [r0c]
    call aggregate
    jc .empty
    pop esi
    pop edi
    pop edx
    pop ebx
    pop eax
    clc
    ret
.rdeep:
    mov ecx, ST_DEEP
    jmp .rfail
.rcyc:
    mov ecx, ST_CYC
.rfail:
    add esp, 20
    jmp .fail
.empty:
    mov dword [etext], 'no n'
    mov dword [etext+4], 'umbe'
    mov dword [etext+8], 'rs'
    mov ecx, ST_ERR
    jmp .fail
.none:
    xor ecx, ecx
    pop esi
    push esi
.fail:
    pop esi
    pop edi
    pop edx
    pop ebx
    pop eax
    stc
    ret

; fn_kind over r0c..r1c, r0r..r1r (cells worked out) -> numv, or CF if
; there are no numbers (but count is 0 then)
aggregate:
    pushad
    fldz                        ; sum
    xor ecx, ecx                ; count
    mov ebx, [r0r]
.r:
    mov eax, [r0c]
.c:
    imul edx, ebx, NCOLS
    add edx, eax
    mov edi, [cst]
    cmp byte [edi+edx], ST_NUM
    jne .n
    mov edi, [vals]
    fld qword [edi+edx*8]
    test ecx, ecx
    jnz .mm
    fst qword [amin]
    fst qword [amax]
.mm:
    fld qword [amin]
    fcomip st0, st1
    jbe .m1
    fst qword [amin]
.m1:
    fld qword [amax]
    fcomip st0, st1
    jae .m2
    fst qword [amax]
.m2:
    faddp st1, st0
    inc ecx
.n:
    inc eax
    cmp eax, [r1c]
    jbe .c
    inc ebx
    cmp ebx, [r1r]
    jbe .r
    mov eax, [fn_kind]
    cmp eax, 4                  ; count
    jne .notc
    fstp st0
    mov [tmp], ecx
    fild dword [tmp]
    jmp .ok
.notc:
    test ecx, ecx
    jnz .some
    fstp st0
    test eax, eax               ; sum of nothing: 0
    jnz .no
    fldz
    jmp .ok
.some:
    cmp eax, 1
    jne .notavg
    mov [tmp], ecx
    fidiv dword [tmp]
    jmp .ok
.notavg:
    cmp eax, 2
    jne .notmin
    fstp st0
    fld qword [amin]
    jmp .ok
.notmin:
    cmp eax, 3
    jne .ok
    fstp st0
    fld qword [amax]
.ok:
    fstp qword [numv]
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = expression -> val, or CF (the message in etext)
evaluate:
    pushad
    mov [ev+GE_EXPR], esi
    mov dword [ev+GE_FLAGS], 0
    mov dword [ev+GE_TEXT], etext
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    test eax, eax
    jnz .err
    fld qword [ev+GE_RESULT]
    fstp qword [val]
    popad
    clc
    ret
.err:
    popad
    stc
    ret

; numv -> nbuf as sci prints it (10 significant digits)
full_text:
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
    popad
    ret

; numv, ecx = most characters -> nbuf: rounded to 6 decimals, then fewer
; while it is too long; noise below 1e-10 is 0. "####" if it never fits.
num_text:
    pushad
    mov [nwidth], ecx
    fld qword [numv]
    fabs
    fld qword [f_noise]
    fcomip st0, st1
    fstp st0
    jbe .go
    fldz
    fstp qword [numv]
.go:
    mov ebp, 6
.try:
    fld qword [numv]
    fld qword [pow10+ebp*8]
    fmul st1, st0
    fxch
    frndint
    fdivrp st1, st0
    fstp qword [ev+GE_X]
    mov dword [ev+GE_EXPR], s_x
    mov dword [ev+GE_FLAGS], GEF_X
    mov dword [ev+GE_TEXT], nbuf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    mov esi, nbuf
    call strlen
    cmp eax, [nwidth]
    jbe .r
    dec ebp
    jns .try
    mov dword [nbuf], '####'
    mov byte [nbuf+4], 0
.r:
    popad
    ret

; ---------- copying and filling ----------
; esi = entry, edi = buffer (CW), ecx = columns, edx = rows to move its
; references by (not the $ parts) -> the moved entry; a reference moved
; off the sheet becomes "#REF"
move_refs:
    pushad
    mov [mdc], ecx
    mov [mdr], edx
    lea ebp, [edi+EMAX]
    cmp byte [esi], '='
    jne .plain
    mov byte [prev], ' '
.c:
    mov al, [esi]
    test al, al
    jz .done
    mov dl, [prev]
    call is_alnum
    je .copy
    call parse_ref
    jc .notref
    mov eax, [rcol]
    test byte [rabs], 1
    jnz .ca
    add eax, [mdc]
.ca:
    mov ebx, [rrow]
    test byte [rabs], 2
    jnz .ra
    add ebx, [mdr]
.ra:
    cmp eax, NCOLS
    jae .refx
    cmp ebx, NROWS
    jae .refx
    lea ecx, [edi+6]
    cmp ecx, ebp
    jae .done
    test byte [rabs], 1
    jz .n1
    mov byte [edi], '$'
    inc edi
.n1:
    add al, 'A'
    stosb
    test byte [rabs], 2
    jz .n2
    mov byte [edi], '$'
    inc edi
.n2:
    lea eax, [ebx+1]
    call gui_utoa
    mov byte [prev], '1'
    jmp .c
.refx:
    lea ecx, [edi+4]
    cmp ecx, ebp
    jae .done
    mov dword [edi], '#REF'
    add edi, 4
    mov byte [prev], 'F'
    jmp .c
.notref:
    mov al, [esi]
.copy:
    mov [prev], al
    inc esi
    cmp edi, ebp
    jae .done
    stosb
    jmp .c
.plain:
    mov ecx, EMAX
.p:
    lodsb
    test al, al
    jz .done
    stosb
    loop .p
.done:
    mov byte [edi], 0
    popad
    ret

; Ctrl+C: the selection (or the cell) into the clipboard
copy_sel:
    pushad
    call sel_box
    mov [cc0], eax
    mov [br0], ebx
    sub ecx, eax
    inc ecx
    sub edx, ebx
    inc edx
    mov eax, ecx
    imul eax, edx
    cmp eax, CLIP_MAX
    ja .big
    mov [clipw], ecx
    mov [cliph], edx
    xor ebx, ebx                ; clipboard cell
    xor edx, edx                ; row in it
.r:
    xor ecx, ecx
.c:
    mov eax, [br0]
    add eax, edx
    imul eax, NCOLS
    add eax, [cc0]
    add eax, ecx
    call cell_ptr
    imul edi, ebx, CW
    add edi, [clip]
    push ecx
    mov ecx, CW / 4
    rep movsd
    pop ecx
    inc ebx
    inc ecx
    cmp ecx, [clipw]
    jb .c
    inc edx
    cmp edx, [cliph]
    jb .r
    mov dword [msg], m_copied
    mov dword [arow], -1
    popad
    ret
.big:
    mov dword [msg], m_toobig
    popad
    ret

; Ctrl+V: the clipboard with its top left at the cursor
paste:
    pushad
    cmp dword [clipw], 0
    je .r
    xor ebx, ebx
    xor edx, edx
.row:
    xor ecx, ecx
.col:
    mov eax, [crow]
    add eax, edx
    cmp eax, NROWS
    jae .skip
    mov edi, [ccol]
    add edi, ecx
    cmp edi, NCOLS
    jae .skip
    imul eax, NCOLS
    add eax, edi
    push eax
    push ecx
    push edx
    imul esi, ebx, CW
    add esi, [clip]
    mov ecx, [ccol]
    sub ecx, [cc0]
    mov edx, [crow]
    sub edx, [br0]
    mov edi, mbuf
    call move_refs
    pop edx
    pop ecx
    pop eax
    mov esi, mbuf
    call set_cell
.skip:
    inc ebx
    inc ecx
    cmp ecx, [clipw]
    jb .col
    inc edx
    cmp edx, [cliph]
    jb .row
.r:
    popad
    ret

; eax = 0 down, 1 right: each column (row) of the selection filled from
; its first cell
fill:
    pushad
    mov [filldir], eax
    call sel_box
    mov [cc0], eax
    mov [br0], ebx
    mov [cc1], ecx
    mov [br1], edx
    mov ebx, [br0]
.r:
    mov eax, [cc0]
.c:
    mov ecx, eax                ; the source: same column, first row
    mov edx, [br0]
    cmp dword [filldir], 0
    je .src
    mov ecx, [cc0]              ; or same row, first column
    mov edx, ebx
.src:
    cmp ecx, eax
    jne .go
    cmp edx, ebx
    je .next
.go:
    push eax
    push ebx
    imul esi, edx, NCOLS
    add esi, ecx
    imul esi, CW
    add esi, [cells]
    neg ecx
    add ecx, eax                ; columns to move by
    neg edx
    add edx, ebx                ; rows
    mov edi, mbuf
    call move_refs
    pop ebx
    pop eax
    push eax
    imul edx, ebx, NCOLS
    add eax, edx
    mov esi, mbuf
    call set_cell
    pop eax
.next:
    inc eax
    cmp eax, [cc1]
    jbe .c
    inc ebx
    cmp ebx, [br1]
    jbe .r
    popad
    ret

; ---------- the chart ----------
chart_key:
    pushad
    cmp dword [arow], -1
    je .next
    call sel_box
    mov [kc0], eax
    mov [kr0], ebx
    mov [kc1], ecx
    mov [kr1], edx
    mov dword [ctype], T_LINE
    mov dword [arow], -1
    jmp .r
.next:
    cmp dword [ctype], T_NONE
    jne .n
    mov dword [msg], m_select
    jmp .r
.n:
    inc dword [ctype]
    cmp dword [ctype], T_SCAT
    jbe .r
    mov dword [ctype], T_NONE
.r:
    popad
    ret

; eax = column, ebx = row -> numv and CF clear if the cell is a number
cell_num:
    push eax
    push edx
    imul edx, ebx, NCOLS
    add eax, edx
    mov edx, [cst]
    cmp byte [edx+eax], ST_NUM
    jne .no
    mov edx, [vals]
    fld qword [edx+eax*8]
    fstp qword [numv]
    pop edx
    pop eax
    clc
    ret
.no:
    pop edx
    pop eax
    stc
    ret

; The chart's parts: the first data row (after a row of names), the
; series columns, the x column for scatter -> drow0, sc0, xcol (-1: none)
chart_parts:
    pushad
    mov eax, [kr0]
    mov [drow0], eax
    mov eax, [kc0]              ; a row of names: a text cell in it
.h:
    imul edx, [kr0], NCOLS
    add edx, eax
    mov edi, [cst]
    cmp byte [edi+edx], ST_TEXT
    jne .h1
    mov ecx, [kr0]
    cmp ecx, [kr1]
    jae .h1
    inc ecx
    mov [drow0], ecx
    jmp .hd
.h1:
    inc eax
    cmp eax, [kc1]
    jbe .h
.hd:
    mov eax, [kc0]
    mov [sc0], eax
    mov dword [xcol], -1
    cmp dword [ctype], T_SCAT
    jne .r
    cmp eax, [kc1]
    jae .r                      ; one column: against the row
    mov [xcol], eax
    inc eax
    mov [sc0], eax
.r:
    popad
    ret

; x (xcol, or the point's number) and y ranges -> xmin..ymax; CF if
; there is nothing to draw
chart_ranges:
    pushad
    mov byte [have], 0
    mov ebx, [drow0]
.r:
    mov eax, [sc0]
.c:
    call cell_num
    jc .n
    call point_x
    jc .n
    fld qword [numv]
    cmp byte [have], 0
    jne .w
    fst qword [ymin]
    fst qword [ymax]
    fld qword [px_]
    fst qword [xmin]
    fstp qword [xmax]
    mov byte [have], 1
.w:
    fld qword [ymin]
    fcomip st0, st1
    jbe .w1
    fst qword [ymin]
.w1:
    fld qword [ymax]
    fcomip st0, st1
    jae .w2
    fst qword [ymax]
.w2:
    fstp st0
    fld qword [px_]
    fld qword [xmin]
    fcomip st0, st1
    jbe .w3
    fst qword [xmin]
.w3:
    fld qword [xmax]
    fcomip st0, st1
    jae .w4
    fst qword [xmax]
.w4:
    fstp st0
.n:
    inc eax
    cmp eax, [kc1]
    jbe .c
    inc ebx
    cmp ebx, [kr1]
    jbe .r
    cmp byte [have], 0
    je .none
    cmp dword [ctype], T_BAR    ; bars stand on 0
    jne .eq
    fldz
    fld qword [ymin]
    fcomip st0, st1
    jbe .b1
    fst qword [ymin]
.b1:
    fld qword [ymax]
    fcomip st0, st1
    jae .b2
    fst qword [ymax]
.b2:
    fstp st0
.eq:                            ; no width: one either side
    lea esi, [xmin]
    call widen
    lea esi, [ymin]
    call widen
    popad
    clc
    ret
.none:
    popad
    stc
    ret

; esi = min, max: if equal, one less and one more
widen:
    fld qword [esi]
    fld qword [esi+8]
    fcomip st0, st1
    fstp st0
    jne .r
    fld1
    fld qword [esi]
    fsub st0, st1
    fstp qword [esi]
    fadd qword [esi+8]
    fstp qword [esi+8]
.r:
    ret

; ebx = row -> px_ = its point's x: the x column's number (CF if it is not
; a number), or the point's number from 1
point_x:
    push eax
    cmp dword [xcol], -1
    je .idx
    push dword [numv]
    push dword [numv+4]
    mov eax, [xcol]
    call cell_num
    fld qword [numv]
    pop dword [numv+4]
    pop dword [numv]
    jc .no
    fstp qword [px_]
    pop eax
    clc
    ret
.no:
    fstp st0
    pop eax
    stc
    ret
.idx:
    mov eax, ebx
    sub eax, [drow0]
    inc eax
    mov [tmp], eax
    fild dword [tmp]
    fstp qword [px_]
    pop eax
    clc
    ret

; st0 = value (popped), esi = min, max, eax = first pixel, ecx = pixels
; less one -> eax = the pixel
to_px:
    push edx
    fsub qword [esi]
    fld qword [esi+8]
    fsub qword [esi]
    fdivp st1, st0
    mov [tmp], ecx
    fimul dword [tmp]
    fistp dword [tmp]
    add eax, [tmp]
    pop edx
    ret

; numv's y -> ebx = pixel row (clamped to the plot)
y_px:
    push eax
    push ecx
    push esi
    fld qword [numv]
    xor eax, eax
    mov ecx, PL_H - 1
    mov esi, ymin
    call to_px
    mov ebx, PL_Y + PL_H - 1
    sub ebx, eax
    pop esi
    pop ecx
    pop eax
    ret

; px_ -> eax = pixel column
x_px:
    push ecx
    push esi
    fld qword [px_]
    mov eax, PL_X + 3
    mov ecx, PL_W - 7
    mov esi, xmin
    call to_px
    pop esi
    pop ecx
    ret

draw_chart:
    pushad
    mov eax, CH_X
    mov ebx, CH_Y
    mov ecx, CH_W
    mov edx, CH_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_ink], C_DGREY
    call gui_box
    call chart_parts
    mov edi, line               ; "Line B1:C6", then the series' names
    mov eax, [ctype]
    mov esi, [type_name+eax*4]
    call scopy
    mov eax, [kc0]
    mov ebx, [kr0]
    call ref_text
    mov al, ':'
    stosb
    mov eax, [kc1]
    mov ebx, [kr1]
    call ref_text
    mov esi, line
    mov eax, CH_X + 3
    mov ebx, CH_Y + 2
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    call gui_text
    call gui_textw
    lea ebp, [eax+CH_X+3+2*CELL_W]
    mov ebx, [sc0]              ; the series' names, in their colours
.nm:
    mov eax, [drow0]
    cmp eax, [kr0]
    je .nmd                     ; no row of names
    imul eax, [kr0], NCOLS
    add eax, ebx
    mov edx, [cst]
    cmp byte [edx+eax], ST_TEXT
    jne .nmn
    call cell_ptr
    mov eax, ebx
    sub eax, [sc0]
    call series_ink
    mov eax, ebp
    push ebx
    mov ebx, CH_Y + 2
    mov ecx, CH_X + CH_W - 3
    sub ecx, eax
    jbe .nmf
    call gui_textn
    call gui_textw
    lea ebp, [ebp+eax+2*CELL_W]
.nmf:
    pop ebx
.nmn:
    inc ebx
    cmp ebx, [kc1]
    jbe .nm
.nmd:
    call chart_ranges
    jc .nothing
    mov eax, PL_X               ; the plot's frame
    mov ebx, PL_Y
    mov ecx, PL_W
    mov edx, PL_H
    mov byte [gui_ink], C_LGREY
    call gui_box
    fld qword [ymax]            ; the y range at the left
    fstp qword [numv]
    mov ecx, 6
    call num_text
    mov esi, nbuf
    mov eax, CH_X + 3
    mov ebx, PL_Y
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    call gui_text
    fld qword [ymin]
    fstp qword [numv]
    call num_text
    mov ebx, PL_Y + PL_H - CELL_H
    call gui_text
    mov byte [zero_in], 0       ; the zero line, if it is inside
    fldz
    fld qword [ymin]
    fcomip st0, st1
    ja .nz
    fld qword [ymax]
    fcomip st0, st1
    jb .nz
    fstp qword [numv]
    call y_px
    mov [zero_y], ebx
    mov byte [zero_in], 1
    jmp .series
.nz:
    fstp st0
    mov dword [zero_y], PL_Y + PL_H - 1
    fld qword [ymin]            ; bars from the edge nearer 0
    fldz
    fcomip st0, st1
    fstp st0
    ja .series
    mov dword [zero_y], PL_Y
.series:
    mov ebp, [sc0]              ; each series
    xor edi, edi                ; its number
.s:
    mov eax, ebp
    sub eax, [sc0]
    call series_ink
    mov dword [last_x], -1
    mov eax, [drow0]
    mov [prow], eax
.p:
    mov eax, ebp
    mov ebx, [prow]
    call cell_num
    jc .gap
    call point_x
    jc .gap
    call y_px
    call x_px
    cmp dword [ctype], T_BAR
    je .bar
    cmp dword [ctype], T_LINE
    jne .dot
    cmp dword [last_x], -1
    je .dot
    push eax
    push ebx
    mov ecx, eax
    mov edx, ebx
    mov eax, [last_x]
    mov ebx, [last_y]
    call gui_line
    pop ebx
    pop eax
.dot:
    mov [last_x], eax
    mov [last_y], ebx
    dec eax
    dec ebx
    mov ecx, 3
    mov edx, 3
    call gui_fill
    jmp .pn
.bar:                           ; a slot each point, a bar each series
    mov eax, [kr1]
    sub eax, [drow0]
    inc eax
    mov ecx, eax
    mov eax, PL_W - 8
    xor edx, edx
    div ecx
    mov esi, eax                ; the slot's width
    mov ecx, [kc1]
    sub ecx, [sc0]
    inc ecx
    sub eax, 4                  ; room between slots
    xor edx, edx
    div ecx
    test eax, eax
    jnz .bw
    inc eax
.bw:
    mov ecx, eax                ; bar width
    mov eax, [prow]
    sub eax, [drow0]
    imul eax, esi
    add eax, PL_X + 6
    mov edx, edi
    imul edx, ecx
    add eax, edx                ; this series' bar
    cmp ecx, 2
    jbe .bw2
    dec ecx                     ; a gap between bars
.bw2:
    mov edx, [zero_y]
    cmp ebx, edx
    jbe .bup
    xchg ebx, edx
.bup:
    sub edx, ebx
    inc edx
    call gui_fill
    jmp .pn
.gap:
    mov dword [last_x], -1
.pn:
    inc dword [prow]
    mov eax, [prow]
    cmp eax, [kr1]
    jbe .p
    inc edi
    inc ebp
    cmp ebp, [kc1]
    jbe .s
    cmp byte [zero_in], 0       ; the zero line on top
    je .r
    mov eax, PL_X
    mov ebx, [zero_y]
    mov ecx, PL_X + PL_W - 1
    mov edx, ebx
    mov byte [gui_ink], C_DGREY
    call gui_line
.r:
    popad
    ret
.nothing:
    mov esi, m_nonum
    mov eax, PL_X
    mov ebx, PL_Y + 10
    mov byte [gui_ink], C_RED
    mov byte [gui_bg], C_WHITE
    call gui_text
    popad
    ret

; eax = series number -> gui_ink its colour
series_ink:
    push eax
    push edx
    xor edx, edx
    push ecx
    mov ecx, 6
    div ecx
    pop ecx
    mov al, [series_col+edx]
    mov [gui_ink], al
    pop edx
    pop eax
    ret

; eax = column, ebx = row, edi -> "B7" at edi (edi after it)
ref_text:
    push eax
    add al, 'A'
    stosb
    lea eax, [ebx+1]
    call gui_utoa
    pop eax
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
    call draw_entry
    call draw_grid
    cmp dword [ctype], T_NONE
    je .nc
    call draw_chart
.nc:
    call draw_status
    call gui_flip
    popad
    ret

; The entry bar: "B7: entry" (yellow while typing)
draw_entry:
    pushad
    mov eax, 3
    mov ebx, FY - 1
    mov ecx, SCR_W - 6
    mov edx, CELL_H + 2
    mov byte [gui_ink], C_WHITE
    cmp byte [editing], 0
    je .f
    mov byte [gui_ink], C_YELLOW
.f:
    call gui_fill
    mov al, [gui_ink]
    mov [gui_bg], al
    mov edi, line
    mov eax, [ccol]
    mov ebx, [crow]
    call ref_text
    mov ax, ': '
    stosw
    mov esi, ebuf
    cmp byte [editing], 0
    jne .t
    call cur_idx
    call cell_ptr
.t:
    call scopy
    cmp byte [editing], 0
    je .e
    mov ax, '_'
    stosw
.e:
    mov byte [edi], 0
    mov esi, line
    mov eax, 5
    mov ebx, FY
    mov ecx, SCR_W - 10
    mov byte [gui_ink], C_BLACK
    call gui_textn
    popad
    ret

draw_grid:
    pushad
    call vrows
    mov [nvis], eax
    mov eax, 3                  ; white under it
    mov ebx, GY
    mov ecx, SCR_W - 6
    mov edx, [nvis]
    inc edx
    imul edx, ROW_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov ecx, RH_W               ; grey headers
    mov edx, ROW_H
    mov byte [gui_ink], C_LGREY
    mov ecx, SCR_W - 6
    call gui_fill
    mov ecx, RH_W
    mov edx, [nvis]
    inc edx
    imul edx, ROW_H
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    xor ebp, ebp                ; column letters
.cl:
    mov eax, [left]
    add eax, ebp
    cmp eax, NCOLS
    jae .cld
    add al, 'A'
    mov [line], al
    mov byte [line+1], 0
    imul eax, ebp, COL_W
    add eax, GX + COL_W / 2 - 3
    mov ebx, GY + 1
    mov esi, line
    call gui_text
    inc ebp
    cmp ebp, VCOLS
    jb .cl
.cld:
    xor ebp, ebp                ; the rows
.row:
    mov eax, [top]
    add eax, ebp
    cmp eax, NROWS
    jae .rows
    mov [drow], eax
    lea ebx, [ebp+1]
    imul ebx, ROW_H
    add ebx, GY + 1
    mov [dyy], ebx
    mov edi, line
    inc eax
    call gui_utoa
    mov esi, line
    mov eax, 5
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    xor edx, edx
.cell:
    mov eax, [left]
    add eax, edx
    cmp eax, NCOLS
    jae .nextrow
    mov [dcol], eax
    push edx
    imul ecx, edx, COL_W
    add ecx, GX
    mov [dxx], ecx
    call draw_cell
    pop edx
    inc edx
    cmp edx, VCOLS
    jb .cell
.nextrow:
    inc ebp
    cmp ebp, [nvis]
    jb .row
.rows:
    mov byte [gui_ink], C_LGREY ; the lines
    xor ebp, ebp
.vl:
    imul eax, ebp, COL_W
    add eax, GX - 1
    mov ebx, GY
    mov ecx, eax
    mov edx, [nvis]
    inc edx
    imul edx, ROW_H
    add edx, GY - 1
    call gui_line
    inc ebp
    cmp ebp, VCOLS
    jbe .vl
    xor ebp, ebp
.hl:
    lea ebx, [ebp+1]
    imul ebx, ROW_H
    add ebx, GY - 1
    mov eax, 3
    mov ecx, GX + VCOLS * COL_W - 1
    mov edx, ebx
    call gui_line
    inc ebp
    cmp ebp, [nvis]
    jbe .hl
    popad
    ret

; dcol, drow at dxx, dyy: the cell's background and what it shows
draw_cell:
    pushad
    mov byte [gui_bg], C_WHITE
    mov eax, [dcol]             ; selected?
    mov ebx, [drow]
    cmp dword [arow], -1
    je .cur
    push eax
    push ebx
    call sel_box
    mov esi, eax
    mov edi, ebx
    pop ebx
    pop eax
    cmp eax, esi
    jb .cur
    cmp eax, ecx
    ja .cur
    cmp ebx, edi
    jb .cur
    cmp ebx, edx
    ja .cur
    mov byte [gui_bg], C_LCYAN
.cur:
    cmp eax, [ccol]
    jne .bg
    cmp ebx, [crow]
    jne .bg
    mov byte [gui_bg], C_YELLOW
.bg:
    cmp byte [gui_bg], C_WHITE
    je .val
    mov al, [gui_bg]
    mov [gui_ink], al
    mov eax, [dxx]
    mov ebx, [dyy]
    dec ebx
    mov ecx, COL_W - 1
    mov edx, ROW_H - 1
    call gui_fill
.val:
    mov eax, [drow]
    imul eax, NCOLS
    add eax, [dcol]
    mov edx, [cst]
    movzx ecx, byte [edx+eax]
    mov byte [gui_ink], C_BLACK
    cmp ecx, ST_NUM
    je .num
    cmp ecx, ST_TEXT
    je .text
    mov esi, s_err
    cmp ecx, ST_ERR
    je .bad
    mov esi, s_cyc
    cmp ecx, ST_CYC
    jne .r
.bad:
    mov byte [gui_ink], C_RED
    jmp .left
.text:
    call cell_ptr
.left:
    mov eax, [dxx]
    inc eax
    mov ebx, [dyy]
    mov ecx, COL_W - 2
    call gui_textn
    jmp .r
.num:                           ; numbers to the right
    mov edx, [vals]
    fld qword [edx+eax*8]
    fstp qword [numv]
    mov ecx, 7
    call num_text
    mov esi, nbuf
    call gui_textw
    neg eax
    add eax, [dxx]
    add eax, COL_W - 2
    mov ebx, [dyy]
    call gui_text
.r:
    popad
    ret

draw_status:
    pushad
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov esi, [msg]
    test esi, esi
    jz .val
    cmp esi, s_errmsg
    jne .red
    mov edi, line               ; "Error: " and sci's message
    call scopy
    mov esi, lasterr
    call scopy
    mov esi, line
.red:
    mov byte [gui_ink], C_RED
    jmp .out
.val:
    mov edi, line               ; "= value" of a number, then the keys
    call cur_idx
    mov edx, [cst]
    mov esi, m_cycle
    cmp byte [edx+eax], ST_CYC
    je .say
    mov esi, m_bad
    cmp byte [edx+eax], ST_ERR
    je .say
    cmp byte [edx+eax], ST_NUM
    jne .keys
    mov edx, [vals]
    fld qword [edx+eax*8]
    fstp qword [numv]
    call full_text
    mov ax, '= '
    stosw
    mov esi, nbuf
    call scopy
    mov ax, '  '
    stosw
.say:
    call scopy
    mov esi, line
    jmp .out
.keys:
    mov esi, s_keys
    call scopy
    mov esi, line
.out:
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    call gui_textn
    popad
    ret

; ---------- files ----------
; fname -> the cells (CSV)
load:
    pushad
    call clear_all
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
    xor ebx, ebx                ; row
.row:
    cmp byte [esi], 0
    je .done
    xor edx, edx                ; column
.field:
    mov edi, mbuf               ; one field into mbuf
    lea ebp, [mbuf+EMAX]
    cmp byte [esi], '"'
    jne .bare
    inc esi
.q:
    lodsb
    test al, al
    jz .qe
    cmp al, '"'
    jne .qc
    cmp byte [esi], '"'
    jne .fend
    inc esi
.qc:
    cmp edi, ebp
    jae .q
    stosb
    jmp .q
.qe:
    dec esi
    jmp .fend
.bare:
    lodsb
    test al, al
    jz .be
    cmp al, ','
    je .be
    cmp al, 10
    je .be
    cmp al, 13
    je .bare
    cmp edi, ebp
    jae .bare
    stosb
    jmp .bare
.be:
    dec esi
.fend:
    mov byte [edi], 0
    cmp ebx, NROWS
    jae .skip
    cmp edx, NCOLS
    jae .skip
    imul eax, ebx, NCOLS
    add eax, edx
    push esi
    mov esi, mbuf
    call set_cell
    pop esi
.skip:
    inc edx
.sep:
    lodsb
    cmp al, ','
    je .field
    cmp al, 13
    je .sep
    test al, al
    jz .done
    cmp al, 10
    jne .sep                    ; anything after a quoted field
    inc ebx
    jmp .row
.done:
    mov byte [dirty], 0
    mov dword [msg], m_opened
    popad
    ret
.new:
    mov dword [msg], m_newfile
    popad
    ret

; the cells -> fname (CSV, up to the last row and column used)
save:
    pushad
    xor ecx, ecx                ; last column and row used, plus one
    xor edx, edx
    xor eax, eax
.u:
    push eax
    call cell_ptr
    cmp byte [esi], 0
    je .un
    push edx
    xor edx, edx
    mov ebx, NCOLS
    div ebx                     ; eax = row, edx = column
    inc edx
    cmp edx, ecx
    jbe .u1
    mov ecx, edx
.u1:
    pop edx
    lea edx, [eax+1]
.un:
    pop eax
    inc eax
    cmp eax, NCELLS
    jb .u
    mov [cc1], ecx
    mov [br1], edx
    mov edi, [fbuf]
    xor ebx, ebx
.row:
    cmp ebx, [br1]
    jae .write
    xor edx, edx
.col:
    test edx, edx
    jz .c1
    mov al, ','
    stosb
.c1:
    imul eax, ebx, NCOLS
    add eax, edx
    call cell_ptr
    push esi                    ; quoted if it holds a comma or a quote
.chk:
    lodsb
    test al, al
    jz .plain
    cmp al, ','
    je .quote
    cmp al, '"'
    jne .chk
.quote:
    pop esi
    mov al, '"'
    stosb
.qc:
    lodsb
    test al, al
    jz .qd
    stosb
    cmp al, '"'
    jne .qc
    stosb
    jmp .qc
.qd:
    mov al, '"'
    stosb
    jmp .cn
.plain:
    pop esi
    call scopy
.cn:
    inc edx
    cmp edx, [cc1]
    jb .col
    mov al, 10
    stosb
    inc ebx
    jmp .row
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

; Asks "Save changes? y/n" if there are any -> CF to stay
ask_unsaved:
    pushad
    cmp byte [dirty], 0
    je .go
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov esi, q_unsaved
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .stay
    or al, 0x20
    cmp al, 'n'
    je .go
    cmp al, 'y'
    jne .k
    call save
    jc .stay
.go:
    popad
    clc
    ret
.stay:
    popad
    stc
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

; ---------- self-check ----------
; esi = keys: characters, or 0xE0 and a scancode, or 0xE1 and a Ctrl
; letter; 0 ends
feed:
    pushad
.k:
    movzx eax, byte [esi]
    test eax, eax
    jz .r
    inc esi
    cmp al, 0xE0
    je .scan
    cmp al, 0xE1
    je .ctl
    cmp al, 10
    jne .send
    mov eax, K_ENTER << 8 | 13
    jmp .send
.scan:
    movzx eax, byte [esi]
    inc esi
    shl eax, 8
    jmp .send
.ctl:
    movzx eax, byte [esi]
    inc esi
    or eax, 1 << 16
.send:
    push esi
    call key
    pop esi
    jmp .k
.r:
    popad
    ret

; esi = "B7" -> eax = cell
ref_idx:
    push esi
    call parse_ref
    pop esi
    imul eax, [rrow], NCOLS
    add eax, [rcol]
    ret

; esi = "B7", then its expected value as a double at edi -> CF unless it
; is a number within 1e-9 of it
want:
    pushad
    call ref_idx
    mov edx, [cst]
    cmp byte [edx+eax], ST_NUM
    jne .no
    mov edx, [vals]
    fld qword [edx+eax*8]
    fsub qword [edi]
    fabs
    fld qword [f_tol]
    fcomip st0, st1
    fstp st0
    jb .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = "B7", dl = state -> CF unless the cell is in it
want_st:
    pushad
    call ref_idx
    mov ecx, [cst]
    cmp [ecx+eax], dl
    jne .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = "B7", edi = text -> CF unless the cell's entry is that
want_text:
    pushad
    call ref_idx
    push edi
    call cell_ptr
    pop edi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .no
    inc esi
    inc edi
    test al, al
    jnz .c
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ecx = colour -> eax = how many plot pixels have it
count_ink:
    pushad
    xor edi, edi
    mov ebx, PL_Y
.y:
    mov eax, PL_X
.x:
    push ecx
    call gui_peek
    cmp cl, [esp]
    pop ecx
    jne .n
    inc edi
.n:
    inc eax
    cmp eax, PL_X + PL_W
    jb .x
    inc ebx
    cmp ebx, PL_Y + PL_H
    jb .y
    mov [esp+28], edi
    popad
    ret

%macro WANT 2                   ; cell, value
    mov esi, %%c
    mov edi, %%v
    call want
    jc .fail
    jmp %%e
%%c db %1, 0
align 8
%%v dq %2
%%e:
%endmacro
%macro WANT_ST 2                ; cell, state
    mov esi, %%c
    mov dl, %2
    call want_st
    jc .fail
    jmp %%e
%%c db %1, 0
%%e:
%endmacro
%macro WANT_TEXT 2              ; cell, entry
    mov esi, %%c
    mov edi, %%t
    call want_text
    jc .fail
    jmp %%e
%%c db %1, 0
%%t db %2, 0
%%e:
%endmacro
%macro TYPE 1                   ; keys
    mov esi, %%k
    call feed
    jmp %%e
%%k db %1, 0
%%e:
%endmacro
%macro GOTO 1                   ; cell
    mov esi, %%c
    call ref_idx
    mov ecx, [rcol]
    mov [ccol], ecx
    mov ecx, [rrow]
    mov [crow], ecx
    mov dword [arow], -1
    jmp %%e
%%c db %1, 0
%%e:
%endmacro

selftest:
    mov byte [bad], 'n'         ; numbers and a formula, typed
    GOTO 'A1'
    TYPE {'2', 10, '3', 10, '=A1*A2+1', 10}
    WANT 'A1', 2.0
    WANT 'A3', 7.0
    WANT_TEXT 'A3', '=A1*A2+1'
    cmp dword [crow], 3
    jne .fail
    mov byte [bad], 'u'         ; a change goes through
    GOTO 'A1'
    TYPE {'4', 10}
    WANT 'A3', 13.0
    mov byte [bad], 's'         ; range functions, sci functions
    GOTO 'B1'
    TYPE {'=sum(A1:A3)', 10, '=AVG(a1:a3)', 10, '=min(A1:A3)+max(A3:A1)', 10}
    TYPE {'=count(A1:B3)', 10, '=sqrt(B1)*2^A1', 10, '=Z99+5', 10}
    WANT 'B1', 20.0
    WANT 'B2', 6.6666666666666667
    WANT 'B3', 16.0
    WANT 'B4', 6.0
    WANT 'B5', 71.55417527999327
    WANT 'B6', 5.0
    mov byte [bad], 't'         ; text, and text in a formula
    GOTO 'C1'
    TYPE {'Name', 10, '=C1+1', 10, '=sum(C1:C2)', 10, '1/0', 10, '=1/0', 10}
    WANT_ST 'C1', ST_TEXT
    WANT_ST 'C2', ST_ERR
    WANT_ST 'C3', ST_ERR
    WANT_ST 'C4', ST_TEXT
    WANT_ST 'C5', ST_ERR
    mov byte [bad], 'c'         ; a cycle
    GOTO 'D1'
    TYPE {'=D2', 10, '=D1+1', 10, '=D2*2', 10}
    WANT_ST 'D1', ST_CYC
    WANT_ST 'D2', ST_CYC
    WANT_ST 'D3', ST_CYC
    mov byte [bad], 'p'         ; copy and paste: references move
    GOTO 'A3'
    TYPE {0xE1, 'c'}
    GOTO 'E3'
    TYPE {0xE1, 'v'}
    WANT_TEXT 'E3', '=E1*E2+1'
    GOTO 'E1'
    TYPE {'=$A$1+A2', 10}
    GOTO 'E1'
    TYPE {0xE1, 'c'}
    GOTO 'F2'
    TYPE {0xE1, 'v'}
    WANT_TEXT 'F2', '=$A$1+B3'
    WANT 'F2', 20.0
    mov byte [bad], 'f'         ; fill down: a running count to row 99
    GOTO 'G1'
    TYPE {'1', 10, '=G1+1', 10}
    GOTO 'G2'
    TYPE {0xE0, K_F3, 0xE1, 'd'}
    mov dword [crow], 98        ; select G2:G99
    mov dword [ccol], 6
    TYPE {0xE1, 'd'}
    WANT_TEXT 'G99', '=G98+1'
    WANT 'G99', 99.0
    GOTO 'H1'
    TYPE {'=G99', 10}           ; upwards through 98 formulas
    WANT 'H1', 99.0
    mov byte [bad], 'x'         ; a moved reference off the sheet
    GOTO 'A1'
    TYPE {'=A2', 10}
    GOTO 'A1'
    TYPE {0xE1, 'c'}
    GOTO 'A99'
    TYPE {0xE1, 'v'}
    WANT_TEXT 'A99', '=#REF'
    WANT_ST 'A99', ST_ERR
    mov byte [bad], 'g'         ; a chart of names and two series
    mov byte [dirty], 0         ; (Ctrl+N would ask)
    TYPE {0xE1, 'n'}
    GOTO 'A1'
    TYPE {'one', 0xE0, K_TAB, 'two', 10}
    GOTO 'A2'
    TYPE {'1', 10, '2', 10, '3', 10, '4', 10}
    GOTO 'B2'
    TYPE {'4', 10, '1', 10, '3', 10, '2', 10}
    GOTO 'A1'
    TYPE {0xE0, K_F3}
    GOTO 'B5'
    mov dword [acol], 0
    mov dword [arow], 0
    TYPE {0xE1, 'g'}
    cmp dword [ctype], T_LINE
    jne .fail
    call recalc
    call draw
    mov ecx, C_BLUE
    call count_ink
    cmp eax, 20
    jb .fail
    mov ecx, C_RED
    call count_ink
    cmp eax, 20
    jb .fail
    mov byte [bad], 'b'         ; bars: the first series' 4 is the tallest
    TYPE {0xE1, 'g'}
    cmp dword [ctype], T_BAR
    jne .fail
    call draw
    mov ecx, C_BLUE
    call count_ink
    mov [tmp2], eax
    mov ecx, C_RED
    call count_ink
    cmp eax, [tmp2]             ; 4+1+3+2 = 10 for both: about equal
    jae .b1
    xchg eax, [tmp2]
.b1:
    sub eax, [tmp2]
    cmp eax, 200                ; (each bar's top may round apart)
    ja .fail
    cmp dword [tmp2], 1000
    jb .fail
    mov byte [bad], 'l'         ; the chart follows the cells
    GOTO 'A2'
    TYPE {'-10', 10}
    call draw
    mov ecx, C_DGREY            ; a zero line now
    call count_ink
    cmp eax, PL_W - 2
    jb .fail
    TYPE {0xE1, 'g', 0xE1, 'g'}
    cmp dword [ctype], T_NONE
    jne .fail
    mov byte [bad], 'v'         ; CSV: save, empty, open
    GOTO 'C1'
    TYPE {'a,b', 10}
    mov esi, s_testfile
    mov edi, fname
    call copy_name
    call save
    jc .fail
    call clear_all
    call load
    call recalc
    WANT_TEXT 'A1', 'one'
    WANT_TEXT 'C1', 'a,b'
    WANT 'B5', 2.0
    WANT 'A2', -10.0
    cmp byte [dirty], 0
    jne .fail
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
title db 'Sheet', 0
s_default db 'sheet.csv', 0
s_testfile db 'stest.csv', 0
s_x db 'x', 0
s_err db '#ERR', 0
s_cyc db '#CYC', 0
s_errmsg db 'Error: ', 0
s_keys db 'F3 sel ^C ^V ^D ^R ^G chart ^S', 0
fn_names db 'sum', 0, 'avg', 0, 'min', 0, 'max', 0, 'count', 0, 0
type_name dd 0, s_line, s_bar, s_scat
s_line db 'Line ', 0
s_bar db 'Bars ', 0
s_scat db 'Scatter ', 0
series_col db C_BLUE, C_RED, C_GREEN, C_MAGENTA, C_BROWN, C_CYAN
q_unsaved db 'Save changes? y/n', 0
m_copied db 'Copied', 0
m_toobig db 'Too many cells to copy', 0
m_select db 'Select cells (F3 or a drag), then Ctrl+G', 0
m_cycle db '#CYC: it depends on itself', 0
m_bad db '#ERR: it cannot be worked out', 0
m_nonum db 'No numbers to draw', 0
m_opened db 'Opened', 0
m_newfile db 'New file', 0
m_saved db 'Saved', 0
m_nosave db 'Could not save', 0
m_nogfx db 'sheet: no graphics', 10, 0
pass db 'sheet: PASS', 10, 0
fail db 'sheet: FAIL ', 0
bad db '?', 10, 0
align 8
f_noise dq 1.0e-10
f_tol dq 1.0e-9
pow10 dq 1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0

SQX_BSS
GUI_BSS
alignb 8
val resq 1
numv resq 1
amin resq 1
amax resq 1
px_ resq 1
xmin resq 1
xmax resq 1
ymin resq 1
ymax resq 1
arg resd 1
cells resd 1
vals resd 1
cst resd 1
clip resd 1
fbuf resd 1
ccol resd 1
crow resd 1
acol resd 1
arow resd 1
top resd 1
left resd 1
msg resd 1
elen resd 1
depth resd 1
cell_now resd 1
err_idx resd 1
rcol resd 1
rrow resd 1
rabs resd 1
r0c resd 1
r0r resd 1
r1c resd 1
r1r resd 1
fn_kind resd 1
tmp resd 1
tmp2 resd 1
nwidth resd 1
mdc resd 1
mdr resd 1
cc0 resd 1
br0 resd 1
cc1 resd 1
br1 resd 1
clipw resd 1
cliph resd 1
filldir resd 1
ctype resd 1
kc0 resd 1
kr0 resd 1
kc1 resd 1
kr1 resd 1
drow0 resd 1
sc0 resd 1
xcol resd 1
last_x resd 1
last_y resd 1
zero_y resd 1
prow resd 1
nvis resd 1
drow resd 1
dcol resd 1
dxx resd 1
dyy resd 1
flen resd 1
ev resb GE_SIZE
prev resb 1
editing resb 1
dirty resb 1
have resb 1
zero_in resb 1
deep_hit resb 1
etext resb 40
lasterr resb 40
nbuf resb 40
fname resb NAME_MAX + 4
ebuf resb CW + 4
mbuf resb CW + 4
line resb 96
exbuf resb DEPTH_MAX * EXLEN
SQX_END
