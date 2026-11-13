; Squirrel-OS/2 — Geometry: constructions that follow their points
; (C.6, OS2-APPS). Original code. run geometry [file]  |  run geometry test
;
; Free points, and objects built from them: midpoints, intersections,
; segments, lines, perpendiculars, parallels, bisectors, circles, and
; measurements (distances, angles, areas). Moving a free point (a mouse
; drag, or Tab and the arrows) moves everything built on it, and the
; measurements change with it.
;
; Objects are made with commands typed on the status row (any key that
; is not one below starts one; Enter runs it, Esc drops it):
;   (1,2)            a free point          seg A B     a segment
;   line A B         a line                circle A B  centre A, through B
;   circle A 2.5     centre A, radius      mid A B     the midpoint
;   perp l A         the perpendicular to l through A
;   par l A          the parallel to l through A
;   bis A B          the perpendicular bisector of AB
;   abis A B C       the bisector of the angle ABC
;   inter o p        where two lines / circles / segments meet
;   dist A B   angle A B C (at B, degrees)   area A B C   measurements
;   del X            remove X and everything built on it
; "N=" in front names the object (N=(1,2), K=mid A B); otherwise points
; get the next free letter and lines, circles and measurements l1, c1,
; m1, ... Numbers may be any sci expression (sqrt(2), 3/4, pi).
;
;   left click on empty canvas: a new point; on a free point: select it,
;   a drag moves it.  Tab: select the next free point; arrows move it by
;   0.25.  +/-: zoom, Home: the first view.  Backspace: remove the last
;   object; Delete: the selected point (and what is built on it).
;   Ctrl+S: save (the commands, as a text file)   Esc: quit
;
; "run geometry test" builds a figure, checks every kind of object and
; measurement, moves a point, removes one, and saves and loads; it
; prints "geometry: PASS". See documentation/apps/geometry.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

MAXOBJ      equ 64
OSIZE       equ 64
NAME_MAX    equ 60
CMAX        equ 60                      ; a command
FBUF        equ 8192

O_TYPE      equ 0                       ; an object
O_DEF       equ 1                       ; 1: defined (it exists)
O_A         equ 2                       ; parents
O_B         equ 3
O_C         equ 4
O_W         equ 5                       ; which intersection (0, 1)
O_NAME      equ 8                       ; up to 7 characters
O_X         equ 16                      ; point / a line's point / centre
O_Y         equ 24
O_DX        equ 32                      ; a line's direction / radius
O_DY        equ 40
O_VAL       equ 48                      ; a measurement / a given radius

T_PT        equ 1                       ; points
T_MID       equ 2
T_INT       equ 3
T_SEG       equ 4                       ; lines (O_X, O_Y, O_DX, O_DY)
T_LINE      equ 5
T_PERP      equ 6
T_PAR       equ 7
T_BIS       equ 8
T_ABIS      equ 9
T_CIRC      equ 10                      ; circles (centre, O_DX radius)
T_CIRCR     equ 11
T_DIST      equ 12                      ; measurements (O_VAL)
T_ANG       equ 13
T_AREA      equ 14

CV_X        equ 3                       ; the canvas
CV_Y        equ WIN_TITLE_H + 2
CV_W        equ 194
STAT_Y      equ SCR_H - CELL_H - 2
CV_H        equ STAT_Y - CV_Y - 2
CEN_X       equ CV_X + CV_W / 2
CEN_Y       equ CV_Y + CV_H / 2
PN_X        equ CV_X + CV_W + 3         ; the list of objects
PN_W        equ SCR_W - 3 - PN_X
PN_ROWS     equ CV_H / CELL_H
NEARPX        equ 5                       ; pixels: a click on a point

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    call reset_view
    mov dword [sel], -1
    mov esi, s_default
    mov edi, fname
    call scopy
    mov eax, SYS_SBRK
    mov ebx, FBUF
    int 0x80
    cmp eax, -1
    je .nogfx
    mov [fbuf], eax
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
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .drag
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.click:
    mov byte [typing], 0
    call mouse_world
    jc .key
    call point_near
    jnc .pick
    mov esi, s_none             ; a new point where it was clicked
    call new_obj
    jc .draw
    mov byte [edi+O_TYPE], T_PT
    fld qword [wx]
    fstp qword [edi+O_X]
    fld qword [wy]
    fstp qword [edi+O_Y]
    call auto_name
    call update
    mov [sel], eax
    jmp .draw
.pick:
    mov [sel], eax
    jmp .draw
.drag:
    mov eax, [sel]
    cmp eax, -1
    je .key
    call mouse_world
    jc .key
    call obj_ptr
    fld qword [wx]
    fstp qword [edi+O_X]
    fld qword [wy]
    fstp qword [edi+O_Y]
    call update
    jmp .draw
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
    cmp byte [typing], 0
    jne .typed
    test eax, 1 << 16
    jnz .ctrl
    cmp bl, K_ESC
    je .quit
    cmp bl, K_TAB
    je .tab
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_HOME
    je .home
    cmp bl, K_BKSP
    je .undo
    cmp bl, K_DEL
    je .del
    cmp bl, K_ENTER
    je .start
    cmp al, '+'
    je .zin
    cmp al, '-'
    je .zout
    cmp al, ' '
    jbe .ok
    cmp al, '~'
    ja .ok
    mov [cbuf], al              ; a command starts
    mov byte [cbuf+1], 0
    mov dword [clen], 1
    mov byte [typing], 1
    jmp .ok
.start:
    mov byte [cbuf], 0
    mov dword [clen], 0
    mov byte [typing], 1
    jmp .ok
.ctrl:
    and al, 0xDF
    cmp al, 'S'
    jne .ok
    call save
    jmp .ok
.quit:
    popad
    stc
    ret
.tab:                           ; the next free point
    mov eax, [sel]
    mov ecx, [nobj]
    test ecx, ecx
    jz .ok
.t:
    inc eax
    cmp eax, [nobj]
    jb .t1
    xor eax, eax
.t1:
    call obj_ptr
    cmp byte [edi+O_TYPE], T_PT
    je .tsel
    loop .t
    jmp .ok
.tsel:
    mov [sel], eax
    jmp .ok
.up:
    mov esi, f_q
    mov edi, O_Y
    jmp .move
.down:
    mov esi, f_mq
    mov edi, O_Y
    jmp .move
.left:
    mov esi, f_mq
    mov edi, O_X
    jmp .move
.right:
    mov esi, f_q
    mov edi, O_X
.move:
    mov eax, [sel]
    cmp eax, -1
    je .ok
    push edi
    call obj_ptr
    pop ecx
    fld qword [edi+ecx]
    fadd qword [esi]
    fstp qword [edi+ecx]
    call update
    jmp .ok
.home:
    call reset_view
    jmp .ok
.zin:
    fld qword [scale]
    fmul qword [f_zoom]
    fstp qword [scale]
    jmp .ok
.zout:
    fld qword [scale]
    fdiv qword [f_zoom]
    fstp qword [scale]
    jmp .ok
.undo:
    mov eax, [nobj]
    test eax, eax
    jz .ok
    dec eax
    call remove
    jmp .ok
.del:
    mov eax, [sel]
    cmp eax, -1
    je .ok
    call remove
    jmp .ok
.typed:                         ; the command line
    mov ecx, [clen]
    cmp bl, K_ESC
    je .drop
    cmp bl, K_ENTER
    je .run
    cmp bl, K_BKSP
    je .bs
    test eax, 1 << 16
    jnz .ok
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    cmp ecx, CMAX
    jae .ok
    mov [cbuf+ecx], al
    inc ecx
    mov byte [cbuf+ecx], 0
    mov [clen], ecx
    jmp .ok
.bs:
    test ecx, ecx
    jz .drop
    dec ecx
    mov byte [cbuf+ecx], 0
    mov [clen], ecx
    jmp .ok
.drop:
    mov byte [typing], 0
    jmp .ok
.run:
    mov byte [typing], 0
    mov esi, cbuf
    call command
.ok:
    popad
    clc
    ret

reset_view:
    fld qword [f_scale]
    fstp qword [scale]
    fldz
    fst qword [vx]
    fstp qword [vy]
    ret

; ---------- objects ----------
; eax = object -> edi = it
obj_ptr:
    mov edi, eax
    shl edi, 6
    add edi, objs
    ret

; esi = name ("" for the next free one of the kind set later) -> eax =
; a new object at the end, edi = it (zeroed, its name copied); CF if full
new_obj:
    mov eax, [nobj]
    cmp eax, MAXOBJ
    jae .full
    call obj_ptr
    push edi
    push eax
    xor eax, eax
    mov ecx, OSIZE / 4
    rep stosd
    pop eax
    pop edi
    push esi
    push edi
    add edi, O_NAME
    mov ecx, 7
.n:
    lodsb
    test al, al
    jz .e
    stosb
    loop .n
.e:
    pop edi
    pop esi
    mov eax, [nobj]
    inc dword [nobj]
    mov byte [dirty], 1
    clc
    ret
.full:
    mov dword [msg], m_full
    stc
    ret

; esi = name -> eax = the object with it, or CF
find:
    push ecx
    push edi
    xor eax, eax
.f:
    cmp eax, [nobj]
    jae .no
    call obj_ptr
    add edi, O_NAME
    push esi
.c:
    mov cl, [esi]
    cmp cl, [edi]
    jne .ne
    inc esi
    inc edi
    test cl, cl
    jnz .c
    pop esi
    pop edi
    pop ecx
    clc
    ret
.ne:
    pop esi
    inc eax
    jmp .f
.no:
    pop edi
    pop ecx
    stc
    ret

; edi = object without a name -> the next free one for its kind: a
; letter for points, l1 c1 m1 ... for the rest
auto_name:
    pushad
    cmp byte [edi+O_NAME], 0
    jne .r
    mov ebp, edi
    movzx eax, byte [edi+O_TYPE]
    call kind
    test ecx, ecx
    jnz .other
    mov byte [nbuf2+1], 0
    mov al, 'A'
.l:
    mov [nbuf2], al
    mov esi, nbuf2
    push eax
    call find
    pop eax
    jc .got
    inc al
    cmp al, 'Z'
    jbe .l
    mov cl, 'P'                 ; then P1, P2, ...
    jmp .num
.other:
    mov cl, [kind_letter+ecx]
    cmp byte [ebp+O_TYPE], T_SEG
    jne .num
    mov cl, 's'
.num:
    mov [nbuf2], cl
    mov ebx, 1
.n:
    lea edi, [nbuf2+1]
    mov eax, ebx
    call gui_utoa
    mov esi, nbuf2
    call find
    jc .got
    inc ebx
    jmp .n
.got:
    mov esi, nbuf2
    lea edi, [ebp+O_NAME]
    call scopy
.r:
    popad
    ret

; eax = type -> ecx = its kind: 0 point, 1 line, 2 circle, 3 measurement
kind:
    xor ecx, ecx
    cmp eax, T_SEG
    jb .r
    inc ecx
    cmp eax, T_CIRC
    jb .r
    inc ecx
    cmp eax, T_DIST
    jb .r
    inc ecx
.r:
    ret

; eax = object: it and everything built on it removed
remove:
    pushad
    mov edi, gone
    mov ecx, MAXOBJ
    push eax
    xor eax, eax
    rep stosb
    pop eax
    mov byte [gone+eax], 1
    mov ebx, eax
.m:                             ; later objects with a removed parent
    inc ebx
    cmp ebx, [nobj]
    jae .pack
    mov eax, ebx
    call obj_ptr
    movzx eax, byte [edi+O_TYPE]
    call nparents
    xor edx, edx
.p:
    cmp edx, ecx
    jae .m
    movzx eax, byte [edi+O_A+edx]
    cmp byte [gone+eax], 0
    jne .g
    inc edx
    jmp .p
.g:
    mov byte [gone+ebx], 1
    jmp .m
.pack:                          ; new places, then the objects moved down
    xor eax, eax
    xor ebx, ebx
.np:
    cmp eax, [nobj]
    jae .move
    mov [newi+eax], bl
    cmp byte [gone+eax], 0
    jne .np1
    inc ebx
.np1:
    inc eax
    jmp .np
.move:
    xor eax, eax
.mv:
    cmp eax, [nobj]
    jae .done
    cmp byte [gone+eax], 0
    jne .mv1
    call obj_ptr
    mov esi, edi
    movzx edx, byte [newi+eax]
    push eax
    mov eax, edx
    call obj_ptr
    pop eax
    push eax
    movzx eax, byte [esi+O_TYPE]
    call nparents
    pop eax
    mov ebx, ecx
    mov ecx, OSIZE / 4
    push edi
    rep movsd
    pop edi
    xor edx, edx                ; its parents' new places
.pp:
    cmp edx, ebx
    jae .mv1
    movzx ecx, byte [edi+O_A+edx]
    mov cl, [newi+ecx]
    mov [edi+O_A+edx], cl
    inc edx
    jmp .pp
.mv1:
    inc eax
    jmp .mv
.done:
    mov eax, [nobj]             ; how many are left
    movzx eax, byte [newi+eax-1]
    mov ecx, [nobj]
    cmp byte [gone+ecx-1], 0
    jne .d1
    inc eax
.d1:
    mov [nobj], eax
    mov eax, [sel]              ; the selection
    cmp eax, -1
    je .u
    cmp byte [gone+eax], 0
    jne .unsel
    movzx eax, byte [newi+eax]
    mov [sel], eax
    jmp .u
.unsel:
    mov dword [sel], -1
.u:
    mov byte [dirty], 1
    call update
    popad
    ret

; eax = type -> ecx = how many parents
nparents:
    movzx ecx, byte [npar+eax]
    ret

; ---------- working out ----------
; Every object from its parents, in order
update:
    pushad
    xor eax, eax
.o:
    cmp eax, [nobj]
    jae .r
    call obj_ptr
    call compute
    inc eax
    jmp .o
.r:
    popad
    ret

; esi = object -> its point to px, py (from O_X, O_Y)
pt_load:
    fld qword [esi+O_X]
    fstp qword [px]
    fld qword [esi+O_Y]
    fstp qword [py]
    ret

; edi = object: worked out from its parents (all defined, or it is not)
compute:
    pushad
    mov byte [edi+O_DEF], 0
    movzx eax, byte [edi+O_TYPE]
    call nparents
    xor edx, edx
.p:
    cmp edx, ecx
    jae .all
    movzx eax, byte [edi+O_A+edx]
    push edi
    call obj_ptr
    mov [par+edx*4], edi
    mov bl, [edi+O_DEF]
    pop edi
    test bl, bl
    jz .r
    inc edx
    jmp .p
.all:
    mov ebx, [par]
    mov ecx, [par+4]
    mov edx, [par+8]
    movzx eax, byte [edi+O_TYPE]
    jmp [compute_tab+eax*4]
.pt:
    jmp .yes
.mid:
    fld qword [ebx+O_X]
    fadd qword [ecx+O_X]
    fmul qword [f_half]
    fstp qword [edi+O_X]
    fld qword [ebx+O_Y]
    fadd qword [ecx+O_Y]
    fmul qword [f_half]
    fstp qword [edi+O_Y]
    jmp .yes
.seg:                           ; through A, along B - A
    fld qword [ebx+O_X]
    fst qword [edi+O_X]
    fsubr qword [ecx+O_X]
    fstp qword [edi+O_DX]
    fld qword [ebx+O_Y]
    fst qword [edi+O_Y]
    fsubr qword [ecx+O_Y]
    fstp qword [edi+O_DY]
    jmp .dir
.perp:                          ; through B, across line A
    fld qword [ebx+O_DY]
    fchs
    fstp qword [edi+O_DX]
    fld qword [ebx+O_DX]
    fstp qword [edi+O_DY]
    jmp .through
.par:
    fld qword [ebx+O_DX]
    fstp qword [edi+O_DX]
    fld qword [ebx+O_DY]
    fstp qword [edi+O_DY]
.through:
    fld qword [ecx+O_X]
    fstp qword [edi+O_X]
    fld qword [ecx+O_Y]
    fstp qword [edi+O_Y]
    jmp .dir
.bis:                           ; through the midpoint, across AB
    fld qword [ebx+O_X]
    fadd qword [ecx+O_X]
    fmul qword [f_half]
    fstp qword [edi+O_X]
    fld qword [ebx+O_Y]
    fadd qword [ecx+O_Y]
    fmul qword [f_half]
    fstp qword [edi+O_Y]
    fld qword [ebx+O_Y]
    fsub qword [ecx+O_Y]
    fstp qword [edi+O_DX]
    fld qword [ecx+O_X]
    fsub qword [ebx+O_X]
    fstp qword [edi+O_DY]
    jmp .dir
.abis:                          ; through B, along unit(A-B) + unit(C-B)
    mov esi, ebx
    mov ebx, ecx                ; ebx = B (the corner)
    call unit_from              ; esi - ebx -> ux, uy
    jc .r
    fld qword [ux]
    fstp qword [edi+O_DX]
    fld qword [uy]
    fstp qword [edi+O_DY]
    mov esi, edx
    call unit_from
    jc .r
    fld qword [ux]
    fadd qword [edi+O_DX]
    fstp qword [edi+O_DX]
    fld qword [uy]
    fadd qword [edi+O_DY]
    fstp qword [edi+O_DY]
    fld qword [ebx+O_X]
    fstp qword [edi+O_X]
    fld qword [ebx+O_Y]
    fstp qword [edi+O_Y]
    fld qword [edi+O_DX]        ; a straight angle: across the sides
    fabs
    fld qword [edi+O_DY]
    fabs
    faddp st1, st0
    fld qword [f_eps]
    fcomip st0, st1
    fstp st0
    jb .yes
    fld qword [uy]
    fchs
    fstp qword [edi+O_DX]
    fld qword [ux]
    fstp qword [edi+O_DY]
    jmp .yes
.dir:                           ; a line needs a direction
    fld qword [edi+O_DX]
    fabs
    fld qword [edi+O_DY]
    fabs
    faddp st1, st0
    fldz
    fcomip st0, st1
    fstp st0
    je .r
    jmp .yes
.circ:
    fld qword [ebx+O_X]
    fst qword [edi+O_X]
    fsubr qword [ecx+O_X]
    fmul st0, st0
    fld qword [ebx+O_Y]
    fst qword [edi+O_Y]
    fsubr qword [ecx+O_Y]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    fstp qword [edi+O_DX]
    jmp .yes
.circr:
    fld qword [ebx+O_X]
    fstp qword [edi+O_X]
    fld qword [ebx+O_Y]
    fstp qword [edi+O_Y]
    fld qword [edi+O_VAL]
    fstp qword [edi+O_DX]
    jmp .yes
.dist:
    fld qword [ecx+O_X]
    fsub qword [ebx+O_X]
    fmul st0, st0
    fld qword [ecx+O_Y]
    fsub qword [ebx+O_Y]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    fstp qword [edi+O_VAL]
    jmp .yes
.ang:                           ; at B: atan2(|u x v|, u . v), degrees
    fld qword [ebx+O_X]
    fsub qword [ecx+O_X]
    fstp qword [ux]
    fld qword [ebx+O_Y]
    fsub qword [ecx+O_Y]
    fstp qword [uy]
    fld qword [edx+O_X]
    fsub qword [ecx+O_X]
    fstp qword [vx_]
    fld qword [edx+O_Y]
    fsub qword [ecx+O_Y]
    fstp qword [vy_]
    fld qword [ux]
    fmul qword [vy_]
    fld qword [uy]
    fmul qword [vx_]
    fsubp st1, st0
    fabs
    fld qword [ux]
    fmul qword [vx_]
    fld qword [uy]
    fmul qword [vy_]
    faddp st1, st0
    fpatan
    fmul qword [f_deg]
    fstp qword [edi+O_VAL]
    jmp .yes
.area:                          ; |(B-A) x (C-A)| / 2
    fld qword [ecx+O_X]
    fsub qword [ebx+O_X]
    fld qword [edx+O_Y]
    fsub qword [ebx+O_Y]
    fmulp st1, st0
    fld qword [ecx+O_Y]
    fsub qword [ebx+O_Y]
    fld qword [edx+O_X]
    fsub qword [ebx+O_X]
    fmulp st1, st0
    fsubp st1, st0
    fabs
    fmul qword [f_half]
    fstp qword [edi+O_VAL]
    jmp .yes
.int:
    call intersect
    jc .r
.yes:
    mov byte [edi+O_DEF], 1
.r:
    popad
    ret

; esi, ebx = points -> ux, uy = (esi - ebx) / its length; CF if 0
unit_from:
    fld qword [esi+O_X]
    fsub qword [ebx+O_X]
    fst qword [ux]
    fmul st0, st0
    fld qword [esi+O_Y]
    fsub qword [ebx+O_Y]
    fst qword [uy]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    fldz
    fcomip st0, st1
    je .zero
    fld qword [ux]
    fdiv st0, st1
    fstp qword [ux]
    fdivr qword [uy]
    fstp qword [uy]
    clc
    ret
.zero:
    fstp st0
    stc
    ret

; edi = an intersection, ebx, ecx = its two parents (lines or circles) ->
; its point, or CF if there is none
intersect:
    pushad
    mov edx, ecx                ; the second parent
    movzx eax, byte [ebx+O_TYPE]
    call kind
    mov esi, ecx                ; esi = the first's kind
    movzx eax, byte [edx+O_TYPE]
    call kind
    xchg ecx, edx               ; ecx = the second, edx = its kind
    cmp esi, 2
    jne .l
    cmp edx, 2
    je .cc
    xchg ebx, ecx               ; circle and line: the line first
    jmp .lc
.l:
    cmp edx, 2
    je .lc
.ll:                            ; P1 + t d1 = P2 + s d2
    fld qword [ebx+O_DX]
    fmul qword [ecx+O_DY]
    fld qword [ebx+O_DY]
    fmul qword [ecx+O_DX]
    fsubp st1, st0              ; det
    fld st0
    fabs
    fld qword [f_tiny]
    fcomip st0, st1
    fstp st0
    jae .none1
    fld qword [ecx+O_X]
    fsub qword [ebx+O_X]
    fmul qword [ecx+O_DY]
    fld qword [ecx+O_Y]
    fsub qword [ebx+O_Y]
    fmul qword [ecx+O_DX]
    fsubp st1, st0
    fdivrp st1, st0             ; t
    jmp .along
.none1:
    fstp st0
    jmp .none
.lc:                            ; ebx = line, ecx = circle
    fld qword [ebx+O_X]         ; f = P - C
    fsub qword [ecx+O_X]
    fstp qword [ux]
    fld qword [ebx+O_Y]
    fsub qword [ecx+O_Y]
    fstp qword [uy]
    fld qword [ebx+O_DX]        ; a = d.d
    fmul st0, st0
    fld qword [ebx+O_DY]
    fmul st0, st0
    faddp st1, st0
    fstp qword [qa]
    fld qword [ux]              ; b = f.d
    fmul qword [ebx+O_DX]
    fld qword [uy]
    fmul qword [ebx+O_DY]
    faddp st1, st0
    fstp qword [qb]
    fld qword [ux]              ; c = f.f - r^2
    fmul st0, st0
    fld qword [uy]
    fmul st0, st0
    faddp st1, st0
    fld qword [ecx+O_DX]
    fmul st0, st0
    fsubp st1, st0
    fld qword [qb]              ; disc = b^2 - a c
    fmul st0, st0
    fld qword [qa]
    fmulp st2, st0
    fsubrp st1, st0
    fldz
    fcomip st0, st1
    jbe .root
    fld st0                     ; a tiny negative (a tangent): 0
    fabs
    fld qword [qb]
    fmul st0, st0
    fmul qword [f_tiny]
    fcomip st0, st1
    fstp st0
    jb .none1
    fstp st0
    fldz
.root:
    fsqrt
    cmp byte [edi+O_W], 0
    jne .plus
    fchs
.plus:
    fsub qword [qb]
    fdiv qword [qa]             ; t
.along:                         ; st0 = t along the first (ebx) line
    fld st0
    fmul qword [ebx+O_DX]
    fadd qword [ebx+O_X]
    fstp qword [edi+O_X]
    fmul qword [ebx+O_DY]
    fadd qword [ebx+O_Y]
    fstp qword [edi+O_Y]
    jmp .onseg
.cc:                            ; two circles
    fld qword [ecx+O_X]
    fsub qword [ebx+O_X]
    fstp qword [ux]             ; D
    fld qword [ecx+O_Y]
    fsub qword [ebx+O_Y]
    fstp qword [uy]
    fld qword [ux]
    fmul st0, st0
    fld qword [uy]
    fmul st0, st0
    faddp st1, st0              ; d^2
    fldz
    fcomip st0, st1
    je .none1
    fld qword [ebx+O_DX]        ; a = (r1^2 - r2^2 + d^2) / 2d
    fmul st0, st0
    fld qword [ecx+O_DX]
    fmul st0, st0
    fsubp st1, st0
    fadd st0, st1
    fxch
    fsqrt                       ; d
    fxch
    fdiv st0, st1
    fmul qword [f_half]         ; st0 = a, st1 = d
    fld qword [ebx+O_DX]        ; h^2 = r1^2 - a^2
    fmul st0, st0
    fld st1
    fmul st0, st0
    fsubp st1, st0
    fldz
    fcomip st0, st1
    jbe .h
    fld st0                     ; tangent within rounding: h = 0
    fabs
    fld qword [ebx+O_DX]
    fmul st0, st0
    fmul qword [f_tiny]
    fcomip st0, st1
    fstp st0
    jb .none3
    fstp st0
    fldz
.h:
    fsqrt                       ; st0 = h, st1 = a, st2 = d
    cmp byte [edi+O_W], 0
    je .h1
    fchs
.h1:
    fdiv st0, st2               ; h/d
    fxch
    fdiv st0, st2               ; a/d
    fld st0                     ; x = C1x + a/d Dx - h/d Dy
    fmul qword [ux]
    fadd qword [ebx+O_X]
    fld st2
    fmul qword [uy]
    fsubp st1, st0
    fstp qword [edi+O_X]
    fmul qword [uy]             ; y = C1y + a/d Dy + h/d Dx
    fadd qword [ebx+O_Y]
    fxch
    fmul qword [ux]
    faddp st1, st0
    fstp qword [edi+O_Y]
    fstp st0                    ; d
    jmp .yes
.none3:
    fstp st0
    fstp st0
    fstp st0
    jmp .none
.onseg:                         ; on a segment parent's part of its line
    mov esi, [par]
    call on_seg
    jc .none
    mov esi, [par+4]
    call on_seg
    jc .none
.yes:
    popad
    clc
    ret
.none:
    popad
    stc
    ret

; esi = a parent, edi = the point -> CF if esi is a segment and the
; point is off it
on_seg:
    cmp byte [esi+O_TYPE], T_SEG
    jne .ok
    fld qword [edi+O_X]         ; t = (X - P).d / d.d
    fsub qword [esi+O_X]
    fmul qword [esi+O_DX]
    fld qword [edi+O_Y]
    fsub qword [esi+O_Y]
    fmul qword [esi+O_DY]
    faddp st1, st0
    fld qword [esi+O_DX]
    fmul st0, st0
    fld qword [esi+O_DY]
    fmul st0, st0
    faddp st1, st0
    fdivp st1, st0
    fld qword [f_meps]
    fcomip st0, st1
    ja .off
    fld1
    fadd qword [f_eps]
    fcomip st0, st1
    jb .off
    fstp st0
.ok:
    clc
    ret
.off:
    fstp st0
    stc
    ret

; ---------- commands ----------
; esi = a command: done, or msg says why not
command:
    pushad
    mov byte [cname], 0
    call skip
    cmp byte [esi], 0
    je .r
    call word_len               ; "Name=" first?
    test ecx, ecx
    jz .body
    lea edi, [esi+ecx]
.sp:
    cmp byte [edi], ' '
    jne .sp1
    inc edi
    jmp .sp
.sp1:
    cmp byte [edi], '='
    jne .body
    cmp ecx, 7
    ja .unknown
    push edi
    mov edi, cname
    rep movsb
    mov byte [edi], 0
    pop esi
    inc esi
    push esi
    mov esi, cname
    call find
    pop esi
    jnc .taken
.body:
    call skip
    cmp byte [esi], '('
    je .point
    call word_len               ; the command's word
    test ecx, ecx
    jz .bad
    mov edi, cmd_names
    xor ebx, ebx
.look:
    cmp byte [edi], 0
    je .bad
    push esi
    push ecx
    push edi
.lc:
    mov al, [esi]
    or al, 0x20
    cmp al, [edi]
    jne .lne
    inc esi
    inc edi
    loop .lc
    cmp byte [edi], 0
    jne .lne
    add esp, 4                  ; (edi at the name's end stays)
    pop ecx
    add esp, 4                  ; (esi after the word stays)
    jmp .found
.lne:
    pop edi
    pop ecx
    pop esi
.skipn:
    inc edi
    cmp byte [edi-1], 0
    jne .skipn
    add edi, 2
    inc ebx
    jmp .look
.found:                         ; edi = the name's end: type, arguments
    movzx eax, byte [edi+1]
    mov [ctype], eax
    movzx eax, byte [edi+2]
    mov [cwhich], eax
    cmp byte [ctype], 0
    je .delete
    mov eax, [ctype]
    call nparents
    mov [cargs], ecx
    xor ebp, ebp                ; the arguments: names
.arg:
    cmp ebp, [cargs]
    jae .args
    call skip
    call word_len
    test ecx, ecx
    jz .maybe_r
    cmp ecx, 7
    ja .maybe_r
    mov edi, nbuf2
    push ecx
    rep movsb
    pop ecx
    mov byte [edi], 0
    push esi
    mov esi, nbuf2
    call find
    pop esi
    jc .notname
    mov [carg+ebp], al
    inc ebp
    jmp .arg
.notname:
    sub esi, ecx
.maybe_r:                       ; "circle A 2.5": a radius
    cmp dword [ctype], T_CIRC
    jne .unknown_or_few
    cmp ebp, 1
    jne .unknown_or_few
    jmp .radius
.unknown_or_few:
    cmp byte [esi], 0
    je .few
    jmp .unknown
.args:
    call skip
    cmp byte [esi], 0
    jne .many
    xor edx, edx                ; the arguments' kinds
.k:
    cmp edx, [cargs]
    jae .make
    movzx eax, byte [carg+edx]
    call obj_ptr
    movzx eax, byte [edi+O_TYPE]
    call kind
    mov eax, [ctype]
    movzx eax, byte [arg_kinds+eax*4+edx]
    cmp al, 9                   ; 9: a line or a circle
    jne .k1
    cmp ecx, 1
    je .k2
    cmp ecx, 2
    je .k2
    jmp .wrong
.k1:
    cmp eax, ecx
    jne .wrong
.k2:
    inc edx
    jmp .k
.make:
    cmp dword [ctype], T_INT
    jne .one
    cmp dword [cwhich], 2       ; "inter": both points (one for lines)
    jne .one
    movzx eax, byte [carg]
    call obj_ptr
    movzx eax, byte [edi+O_TYPE]
    call kind
    mov ebx, ecx
    movzx eax, byte [carg+1]
    call obj_ptr
    movzx eax, byte [edi+O_TYPE]
    call kind
    add ecx, ebx
    mov dword [cwhich], 0
    cmp ecx, 2                  ; two lines: one point
    je .one
    call make
    jc .r
    mov byte [cname], 0
    mov dword [cwhich], 1
.one:
    call make
    jmp .r
.radius:
    call skip
    call evaluate
    jc .r
    fld qword [val]
    fldz
    fcomip st0, st1
    fstp st0
    jae .negr
    mov dword [ctype], T_CIRCR
    mov dword [cargs], 1
    call make
    jc .r
    fld qword [val]
    fstp qword [edi+O_VAL]
    call update
    jmp .r
.point:                         ; "(x, y)"
    inc esi
    mov edi, ebuf               ; x: up to the comma outside brackets
    xor edx, edx
.px:
    lodsb
    test al, al
    jz .bad
    cmp al, '('
    jne .px1
    inc edx
.px1:
    cmp al, ')'
    jne .px2
    dec edx
.px2:
    test edx, edx
    jnz .px3
    cmp al, ','
    je .pxd
.px3:
    stosb
    cmp edi, ebuf + CMAX
    jb .px
    jmp .bad
.pxd:
    mov byte [edi], 0
    mov edi, ebuf2              ; y: up to the closing bracket
    xor edx, edx
.py:
    lodsb
    test al, al
    jz .bad
    cmp al, '('
    jne .py1
    inc edx
.py1:
    cmp al, ')'
    jne .py2
    dec edx
    js .pyd
.py2:
    stosb
    cmp edi, ebuf2 + CMAX
    jb .py
    jmp .bad
.pyd:
    mov byte [edi], 0
    call skip
    cmp byte [esi], 0
    jne .many
    mov esi, ebuf
    call evaluate
    jc .r
    fld qword [val]
    fstp qword [wx]
    mov esi, ebuf2
    call evaluate
    jc .r
    fld qword [val]
    fstp qword [wy]
    mov dword [ctype], T_PT
    mov dword [cargs], 0
    call make
    jc .r
    fld qword [wx]
    fstp qword [edi+O_X]
    fld qword [wy]
    fstp qword [edi+O_Y]
    call update
    mov [sel], eax
    jmp .r
.delete:
    call skip
    call word_len
    cmp ecx, 7
    ja .unknown
    mov edi, nbuf2
    rep movsb
    mov byte [edi], 0
    mov esi, nbuf2
    call find
    jc .unknown
    call remove
    jmp .r
.taken:
    mov dword [msg], m_taken
    jmp .r
.negr:
    mov dword [msg], m_negr
    jmp .r
.wrong:
    mov dword [msg], m_wrong
    jmp .r
.few:
    mov dword [msg], m_few
    jmp .r
.many:
    mov dword [msg], m_many
    jmp .r
.unknown:
    mov dword [msg], m_unknown
    jmp .r
.bad:
    mov dword [msg], m_bad
.r:
    popad
    ret

; ctype, cwhich, carg (cargs of them), cname -> eax = the new object,
; edi = it, worked out; CF if there is no room
make:
    mov esi, cname
    call new_obj
    jc .r
    mov cl, [ctype]
    mov [edi+O_TYPE], cl
    mov cl, [cwhich]
    mov [edi+O_W], cl
    mov ecx, [carg]
    mov [edi+O_A], cx
    shr ecx, 16
    mov [edi+O_C], cl
    call auto_name
    call update
    clc
.r:
    ret

; esi -> esi at the first non-space
skip:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip
.r:
    ret

; esi -> ecx = the length of the word there (letters and digits, from a
; letter or digit)
word_len:
    xor ecx, ecx
.c:
    mov al, [esi+ecx]
    cmp al, '0'
    jb .r
    cmp al, '9'
    jbe .y
    or al, 0x20
    cmp al, 'a'
    jb .r
    cmp al, 'z'
    ja .r
.y:
    inc ecx
    jmp .c
.r:
    ret

; esi = expression -> val, or CF (the message in msg)
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

; numv, ecx = most characters -> nbuf: rounded to 4 decimals, then fewer
; while it is too long; noise below 1e-9 is 0. "####" if it never fits.
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
    mov ebp, 4
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

; st0 (popped), ecx = most characters -> its text at edi (edi after it)
num_at:
    fstp qword [numv]
    call num_text
    push esi
    mov esi, nbuf
    call scopy
    pop esi
    ret

; ---------- the screen ----------
; wx, wy -> eax, ebx = the pixel (kept within +-30000)
w2s:
    fld qword [wx]
    fsub qword [vx]
    fmul qword [scale]
    fiadd dword [i_cenx]
    call clamp_pop
    mov eax, [tmp]
    fld qword [wy]
    fsub qword [vy]
    fmul qword [scale]
    fisubr dword [i_ceny]
    call clamp_pop
    mov ebx, [tmp]
    ret

; st0 (popped) -> tmp, rounded, within +-30000
clamp_pop:
    fld qword [f_big]
    fcomip st0, st1
    jae .lo
    fstp st0
    fld qword [f_big]
.lo:
    fld qword [f_big]
    fchs
    fcomip st0, st1
    jbe .ok
    fstp st0
    fld qword [f_big]
    fchs
.ok:
    fistp dword [tmp]
    ret

; gui_mx, gui_my -> wx, wy; CF off the canvas
mouse_world:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    cmp eax, CV_X
    jb .no
    cmp eax, CV_X + CV_W
    jae .no
    cmp ebx, CV_Y
    jb .no
    cmp ebx, CV_Y + CV_H
    jae .no
    sub eax, CEN_X
    mov [tmp], eax
    fild dword [tmp]
    fdiv qword [scale]
    fadd qword [vx]
    fstp qword [wx]
    neg ebx
    add ebx, CEN_Y
    mov [tmp], ebx
    fild dword [tmp]
    fdiv qword [scale]
    fadd qword [vy]
    fstp qword [wy]
    clc
    ret
.no:
    stc
    ret

; gui_mx, gui_my -> eax = a free point within NEARPX pixels, or CF
point_near:
    push ebx
    push ecx
    push edx
    push edi
    xor ecx, ecx
.o:
    cmp ecx, [nobj]
    jae .no
    mov eax, ecx
    call obj_ptr
    cmp byte [edi+O_TYPE], T_PT
    jne .n
    fld qword [edi+O_X]
    fstp qword [wx]
    fld qword [edi+O_Y]
    fstp qword [wy]
    call w2s
    sub eax, [gui_mx]
    cdq
    xor eax, edx
    sub eax, edx
    cmp eax, NEARPX
    ja .n
    sub ebx, [gui_my]
    mov eax, ebx
    cdq
    xor eax, edx
    sub eax, edx
    cmp eax, NEARPX
    ja .n
    mov eax, ecx
    pop edi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.n:
    inc ecx
    jmp .o
.no:
    pop edi
    pop edx
    pop ecx
    pop ebx
    stc
    ret

draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    call draw_canvas
    call draw_list
    call draw_status
    call gui_flip
    popad
    ret

draw_canvas:
    pushad
    mov eax, CV_X
    mov ebx, CV_Y
    mov ecx, CV_W
    mov edx, CV_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    call gui_clip
    call draw_axes
    xor eax, eax                ; lines and circles first
.o:
    cmp eax, [nobj]
    jae .pts
    call obj_ptr
    cmp byte [edi+O_DEF], 0
    je .n
    movzx ebx, byte [edi+O_TYPE]
    cmp ebx, T_SEG
    je .seg
    cmp ebx, T_CIRC
    jae .c
    cmp ebx, T_SEG
    ja .line
    jmp .n
.c:
    cmp ebx, T_DIST
    jae .n
    call draw_circle
    jmp .n
.seg:
    call draw_seg
    jmp .n
.line:
    call draw_line
.n:
    inc eax
    jmp .o
.pts:
    xor eax, eax
.p:
    cmp eax, [nobj]
    jae .done
    call obj_ptr
    cmp byte [edi+O_DEF], 0
    je .pn
    cmp byte [edi+O_TYPE], T_INT
    ja .pn
    call draw_point
.pn:
    inc eax
    jmp .p
.done:
    call gui_noclip
    mov eax, CV_X
    mov ebx, CV_Y
    mov ecx, CV_W
    mov edx, CV_H
    mov byte [gui_ink], C_DGREY
    call gui_box
    popad
    ret

; The axes, and a light grid at whole units when they are 8 pixels apart
draw_axes:
    pushad
    fldz
    fst qword [wx]
    fstp qword [wy]
    call w2s
    mov [ax0], eax
    mov [ay0], ebx
    fld qword [scale]
    fld qword [f_8]
    fcomip st0, st1
    fstp st0
    ja .axes
    fld qword [vx]              ; vertical lines: from the left edge
    fld qword [f_halfw]
    fdiv qword [scale]
    fsubp st1, st0
    frndint
    fstp qword [gx]
    mov byte [gui_ink], C_LGREY
.v:
    fld qword [gx]
    fstp qword [wx]
    call w2s
    cmp eax, CV_X + CV_W
    jge .h0
    mov ecx, eax
    mov ebx, CV_Y
    mov edx, CV_Y + CV_H - 1
    call gui_line
    fld1
    fadd qword [gx]
    fstp qword [gx]
    jmp .v
.h0:
    fld qword [vy]
    fld qword [f_halfh]
    fdiv qword [scale]
    fsubp st1, st0
    frndint
    fstp qword [gx]
.h:
    fld qword [gx]
    fstp qword [wy]
    call w2s
    cmp ebx, CV_Y
    jl .axes
    mov edx, ebx
    mov eax, CV_X
    mov ecx, CV_X + CV_W - 1
    call gui_line
    fld1
    fadd qword [gx]
    fstp qword [gx]
    jmp .h
.axes:
    mov byte [gui_ink], C_DGREY
    mov eax, [ax0]
    mov ecx, eax
    mov ebx, CV_Y
    mov edx, CV_Y + CV_H - 1
    call gui_line
    mov ebx, [ay0]
    mov edx, ebx
    mov eax, CV_X
    mov ecx, CV_X + CV_W - 1
    call gui_line
    popad
    ret

; edi = a segment
draw_seg:
    pushad
    fld qword [edi+O_X]
    fstp qword [wx]
    fld qword [edi+O_Y]
    fstp qword [wy]
    call w2s
    push eax
    push ebx
    fld qword [edi+O_X]
    fadd qword [edi+O_DX]
    fstp qword [wx]
    fld qword [edi+O_Y]
    fadd qword [edi+O_DY]
    fstp qword [wy]
    call w2s
    mov ecx, eax
    mov edx, ebx
    pop ebx
    pop eax
    mov byte [gui_ink], C_BLACK
    call gui_line
    popad
    ret

; edi = a line: from the view centre's foot on it, half the canvas'
; outline each way
draw_line:
    pushad
    fld qword [edi+O_DX]        ; |d|
    fmul st0, st0
    fld qword [edi+O_DY]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    fld qword [vx]              ; t = (V - P).d / |d|^2
    fsub qword [edi+O_X]
    fmul qword [edi+O_DX]
    fld qword [vy]
    fsub qword [edi+O_Y]
    fmul qword [edi+O_DY]
    faddp st1, st0
    fdiv st0, st1
    fdiv st0, st1
    fstp qword [qa]             ; t
    fld qword [f_reach]         ; s = reach / scale / |d|
    fdiv qword [scale]
    fdivrp st1, st0
    fstp qword [qb]
    fld qword [qa]
    fsub qword [qb]
    call .at
    push eax
    push ebx
    fld qword [qa]
    fadd qword [qb]
    call .at
    mov ecx, eax
    mov edx, ebx
    pop ebx
    pop eax
    mov byte [gui_ink], C_BLACK
    call gui_line
    popad
    ret
.at:                            ; st0 = t (popped) -> eax, ebx
    fld st0
    fmul qword [edi+O_DX]
    fadd qword [edi+O_X]
    fstp qword [wx]
    fmul qword [edi+O_DY]
    fadd qword [edi+O_Y]
    fstp qword [wy]
    jmp w2s

; edi = a circle (midpoint algorithm; not drawn past 2000 pixels)
draw_circle:
    pushad
    fld qword [edi+O_X]
    fstp qword [wx]
    fld qword [edi+O_Y]
    fstp qword [wy]
    call w2s
    mov [ccx], eax
    mov [ccy], ebx
    fld qword [edi+O_DX]
    fmul qword [scale]
    fld qword [f_2000]
    fcomip st0, st1
    jb .big
    fistp dword [tmp]
    mov ecx, [tmp]              ; x = r, y = 0
    xor edx, edx
    mov ebp, 1
    sub ebp, ecx                ; d = 1 - r
    mov byte [gui_ink], C_BLUE
.l:
    cmp edx, ecx
    jg .r
    call .eight
    inc edx
    test ebp, ebp
    js .in
    dec ecx
    mov eax, edx
    sub eax, ecx
    lea ebp, [ebp+eax*2+1]
    jmp .l
.in:
    lea ebp, [ebp+edx*2+1]
    jmp .l
.big:
    fstp st0
.r:
    popad
    ret
.eight:                         ; (+-x, +-y) and (+-y, +-x)
    push ecx
    push edx
    mov esi, ecx
    mov edi, edx
    mov cl, [gui_ink]
    mov eax, [ccx]
    add eax, esi
    mov ebx, [ccy]
    add ebx, edi
    call gui_pset
    mov ebx, [ccy]
    sub ebx, edi
    call gui_pset
    mov eax, [ccx]
    sub eax, esi
    call gui_pset
    mov ebx, [ccy]
    add ebx, edi
    call gui_pset
    mov eax, [ccx]
    add eax, edi
    mov ebx, [ccy]
    add ebx, esi
    call gui_pset
    mov ebx, [ccy]
    sub ebx, esi
    call gui_pset
    mov eax, [ccx]
    sub eax, edi
    call gui_pset
    mov ebx, [ccy]
    add ebx, esi
    call gui_pset
    pop edx
    pop ecx
    ret

; eax = its number, edi = a point: a dot and its name
draw_point:
    pushad
    mov ebp, eax
    fld qword [edi+O_X]
    fstp qword [wx]
    fld qword [edi+O_Y]
    fstp qword [wy]
    call w2s
    push eax
    push ebx
    mov cl, C_DGREY             ; free points red, others grey
    cmp byte [edi+O_TYPE], T_PT
    jne .c
    mov cl, C_RED
.c:
    mov [gui_ink], cl
    sub eax, 2
    sub ebx, 2
    mov ecx, 5
    mov edx, 5
    call gui_fill
    pop ebx
    pop eax
    cmp ebp, [sel]
    jne .name
    mov byte [gui_ink], C_BLACK
    sub eax, 4
    sub ebx, 4
    mov ecx, 9
    mov edx, 9
    call gui_box
    add eax, 4
    add ebx, 4
.name:
    add eax, 4
    sub ebx, CELL_H + 1
    lea esi, [edi+O_NAME]
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    call gui_text
    popad
    ret

; The list on the right: an object a row (the last ones if they are many)
draw_list:
    pushad
    mov eax, PN_X
    mov ebx, CV_Y
    mov ecx, PN_W
    mov edx, CV_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_ink], C_DGREY
    call gui_box
    xor ebp, ebp
    mov eax, [nobj]
    sub eax, PN_ROWS
    jbe .o
    mov ebp, eax
.o:
    cmp ebp, [nobj]
    jae .r
    mov eax, ebp
    call obj_ptr
    call describe
    mov eax, ebp
    sub eax, [nobj]
    add eax, PN_ROWS
    cmp dword [nobj], PN_ROWS
    jae .y
    mov eax, ebp
.y:
    imul ebx, eax, CELL_H
    add ebx, CV_Y + 2
    mov eax, PN_X + 2
    mov ecx, PN_W - 4
    mov esi, line
    mov byte [gui_ink], C_BLACK
    cmp ebp, [sel]
    jne .t
    mov byte [gui_ink], C_RED
.t:
    mov byte [gui_bg], C_WHITE
    call gui_textn
    inc ebp
    jmp .o
.r:
    popad
    ret

; edi = an object -> line: "A (1, 2)", "l1: slope 2", "c1: r 3",
; "m1 = 5", "s1: length 5", or its name and "?" when it does not exist
describe:
    pushad
    mov ebx, edi
    lea esi, [ebx+O_NAME]
    mov edi, line
    call scopy
    cmp byte [ebx+O_DEF], 0
    je .undef
    movzx eax, byte [ebx+O_TYPE]
    call kind
    jmp [desc_tab+ecx*4]
.point:
    mov ax, ' ('
    stosw
    fld qword [ebx+O_X]
    mov ecx, 7
    call num_at
    mov ax, ', '
    stosw
    fld qword [ebx+O_Y]
    call num_at
    mov al, ')'
    stosb
    jmp .r
.line:
    cmp byte [ebx+O_TYPE], T_SEG
    jne .slope
    mov esi, s_length
    call scopy
    fld qword [ebx+O_DX]
    fmul st0, st0
    fld qword [ebx+O_DY]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    mov ecx, 9
    call num_at
    jmp .r
.slope:
    fld qword [ebx+O_DX]
    fabs
    fld qword [f_tiny]
    fcomip st0, st1
    fstp st0
    jb .s
    mov esi, s_vertical
    call scopy
    jmp .r
.s:
    mov esi, s_slope
    call scopy
    fld qword [ebx+O_DY]
    fdiv qword [ebx+O_DX]
    mov ecx, 9
    call num_at
    jmp .r
.circle:
    mov esi, s_radius
    call scopy
    fld qword [ebx+O_DX]
    mov ecx, 9
    call num_at
    jmp .r
.measure:
    mov ax, ' ='
    stosw
    mov al, ' '
    stosb
    fld qword [ebx+O_VAL]
    mov ecx, 9
    call num_at
    cmp byte [ebx+O_TYPE], T_ANG
    jne .r
    mov esi, s_deg
    call scopy
    jmp .r
.undef:
    mov esi, s_undef
    call scopy
.r:
    mov byte [edi], 0
    popad
    ret

draw_status:
    pushad
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    cmp byte [typing], 0
    je .f
    mov byte [gui_ink], C_YELLOW
.f:
    call gui_fill
    mov al, [gui_ink]
    mov [gui_bg], al
    mov byte [gui_ink], C_BLACK
    cmp byte [typing], 0
    je .msg
    mov edi, line
    mov ax, '> '
    stosw
    mov esi, cbuf
    call scopy
    mov ax, '_'
    stosw
    mov esi, line
    jmp .out
.msg:
    mov esi, [msg]
    test esi, esi
    jnz .out
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
; The objects -> fname: one command a line, each named
save:
    pushad
    mov edi, [fbuf]
    xor eax, eax
.o:
    cmp eax, [nobj]
    jae .write
    mov ebp, eax
    shl ebp, 6
    add ebp, objs
    push eax
    lea esi, [ebp+O_NAME]
    call scopy
    mov al, '='
    stosb
    movzx eax, byte [ebp+O_TYPE]
    cmp eax, T_PT
    jne .cmd
    mov al, '('
    stosb
    fld qword [ebp+O_X]
    call full_at
    mov al, ','
    stosb
    fld qword [ebp+O_Y]
    call full_at
    mov al, ')'
    stosb
    jmp .eol
.cmd:
    mov esi, [save_word+eax*4]
    call scopy
    movzx eax, byte [ebp+O_TYPE]
    cmp eax, T_INT              ; inter1 / inter2
    jne .args
    mov al, '1'
    add al, [ebp+O_W]
    stosb
    mov eax, T_INT
.args:
    call nparents
    xor edx, edx
.a:
    cmp edx, ecx
    jae .rad
    mov al, ' '
    stosb
    movzx esi, byte [ebp+O_A+edx]
    shl esi, 6
    add esi, objs + O_NAME
    call scopy
    inc edx
    jmp .a
.rad:
    cmp byte [ebp+O_TYPE], T_CIRCR
    jne .eol
    mov al, ' '
    stosb
    fld qword [ebp+O_VAL]
    call full_at
.eol:
    mov al, 10
    stosb
    pop eax
    inc eax
    jmp .o
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

; st0 (popped) -> its full text at edi (edi after it)
full_at:
    fstp qword [numv]
    call full_text
    push esi
    mov esi, nbuf
    call scopy
    pop esi
    ret

; fname -> the objects: each line run as a command
load:
    pushad
    mov dword [nobj], 0
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
.l:
    cmp byte [esi], 0
    je .done
    mov edi, cbuf
    xor ecx, ecx
.c:
    lodsb
    test al, al
    jz .end0
    cmp al, 10
    je .end
    cmp al, 13
    je .c
    cmp ecx, CMAX
    jae .c
    stosb
    inc ecx
    jmp .c
.end0:
    dec esi
.end:
    mov byte [edi], 0
    push esi
    mov esi, cbuf
    call command
    pop esi
    jmp .l
.done:
    mov byte [dirty], 0
    mov dword [msg], m_opened
    cmp dword [nobj], 0
    jne .r
.new:
    mov dword [msg], m_newfile
.r:
    popad
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
; esi = a name, edi = expected doubles at +0 (and +8): CF unless the
; object exists and its value (a measurement, a circle's radius) or its
; point (x and y) is within 1e-9 of them
want:
    pushad
    call find
    jc .no
    mov ebx, edi
    call obj_ptr
    cmp byte [edi+O_DEF], 0
    je .no
    movzx eax, byte [edi+O_TYPE]
    call kind
    lea esi, [edi+O_VAL]
    cmp ecx, 3
    je .one
    lea esi, [edi+O_DX]
    cmp ecx, 2
    je .one
    lea esi, [edi+O_X]          ; a point: x, y
    fld qword [esi+8]
    fsub qword [ebx+8]
    call near0
    jc .no
.one:
    fld qword [esi]
    fsub qword [ebx]
    call near0
    jc .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; st0 (popped) -> CF unless |st0| <= 1e-9
near0:
    fabs
    fld qword [f_tol]
    fcomip st0, st1
    fstp st0
    jb .no
    clc
    ret
.no:
    stc
    ret

; esi = a name -> CF unless it is there and does not exist (O_DEF 0)
want_undef:
    pushad
    call find
    jc .no
    call obj_ptr
    cmp byte [edi+O_DEF], 0
    jne .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = commands, a zero after each, two zeros at the end
run_all:
    pushad
.c:
    cmp byte [esi], 0
    je .r
    mov dword [msg], 0
    call command
    cmp dword [msg], 0
    jne .bad
    call strlen
    lea esi, [esi+eax+1]
    jmp .c
.r:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; esi = keys: characters, or 0xE0 and a scancode; 0 ends
feed:
    pushad
.k:
    movzx eax, byte [esi]
    test eax, eax
    jz .r
    inc esi
    cmp al, 0xE0
    jne .send
    movzx eax, byte [esi]
    inc esi
    shl eax, 8
.send:
    push esi
    call key
    pop esi
    jmp .k
.r:
    popad
    ret

; ecx = colour, eax, ebx = a pixel -> CF unless that colour is within a
; pixel of it
ink_near:
    pushad
    mov esi, eax
    mov edi, ebx
    mov ebx, edi
    dec ebx
.y:
    mov eax, esi
    dec eax
.x:
    push ecx
    call gui_peek
    cmp cl, [esp]
    pop ecx
    je .yes
    inc eax
    lea edx, [esi+1]
    cmp eax, edx
    jle .x
    inc ebx
    lea edx, [edi+1]
    cmp ebx, edx
    jle .y
    popad
    stc
    ret
.yes:
    popad
    clc
    ret

%macro WANT 2-3 0.0             ; name, value (or x), y
    mov esi, %%n
    mov edi, %%v
    call want
    jc .fail
    jmp %%e
%%n db %1, 0
align 8
%%v dq %2, %3
%%e:
%endmacro
%macro RUN 1
    mov esi, %%c
    call run_all
    jc .fail
    jmp %%e
%%c db %1, 0, 0
%%e:
%endmacro

selftest:
    mov byte [bad], 'p'         ; points, and the measurements of a 3-4-5
    RUN {'(0,0)', 0, '(4,0)', 0, 'C=(0, 1+2)', 0, 'dist B C', 0, 'angle B A C', 0, 'area A B C', 0}
    WANT 'A', 0.0, 0.0
    WANT 'C', 0.0, 3.0
    WANT 'm1', 5.0
    WANT 'm2', 90.0
    WANT 'm3', 6.0
    mov byte [bad], 'c'         ; constructions
    RUN {'M=mid A B', 0, 'seg B C', 0, 'line A B', 0, 'perp l1 C', 0, 'par l1 C', 0}
    RUN {'bis A B', 0, 'abis B A C', 0, 'circle A B', 0, 'k=circle C 2', 0}
    WANT 'M', 2.0, 0.0
    WANT 'c1', 4.0
    WANT 'k', 2.0
    mov byte [bad], 'i'         ; intersections
    RUN {'inter l2 l1', 0}      ; perpendicular through C meets AB at A
    WANT 'D', 0.0, 0.0
    RUN {'inter l4 l1', 0}      ; the bisector of AB at M
    WANT 'E', 2.0, 0.0
    RUN {'inter l5 s1', 0}      ; the angle bisector meets BC at (12/7, 12/7)
    WANT 'F', 1.7142857142857142, 1.7142857142857142
    RUN {'inter s1 c1', 0}      ; BC meets the circle at B, and past C (off BC)
    WANT 'G', 4.0, 0.0
    mov esi, s_H
    call want_undef
    jc .fail
    RUN {'inter c1 k', 0}       ; two circles
    WANT 'I', -1.9364916731037085, 3.5
    WANT 'J', 1.9364916731037085, 3.5
    RUN {'inter l1 l3', 0}      ; parallels: no point
    mov esi, s_K
    call want_undef
    jc .fail
    mov byte [bad], 'm'         ; a point moved: everything follows
    mov dword [sel], 0          ; A, then Tab: B
    mov esi, keys_move
    call feed
    WANT 'B', 4.5, 0.0
    WANT 'm1', 5.408326913195984
    WANT 'm3', 6.75
    WANT 'M', 2.25, 0.0
    mov byte [bad], 'd'         ; drawn: the circle c1 round A, radius 4
    call draw
    fld qword [scale]           ; k's lowest point: C - (0, 2) = (0, 1)
    fistp dword [tmp]
    mov eax, CEN_X
    mov ebx, CEN_Y
    sub ebx, [tmp]
    mov ecx, C_BLUE
    call ink_near
    jc .fail
    mov eax, CEN_X - 2          ; C (0, 3), a free point: red
    mov ebx, CEN_Y - 60
    mov ecx, C_RED
    call ink_near
    jc .fail
    mov byte [bad], 'r'         ; removing B removes what is built on it
    mov eax, [nobj]
    mov [tmp2], eax
    RUN {'del B', 0}
    mov esi, s_m1
    call find
    jnc .fail
    mov esi, s_m2               ; (BAC's angle needs B too)
    call find
    jnc .fail
    mov esi, s_k
    call find
    jc .fail
    mov byte [bad], 'e'         ; errors
    mov esi, c_bad1             ; (an unknown command lists them)
    call command
    cmp dword [msg], m_bad
    jne .fail
    mov esi, c_bad2
    call command
    cmp dword [msg], m_wrong
    jne .fail
    mov esi, c_bad3
    call command
    cmp dword [msg], m_taken
    jne .fail
    mov byte [bad], 'f'         ; save and load
    mov dword [msg], 0
    RUN {'B=(4,0)', 0, 'dist A B', 0, 'circle B 1.5', 0, 'inter c1 k', 0}
    mov eax, [nobj]
    mov [tmp2], eax
    mov esi, s_testfile
    mov edi, fname
    call copy_name
    call save
    jc .fail
    mov dword [nobj], 0
    call load
    mov eax, [nobj]
    cmp eax, [tmp2]
    jne .fail
    WANT 'k', 2.0
    WANT 'c1', 1.5
    WANT 'm1', 4.0
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
title db 'Geometry', 0
s_default db 'drawing.geo', 0
s_testfile db 'gtest.geo', 0
s_none db 0
s_x db 'x', 0
s_H db 'H', 0
s_K db 'K', 0
s_m1 db 'm1', 0
s_m2 db 'm2', 0
s_k db 'k', 0
c_bad1 db 'circel A B', 0
c_bad2 db 'perp A C', 0
c_bad3 db 'A=(1,1)', 0
keys_move db 0xE0, K_TAB, 0xE0, K_RIGHT, 0xE0, K_RIGHT, 0
s_keys db 'Type a command: (1,2) seg line circle ...', 0
s_length db ': length ', 0
s_vertical db ': vertical', 0
s_slope db ': slope ', 0
s_radius db ': r ', 0
s_deg db ' deg', 0
s_undef db ' ?', 0
m_full db 'No room for more objects', 0
m_taken db 'That name is taken', 0
m_negr db 'The radius must be more than 0', 0
m_wrong db 'Those are not the right kinds of object', 0
m_few db 'Not enough objects named', 0
m_many db 'Too much after the command', 0
m_unknown db 'Unknown command or name', 0
m_bad db 'Commands: (x,y) seg line circle mid perp par bis abis inter dist angle area del', 0
m_opened db 'Opened', 0
m_newfile db 'New file', 0
m_saved db 'Saved', 0
m_nosave db 'Could not save', 0
m_nogfx db 'geometry: no graphics', 10, 0
pass db 'geometry: PASS', 10, 0
fail db 'geometry: FAIL ', 0
bad db '?', 10, 0
; commands: the word, its type, its "which" (2: inter makes both)
cmd_names:
    db 'seg', 0, T_SEG, 0
    db 'line', 0, T_LINE, 0
    db 'circle', 0, T_CIRC, 0
    db 'mid', 0, T_MID, 0
    db 'perp', 0, T_PERP, 0
    db 'par', 0, T_PAR, 0
    db 'bis', 0, T_BIS, 0
    db 'abis', 0, T_ABIS, 0
    db 'inter', 0, T_INT, 2
    db 'inter1', 0, T_INT, 0
    db 'inter2', 0, T_INT, 1
    db 'dist', 0, T_DIST, 0
    db 'angle', 0, T_ANG, 0
    db 'area', 0, T_AREA, 0
    db 'del', 0, 0, 0
    db 0
; parents of each type
npar db 0, 0, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 2, 3, 3
; the kinds each type's parents must be (0 point, 1 line, 2 circle,
; 9 line or circle), four bytes a type
arg_kinds:
    db 0, 0, 0, 0               ; -
    db 0, 0, 0, 0               ; point
    db 0, 0, 0, 0               ; mid
    db 9, 9, 0, 0               ; inter
    db 0, 0, 0, 0               ; seg
    db 0, 0, 0, 0               ; line
    db 1, 0, 0, 0               ; perp
    db 1, 0, 0, 0               ; par
    db 0, 0, 0, 0               ; bis
    db 0, 0, 0, 0               ; abis
    db 0, 0, 0, 0               ; circle
    db 0, 0, 0, 0               ; circle with a radius
    db 0, 0, 0, 0               ; dist
    db 0, 0, 0, 0               ; angle
    db 0, 0, 0, 0               ; area
save_word dd 0, 0, s_wmid, s_wint, s_wseg, s_wline, s_wperp, s_wpar
          dd s_wbis, s_wabis, s_wcirc, s_wcirc, s_wdist, s_wang, s_warea
s_wmid db 'mid', 0
s_wint db 'inter', 0
s_wseg db 'seg', 0
s_wline db 'line', 0
s_wperp db 'perp', 0
s_wpar db 'par', 0
s_wbis db 'bis', 0
s_wabis db 'abis', 0
s_wcirc db 'circle', 0
s_wdist db 'dist', 0
s_wang db 'angle', 0
s_warea db 'area', 0
kind_letter db 'P', 'l', 'c', 'm'
compute_tab dd compute.r, compute.pt, compute.mid, compute.int
            dd compute.seg, compute.seg, compute.perp, compute.par
            dd compute.bis, compute.abis, compute.circ, compute.circr
            dd compute.dist, compute.ang, compute.area
desc_tab dd describe.point, describe.line, describe.circle, describe.measure
i_cenx dd CEN_X
i_ceny dd CEN_Y
align 8
f_scale dq 20.0
f_zoom dq 1.5
f_half dq 0.5
f_q dq 0.25
f_mq dq -0.25
f_4 dq 4.0
f_8 dq 8.0
f_eps dq 1.0e-9
f_meps dq -1.0e-9
f_tiny dq 1.0e-12
f_tol dq 1.0e-9
f_noise dq 1.0e-9
f_big dq 30000.0
f_2000 dq 2000.0
f_reach dq 400.0
f_halfw dq 97.0
f_halfh dq 87.0
f_deg dq 57.29577951308232
pow10 dq 1.0, 10.0, 100.0, 1000.0, 10000.0

SQX_BSS
GUI_BSS
alignb 8
val resq 1
numv resq 1
scale resq 1
vx resq 1
vy resq 1
wx resq 1
wy resq 1
px resq 1
py resq 1
ux resq 1
uy resq 1
vx_ resq 1
vy_ resq 1
qa resq 1
qb resq 1
gx resq 1
arg resd 1
fbuf resd 1
flen resd 1
nobj resd 1
sel resd 1
msg resd 1
clen resd 1
tmp resd 1
tmp2 resd 1
nwidth resd 1
ctype resd 1
cwhich resd 1
cargs resd 1
carg resd 1
par resd 3
ax0 resd 1
ay0 resd 1
ccx resd 1
ccy resd 1
ev resb GE_SIZE
typing resb 1
dirty resb 1
gone resb MAXOBJ
newi resb MAXOBJ
cname resb 8
nbuf2 resb 16
etext resb 40
nbuf resb 40
fname resb NAME_MAX + 4
cbuf resb CMAX + 4
ebuf resb CMAX + 4
ebuf2 resb CMAX + 4
line resb 96
objs resb MAXOBJ * OSIZE
SQX_END
