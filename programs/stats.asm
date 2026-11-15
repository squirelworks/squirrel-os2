; Squirrel-OS/2 — Statistics: lists, statistics and regressions in a
; window (C.3, OS2-APPS). Original code.
; run stats [file.csv]   |   run stats test
;
; Two lists, L1 and L2 (up to 99 numbers each), in a table on the left;
; results and plots on the right. An entry is any sci expression (2.5,
; sqrt(2), 1/3), evaluated by the kernel's sci engine (SYS_GUI GUI_EVAL).
;
;   arrows, PgUp, PgDn  move in the table (Tab: the other list); a click
;                       on a cell goes there
;   a digit, - . ( or   start typing an entry: Enter keeps it and goes
;   Enter               down, Esc drops it
;   Delete              removes the entry (the ones below move up)
;   v                   one-variable statistics of the list
;   x                   two-variable statistics of L1 (x) and L2 (y)
;   r                   regression of L2 on L1: each press the next model
;                       (linear, quadratic, cubic, exponential,
;                       logarithmic, power, logistic) with its plot
;   h  b  p             histogram, box plot of the list; scatter plot
;   Ctrl+S              save as CSV (the file named on the command line,
;                       or stats.csv)
;   Ctrl+N              empty both lists          Esc  quit
;
; Quartiles are the medians of the lower and upper halves (the median
; itself left out when n is odd). Exponential, power and logarithmic
; fits are least squares on ln y and/or ln x; the logistic fit searches
; the ceiling c (golden section) with a linear fit of ln(c/y - 1) inside.
; r^2 is always 1 - SSres/SStot of y itself.
; "run stats test" checks every statistic and model on known data, the
; histogram and quartiles, and saving and loading a CSV file, and prints
; "stats: PASS". See documentation/apps/stats.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

N_MAX       equ 99
EMAX        equ 40                      ; an entry being typed
FBUF        equ 8192                    ; a CSV file
RES_MAX     equ 18

TX          equ 4                       ; the table
TY          equ 14
ROW_H       equ CELL_H + 1
VIS         equ 18                      ; rows shown
IDX_W       equ 3 * CELL_W
COL_W       equ 9 * CELL_W + 2
C1_X        equ TX + IDX_W + 3
C2_X        equ C1_X + COL_W + 2
TAB_R       equ C2_X + COL_W            ; right edge
PAN_X       equ TAB_R + 6               ; the panel
PAN_W       equ SCR_W - PAN_X - 4
PAN_Y       equ TY
PAN_B       equ TY + (VIS + 1) * ROW_H  ; bottom of table and panel
STAT_Y      equ SCR_H - CELL_H - 2      ; status row
PL_X        equ PAN_X + 2               ; plot area (below the text)
PL_W        equ PAN_W - 4

V_HELP      equ 0                       ; views of the panel
V_ONE       equ 1
V_TWO       equ 2
V_REG       equ 3
V_HIST      equ 4
V_BOX       equ 5
V_SCAT      equ 6

M_LIN       equ 0                       ; regression models
M_QUAD      equ 1
M_CUBIC     equ 2
M_EXP       equ 3
M_LOG       equ 4
M_POW       equ 5
M_LOGI      equ 6
MODELS      equ 7

SC_S        equ 0x1F                    ; scancodes for Ctrl+S, Ctrl+N
SC_N        equ 0x31

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    mov esi, s_default
    mov edi, fname
    call scopy
    call gui_open
    jc .nogfx
    mov esi, [arg]
    test esi, esi
    jz .draw
    cmp dword [esi], 'test'
    je selftest
    cmp byte [esi], 0
    je .draw
    mov edi, fname
    call scopy
    call load
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
    cmp byte [editing], 0
    jne .editkey
    movzx ebx, ah               ; scancode
    test eax, 1 << 16
    jnz .ctrl
    cmp bl, K_ESC
    je .quit
    cmp bl, K_ENTER
    je .startedit
    cmp bl, K_TAB
    je .tab
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_LEFT
    je .tab
    cmp bl, K_RIGHT
    je .tab
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_DEL
    je .del
    cmp al, '0'
    jb .notdigit
    cmp al, '9'
    jbe .typed
.notdigit:
    cmp al, '-'
    je .typed
    cmp al, '.'
    je .typed
    cmp al, '('
    je .typed
    or al, 0x20
    mov ecx, V_ONE
    cmp al, 'v'
    je .view
    mov ecx, V_TWO
    cmp al, 'x'
    je .view
    mov ecx, V_HIST
    cmp al, 'h'
    je .view
    mov ecx, V_BOX
    cmp al, 'b'
    je .view
    mov ecx, V_SCAT
    cmp al, 'p'
    je .view
    cmp al, 'r'
    jne .key
    cmp dword [view], V_REG     ; again: the next model
    jne .reg
    mov eax, [model]
    inc eax
    cmp eax, MODELS
    jb .m
    xor eax, eax
.m:
    mov [model], eax
.reg:
    mov ecx, V_REG
.view:
    mov [view], ecx
    call compute
    jmp .draw
.ctrl:
    cmp bl, SC_S
    je .save
    cmp bl, SC_N
    jne .key
    mov dword [len], 0
    mov dword [len+4], 0
    mov dword [crow], 0
    mov dword [top], 0
    mov dword [view], V_HELP
    jmp .draw
.save:
    call save
    jmp .draw
.tab:
    xor dword [ccol], 1
    call clamp_row
    jmp .draw
.up:
    cmp dword [crow], 0
    je .key
    dec dword [crow]
    call clamp_row
    jmp .draw
.down:
    inc dword [crow]
    call clamp_row
    jmp .draw
.pgup:
    sub dword [crow], VIS
    jns .pg
    mov dword [crow], 0
.pg:
    call clamp_row
    jmp .draw
.pgdn:
    add dword [crow], VIS
    jmp .pg
.del:
    call delete_entry
    call recompute
    jmp .draw
.startedit:                     ; Enter: the entry's value to start from
    mov byte [elen], 0
    mov byte [ebuf], 0
    mov byte [editing], 1
    call cur_ptr
    jc .draw
    fld qword [esi]
    fstp qword [numv]
    call full_text
    mov esi, nbuf
    mov edi, ebuf
    call scopy
    sub edi, ebuf
    mov [elen], edi
    jmp .draw
.typed:
    mov byte [ebuf], al
    mov byte [ebuf+1], 0
    mov dword [elen], 1
    mov byte [editing], 1
    jmp .draw
.editkey:
    movzx ebx, ah
    mov ecx, [elen]
    cmp bl, K_ESC
    je .edone
    cmp bl, K_ENTER
    je .enter
    cmp bl, K_BKSP
    je .bs
    cmp al, ' '
    jb .key
    cmp al, '~'
    ja .key
    cmp ecx, EMAX
    jae .key
    mov [ebuf+ecx], al
    inc ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .draw
.bs:
    test ecx, ecx
    jz .key
    dec ecx
    mov byte [ebuf+ecx], 0
    mov [elen], ecx
    jmp .draw
.enter:
    mov esi, ebuf
    call evaluate
    jc .draw                    ; the message shows; editing goes on
    call store_entry
    jc .draw
    inc dword [crow]
    call clamp_row
    call recompute
.edone:
    mov byte [editing], 0
    jmp .draw
.click:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    sub ebx, TY + ROW_H
    js .key
    cmp ebx, VIS * ROW_H
    jae .key
    cmp eax, C1_X
    jb .key
    cmp eax, TAB_R
    jae .key
    xor ecx, ecx
    cmp eax, C2_X
    jb .c1
    inc ecx
.c1:
    mov [ccol], ecx
    mov eax, ebx
    xor edx, edx
    mov ecx, ROW_H
    div ecx
    add eax, [top]
    mov [crow], eax
    mov byte [editing], 0
    call clamp_row
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

; ---------- the lists ----------
; eax = list -> esi = its first number
list_ptr:
    imul esi, eax, N_MAX * 8
    add esi, lists
    ret

; -> esi = the current entry, or CF on the empty slot after the list
cur_ptr:
    mov eax, [ccol]
    call list_ptr
    mov eax, [crow]
    mov ecx, [ccol]
    cmp eax, [len+ecx*4]
    jae .no
    lea esi, [esi+eax*8]
    clc
    ret
.no:
    stc
    ret

; crow within 0 .. len (the slot after the last entry), the view on it
clamp_row:
    push eax
    push ecx
    mov ecx, [ccol]
    mov eax, [len+ecx*4]
    cmp eax, N_MAX - 1
    jbe .l
    mov eax, N_MAX - 1
.l:
    cmp [crow], eax
    jbe .t
    mov [crow], eax
.t:
    mov eax, [crow]
    cmp eax, [top]
    jae .b
    mov [top], eax
.b:
    sub eax, VIS - 1
    jbe .r
    cmp eax, [top]
    jbe .r
    mov [top], eax
.r:
    pop ecx
    pop eax
    ret

; val -> the current entry, or appended after the list. CF if full.
store_entry:
    pushad
    mov ecx, [ccol]
    mov eax, [crow]
    cmp eax, [len+ecx*4]
    jb .put
    mov eax, [len+ecx*4]
    cmp eax, N_MAX
    jae .full
    inc dword [len+ecx*4]
    mov [crow], eax
.put:
    mov edx, eax
    mov eax, ecx
    call list_ptr
    fld qword [val]
    fstp qword [esi+edx*8]
    popad
    clc
    ret
.full:
    mov dword [msg], m_full
    popad
    stc
    ret

delete_entry:
    pushad
    call cur_ptr
    jc .r
    mov edi, esi
    add esi, 8
    mov ecx, [ccol]
    mov eax, [len+ecx*4]
    sub eax, [crow]
    dec eax                     ; entries below
    lea ecx, [eax*2]
    rep movsd
    mov ecx, [ccol]
    dec dword [len+ecx*4]
    call clamp_row
.r:
    popad
    ret

; The view again after the data changed (an error shows the help).
recompute:
    cmp dword [view], V_HELP
    je .r
    call compute
.r:
    ret

; ---------- numbers ----------
; esi = expression -> val, or CF and the error in msg
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
    mov dword [msg], etext
    popad
    stc
    ret

; numv -> nbuf as sci prints it (all its digits)
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

; ---------- results ----------
; esi = label, st0 = value (popped): a "label = value" line
add_res:
    push eax
    mov eax, [nres]
    cmp eax, RES_MAX
    jae .full
    mov [res_lab+eax*4], esi
    fstp qword [res_val+eax*8]
    mov byte [res_has+eax], 1
    inc dword [nres]
    pop eax
    ret
.full:
    fstp st0
    pop eax
    ret

; esi = a line of text alone
add_text:
    push eax
    mov eax, [nres]
    cmp eax, RES_MAX
    jae .r
    mov [res_lab+eax*4], esi
    mov byte [res_has+eax], 0
    inc dword [nres]
.r:
    pop eax
    ret

; [view] -> the results (and what the plot needs). An error goes to msg
; and the panel shows the help.
compute:
    pushad
    mov dword [nres], 0
    mov byte [plot], 0
    mov eax, [view]
    cmp eax, V_ONE
    je .one
    cmp eax, V_TWO
    je .two
    cmp eax, V_REG
    je .reg
    cmp eax, V_HIST
    je .hist
    cmp eax, V_BOX
    je .box
    cmp eax, V_SCAT
    je .scat
    jmp .r
.one:
    call one_var
    jmp .done
.two:
    call two_var
    jmp .done
.reg:
    call regression
    jmp .done
.hist:
    call histogram
    jmp .done
.box:
    call box_stats
    jmp .done
.scat:
    call pairs
    jc .done
    mov esi, s_n
    fild dword [pn]
    call add_res
    mov byte [plot], V_SCAT
    clc
.done:
    jnc .r
    mov dword [view], V_HELP
.r:
    popad
    ret

; The current list -> srt (sorted), sn = its length; CF if empty.
sort_cur:
    pushad
    mov eax, [ccol]
    mov ecx, [len+eax*4]
    mov [sn], ecx
    test ecx, ecx
    jz .empty
    call list_ptr
    mov edi, srt
    lea ecx, [ecx*2]
    rep movsd
    mov ecx, 1                  ; insertion sort
.i:
    cmp ecx, [sn]
    jae .ok
    fld qword [srt+ecx*8]
    mov edx, ecx
.j:
    test edx, edx
    jz .put
    fld qword [srt+edx*8-8]
    fcomip st0, st1
    jbe .put
    fld qword [srt+edx*8-8]
    fstp qword [srt+edx*8]
    dec edx
    jmp .j
.put:
    fstp qword [srt+edx*8]
    inc ecx
    jmp .i
.ok:
    popad
    clc
    ret
.empty:
    mov dword [msg], m_empty
    popad
    stc
    ret

; esi = sorted numbers, ecx = how many (> 0) -> st0 = their median
median:
    push eax
    mov eax, ecx
    shr eax, 1
    test ecx, 1
    jz .even
    fld qword [esi+eax*8]
    pop eax
    ret
.even:
    fld qword [esi+eax*8-8]
    fadd qword [esi+eax*8]
    fmul dword [f_half]
    pop eax
    ret

; srt, sn -> q1, med, q3
quartiles:
    pushad
    mov ecx, [sn]
    mov esi, srt
    call median
    fst qword [med]
    cmp ecx, 2
    jae .halves
    fst qword [q1]
    fstp qword [q3]
    jmp .r
.halves:
    fstp st0
    shr ecx, 1                  ; the lower half
    call median
    fstp qword [q1]
    mov eax, [sn]
    sub eax, ecx
    lea esi, [srt+eax*8]
    call median
    fstp qword [q3]
.r:
    popad
    ret

; The current list -> sums: n, mean, ss (sum of squares about the mean)
; in sum, mean, ss. Needs srt from sort_cur.
moments:
    pushad
    fldz
    xor ecx, ecx
.s:
    cmp ecx, [sn]
    jae .m
    fadd qword [srt+ecx*8]
    inc ecx
    jmp .s
.m:
    fst qword [sum]
    fidiv dword [sn]
    fstp qword [mean]
    fldz
    xor ecx, ecx
.q:
    cmp ecx, [sn]
    jae .d
    fld qword [srt+ecx*8]
    fsub qword [mean]
    fmul st0, st0
    faddp st1, st0
    inc ecx
    jmp .q
.d:
    fstp qword [ssq]
    popad
    ret

one_var:
    call sort_cur
    jc .r
    call moments
    call quartiles
    mov esi, s_n
    fild dword [sn]
    call add_res
    mov esi, s_mean
    fld qword [mean]
    call add_res
    mov esi, s_sum
    fld qword [sum]
    call add_res
    fldz                        ; sum of x^2
    xor ecx, ecx
.sq:
    cmp ecx, [sn]
    jae .sqd
    fld qword [srt+ecx*8]
    fmul st0, st0
    faddp st1, st0
    inc ecx
    jmp .sq
.sqd:
    mov esi, s_sumsq
    call add_res
    cmp dword [sn], 2
    jb .pop
    mov esi, s_sx               ; sample standard deviation
    fld qword [ssq]
    mov eax, [sn]
    dec eax
    mov [tmp], eax
    fidiv dword [tmp]
    fsqrt
    call add_res
.pop:
    mov esi, s_sigx             ; population standard deviation
    fld qword [ssq]
    fidiv dword [sn]
    fsqrt
    call add_res
    call five
    clc
.r:
    ret

; min, Q1, median, Q3, max as results (after sort_cur and quartiles)
five:
    mov esi, s_min
    fld qword [srt]
    call add_res
    mov esi, s_q1
    fld qword [q1]
    call add_res
    mov esi, s_med
    fld qword [med]
    call add_res
    mov esi, s_q3
    fld qword [q3]
    call add_res
    mov esi, s_max
    mov eax, [sn]
    fld qword [srt+eax*8-8]
    call add_res
    ret

box_stats:
    call sort_cur
    jc .r
    call quartiles
    mov esi, s_n
    fild dword [sn]
    call add_res
    call five
    mov byte [plot], V_BOX
    clc
.r:
    ret

; L1 and L2 as pairs -> pn, CF (and msg) unless both have the same
; length of at least 1
pairs:
    mov eax, [len]
    test eax, eax
    jz .empty
    cmp eax, [len+4]
    jne .differ
    mov [pn], eax
    clc
    ret
.empty:
    mov dword [msg], m_empty
    stc
    ret
.differ:
    mov dword [msg], m_differ
    stc
    ret

; the means of L1 and L2 and Sxx, Syy, Sxy about them (after pairs)
sums2:
    pushad
    fldz
    fldz
    xor ecx, ecx
.s:
    cmp ecx, [pn]
    jae .m
    fadd qword [lists+ecx*8]
    fxch
    fadd qword [lists+N_MAX*8+ecx*8]
    fxch
    inc ecx
    jmp .s
.m:
    fst qword [sumx]
    fidiv dword [pn]
    fstp qword [mx]
    fst qword [sumy]
    fidiv dword [pn]
    fstp qword [my]
    fldz
    fstp qword [sxx]
    fldz
    fstp qword [syy]
    fldz
    fstp qword [sxy]
    xor ecx, ecx
.q:
    cmp ecx, [pn]
    jae .r
    fld qword [lists+ecx*8]
    fsub qword [mx]
    fld qword [lists+N_MAX*8+ecx*8]
    fsub qword [my]
    fld st1
    fmul st0, st1
    fadd qword [sxy]
    fstp qword [sxy]
    fmul st0, st0
    fadd qword [syy]
    fstp qword [syy]
    fmul st0, st0
    fadd qword [sxx]
    fstp qword [sxx]
    inc ecx
    jmp .q
.r:
    popad
    ret

two_var:
    call pairs
    jc .r
    call sums2
    mov esi, s_n
    fild dword [pn]
    call add_res
    mov esi, s_mx
    fld qword [mx]
    call add_res
    mov esi, s_my
    fld qword [my]
    call add_res
    mov esi, s_sumx
    fld qword [sumx]
    call add_res
    mov esi, s_sumy
    fld qword [sumy]
    call add_res
    fldz                        ; sum of x*y
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .pd
    fld qword [lists+ecx*8]
    fmul qword [lists+N_MAX*8+ecx*8]
    faddp st1, st0
    inc ecx
    jmp .p
.pd:
    mov esi, s_sumxy
    call add_res
    cmp dword [pn], 2
    jb .ok
    mov eax, [pn]
    dec eax
    mov [tmp], eax
    mov esi, s_sx
    fld qword [sxx]
    fidiv dword [tmp]
    fsqrt
    call add_res
    mov esi, s_sy
    fld qword [syy]
    fidiv dword [tmp]
    fsqrt
    call add_res
    fld qword [sxx]             ; r, when neither list is constant
    fmul qword [syy]
    ftst
    fnstsw ax
    sahf
    je .flat
    fsqrt
    fdivr qword [sxy]
    mov esi, s_r
    call add_res
    jmp .ok
.flat:
    fstp st0
.ok:
    clc
.r:
    ret

; ---------- regression ----------
; tx, ty, pn -> slope, icept: the least-squares line; CF if all tx are
; the same
fit_line:
    pushad
    fldz
    fldz
    xor ecx, ecx
.s:
    cmp ecx, [pn]
    jae .m
    fadd qword [tx+ecx*8]
    fxch
    fadd qword [ty+ecx*8]
    fxch
    inc ecx
    jmp .s
.m:
    fidiv dword [pn]
    fstp qword [fx]             ; mean of tx
    fidiv dword [pn]
    fstp qword [fy]
    fldz                        ; Sxy
    fldz                        ; Sxx
    xor ecx, ecx
.q:
    cmp ecx, [pn]
    jae .d
    fld qword [tx+ecx*8]
    fsub qword [fx]
    fld st0
    fmul st0, st0
    faddp st2, st0
    fld qword [ty+ecx*8]
    fsub qword [fy]
    fmulp st1, st0
    faddp st2, st0
    inc ecx
    jmp .q
.d:
    ftst
    fnstsw ax
    sahf
    je .flat
    fdivp st1, st0
    fst qword [slope]
    fmul qword [fx]
    fsubr qword [fy]
    fstp qword [icept]
    popad
    clc
    ret
.flat:
    fstp st0
    fstp st0
    mov dword [msg], m_samex
    popad
    stc
    ret

; L1, L2, pn, edx = degree (1-3) -> coef[0..3] (coef[i] of x^i), by the
; normal equations; CF if they are singular (too few distinct x)
polyfit:
    pushad
    mov [deg], edx
    lea eax, [edx+1]
    mov [dim], eax
    xor ebx, ebx                ; nm[i][j] = sum x^(i+j), rhs[i] = sum y x^i
.zero:
    fldz
    fstp qword [nm+ebx*8]
    inc ebx
    cmp ebx, 20
    jb .zero
    xor ecx, ecx
.pt:
    cmp ecx, [pn]
    jae .solve
    fld1                        ; powers x^0 .. x^6 into pw
    xor ebx, ebx
.pw:
    fst qword [pw+ebx*8]
    fmul qword [lists+ecx*8]
    inc ebx
    cmp ebx, 7
    jb .pw
    fstp st0
    xor esi, esi                ; i
.i:
    cmp esi, [dim]
    jae .next
    xor edi, edi                ; j
.j:
    cmp edi, [dim]
    jae .rhs
    lea ebx, [esi+edi]
    fld qword [pw+ebx*8]
    imul ebx, esi, 5
    add ebx, edi
    fadd qword [nm+ebx*8]
    fstp qword [nm+ebx*8]
    inc edi
    jmp .j
.rhs:
    imul ebx, esi, 5
    add ebx, 4                  ; column 4 is the right side
    fld qword [pw+esi*8]
    fmul qword [lists+N_MAX*8+ecx*8]
    fadd qword [nm+ebx*8]
    fstp qword [nm+ebx*8]
    inc esi
    jmp .i
.next:
    inc ecx
    jmp .pt
.solve:                         ; Gauss-Jordan, partial pivoting
    xor esi, esi                ; the pivot column
.col:
    cmp esi, [dim]
    jae .back
    mov edi, esi                ; the row with the largest entry
    mov ebx, esi
.find:
    inc ebx
    cmp ebx, [dim]
    jae .found
    imul eax, ebx, 5
    add eax, esi
    fld qword [nm+eax*8]
    fabs
    imul eax, edi, 5
    add eax, esi
    fld qword [nm+eax*8]
    fabs
    fcomip st0, st1
    fstp st0
    jae .find
    mov edi, ebx
    jmp .find
.found:
    imul eax, edi, 5
    add eax, esi
    fld qword [nm+eax*8]
    fabs
    fld qword [f_tiny]
    fcomip st0, st1
    fstp st0
    jae .singular
    xor ebx, ebx                ; swap rows esi and edi
.sw:
    imul eax, esi, 5
    add eax, ebx
    imul edx, edi, 5
    add edx, ebx
    fld qword [nm+eax*8]
    fld qword [nm+edx*8]
    fstp qword [nm+eax*8]
    fstp qword [nm+edx*8]
    inc ebx
    cmp ebx, 5
    jb .sw
    xor edi, edi                ; clear the column in the other rows
.el:
    cmp edi, esi
    je .eln
    cmp edi, [dim]
    jae .eld
    imul eax, edi, 5
    add eax, esi
    fld qword [nm+eax*8]        ; factor = nm[r][c] / nm[c][c]
    imul eax, esi, 5
    add eax, esi
    fdiv qword [nm+eax*8]
    xor ebx, ebx
.row:
    imul eax, esi, 5
    add eax, ebx
    fld qword [nm+eax*8]
    fmul st0, st1
    imul edx, edi, 5
    add edx, ebx
    fsubr qword [nm+edx*8]
    fstp qword [nm+edx*8]
    inc ebx
    cmp ebx, 5
    jb .row
    fstp st0
.eln:
    inc edi
    jmp .el
.eld:
    inc esi
    jmp .col
.back:
    xor esi, esi
.cf:
    fldz
    fstp qword [coef+esi*8]
    inc esi
    cmp esi, 4
    jb .cf
    xor esi, esi
.co:
    imul eax, esi, 5
    fld qword [nm+eax*8+4*8]
    add eax, esi
    fdiv qword [nm+eax*8]
    fstp qword [coef+esi*8]
    inc esi
    cmp esi, [dim]
    jb .co
    popad
    clc
    ret
.singular:
    mov dword [msg], m_samex
    popad
    stc
    ret

; st0 -> e^st0
fexp:
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

; st0 (> 0) -> ln st0
fln:
    fldln2
    fxch
    fyl2x
    ret

; mxv -> myv = the model at x, or CF where it is undefined
model_y:
    mov eax, [model]
    cmp eax, M_CUBIC
    jbe .poly
    cmp eax, M_EXP
    je .exp
    cmp eax, M_LOGI
    je .logi
    fld qword [mxv]             ; log and power need x > 0
    ftst
    fnstsw ax
    sahf
    jbe .undef
    call fln
    cmp dword [model], M_LOG
    je .log
    fmul qword [coef+8]         ; power: a * e^(b ln x)
    call fexp
    fmul qword [coef]
    jmp .ok
.log:                           ; a + b ln x
    fmul qword [coef+8]
    fadd qword [coef]
    jmp .ok
.exp:                           ; a * e^(x ln b)
    fld qword [lnb]
    fmul qword [mxv]
    call fexp
    fmul qword [coef]
    jmp .ok
.logi:                          ; c / (1 + a e^(-b x))
    fld qword [coef+8]
    fmul qword [mxv]
    fchs
    call fexp
    fmul qword [coef]
    fld1
    faddp st1, st0
    fdivr qword [coef+16]
    jmp .ok
.poly:                          ; Horner on coef[3..0]
    fld qword [coef+24]
    fmul qword [mxv]
    fadd qword [coef+16]
    fmul qword [mxv]
    fadd qword [coef+8]
    fmul qword [mxv]
    fadd qword [coef]
.ok:
    fstp qword [myv]
    clc
    ret
.undef:
    fstp st0
    stc
    ret

; -> sse: the sum of squared residuals of the model over the pairs
model_sse:
    pushad
    fldz
    fstp qword [sse]
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .r
    fld qword [lists+ecx*8]
    fstp qword [mxv]
    call model_y
    jc .inf
    fld qword [myv]
    fsub qword [lists+N_MAX*8+ecx*8]
    fmul st0, st0
    fadd qword [sse]
    fstp qword [sse]
    inc ecx
    jmp .p
.inf:
    fld dword [f_huge]
    fstp qword [sse]
.r:
    popad
    ret

; tx = L1 (or ln L1 with bit 0 of eax), ty = L2 (or ln L2 with bit 1);
; CF and msg if a logarithm's argument is not > 0
transform:
    pushad
    mov ebp, eax
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .ok
    fld qword [lists+ecx*8]
    test ebp, 1
    jz .x
    ftst
    fnstsw ax
    sahf
    jbe .badx
    call fln
.x:
    fstp qword [tx+ecx*8]
    fld qword [lists+N_MAX*8+ecx*8]
    test ebp, 2
    jz .y
    ftst
    fnstsw ax
    sahf
    jbe .bady
    call fln
.y:
    fstp qword [ty+ecx*8]
    inc ecx
    jmp .p
.ok:
    popad
    clc
    ret
.badx:
    fstp st0
    mov dword [msg], m_xpos
    popad
    stc
    ret
.bady:
    fstp st0
    mov dword [msg], m_ypos
    popad
    stc
    ret

; logistic: for c = [lc], fit ln(c/y - 1) = ln a - b x -> coef, sse
logi_at:
    pushad
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .fit
    fld qword [lists+ecx*8]
    fstp qword [tx+ecx*8]
    fld qword [lc]
    fdiv qword [lists+N_MAX*8+ecx*8]
    fld1
    fsubp st1, st0
    call fln
    fstp qword [ty+ecx*8]
    inc ecx
    jmp .p
.fit:
    call fit_line
    jc .bad
    fld qword [icept]
    call fexp
    fstp qword [coef]           ; a
    fld qword [slope]
    fchs
    fstp qword [coef+8]         ; b
    fld qword [lc]
    fstp qword [coef+16]        ; c
    call model_sse
    popad
    ret
.bad:
    fld dword [f_huge]
    fstp qword [sse]
    popad
    ret

; logistic: c by golden section between 1.000001 and 10 times the
; largest y, the fit inside
logistic:
    pushad
    fld qword [lists+N_MAX*8]   ; the largest y
    xor ecx, ecx
.mx:
    cmp ecx, [pn]
    jae .got
    fld qword [lists+N_MAX*8+ecx*8]
    fcomi st0, st1
    jbe .smaller
    fxch
.smaller:
    fstp st0
    inc ecx
    jmp .mx
.got:
    fld st0
    fmul qword [f_lo_c]
    fstp qword [ga]
    fmul dword [f_10]
    fstp qword [gb]
    mov ebp, 120
.it:
    fld qword [gb]              ; c1 = b - g (b - a), c2 = a + g (b - a)
    fsub qword [ga]
    fmul qword [f_gold]
    fld qword [gb]
    fsub st0, st1
    fstp qword [gc1]
    fadd qword [ga]
    fstp qword [gc2]
    fld qword [gc1]
    fstp qword [lc]
    call logi_at
    fld qword [sse]
    fstp qword [gs1]
    fld qword [gc2]
    fstp qword [lc]
    call logi_at
    fld qword [sse]             ; keep the side of the smaller sse
    fld qword [gs1]
    fcomip st0, st1
    fstp st0
    ja .right
    fld qword [gc2]
    fstp qword [gb]
    jmp .n
.right:
    fld qword [gc1]
    fstp qword [ga]
.n:
    dec ebp
    jnz .it
    fld qword [ga]
    fadd qword [gb]
    fmul dword [f_half]
    fstp qword [lc]
    call logi_at
    popad
    ret

regression:
    call pairs
    jc .r
    call sums2
    mov eax, [model]
    mov esi, [model_name+eax*4]
    call add_text
    mov ecx, [model_min+eax*4]  ; points needed
    cmp [pn], ecx
    jb .few
    cmp eax, M_CUBIC
    jbe .poly
    cmp eax, M_EXP
    je .exp
    cmp eax, M_LOG
    je .log
    cmp eax, M_POW
    je .pow
    mov eax, 2                  ; logistic: y > 0
    call transform
    jc .r
    call logistic
    fld qword [sse]
    fld dword [f_huge]
    fcomip st0, st1
    fstp st0
    jbe .nofit
    jmp .show
.poly:
    lea edx, [eax+1]
    call polyfit
    jc .r
    mov ecx, [model]            ; a is the highest power
    inc ecx
    xor ebx, ebx
.rev:
    mov eax, ecx
    sub eax, ebx
    fld qword [coef+eax*8]
    fstp qword [shown+ebx*8]
    inc ebx
    cmp ebx, ecx
    jbe .rev
    lea ecx, [ecx+1]
    jmp .coefs
.exp:
    mov eax, 2
    call transform
    jc .r
    call fit_line
    jc .r
    fld qword [icept]
    call fexp
    fstp qword [coef]
    fld qword [slope]
    fst qword [lnb]
    call fexp
    fstp qword [coef+8]
    jmp .two
.log:
    mov eax, 1
    call transform
    jc .r
    call fit_line
    jc .r
    fld qword [icept]
    fstp qword [coef]
    fld qword [slope]
    fstp qword [coef+8]
    jmp .two
.pow:
    mov eax, 3
    call transform
    jc .r
    call fit_line
    jc .r
    fld qword [icept]
    call fexp
    fstp qword [coef]
    fld qword [slope]
    fstp qword [coef+8]
.two:
    fld qword [coef]
    fstp qword [shown]
    fld qword [coef+8]
    fstp qword [shown+8]
    mov ecx, 2
    jmp .coefs
.show:                          ; logistic: a, b, c
    fld qword [coef]
    fstp qword [shown]
    fld qword [coef+8]
    fstp qword [shown+8]
    fld qword [coef+16]
    fstp qword [shown+16]
    mov ecx, 3
.coefs:
    xor ebx, ebx
.c:
    mov esi, [coef_name+ebx*4]
    fld qword [shown+ebx*8]
    call add_res
    inc ebx
    cmp ebx, ecx
    jb .c
    call model_sse              ; r^2 = 1 - SSres / SStot
    fld1
    fld qword [syy]
    ftst
    fnstsw ax
    sahf
    je .r2
    fdivr qword [sse]
    fsubp st1, st0
    jmp .r2s
.r2:
    fstp st0
.r2s:
    mov esi, s_r2
    call add_res
    mov byte [plot], V_REG
    clc
.r:
    ret
.few:
    mov dword [msg], m_few
    stc
    ret
.nofit:
    mov dword [msg], m_nofit
    stc
    ret

; the current list -> bins (nbins of width bw from blo) and their counts
histogram:
    call sort_cur
    jc .r
    fild dword [sn]             ; about the square root of n bins
    fsqrt
    fistp dword [nbins]
    cmp dword [nbins], 1
    jge .b1
    mov dword [nbins], 1
.b1:
    cmp dword [nbins], 12
    jle .b2
    mov dword [nbins], 12
.b2:
    fld qword [srt]
    fstp qword [blo]
    mov eax, [sn]
    fld qword [srt+eax*8-8]
    fsub qword [srt]
    ftst
    fnstsw ax
    sahf
    jne .w
    fstp st0                    ; all equal: one bin of width 1
    mov dword [nbins], 1
    fld1
    fld qword [blo]
    fsub dword [f_half]
    fstp qword [blo]
    jmp .ws
.w:
    fidiv dword [nbins]
.ws:
    fstp qword [bw]
    xor ecx, ecx
.z:
    mov dword [bins+ecx*4], 0
    inc ecx
    cmp ecx, 12
    jb .z
    xor ecx, ecx
.c:
    cmp ecx, [sn]
    jae .shown
    fld qword [srt+ecx*8]
    fsub qword [blo]
    fdiv qword [bw]
    fstcw [cw0]                 ; floor: round toward -inf
    mov ax, [cw0]
    or ax, 0x0400
    and ax, ~0x0800
    mov [cw1], ax
    fldcw [cw1]
    fistp dword [tmp]
    fldcw [cw0]
    mov eax, [tmp]
    test eax, eax
    jns .lo
    xor eax, eax
.lo:
    cmp eax, [nbins]
    jb .in
    mov eax, [nbins]
    dec eax
.in:
    inc dword [bins+eax*4]
    inc ecx
    jmp .c
.shown:
    mov esi, s_n
    fild dword [sn]
    call add_res
    mov esi, s_bins
    fild dword [nbins]
    call add_res
    mov esi, s_from
    fld qword [blo]
    call add_res
    mov esi, s_width
    fld qword [bw]
    call add_res
    mov byte [plot], V_HIST
    clc
.r:
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
    call draw_table
    call draw_panel
    call draw_status
    call gui_flip
    popad
    ret

draw_table:
    pushad
    mov eax, TX                 ; white under the table
    mov ebx, TY
    mov ecx, TAB_R - TX
    mov edx, (VIS + 1) * ROW_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    mov esi, s_hidx
    mov eax, TX + 1
    mov ebx, TY + 1
    call gui_text
    mov esi, s_l1
    mov eax, C1_X + 1
    call gui_text
    mov esi, s_l2
    mov eax, C2_X + 1
    call gui_text
    mov byte [gui_ink], C_DGREY ; lines under the header, between columns
    mov eax, TX
    mov ebx, TY + ROW_H - 1
    mov ecx, TAB_R - 1
    mov edx, ebx
    call gui_line
    mov eax, C1_X - 2
    mov ebx, TY
    mov ecx, eax
    mov edx, PAN_B - 1
    call gui_line
    mov eax, C2_X - 1
    mov ecx, eax
    call gui_line
    xor ebp, ebp                ; the visible rows
.row:
    mov eax, [top]
    add eax, ebp
    mov [drow], eax
    imul ebx, ebp, ROW_H
    add ebx, TY + ROW_H + 1
    mov [dyy], ebx
    mov edi, line               ; the row number
    inc eax
    call gui_utoa
    mov esi, line
    mov eax, TX + 1
    mov byte [gui_ink], C_DGREY
    mov byte [gui_bg], C_WHITE
    call gui_text
    xor edx, edx                ; each list
.cell:
    mov [dcol], edx
    mov eax, C1_X
    test edx, edx
    jz .cx
    mov eax, C2_X
.cx:
    mov [dx_], eax
    mov byte [gui_bg], C_WHITE
    mov eax, [drow]             ; the cursor cell
    cmp eax, [crow]
    jne .val
    cmp edx, [ccol]
    jne .val
    mov eax, [dx_]
    mov ebx, [dyy]
    dec ebx
    mov ecx, COL_W - 2
    mov edx, ROW_H
    mov byte [gui_ink], C_LCYAN
    cmp byte [editing], 0
    je .hl
    mov byte [gui_ink], C_YELLOW
.hl:
    call gui_fill
    mov al, [gui_ink]
    mov [gui_bg], al
.val:
    mov edx, [dcol]
    mov eax, [drow]
    cmp eax, [len+edx*4]
    jae .nc
    mov ecx, eax
    mov eax, edx
    call list_ptr
    fld qword [esi+ecx*8]
    fstp qword [numv]
    mov ecx, 9
    call num_text
    mov esi, nbuf
    mov eax, [dx_]
    inc eax
    mov ebx, [dyy]
    mov byte [gui_ink], C_BLACK
    call gui_text
.nc:
    mov edx, [dcol]
    inc edx
    cmp edx, 2
    jb .cell
    inc ebp
    cmp ebp, VIS
    jb .row
    popad
    ret

; The panel: the results as "label = value" lines, then the plot.
draw_panel:
    pushad
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    cmp dword [view], V_HELP
    jne .res
    mov esi, help_lines
    mov ebx, PAN_Y
.h:
    cmp byte [esi], 0
    je .r
    mov eax, PAN_X
    call gui_text
.skip:
    lodsb
    test al, al
    jnz .skip
    add ebx, ROW_H
    jmp .h
.res:
    xor ebp, ebp
    mov ebx, PAN_Y
.line:
    cmp ebp, [nres]
    jae .plot
    mov edi, line
    mov esi, [res_lab+ebp*4]
    call scopy
    cmp byte [res_has+ebp], 0
    je .out
    mov esi, s_eq
    call scopy
    fld qword [res_val+ebp*8]
    fstp qword [numv]
    mov ecx, 12
    call num_text
    mov esi, nbuf
    call scopy
.out:
    mov esi, line
    mov eax, PAN_X
    mov ecx, PAN_W
    call gui_textn
    add ebx, ROW_H
    inc ebp
    jmp .line
.plot:
    cmp byte [plot], 0
    je .r
    add ebx, 2
    mov [pl_y], ebx
    mov eax, PAN_B
    sub eax, ebx
    mov [pl_h], eax
    mov eax, PL_X               ; a white area with a frame
    mov ecx, PL_W
    mov edx, [pl_h]
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_ink], C_DGREY
    call gui_box
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    call gui_clip
    movzx eax, byte [plot]
    cmp eax, V_HIST
    je .hist
    cmp eax, V_BOX
    je .box
    call scatter                ; scatter and regression
    cmp byte [plot], V_REG
    jne .nc
    call curve
    jmp .nc
.hist:
    call bars
    jmp .nc
.box:
    call boxplot
.nc:
    call gui_noclip
.r:
    popad
    ret

; The x and y ranges of the pairs, 8% wider on each side (1 if flat)
ranges:
    pushad
    fld qword [lists]
    fst qword [rx0]
    fstp qword [rx1]
    fld qword [lists+N_MAX*8]
    fst qword [ry0]
    fstp qword [ry1]
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .wide
    fld qword [lists+ecx*8]
    lea esi, [rx0]
    call .minmax
    fld qword [lists+N_MAX*8+ecx*8]
    lea esi, [ry0]
    call .minmax
    inc ecx
    jmp .p
.wide:
    lea esi, [rx0]
    call .margin
    lea esi, [ry0]
    call .margin
    popad
    ret
.minmax:                        ; st0 into [esi] (min) and [esi+8] (max)
    fld qword [esi]
    fcomip st0, st1
    jbe .notmin
    fst qword [esi]
.notmin:
    fld qword [esi+8]
    fcomip st0, st1
    jae .notmax
    fst qword [esi+8]
.notmax:
    fstp st0
    ret
.margin:
    fld qword [esi+8]
    fsub qword [esi]
    ftst
    fnstsw ax
    sahf
    jne .m
    fstp st0
    fld1
.m:
    fmul dword [f_margin]
    fld qword [esi]
    fsub st0, st1
    fstp qword [esi]
    fadd qword [esi+8]
    fstp qword [esi+8]
    ret

; mxv, myv -> eax, ebx = the pixel on the plot (clamped far out)
to_px:
    fld qword [mxv]
    fsub qword [rx0]
    fld qword [rx1]
    fsub qword [rx0]
    fdivp st1, st0
    mov dword [tmp], PL_W - 3
    fimul dword [tmp]
    call clamp_int
    lea eax, [eax+PL_X+1]
    push eax
    fld qword [ry1]
    fsub qword [myv]
    fld qword [ry1]
    fsub qword [ry0]
    fdivp st1, st0
    mov eax, [pl_h]
    sub eax, 3
    mov [tmp], eax
    fimul dword [tmp]
    call clamp_int
    mov ebx, eax
    add ebx, [pl_y]
    inc ebx
    pop eax
    ret

; st0 -> eax, rounded, within +-10000 (popped)
clamp_int:
    fld dword [f_10000]
    fcomip st0, st1
    ja .hi
    fstp st0
    mov eax, 10000
    ret
.hi:
    fld dword [f_10000]
    fchs
    fcomip st0, st1
    jb .ok
    fstp st0
    mov eax, -10000
    ret
.ok:
    fistp dword [tmp]
    mov eax, [tmp]
    ret

; The pairs as small squares
scatter:
    pushad
    call pairs
    jc .r
    call ranges
    xor ecx, ecx
.p:
    cmp ecx, [pn]
    jae .r
    fld qword [lists+ecx*8]
    fstp qword [mxv]
    fld qword [lists+N_MAX*8+ecx*8]
    fstp qword [myv]
    call to_px
    push ecx
    dec eax
    dec ebx
    mov ecx, 3
    mov edx, 3
    mov byte [gui_ink], C_BLUE
    call gui_fill
    pop ecx
    inc ecx
    jmp .p
.r:
    popad
    ret

; The model across the plot, column by column
curve:
    pushad
    mov byte [havep], 0
    xor ebp, ebp
.c:
    mov [tmp], ebp              ; x at this column
    fild dword [tmp]
    fld qword [rx1]
    fsub qword [rx0]
    fmulp st1, st0
    mov dword [tmp], PL_W - 3
    fidiv dword [tmp]
    fadd qword [rx0]
    fstp qword [mxv]
    call model_y
    jc .gap
    call to_px
    cmp byte [havep], 0
    je .first
    mov ecx, [prevx]
    mov edx, [prevy]
    mov byte [gui_ink], C_RED
    call gui_line
.first:
    mov [prevx], eax
    mov [prevy], ebx
    mov byte [havep], 1
    jmp .n
.gap:
    mov byte [havep], 0
.n:
    inc ebp
    cmp ebp, PL_W - 3
    jbe .c
    popad
    ret

; The histogram's bars, the tallest filling the plot
bars:
    pushad
    xor eax, eax                ; the largest count
    xor ecx, ecx
.mx:
    cmp ecx, [nbins]
    jae .go
    cmp eax, [bins+ecx*4]
    jae .mn
    mov eax, [bins+ecx*4]
.mn:
    inc ecx
    jmp .mx
.go:
    mov [bmax], eax
    mov eax, PL_W - 4           ; bar width
    xor edx, edx
    div dword [nbins]
    mov [bwpx], eax
    xor ebp, ebp
.b:
    cmp ebp, [nbins]
    jae .r
    mov eax, [pl_h]             ; height = count * (h - 4) / max
    sub eax, 4
    imul eax, [bins+ebp*4]
    xor edx, edx
    div dword [bmax]
    mov edx, eax
    test edx, edx
    jz .n
    mov eax, [bwpx]
    imul eax, ebp
    add eax, PL_X + 2
    mov ebx, [pl_y]
    add ebx, [pl_h]
    sub ebx, 2
    sub ebx, edx
    mov ecx, [bwpx]
    mov byte [gui_ink], C_LBLUE
    call gui_fill
    mov byte [gui_ink], C_BLUE
    call gui_box
.n:
    inc ebp
    jmp .b
.r:
    popad
    ret

; The box plot: whiskers from min to max, the box Q1 to Q3, the median
boxplot:
    pushad
    fld qword [srt]             ; the range: min to max
    fstp qword [rx0]
    mov eax, [sn]
    fld qword [srt+eax*8-8]
    fstp qword [rx1]
    lea esi, [rx0]
    call ranges.margin
    fldz
    fstp qword [ry0]
    fld1
    fstp qword [ry1]
    fld dword [f_half]
    fstp qword [myv]
    fld qword [srt]             ; the whisker line
    fstp qword [mxv]
    call to_px
    mov [bx0], eax
    mov [by0], ebx
    mov eax, [sn]
    fld qword [srt+eax*8-8]
    fstp qword [mxv]
    call to_px
    mov ecx, eax
    mov edx, ebx
    mov eax, [bx0]
    mov byte [gui_ink], C_BLACK
    call gui_line
    mov ebx, [by0]              ; end ticks
    sub ebx, 4
    add edx, 4
    push ecx
    mov ecx, eax
    call gui_line
    pop eax
    mov ecx, eax
    call gui_line
    fld qword [q1]              ; the box
    fstp qword [mxv]
    call to_px
    mov [bx0], eax
    fld qword [q3]
    fstp qword [mxv]
    call to_px
    mov ecx, eax
    sub ecx, [bx0]
    inc ecx
    mov eax, [bx0]
    mov ebx, [by0]
    sub ebx, 8
    mov edx, 17
    mov byte [gui_ink], C_LBLUE
    call gui_fill
    mov byte [gui_ink], C_BLUE
    call gui_box
    fld qword [med]             ; the median
    fstp qword [mxv]
    call to_px
    mov ecx, eax
    mov ebx, [by0]
    lea edx, [ebx+8]
    sub ebx, 8
    mov byte [gui_ink], C_RED
    call gui_line
    popad
    ret

; The status row: the entry being typed, a message, or the keys
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
    jz .nomsg
    mov byte [gui_ink], C_RED
    jmp .out
.nomsg:
    cmp byte [editing], 0
    je .keys
    mov edi, line               ; "L1(3) = text_"
    mov al, 'L'
    stosb
    mov al, '1'
    add al, [ccol]
    stosb
    mov al, '('
    stosb
    mov eax, [crow]
    inc eax
    call gui_utoa
    mov esi, s_editeq
    call scopy
    mov esi, ebuf
    call scopy
    mov ax, '_'
    stosw
    mov esi, line
    jmp .out
.keys:
    mov esi, s_keys
.out:
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    call gui_textn
    popad
    ret

; ---------- files ----------
; fname -> the lists (CSV: x,y a line; a field may be empty; a first
; line that is not numbers is a header)
load:
    pushad
    mov dword [len], 0
    mov dword [len+4], 0
    mov eax, SYS_OPEN
    mov ebx, fname
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .new
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, fbuf
    mov edx, FBUF - 1
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    test eax, eax
    jns .got
    xor eax, eax
.got:
    mov byte [fbuf+eax], 0
    mov esi, fbuf
    mov dword [lineno], 0
.line:
    cmp byte [esi], 0
    je .done
    inc dword [lineno]
    xor ebp, ebp                ; the field: 0 x, 1 y
.field:
    mov edi, ebuf               ; up to , ; tab or the line's end
    xor ecx, ecx
.ch:
    mov al, [esi]
    test al, al
    jz .fend
    cmp al, 10
    je .fend
    cmp al, ','
    je .fend
    cmp al, ';'
    je .fend
    cmp al, 9
    je .fend
    inc esi
    cmp al, 13
    je .ch
    cmp al, ' '
    je .ch
    cmp ecx, EMAX
    jae .ch
    stosb
    inc ecx
    jmp .ch
.fend:
    mov byte [edi], 0
    test ecx, ecx
    jz .empty
    cmp ebp, 2
    jae .empty
    push esi
    mov esi, ebuf
    call evaluate
    pop esi
    jc .bad
    mov eax, ebp
    mov ecx, [len+eax*4]
    cmp ecx, N_MAX
    jae .empty
    push esi
    call list_ptr
    fld qword [val]
    fstp qword [esi+ecx*8]
    pop esi
    inc dword [len+eax*4]
.empty:
    mov al, [esi]
    test al, al
    jz .done
    inc esi
    cmp al, 10
    je .line
    inc ebp
    jmp .field
.bad:
    cmp dword [lineno], 1       ; a header line
    jne .badnum
    mov dword [msg], 0
.skipline:
    mov al, [esi]
    test al, al
    jz .done
    inc esi
    cmp al, 10
    jne .skipline
    jmp .line
.badnum:
    mov dword [msg], m_badnum
    jmp .r
.done:
    mov dword [msg], m_loaded
.r:
    popad
    ret
.new:
    mov dword [msg], m_newfile
    popad
    ret

; the lists -> fname as CSV
save:
    pushad
    mov edi, fbuf
    mov ecx, [len]
    cmp ecx, [len+4]
    jae .n
    mov ecx, [len+4]
.n:
    xor ebx, ebx
.row:
    cmp ebx, ecx
    jae .write
    xor ebp, ebp
.f:
    cmp ebx, [len+ebp*4]
    jae .sep
    mov eax, ebp
    call list_ptr
    fld qword [esi+ebx*8]
    fstp qword [numv]
    call full_text
    mov esi, nbuf
    call scopy
.sep:
    mov al, ','
    test ebp, ebp
    jz .put
    mov al, 10
.put:
    stosb
    inc ebp
    cmp ebp, 2
    jb .f
    inc ebx
    jmp .row
.write:
    sub edi, fbuf
    mov [flen], edi
    mov eax, SYS_OPEN
    mov ebx, fname
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, fbuf
    mov edx, [flen]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [flen]
    jne .fail
    mov dword [msg], m_saved
    popad
    clc
    ret
.fail:
    mov dword [msg], m_nosave
    popad
    stc
    ret

; ---------- strings ----------
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
; esi = doubles, ecx = how many -> L1 (eax = 0) or L2 (eax = 1)
set_list:
    pushad
    mov [len+eax*4], ecx
    mov edx, ecx
    push esi
    call list_ptr
    mov edi, esi
    pop esi
    lea ecx, [edx*2]
    rep movsd
    popad
    ret

; esi = expected doubles, ecx = how many: CF unless the results with a
; value match them in order (to 1e-6 relative, or absolute near 0)
expect:
    pushad
    xor ebx, ebx                ; result
    xor edx, edx                ; expected
.e:
    cmp edx, ecx
    jae .yes
.f:
    cmp ebx, [nres]
    jae .no
    cmp byte [res_has+ebx], 0
    jne .cmp
    inc ebx
    jmp .f
.cmp:
    fld qword [res_val+ebx*8]
    fsub qword [esi+edx*8]
    fabs
    fld qword [esi+edx*8]
    fabs
    fld1
    fcomi st0, st1
    jae .one
    fxch
.one:
    fstp st1
    fmul qword [f_tol]
    fcomip st0, st1
    fstp st0
    jbe .no
    inc ebx
    inc edx
    jmp .e
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ecx = view, edx = model: computed, drawn, then checked against esi
; (ecx2 = how many in eax) -> CF
check_view:
    mov [view], ecx
    mov [model], edx
    push eax
    push esi
    call compute
    call draw
    pop esi
    pop ecx
    cmp dword [view], V_HELP    ; an error
    je .no
    jmp expect
.no:
    stc
    ret

selftest:
    mov byte [bad], 'v'         ; one-variable: 1..5
    xor eax, eax
    mov esi, d15
    mov ecx, 5
    call set_list
    mov eax, 1
    mov esi, d24545
    mov ecx, 5
    call set_list
    mov dword [ccol], 0
    mov ecx, V_ONE
    xor edx, edx
    mov esi, e_one
    mov eax, 11
    call check_view
    jc .fail
    mov byte [bad], 'x'         ; two-variable
    mov ecx, V_TWO
    mov esi, e_two
    mov eax, 9
    call check_view
    jc .fail
    mov byte [bad], 'l'         ; linear: 0.6 x + 2.2, r^2 = 0.6
    mov ecx, V_REG
    mov edx, M_LIN
    mov esi, e_lin
    mov eax, 3
    call check_view
    jc .fail
    mov byte [bad], 'q'         ; quadratic: 2x^2 - 3x + 1
    xor eax, eax
    mov esi, d15
    mov ecx, 5
    call set_list
    mov eax, 1
    mov esi, dquad
    mov ecx, 5
    call set_list
    mov ecx, V_REG
    mov edx, M_QUAD
    mov esi, e_quad
    mov eax, 4
    call check_view
    jc .fail
    mov byte [bad], 'c'         ; cubic: x^3 - x on -2..3
    xor eax, eax
    mov esi, dm23
    mov ecx, 6
    call set_list
    mov eax, 1
    mov esi, dcub
    mov ecx, 6
    call set_list
    mov ecx, V_REG
    mov edx, M_CUBIC
    mov esi, e_cub
    mov eax, 5
    call check_view
    jc .fail
    mov byte [bad], 'e'         ; exponential: 2 * 3^x on 0..4
    xor eax, eax
    mov esi, d04
    mov ecx, 5
    call set_list
    mov eax, 1
    mov esi, dexp
    mov ecx, 5
    call set_list
    mov ecx, V_REG
    mov edx, M_EXP
    mov esi, e_exp
    mov eax, 3
    call check_view
    jc .fail
    mov byte [bad], 'g'         ; logarithmic: 1 + 2 ln x on 1..5
    xor eax, eax
    mov esi, d15
    mov ecx, 5
    call set_list
    mov eax, 1
    mov esi, dlog
    mov ecx, 5
    call set_list
    mov ecx, V_REG
    mov edx, M_LOG
    mov esi, e_log
    mov eax, 3
    call check_view
    jc .fail
    mov byte [bad], 'w'         ; power: 3 x^2 on 1..5
    mov eax, 1
    mov esi, dpow
    mov ecx, 5
    call set_list
    mov ecx, V_REG
    mov edx, M_POW
    mov esi, e_pow
    mov eax, 3
    call check_view
    jc .fail
    mov byte [bad], 's'         ; logistic: 10 / (1 + 4 e^-x) on 0..8
    xor eax, eax
    mov esi, d08
    mov ecx, 9
    call set_list
    mov eax, 1
    mov esi, dlogi
    mov ecx, 9
    call set_list
    mov ecx, V_REG
    mov edx, M_LOGI
    mov esi, e_logi
    mov eax, 4
    call check_view
    jc .fail
    mov byte [bad], 'h'         ; histogram of 1..8: 3 bins, 3 2 3
    xor eax, eax
    mov esi, d18
    mov ecx, 8
    call set_list
    mov ecx, V_HIST
    xor edx, edx
    mov esi, e_hist
    mov eax, 2
    call check_view
    jc .fail
    cmp dword [bins], 3
    jne .fail
    cmp dword [bins+4], 2
    jne .fail
    cmp dword [bins+8], 3
    jne .fail
    mov byte [bad], 'b'         ; box plot of 1..8: 2.5 4.5 6.5
    mov ecx, V_BOX
    mov esi, e_box
    mov eax, 6
    call check_view
    jc .fail
    mov byte [bad], 'f'         ; save, empty, load: the same lists
    mov eax, 1
    mov esi, d24545
    mov ecx, 5
    call set_list
    mov esi, s_testfile
    mov edi, fname
    call scopy
    call save
    jc .fail
    mov dword [len], 0
    mov dword [len+4], 0
    call load
    cmp dword [len], 8
    jne .fail
    cmp dword [len+4], 5
    jne .fail
    fld qword [lists+7*8]
    fcomp dword [f_8]
    fnstsw ax
    sahf
    jne .fail
    fld qword [lists+N_MAX*8+2*8]
    fcomp dword [f_5]
    fnstsw ax
    sahf
    jne .fail
    mov byte [bad], 'n'         ; errors: different lengths, x <= 0
    mov ecx, V_TWO
    mov esi, e_two
    xor eax, eax
    call check_view
    jnc .fail
    cmp dword [msg], m_differ
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
f_half dd 0.5
f_10 dd 10.0
f_10000 dd 10000.0
f_margin dd 0.08
f_huge dd 1.0e30
f_5 dd 5.0
f_8 dd 8.0
alignb 8
f_noise dq 1.0e-10
f_tiny dq 1.0e-12
f_tol dq 1.0e-6
f_gold dq 0.6180339887498949
f_lo_c dq 1.000001
pow10 dq 1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0

; self-check data and what it must give
d15 dq 1.0, 2.0, 3.0, 4.0, 5.0
d24545 dq 2.0, 4.0, 5.0, 4.0, 5.0
d18 dq 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0
d04 dq 0.0, 1.0, 2.0, 3.0, 4.0
d08 dq 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0
dm23 dq -2.0, -1.0, 0.0, 1.0, 2.0, 3.0
dquad dq 0.0, 3.0, 10.0, 21.0, 36.0
dcub dq -6.0, 0.0, 0.0, 0.0, 6.0, 24.0
dexp dq 2.0, 6.0, 18.0, 54.0, 162.0
dlog dq 1.0, 2.386294361119891, 3.197224577336219, 3.772588722239781, 4.218875824868201
dpow dq 3.0, 12.0, 27.0, 48.0, 75.0
dlogi dq 2.0, 4.046096751916896, 6.487856442839393, 8.33925230201154, 9.317384593585716
      dq 9.737555469386477, 9.901823335417472, 9.963657282452662, 9.98659947638337
; n mean sum sumsq sx sigx min q1 med q3 max
e_one dq 5.0, 3.0, 15.0, 55.0, 1.5811388300841898, 1.4142135623730951
      dq 1.0, 1.5, 3.0, 4.5, 5.0
; n mx my sumx sumy sumxy sx sy r
e_two dq 5.0, 3.0, 4.0, 15.0, 20.0, 66.0, 1.5811388300841898, 1.224744871391589
      dq 0.7745966692414834
e_lin dq 0.6, 2.2, 0.6
e_quad dq 2.0, -3.0, 1.0, 1.0
e_cub dq 1.0, 0.0, -1.0, 0.0, 1.0
e_exp dq 2.0, 3.0, 1.0
e_log dq 1.0, 2.0, 1.0
e_pow dq 3.0, 2.0, 1.0
e_logi dq 4.0, 1.0, 10.0, 1.0
e_hist dq 8.0, 3.0
e_box dq 8.0, 1.0, 2.5, 4.5, 6.5, 8.0

title db 'Statistics', 0
s_default db 'stats.csv', 0
s_testfile db 'stest.csv', 0
s_x db 'x', 0
s_hidx db '#', 0
s_l1 db 'L1', 0
s_l2 db 'L2', 0
s_eq db ' = ', 0
s_editeq db ') = ', 0
s_keys db 'v x r h b p  Enter type  Del  ^S save  ^N new  Esc', 0
s_n db 'n', 0
s_mean db 'mean', 0
s_sum db 'sum', 0
s_sumsq db 'sum x^2', 0
s_sx db 'sx', 0
s_sy db 'sy', 0
s_sigx db 'sigma x', 0
s_min db 'min', 0
s_q1 db 'Q1', 0
s_med db 'median', 0
s_q3 db 'Q3', 0
s_max db 'max', 0
s_mx db 'mean x', 0
s_my db 'mean y', 0
s_sumx db 'sum x', 0
s_sumy db 'sum y', 0
s_sumxy db 'sum xy', 0
s_r db 'r', 0
s_r2 db 'r^2', 0
s_bins db 'bins', 0
s_from db 'from', 0
s_width db 'width', 0
s_ca db 'a', 0
s_cb db 'b', 0
s_cc db 'c', 0
s_cd db 'd', 0
coef_name dd s_ca, s_cb, s_cc, s_cd
model_name dd n_lin, n_quad, n_cub, n_exp, n_log, n_pow, n_logi
model_min dd 2, 3, 4, 2, 2, 2, 3
n_lin db 'linear: y = a*x + b', 0
n_quad db 'quadratic: y=a*x^2+b*x+c', 0
n_cub db 'cubic: y=a*x^3+b*x^2+c*x+d', 0
n_exp db 'exponential: y = a*b^x', 0
n_log db 'logarithmic: y=a+b*ln(x)', 0
n_pow db 'power: y = a*x^b', 0
n_logi db 'logistic: y=c/(1+a*e^(-b*x))', 0
help_lines:
    db 'Type numbers into L1 and L2:', 0
    db 'a digit starts an entry,', 0
    db 'Enter keeps it and goes down.', 0
    db ' ', 0
    db 'v  statistics of the list', 0
    db 'x  L1 and L2 as x and y', 0
    db 'r  regression of L2 on L1', 0
    db '   (again: the next model)', 0
    db 'h  histogram of the list', 0
    db 'b  box plot of the list', 0
    db 'p  scatter plot', 0
    db 'Tab  the other list', 0
    db 'Del  remove an entry', 0
    db 'Ctrl+S  save CSV', 0
    db 'Ctrl+N  empty both lists', 0
    db 0
m_empty db 'The list is empty', 0
m_differ db 'L1 and L2 must have the same length', 0
m_samex db 'Not enough different x values', 0
m_few db 'Too few points for this model', 0
m_xpos db 'This model needs every x > 0', 0
m_ypos db 'This model needs every y > 0', 0
m_nofit db 'No fit found', 0
m_full db 'The list is full (99)', 0
m_loaded db 'Loaded', 0
m_newfile db 'New file', 0
m_badnum db 'Not a number in the file', 0
m_saved db 'Saved', 0
m_nosave db 'Could not save', 0
m_nogfx db 'stats: no graphics', 10, 0
pass db 'stats: PASS', 10, 0
fail db 'stats: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 8
lists resq 2 * N_MAX
srt resq N_MAX
tx resq N_MAX
ty resq N_MAX
res_val resq RES_MAX
nm resq 20
pw resq 7
coef resq 4
shown resq 4
val resq 1
numv resq 1
sum resq 1
mean resq 1
ssq resq 1
q1 resq 1
med resq 1
q3 resq 1
sumx resq 1
sumy resq 1
mx resq 1
my resq 1
sxx resq 1
syy resq 1
sxy resq 1
fx resq 1
fy resq 1
slope resq 1
icept resq 1
lnb resq 1
mxv resq 1
myv resq 1
sse resq 1
lc resq 1
ga resq 1
gb resq 1
gc1 resq 1
gc2 resq 1
gs1 resq 1
blo resq 1
bw resq 1
rx0 resq 1
rx1 resq 1
ry0 resq 1
ry1 resq 1
arg resd 1
tmp resd 1
len resd 2
crow resd 1
ccol resd 1
top resd 1
view resd 1
model resd 1
msg resd 1
elen resd 1
nres resd 1
res_lab resd RES_MAX
sn resd 1
pn resd 1
deg resd 1
dim resd 1
nbins resd 1
bins resd 12
bmax resd 1
bwpx resd 1
nwidth resd 1
drow resd 1
dcol resd 1
dx_ resd 1
dyy resd 1
pl_y resd 1
pl_h resd 1
prevx resd 1
prevy resd 1
bx0 resd 1
by0 resd 1
lineno resd 1
flen resd 1
cw0 resw 1
cw1 resw 1
res_has resb RES_MAX
editing resb 1
plot resb 1
havep resb 1
ev resb GE_SIZE
etext resb 40
nbuf resb 40
ebuf resb EMAX + 2
line resb 80
fname resb 64
fbuf resb FBUF
SQX_END
