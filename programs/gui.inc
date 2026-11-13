; Squirrel-OS/2 — graphics toolkit for programs (OS2-APPS)
; Original code. Include after SQX_HEADER:
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     %include "gui.inc"    ; after the header: it holds code
;     main: call gui_open ... call gui_flip ... call gui_close
;     ...
;     SQX_BSS
;     GUI_BSS               ; the toolkit's zeroed data
;     SQX_END
;
; The program draws into a 320 x 200 back buffer (one byte a pixel, from
; SYS_SBRK) and gui_flip copies it to the screen with SYS_GUI. Text uses
; the kernel's 5 x 7 font in 6 x 8 cells, so tools/qemu_screen.py <gfx>
; reads it. Every routine keeps all registers unless it says otherwise.
; See documentation/kernel/syscalls.md (SYS_GUI) and documentation/apps/.

SYS_GUI     equ 35
GUI_ENTER   equ 0
GUI_LEAVE   equ 1
GUI_BLIT    equ 2
GUI_READ    equ 3
GUI_KEY     equ 4
GUI_MOUSE   equ 5
GUI_FONT    equ 6
GUI_TICKS   equ 7
GUI_TIME    equ 8
GUI_DATE    equ 9
GUI_EVAL    equ 10

SCR_W       equ 320
SCR_H       equ 200
CELL_W      equ 6
CELL_H      equ 8
FONT_FIRST  equ 0x20
FONT_LAST   equ 0x7E
FONT_H      equ 7

; key scancodes (bits 8-15 of a GUI_KEY result)
K_ESC       equ 0x01
K_BKSP      equ 0x0E
K_TAB       equ 0x0F
K_ENTER     equ 0x1C
K_F1        equ 0x3B
K_F2        equ 0x3C
K_HOME      equ 0x47
K_UP        equ 0x48
K_PGUP      equ 0x49
K_LEFT      equ 0x4B
K_RIGHT     equ 0x4D
K_END       equ 0x4F
K_DOWN      equ 0x50
K_PGDN      equ 0x51
K_DEL       equ 0x53

; colours: the EGA palette mode 13h keeps (as the window manager uses it)
C_BLACK     equ 0x00
C_BLUE      equ 0x01
C_GREEN     equ 0x02
C_CYAN      equ 0x03
C_RED       equ 0x04
C_MAGENTA   equ 0x05
C_BROWN     equ 0x06
C_LGREY     equ 0x07
C_DGREY     equ 0x38
C_LBLUE     equ 0x39
C_LGREEN    equ 0x3A
C_LCYAN     equ 0x3B
C_LRED      equ 0x3C
C_LMAGENTA  equ 0x3D
C_YELLOW    equ 0x3E
C_WHITE     equ 0x3F

WIN_TITLE_H equ CELL_H + 2      ; as the kernel's WM_TITLE_H

; Eval block for GUI_EVAL (kernel/appsys.asm)
GE_EXPR     equ 0
GE_FLAGS    equ 4
GE_X        equ 8
GE_Y        equ 16
GE_RESULT   equ 24
GE_TEXT     equ 32
GE_COL      equ 36
GE_SIZE     equ 40
GEF_X       equ 1
GEF_XY      equ 2
GEF_DEG     equ 1 << 8
GEF_ANS     equ 1 << 9

; -> CF set if there is no memory for the buffer or for graphics.
; Otherwise the screen is in graphics mode and the buffer is clear.
gui_open:
    pushad
    cmp dword [gui_fb], 0
    jne .have
    mov eax, SYS_SBRK
    mov ebx, SCR_W * SCR_H
    int 0x80
    cmp eax, -1
    je .fail
    mov [gui_fb], eax
.have:
    mov eax, SYS_GUI
    mov ebx, GUI_FONT
    mov ecx, gui_font
    int 0x80
    mov eax, SYS_GUI
    mov ebx, GUI_ENTER
    int 0x80
    test eax, eax
    jnz .fail
    mov byte [gui_on], 1
    call gui_noclip
    mov ecx, 32                 ; drop keys typed before (the shell's Enter)
.drain:
    call gui_pollkey
    loop .drain
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov edi, [gui_fb]
    mov ecx, SCR_W * SCR_H / 4
    xor eax, eax
    rep stosd
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Back to text mode (the shell's screen as it was). Safe to call twice.
gui_close:
    pushad
    cmp byte [gui_on], 0
    je .r
    mov byte [gui_on], 0
    mov eax, SYS_GUI
    mov ebx, GUI_LEAVE
    int 0x80
.r:
    popad
    ret

; Copies the whole back buffer to the screen.
gui_flip:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    call gui_flip_rect
    cmp byte [gui_ptr_on], 0
    je .r
    call gui_ptr_show
.r:
    popad
    ret

; eax = x, ebx = y, ecx = w, edx = h: copies that part of the buffer.
gui_flip_rect:
    pushad
    mov [gui_blk], eax
    mov [gui_blk+4], ebx
    mov [gui_blk+8], ecx
    mov [gui_blk+12], edx
    imul ebx, SCR_W
    add ebx, eax
    add ebx, [gui_fb]
    mov [gui_blk+16], ebx
    mov dword [gui_blk+20], SCR_W
    mov eax, SYS_GUI
    mov ebx, GUI_BLIT
    mov ecx, gui_blk
    int 0x80
    popad
    ret

; eax = x, ebx = y -> cl = the colour on the screen (not the buffer), for
; self-checks that read back what really reached the display.
gui_peek:
    push eax
    push ebx
    push edx
    mov [gui_blk], eax
    mov [gui_blk+4], ebx
    mov dword [gui_blk+8], 1
    mov dword [gui_blk+12], 1
    mov dword [gui_blk+16], gui_peekb
    mov dword [gui_blk+20], 1
    mov eax, SYS_GUI
    mov ebx, GUI_READ
    mov ecx, gui_blk
    int 0x80
    movzx ecx, byte [gui_peekb]
    pop edx
    pop ebx
    pop eax
    ret

; eax = x, ebx = y, cl = colour. Outside the clip rectangle (the whole
; screen unless gui_clip set a smaller one): nothing.
gui_pset:
    cmp eax, [gui_clx0]
    jl .r
    cmp eax, [gui_clx1]
    jge .r
    cmp ebx, [gui_cly0]
    jl .r
    cmp ebx, [gui_cly1]
    jge .r
    push ebx
    imul ebx, SCR_W
    add ebx, [gui_fb]
    mov [ebx+eax], cl
    pop ebx
.r:
    ret

; eax = x, ebx = y, ecx = w, edx = h: drawing is clipped to this rectangle
; (within the screen) until the next gui_clip or gui_noclip.
gui_clip:
    push eax
    push ebx
    mov [gui_clx0], eax
    mov [gui_cly0], ebx
    add eax, ecx
    add ebx, edx
    mov [gui_clx1], eax
    mov [gui_cly1], ebx
    cmp dword [gui_clx0], 0
    jge .a
    mov dword [gui_clx0], 0
.a:
    cmp dword [gui_cly0], 0
    jge .b
    mov dword [gui_cly0], 0
.b:
    cmp eax, SCR_W
    jle .c
    mov dword [gui_clx1], SCR_W
.c:
    cmp ebx, SCR_H
    jle .d
    mov dword [gui_cly1], SCR_H
.d:
    pop ebx
    pop eax
    ret

; Drawing reaches the whole screen again.
gui_noclip:
    mov dword [gui_clx0], 0
    mov dword [gui_cly0], 0
    mov dword [gui_clx1], SCR_W
    mov dword [gui_cly1], SCR_H
    ret

; eax = x, ebx = y -> cl = the colour in the buffer (0 off the screen)
gui_pget:
    xor ecx, ecx
    cmp eax, SCR_W
    jae .r
    cmp ebx, SCR_H
    jae .r
    push ebx
    imul ebx, SCR_W
    add ebx, [gui_fb]
    mov cl, [ebx+eax]
    pop ebx
.r:
    ret

; eax = x, ebx = y, ecx = w, edx = h, colour [gui_ink]. Clipped.
gui_fill:
    pushad
    lea esi, [eax+ecx]
    lea edi, [ebx+edx]
    cmp esi, SCR_W
    jle .w
    mov esi, SCR_W
.w:
    cmp edi, SCR_H
    jle .h
    mov edi, SCR_H
.h:
    test eax, eax
    jns .x
    xor eax, eax
.x:
    test ebx, ebx
    jns .y
    xor ebx, ebx
.y:
    mov cl, [gui_ink]
    mov ebp, eax
.row:
    cmp ebx, edi
    jge .done
    mov eax, ebp
.col:
    cmp eax, esi
    jge .next
    call gui_pset
    inc eax
    jmp .col
.next:
    inc ebx
    jmp .row
.done:
    popad
    ret

; eax = x, ebx = y, ecx = w, edx = h: a one-pixel outline in [gui_ink]
gui_box:
    push eax
    mov al, [gui_ink]
    mov [gui_ink2], al
    pop eax
    jmp gui_edges

; A raised ([gui_bevel_up] = 1) or sunken (0) bevel round a rectangle,
; eax, ebx, ecx, edx as gui_box: white top and left, dark grey bottom and
; right when raised, the other way round when sunken.
gui_bevel:
    mov byte [gui_ink], C_WHITE
    mov byte [gui_ink2], C_DGREY
    cmp byte [gui_bevel_up], 0
    jne gui_edges
    mov byte [gui_ink], C_DGREY
    mov byte [gui_ink2], C_WHITE
; top and left in [gui_ink], bottom and right in [gui_ink2]
gui_edges:
    pushad
    push edx
    mov edx, 1
    call gui_fill               ; top
    pop edx
    push ecx
    mov ecx, 1
    call gui_fill               ; left
    pop ecx
    push dword [gui_ink]
    mov al, [gui_ink2]
    mov [gui_ink], al
    mov eax, [esp+4+28]
    push ebx
    lea ebx, [ebx+edx-1]
    push edx
    mov edx, 1
    call gui_fill               ; bottom
    pop edx
    pop ebx
    lea eax, [eax+ecx-1]
    mov ecx, 1
    call gui_fill               ; right
    pop dword [gui_ink]
    popad
    ret

; eax = x0, ebx = y0, ecx = x1, edx = y1 in [gui_ink] (Bresenham)
gui_line:
    pushad
    mov [gl_x1], ecx
    mov [gl_y1], edx
    mov esi, 1
    sub ecx, eax
    jge .dx
    neg ecx
    neg esi
.dx:
    mov [gl_dx], ecx
    mov edi, 1
    sub edx, ebx
    jge .dy
    neg edx
    neg edi
.dy:
    neg edx
    mov [gl_dy], edx
    add ecx, edx
    mov ebp, ecx                ; err = dx + dy
.plot:
    mov cl, [gui_ink]
    call gui_pset
    cmp eax, [gl_x1]
    jne .step
    cmp ebx, [gl_y1]
    je .done
.step:
    lea edx, [ebp+ebp]
    cmp edx, [gl_dy]
    jl .nx
    add ebp, [gl_dy]
    add eax, esi
.nx:
    cmp edx, [gl_dx]
    jg .plot
    add ebp, [gl_dx]
    add ebx, edi
    jmp .plot
.done:
    popad
    ret

; eax = x, ebx = y (top left of the 6 x 8 cell), dl = character.
; Ink [gui_ink], background [gui_bg]; the spacing column and the bottom
; row are background, as the kernel draws it. Font row bits: column 0 is
; bit 4.
gui_char:
    pushad
    movzx esi, dl
    cmp esi, FONT_FIRST
    jb .unk
    cmp esi, FONT_LAST
    jbe .ok
.unk:
    mov esi, '?'
.ok:
    sub esi, FONT_FIRST
    imul esi, FONT_H
    add esi, gui_font
    mov edi, eax                ; left edge
    xor ebp, ebp                ; row
.row:
    xor edx, edx
    cmp ebp, FONT_H
    jae .bits
    movzx edx, byte [esi+ebp]
.bits:
    shl edx, 1                  ; bit 5 = column 0 ... bit 1 = column 4, bit 0 clear
    mov eax, edi
.col:
    mov cl, [gui_bg]
    test edx, 1 << 5
    jz .put
    mov cl, [gui_ink]
.put:
    call gui_pset
    shl edx, 1
    inc eax
    lea ecx, [edi+CELL_W]
    cmp eax, ecx
    jb .col
    inc ebx
    inc ebp
    cmp ebp, CELL_H
    jb .row
    popad
    ret

; esi = zero-terminated string, eax = x, ebx = y
gui_text:
    pushad
.c:
    mov dl, [esi]
    test dl, dl
    jz .r
    call gui_char
    add eax, CELL_W
    inc esi
    jmp .c
.r:
    popad
    ret

; As gui_text, but at most ecx pixels wide (whole cells only).
gui_textn:
    pushad
    add ecx, eax
.c:
    mov dl, [esi]
    test dl, dl
    jz .r
    lea edi, [eax+CELL_W]
    cmp edi, ecx
    jg .r
    call gui_char
    mov eax, edi
    inc esi
    jmp .c
.r:
    popad
    ret

; esi = string -> eax = its width in pixels
gui_textw:
    push esi
    xor eax, eax
.c:
    cmp byte [esi], 0
    je .r
    add eax, CELL_W
    inc esi
    jmp .c
.r:
    pop esi
    ret

; A window in the window manager's look: eax = x, ebx = y, ecx = width,
; edx = height (outer), esi = title. A white frame, a blue title bar with
; the title in white, a light grey client area. Sets gui_cx/cy/cw/ch to
; the client area.
gui_window:
    pushad
    mov byte [gui_ink], C_WHITE
    call gui_fill
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    push edx
    mov edx, WIN_TITLE_H
    mov byte [gui_ink], C_BLUE
    call gui_fill
    pop edx
    push eax
    push ebx
    push ecx
    add eax, 2
    inc ebx
    sub ecx, 4
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLUE
    call gui_textn
    pop ecx
    pop ebx
    pop eax
    add ebx, WIN_TITLE_H
    sub edx, WIN_TITLE_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov [gui_cx], eax
    mov [gui_cy], ebx
    mov [gui_cw], ecx
    mov [gui_ch], edx
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    popad
    ret

; A push button: eax = x, ebx = y, ecx = w, edx = h, esi = label,
; [gui_bevel_up] 1 raised / 0 pressed. The label is centred.
gui_button:
    pushad
    push ecx
    push edx
    mov byte [gui_ink], C_LGREY
    call gui_fill
    call gui_bevel
    pop edx
    pop ecx
    push eax
    call gui_textw
    sub ecx, eax
    pop eax
    sar ecx, 1
    add eax, ecx
    sub edx, CELL_H
    sar edx, 1
    add ebx, edx
    cmp byte [gui_bevel_up], 0
    jne .t
    inc eax                     ; pressed: the label moves too
    inc ebx
.t:
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    popad
    ret

; Fills the whole buffer with colour al.
gui_clear:
    pushad
    mov ah, al
    mov ecx, eax
    shl eax, 16
    mov ax, cx
    mov edi, [gui_fb]
    mov ecx, SCR_W * SCR_H / 4
    rep stosd
    popad
    ret

; -> eax = a key (ASCII | scancode << 8 | Ctrl << 16), or 0 if none yet
gui_pollkey:
    push ebx
    mov eax, SYS_GUI
    mov ebx, GUI_KEY
    int 0x80
    pop ebx
    ret

; Waits for a key -> eax as gui_pollkey. Yields while waiting.
gui_getkey:
    call gui_pollkey
    test eax, eax
    jnz .r
    push eax
    mov eax, SYS_YIELD
    int 0x80
    pop eax
    jmp gui_getkey
.r:
    ret

; ecx = ticks to wait at most -> eax = a key, or 0 when the time ran out
gui_waitkey:
    push ebx
    push edx
    mov eax, SYS_GUI
    mov ebx, GUI_TICKS
    int 0x80
    mov edx, eax
.w:
    call gui_pollkey
    test eax, eax
    jnz .r
    mov eax, SYS_YIELD
    int 0x80
    mov eax, SYS_GUI
    mov ebx, GUI_TICKS
    int 0x80
    sub eax, edx
    cmp eax, ecx
    jb .w
    xor eax, eax
.r:
    pop edx
    pop ebx
    ret

; ---------- mouse ----------
; The pointer is drawn on the screen only, never into the back buffer:
; gui_flip puts it back on top after copying the buffer.
EV_CLICK    equ 0x80000000      ; gui_event: a left click at gui_mx, gui_my
PTR_W       equ 7
PTR_H       equ 10

; ecx = ticks to wait at most (0: no limit) -> eax = a key (as
; gui_pollkey), EV_CLICK for a left-button press (position in gui_mx /
; gui_my), or 0 when the time ran out. Moves the pointer as the mouse moves.
gui_event:
    push ebx
    push edx
    push esi
    call gui_ticks
    mov esi, eax
.w:
    call gui_pollkey
    test eax, eax
    jnz .r
    mov eax, SYS_GUI
    mov ebx, GUI_MOUSE
    int 0x80
    cmp eax, -1
    je .time
    mov edx, eax
    and edx, 0x3FF              ; x
    mov ebx, eax
    shr ebx, 10
    and ebx, 0x3FF              ; y
    cmp byte [gui_ptr_on], 0
    je .move
    cmp edx, [gui_mx]
    jne .move
    cmp ebx, [gui_my]
    je .btn
.move:
    call gui_ptr_hide
    mov [gui_mx], edx
    mov [gui_my], ebx
    call gui_ptr_show
.btn:
    shr eax, 20
    mov bl, [gui_btns]
    mov [gui_btns], al
    test al, 1
    jz .time
    test bl, 1
    jnz .time
    mov eax, EV_CLICK
    jmp .r
.time:
    test ecx, ecx
    jz .y
    call gui_ticks
    sub eax, esi
    cmp eax, ecx
    jb .y
    xor eax, eax
    jmp .r
.y:
    mov eax, SYS_YIELD
    int 0x80
    jmp .w
.r:
    pop esi
    pop edx
    pop ebx
    ret

; Copies the buffer under the pointer back to the screen.
gui_ptr_hide:
    cmp byte [gui_ptr_on], 0
    je .r
    pushad
    mov byte [gui_ptr_on], 0
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    call gui_ptr_clip
    call gui_flip_rect
    popad
.r:
    ret

; eax = x, ebx = y -> ecx = w, edx = h of the pointer's box, cut at the
; screen's right and bottom edges.
gui_ptr_clip:
    mov ecx, SCR_W
    sub ecx, eax
    cmp ecx, PTR_W
    jbe .h
    mov ecx, PTR_W
.h:
    mov edx, SCR_H
    sub edx, ebx
    cmp edx, PTR_H
    jbe .r
    mov edx, PTR_H
.r:
    ret

; Draws the pointer at gui_mx, gui_my on the screen: the buffer under it
; with the arrow on top, copied out in one block.
gui_ptr_show:
    pushad
    mov byte [gui_ptr_on], 1
    xor edx, edx                ; row
.row:
    xor ecx, ecx                ; column
.col:
    mov eax, [gui_mx]
    add eax, ecx
    mov ebx, [gui_my]
    add ebx, edx
    push ecx
    call gui_pget
    mov al, cl
    pop ecx
    movzx ebx, word [gui_arrow+edx*2]
    bt ebx, ecx                 ; outline: low byte
    jnc .fill
    mov al, C_BLACK
    jmp .put
.fill:
    push ecx
    add ecx, 8                  ; fill: high byte
    bt ebx, ecx
    pop ecx
    jnc .put
    mov al, C_WHITE
.put:
    imul ebx, edx, PTR_W
    mov [gui_ptrbuf+ebx+ecx], al
    inc ecx
    cmp ecx, PTR_W
    jb .col
    inc edx
    cmp edx, PTR_H
    jb .row
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    call gui_ptr_clip
    mov [gui_blk], eax
    mov [gui_blk+4], ebx
    mov [gui_blk+8], ecx
    mov [gui_blk+12], edx
    mov dword [gui_blk+16], gui_ptrbuf
    mov dword [gui_blk+20], PTR_W
    mov eax, SYS_GUI
    mov ebx, GUI_BLIT
    mov ecx, gui_blk
    int 0x80
    popad
    ret

; The arrow, one word a row: low byte black outline, high byte white fill
; (bit n = column n).
gui_arrow:
    dw 0x0001, 0x0003, 0x0205, 0x0609, 0x0E11, 0x1E21, 0x0E71, 0x040B
    dw 0x0012, 0x0018

; -> eax = ticks (100 a second)
gui_ticks:
    push ebx
    mov eax, SYS_GUI
    mov ebx, GUI_TICKS
    int 0x80
    pop ebx
    ret

; eax = unsigned number, edi = buffer -> the decimal text, zero-terminated;
; edi points at the zero afterwards.
gui_utoa:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.o:
    pop eax
    add al, '0'
    stosb
    loop .o
    mov byte [edi], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; eax = signed number, edi = buffer: as gui_utoa with a '-' if negative
gui_itoa:
    test eax, eax
    jns gui_utoa
    mov byte [edi], '-'
    inc edi
    push eax
    neg eax
    call gui_utoa
    pop eax
    ret

; esi = zero-terminated string -> prints it on the text screen
gui_puts:
    pushad
    mov eax, SYS_PUTS
    mov ebx, esi
    int 0x80
    popad
    ret

; The toolkit's zeroed data: put GUI_BSS after SQX_BSS.
%macro GUI_BSS 0
gui_fb      resd 1
gui_on      resb 1
gui_ink     resb 1
gui_bg      resb 1
gui_ink2    resb 1
gui_bevel_up resb 1
gui_ptr_on  resb 1
gui_btns    resb 1
alignb 4
gui_cx      resd 1
gui_cy      resd 1
gui_cw      resd 1
gui_ch      resd 1
gui_mx      resd 1
gui_clx0    resd 1
gui_cly0    resd 1
gui_clx1    resd 1
gui_cly1    resd 1
gui_my      resd 1
gui_blk     resd 6
gl_x1       resd 1
gl_y1       resd 1
gl_dx       resd 1
gl_dy       resd 1
gui_peekb   resb 4
gui_ptrbuf  resb PTR_W * PTR_H + 2
gui_font    resb (FONT_LAST - FONT_FIRST + 1) * FONT_H
alignb 4
%endmacro
