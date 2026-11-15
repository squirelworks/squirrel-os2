; Squirrel-OS/2 — Paint (A.2, OS2-APPS)
; Original code. run paint [file.bmp]   |   run paint test
;
; A bitmap painter: a 272 x 160 canvas in the 16 EGA colours, saved and
; opened as 8-bit BMP files (bmp.inc).
;
; Tools (click one, or its key):  p Pen   l Line   b Box   s Solid box
;                                 f Fill  e Eraser
;   Mouse: on the canvas the left button draws with Pen and Eraser (drag
;   for strokes); Line, Box and Solid take two clicks, Fill one. A click
;   on the palette picks the colour.
;   Keys: arrows move the cross (Ctrl+arrow 8 pixels); Space puts the pen
;   down or up, or sets the first and then the second corner; c and C or
;   [ and ] pick the colour; u undoes the last change; Ctrl+S saves
;   (F2 too; the first time it asks for a name); Ctrl+O opens; Ctrl+N
;   clears; Esc drops a started shape, else quits (asking if unsaved).
;
; "run paint test" draws with each tool, checks the canvas, saves
; ptest.bmp, opens it again and compares, then prints "paint: PASS".
; See documentation/apps/paint.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "bmp.inc"

CW_         equ 272             ; canvas
CH_         equ 160
CX_         equ 44              ; on the screen
CY_         equ 1 + WIN_TITLE_H + 3
TB_X        equ 3               ; tool buttons
TB_W        equ 38
TB_H        equ 13
PAL_Y       equ CY_ + CH_ + 4
SW_W        equ 17              ; palette swatch
SW_H        equ 9
STAT_Y      equ PAL_Y + SW_H + 3
NAME_MAX    equ 31
STACK_MAX   equ 32768           ; fill stack entries

T_PEN       equ 0
T_LINE      equ 1
T_BOX       equ 2
T_SOLID     equ 3
T_FILL      equ 4
T_ERASE     equ 5
TOOLS       equ 6

main:
    mov esi, [esp+4]
    mov [arg], esi
    call alloc
    jc .nomem
    call gui_open
    jc .nogfx
    call clear_canvas
    mov byte [colour], C_BLACK
    mov dword [kx], CW_ / 2
    mov dword [ky], CH_ / 2
    mov esi, [arg]
    cmp dword [esi], 'test'
    je selftest
    cmp byte [esi], 0
    je .draw
    mov edi, name
    call copy_name
    call open_file
.draw:
    call draw
.ev:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    cmp eax, EV_DRAG
    je .drag
    mov ebx, eax
    shr ebx, 8                  ; bl = scancode, bit 8 = Ctrl
    test eax, 1 << 16
    jz .plain
    and al, 0xDF
    cmp al, 'S'
    je .save
    cmp al, 'O'
    je .open
    cmp al, 'N'
    je .new
    mov edx, 8                  ; Ctrl+arrow: 8 pixels
    jmp .arrows
.plain:
    mov edx, 1
    cmp bl, K_ESC
    je .esc
    cmp bl, K_F2
    je .save
    cmp al, ' '
    je .space
.arrows:
    cmp bl, K_LEFT
    je .l
    cmp bl, K_RIGHT
    je .r
    cmp bl, K_UP
    je .u
    cmp bl, K_DOWN
    je .d
    test eax, 1 << 16
    jnz .ev
    mov edi, tool_keys          ; a tool's key
    mov ecx, TOOLS
    push edi
    repne scasb
    pop ebx
    jne .other
    sub edi, ebx
    dec edi
    mov [tool], edi
    mov byte [anchor], 0
    mov byte [pendown], 0
    jmp .draw
.other:
    cmp al, 'c'
    je .cnext
    cmp al, ']'
    je .cnext
    cmp al, 'C'
    je .cprev
    cmp al, '['
    je .cprev
    cmp al, 'u'
    je .undo
    jmp .ev
.l:
    neg edx
.r:
    add [kx], edx
    jmp .moved
.u:
    neg edx
.d:
    add [ky], edx
.moved:
    call clamp_cross
    cmp byte [pendown], 0
    je .draw
    mov eax, [px_]              ; pen down: a line from the last place
    mov ebx, [py_]
    mov ecx, [kx]
    mov edx, [ky]
    call stroke
    jmp .draw
.space:
    mov eax, [kx]
    mov ebx, [ky]
    call act
    jmp .draw
.click:
    mov byte [mouse_pen], 0
    call to_canvas
    jc .clk_ui
    mov [kx], eax
    mov [ky], ebx
    mov byte [pendown], 0
    call act
    cmp dword [tool], T_PEN     ; a click with the pen: a dot, and the
    je .clkpen                  ; drag goes on from it
    cmp dword [tool], T_ERASE
    jne .draw
.clkpen:
    mov byte [pendown], 0
    mov byte [mouse_pen], 1
    jmp .draw
.drag:
    cmp byte [mouse_pen], 0
    je .ev
    call to_canvas
    jc .ev
    mov ecx, eax
    mov edx, ebx
    mov eax, [px_]
    mov ebx, [py_]
    mov [kx], ecx
    mov [ky], edx
    call stroke
    jmp .draw
.clk_ui:
    mov byte [mouse_pen], 0
    call ui_click
    jmp .draw
.cnext:
    mov eax, 1
    jmp .cpick
.cprev:
    mov eax, 15
.cpick:
    push eax
    mov al, [colour]
    call bmp_ega_index
    pop ecx
    add eax, ecx
    and eax, 15
    mov al, [bmp_ega+eax]
    mov [colour], al
    jmp .draw
.undo:
    call swap_undo
    jmp .draw
.save:
    call save
    jmp .draw
.open:
    call ask_unsaved
    jc .draw
    mov esi, q_open
    call ask_name
    jc .draw
    call open_file
    jmp .draw
.new:
    call ask_unsaved
    jc .draw
    call keep_undo
    call clear_canvas
    mov byte [name], 0
    mov byte [dirty], 0
    jmp .draw
.esc:
    cmp byte [anchor], 0
    jne .drop
    cmp byte [pendown], 0
    jne .drop
    call ask_unsaved
    jc .draw
    call gui_close
    xor eax, eax
    ret
.drop:
    mov byte [anchor], 0
    mov byte [pendown], 0
    jmp .draw
.nogfx:
.nomem:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- memory ----------
; canvas, the undo copy and the fill stack, from the heap
alloc:
    mov eax, SYS_SBRK
    mov ebx, CW_ * CH_ * 2 + STACK_MAX * 4
    int 0x80
    cmp eax, -1
    je .no
    mov [canvas], eax
    add eax, CW_ * CH_
    mov [undo], eax
    add eax, CW_ * CH_
    mov [stack], eax
    clc
    ret
.no:
    stc
    ret

clear_canvas:
    pushad
    mov edi, [canvas]
    mov ecx, CW_ * CH_
    mov al, C_WHITE
    rep stosb
    popad
    ret

; Copies the canvas to the undo copy (before a change).
keep_undo:
    pushad
    mov esi, [canvas]
    mov edi, [undo]
    mov ecx, CW_ * CH_ / 4
    rep movsd
    mov byte [can_undo], 1
    popad
    ret

; u: the canvas and the undo copy change places (so u again redoes).
swap_undo:
    cmp byte [can_undo], 0
    je .r
    mov eax, [canvas]
    xchg eax, [undo]
    mov [canvas], eax
    mov byte [dirty], 1
.r:
    ret

; ---------- canvas pixels ----------
; eax = x, ebx = y -> cl = the canvas colour (CF off the canvas)
cget:
    cmp eax, CW_
    jae .off
    cmp ebx, CH_
    jae .off
    push ebx
    imul ebx, CW_
    add ebx, [canvas]
    mov cl, [ebx+eax]
    pop ebx
    clc
    ret
.off:
    stc
    ret

; eax = x, ebx = y, cl = colour; off the canvas: nothing
cset:
    cmp eax, CW_
    jae .r
    cmp ebx, CH_
    jae .r
    push ebx
    imul ebx, CW_
    add ebx, [canvas]
    mov [ebx+eax], cl
    pop ebx
.r:
    ret

; The colour the current tool puts down: the eraser's is white.
ink:
    mov cl, [colour]
    cmp dword [tool], T_ERASE
    jne .r
    mov cl, C_WHITE
.r:
    ret

; eax, ebx -> ecx, edx: a line on the canvas in [lc] (Bresenham)
cline:
    pushad
    mov [lx1], ecx
    mov [ly1], edx
    mov esi, 1
    sub ecx, eax
    jge .dx
    neg ecx
    neg esi
.dx:
    mov [ldx], ecx
    mov edi, 1
    sub edx, ebx
    jge .dy
    neg edx
    neg edi
.dy:
    neg edx
    mov [ldy], edx
    add ecx, edx
    mov ebp, ecx
.p:
    mov cl, [lc]
    call cset
    cmp eax, [lx1]
    jne .s
    cmp ebx, [ly1]
    je .done
.s:
    lea edx, [ebp+ebp]
    cmp edx, [ldy]
    jl .nx
    add ebp, [ldy]
    add eax, esi
.nx:
    cmp edx, [ldx]
    jg .p
    add ebp, [ldx]
    add ebx, edi
    jmp .p
.done:
    popad
    ret

; A pen or eraser stroke from eax, ebx to ecx, edx; px_, py_ follow.
stroke:
    pushad
    push ecx
    call ink
    mov [lc], cl
    pop ecx
    call cline
    mov [px_], ecx
    mov [py_], edx
    mov byte [dirty], 1
    popad
    ret

; eax, ebx and ecx, edx = two corners (any order) -> a box outline
; ([solid] = 0) or a filled box (1) in [lc]
cbox:
    pushad
    cmp eax, ecx
    jle .x
    xchg eax, ecx
.x:
    cmp ebx, edx
    jle .y
    xchg ebx, edx
.y:
    mov [lx0], eax
    mov [ly0], ebx
    mov [lx1], ecx
    mov [ly1], edx
    mov cl, [lc]
    mov ebx, [ly0]
.row:
    mov eax, [lx0]
.col:
    cmp byte [solid], 0
    jne .put
    cmp ebx, [ly0]              ; an outline: only the edges
    je .put
    cmp ebx, [ly1]
    je .put
    cmp eax, [lx0]
    je .put
    cmp eax, [lx1]
    jne .skip
.put:
    call cset
.skip:
    inc eax
    cmp eax, [lx1]
    jle .col
    inc ebx
    cmp ebx, [ly1]
    jle .row
    popad
    ret

; eax, ebx: flood fill of the area of one colour with [lc]
; (scanlines, with a stack of seeds on the heap)
cfill:
    pushad
    call cget
    jc .r
    cmp cl, [lc]
    je .r
    mov [lold], cl
    mov edi, [stack]
    xor ebp, ebp                ; entries
    call .push
.pop:
    test ebp, ebp
    jz .r
    dec ebp
    movzx eax, word [edi+ebp*4]
    movzx ebx, word [edi+ebp*4+2]
    call cget
    cmp cl, [lold]
    jne .pop
.left:                          ; to the start of the run
    test eax, eax
    jz .run
    dec eax
    call cget
    inc eax
    cmp cl, [lold]
    jne .run
    dec eax
    jmp .left
.run:
    mov byte [up_], 0
    mov byte [down_], 0
.go:
    call cget
    jc .pop
    cmp cl, [lold]
    jne .pop
    mov cl, [lc]
    call cset
    ; above
    test ebx, ebx
    jz .below
    dec ebx
    call cget
    inc ebx
    cmp cl, [lold]
    jne .noup
    cmp byte [up_], 0
    jne .below
    dec ebx
    call .push
    inc ebx
    mov byte [up_], 1
    jmp .below
.noup:
    mov byte [up_], 0
.below:
    inc ebx
    call cget
    dec ebx
    jc .nxt
    cmp cl, [lold]
    jne .nodn
    cmp byte [down_], 0
    jne .nxt
    inc ebx
    call .push
    dec ebx
    mov byte [down_], 1
    jmp .nxt
.nodn:
    mov byte [down_], 0
.nxt:
    inc eax
    jmp .go
.r:
    popad
    ret
.push:
    cmp ebp, STACK_MAX
    jae .full
    mov [edi+ebp*4], ax
    mov [edi+ebp*4+2], bx
    inc ebp
.full:
    ret

; ---------- tools ----------
; eax, ebx = a canvas point: what the tool does there.
act:
    pushad
    mov ecx, [tool]
    cmp ecx, T_PEN
    je .pen
    cmp ecx, T_ERASE
    je .pen
    cmp ecx, T_FILL
    je .fill
    cmp byte [anchor], 0        ; Line, Box, Solid: corners
    jne .second
    mov [ax_], eax
    mov [ay_], ebx
    mov byte [anchor], 1
    popad
    ret
.second:
    mov byte [anchor], 0
    call keep_undo
    mov ecx, eax
    mov edx, ebx
    mov eax, [ax_]
    mov ebx, [ay_]
    call shape
    mov byte [dirty], 1
    popad
    ret
.pen:
    cmp byte [pendown], 0
    jne .up
    call keep_undo
    mov [px_], eax
    mov [py_], ebx
    mov ecx, eax
    mov edx, ebx
    call stroke                 ; a dot
    mov byte [pendown], 1
    popad
    ret
.up:
    mov byte [pendown], 0
    popad
    ret
.fill:
    call keep_undo
    mov cl, [colour]
    mov [lc], cl
    call cfill
    mov byte [dirty], 1
    popad
    ret

; eax, ebx -> ecx, edx with the current shape tool, in [colour]
shape:
    pushad
    mov dl, [colour]            ; (ecx and edx are the second corner:
    mov [lc], dl                ; only dl may change before it is read)
    mov edx, [esp+20]
    cmp dword [tool], T_LINE
    jne .box
    call cline
    popad
    ret
.box:
    mov byte [solid], 0
    cmp dword [tool], T_SOLID
    jne .b
    mov byte [solid], 1
.b:
    call cbox
    popad
    ret

clamp_cross:
    mov eax, [kx]
    test eax, eax
    jns .a
    xor eax, eax
.a:
    cmp eax, CW_
    jb .b
    mov eax, CW_ - 1
.b:
    mov [kx], eax
    mov eax, [ky]
    test eax, eax
    jns .c
    xor eax, eax
.c:
    cmp eax, CH_
    jb .d
    mov eax, CH_ - 1
.d:
    mov [ky], eax
    ret

; gui_mx, gui_my -> eax, ebx on the canvas, CF if off it
to_canvas:
    mov eax, [gui_mx]
    sub eax, CX_
    jb .no
    cmp eax, CW_
    jae .no
    mov ebx, [gui_my]
    sub ebx, CY_
    jb .no
    cmp ebx, CH_
    jae .no
    clc
    ret
.no:
    stc
    ret

; A click off the canvas: a tool button or a palette swatch
ui_click:
    pushad
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    sub eax, TB_X
    jb .pal
    cmp eax, TB_W
    jae .pal
    sub ebx, CY_
    jb .r
    xor edx, edx
    mov eax, ebx
    mov ecx, TB_H + 2
    div ecx
    cmp eax, TOOLS
    jae .r
    mov [tool], eax
    mov byte [anchor], 0
    mov byte [pendown], 0
    jmp .r
.pal:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    sub ebx, PAL_Y
    jb .r
    cmp ebx, SW_H
    jae .r
    sub eax, CX_
    jb .r
    xor edx, edx
    mov ecx, SW_W
    div ecx
    cmp eax, 16
    jae .r
    mov al, [bmp_ega+eax]
    mov [colour], al
.r:
    popad
    ret

; ---------- drawing ----------
draw:
    pushad
    mov edi, line
    mov esi, title
    call scopy
    cmp byte [name], 0
    je .t
    mov esi, s_dash
    call scopy
    mov esi, name
    call scopy
.t:
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, line
    call gui_window
    ; tool buttons; the current one pressed
    xor ebp, ebp
.tb:
    mov eax, TB_X
    imul ebx, ebp, TB_H + 2
    add ebx, CY_
    mov ecx, TB_W
    mov edx, TB_H
    mov byte [gui_bevel_up], 1
    cmp ebp, [tool]
    jne .tbu
    mov byte [gui_bevel_up], 0
.tbu:
    mov esi, [tool_names+ebp*4]
    call gui_button
    inc ebp
    cmp ebp, TOOLS
    jb .tb
    ; the current colour, under the buttons
    mov eax, TB_X
    mov ebx, CY_ + TOOLS * (TB_H + 2) + 4
    mov ecx, TB_W
    mov edx, 20
    mov byte [gui_ink], C_BLACK
    call gui_box
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    mov dl, [colour]
    mov [gui_ink], dl
    mov edx, 18
    call gui_fill
    ; the canvas
    mov esi, [canvas]
    xor ebx, ebx
.cr:
    xor eax, eax
.cc:
    mov cl, [esi]
    inc esi
    push eax
    push ebx
    add eax, CX_
    add ebx, CY_
    call gui_pset
    pop ebx
    pop eax
    inc eax
    cmp eax, CW_
    jb .cc
    inc ebx
    cmp ebx, CH_
    jb .cr
    mov eax, CX_ - 1
    mov ebx, CY_ - 1
    mov ecx, CW_ + 2
    mov edx, CH_ + 2
    mov byte [gui_ink], C_BLACK
    call gui_box
    ; a started shape: the outline from the first corner to the cross
    cmp byte [anchor], 0
    je .cross
    call preview
.cross:
    call cross
    ; the palette
    xor ebp, ebp
.sw:
    imul eax, ebp, SW_W
    add eax, CX_
    mov ebx, PAL_Y
    mov ecx, SW_W - 2
    mov edx, SW_H
    mov dl, [bmp_ega+ebp]
    mov [gui_ink], dl
    mov edx, SW_H
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov dl, [bmp_ega+ebp]
    cmp dl, [colour]
    jne .swn
    dec eax
    dec ebx
    add ecx, 2
    add edx, 2
    call gui_box
.swn:
    inc ebp
    cmp ebp, 16
    jb .sw
    ; the status row
    mov edi, line
    mov ebp, [tool]
    mov esi, [tool_names+ebp*4]
    call scopy
    mov ax, '  '
    stosw
    mov eax, [kx]
    call gui_utoa
    mov al, ','
    stosb
    mov eax, [ky]
    call gui_utoa
    cmp byte [dirty], 0
    je .cl
    mov ax, ' *'
    stosw
.cl:
    mov ax, '  '
    stosw
    mov esi, [msg]
    test esi, esi
    jnz .m
    mov esi, s_help
    cmp byte [anchor], 0
    je .m
    mov esi, s_second
.m:
    call scopy
    mov esi, line
    mov eax, TB_X
    mov ebx, STAT_Y
    mov ecx, SCR_W - 6
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    mov dword [msg], 0
    call gui_flip
    popad
    ret

; The keyboard cross at kx, ky: dark on light pixels, white on dark ones.
cross:
    pushad
    mov eax, [kx]
    mov ebx, [ky]
    call cget
    mov dl, C_BLACK
    cmp cl, C_WHITE
    je .c
    cmp cl, C_YELLOW
    je .c
    cmp cl, C_LGREY
    je .c
    mov dl, C_WHITE
.c:
    mov [gui_ink], dl
    add eax, CX_
    add ebx, CY_
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
    popad
    ret

; The outline of the shape being made, on the screen only.
preview:
    pushad
    mov eax, CX_
    mov ebx, CY_
    mov ecx, CW_
    mov edx, CH_
    call gui_clip
    mov dl, [colour]
    mov [gui_ink], dl
    mov eax, [ax_]
    mov ebx, [ay_]
    mov ecx, [kx]
    mov edx, [ky]
    add eax, CX_
    add ebx, CY_
    add ecx, CX_
    add edx, CY_
    cmp dword [tool], T_LINE
    jne .box
    call gui_line
    jmp .r
.box:
    cmp eax, ecx
    jle .x
    xchg eax, ecx
.x:
    cmp ebx, edx
    jle .y
    xchg ebx, edx
.y:
    sub ecx, eax
    inc ecx
    sub edx, ebx
    inc edx
    call gui_box
.r:
    call gui_noclip
    popad
    ret

; ---------- files ----------
save:
    pushad
    cmp byte [name], 0
    jne .go
    mov esi, q_save
    call ask_name
    jc .r
.go:
    mov esi, name
    mov edi, [canvas]
    mov ecx, CW_
    mov edx, CH_
    call bmp_save16
    jc .fail
    mov byte [dirty], 0
    mov dword [msg], m_saved
.r:
    popad
    ret
.fail:
    mov dword [msg], m_nosave
    popad
    ret

; name -> the canvas: any 8- or 24-bit BMP, each pixel the nearest of the
; 16 colours; larger pictures are cut, smaller ones sit at the top left.
open_file:
    pushad
    mov esi, name
    call bmp_load
    jc .fail
    call keep_undo
    call clear_canvas
    xor ebx, ebx
.row:
    xor eax, eax
.col:
    push eax
    call bmp_rgb
    call bmp_near16
    mov cl, al
    pop eax
    call cset
    inc eax
    cmp eax, CW_
    jb .col
    inc ebx
    cmp ebx, CH_
    jb .row
    call bmp_free
    mov byte [dirty], 0
    mov dword [msg], m_opened
    popad
    ret
.fail:
    mov dword [msg], m_noopen
    popad
    ret

ask_unsaved:
    cmp byte [dirty], 0
    je .ok
    mov dword [msg], q_unsaved
    call draw
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .back
    or al, 0x20
    cmp al, 'n'
    je .ok
    cmp al, 'y'
    jne .k
    call save
    cmp byte [dirty], 0
    jne .back
.ok:
    clc
    ret
.back:
    stc
    ret

; esi = question -> name, typed on the status row. CF on Esc or nothing.
ask_name:
    pushad
    mov [ask_q], esi
    xor ecx, ecx
.d:
    mov byte [ask_buf+ecx], 0
    push ecx
    mov edi, line
    mov esi, [ask_q]
    call scopy
    mov esi, ask_buf
    call scopy
    mov al, '_'
    stosb
    mov byte [edi], 0
    mov eax, TB_X
    mov ebx, STAT_Y
    mov ecx, SCR_W - 6
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov esi, line
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
    pop ecx
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .no
    cmp ah, K_ENTER
    je .done
    cmp ah, K_BKSP
    je .bs
    cmp al, ' '
    jbe .k
    cmp al, '~'
    ja .k
    cmp ecx, NAME_MAX
    jae .k
    mov [ask_buf+ecx], al
    inc ecx
    jmp .d
.bs:
    jecxz .k
    dec ecx
    jmp .d
.done:
    jecxz .no
    mov esi, ask_buf
    mov edi, name
    call copy_name
    popad
    clc
    ret
.no:
    popad
    stc
    ret

copy_name:
    push ecx
    mov ecx, NAME_MAX
.c:
    lodsb
    cmp al, ' '
    jbe .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    pop ecx
    ret

; esi -> edi without the zero; edi ends where the zero would go
scopy:
    lodsb
    test al, al
    jz .r
    stosb
    jmp scopy
.r:
    mov byte [edi], 0
    ret

; ---------- self-check ----------
selftest:
    mov byte [bad], 'l'         ; a black line from (0, 0) to (50, 0)
    mov dword [tool], T_LINE
    mov byte [colour], C_BLACK
    xor eax, eax
    xor ebx, ebx
    call act
    mov eax, 50
    call act
    mov eax, 25
    xor ebx, ebx
    call cget
    cmp cl, C_BLACK
    jne .fail
    mov eax, 51
    call cget
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'b'         ; a red box (10, 10)-(30, 30): edge red,
    mov dword [tool], T_BOX     ; inside still white
    mov byte [colour], C_RED
    mov eax, 30
    mov ebx, 30
    call act
    mov eax, 10
    mov ebx, 10
    call act
    mov eax, 10
    mov ebx, 20
    call cget
    cmp cl, C_RED
    jne .fail
    mov eax, 20
    call cget
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'f'         ; fill its inside green: it stays inside
    mov dword [tool], T_FILL
    mov byte [colour], C_GREEN
    mov eax, 20
    mov ebx, 20
    call act
    call cget
    cmp cl, C_GREEN
    jne .fail
    mov eax, 11
    mov ebx, 29
    call cget
    cmp cl, C_GREEN
    jne .fail
    mov eax, 31
    mov ebx, 20
    call cget
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'u'         ; undo takes the fill back, undo again redoes
    call swap_undo
    mov eax, 20
    mov ebx, 20
    call cget
    cmp cl, C_WHITE
    jne .fail
    call swap_undo
    mov eax, 20
    call cget
    cmp cl, C_GREEN
    jne .fail
    mov byte [bad], 's'         ; a solid blue box (100, 100)-(120, 110)
    mov dword [tool], T_SOLID
    mov byte [colour], C_BLUE
    mov eax, 100
    mov ebx, 100
    call act
    mov eax, 120
    mov ebx, 110
    call act
    mov eax, 110
    mov ebx, 105
    call cget
    cmp cl, C_BLUE
    jne .fail
    mov byte [bad], 'e'         ; the eraser takes a dot of it out
    mov dword [tool], T_ERASE
    mov eax, 110
    mov ebx, 105
    call act
    call cget
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'd'         ; drawn on the screen as well
    call draw
    mov eax, CX_ + 20
    mov ebx, CY_ + 20
    call gui_peek
    cmp cl, C_GREEN
    jne .fail
    mov byte [bad], 'w'         ; save, clear, open: the same picture
    mov esi, t_name
    mov edi, name
    call scopy
    call save
    cmp byte [dirty], 0
    jne .fail
    mov esi, [canvas]           ; keep a copy (in the fill stack's room)
    mov edi, [stack]
    mov ecx, CW_ * CH_ / 4
    rep movsd
    call clear_canvas
    call open_file
    mov byte [bad], 'o'
    cmp dword [msg], m_opened
    jne .fail
    mov esi, [canvas]
    mov edi, [stack]
    mov ecx, CW_ * CH_
    repe cmpsb
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
tool_keys db 'plbsfe'
tool_names dd n_pen, n_line, n_box, n_solid, n_fill, n_erase
n_pen db 'Pen', 0
n_line db 'Line', 0
n_box db 'Box', 0
n_solid db 'Solid', 0
n_fill db 'Fill', 0
n_erase db 'Erase', 0
title db 'Paint', 0
s_dash db ' - ', 0
s_help db '^S save ^O open u undo Esc', 0
s_second db 'Space or click: second corner', 0
q_unsaved db 'Save changes? y/n', 0
q_save db 'Save as: ', 0
q_open db 'Open: ', 0
m_saved db 'Saved', 0
m_nosave db 'Not saved!', 0
m_opened db 'Opened', 0
m_noopen db 'Cannot open that', 0
m_nogfx db 'paint: no graphics or memory', 10, 0
t_name db 'ptest.bmp', 0
pass db 'paint: PASS', 10, 0
fail db 'paint: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
BMP_BSS
arg resd 1
canvas resd 1
undo resd 1
stack resd 1
tool resd 1
kx resd 1
ky resd 1
px_ resd 1
py_ resd 1
ax_ resd 1
ay_ resd 1
lx0 resd 1
ly0 resd 1
lx1 resd 1
ly1 resd 1
ldx resd 1
ldy resd 1
msg resd 1
ask_q resd 1
colour resb 1
lc resb 1
lold resb 1
up_ resb 1
down_ resb 1
solid resb 1
anchor resb 1
pendown resb 1
mouse_pen resb 1
dirty resb 1
can_undo resb 1
name resb NAME_MAX + 1
ask_buf resb NAME_MAX + 1
line resb 96
SQX_END
