; Squirrel-OS/2 — Calculator in a window (A.1, OS2-APPS)
; Original code. run calculator
;
; A graphical calculator with a standard and a scientific keypad, on the
; kernel's sci engine (SYS_GUI GUI_EVAL), so it takes the same expressions
; as `sci`: + - * / ^, parentheses, pi, e, ans and sin cos tan asin acos
; atan sqrt ln log exp abs. Keys and the mouse both work:
;
;   typing          adds to the expression     Enter or =   computes it
;   Backspace       removes the last character Delete       clears
;   arrows          move the keypad focus      Space        presses it
;   Tab             standard <-> scientific    F2           degrees <-> radians
;   Esc             quits                      left click   presses a key
;
; After a result, an operator continues from it (ans); anything else
; starts a new expression. See documentation/apps/gui-programs.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

COLS        equ 6               ; keypad columns in scientific mode
ROWS        equ 5
STD_FIRST   equ 2               ; the standard keypad is columns 2-5
BTN_W       equ 28
BTN_H       equ 18
PITCH_X     equ 31
PITCH_Y     equ 21
DISP_H      equ 3 * CELL_H + 8
WIN_H       equ 2 + WIN_TITLE_H + 4 + DISP_H + 4 + ROWS * PITCH_Y + CELL_H + 4
EXPR_MAX    equ 60

K_CLEAR     equ 1               ; special keypad keys (below 16: not text)
K_DEGRAD    equ 2
K_EQUALS    equ 3

main:
    call gui_open
    jc .nogfx
    mov byte [sci], 0
    mov dword [focus], 2 * COLS + 2 ; the key '4'
.redraw:
    call layout
    call draw
.loop:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    mov ebx, eax
    shr ebx, 8
    and ebx, 0xFF               ; scancode
    cmp bl, K_ESC
    je .quit
    cmp bl, K_TAB
    je .mode
    cmp bl, K_F2
    je .degrad
    cmp bl, K_ENTER
    je .equals
    cmp bl, K_BKSP
    je .back
    cmp bl, K_DEL
    je .clear
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    and eax, 0xFF
    cmp al, ' '
    je .space
    cmp al, '='
    je .equals
    cmp al, ' '
    jb .loop
    cmp al, '~'
    ja .loop
    mov [onechar], al
    mov esi, onechar
    call add_text
    jmp .show
.space:
    mov eax, [focus]
    call press
    jmp .show
.click:
    call hit
    jc .loop
    mov [focus], eax
    call press
    jmp .show
.equals:
    call compute
    jmp .show
.back:
    call unresult
    mov ecx, [len]
    jecxz .show
    dec dword [len]
    mov byte [expr+ecx-1], 0
    jmp .show
.clear:
    call clear
    jmp .show
.mode:
    xor byte [sci], 1
    call clamp_focus
    jmp .redraw
.degrad:
    xor byte [deg], 1
    jmp .show
.left:
    dec dword [focus]
    jmp .clamp
.right:
    inc dword [focus]
    jmp .clamp
.up:
    sub dword [focus], COLS
    jmp .clamp
.down:
    add dword [focus], COLS
.clamp:
    call clamp_focus
.show:
    call draw
    jmp .loop
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, msg_nogfx
    call gui_puts
    mov eax, 1
    ret

; Keeps the focus on a key of the keypad shown (wrapping by rows).
clamp_focus:
    mov eax, [focus]
    test eax, eax
    jns .lo
    add eax, COLS * ROWS
.lo:
    cmp eax, COLS * ROWS
    jb .hi
    sub eax, COLS * ROWS
.hi:
    cmp byte [sci], 0
    jne .ok
    xor edx, edx
    mov ecx, COLS
    push eax
    div ecx                     ; edx = column
    pop eax
    cmp edx, STD_FIRST
    jae .ok
    sub eax, edx
    add eax, STD_FIRST          ; a scientific column: to the first standard one
.ok:
    mov [focus], eax
    ret

; Window size and place for the mode.
layout:
    mov eax, (COLS - STD_FIRST) * PITCH_X + 3 + 2 + 4
    cmp byte [sci], 0
    je .w
    mov eax, COLS * PITCH_X + 3 + 2 + 4
.w:
    mov [win_w], eax
    mov ebx, SCR_W
    sub ebx, eax
    shr ebx, 1
    mov [win_x], ebx
    mov dword [win_y], (SCR_H - WIN_H) / 2
    ret

; The whole window into the buffer, then onto the screen.
draw:
    pushad
    mov al, C_CYAN
    call gui_clear
    mov eax, [win_x]
    mov ebx, [win_y]
    mov ecx, [win_w]
    mov edx, WIN_H
    mov esi, title
    call gui_window
    ; the display: white, sunken
    mov eax, [gui_cx]
    add eax, 3
    mov ebx, [gui_cy]
    add ebx, 3
    mov ecx, [gui_cw]
    sub ecx, 6
    mov edx, DISP_H
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_bevel_up], 0
    call gui_bevel
    mov [disp_x], eax
    mov [disp_y], ebx
    mov [disp_w], ecx
    call draw_display
    ; the keypad
    xor ebp, ebp
.key:
    mov eax, ebp
    call key_rect
    jc .nextkey
    mov byte [gui_bevel_up], 1
    mov esi, [keys+ebp*8]
    call gui_button
    cmp ebp, [focus]
    jne .nextkey
    dec eax                     ; the focus: a black outline round the key
    dec ebx
    add ecx, 2
    add edx, 2
    mov byte [gui_ink], C_BLACK
    call gui_box
.nextkey:
    inc ebp
    cmp ebp, COLS * ROWS
    jb .key
    ; the help row and the angle mode
    mov eax, [gui_cx]
    add eax, 3
    mov ebx, [gui_cy]
    add ebx, [gui_ch]
    sub ebx, CELL_H + 2
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov esi, help
    mov ecx, [gui_cw]
    sub ecx, 3 + 4 * CELL_W
    call gui_textn
    mov eax, [gui_cx]
    add eax, [gui_cw]
    sub eax, 3 * CELL_W + 3
    mov esi, s_rad
    cmp byte [deg], 0
    je .ang
    mov esi, s_deg
.ang:
    call gui_text
    call gui_flip
    popad
    ret

; The expression (its last part when it is long) and the result line.
draw_display:
    pushad
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    mov eax, [disp_w]
    sub eax, 6
    xor edx, edx
    mov ecx, CELL_W
    div ecx
    mov ecx, eax                ; characters that fit
    mov esi, expr
    mov eax, [len]
    sub eax, ecx
    jbe .all
    add esi, eax
.all:
    mov eax, [disp_x]
    add eax, 3
    mov ebx, [disp_y]
    add ebx, 3
    call gui_text
    ; the result, right-aligned on the second row; one too long for it
    ; is broken at a space onto the third row
    add ebx, CELL_H + 1
    mov esi, result
    call gui_textw
    mov edx, [disp_w]
    sub edx, 6
    cmp eax, edx
    jg .wrap
    mov ecx, [disp_w]
    sub ecx, 3
    sub ecx, eax
    mov eax, [disp_x]
    add eax, ecx
    call gui_text
    popad
    ret
.wrap:
    mov eax, edx
    xor edx, edx
    mov ecx, CELL_W
    div ecx                     ; characters on a row
    mov ecx, eax
.space:
    cmp byte [result+ecx], ' '  ; the last space that fits
    je .cut
    loop .space
    mov ecx, eax                ; none: cut anywhere
.cut:
    mov dl, [result+ecx]
    mov byte [result+ecx], 0
    mov eax, [disp_x]
    add eax, 3
    call gui_text
    mov [result+ecx], dl
    lea esi, [result+ecx]
    cmp dl, ' '
    jne .rest
    inc esi
.rest:
    add ebx, CELL_H + 1
    mov ecx, [disp_w]
    sub ecx, 6
    call gui_textn
    popad
    ret

; eax = key index -> eax, ebx, ecx, edx = its rectangle; CF if the key is
; not on the keypad shown.
key_rect:
    push esi
    xor edx, edx
    mov ecx, COLS
    div ecx                     ; eax = row, edx = column
    cmp byte [sci], 0
    jne .sci
    sub edx, STD_FIRST
    jb .no
.sci:
    imul ecx, edx, PITCH_X
    add ecx, [gui_cx]
    add ecx, 4
    imul ebx, eax, PITCH_Y
    add ebx, [disp_y]
    add ebx, DISP_H + 4
    mov eax, ecx
    mov ecx, BTN_W
    mov edx, BTN_H
    pop esi
    clc
    ret
.no:
    pop esi
    stc
    ret

; gui_mx, gui_my -> eax = the key under the pointer; CF if none.
hit:
    xor ebp, ebp
.k:
    mov eax, ebp
    call key_rect
    jc .n
    mov esi, [gui_mx]
    sub esi, eax
    jb .n
    cmp esi, ecx
    jae .n
    mov esi, [gui_my]
    sub esi, ebx
    jb .n
    cmp esi, edx
    jae .n
    mov eax, ebp
    clc
    ret
.n:
    inc ebp
    cmp ebp, COLS * ROWS
    jb .k
    stc
    ret

; eax = key index: what the key does.
press:
    mov esi, [keys+eax*8+4]
    cmp esi, K_CLEAR
    je clear
    cmp esi, K_DEGRAD
    je .dr
    cmp esi, K_EQUALS
    je compute
    jmp add_text
.dr:
    xor byte [deg], 1
    ret

clear:
    mov dword [len], 0
    mov byte [expr], 0
    mov byte [result], 0
    mov byte [shown], 0
    ret

; After a result: forget it before the expression is edited.
unresult:
    cmp byte [shown], 0
    je .r
    mov byte [shown], 0
    mov byte [result], 0
.r:
    ret

; esi = text to add to the expression. Just after a result, an operator
; continues from ans and anything else starts afresh.
add_text:
    cmp byte [shown], 0
    je .add
    mov al, [esi]
    push esi
    mov edi, ops
    mov ecx, ops_n
    repne scasb
    pop esi
    pushfd
    call clear
    popfd
    jne .add
    push esi
    mov esi, s_ans
    call .append
    pop esi
.add:
.append:
    mov edi, [len]
.c:
    lodsb
    test al, al
    jz .done
    cmp edi, EXPR_MAX
    jae .done
    mov [expr+edi], al
    inc edi
    jmp .c
.done:
    mov byte [expr+edi], 0
    mov [len], edi
    ret

; Evaluates the expression with the sci engine: "= value", or the error.
compute:
    cmp dword [len], 0
    je .r
    mov dword [ev+GE_EXPR], expr
    mov eax, GEF_ANS
    cmp byte [deg], 0
    je .f
    or eax, GEF_DEG
.f:
    mov [ev+GE_FLAGS], eax
    mov dword [ev+GE_TEXT], val
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    mov edi, result
    test eax, eax
    jnz .err
    mov word [edi], '= '
    add edi, 2
    mov esi, val
    call strcpy
    mov byte [shown], 1
.r:
    ret
.err:
    mov esi, s_error
    call strcpy
    mov esi, val
    call strcpy
    cmp byte [edi-1], ' '       ; "syntax at column ": add the column
    jne .r
    mov eax, [ev+GE_COL]
    call gui_utoa
    ret

; esi -> edi, zero-terminated; edi ends on the zero.
strcpy:
    lodsb
    stosb
    test al, al
    jnz strcpy
    dec edi
    ret

; ---------- data ----------
; Keypad, row by row: label, then the text it adds or a K_* code.
keys:
    dd l_sin, t_sin,   l_sqrt, t_sqrt,  l_c, K_CLEAR, l_lp, l_lp,  l_rp, l_rp,  l_div, l_div
    dd l_cos, t_cos,   l_pow, l_pow,    l_7, l_7,     l_8, l_8,    l_9, l_9,    l_mul, l_mul
    dd l_tan, t_tan,   l_pi, l_pi,      l_4, l_4,     l_5, l_5,    l_6, l_6,    l_sub, l_sub
    dd l_ln, t_ln,     l_e, l_e,        l_1, l_1,     l_2, l_2,    l_3, l_3,    l_add, l_add
    dd l_log, t_log,   l_dr, K_DEGRAD,  l_0, l_0,     l_dot, l_dot, s_ans, s_ans, l_eq, K_EQUALS

l_sin db 'sin', 0
t_sin db 'sin(', 0
l_cos db 'cos', 0
t_cos db 'cos(', 0
l_tan db 'tan', 0
t_tan db 'tan(', 0
l_ln db 'ln', 0
t_ln db 'ln(', 0
l_log db 'log', 0
t_log db 'log(', 0
l_sqrt db 'sqrt', 0
t_sqrt db 'sqrt(', 0
l_pow db '^', 0
l_pi db 'pi', 0
l_e db 'e', 0
l_dr db 'D/R', 0
l_c db 'C', 0
l_lp db '(', 0
l_rp db ')', 0
l_div db '/', 0
l_mul db '*', 0
l_sub db '-', 0
l_add db '+', 0
l_eq db '=', 0
l_dot db '.', 0
l_0 db '0', 0
l_1 db '1', 0
l_2 db '2', 0
l_3 db '3', 0
l_4 db '4', 0
l_5 db '5', 0
l_6 db '6', 0
l_7 db '7', 0
l_8 db '8', 0
l_9 db '9', 0
s_ans db 'ans', 0
ops db '+-*/^%'
ops_n equ $ - ops

title db 'Calculator', 0
help db 'Tab:mode Esc:quit', 0
s_rad db 'RAD', 0
s_deg db 'DEG', 0
s_error db 'Error: ', 0
msg_nogfx db 'calculator: no graphics', 10, 0

SQX_BSS
GUI_BSS
sci resb 1
deg resb 1
shown resb 1
onechar resb 2
alignb 4
focus resd 1
len resd 1
win_x resd 1
win_y resd 1
win_w resd 1
disp_x resd 1
disp_y resd 1
disp_w resd 1
ev resb GE_SIZE
expr resb EXPR_MAX + 1
result resb 64
val resb 40
SQX_END
