; Squirrel-OS/2 — Grapher: 2D graphing calculator (C.2, OS2-APPS)
; Original code. run grapher [function]   |   run grapher test
;
; Plots up to four functions at once, each in its own colour, on the
; kernel's sci engine (SYS_GUI GUI_EVAL):
;
;   y = f(x)  or just f(x)          explicit
;   r = f(t)                        polar, t from 0 to 2 pi
;   x = f(t), y = g(t)              parametric, t from 0 to 2 pi
;   f(x, y) = g(x, y)               implicit: x^2 + y^2 = 25, x = 3
;   f(x, y) < g(x, y)  (> <= >=)    inequality: the region is shaded
;
; a, b and c standing alone are sliders (each 1 at first, -10 to 10):
; the a, b or c key picks one; Left/Right change it by 0.1, Up/Down by
; 1, a click or drag on its bar sets it, Esc or Enter ends.
;
; Viewing:  Enter edit the current function   Tab  next function
;           Delete  remove it                 + -  zoom in / out
;           arrows  pan                       Home the standard window
;           left click: centre the view there
;           t  trace (Left/Right move along the curve, Up/Down change
;              function, Esc ends)
;           z  roots of the current function in view
;           m  minima and maxima in view      i  intersections with the
;                                                next explicit function
;           a b c  sliders               Esc  quit
; Editing:  type the function, Enter plots it, Esc leaves it as it was.
;
; "run grapher test" plots y = x^2 - 1, reads the curve back from the
; screen, finds its roots (-1 and 1), its minimum (0, -1) and where it
; meets y = x + 1 (-1 and 2), reads back the implicit circle
; x^2 + y^2 = 25, the shading of y < x and y = a*x with a = 2, and prints
; "grapher: PASS" or FAIL.
; See documentation/apps/grapher.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

SLOTS       equ 4
TEXT_MAX    equ 56
PX          equ 2                       ; plot area on the screen
PY          equ 1 + WIN_TITLE_H + 1
PW          equ SCR_W - 4
PH          equ SCR_H - PY - 2 * CELL_H - 5
ROW1_Y      equ PY + PH + 2             ; the function row
ROW2_Y      equ ROW1_Y + CELL_H + 1     ; the status row
TSTEPS      equ 240                     ; steps in t for polar / parametric
FOUND_MAX   equ 8

K_EXPL      equ 1                       ; slot kinds
K_POLAR     equ 2
K_PARAM     equ 3
K_IMPL      equ 4                       ; F(x, y) = lhs - rhs, drawn where F = 0
K_INEQ      equ 5                       ; the region where F > 0 or F < 0
EXPR_MAX    equ 248                     ; an expression with sliders filled in

; slot record
S_KIND      equ 0
S_REL       equ 1                       ; inequality: bit 0 F > 0 (else F < 0),
                                        ; bit 1 or equal
S_USES      equ 2                       ; bits 0-2: uses slider a, b, c
S_TEXT      equ 4                       ; what was typed
S_E1        equ S_TEXT + TEXT_MAX + 1   ; f (in x), with t turned into x
S_E2        equ S_E1 + EXPR_MAX         ; g for parametric
S_SIZE      equ S_E2 + EXPR_MAX

SLIDERS     equ 3
GSTEP          equ 2                       ; grid step of implicit plots, pixels
NCOL        equ PW / GSTEP + 1
NROW        equ PH / GSTEP + 1
SB_X        equ PX + 50                 ; the slider bar on the status row
SB_W        equ 200                     ; 0.1 a pixel, -10 to 10

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    mov dword [slider], 100
    mov dword [slider+4], 100
    mov dword [slider+8], 100
    call std_window
    call gui_open
    jc .nogfx
    mov esi, [arg]
    cmp dword [esi], 'test'
    je selftest
    cmp byte [esi], 0
    je .edit
    mov edi, edit_buf           ; a function on the command line
    call scopy0
    call commit
    jnc .view
.edit:
    call edit_line
.view:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    mov byte [status], 0
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .drag
    movzx ebx, ah               ; scancode
    cmp byte [sliding], 0
    je .noslide
    call slide_key
    jmp .view
.noslide:
    cmp byte [tracing], 0
    je .notrace
    call trace_key
    jmp .view
.notrace:
    cmp bl, K_ESC
    je .quit
    cmp bl, K_ENTER
    je .edit
    cmp bl, K_TAB
    je .next
    cmp bl, K_DEL
    je .del
    cmp bl, K_HOME
    je .home
    cmp bl, K_LEFT
    je .pl
    cmp bl, K_RIGHT
    je .pr
    cmp bl, K_UP
    je .pu
    cmp bl, K_DOWN
    je .pd
    or al, 0x20                 ; lower case (and '+' stays '+')
    cmp al, '+'
    je .zin
    cmp al, '='
    je .zin
    cmp al, '-'
    je .zout
    cmp al, 't'
    je .trace
    cmp al, 'z'
    je .roots
    cmp al, 'm'
    je .ext
    cmp al, 'i'
    je .inter
    cmp al, 'a'
    jb .key
    cmp al, 'a' + SLIDERS - 1
    ja .key
    sub al, 'a'
    mov [sel], al
    mov byte [sliding], 1
    jmp .view
.drag:
    cmp byte [sliding], 0
    je .key
    call slide_mouse
    jmp .view
.click:
    cmp byte [sliding], 0
    je .centre
    call slide_mouse
    jnc .view
.centre:
    mov eax, [gui_mx]
    sub eax, PX
    mov ebx, [gui_my]
    sub ebx, PY
    call center_on
    jmp .view
.next:
    mov eax, [cur]
    inc eax
    and eax, SLOTS - 1
    mov [cur], eax
    jmp .view
.del:
    call cur_slot
    mov byte [edi+S_KIND], 0
    mov byte [edi+S_TEXT], 0
    jmp .view
.home:
    call std_window
    jmp .view
.pl:
    mov eax, -(PW / 4)
    xor ebx, ebx
    jmp .pan
.pr:
    mov eax, PW / 4
    xor ebx, ebx
    jmp .pan
.pu:
    xor eax, eax
    mov ebx, -(PH / 4)
    jmp .pan
.pd:
    xor eax, eax
    mov ebx, PH / 4
.pan:
    add eax, PW / 2
    add ebx, PH / 2
    call center_on
    jmp .view
.zin:
    fld dword [f_half]
    jmp .zoom
.zout:
    fld dword [f_two]
.zoom:
    fstp qword [zf]
    call zoom
    jmp .view
.trace:
    call cur_slot
    cmp byte [edi+S_KIND], 0
    je .key
    cmp byte [edi+S_KIND], K_IMPL
    jb .cantrace
    mov esi, m_notrace
    mov edi, status
    call scopy0
    jmp .view
.cantrace:
    mov byte [tracing], 1
    mov dword [tpos], PW / 2
    cmp byte [edi+S_KIND], K_EXPL
    je .view
    mov dword [tpos], 0
    jmp .view
.roots:
    call find_roots
    jmp .view
.ext:
    call find_extrema
    jmp .view
.inter:
    call find_inter
    jmp .view
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- the window in graph units ----------
std_window:
    fld dword [f_m10]
    fst qword [xmin]
    fstp qword [ymin]
    fld dword [f_10]
    fst qword [xmax]
    fstp qword [ymax]
    ret

; eax, ebx = a point of the plot area in pixels: it becomes the centre.
center_on:
    call px_to_x
    fld qword [xmax]
    fsub qword [xmin]
    fmul dword [f_half]         ; half the width
    fld qword [vx]
    fsub st0, st1
    fstp qword [xmin]
    fadd qword [vx]
    fstp qword [xmax]
    mov eax, ebx
    call py_to_y
    fld qword [ymax]
    fsub qword [ymin]
    fmul dword [f_half]
    fld qword [vy]
    fsub st0, st1
    fstp qword [ymin]
    fadd qword [vy]
    fstp qword [ymax]
    ret

; Scales both ranges about the centre by zf.
zoom:
    fld qword [xmin]
    fadd qword [xmax]
    fmul dword [f_half]         ; centre
    fld qword [xmax]
    fsub qword [xmin]
    fmul qword [zf]
    fmul dword [f_half]         ; new half width
    fld st1
    fsub st0, st1
    fstp qword [xmin]
    faddp st1, st0
    fstp qword [xmax]
    fld qword [ymin]
    fadd qword [ymax]
    fmul dword [f_half]
    fld qword [ymax]
    fsub qword [ymin]
    fmul qword [zf]
    fmul dword [f_half]
    fld st1
    fsub st0, st1
    fstp qword [ymin]
    faddp st1, st0
    fstp qword [ymax]
    ret

; eax = column of the plot area -> vx = xmin + eax * (xmax - xmin) / (PW - 1)
px_to_x:
    mov [tmp], eax
    fild dword [tmp]
    fld qword [xmax]
    fsub qword [xmin]
    fmulp st1, st0
    mov dword [tmp], PW - 1
    fidiv dword [tmp]
    fadd qword [xmin]
    fstp qword [vx]
    ret

; eax = row of the plot area -> vy (row 0 is ymax)
py_to_y:
    mov [tmp], eax
    fild dword [tmp]
    fld qword [ymax]
    fsub qword [ymin]
    fmulp st1, st0
    mov dword [tmp], PH - 1
    fidiv dword [tmp]
    fsubr qword [ymax]
    fstp qword [vy]
    ret

; vx, vy -> eax, ebx = pixel in the plot area, clamped to +-20000 (far
; points still give lines that leave the area the right way).
to_pixel:
    fld qword [vx]
    fsub qword [xmin]
    mov dword [tmp], PW - 1
    fimul dword [tmp]
    fld qword [xmax]
    fsub qword [xmin]
    fdivp st1, st0
    call clamp_pop
    mov eax, [tmp]
    fld qword [ymax]
    fsub qword [vy]
    mov dword [tmp], PH - 1
    fimul dword [tmp]
    fld qword [ymax]
    fsub qword [ymin]
    fdivp st1, st0
    call clamp_pop
    mov ebx, [tmp]
    ret

; st0 -> tmp, rounded and clamped to +-20000, popped
clamp_pop:
    fld dword [f_lim]
    fcomip st0, st1
    ja .hi
    fstp st0
    mov dword [tmp], 20000
    ret
.hi:
    fld dword [f_lim]
    fchs
    fcomip st0, st1
    jb .ok
    fstp st0
    mov dword [tmp], -20000
    ret
.ok:
    fistp dword [tmp]
    ret

; ---------- evaluation ----------
; esi = expression, ex = x -> ey, CF on an error (the FPU is reset).
eval:
    push eax
    push ebx
    push ecx
    mov [ev+GE_EXPR], esi
    mov dword [ev+GE_FLAGS], GEF_X
    fld qword [ex]
    fstp qword [ev+GE_X]
    mov dword [ev+GE_TEXT], ev_text
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    fld qword [ev+GE_RESULT]
    fstp qword [ey]
    test eax, eax               ; 0 or -1
    pop ecx
    pop ebx
    pop eax
    jnz .err
    clc
    ret
.err:
    stc
    ret

; esi = expression in x and y, ex = x, eyin = y -> ey, CF on an error.
eval_xy:
    push eax
    push ebx
    push ecx
    mov [ev+GE_EXPR], esi
    mov dword [ev+GE_FLAGS], GEF_XY
    fld qword [ex]
    fstp qword [ev+GE_X]
    fld qword [eyin]
    fstp qword [ev+GE_Y]
    mov dword [ev+GE_TEXT], ev_text
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    fld qword [ev+GE_RESULT]
    fstp qword [ey]
    test eax, eax
    pop ecx
    pop ebx
    pop eax
    jnz .err
    clc
    ret
.err:
    stc
    ret

; [val] -> fmt_buf: the number as sci prints it (through GUI_EVAL "x"),
; first rounded to 1e-5 of the x range's power of ten, so 6.28318... in
; a window 20 wide reads 6.2832 and a root at 1e-17 reads 0.
fmt:
    pushad
    fld qword [xmax]
    fsub qword [xmin]
    fmul dword [f_1e5]
    call pow10_near             ; q
    fld qword [val]
    fdiv st0, st1
    frndint
    fmulp st1, st0
    fstp qword [val]
    mov dword [ev+GE_EXPR], s_x
    mov dword [ev+GE_FLAGS], GEF_X
    fld qword [val]
    fstp qword [ev+GE_X]
    mov dword [ev+GE_TEXT], fmt_buf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    popad
    ret

; edi = slot, edx = point number -> vx, vy = the point: for explicit
; slots edx is a column, otherwise a step in t. CF if undefined there.
point:
    cmp byte [edi+S_KIND], K_EXPL
    jne .t
    mov eax, edx
    call px_to_x
    fld qword [vx]
    fstp qword [ex]
    lea esi, [edi+S_E1]
    call eval
    jc .r
    fld qword [ey]
    fstp qword [vy]
    clc
.r:
    ret
.t:
    mov [tmp], edx              ; t = step * 2 pi / TSTEPS
    fild dword [tmp]
    fldpi
    fmulp st1, st0
    fadd st0, st0
    mov dword [tmp], TSTEPS
    fidiv dword [tmp]
    fst qword [ex]
    fstp qword [tval]
    lea esi, [edi+S_E1]
    call eval
    jc .r
    cmp byte [edi+S_KIND], K_POLAR
    je .polar
    fld qword [ey]
    fstp qword [vx]
    fld qword [tval]
    fstp qword [ex]
    lea esi, [edi+S_E2]
    call eval
    jc .r
    fld qword [ey]
    fstp qword [vy]
    clc
    ret
.polar:                         ; x = r cos t, y = r sin t
    fld qword [tval]
    fsincos
    fmul qword [ey]
    fstp qword [vx]
    fmul qword [ey]
    fstp qword [vy]
    clc
    ret

; edi = slot -> ecx = its last point number
last_point:
    mov ecx, PW - 1
    cmp byte [edi+S_KIND], K_EXPL
    je .r
    mov ecx, TSTEPS
.r:
    ret

; ---------- drawing ----------
draw:
    pushad
    mov eax, 0
    mov ebx, 0
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    mov eax, PX
    mov ebx, PY
    mov ecx, PW
    mov edx, PH
    mov byte [gui_ink], C_WHITE
    call gui_fill
    call gui_clip
    call axes
    xor ebp, ebp
.slot:
    mov edi, ebp
    imul edi, S_SIZE
    add edi, slots
    cmp byte [edi+S_KIND], 0
    je .ns
    mov al, [colours+ebp]
    mov [gui_ink], al
    cmp byte [edi+S_KIND], K_IMPL
    jae .field
    call plot
    jmp .ns
.field:
    call field
.ns:
    inc ebp
    cmp ebp, SLOTS
    jb .slot
    call marks
    cmp byte [tracing], 0
    je .rows
    call trace_mark
.rows:
    call gui_noclip
    call row1
    call row2
    call gui_flip
    popad
    ret

; The axes (dark grey) where they are in view, with a tick at every
; grid step along each.
axes:
    pushad
    mov byte [gui_ink], C_DGREY
    fldz
    fst qword [vx]
    fstp qword [vy]
    call to_pixel
    mov [ax0], eax
    mov [ay0], ebx
    ; the x axis
    lea ebx, [ebx+PY]
    mov eax, PX
    mov ecx, PX + PW - 1
    mov edx, ebx
    call gui_line
    ; the y axis
    mov eax, [ax0]
    add eax, PX
    mov ecx, eax
    mov ebx, PY
    mov edx, PY + PH - 1
    call gui_line
    ; ticks: the step is a power of ten that gives 4 to 40 ticks
    fld qword [xmax]
    fsub qword [xmin]
    call grid_step
    fstp qword [gstep]
    fld qword [xmin]
    fdiv qword [gstep]
    frndint
    fmul qword [gstep]
    fstp qword [gpos]
.xt:
    fld qword [gpos]
    fcom qword [xmax]
    fnstsw ax
    sahf
    ja .xdone
    fstp qword [vx]
    fldz
    fstp qword [vy]
    call to_pixel
    add eax, PX
    add ebx, PY
    lea edx, [ebx+2]
    sub ebx, 2
    mov ecx, eax
    call gui_line
    fld qword [gpos]
    fadd qword [gstep]
    fstp qword [gpos]
    jmp .xt
.xdone:
    fstp st0
    fld qword [ymax]
    fsub qword [ymin]
    call grid_step
    fstp qword [gstep]
    fld qword [ymin]
    fdiv qword [gstep]
    frndint
    fmul qword [gstep]
    fstp qword [gpos]
.yt:
    fld qword [gpos]
    fcom qword [ymax]
    fnstsw ax
    sahf
    ja .ydone
    fstp qword [vy]
    fldz
    fstp qword [vx]
    call to_pixel
    add eax, PX
    add ebx, PY
    lea ecx, [eax+2]
    sub eax, 2
    mov edx, ebx
    call gui_line
    fld qword [gpos]
    fadd qword [gstep]
    fstp qword [gpos]
    jmp .yt
.ydone:
    fstp st0
    popad
    ret

; st0 = a range -> st0 = 10^round(log10(range / 20)): about 6 to 60 ticks
grid_step:
    fmul dword [f_twentieth]
; st0 -> st0 = 10^round(log10(st0))
pow10_near:
    fldlg2
    fxch
    fyl2x                       ; log10
    frndint                     ; nearest; 4..40 ticks either way is fine
    fldl2t
    fmulp st1, st0              ; * log2(10)
    fld st0                     ; 2^st0
    frndint
    fsub st1, st0
    fxch
    f2xm1
    fld1
    faddp st1, st0
    fscale
    fstp st1
    ret

; edi = slot, [gui_ink] = colour: its curve, point to point. A jump of
; more than the plot height between two points is not joined (asymptotes).
plot:
    pushad
    mov byte [havep], 0
    call last_point
    mov [lastp], ecx
    xor edx, edx
.p:
    push edx
    call point
    pop edx
    jc .gap
    call to_pixel
    add eax, PX
    add ebx, PY
    cmp byte [havep], 0
    je .first
    mov ecx, ebx
    sub ecx, [prevy]
    jns .abs
    neg ecx
.abs:
    cmp ecx, PH
    ja .first
    mov ecx, [prevx]
    push edx
    mov edx, [prevy]
    call gui_line
    pop edx
.first:
    mov [prevx], eax
    mov [prevy], ebx
    mov byte [havep], 1
    mov cl, [gui_ink]
    call gui_pset
    jmp .n
.gap:
    mov byte [havep], 0
.n:
    inc edx
    cmp edx, [lastp]
    jbe .p
    popad
    ret

; Small black squares on the points found by z, m or i.
marks:
    pushad
    xor ebp, ebp
.m:
    cmp ebp, [nfound]
    jae .r
    mov eax, ebp
    shl eax, 4
    fld qword [found+eax]
    fstp qword [vx]
    fld qword [found+eax+8]
    fstp qword [vy]
    call to_pixel
    lea eax, [eax+PX-1]
    lea ebx, [ebx+PY-1]
    mov ecx, 3
    mov edx, 3
    mov byte [gui_ink], C_BLACK
    call gui_fill
    inc ebp
    jmp .m
.r:
    popad
    ret

; The function row: "n: text" in the slot's colour, or the editor.
row1:
    pushad
    mov eax, PX
    mov ebx, ROW1_Y
    mov ecx, PW
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov eax, [cur]
    mov dl, [colours+eax]
    mov [gui_ink], dl
    mov eax, PX                 ; a swatch in the slot's colour
    mov ebx, ROW1_Y + 1
    mov ecx, 5
    mov edx, 6
    call gui_fill
    mov edi, line
    mov eax, [cur]
    inc eax
    add al, '0'
    stosb
    mov ax, ': '
    stosw
    cmp byte [editing], 0
    je .shown
    mov esi, edit_buf
    call scopy
    mov al, '_'
    stosb
    jmp .out
.shown:
    call cur_slot
    lea esi, [edi+S_TEXT]
    mov edi, line + 3
    cmp byte [esi], 0
    jne .t
    mov esi, s_empty
.t:
    call scopy
.out:
    mov byte [edi], 0
    mov esi, line
    mov eax, PX + 8
    mov ebx, ROW1_Y
    mov ecx, PW - 8
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    popad
    ret

; The status row: a message, the trace values, or the window and help;
; while a slider is chosen, its value and bar.
row2:
    pushad
    mov eax, PX
    mov ebx, ROW2_Y
    mov ecx, PW
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    cmp byte [sliding], 0
    jne .slider
    mov esi, status
    cmp byte [esi], 0
    jne .out
    mov esi, s_help_edit
    cmp byte [editing], 0
    jne .out
    mov esi, s_help
.out:
    mov eax, PX
    mov ebx, ROW2_Y
    mov ecx, PW
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    popad
    ret
.slider:                        ; "a = 1.5", the bar and its knob
    mov edi, line
    mov al, 'a'
    add al, [sel]
    stosb
    mov eax, ' = '
    stosd
    dec edi
    movzx eax, byte [sel]
    mov eax, [slider+eax*4]
    call hund
    mov byte [edi], 0
    mov esi, line
    mov eax, PX
    mov ebx, ROW2_Y
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    mov byte [gui_ink], C_DGREY
    mov eax, SB_X
    mov ebx, ROW2_Y + 3
    mov ecx, SB_X + SB_W
    mov edx, ebx
    call gui_line
    mov eax, SB_X + SB_W / 2    ; a tick at 0
    mov ecx, eax
    mov ebx, ROW2_Y + 1
    mov edx, ROW2_Y + 5
    call gui_line
    movzx eax, byte [sel]
    mov eax, [slider+eax*4]
    add eax, 1000
    xor edx, edx
    mov ecx, 10
    div ecx
    lea eax, [eax+SB_X-1]
    mov ebx, ROW2_Y
    mov ecx, 3
    mov edx, CELL_H - 1
    mov byte [gui_ink], C_BLACK
    call gui_fill
    mov esi, s_slide_help
    mov eax, SB_X + SB_W + 8
    mov ebx, ROW2_Y
    mov byte [gui_bg], C_LGREY
    call gui_text
    popad
    ret

; edi -> the current slot
cur_slot:
    mov edi, [cur]
    imul edi, S_SIZE
    add edi, slots
    ret

; ---------- editing ----------
; Edits the current slot on the function row. Enter plots it (a syntax
; error is shown and editing goes on), Esc leaves the slot as it was.
edit_line:
    pushad
    mov byte [editing], 1
    call cur_slot
    lea esi, [edi+S_TEXT]
    mov edi, edit_buf
    call scopy0
    sub edi, edit_buf
    mov ecx, edi                ; length
    call draw
    jmp .k
.d:                             ; typing redraws only the two rows
    call row1
    call row2
    pushad
    mov eax, PX
    mov ebx, ROW1_Y
    mov ecx, PW
    mov edx, 2 * CELL_H + 1
    call gui_flip_rect
    popad
.k:
    call gui_getkey
    mov byte [status], 0
    cmp ah, K_ESC
    je .done
    cmp ah, K_ENTER
    je .enter
    cmp ah, K_BKSP
    je .bs
    cmp al, ' '
    jb .k
    cmp al, '~'
    ja .k
    cmp ecx, TEXT_MAX
    jae .k
    mov [edit_buf+ecx], al
    inc ecx
    mov byte [edit_buf+ecx], 0
    jmp .d
.bs:
    jecxz .k
    dec ecx
    mov byte [edit_buf+ecx], 0
    jmp .d
.enter:
    push ecx
    call commit
    pop ecx
    jc .d
.done:
    mov byte [editing], 0
    popad
    ret

; edit_buf -> the current slot (kind, text, expressions). An empty text
; clears the slot. CF and a message in status if it does not parse; the
; slot then keeps what it had.
commit:
    pushad
    call cur_slot
    mov ebp, edi
    mov esi, edit_buf
    call parse
    jc .fail
    mov esi, edit_buf
    lea edi, [ebp+S_TEXT]
    call scopy0
    mov dword [nfound], 0
    popad
    clc
    ret
.fail:
    lea esi, [ebp+S_TEXT]       ; back to the slot's own text
    call parse
    popad
    stc
    ret

; esi = text, ebp = slot -> the slot's kind and expressions, with the
; sliders' values filled in. CF and a message in status if it does not
; parse (the slot's expressions may be overwritten then).
parse:
    pushad
    mov byte [uses], 0
    mov byte [relk], 0
    call skip
    cmp byte [esi], 0
    jne .some
    mov byte [ebp+S_KIND], 0
    jmp .ok
.some:
    mov al, [esi]               ; "y =", "r =", "x = ..., y ="
    or al, 0x20
    lea ebx, [esi+1]
    xchg esi, ebx
    call skip
    xchg esi, ebx
    cmp byte [ebx], '='
    jne .general
    inc ebx
    mov byte [kind], K_EXPL
    cmp al, 'y'
    je .rhs
    mov byte [kind], K_POLAR
    cmp al, 'r'
    je .rhs
    cmp al, 'x'
    jne .general
    mov ecx, ebx                ; x = : parametric only with a comma
.comma:
    mov dl, [ecx]
    inc ecx
    test dl, dl
    jz .general
    cmp dl, ','
    jne .comma
    mov byte [kind], K_PARAM
.rhs:
    mov esi, ebx
.one:
    lea edi, [ebp+S_E1]
    lea eax, [edi+EXPR_MAX-12]
    mov [elim], eax
    call copy_expr
    jc .long
    cmp byte [kind], K_PARAM
    jne .end
    cmp byte [esi], ','
    jne .bad
    inc esi
    call skip
    mov al, [esi]
    or al, 0x20
    cmp al, 'y'
    jne .bad
    inc esi
    call skip
    cmp byte [esi], '='
    jne .bad
    inc esi
    lea edi, [ebp+S_E2]
    lea eax, [edi+EXPR_MAX-12]
    mov [elim], eax
    call copy_expr
    jc .long
    jmp .end
.general:                       ; the first = < or > decides
    mov byte [kind], K_EXPL
    mov ecx, esi
.find:
    mov dl, [ecx]
    test dl, dl
    jz .one
    inc ecx
    cmp dl, '='
    je .eq
    cmp dl, '<'
    je .two
    cmp dl, '>'
    jne .find
    mov byte [relk], 1
    jmp .two
.eq:
    mov byte [kind], K_IMPL
    jmp .lhs
.two:
    mov byte [kind], K_INEQ
    cmp byte [ecx], '='
    jne .lhs
    or byte [relk], 2
.lhs:                           ; "(lhs)-(rhs)"
    lea edi, [ebp+S_E1]
    lea eax, [edi+EXPR_MAX-12]
    mov [elim], eax
    mov al, '('
    stosb
    call copy_expr
    jc .long
    mov al, ')'
    stosb
    mov al, '-'
    stosb
    mov al, '('
    stosb
    inc esi                     ; the relation: = < > <= >=
    cmp byte [esi], '='
    jne .r
    inc esi
.r:
    call copy_expr
    jc .long
    mov al, ')'
    stosb
    mov byte [edi], 0
.end:
    cmp byte [esi], 0
    jne .bad
    ; a syntax check at x = 1 (and y = 1); a domain error there is fine
    fld1
    fst qword [ex]
    fstp qword [eyin]
    lea esi, [ebp+S_E1]
    cmp byte [kind], K_IMPL
    jae .xy
    call eval
    jmp .e1
.xy:
    call eval_xy
.e1:
    jnc .e2
    call syntax_err
    jc .fail
.e2:
    cmp byte [kind], K_PARAM
    jne .store
    lea esi, [ebp+S_E2]
    call eval
    jnc .store
    call syntax_err
    jc .fail
.store:
    mov al, [kind]
    mov [ebp+S_KIND], al
    mov al, [relk]
    mov [ebp+S_REL], al
    mov al, [uses]
    mov [ebp+S_USES], al
.ok:
    popad
    clc
    ret
.long:
    mov esi, m_long
    jmp .msg
.bad:
    mov esi, m_form
.msg:
    mov edi, status
    call scopy0
.fail:
    popad
    stc
    ret

; Every slot that uses a slider, again with the sliders' new values.
reparse_all:
    pushad
    xor ebp, ebp
.s:
    mov edi, ebp
    imul edi, S_SIZE
    add edi, slots
    cmp byte [edi+S_KIND], 0
    je .n
    cmp byte [edi+S_USES], 0
    je .n
    push ebp
    mov ebp, edi
    lea esi, [edi+S_TEXT]
    call parse
    pop ebp
.n:
    inc ebp
    cmp ebp, SLOTS
    jb .s
    mov dword [nfound], 0
    popad
    ret

; After eval failed: CF and the message in status if it is a syntax error.
syntax_err:
    cmp dword [ev_text], 'synt'
    jne .no
    mov edi, status
    mov esi, s_error
    call scopy
    mov esi, ev_text
    call scopy
    mov eax, [ev+GE_COL]
    call gui_utoa
    stc
    ret
.no:
    clc
    ret

; esi = text -> edi: the expression up to a comma, = < > or the end
; (edi ends on its zero). A t that stands alone (not part of a longer
; name) becomes x; a lone a, b or c becomes its slider's value in
; brackets, and its bit is set in uses. CF if it would pass elim.
copy_expr:
    call skip
    xor edx, edx                ; dl: the last character was a letter
.c:
    mov al, [esi]
    test al, al
    jz .e
    cmp al, ','
    je .e
    cmp al, '='
    je .e
    cmp al, '<'
    je .e
    cmp al, '>'
    je .e
    cmp edi, [elim]
    jae .long
    mov ah, al
    call is_alpha
    jne .other
    test dl, dl
    jnz .letter
    mov ah, [esi+1]
    call is_alpha
    je .letter
    cmp al, 't'
    je .t
    cmp al, 'a'
    jb .letter
    cmp al, 'a' + SLIDERS - 1
    ja .letter
    movzx ebx, al               ; a slider: "(value)"
    sub ebx, 'a'
    bts dword [uses], ebx
    mov al, '('
    stosb
    mov eax, [slider+ebx*4]
    call hund
    mov al, ')'
    stosb
    mov dl, 1
    inc esi
    jmp .c
.t:
    mov al, 'x'
.letter:
    mov dl, 1
    jmp .put
.other:
    xor edx, edx
.put:
    stosb
    inc esi
    jmp .c
.e:
    mov byte [edi], 0
    clc
    ret
.long:
    stc
    ret

; eax = hundredths -> edi: the number ("1.5", "-0.25", "3"); edi ends
; after it. Keeps the other registers.
hund:
    push eax
    push ecx
    push edx
    test eax, eax
    jns .p
    mov byte [edi], '-'
    inc edi
    neg eax
.p:
    xor edx, edx
    mov ecx, 100
    div ecx
    push edx
    call gui_utoa
    pop eax
    test eax, eax
    jz .r
    mov byte [edi], '.'
    inc edi
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    stosb
    test edx, edx
    jz .r
    lea eax, [edx+'0']
    stosb
.r:
    pop edx
    pop ecx
    pop eax
    ret

; ah = character -> ZF set if it is a letter
is_alpha:
    push eax
    or ah, 0x20
    cmp ah, 'a'
    jb .no
    cmp ah, 'z'
    ja .no
    cmp al, al
    pop eax
    ret
.no:
    test esp, esp               ; ZF clear
    pop eax
    ret

skip:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip
.r:
    ret

; esi -> edi, without the zero (edi ends where it would go)
scopy:
    lodsb
    test al, al
    jz .r
    stosb
    jmp scopy
.r:
    mov byte [edi], 0
    ret

; esi -> edi with the zero; edi ends on the zero
scopy0:
    call scopy
    ret

; ---------- implicit curves and inequalities ----------
; edi = slot (K_IMPL or K_INEQ), [gui_ink] = its colour. F is sampled
; every GSTEP pixels. Where it changes sign along a grid edge the zero is
; put by linear interpolation and kept if F there is small (so a pole,
; where F jumps through infinity, is dropped); the zeros on the edges of
; each grid cell are joined by lines. An inequality shades the grid
; points where it holds (white pixels only, so curves and axes stay),
; and its boundary is dashed if strict.
field:
    pushad
    mov [fslot], edi
    mov dword [frow], 0
.row:
    mov eax, [frow]
    imul eax, GSTEP
    mov [fpy], eax
    call py_to_y
    fld qword [vy]
    fstp qword [eyin]
    mov dword [fcol], 0
    mov byte [vl_ok], 0
.col:
    mov eax, [fcol]
    imul eax, GSTEP
    mov [fpx], eax
    call px_to_x
    fld qword [vx]
    fstp qword [ex]
    mov edi, [fslot]
    lea esi, [edi+S_E1]
    call eval_xy
    mov ebx, [fcol]
    mov byte [vcur+ebx], 0
    mov byte [hc_ok+ebx], 0
    mov byte [vr_ok], 0
    jc .cell
    mov byte [vcur+ebx], 1
    fld qword [ey]
    fstp qword [fcur+ebx*8]
    cmp byte [edi+S_KIND], K_INEQ
    jne .h
    call holds
    jnc .h
    mov eax, [fpx]
    add eax, PX
    mov ebx, [fpy]
    add ebx, PY
    call gui_pget
    cmp cl, C_WHITE
    jne .h0
    mov cl, [gui_ink]
    call gui_pset
.h0:
    mov ebx, [fcol]
.h:                             ; the edge to the left
    test ebx, ebx
    jz .v
    cmp byte [vcur+ebx-1], 0
    je .v
    lea esi, [fcur+ebx*8-8]
    lea edx, [fcur+ebx*8]
    call cross
    jc .v
    mov eax, [fpx]
    sub eax, GSTEP
    mov [fbx], eax
    mov eax, [fpy]
    mov [fby], eax
    mov byte [fdir], 0
    call edge_point
    mov ebx, [fcol]
    jc .v
    mov [hc_x+ebx*4], eax
    mov [hc_y+ebx*4], ecx
    mov byte [hc_ok+ebx], 1
.v:                             ; the edge above
    cmp dword [frow], 0
    je .cell
    cmp byte [vprev+ebx], 0
    je .cell
    cmp byte [vcur+ebx], 0
    je .cell
    lea esi, [fprev+ebx*8]
    lea edx, [fcur+ebx*8]
    call cross
    jc .cell
    mov eax, [fpx]
    mov [fbx], eax
    mov eax, [fpy]
    sub eax, GSTEP
    mov [fby], eax
    mov byte [fdir], 1
    call edge_point
    jc .cell
    mov [vr_x], eax
    mov [vr_y], ecx
    mov byte [vr_ok], 1
.cell:
    call cell
    mov eax, [vr_x]             ; this right edge is the next left one
    mov [vl_x], eax
    mov eax, [vr_y]
    mov [vl_y], eax
    mov al, [vr_ok]
    mov [vl_ok], al
    inc dword [fcol]
    cmp dword [fcol], NCOL
    jb .col
    mov esi, fcur               ; this row becomes the one above
    mov edi, fprev
    mov ecx, NCOL * 2
    rep movsd
    mov esi, vcur
    mov edi, vprev
    mov ecx, NCOL
    rep movsb
    mov esi, hc_x
    mov edi, hp_x
    mov ecx, NCOL * 2
    rep movsd
    mov esi, hc_ok
    mov edi, hp_ok
    mov ecx, NCOL
    rep movsb
    inc dword [frow]
    cmp dword [frow], NROW
    jb .row
    popad
    ret

; The grid cell left of and above (fcol, frow): its zeros, top, left,
; bottom, right, joined two by two (one alone is a dot).
cell:
    pushad
    mov ebx, [fcol]
    test ebx, ebx
    jz .r
    cmp dword [frow], 0
    je .r
    mov edi, [fslot]            ; strict inequality: every other pair of
    cmp byte [edi+S_KIND], K_INEQ ; cells is left out
    jne .go
    test byte [edi+S_REL], 2
    jnz .go
    mov eax, ebx
    add eax, [frow]
    test eax, 2
    jnz .r
.go:
    xor ebp, ebp                ; points in cpts
    cmp byte [hp_ok+ebx], 0
    je .l
    mov eax, [hp_x+ebx*4]
    mov edx, [hp_y+ebx*4]
    call .add
.l:
    cmp byte [vl_ok], 0
    je .b
    mov eax, [vl_x]
    mov edx, [vl_y]
    call .add
.b:
    cmp byte [hc_ok+ebx], 0
    je .rt
    mov eax, [hc_x+ebx*4]
    mov edx, [hc_y+ebx*4]
    call .add
.rt:
    cmp byte [vr_ok], 0
    je .join
    mov eax, [vr_x]
    mov edx, [vr_y]
    call .add
.join:
    xor esi, esi
.pair:
    mov eax, ebp
    sub eax, esi
    jz .r
    mov eax, [cpts+esi*8]
    mov ebx, [cpts+esi*8+4]
    add eax, PX
    add ebx, PY
    cmp ebp, 1
    je .dot
    cmp ebp, 3
    je .dot
    mov ecx, [cpts+esi*8+8]
    mov edx, [cpts+esi*8+12]
    add ecx, PX
    add edx, PY
    call gui_line
    add esi, 2
    jmp .pair
.dot:
    mov cl, [gui_ink]
    call gui_pset
    inc esi
    jmp .pair
.r:
    popad
    ret
.add:
    mov [cpts+ebp*8], eax
    mov [cpts+ebp*8+4], edx
    inc ebp
    ret

; ebx = column -> CF if the inequality holds at fcur[ebx]
holds:
    push eax
    fld qword [fcur+ebx*8]
    ftst
    fnstsw ax
    fstp st0
    sahf                        ; ZF: F = 0, CF: F < 0
    mov ah, [edi+S_REL]
    je .zero
    jb .neg
    test ah, 1                  ; F > 0
    jnz .yes
    jmp .no
.neg:
    test ah, 1
    jz .yes
    jmp .no
.zero:
    test ah, 2
    jnz .yes
.no:
    pop eax
    clc
    ret
.yes:
    pop eax
    stc
    ret

; esi, edx = two values of F -> CF unless one is > 0 and the other not;
; then ft = where the line between them crosses 0 (0 to 1) and fmax the
; larger size of the two.
cross:
    push eax
    push ecx
    fld qword [esi]
    ftst
    fnstsw ax
    sahf
    seta cl
    fabs
    fld qword [edx]
    ftst
    fnstsw ax
    sahf
    seta ch
    fabs
    fcomi st0, st1
    jae .big
    fxch
.big:
    fstp qword [fmax]
    fstp st0
    cmp cl, ch
    je .no
    fld qword [esi]
    fld st0
    fsub qword [edx]
    fdivp st1, st0
    fstp qword [ft]
    pop ecx
    pop eax
    clc
    ret
.no:
    pop ecx
    pop eax
    stc
    ret

; The zero on the edge from (fbx, fby), across if fdir = 0, down if 1,
; at ft of GSTEP pixels -> eax, ecx = its pixel in the plot area, or CF if
; F there is not small. Keeps eyin and ex as they were.
edge_point:
    push ebx
    push edx
    push esi
    push edi
    fld qword [ex]
    fstp qword [fsx]
    fld qword [eyin]
    fstp qword [fsy]
    fild dword [fbx]            ; the point in pixels, as fractions
    fstp qword [fqx]
    fild dword [fby]
    fstp qword [fqy]
    mov dword [tmp], GSTEP
    fild dword [tmp]
    fmul qword [ft]
    cmp byte [fdir], 0
    jne .down
    fadd qword [fqx]
    fstp qword [fqx]
    jmp .graph
.down:
    fadd qword [fqy]
    fstp qword [fqy]
.graph:                         ; and in graph units
    fld qword [xmax]
    fsub qword [xmin]
    fmul qword [fqx]
    mov dword [tmp], PW - 1
    fidiv dword [tmp]
    fadd qword [xmin]
    fstp qword [ex]
    fld qword [ymax]
    fsub qword [ymin]
    fmul qword [fqy]
    mov dword [tmp], PH - 1
    fidiv dword [tmp]
    fsubr qword [ymax]
    fstp qword [eyin]
    mov edi, [fslot]
    lea esi, [edi+S_E1]
    call eval_xy
    jc .no
    fld qword [ey]              ; |F| there must be under half of fmax
    fabs
    fadd st0, st0
    fld qword [fmax]
    fcomip st0, st1
    fstp st0
    jb .no
    fld qword [fqx]
    fistp dword [tmp]
    mov eax, [tmp]
    fld qword [fqy]
    fistp dword [tmp]
    mov ecx, [tmp]
    clc
    jmp .r
.no:
    stc
.r:
    pushf
    fld qword [fsx]
    fstp qword [ex]
    fld qword [fsy]
    fstp qword [eyin]
    popf
    pop edi
    pop esi
    pop edx
    pop ebx
    ret

; ---------- sliders ----------
; bl = scancode, al = character, while a slider is chosen.
slide_key:
    movzx edx, byte [sel]
    mov ecx, [slider+edx*4]
    cmp bl, K_ESC
    je .end
    cmp bl, K_ENTER
    je .end
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    cmp bl, K_DOWN
    je .d
    or al, 0x20
    cmp al, 'a'
    jb .x
    cmp al, 'a' + SLIDERS - 1
    ja .x
    sub al, 'a'
    mov [sel], al
.x:
    ret
.end:
    mov byte [sliding], 0
    ret
.l:
    sub ecx, 10
    jmp .set
.r:
    add ecx, 10
    jmp .set
.u:
    add ecx, 100
    jmp .set
.d:
    sub ecx, 100
.set:
    mov eax, ecx
; eax = the chosen slider's new value (hundredths), clamped to +-10
slide_set:
    cmp eax, -1000
    jge .lo
    mov eax, -1000
.lo:
    cmp eax, 1000
    jle .hi
    mov eax, 1000
.hi:
    movzx edx, byte [sel]
    mov [slider+edx*4], eax
    jmp reparse_all

; A click or drag at gui_mx, gui_my: on the status row it sets the
; chosen slider from the bar (CF clear); elsewhere CF.
slide_mouse:
    mov eax, [gui_my]
    cmp eax, ROW2_Y
    jb .no
    cmp eax, ROW2_Y + CELL_H
    jae .no
    mov eax, [gui_mx]
    sub eax, SB_X
    jns .p
    xor eax, eax
.p:
    cmp eax, SB_W
    jbe .in
    mov eax, SB_W
.in:
    imul eax, 10
    sub eax, 1000
    call slide_set
    clc
    ret
.no:
    stc
    ret

; ---------- trace ----------
trace_key:
    cmp bl, K_ESC
    je .end
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    cmp bl, K_DOWN
    je .u
    ret
.end:
    mov byte [tracing], 0
    ret
.l:
    dec dword [tpos]
    jns .ok
    mov dword [tpos], 0
    ret
.r:
    call cur_slot
    call last_point
    inc dword [tpos]
    cmp [tpos], ecx
    jbe .ok
    mov [tpos], ecx
.ok:
    ret
.u:                             ; the next function that is set
    mov ecx, SLOTS
.s:
    mov eax, [cur]
    inc eax
    and eax, SLOTS - 1
    mov [cur], eax
    call cur_slot
    cmp byte [edi+S_KIND], 0
    je .sn
    cmp byte [edi+S_KIND], K_IMPL
    jb .got
.sn:
    loop .s
.got:
    call last_point
    cmp [tpos], ecx
    jbe .ok
    mov [tpos], ecx
    ret

; The trace point: a black cross, and its coordinates on the status row.
trace_mark:
    pushad
    call cur_slot
    mov edx, [tpos]
    call point
    jc .undef
    fld qword [vx]
    fstp qword [tx]
    fld qword [vy]
    fstp qword [ty]
    call to_pixel
    add eax, PX
    add ebx, PY
    mov byte [gui_ink], C_BLACK
    push eax
    push ebx
    lea ecx, [eax+3]
    sub eax, 3
    mov edx, ebx
    call gui_line
    pop ebx
    pop eax
    mov ecx, eax
    lea edx, [ebx+3]
    sub ebx, 3
    call gui_line
    mov edi, status             ; "x = ...  y = ..." (t = ... first)
    call cur_slot
    cmp byte [edi+S_KIND], K_EXPL
    mov edi, status
    je .xy
    mov esi, s_t
    call scopy
    fld qword [tval]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
    mov ax, '  '
    stosw
.xy:
    mov esi, s_xeq
    call scopy
    fld qword [tx]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
    mov esi, s_yeq
    call scopy
    fld qword [ty]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
    popad
    ret
.undef:
    mov esi, m_undef
    mov edi, status
    call scopy0
    popad
    ret

; ---------- roots, extrema, intersections ----------
; Each scans the columns of the plot area for a sign change of a function
; h (f, its slope, or f - g), then halves the bracket 60 times. Results
; go to found (x, y pairs) and are listed on the status row.

; h(x) for find_* -> ey, CF if undefined. hx = x.
hfun:
    cmp byte [hmode], 1
    je .slope
    cmp byte [hmode], 2
    je .diff
    fld qword [hx]
    fstp qword [ex]
    mov esi, [hf]
    jmp eval
.slope:                         ; f(x + d) - f(x - d)
    fld qword [hx]
    fadd qword [hd]
    fstp qword [ex]
    mov esi, [hf]
    call eval
    jc .r
    fld qword [ey]
    fstp qword [hy]
    fld qword [hx]
    fsub qword [hd]
    fstp qword [ex]
    call eval
    jc .r
    fld qword [hy]
    fsub qword [ey]
    fstp qword [ey]
    clc
.r:
    ret
.diff:                          ; f(x) - g(x)
    fld qword [hx]
    fstp qword [ex]
    mov esi, [hf]
    call eval
    jc .r
    fld qword [ey]
    fstp qword [hy]
    mov esi, [hg]
    call eval
    jc .r
    fld qword [hy]
    fsub qword [ey]
    fstp qword [ey]
    clc
    ret

; esi -> CF unless the current slot is explicit; hf = its f
need_explicit:
    call cur_slot
    cmp byte [edi+S_KIND], K_EXPL
    jne .no
    lea eax, [edi+S_E1]
    mov [hf], eax
    clc
    ret
.no:
    mov esi, m_explicit
    mov edi, status
    call scopy0
    stc
    ret

find_roots:
    call need_explicit
    jc .r
    mov byte [hmode], 0
    mov esi, s_roots
    call scan
.r:
    ret

find_extrema:
    call need_explicit
    jc .r
    mov byte [hmode], 1
    ; d = a hundredth of a column
    fld qword [xmax]
    fsub qword [xmin]
    mov dword [tmp], PW * 100
    fidiv dword [tmp]
    fstp qword [hd]
    mov esi, s_ext
    call scan
.r:
    ret

find_inter:
    call need_explicit
    jc .r
    mov ecx, SLOTS - 1          ; the next explicit slot
    mov eax, [cur]
.s:
    inc eax
    and eax, SLOTS - 1
    mov edi, eax
    imul edi, S_SIZE
    add edi, slots
    cmp byte [edi+S_KIND], K_EXPL
    je .got
    loop .s
    mov esi, m_two
    mov edi, status
    call scopy0
.r:
    ret
.got:
    lea eax, [edi+S_E1]
    mov [hg], eax
    mov byte [hmode], 2
    mov esi, s_inter
    jmp scan

; esi = the status label. Brackets sign changes of h over the plot
; columns, refines them, and keeps those where h is near 0 (not a jump).
scan:
    pushad
    mov edi, status
    call scopy
    mov [stat_end], edi
    mov dword [nfound], 0
    mov byte [havep], 0
    xor ebp, ebp
.col:
    mov eax, ebp
    call px_to_x
    fld qword [vx]
    fstp qword [hx]
    call hfun
    jc .gap
    fld qword [ey]
    ftst
    fnstsw ax
    sahf
    fstp qword [hb]             ; h at this column
    fld qword [hx]
    fstp qword [xb]
    cmp byte [havep], 0
    je .keep
    ; a sign change (or an exact zero) since the previous column?
    fld qword [ha]
    fmul qword [hb]
    ftst
    fnstsw ax
    fstp st0
    sahf
    ja .keep
    call refine
.keep:
    fld qword [hb]
    fstp qword [ha]
    fld qword [xb]
    fstp qword [xa]
    mov byte [havep], 1
    jmp .n
.gap:
    mov byte [havep], 0
.n:
    inc ebp
    cmp ebp, PW
    jb .col
    cmp dword [nfound], 0
    jne .r
    mov esi, m_none
    mov edi, [stat_end]
    call scopy0
.r:
    popad
    ret

; xa, ha .. xb, hb bracket a sign change: bisection, then the point is
; kept if h there is small (a real zero, not a pole) and not already kept.
refine:
    pushad
    fld qword [xa]
    fstp qword [lo]
    fld qword [xb]
    fstp qword [hi]
    fld qword [ha]
    fstp qword [hlo]
    mov ecx, 60
.b:
    fld qword [lo]
    fadd qword [hi]
    fmul dword [f_half]
    fst qword [hx]
    fstp qword [mid]
    push ecx
    call hfun
    pop ecx
    jc .r
    fld qword [ey]
    fmul qword [hlo]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jbe .left                   ; the sign changes in [lo, mid]
    fld qword [mid]
    fstp qword [lo]
    fld qword [ey]
    fstp qword [hlo]
    jmp .nb
.left:
    fld qword [mid]
    fstp qword [hi]
.nb:
    loop .b
    ; at a pole |h| stays large: compare with a column's worth of y
    cmp byte [hmode], 1
    je .slopeok                 ; (the slope's size says nothing here)
    fld qword [ey]
    fabs
    fld qword [ymax]
    fsub qword [ymin]
    mov dword [tmp], PH
    fidiv dword [tmp]
    fcomip st0, st1
    fstp st0
    jb .r
.slopeok:
    mov eax, [nfound]
    cmp eax, FOUND_MAX
    jae .r
    test eax, eax               ; the same point as the last one (an exact
    jz .new                     ; zero seen from two columns): skip it
    mov ebx, eax
    shl ebx, 4
    fld qword [found+ebx-16]
    fsub qword [mid]
    fabs
    fld qword [xmax]
    fsub qword [xmin]
    mov dword [tmp], PW
    fidiv dword [tmp]
    fcomip st0, st1
    fstp st0
    ja .r
.new:
    ; the point: x, and y = f(x)
    fld qword [mid]
    fst qword [ex]
    fstp qword [vx]
    mov esi, [hf]
    call eval
    jc .r
    shl eax, 4
    fld qword [vx]
    fstp qword [found+eax]
    fld qword [ey]
    fstp qword [found+eax+8]
    inc dword [nfound]
    ; on the status row: x for roots, (x, y) otherwise; two spaces
    ; between. Only what fits on the row is listed.
    mov edi, [stat_end]
    lea eax, [edi-status]
    cmp eax, PW / CELL_W
    jae .r
    cmp dword [nfound], 1
    je .first
    mov ax, '  '
    stosw
.first:
    cmp byte [hmode], 0
    je .xonly
    ; extrema: "min" or "max" from the slope's sign before the point
    cmp byte [hmode], 1
    jne .pair
    mov esi, s_min
    fld qword [ha]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jb .mm
    mov esi, s_max
.mm:
    call scopy
.pair:
    mov al, '('
    stosb
    fld qword [vx]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
    mov ax, ', '
    stosw
    fld qword [ey]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
    mov al, ')'
    stosb
    jmp .done
.xonly:
    fld qword [vx]
    fstp qword [val]
    call fmt
    mov esi, fmt_buf
    call scopy
.done:
    mov byte [edi], 0
    mov [stat_end], edi
.r:
    popad
    ret

; ---------- self-check ----------
selftest:
    mov byte [bad], 'p'         ; plot y = x^2 - 1
    mov esi, t_f
    mov edi, edit_buf
    call scopy0
    call commit
    jc .fail
    call draw
    ; the curve at x = 0 is y = -1: its pixel must be the slot colour
    fldz
    fstp qword [vx]
    fld1
    fchs
    fstp qword [vy]
    call to_pixel
    add eax, PX
    add ebx, PY
    call gui_peek
    cmp cl, [colours]
    jne .fail
    mov byte [bad], 'w'         ; and the plot area off it is white
    add eax, 20
    sub ebx, 20
    call gui_peek
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'r'         ; roots: -1 and 1
    call find_roots
    call draw
    cmp dword [nfound], 2
    jne .fail
    mov esi, found
    mov edx, f_m1
    call near_val
    jc .fail
    mov esi, found + 16
    mov edx, f_1
    call near_val
    jc .fail
    mov byte [bad], 'm'         ; the minimum (0, -1)
    call find_extrema
    call draw
    cmp dword [nfound], 1
    jne .fail
    mov esi, found
    mov edx, f_0
    call near_val
    jc .fail
    mov esi, found + 8
    mov edx, f_m1
    call near_val
    jc .fail
    mov byte [bad], 'i'         ; y = x + 1 meets it at x = -1 and x = 2
    mov dword [cur], 1
    mov esi, t_g
    mov edi, edit_buf
    call scopy0
    call commit
    jc .fail
    mov dword [cur], 0
    call find_inter
    call draw
    cmp dword [nfound], 2
    jne .fail
    mov esi, found
    mov edx, f_m1
    call near_val
    jc .fail
    mov esi, found + 16
    mov edx, f_2
    call near_val
    jc .fail
    mov byte [bad], 'c'         ; a polar circle r = 2 passes (2, 0)
    mov dword [cur], 2
    mov esi, t_r
    mov edi, edit_buf
    call scopy0
    call commit
    jc .fail
    call draw
    fld dword [f_2]
    fstp qword [vx]
    fldz
    fstp qword [vy]
    call to_pixel
    add eax, PX
    add ebx, PY
    call gui_peek
    cmp cl, [colours+2]
    jne .fail
    mov byte [bad], 'k'         ; the implicit circle x^2 + y^2 = 25
    mov dword [cur], 3          ; passes (5, 0) and (0, -5)
    mov esi, t_circ
    call .set
    jc .fail
    mov dl, [colours+3]
    mov eax, f_5
    mov ebx, f_0
    call peek_near
    jc .fail
    mov eax, f_0
    mov ebx, f_m5
    call peek_near
    jc .fail
    mov byte [bad], 'q'         ; y < x: (5, -5) shaded, (-5, 5) not
    mov dword [cur], 1
    mov esi, t_ineq
    call .set
    jc .fail
    fld dword [f_5]
    fst qword [vx]
    fchs
    fstp qword [vy]
    call to_pixel
    and eax, -2                 ; the shading is on even pixels
    and ebx, -2
    add eax, PX
    add ebx, PY
    call gui_peek
    cmp cl, [colours+1]
    jne .fail
    fld dword [f_5]
    fst qword [vy]
    fchs
    fstp qword [vx]
    call to_pixel
    and eax, -2
    and ebx, -2
    add eax, PX
    add ebx, PY
    call gui_peek
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 's'         ; y = a*x with the slider a at 2: (2, 4)
    mov esi, t_slide
    call .set
    jc .fail
    mov dword [slider], 200
    call reparse_all
    call draw
    mov dl, [colours+1]
    mov eax, f_2
    mov ebx, f_4
    call peek_near
    jc .fail
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

; esi = a function -> the current slot, drawn (CF if it did not parse)
.set:
    mov edi, edit_buf
    call scopy0
    call commit
    jc .r
    call draw
    clc
.r:
    ret

; eax, ebx = floats x and y, dl = colour -> CF unless a pixel within one
; of that point's is that colour
peek_near:
    pushad
    fld dword [eax]
    fstp qword [vx]
    fld dword [ebx]
    fstp qword [vy]
    call to_pixel
    add eax, PX - 1
    add ebx, PY - 1
    mov esi, 3
.row:
    mov edi, 3
.col:
    call gui_peek
    cmp cl, dl
    je .yes
    inc eax
    dec edi
    jnz .col
    sub eax, 3
    inc ebx
    dec esi
    jnz .row
    popad
    stc
    ret
.yes:
    popad
    clc
    ret

; esi = a double, edx = a float -> CF unless they differ by under 1e-6
near_val:
    fld qword [esi]
    fsub dword [edx]
    fabs
    fld dword [f_eps]
    fcomip st0, st1
    fstp st0
    jbe .no
    clc
    ret
.no:
    stc
    ret

; ---------- data ----------
colours db C_BLUE, C_RED, C_GREEN, C_MAGENTA
f_half dd 0.5
f_two dd 2.0
f_twentieth dd 0.05
f_1e5 dd 0.00001
f_10 dd 10.0
f_m10 dd -10.0
f_lim dd 20000.0
f_eps dd 0.000001
f_0 dd 0.0
f_1 dd 1.0
f_m1 dd -1.0
f_2 dd 2.0
f_4 dd 4.0
f_5 dd 5.0
f_m5 dd -5.0

title db 'Grapher', 0
s_x db 'x', 0
s_empty db '(empty: Enter to type a function)', 0
s_help db 'Enter edit Tab next t z m i +- a b c sliders Esc', 0
s_help_edit db 'y= r= x=,y=  = < >   Enter: plot  Esc: back', 0
s_slide_help db 'Esc', 0
s_error db 'Error: ', 0
s_t db 't=', 0
s_xeq db 'x=', 0
s_yeq db '  y=', 0
s_roots db 'roots: ', 0
s_ext db '', 0
s_min db 'min', 0
s_max db 'max', 0
s_inter db 'meet: ', 0
m_none db 'none in view', 0
m_form db 'Use y = f(x), r = f(t), x = f(t), y = g(t), = < >', 0
m_long db 'Too long with the sliders filled in', 0
m_notrace db 'Trace is for y =, r = and x =, y =', 0
m_undef db 'undefined here', 0
m_explicit db 'only for y = f(x)', 0
m_two db 'needs a second y = f(x)', 0
m_nogfx db 'grapher: no graphics', 10, 0
t_f db 'y = x^2 - 1', 0
t_g db 'y = x + 1', 0
t_r db 'r = 2', 0
t_circ db 'x^2 + y^2 = 25', 0
t_ineq db 'y < x', 0
t_slide db 'y = a*x', 0
pass db 'grapher: PASS', 10, 0
fail db 'grapher: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 8
xmin resq 1
xmax resq 1
ymin resq 1
ymax resq 1
vx resq 1
vy resq 1
ex resq 1
ey resq 1
zf resq 1
val resq 1
tval resq 1
tx resq 1
ty resq 1
gstep resq 1
gpos resq 1
hx resq 1
hy resq 1
hd resq 1
ha resq 1
hb resq 1
eyin resq 1
ft resq 1
fmax resq 1
fsx resq 1
fsy resq 1
fqx resq 1
fqy resq 1
fcur resq NCOL
fprev resq NCOL
xa resq 1
xb resq 1
lo resq 1
hi resq 1
hlo resq 1
mid resq 1
found resq 2 * FOUND_MAX
arg resd 1
tmp resd 1
cur resd 1
tpos resd 1
ax0 resd 1
ay0 resd 1
prevx resd 1
prevy resd 1
lastp resd 1
nfound resd 1
hf resd 1
hg resd 1
stat_end resd 1
elim resd 1
slider resd SLIDERS
fslot resd 1
frow resd 1
fcol resd 1
fpx resd 1
fpy resd 1
fbx resd 1
fby resd 1
vl_x resd 1
vl_y resd 1
vr_x resd 1
vr_y resd 1
cpts resd 8
hp_x resd NCOL
hp_y resd NCOL
hc_x resd NCOL
hc_y resd NCOL
tracing resb 1
sliding resb 1
sel resb 1
uses resb 4
relk resb 1
fdir resb 1
editing resb 1
havep resb 1
kind resb 1
hmode resb 1
alignb 4
ev resb GE_SIZE
ev_text resb 40
fmt_buf resb 40
edit_buf resb TEXT_MAX + 2
line resb 80
status resb 256
slots resb S_SIZE * SLOTS
vcur resb NCOL
vprev resb NCOL
hc_ok resb NCOL
hp_ok resb NCOL
vl_ok resb 1
vr_ok resb 1
SQX_END
