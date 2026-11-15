; Squirrel-OS/2 — guitest: self-check of SYS_GUI and gui.inc (OS2-APPS)
; Original code.
;
; Opens graphics mode, draws a window with a title and a line of text into
; the back buffer, copies it to the screen, and reads pixels back from the
; screen: a frame pixel, the title bar, an ink pixel of the text's first
; glyph and the client area beside it. Also checks that a key poll with
; nothing typed gives 0, that the clock ticks and the date looks sane,
; that GUI_EVAL computes 2^10 and reports a syntax error, and, in ring 3,
; that SYS_GUI refuses buffers in kernel memory (-1), then returns to
; text mode and prints "guitest: PASS" (or FAIL and the first bad check).
; "run guitest hold" waits for a key before leaving graphics mode, so the
; regression run can read the window's text.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

GT_X equ 40
GT_Y equ 30
GT_W equ 200
GT_H equ 100

main:
    mov eax, [esp+4]            ; the argument string
    mov [arg], eax
    call gui_open
    jc .nogfx
    mov al, C_CYAN
    call gui_clear
    mov eax, GT_X
    mov ebx, GT_Y
    mov ecx, GT_W
    mov edx, GT_H
    mov esi, title
    call gui_window
    mov eax, [gui_cx]
    add eax, 4
    mov ebx, [gui_cy]
    add ebx, 4
    mov esi, hello
    call gui_text
    call gui_flip

    mov byte [bad], 'f'         ; the frame: white
    mov eax, GT_X
    mov ebx, GT_Y + 50
    call gui_peek
    cmp cl, C_WHITE
    jne .fail
    mov byte [bad], 'b'         ; the title bar: blue
    mov eax, GT_X + GT_W - 3
    mov ebx, GT_Y + 2
    call gui_peek
    cmp cl, C_BLUE
    jne .fail
    mov byte [bad], 'i'         ; 'H': column 0 is ink on every row
    mov eax, [gui_cx]
    add eax, 4
    mov ebx, [gui_cy]
    add ebx, 4 + 3
    call gui_peek
    cmp cl, C_BLACK
    jne .fail
    mov byte [bad], 'c'         ; the client area, right of the text
    mov eax, GT_X + GT_W - 10
    mov ebx, GT_Y + 60
    call gui_peek
    cmp cl, C_LGREY
    jne .fail
    mov byte [bad], 'd'         ; the desktop outside the window
    mov eax, 5
    mov ebx, 5
    call gui_peek
    cmp cl, C_CYAN
    jne .fail

    mov byte [bad], 'k'         ; no key typed yet
    mov eax, [arg]
    test eax, eax
    jz .poll
    cmp byte [eax], 'h'
    je .hold
.poll:
    call gui_pollkey
    test eax, eax
    jnz .fail
    jmp .clock
.hold:
    call gui_getkey             ; the regression run reads the screen here
.clock:
    mov byte [bad], 't'         ; ticks advance
    call gui_ticks
    mov esi, eax
    mov ecx, 5
    call gui_waitkey
    call gui_ticks
    cmp eax, esi
    je .fail
    mov byte [bad], 'y'         ; a year after 2000
    mov eax, SYS_GUI
    mov ebx, GUI_DATE
    int 0x80
    shr eax, 16
    cmp eax, 2000
    jb .fail
    mov byte [bad], 'e'         ; GUI_EVAL: 2^10 = 1024
    mov dword [ev+GE_EXPR], expr
    mov dword [ev+GE_TEXT], outbuf
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    test eax, eax
    jnz .fail
    cmp dword [outbuf], '1024'
    jne .fail
    mov byte [bad], 's'         ; and a syntax error at column 4
    mov dword [ev+GE_EXPR], expr_bad
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    cmp eax, -1
    jne .fail
    cmp dword [ev+GE_COL], 4
    jne .fail
    mov byte [bad], 'x'         ; x as a variable: x^2 at x = 3
    mov dword [ev+GE_EXPR], expr_x
    mov dword [ev+GE_FLAGS], GEF_X
    fld dword [three]
    fstp qword [ev+GE_X]
    mov eax, SYS_GUI
    mov ebx, GUI_EVAL
    mov ecx, ev
    int 0x80
    test eax, eax
    jnz .fail
    cmp word [outbuf], '9'
    jne .fail

    mov ax, cs                  ; ring 3 (2.4): kernel pointers are refused
    test al, 3
    jz .done
    mov byte [bad], 'p'
    mov ebp, refuse
.ref:
    mov ebx, [ebp]
    cmp ebx, -1
    je .done
    mov eax, [ebp+12]           ; patch the eval block or the rect block
    test eax, eax
    jz .call
    mov edx, [ebp+16]
    mov [eax], edx
.call:
    mov eax, SYS_GUI
    mov ecx, [ebp+4]
    mov edx, [ebp+8]
    int 0x80
    cmp eax, -1
    jne .fail
    inc byte [bad]
    add ebp, 20
    jmp .ref
.done:
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
.nogfx:
    mov esi, nogfx
    call gui_puts
    mov eax, 1
    ret

KMEM equ 0x8000                 ; the kernel's low image
; op, ecx, edx, address to patch first (0: none), value: each must give -1
refuse:
    dd GUI_FONT, KMEM, 0, 0, 0                          ; p
    dd GUI_PALETTE, 64 | 1 << 16, KMEM, 0, 0            ; q
    dd GUI_BLIT, KMEM, 0, 0, 0                          ; r: the block
    dd GUI_READ, rb, 0, rb+16, KMEM                     ; s: its buffer
    dd GUI_READ, rb, 0, rb+16, 0x3FFF0                  ; t: past the program
    dd GUI_EVAL, KMEM, 0, 0, 0                          ; u: the block
    dd GUI_EVAL, ev, 0, ev+GE_TEXT, KMEM                ; v: the text buffer
    dd GUI_EVAL, ev, 0, ev+GE_EXPR, KMEM                ; w: the expression
    dd -1
rb dd 0, 0, 8, 8, 0, 8          ; x y w h buffer pitch

title db 'Gui test', 0
hello db 'Hello from a program', 0
expr db '2^10', 0
expr_bad db '2 +', 0
expr_x db 'x^2', 0
three dd 3.0
pass db 'guitest: PASS', 10, 0
fail db 'guitest: FAIL ', 0
nogfx db 'guitest: no graphics', 10, 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
arg resd 1
ev resb GE_SIZE
outbuf resb 40
SQX_END
