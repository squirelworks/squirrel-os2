; Squirrel-OS/2 — 3D Grapher: surfaces and space curves (C.7, OS2-APPS)
; Original code. run graph3d [function]   |   run graph3d test
;
;   z = f(x, y)  or just f(x, y)             a surface over the square
;                                            -d <= x, y <= d (d = 3 at first)
;   x = f(t), y = g(t), z = h(t)             a curve, t from 0 to 2 pi
;
; A surface is a 20 x 20 mesh of filled quadrilaterals coloured by height
; (blue low to red high), drawn back to front so nearer parts hide the
; ones behind, with dark edges. x and y are scaled to the square, z to its
; range. A curve keeps the same scale on all three axes.
;
;   Left, Right   turn about the z axis (15 degrees)
;   Up, Down      look from higher or lower (10 degrees, 0 to 90)
;   + -           zoom in / out           PgUp PgDn  d twice / half
;   Home          the first view          w  edges only (wireframe)
;   Enter         edit the function (Enter draws it, Esc leaves it)
;   Esc           quit
;
; "run graph3d test" draws z = x^2 + y^2 and a helix, checks the ranges,
; the projection, that the surface and the curve reach the screen and
; that turning moves them, and prints "graph3d: PASS".
; See documentation/apps/graph3d.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

TEXT_MAX    equ 72
PX          equ 2                       ; the plot area
PY          equ 1 + WIN_TITLE_H + 1
PW          equ SCR_W - 4
PH          equ SCR_H - PY - 2 * CELL_H - 5
ROW1_Y      equ PY + PH + 2
ROW2_Y      equ ROW1_Y + CELL_H + 1
CENX          equ PX + PW / 2             ; the centre of the picture
CENY          equ PY + PH / 2 + 6
G           equ 20                      ; quads a side
GP          equ G + 1                   ; points a side
NQ          equ G * G
TSTEPS      equ 240
RAMP        equ 64                      ; DAC entries 64 .. 64 + RAMP_N - 1
RAMP_N      equ 32

F_NONE      equ 0
F_SURF      equ 1
F_CURVE     equ 2

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    call home
    fld dword [f_3]
    fstp qword [dom]
    call gui_open
    jc .nogfx
    call set_ramp
    mov esi, [arg]
    test esi, esi
    jz .edit
    cmp dword [esi], 'test'
    je selftest
    cmp byte [esi], 0
    je .edit
    mov edi, edit_buf
    call scopy
    call commit
    jnc .view
.edit:
    call edit_line
.view:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .key
    test eax, EV_DRAG
    jnz .key
    mov byte [status], 0
    movzx ebx, ah
    cmp bl, K_ESC
    je .quit
    cmp bl, K_ENTER
    je .edit
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    cmp bl, K_DOWN
    je .d
    cmp bl, K_HOME
    je .home
    cmp bl, K_PGUP
    je .dup
    cmp bl, K_PGDN
    je .ddown
    or al, 0x20
    cmp al, '+'
    je .zin
    cmp al, '='
    je .zin
    cmp al, '-'
    je .zout
    cmp al, 'w'
    je .wire
    jmp .key
.l:
    sub dword [az], 15
    jmp .view
.r:
    add dword [az], 15
    jmp .view
.u:
    add dword [el], 10
    cmp dword [el], 90
    jle .view
    mov dword [el], 90
    jmp .view
.d:
    sub dword [el], 10
    jns .view
    mov dword [el], 0
    jmp .view
.home:
    call home
    jmp .view
.zin:
    fld qword [zoom]
    fmul dword [f_1_25]
    fstp qword [zoom]
    jmp .view
.zout:
    fld qword [zoom]
    fdiv dword [f_1_25]
    fstp qword [zoom]
    jmp .view
.dup:
    fld qword [dom]
    fadd st0, st0
    jmp .dom
.ddown:
    fld qword [dom]
    fmul dword [f_half]
.dom:
    fstp qword [dom]
    call compute
    jmp .view
.wire:
    xor byte [wire], 1
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

home:
    mov dword [az], 30
    mov dword [el], 25
    fld1
    fstp qword [zoom]
    ret

; DAC entries RAMP.. : blue (low) through cyan, green and yellow to red
set_ramp:
    pushad
    mov edi, pal
    xor ecx, ecx
.e:
    mov eax, ecx                ; 0..31 in four parts of 8
    shr eax, 3
    mov edx, ecx
    and edx, 7
    imul edx, 63 / 7            ; 0..63 within the part
    cmp eax, 0
    je .p0
    cmp eax, 1
    je .p1
    cmp eax, 2
    je .p2
    mov byte [edi], 63          ; yellow to red
    mov eax, 63
    sub eax, edx
    mov [edi+1], al
    mov byte [edi+2], 0
    jmp .n
.p0:                            ; blue to cyan
    mov byte [edi], 0
    mov [edi+1], dl
    mov byte [edi+2], 63
    jmp .n
.p1:                            ; cyan to green
    mov byte [edi], 0
    mov byte [edi+1], 63
    mov eax, 63
    sub eax, edx
    mov [edi+2], al
    jmp .n
.p2:                            ; green to yellow
    mov [edi], dl
    mov byte [edi+1], 63
    mov byte [edi+2], 0
.n:
    add edi, 3
    inc ecx
    cmp ecx, RAMP_N
    jb .e
    mov eax, SYS_GUI
    mov ebx, GUI_PALETTE
    mov ecx, RAMP | RAMP_N << 16
    mov edx, pal
    int 0x80
    popad
    ret

; ---------- evaluation ----------
; esi = expression, ex = x (and ey_in = y with GEF_XY in [evf]) -> res
eval:
    push eax
    push ebx
    push ecx
    mov [ev+GE_EXPR], esi
    mov eax, [evf]
    mov [ev+GE_FLAGS], eax
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
    fstp qword [res]
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

; The function at every grid point or t step, and its ranges.
compute:
    pushad
    mov byte [have], 0
    cmp byte [kind], F_SURF
    je .surf
    cmp byte [kind], F_CURVE
    je .curve
    jmp .r
.surf:
    mov dword [evf], GEF_XY
    xor ebp, ebp                ; point j * GP + i
    xor edi, edi                ; j
.row:
    mov [tmp], edi              ; y = -d + 2 d j / G
    call grid_coord
    fstp qword [eyin]
    xor esi, esi                ; i
.col:
    mov [tmp], esi
    call grid_coord
    fstp qword [ex]
    push esi
    mov esi, e1
    call eval
    pop esi
    mov byte [zok+ebp], 0
    jc .nx
    call finite
    jc .nx
    mov byte [zok+ebp], 1
    fld qword [res]
    fstp qword [zv+ebp*8]
    call widen
.nx:
    inc ebp
    inc esi
    cmp esi, GP
    jb .col
    inc edi
    cmp edi, GP
    jb .row
    jmp .r
.curve:
    mov dword [evf], GEF_X
    xor ebp, ebp
.t:
    mov [tmp], ebp              ; t = step * 2 pi / TSTEPS
    fild dword [tmp]
    fldpi
    fmulp st1, st0
    fadd st0, st0
    mov dword [tmp], TSTEPS
    fidiv dword [tmp]
    fstp qword [ex]
    mov byte [cok+ebp], 0
    mov esi, e1
    call eval
    jc .tn
    call finite
    jc .tn
    fld qword [res]
    fstp qword [cvx+ebp*8]
    mov esi, e2
    call eval
    jc .tn
    call finite
    jc .tn
    fld qword [res]
    fstp qword [cvy+ebp*8]
    mov esi, e3
    call eval
    jc .tn
    call finite
    jc .tn
    fld qword [res]
    fstp qword [cvz+ebp*8]
    mov byte [cok+ebp], 1
    fld qword [cvx+ebp*8]       ; ranges of all three
    fstp qword [res]
    lea ebx, [rx0]
    call widen_in
    fld qword [cvy+ebp*8]
    fstp qword [res]
    lea ebx, [ry0]
    call widen_in
    fld qword [cvz+ebp*8]
    fstp qword [res]
    call widen
.tn:
    inc ebp
    cmp ebp, TSTEPS
    jbe .t
.r:
    popad
    ret

; [tmp] = grid index -> st0 = -d + 2 d index / G
grid_coord:
    fild dword [tmp]
    fadd st0, st0
    mov dword [tmp], G
    fidiv dword [tmp]
    fld1
    fsubp st1, st0
    fmul qword [dom]
    ret

; res -> CF unless it is a finite number below 1e30 in size
finite:
    fld qword [res]
    fabs
    fld dword [f_big]
    fcomip st0, st1
    fstp st0
    jbe .no                     ; also NaN (unordered)
    clc
    ret
.no:
    stc
    ret

; res into the z range (zlo, zhi); the first value starts it
widen:
    lea ebx, [zlo]
    call widen_in
    mov byte [have], 1
    ret

; res into the range at ebx (lo, hi); before the first z (have = 0) it
; starts the range
widen_in:
    cmp byte [have], 0
    je .first
    fld qword [res]
    fld qword [ebx]
    fcomip st0, st1
    jbe .notlo
    fst qword [ebx]
.notlo:
    fld qword [ebx+8]
    fcomip st0, st1
    jae .nothi
    fst qword [ebx+8]
.nothi:
    fstp st0
    ret
.first:
    fld qword [res]
    fst qword [ebx]
    fstp qword [ebx+8]
    ret

; ---------- projection ----------
; sin and cos of az and el
angles:
    fild dword [az]
    fldpi
    fmulp st1, st0
    fdiv dword [f_180]
    fsincos
    fstp qword [caz]
    fstp qword [saz]
    fild dword [el]
    fldpi
    fmulp st1, st0
    fdiv dword [f_180]
    fsincos
    fstp qword [cel]
    fstp qword [sel]
    fld dword [f_scale]
    fmul qword [zoom]
    fstp qword [scale]
    ret

; qx, qy, qz (about -1 .. 1) -> eax, ebx on the screen, depth (larger
; is farther)
project:
    fld qword [qx]              ; x' = x cos az - y sin az
    fmul qword [caz]
    fld qword [qy]
    fmul qword [saz]
    fsubp st1, st0
    fmul qword [scale]
    call clamp_int
    add eax, CENX
    push eax
    fld qword [qx]              ; y' = x sin az + y cos az
    fmul qword [saz]
    fld qword [qy]
    fmul qword [caz]
    faddp st1, st0              ; st0 = y'
    fld st0
    fmul qword [cel]            ; depth = y' cos el - z sin el
    fld qword [qz]
    fmul qword [sel]
    fsubp st1, st0
    fstp qword [depth]
    fmul qword [sel]            ; up = z cos el + y' sin el
    fld qword [qz]
    fmul qword [cel]
    faddp st1, st0
    fmul qword [scale]
    call clamp_int
    neg eax
    add eax, CENY
    mov ebx, eax
    pop eax
    ret

; st0 -> eax, rounded, within +-20000 (popped)
clamp_int:
    fld dword [f_lim]
    fcomip st0, st1
    ja .hi
    fstp st0
    mov eax, 20000
    ret
.hi:
    fld dword [f_lim]
    fchs
    fcomip st0, st1
    jb .ok
    fstp st0
    mov eax, -20000
    ret
.ok:
    fistp dword [tmp]
    mov eax, [tmp]
    ret

; z (res) -> qz = (z - mid) / half * 0.8 (0 if flat)
z_norm:
    fld qword [zhi]
    fsub qword [zlo]
    fmul dword [f_half]
    ftst
    fnstsw ax
    sahf
    je .flat
    fld qword [res]
    fsub qword [zlo]
    fdiv st0, st1
    fld1
    fsubp st1, st0
    fmul dword [f_zs]
    fstp qword [qz]
    fstp st0
    ret
.flat:
    fstp st0
    fldz
    fstp qword [qz]
    ret

; grid point ebp -> sx, sy (screen) and its depth in pdp
proj_point:
    pushad
    xor edx, edx
    mov eax, ebp
    mov ecx, GP
    div ecx                     ; eax = j, edx = i
    mov [tmp], edx              ; x / d = -1 + 2 i / G
    fild dword [tmp]
    fadd st0, st0
    mov dword [tmp], G
    fidiv dword [tmp]
    fld1
    fsubp st1, st0
    fstp qword [qx]
    mov [tmp], eax
    fild dword [tmp]
    fadd st0, st0
    mov dword [tmp], G
    fidiv dword [tmp]
    fld1
    fsubp st1, st0
    fstp qword [qy]
    fld qword [zv+ebp*8]
    fstp qword [res]
    call z_norm
    call project
    mov [sx+ebp*4], eax
    mov [sy+ebp*4], ebx
    fld qword [depth]
    fstp qword [pdp+ebp*8]
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
    mov eax, PX
    mov ebx, PY
    mov ecx, PW
    mov edx, PH
    mov byte [gui_ink], C_WHITE
    call gui_fill
    call gui_clip
    call angles
    call floor_box
    cmp byte [have], 0
    je .rows
    cmp byte [kind], F_SURF
    jne .curve
    call surface
    jmp .rows
.curve:
    call curve
.rows:
    call gui_noclip
    call row1
    call row2
    call gui_flip
    popad
    ret

; The square under the picture (z = -1) with its x and y labels
floor_box:
    pushad
    mov byte [gui_ink], C_LGREY
    xor ebp, ebp
.c:
    fld qword [corner+ebp*8]
    fstp qword [qx]
    fld qword [corner+ebp*8+32]
    fstp qword [qy]
    fld dword [f_m1]
    fstp qword [qz]
    call project
    mov [bxs+ebp*4], eax
    mov [bys+ebp*4], ebx
    inc ebp
    cmp ebp, 4
    jb .c
    xor ebp, ebp
.e:
    mov eax, ebp
    inc eax
    and eax, 3
    mov ecx, [bxs+eax*4]
    mov edx, [bys+eax*4]
    mov eax, [bxs+ebp*4]
    mov ebx, [bys+ebp*4]
    call gui_line
    inc ebp
    cmp ebp, 4
    jb .e
    mov byte [gui_ink], C_DGREY ; x and y at the ends of the axes
    mov byte [gui_bg], C_WHITE
    fld dword [f_1_15]
    fstp qword [qx]
    fldz
    fstp qword [qy]
    fld dword [f_m1]
    fstp qword [qz]
    call project
    mov esi, s_x
    call .label
    fldz
    fstp qword [qx]
    fld dword [f_1_15]
    fstp qword [qy]
    call project
    mov esi, s_y
    call .label
    popad
    ret
.label:
    sub eax, 2
    sub ebx, 3
    jmp gui_text

; The mesh: quads sorted by depth, farthest first
surface:
    pushad
    xor ebp, ebp
.p:
    cmp byte [zok+ebp], 0
    je .pn
    call proj_point
.pn:
    inc ebp
    cmp ebp, GP * GP
    jb .p
    xor ecx, ecx                ; the quads with all corners defined
    xor ebp, ebp                ; quad j * G + i
.q:
    xor edx, edx
    mov eax, ebp
    mov ebx, G
    div ebx                     ; eax = j, edx = i
    imul eax, GP
    add eax, edx                ; its first corner
    mov [qc+ebp*4], eax
    cmp byte [zok+eax], 0
    je .qn
    cmp byte [zok+eax+1], 0
    je .qn
    cmp byte [zok+eax+GP], 0
    je .qn
    cmp byte [zok+eax+GP+1], 0
    je .qn
    fld qword [pdp+eax*8]      ; depth: the mean of the corners
    fadd qword [pdp+eax*8+8]
    fadd qword [pdp+eax*8+GP*8]
    fadd qword [pdp+eax*8+GP*8+8]
    fstp qword [qdep+ebp*8]
    mov [order+ecx*4], ebp
    inc ecx
.qn:
    inc ebp
    cmp ebp, NQ
    jb .q
    mov [nord], ecx
    mov ecx, 1                  ; insertion sort, deepest first
.i:
    cmp ecx, [nord]
    jae .draw
    mov eax, [order+ecx*4]
    fld qword [qdep+eax*8]
    mov edx, ecx
.j:
    test edx, edx
    jz .put
    mov ebx, [order+edx*4-4]
    fld qword [qdep+ebx*8]
    fcomip st0, st1
    jae .put
    mov [order+edx*4], ebx
    dec edx
    jmp .j
.put:
    fstp st0
    mov [order+edx*4], eax
    inc ecx
    jmp .i
.draw:
    xor ebp, ebp
.d:
    cmp ebp, [nord]
    jae .r
    mov eax, [order+ebp*4]
    call quad
    inc ebp
    jmp .d
.r:
    popad
    ret

; eax = quad: filled in its height colour, then its edges
quad:
    pushad
    mov esi, [qc+eax*4]
    mov [q0], esi
    cmp byte [wire], 0
    jne .edges
    fld qword [zv+esi*8]        ; the colour of the mean height
    fadd qword [zv+esi*8+8]
    fadd qword [zv+esi*8+GP*8]
    fadd qword [zv+esi*8+GP*8+8]
    fmul dword [f_quarter]
    fsub qword [zlo]
    fld qword [zhi]
    fsub qword [zlo]
    ftst
    fnstsw ax
    sahf
    jne .scale
    fstp st0
    fstp st0
    fldz
    jmp .idx
.scale:
    fdivp st1, st0
    mov dword [tmp], RAMP_N - 1
    fimul dword [tmp]
.idx:
    fistp dword [tmp]
    mov eax, [tmp]
    test eax, eax
    jns .lo
    xor eax, eax
.lo:
    cmp eax, RAMP_N - 1
    jbe .hi
    mov eax, RAMP_N - 1
.hi:
    add eax, RAMP
    mov [gui_ink], al
    mov esi, [q0]               ; two triangles: 0 1 GP+1, 0 GP+1 GP
    mov eax, esi
    lea ebx, [esi+1]
    lea ecx, [esi+GP+1]
    call tri
    mov eax, esi
    lea ebx, [esi+GP+1]
    lea ecx, [esi+GP]
    call tri
.edges:
    mov byte [gui_ink], C_DGREY
    cmp byte [wire], 0
    je .e
    mov byte [gui_ink], C_BLUE
.e:
    mov esi, [q0]
    mov eax, esi
    lea ebx, [esi+1]
    call edge
    lea eax, [esi+1]
    lea ebx, [esi+GP+1]
    call edge
    lea eax, [esi+GP+1]
    lea ebx, [esi+GP]
    call edge
    lea eax, [esi+GP]
    mov ebx, esi
    call edge
    popad
    ret

; eax, ebx = grid points: a line between them
edge:
    pushad
    mov ecx, [sx+ebx*4]
    mov edx, [sy+ebx*4]
    mov ebx, [sy+eax*4]
    mov eax, [sx+eax*4]
    call gui_line
    popad
    ret

; eax, ebx, ecx = grid points: the triangle filled in [gui_ink]
tri:
    pushad
    mov edx, [sx+eax*4]         ; corners into t_x / t_y
    mov [t_x], edx
    mov edx, [sy+eax*4]
    mov [t_y], edx
    mov edx, [sx+ebx*4]
    mov [t_x+4], edx
    mov edx, [sy+ebx*4]
    mov [t_y+4], edx
    mov edx, [sx+ecx*4]
    mov [t_x+8], edx
    mov edx, [sy+ecx*4]
    mov [t_y+8], edx
    call fill_tri
    popad
    ret

; t_x, t_y (3 corners) -> the triangle filled scanline by scanline
fill_tri:
    pushad
    mov ecx, 3                  ; sort the corners by y (three passes)
.sort:
    mov eax, [t_y]
    cmp eax, [t_y+4]
    jle .s1
    call .swap01
.s1:
    mov eax, [t_y+4]
    cmp eax, [t_y+8]
    jle .s2
    call .swap12
.s2:
    loop .sort
    mov ebx, [t_y]              ; y from the top corner to the bottom one
    cmp ebx, PY
    jge .y
    mov ebx, PY
.y:
    cmp ebx, [t_y+8]
    jg .r
    cmp ebx, PY + PH
    jge .r
    ; xa on the long edge 0 -> 2
    mov eax, ebx
    sub eax, [t_y]
    mov ecx, [t_x+8]
    sub ecx, [t_x]
    imul ecx
    mov ecx, [t_y+8]
    sub ecx, [t_y]
    jz .flat
    idiv ecx
    add eax, [t_x]
    mov [xa], eax
    ; xb on 0 -> 1 above the middle corner, 1 -> 2 below
    cmp ebx, [t_y+4]
    jge .lower
    mov eax, ebx
    sub eax, [t_y]
    mov ecx, [t_x+4]
    sub ecx, [t_x]
    imul ecx
    mov ecx, [t_y+4]
    sub ecx, [t_y]
    idiv ecx
    add eax, [t_x]
    jmp .xb
.lower:
    mov eax, ebx
    sub eax, [t_y+4]
    mov ecx, [t_x+8]
    sub ecx, [t_x+4]
    imul ecx
    mov ecx, [t_y+8]
    sub ecx, [t_y+4]
    jz .mid
    idiv ecx
    add eax, [t_x+4]
    jmp .xb
.mid:
    mov eax, [t_x+4]
.xb:
    mov ecx, eax                ; fill xa..xb
    mov eax, [xa]
    cmp eax, ecx
    jle .ord
    xchg eax, ecx
.ord:
    sub ecx, eax
    inc ecx
    push ebx
    mov edx, 1
    call gui_fill
    pop ebx
.n:
    inc ebx
    jmp .y
.flat:                          ; all three on one row
    mov eax, [t_x]
    mov ecx, eax
    cmp [t_x+4], eax
    jge .f1
    mov eax, [t_x+4]
.f1:
    cmp [t_x+8], eax
    jge .f2
    mov eax, [t_x+8]
.f2:
    cmp [t_x+4], ecx
    jle .f3
    mov ecx, [t_x+4]
.f3:
    cmp [t_x+8], ecx
    jle .f4
    mov ecx, [t_x+8]
.f4:
    sub ecx, eax
    inc ecx
    mov edx, 1
    call gui_fill
.r:
    popad
    ret
.swap01:
    mov eax, [t_x]
    xchg eax, [t_x+4]
    mov [t_x], eax
    mov eax, [t_y]
    xchg eax, [t_y+4]
    mov [t_y], eax
    ret
.swap12:
    mov eax, [t_x+4]
    xchg eax, [t_x+8]
    mov [t_x+4], eax
    mov eax, [t_y+4]
    xchg eax, [t_y+8]
    mov [t_y+4], eax
    ret

; The curve: one scale for all three axes (the largest range), each
; piece in the colour of its height
curve:
    pushad
    fld qword [rx1]             ; half the largest range
    fsub qword [rx0]
    fld qword [ry1]
    fsub qword [ry0]
    fcomi st0, st1
    jbe .a
    fxch
.a:
    fstp st0
    fld qword [zhi]
    fsub qword [zlo]
    fcomi st0, st1
    jbe .b
    fxch
.b:
    fstp st0
    fmul dword [f_half]
    ftst
    fnstsw ax
    sahf
    jne .c
    fstp st0
    fld1
.c:
    fstp qword [half]
    mov byte [havep], 0
    xor ebp, ebp
.t:
    cmp byte [cok+ebp], 0
    je .gap
    fld qword [rx0]             ; each axis about its middle
    fadd qword [rx1]
    fmul dword [f_half]
    fsubr qword [cvx+ebp*8]
    fdiv qword [half]
    fstp qword [qx]
    fld qword [ry0]
    fadd qword [ry1]
    fmul dword [f_half]
    fsubr qword [cvy+ebp*8]
    fdiv qword [half]
    fstp qword [qy]
    fld qword [zlo]
    fadd qword [zhi]
    fmul dword [f_half]
    fsubr qword [cvz+ebp*8]
    fdiv qword [half]
    fstp qword [qz]
    call project
    mov [cpx+ebp*4], eax
    mov [cpy+ebp*4], ebx
    cmp byte [havep], 0
    je .first
    push eax
    push ebx
    fld qword [qz]              ; colour by height: -1 .. 1
    fld1
    faddp st1, st0
    mov dword [tmp], (RAMP_N - 1) / 2
    fimul dword [tmp]
    fistp dword [tmp]
    mov eax, [tmp]
    test eax, eax
    jns .l0
    xor eax, eax
.l0:
    cmp eax, RAMP_N - 1
    jbe .l1
    mov eax, RAMP_N - 1
.l1:
    add eax, RAMP
    mov [gui_ink], al
    pop ebx
    pop eax
    mov ecx, [prevx]
    mov edx, [prevy]
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
    cmp ebp, TSTEPS
    jbe .t
    popad
    ret

; The function row: the function, or the editor
row1:
    pushad
    mov eax, PX
    mov ebx, ROW1_Y
    mov ecx, PW
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov edi, line
    cmp byte [editing], 0
    je .shown
    mov esi, edit_buf
    call scopy
    mov ax, '_'
    stosw
    jmp .out
.shown:
    mov esi, text
    cmp byte [esi], 0
    jne .t
    mov esi, s_empty
.t:
    call scopy
.out:
    mov esi, line
    mov eax, PX
    mov ebx, ROW1_Y
    mov ecx, PW
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    popad
    ret

; The status row: a message, the help while editing, or the ranges
row2:
    pushad
    mov eax, PX
    mov ebx, ROW2_Y
    mov ecx, PW
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov esi, status
    cmp byte [esi], 0
    jne .out
    mov esi, s_help_edit
    cmp byte [editing], 0
    jne .out
    mov esi, s_help
    cmp byte [have], 0
    je .out
    mov edi, status             ; "x, y: -3 to 3  z: 0 to 18"
    cmp byte [kind], F_SURF
    jne .crv
    mov esi, s_xy
    call scopy
    fld qword [dom]
    fchs
    fstp qword [val]
    call fmt
    mov esi, s_to
    call scopy
    fld qword [dom]
    fstp qword [val]
    call fmt
    jmp .z
.crv:
    mov esi, s_t
    call scopy
.z:
    mov esi, s_z
    call scopy
    fld qword [zlo]
    fstp qword [val]
    call fmt
    mov esi, s_to
    call scopy
    fld qword [zhi]
    fstp qword [val]
    call fmt
    mov esi, status
.out:
    mov eax, PX
    mov ebx, ROW2_Y
    mov ecx, PW
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    mov byte [status], 0
    popad
    ret

; val -> edi: as sci prints it, rounded to 4 decimals; edi ends on the zero
fmt:
    pushad
    fld qword [val]
    fmul dword [f_1e4]
    frndint
    fdiv dword [f_1e4]
    fstp qword [ev+GE_X]
    mov dword [ev+GE_EXPR], s_x
    mov dword [ev+GE_FLAGS], GEF_X
    mov dword [ev+GE_TEXT], fmt_buf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    mov esi, fmt_buf
    call scopy
    mov [esp], edi              ; edi comes back advanced
    popad
    ret

; ---------- editing ----------
edit_line:
    pushad
    mov byte [editing], 1
    mov esi, text
    mov edi, edit_buf
    call scopy
    sub edi, edit_buf
    mov ecx, edi
    call draw
    jmp .k
.d:
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
    test ecx, ecx
    jz .k
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

; edit_buf -> kind, e1 (e2, e3), text, computed. CF and a message in
; status if it does not parse (the last function stays).
commit:
    pushad
    mov esi, edit_buf
    call skip
    cmp byte [esi], 0
    jne .some
    mov byte [kind], F_NONE
    mov byte [text], 0
    mov byte [have], 0
    jmp .ok
.some:
    mov al, [esi]
    or al, 0x20
    lea ebx, [esi+1]
    xchg esi, ebx
    call skip
    xchg esi, ebx
    cmp byte [ebx], '='
    jne .surface                ; no "name =": the whole text is f(x, y)
    inc ebx
    cmp al, 'z'
    je .zrhs
    cmp al, 'x'
    jne .bad
    mov esi, ebx                ; x = f(t), y = g(t), z = h(t)
    mov byte [tsub], 1
    mov edi, n1
    call copy_expr
    mov ah, 'y'
    call next_part
    jc .bad
    mov edi, n2
    call copy_expr
    mov ah, 'z'
    call next_part
    jc .bad
    mov edi, n3
    call copy_expr
    cmp byte [esi], 0
    jne .bad
    mov dword [evf], GEF_X
    fld1
    fstp qword [ex]
    mov esi, n1
    call eval
    jnc .c2
    call syntax_err
    jc .fail
.c2:
    mov esi, n2
    call eval
    jnc .c3
    call syntax_err
    jc .fail
.c3:
    mov esi, n3
    call eval
    jnc .curve
    call syntax_err
    jc .fail
.curve:
    mov byte [nkind], F_CURVE
    jmp .store
.zrhs:
    mov esi, ebx
.surface:
    mov byte [tsub], 0
    mov edi, n1
    call copy_expr
    cmp byte [esi], 0
    jne .bad
    mov dword [evf], GEF_XY
    fld1
    fst qword [ex]
    fstp qword [eyin]
    mov esi, n1
    call eval
    jnc .surf
    call syntax_err
    jc .fail
.surf:
    mov byte [nkind], F_SURF
.store:
    mov al, [nkind]
    mov [kind], al
    mov esi, n1
    mov edi, e1
    call scopy
    mov esi, n2
    mov edi, e2
    call scopy
    mov esi, n3
    mov edi, e3
    call scopy
    mov esi, edit_buf
    mov edi, text
    call scopy
    call compute
.ok:
    popad
    clc
    ret
.bad:
    mov esi, m_form
    mov edi, status
    call scopy
.fail:
    popad
    stc
    ret

; esi at "," -> after "<ah> =", or CF
next_part:
    cmp byte [esi], ','
    jne .no
    inc esi
    call skip
    mov al, [esi]
    or al, 0x20
    cmp al, ah
    jne .no
    inc esi
    call skip
    cmp byte [esi], '='
    jne .no
    inc esi
    clc
    ret
.no:
    stc
    ret

; After eval failed: CF and the message in status if it is a syntax error
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

; esi -> edi: up to a comma or the end; with tsub, a lone t becomes x
copy_expr:
    call skip
    xor edx, edx                ; dl: the last character was a letter
.c:
    mov al, [esi]
    test al, al
    jz .e
    cmp al, ','
    je .e
    mov ah, al
    call is_alpha
    jne .other
    test dl, dl
    jnz .letter
    cmp al, 't'
    jne .letter
    cmp byte [tsub], 0
    je .letter
    mov ah, [esi+1]
    call is_alpha
    je .letter
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
    test esp, esp
    pop eax
    ret

skip:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip
.r:
    ret

; esi -> edi with the zero; edi ends on the zero
scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
    ret

; ---------- self-check ----------
; esi = function: set and drawn -> CF if it did not parse
set_fn:
    mov edi, edit_buf
    call scopy
    call commit
    jc .r
    call draw
    clc
.r:
    ret

; eax, ebx = screen point -> CF if the pixel there and its 8 neighbours
; are all white
not_white:
    pushad
    dec eax
    dec ebx
    mov esi, 3
.row:
    mov edi, 3
.col:
    call gui_peek
    cmp cl, C_WHITE
    jne .yes
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

selftest:
    mov byte [bad], 'p'         ; z = x^2 + y^2 on -3..3: z from 0 to 18
    mov esi, t_bowl
    call set_fn
    jc .fail
    mov byte [bad], 'z'
    cmp byte [have], 1
    jne .fail
    fld qword [zlo]
    ftst
    fnstsw ax
    fstp st0
    sahf
    jne .fail
    fld qword [zhi]
    fcomp dword [f_18]
    fnstsw ax
    sahf
    jne .fail
    mov byte [bad], 'o'         ; looking straight down (el 90, az 0) the
    mov dword [az], 0           ; corner (3, 3) is up and right of centre
    mov dword [el], 90
    call angles
    fld1
    fst qword [qx]
    fstp qword [qy]
    fldz
    fstp qword [qz]
    call project
    cmp eax, CENX
    jle .fail
    cmp ebx, CENY
    jge .fail
    mov byte [bad], 's'         ; the surface reaches the screen: the
    call home                   ; middle of the bowl is coloured
    call draw
    mov ebp, (GP * GP) / 2      ; the centre grid point
    call proj_point
    mov eax, [sx+ebp*4]
    mov ebx, [sy+ebp*4]
    sub ebx, 12                 ; a little above: the far wall
    call not_white
    jc .fail
    mov byte [bad], 'c'         ; a helix: x, y from -1 to 1, z 0 to 2 pi / 5
    mov esi, t_helix
    call set_fn
    jc .fail
    cmp byte [kind], F_CURVE
    jne .fail
    fld qword [zhi]
    fsub qword [zlo]
    fldpi
    fadd st0, st0
    fdiv dword [f_5]
    fsubp st1, st0
    fabs
    fcomp dword [f_eps]
    fnstsw ax
    sahf
    jae .fail
    mov eax, [cpx]              ; its start (t = 0) is drawn
    mov ebx, [cpy]
    call not_white
    jc .fail
    mov byte [bad], 't'         ; turning moves it
    mov eax, [cpx+60*4]
    mov [tmp2], eax
    add dword [az], 90
    call draw
    mov eax, [cpx+60*4]
    sub eax, [tmp2]
    jns .abs
    neg eax
.abs:
    cmp eax, 10
    jb .fail
    mov byte [bad], 'e'         ; a syntax error is reported
    mov esi, t_bad
    mov edi, edit_buf
    call scopy
    call commit
    jnc .fail
    cmp dword [status], 'Erro'
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
f_quarter dd 0.25
f_3 dd 3.0
f_5 dd 5.0
f_18 dd 18.0
f_m1 dd -1.0
f_180 dd 180.0
f_1_25 dd 1.25
f_1_15 dd 1.15
f_1e4 dd 10000.0
f_scale dd 62.0
f_zs dd 0.8
f_lim dd 20000.0
f_big dd 1.0e30
f_eps dd 0.000001
alignb 8
corner dq -1.0, 1.0, 1.0, -1.0          ; x of the floor's corners
       dq -1.0, -1.0, 1.0, 1.0          ; y

title db '3D Grapher', 0
s_x db 'x', 0
s_y db 'y', 0
s_empty db '(empty: Enter to type a function)', 0
s_help db 'Enter edit  arrows turn  + - zoom  PgUp PgDn size  w  Esc', 0
s_help_edit db 'z = f(x,y)  or  x=f(t), y=g(t), z=h(t)   Enter  Esc', 0
s_xy db 'x, y: ', 0
s_t db 't: 0 to 2 pi', 0
s_z db '  z: ', 0
s_to db ' to ', 0
s_error db 'Error: ', 0
m_form db 'Use z = f(x, y) or x = f(t), y = g(t), z = h(t)', 0
m_nogfx db 'graph3d: no graphics', 10, 0
t_bowl db 'z = x^2 + y^2', 0
t_helix db 'x = cos(t), y = sin(t), z = t/5', 0
t_bad db 'z = x*(', 0
pass db 'graph3d: PASS', 10, 0
fail db 'graph3d: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 8
zv resq GP * GP
pdp resq GP * GP
qdep resq NQ
cvx resq TSTEPS + 1
cvy resq TSTEPS + 1
cvz resq TSTEPS + 1
dom resq 1
zoom resq 1
scale resq 1
caz resq 1
saz resq 1
cel resq 1
sel resq 1
qx resq 1
qy resq 1
qz resq 1
depth resq 1
ex resq 1
eyin resq 1
res resq 1
val resq 1
half resq 1
zlo resq 1
zhi resq 1
rx0 resq 1
rx1 resq 1
ry0 resq 1
ry1 resq 1
sx resd GP * GP
sy resd GP * GP
qc resd NQ
order resd NQ
cpx resd TSTEPS + 1
cpy resd TSTEPS + 1
nord resd 1
az resd 1
el resd 1
evf resd 1
arg resd 1
tmp resd 1
tmp2 resd 1
q0 resd 1
xa resd 1
prevx resd 1
prevy resd 1
t_x resd 3
t_y resd 3
bxs resd 4
bys resd 4
zok resb GP * GP
cok resb TSTEPS + 1
kind resb 1
nkind resb 1
have resb 1
havep resb 1
editing resb 1
wire resb 1
tsub resb 1
alignb 4
pal resb 3 * RAMP_N
ev resb GE_SIZE
ev_text resb 40
fmt_buf resb 40
edit_buf resb TEXT_MAX + 2
text resb TEXT_MAX + 2
line resb 96
status resb 96
e1 resb 160
e2 resb 160
e3 resb 160
n1 resb 160
n2 resb 160
n3 resb 160
SQX_END
