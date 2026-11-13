; wingui.inc — the Win32 GUI subset for winrun (P.6): USER32 and GDI32 on
; SYS_GUI. Original code, written from the documented Win32 API; no Wine
; or ReactOS code. Included by winrun.asm after winshim.inc.
;
; The screen is SYS_GUI's 320 x 200, 256 colours, drawn in a back buffer
; and copied with GUI_BLIT. Top-level windows (up to WG_MAXW) get a frame
; and a title bar (WG_TITLE pixels, the 5 x 7 font in 6 x 8 cells) and are
; painted in the order they were made, the newest on top and with the
; keyboard. The client area is drawn straight into the back buffer, clipped
; to the window. Colours (COLORREF) go to the nearest of the 64 EGA colours
; the display keeps in entries 0-63.
;
; Messages: one queue for the process. GetMessage/PeekMessage hand out, in
; order: posted messages; WM_PAINT for a window that is invalid; WM_TIMER
; for a timer that is due (GUI_TICKS, 10 ms); then keys from GUI_KEY
; (WM_KEYDOWN, and WM_CHAR through TranslateMessage) and left clicks from
; GUI_MOUSE (WM_LBUTTONDOWN/UP in client coordinates; a click in the title
; bar's right end is WM_CLOSE). The message filters are ignored.
;
; Not provided: child windows and controls, menus, dialogs from
; resources, fonts other than the system one, regions, bitmaps, and a
; mouse pointer on the screen.

WG_MAXW     equ 4
WG_MAXC     equ 4
WG_TITLE    equ 10
WG_DESK     equ 3               ; cyan
WG_FRAME    equ 0x38            ; dark grey
WG_BAR      equ 1               ; blue
WG_QMAX     equ 32
WG_TMAX     equ 8
WG_HBASE    equ 0x1000          ; hwnd = WG_HBASE + slot
WG_DCBASE   equ 0x2000          ; hdc = WG_DCBASE + slot

; a window
W_USED      equ 0
W_X         equ 4
W_Y         equ 8
W_W         equ 12
W_H         equ 16
W_PROC      equ 20
W_BG        equ 24              ; host colour, or -1: no erase
W_INVALID   equ 28
W_VISIBLE   equ 32
W_PEN       equ 36              ; host colour, or -1: the null pen
W_BRUSH     equ 40
W_TEXT      equ 44
W_BK        equ 48
W_BKMODE    equ 52
W_CURX      equ 56
W_CURY      equ 60
W_HPEN      equ 64              ; the handles SelectObject gives back
W_HBRUSH    equ 68
W_TITLE     equ 72              ; 32 bytes
WSIZE       equ 104

H_BRUSH     equ 0x10000000      ; GDI handles: type | host colour
H_PEN       equ 0x20000000
H_FONT      equ 0x30000000
H_NULLCOL   equ 0x100

WM_CREATE   equ 0x0001
WM_DESTROY  equ 0x0002
WM_SIZE     equ 0x0005
WM_PAINT    equ 0x000F
WM_CLOSE    equ 0x0010
WM_QUIT     equ 0x0012
WM_ERASEBKGND equ 0x0014
WM_KEYDOWN  equ 0x0100
WM_CHAR     equ 0x0102
WM_TIMER    equ 0x0113
WM_LBUTTONDOWN equ 0x0201
WM_LBUTTONUP equ 0x0202

%define PA(n) [esp+36+4*(n)]    ; stdcall arguments after pushad

; ---------- screen ----------

; graphics on, once: the back buffer, the font, the desktop
wg_on:
    cmp byte [wg_active], 0
    jne .r
    pushad
    mov eax, SYS_SBRK
    mov ebx, 64000 + 96*7
    int 0x80
    cmp eax, -1
    je .no
    mov [wg_buf], eax
    add eax, 64000
    mov [wg_font], eax
    mov ecx, eax
    mov eax, 35                 ; SYS_GUI
    mov ebx, 6                  ; GUI_FONT
    int 0x80
    mov eax, 35
    mov ebx, 0                  ; GUI_ENTER
    int 0x80
    test eax, eax
    jnz .no
    mov byte [wg_active], 1
    mov dword [wg_mouse], -1
    call wg_redraw
.no:
    popad
.r:
    ret

; graphics off at the end (ExitProcess, exit, the entry's return)
gui_end:
    cmp byte [wg_active], 0
    je .r
    push eax
    push ebx
    mov eax, 35
    mov ebx, 1                  ; GUI_LEAVE
    int 0x80
    mov byte [wg_active], 0
    pop ebx
    pop eax
.r:
    ret

; the back buffer to the screen
wg_flip:
    cmp byte [wg_active], 0
    je .r
    pushad
    mov eax, [wg_buf]
    mov [wg_rect+16], eax
    mov eax, 35
    mov ebx, 2                  ; GUI_BLIT
    mov ecx, wg_rect
    int 0x80
    mov byte [wg_dirty], 0
    popad
.r:
    ret

; desktop, then every visible window's frame and client, all invalid
wg_redraw:
    cmp byte [wg_active], 0
    je .r
    pushad
    mov edi, [wg_buf]
    mov ecx, 64000/4
    mov eax, WG_DESK * 0x01010101
    rep stosd
    mov edi, wg_wnds
    mov ecx, WG_MAXW
.w:
    cmp dword [edi+W_USED], 0
    je .n
    cmp dword [edi+W_VISIBLE], 0
    je .n
    call wg_frame
    mov dword [edi+W_INVALID], 1
.n:
    add edi, WSIZE
    loop .w
    mov byte [wg_dirty], 1
    popad
.r:
    ret

; edi = window: border, title bar with its title, client in its colour
wg_frame:
    pushad
    mov eax, [edi+W_X]
    mov ebx, [edi+W_Y]
    mov ecx, [edi+W_X]
    add ecx, [edi+W_W]
    mov edx, [edi+W_Y]
    add edx, [edi+W_H]
    mov ebp, WG_FRAME
    call wg_sfill               ; the whole frame
    inc eax
    inc ebx
    dec ecx
    push edx
    lea edx, [ebx+WG_TITLE-1]
    mov ebp, WG_BAR
    call wg_sfill               ; the title bar
    pop edx
    push eax
    push ebx                    ; the close box: a light square at the right
    push ecx
    push edx
    lea eax, [ecx-8]
    inc ebx
    lea edx, [ebx+WG_TITLE-3]
    dec ecx
    mov ebp, 7
    call wg_sfill
    pop edx
    pop ecx
    pop ebx
    pop eax
    add ebx, WG_TITLE
    dec edx
    mov ebp, [edi+W_BG]
    cmp ebp, -1
    jne .bg
    mov ebp, 63
.bg:
    call wg_sfill               ; the client
    ; the title, white on the bar
    lea esi, [edi+W_TITLE]
    mov eax, [edi+W_X]
    add eax, 3
    mov ebx, [edi+W_Y]
    add ebx, 2
    mov ecx, 63
    mov ebp, WG_BAR
.t:
    cmp byte [esi], 0
    je .td
    mov edx, [edi+W_X]
    add edx, [edi+W_W]
    sub edx, 16
    cmp eax, edx
    jg .td
    movzx edx, byte [esi]
    call wg_sglyph
    add eax, 6
    inc esi
    jmp .t
.td:
    popad
    ret

; screen rectangle eax, ebx to ecx, edx (exclusive) in colour ebp,
; clipped to the screen
wg_sfill:
    pushad
    call wg_sclip
    jc .r
.y:
    cmp ebx, edx
    jge .r
    imul edi, ebx, 320
    add edi, eax
    add edi, [wg_buf]
    push ecx
    sub ecx, eax
    push eax
    mov eax, ebp
    rep stosb
    pop eax
    pop ecx
    inc ebx
    jmp .y
.r:
    popad
    ret
wg_sclip:                       ; clip eax..ecx, ebx..edx to 0..320, 0..200
    test eax, eax
    jns .a
    xor eax, eax
.a:
    test ebx, ebx
    jns .b
    xor ebx, ebx
.b:
    cmp ecx, 320
    jle .c
    mov ecx, 320
.c:
    cmp edx, 200
    jle .d
    mov edx, 200
.d:
    cmp eax, ecx
    jge .no
    cmp ebx, edx
    jge .no
    clc
    ret
.no:
    stc
    ret

; one glyph at screen eax, ebx: edx = character, ecx = ink, ebp =
; background or -1
wg_sglyph:
    pushad
    jmp wg_glyph_any

; ---------- window and DC lookup ----------

; eax = hwnd -> edi = its window; CF if none
wg_win:
    sub eax, WG_HBASE
    jmp wg_slot
; eax = hdc -> edi
wg_dc:
    sub eax, WG_DCBASE
wg_slot:
    cmp eax, WG_MAXW
    jae .no
    imul edi, eax, WSIZE
    add edi, wg_wnds
    cmp dword [edi+W_USED], 0
    je .no
    clc
    ret
.no:
    stc
    ret

; edi = window -> eax = its hwnd
wg_hwnd_of:
    mov eax, edi
    sub eax, wg_wnds
    push edx
    xor edx, edx
    push ecx
    mov ecx, WSIZE
    div ecx
    pop ecx
    pop edx
    add eax, WG_HBASE
    ret

; edi = window -> eax, ebx = client origin on the screen, ecx, edx = size
wg_client:
    mov eax, [edi+W_X]
    inc eax
    mov ebx, [edi+W_Y]
    add ebx, WG_TITLE + 1
    mov ecx, [edi+W_W]
    sub ecx, 2
    mov edx, [edi+W_H]
    sub edx, WG_TITLE + 2
    ret

; edi = window, eax, ebx = client point, cl = colour: one pixel, clipped
wg_pset:
    pushad
    test eax, eax
    js .r
    test ebx, ebx
    js .r
    push eax
    push ebx
    push ecx
    call wg_client
    mov esi, ecx                ; width
    mov ebp, edx                ; height
    pop ecx
    pop edx                     ; y
    pop edi                     ; x  (edi no longer the window)
    cmp edi, esi
    jge .r
    cmp edx, ebp
    jge .r
    add edi, eax
    add edx, ebx
    cmp edi, 320
    jae .r
    cmp edx, 200
    jae .r
    imul edx, 320
    add edx, edi
    add edx, [wg_buf]
    mov [edx], cl
    mov byte [wg_dirty], 1
.r:
    popad
    ret

; edi = window, eax, ebx = client point -> eax = host colour, or -1
wg_pget:
    push ebx
    push ecx
    push edx
    push esi
    push ebp
    test eax, eax
    js .no
    test ebx, ebx
    js .no
    push eax
    push ebx
    call wg_client
    mov esi, ecx
    mov ebp, edx
    pop edx
    pop ecx
    cmp ecx, esi
    jge .no
    cmp edx, ebp
    jge .no
    add ecx, eax
    add edx, ebx
    imul edx, 320
    add edx, ecx
    add edx, [wg_buf]
    movzx eax, byte [edx]
    jmp .r
.no:
    mov eax, -1
.r:
    pop ebp
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; edi = window; client rectangle eax, ebx to ecx, edx (exclusive) in
; colour ebp; clipped to the client
wg_cfill:
    pushad
    cmp ebp, -1
    je .r
    test eax, eax
    jns .a
    xor eax, eax
.a:
    test ebx, ebx
    jns .b
    xor ebx, ebx
.b:
    push eax
    push ebx
    push ecx
    push edx
    call wg_client              ; eax, ebx origin; ecx, edx size
    mov esi, ecx
    mov edi, edx
    mov [wg_ox], eax
    mov [wg_oy], ebx
    pop edx
    pop ecx
    pop ebx
    pop eax
    cmp ecx, esi
    jle .c
    mov ecx, esi
.c:
    cmp edx, edi
    jle .d
    mov edx, edi
.d:
    add eax, [wg_ox]
    add ecx, [wg_ox]
    add ebx, [wg_oy]
    add edx, [wg_oy]
    call wg_sfill
    mov byte [wg_dirty], 1
.r:
    popad
    ret

; edi = window; eax, ebx = client position; esi = text, ecx = length:
; the DC's text colour, and its background when the mode is OPAQUE
wg_text:
    pushad
.c:
    jecxz .r
    push ecx
    movzx edx, byte [esi]
    mov ecx, [edi+W_TEXT]
    mov ebp, [edi+W_BK]
    cmp dword [edi+W_BKMODE], 1     ; TRANSPARENT
    jne .g
    mov ebp, -1
.g:
    call wg_cglyph
    pop ecx
    add eax, 6
    inc esi
    dec ecx
    jmp .c
.r:
    popad
    ret

; edi = window; eax, ebx client; edx = character, ecx = ink, ebp =
; background or -1
wg_cglyph:
    pushad
    mov [wg_gwin], edi
    mov [wg_gx], eax
    mov [wg_gy], ebx
    mov byte [wg_gclient], 1
    jmp wg_glyph_body
; screen version: eax, ebx screen; edx, ecx, ebp as above (pushad done)
wg_glyph_any:
    mov [wg_gx], eax
    mov [wg_gy], ebx
    mov byte [wg_gclient], 0
wg_glyph_body:
    sub edx, 0x20
    cmp edx, 0x7E - 0x20
    jbe .ok
    mov edx, '?' - 0x20
.ok:
    imul esi, edx, 7
    add esi, [wg_font]
    xor edx, edx                ; row
.row:
    xor edi, edi
    cmp edx, 7
    jae .bits
    movzx edi, byte [esi+edx]
.bits:
    xor eax, eax                ; column
.col:
    push ecx
    bt edi, 4
    jc .ink
    cmp ebp, -1
    je .skip
    mov ecx, ebp
.ink:
    push eax
    push ebx
    add eax, [wg_gx]
    mov ebx, [wg_gy]
    add ebx, edx
    cmp byte [wg_gclient], 0
    je .scr
    push edi
    mov edi, [wg_gwin]
    call wg_pset
    pop edi
    jmp .done
.scr:
    cmp eax, 320
    jae .done
    cmp ebx, 200
    jae .done
    imul ebx, 320
    add ebx, eax
    add ebx, [wg_buf]
    mov [ebx], cl
.done:
    pop ebx
    pop eax
.skip:
    pop ecx
    shl edi, 1
    inc eax
    cmp eax, 6
    jb .col
    inc edx
    cmp edx, 8
    jb .row
    popad
    ret

; edi = window: a line from eax, ebx to ecx, edx in colour ebp, the last
; point left out (as LineTo)
wg_line:
    pushad
    cmp ebp, -1
    je .r
    mov [wg_lx1], ecx
    mov [wg_ly1], edx
    sub ecx, eax                ; dx
    mov esi, 1
    jns .px
    neg ecx
    neg esi
.px:
    mov [wg_sx], esi
    sub edx, ebx                ; dy
    mov esi, 1
    jns .py
    neg edx
    neg esi
.py:
    mov [wg_sy], esi
    neg edx                     ; err = dx - dy (dy as negative)
    mov [wg_ldx], ecx
    mov [wg_ldy], edx
    lea esi, [ecx+edx]          ; err
.l:
    cmp eax, [wg_lx1]
    jne .draw
    cmp ebx, [wg_ly1]
    je .r
.draw:
    push ecx
    mov ecx, ebp
    call wg_pset
    pop ecx
    lea ecx, [esi+esi]
    cmp ecx, [wg_ldy]
    jl .noy
    add esi, [wg_ldy]
    add eax, [wg_sx]
.noy:
    cmp ecx, [wg_ldx]
    jg .l
    add esi, [wg_ldx]
    add ebx, [wg_sy]
    jmp .l
.r:
    popad
    ret

; ---------- colours ----------

; eax = COLORREF (0x00BBGGRR) -> eax = the nearest EGA colour (0-63)
wg_host:
    push ebx
    push ecx
    push edx
    xor edx, edx                ; result
    xor ecx, ecx                ; channel: 0 red, 1 green, 2 blue
.ch:
    movzx ebx, al
    add ebx, 42
    push eax
    mov eax, ebx
    push edx
    xor edx, edx
    mov ebx, 85
    div ebx                     ; 0..3
    pop edx
    mov ebx, 2
    sub ebx, ecx                ; red bit 2, green 1, blue 0
    test eax, 2                 ; two thirds
    jz .lo
    bts edx, ebx
.lo:
    test eax, 1                 ; a third
    jz .nx
    add ebx, 3
    bts edx, ebx
.nx:
    pop eax
    shr eax, 8
    inc ecx
    cmp ecx, 3
    jb .ch
    mov eax, edx
    pop edx
    pop ecx
    pop ebx
    ret

; eax = EGA colour (0-63) -> eax = its COLORREF
wg_rgb:
    push ebx
    push ecx
    push edx
    mov edx, eax
    xor eax, eax
    mov ecx, 2                  ; blue first: built from the top byte down
.ch:
    shl eax, 8
    xor ebx, ebx
    bt edx, ecx
    jnc .l
    add ebx, 170
.l:
    lea ebx, [ebx]
    push ecx
    add ecx, 3
    bt edx, ecx
    pop ecx
    jnc .s
    add ebx, 85
.s:
    or eax, ebx
    dec ecx
    jns .ch
    ; built as R G B from high to low: swap to 0x00BBGGRR
    bswap eax
    shr eax, 8
    pop edx
    pop ecx
    pop ebx
    ret

; eax = a brush (handle, or COLOR_x + 1) -> eax = host colour or -1
wg_brush_col:
    cmp eax, 64
    jae .h
    cmp eax, 2                  ; COLOR_BACKGROUND + 1: the desktop
    je .desk
    cmp eax, 16                 ; COLOR_BTNFACE + 1
    je .face
    test eax, eax
    jz .none
    mov eax, 63                 ; COLOR_WINDOW + 1 and the rest: white
    ret
.desk:
    mov eax, WG_DESK
    ret
.face:
    mov eax, 7
    ret
.h:
    and eax, 0x1FF
    cmp eax, H_NULLCOL
    je .none
    ret
.none:
    mov eax, -1
    ret

; ---------- the queue ----------

; eax = hwnd, ebx = message, ecx = wParam, edx = lParam, [wg_qascii] the
; key's ASCII for TranslateMessage
wg_post:
    push esi
    mov esi, [wg_qn]
    cmp esi, WG_QMAX
    jae .full
    add esi, [wg_qh]
    and esi, WG_QMAX-1
    imul esi, 20
    add esi, wg_queue
    mov [esi], eax
    mov [esi+4], ebx
    mov [esi+8], ecx
    mov [esi+12], edx
    push eax
    movzx eax, byte [wg_qascii]
    mov [esi+16], eax
    pop eax
    mov byte [wg_qascii], 0
    inc dword [wg_qn]
.full:
    pop esi
    ret

; edi = MSG, al = 1 to remove, ah = 1 to wait -> CF clear with a message
wg_next:
    mov [wg_rm], al
    mov [wg_wait], ah
.again:
    cmp dword [wg_qn], 0
    je .paint
    mov esi, [wg_qh]
    imul esi, 20
    add esi, wg_queue
    mov eax, [esi]
    mov ebx, [esi+4]
    mov ecx, [esi+8]
    mov edx, [esi+12]
    push eax
    mov eax, [esi+16]
    mov [wg_lastascii], al
    pop eax
    cmp byte [wg_rm], 0
    je .give
    mov esi, [wg_qh]
    inc esi
    and esi, WG_QMAX-1
    mov [wg_qh], esi
    dec dword [wg_qn]
    jmp .give
.paint:
    mov esi, wg_wnds
    xor ebp, ebp
.pw:
    cmp dword [esi+W_USED], 0
    je .pn
    cmp dword [esi+W_VISIBLE], 0
    je .pn
    cmp dword [esi+W_INVALID], 0
    je .pn
    lea eax, [ebp+WG_HBASE]
    mov ebx, WM_PAINT
    xor ecx, ecx
    xor edx, edx
    jmp .give
.pn:
    add esi, WSIZE
    inc ebp
    cmp ebp, WG_MAXW
    jb .pw
    ; timers
    push edi
    mov eax, 35
    mov ebx, 7                  ; GUI_TICKS
    int 0x80
    pop edi
    mov esi, wg_timers
    mov ecx, WG_TMAX
.tm:
    cmp dword [esi+8], 0        ; interval 0: a free slot
    je .tn
    cmp eax, [esi+12]
    jb .tn
    cmp byte [wg_rm], 0
    je .tgive
    mov edx, eax
    add edx, [esi+8]
    mov [esi+12], edx
.tgive:
    mov edx, [esi+16]           ; TIMERPROC, or 0
    mov ecx, [esi+4]            ; the id
    mov ebx, WM_TIMER
    mov eax, [esi]
    jmp .give
.tn:
    add esi, 20
    loop .tm
    ; input
    call wg_poll
    cmp dword [wg_qn], 0
    jne .again
    cmp byte [wg_dirty], 0
    je .nd
    call wg_flip
.nd:
    cmp byte [wg_wait], 0
    je .none
    push edi
    mov eax, SYS_YIELD
    int 0x80
    pop edi
    jmp .again
.none:
    stc
    ret
.give:
    mov [edi], eax
    mov [edi+4], ebx
    mov [edi+8], ecx
    mov [edi+12], edx
    push edi
    push eax
    mov eax, 35
    mov ebx, 7
    int 0x80
    imul eax, 10
    mov edx, eax
    pop eax
    pop edi
    mov [edi+16], edx           ; time, in ms
    mov edx, [wg_mouse]
    mov ebx, edx
    and edx, 0x3FF
    shr ebx, 10
    and ebx, 0x3FF
    mov [edi+20], edx
    mov [edi+24], ebx
    clc
    ret

; keys and the left button into the queue, for the top window
wg_poll:
    pushad
    call wg_top
    mov [wg_focus], eax
    mov eax, 35
    mov ebx, 4                  ; GUI_KEY
    int 0x80
    test eax, eax
    jz .mouse
    mov edx, eax
    shr edx, 8
    and edx, 0xFF               ; scan code
    movzx ecx, al               ; ASCII
    mov [wg_qascii], al
    call wg_vk
    mov ecx, eax                ; wParam = the virtual key
    shl edx, 16
    or edx, 1                   ; lParam: repeat 1, the scan code
    mov eax, [wg_focus]
    mov ebx, WM_KEYDOWN
    test eax, eax
    jz .mouse
    call wg_post
.mouse:
    mov byte [wg_qascii], 0
    mov eax, 35
    mov ebx, 5                  ; GUI_MOUSE
    int 0x80
    cmp eax, -1
    je .r
    mov edx, [wg_mouse]
    mov [wg_mouse], eax
    cmp edx, -1
    jne .edge
    xor edx, edx
.edge:
    shr eax, 20
    shr edx, 20
    and eax, 1
    and edx, 1
    cmp eax, edx
    je .r
    mov ebx, WM_LBUTTONDOWN
    test eax, eax
    jnz .hit
    mov ebx, WM_LBUTTONUP
.hit:
    mov ecx, [wg_mouse]
    mov edx, ecx
    and ecx, 0x3FF              ; x
    shr edx, 10
    and edx, 0x3FF              ; y
    ; the topmost window under the point
    mov edi, wg_wnds + (WG_MAXW-1)*WSIZE
    mov ebp, WG_MAXW
.w:
    cmp dword [edi+W_USED], 0
    je .wn
    cmp dword [edi+W_VISIBLE], 0
    je .wn
    mov eax, ecx
    sub eax, [edi+W_X]
    js .wn
    cmp eax, [edi+W_W]
    jge .wn
    mov esi, edx
    sub esi, [edi+W_Y]
    js .wn
    cmp esi, [edi+W_H]
    jge .wn
    cmp esi, WG_TITLE
    jge .client
    cmp ebx, WM_LBUTTONDOWN
    jne .r
    mov esi, [edi+W_W]          ; the close box: the bar's last 10 pixels
    sub esi, 10
    cmp eax, esi
    jl .r
    call wg_hwnd_of
    mov ebx, WM_CLOSE
    xor ecx, ecx
    xor edx, edx
    call wg_post
    jmp .r
.client:
    dec eax                     ; client coordinates
    sub esi, WG_TITLE + 1
    shl esi, 16
    or esi, eax
    mov edx, esi
    call wg_hwnd_of
    xor ecx, ecx
    cmp ebx, WM_LBUTTONDOWN
    jne .post
    inc ecx                     ; MK_LBUTTON
.post:
    call wg_post
    jmp .r
.wn:
    sub edi, WSIZE
    dec ebp
    jnz .w
.r:
    popad
    ret

; -> eax = the top visible window's hwnd, or 0
wg_top:
    push edi
    push ecx
    mov edi, wg_wnds + (WG_MAXW-1)*WSIZE
    mov ecx, WG_MAXW
.w:
    cmp dword [edi+W_USED], 0
    je .n
    cmp dword [edi+W_VISIBLE], 0
    je .n
    call wg_hwnd_of
    jmp .r
.n:
    sub edi, WSIZE
    loop .w
    xor eax, eax
.r:
    pop ecx
    pop edi
    ret

; ecx = ASCII, edx = scan code -> eax = the virtual-key code
wg_vk:
    mov eax, ecx
    cmp al, 'a'
    jb .ascii
    cmp al, 'z'
    ja .ascii
    sub al, 0x20
    ret
.ascii:
    test al, al
    jz .scan
    cmp al, 10
    jne .r
    mov al, 13
.r:
    ret
.scan:
    mov eax, 0x26
    cmp dl, 0x48
    je .r
    mov eax, 0x28
    cmp dl, 0x50
    je .r
    mov eax, 0x25
    cmp dl, 0x4B
    je .r
    mov eax, 0x27
    cmp dl, 0x4D
    je .r
    mov eax, 0x24
    cmp dl, 0x47
    je .r
    mov eax, 0x23
    cmp dl, 0x4F
    je .r
    mov eax, 0x21
    cmp dl, 0x49
    je .r
    mov eax, 0x22
    cmp dl, 0x51
    je .r
    mov eax, 0x2E
    cmp dl, 0x53
    je .r
    movzx eax, dl               ; F1-F10: VK_F1 = 0x70
    sub eax, 0x3B
    cmp eax, 9
    ja .none
    add eax, 0x70
    ret
.none:
    xor eax, eax
    ret

; eax = hwnd, ebx = msg, ecx = wParam, edx = lParam -> eax = the window
; procedure's result (0 for no such window)
wg_send:
    push edi
    push eax
    call wg_win
    pop eax
    jc .no
    push edx
    push ecx
    push ebx
    push eax
    call [edi+W_PROC]
    pop edi
    ret
.no:
    xor eax, eax
    pop edi
    ret

; ---------- USER32 ----------

; ATOM RegisterClassA(WNDCLASSA *)
u_RegisterClassA:
    pushad
    mov esi, PA(0)
    mov eax, [esi+4]            ; lpfnWndProc
    mov ebx, [esi+28]           ; hbrBackground
    mov edx, [esi+36]           ; lpszClassName
    jmp wg_register
; ATOM RegisterClassExA(WNDCLASSEXA *)
u_RegisterClassExA:
    pushad
    mov esi, PA(0)
    mov eax, [esi+8]
    mov ebx, [esi+32]
    mov edx, [esi+40]
wg_register:
    mov edi, wg_classes
    mov ecx, WG_MAXC
.f:
    cmp dword [edi+32], 0
    je .free
    add edi, 40
    loop .f
    mov dword [esp+28], 0
    popad
    ret 4
.free:
    mov [edi+32], eax
    push eax
    mov eax, ebx
    call wg_brush_col
    mov [edi+36], eax
    pop eax
    mov esi, edx
    mov ecx, 31
.cp:
    lodsb
    stosb
    test al, al
    jz .cd
    loop .cp
    mov byte [edi], 0
.cd:
    mov dword [esp+28], 0xC000
    popad
    ret 4

; HWND CreateWindowExA(exstyle, class, name, style, x, y, w, h, parent,
;                      menu, instance, param)
u_CreateWindowExA:
    pushad
    call wg_on
    ; the class, by name
    mov edx, PA(1)
    mov esi, wg_classes
    mov ecx, WG_MAXC
.cls:
    cmp dword [esi+32], 0
    je .cn
    push esi
    push edx
.cc:
    mov al, [esi]
    mov ah, [edx]
    or ax, 0x2020
    cmp al, ah
    jne .cne
    test byte [esi], 0xFF
    jz .cfound
    inc esi
    inc edx
    jmp .cc
.cne:
    pop edx
    pop esi
.cn:
    add esi, 40
    loop .cls
    jmp .fail
.cfound:
    pop edx
    pop esi
    ; a free window
    mov edi, wg_wnds
    mov ecx, WG_MAXW
.wf:
    cmp dword [edi+W_USED], 0
    je .wfree
    add edi, WSIZE
    loop .wf
    jmp .fail
.wfree:
    push edi
    mov ecx, WSIZE/4
    xor eax, eax
    rep stosd
    pop edi
    mov dword [edi+W_USED], 1
    mov eax, [esi+32]
    mov [edi+W_PROC], eax
    mov eax, [esi+36]
    mov [edi+W_BG], eax
    mov dword [edi+W_TEXT], 0
    mov dword [edi+W_BK], 63
    mov dword [edi+W_BKMODE], 2
    mov dword [edi+W_PEN], 0
    mov dword [edi+W_BRUSH], 63
    mov dword [edi+W_HPEN], H_PEN | 0
    mov dword [edi+W_HBRUSH], H_BRUSH | 63
    ; the place: CW_USEDEFAULT gives 10, 10, 300 x 180
    mov eax, PA(4)
    mov ebx, PA(5)
    mov ecx, PA(6)
    mov edx, PA(7)
    cmp eax, 0x80000000
    jne .px
    mov eax, 10
    mov ebx, 10
.px:
    cmp ecx, 0x80000000
    jne .ps
    mov ecx, 300
    mov edx, 180
.ps:
    mov [edi+W_X], eax
    mov [edi+W_Y], ebx
    mov [edi+W_W], ecx
    mov [edi+W_H], edx
    mov esi, PA(2)
    lea ebx, [edi+W_TITLE]
    call wg_settitle
    ; WM_CREATE with a CREATESTRUCT, then WM_SIZE
    call wg_hwnd_of
    mov ebp, eax
    mov ecx, PA(11)
    mov [wg_cs], ecx
    mov ecx, PA(10)
    mov [wg_cs+4], ecx
    mov dword [wg_cs+8], 0
    mov dword [wg_cs+12], 0
    mov ecx, [edi+W_H]
    mov [wg_cs+16], ecx
    mov ecx, [edi+W_W]
    mov [wg_cs+20], ecx
    mov ecx, [edi+W_Y]
    mov [wg_cs+24], ecx
    mov ecx, [edi+W_X]
    mov [wg_cs+28], ecx
    mov ecx, PA(3)
    mov [wg_cs+32], ecx
    mov ecx, PA(2)
    mov [wg_cs+36], ecx
    mov ecx, PA(1)
    mov [wg_cs+40], ecx
    mov ecx, PA(0)
    mov [wg_cs+44], ecx
    mov eax, ebp
    mov ebx, WM_CREATE
    xor ecx, ecx
    mov edx, wg_cs
    call wg_send
    cmp eax, -1
    je .refused
    call wg_client
    shl edx, 16
    or edx, ecx
    mov eax, ebp
    mov ebx, WM_SIZE
    xor ecx, ecx
    call wg_send
    test dword PA(3), 0x10000000    ; WS_VISIBLE
    jz .ok
    mov dword [edi+W_VISIBLE], 1
    call wg_redraw
.ok:
    mov [esp+28], ebp
    popad
    ret 48
.refused:
    mov dword [edi+W_USED], 0
.fail:
    mov dword [esp+28], 0
    popad
    ret 48

; esi = text or 0, ebx = 32-byte title field
wg_settitle:
    push ecx
    push eax
    mov byte [ebx], 0
    test esi, esi
    jz .r
    mov ecx, 31
.c:
    lodsb
    mov [ebx], al
    test al, al
    jz .r
    inc ebx
    loop .c
    mov byte [ebx], 0
.r:
    pop eax
    pop ecx
    ret

; BOOL ShowWindow(hwnd, cmd): SW_HIDE (0) hides, the rest show
u_ShowWindow:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    mov eax, [edi+W_VISIBLE]
    mov [esp+28], eax
    xor eax, eax
    cmp dword PA(1), 0
    je .set
    inc eax
.set:
    mov [edi+W_VISIBLE], eax
    call wg_redraw
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; BOOL UpdateWindow(hwnd): WM_PAINT now, if it is invalid
u_UpdateWindow:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .r
    cmp dword [edi+W_INVALID], 0
    je .r
    cmp dword [edi+W_VISIBLE], 0
    je .r
    mov eax, PA(0)
    mov ebx, WM_PAINT
    xor ecx, ecx
    xor edx, edx
    call wg_send
.r:
    mov dword [esp+28], 1
    popad
    ret 4

; BOOL DestroyWindow(hwnd)
u_DestroyWindow:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    mov eax, PA(0)
    mov ebx, WM_DESTROY
    xor ecx, ecx
    xor edx, edx
    call wg_send
    mov dword [edi+W_USED], 0
    mov eax, PA(0)
    mov esi, wg_timers          ; its timers stop
    mov ecx, WG_TMAX
.t:
    cmp [esi], eax
    jne .tn
    mov dword [esi+8], 0
.tn:
    add esi, 20
    loop .t
    call wg_redraw
    mov dword [esp+28], 1
    popad
    ret 4
.no:
    mov dword [esp+28], 0
    popad
    ret 4

; LRESULT DefWindowProcA(hwnd, msg, wParam, lParam)
u_DefWindowProcA:
    mov eax, [esp+8]
    cmp eax, WM_CLOSE
    je .close
    cmp eax, WM_PAINT
    je .paint
    cmp eax, WM_ERASEBKGND
    je .one
    xor eax, eax
    ret 16
.one:
    mov eax, 1
    ret 16
.close:
    push dword [esp+4]
    call u_DestroyWindow
    xor eax, eax
    ret 16
.paint:
    push wg_ps                  ; validate: BeginPaint and EndPaint
    push dword [esp+8]
    call u_BeginPaint
    push wg_ps
    push dword [esp+8]
    call u_EndPaint
    xor eax, eax
    ret 16

; BOOL GetMessageA(MSG *, hwnd, min, max): 0 for WM_QUIT
u_GetMessageA:
    pushad
    mov edi, PA(0)
    mov ax, 0x0101              ; remove, wait
    call wg_next
    xor eax, eax
    cmp dword [edi+4], WM_QUIT
    je .q
    inc eax
.q:
    mov [esp+28], eax
    popad
    ret 16

; BOOL PeekMessageA(MSG *, hwnd, min, max, remove)
u_PeekMessageA:
    pushad
    mov edi, PA(0)
    mov eax, PA(4)
    and eax, 1                  ; PM_REMOVE
    call wg_next
    mov eax, 0
    jc .q
    inc eax
.q:
    mov [esp+28], eax
    popad
    ret 20

; BOOL TranslateMessage(MSG *): WM_KEYDOWN with a character -> WM_CHAR
u_TranslateMessage:
    pushad
    mov esi, PA(0)
    xor eax, eax
    cmp dword [esi+4], WM_KEYDOWN
    jne .r
    movzx ecx, byte [wg_lastascii]
    jecxz .r
    cmp ecx, 10
    jne .c
    mov ecx, 13
.c:
    mov eax, [esi]
    mov ebx, WM_CHAR
    mov edx, [esi+12]
    call wg_post
    mov byte [wg_lastascii], 0
    mov eax, 1
.r:
    mov [esp+28], eax
    popad
    ret 4

; LRESULT DispatchMessageA(MSG *)
u_DispatchMessageA:
    pushad
    mov esi, PA(0)
    mov eax, [esi]
    mov ebx, [esi+4]
    mov ecx, [esi+8]
    mov edx, [esi+12]
    cmp ebx, WM_TIMER
    jne .send
    test edx, edx               ; a TIMERPROC(hwnd, WM_TIMER, id, time)
    jz .send
    push dword [esi+16]
    push ecx
    push ebx
    push eax
    call edx
    jmp .r
.send:
    call wg_send
.r:
    mov [esp+28], eax
    popad
    ret 4

; void PostQuitMessage(code)
u_PostQuitMessage:
    pushad
    xor eax, eax
    mov ebx, WM_QUIT
    mov ecx, PA(0)
    xor edx, edx
    call wg_post
    popad
    ret 4

; BOOL PostMessageA(hwnd, msg, wParam, lParam)
u_PostMessageA:
    pushad
    mov eax, PA(0)
    mov ebx, PA(1)
    mov ecx, PA(2)
    mov edx, PA(3)
    call wg_post
    mov dword [esp+28], 1
    popad
    ret 16

; LRESULT SendMessageA(hwnd, msg, wParam, lParam)
u_SendMessageA:
    pushad
    mov eax, PA(0)
    mov ebx, PA(1)
    mov ecx, PA(2)
    mov edx, PA(3)
    call wg_send
    mov [esp+28], eax
    popad
    ret 16

; HDC BeginPaint(hwnd, PAINTSTRUCT *): erases with the class colour
u_BeginPaint:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    mov dword [edi+W_INVALID], 0
    mov ebp, [edi+W_BG]
    xor eax, eax
    xor ebx, ebx
    mov ecx, 320
    mov edx, 200
    call wg_cfill
    mov esi, PA(1)
    mov eax, PA(0)
    add eax, WG_DCBASE - WG_HBASE
    mov [esi], eax              ; hdc
    mov [esp+28], eax
    mov dword [esi+4], 0        ; fErase: done
    call wg_client
    mov dword [esi+8], 0
    mov dword [esi+12], 0
    mov [esi+16], ecx
    mov [esi+20], edx
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; BOOL EndPaint(hwnd, PAINTSTRUCT *) / int ReleaseDC(hwnd, hdc)
u_EndPaint:
u_ReleaseDC:
    call wg_flip
    mov eax, 1
    ret 8

; HDC GetDC(hwnd)
u_GetDC:
    mov eax, [esp+4]
    push edi
    call wg_win
    pop edi
    mov eax, 0
    jc .r
    mov eax, [esp+4]
    add eax, WG_DCBASE - WG_HBASE
.r:
    ret 4

; BOOL InvalidateRect(hwnd, RECT *, erase): the whole client; hwnd 0: all
u_InvalidateRect:
    pushad
    mov eax, PA(0)
    test eax, eax
    jz .all
    call wg_win
    jc .r
    mov dword [edi+W_INVALID], 1
    jmp .r
.all:
    mov edi, wg_wnds
    mov ecx, WG_MAXW
.a:
    mov dword [edi+W_INVALID], 1
    add edi, WSIZE
    loop .a
.r:
    mov dword [esp+28], 1
    popad
    ret 12

; BOOL ValidateRect(hwnd, RECT *)
u_ValidateRect:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .r
    mov dword [edi+W_INVALID], 0
.r:
    mov dword [esp+28], 1
    popad
    ret 8

; BOOL GetClientRect(hwnd, RECT *)
u_GetClientRect:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    call wg_client
    mov esi, PA(1)
    mov dword [esi], 0
    mov dword [esi+4], 0
    mov [esi+8], ecx
    mov [esi+12], edx
    mov dword [esp+28], 1
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; int FillRect(hdc, RECT *, brush)
u_FillRect:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov eax, PA(2)
    call wg_brush_col
    mov ebp, eax
    mov esi, PA(1)
    mov eax, [esi]
    mov ebx, [esi+4]
    mov ecx, [esi+8]
    mov edx, [esi+12]
    call wg_cfill
.r:
    mov dword [esp+28], 1
    popad
    ret 12

; int DrawTextA(hdc, text, n, RECT *, format): one line; DT_CENTER (1),
; DT_RIGHT (2), DT_VCENTER (4), DT_BOTTOM (8)
u_DrawTextA:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov esi, PA(1)
    mov ecx, PA(2)
    cmp ecx, -1
    jne .n
    xor ecx, ecx
.len:
    cmp byte [esi+ecx], 0
    je .n
    inc ecx
    jmp .len
.n:
    mov ebp, PA(3)
    mov eax, [ebp]              ; left
    mov ebx, [ebp+4]            ; top
    mov edx, PA(4)
    test edx, 1
    jz .nc
    mov eax, [ebp+8]
    sub eax, [ebp]
    imul edx, ecx, 6
    sub eax, edx
    sar eax, 1
    add eax, [ebp]
    mov edx, PA(4)
.nc:
    test edx, 2
    jz .nr
    mov eax, [ebp+8]
    push edx
    imul edx, ecx, 6
    sub eax, edx
    pop edx
.nr:
    test edx, 4
    jz .nv
    mov ebx, [ebp+12]
    sub ebx, [ebp+4]
    sub ebx, 8
    sar ebx, 1
    add ebx, [ebp+4]
.nv:
    test edx, 8
    jz .nb
    mov ebx, [ebp+12]
    sub ebx, 8
.nb:
    call wg_text
.r:
    mov dword [esp+28], 8
    popad
    ret 20

; int MessageBoxA(hwnd, text, caption, type): a box in the middle of the
; screen, or two lines on the console before graphics; IDOK, or IDYES /
; IDNO for MB_YESNO (Y and N)
u_MessageBoxA:
    pushad
    cmp byte [wg_active], 0
    jne .gfx
    mov ebx, PA(2)
    test ebx, ebx
    jz .t
    call puts
    mov ebx, m_colon
    call puts
.t:
    mov ebx, PA(1)
    call puts
    mov ebx, m_nl
    call puts
    mov dword [esp+28], 1
    popad
    ret 16
.gfx:
    mov esi, PA(1)
    call wg_strlen
    mov ebp, ecx
    mov esi, PA(2)
    call wg_strlen
    cmp ecx, ebp
    jbe .w
    mov ebp, ecx
.w:
    imul ebp, 6
    add ebp, 16                 ; width
    cmp ebp, 316
    jbe .w2
    mov ebp, 316
.w2:
    mov eax, 320
    sub eax, ebp
    shr eax, 1                  ; left
    mov [wg_mbx], eax
    lea ecx, [eax+ebp]
    mov ebx, 70
    mov edx, 130
    push ebp
    mov ebp, WG_FRAME
    call wg_sfill
    inc eax
    inc ebx
    dec ecx
    dec edx
    mov ebp, 7
    call wg_sfill
    mov edx, ebx
    add edx, WG_TITLE-1
    mov ebp, WG_BAR
    call wg_sfill
    pop ebp
    mov esi, PA(2)
    mov eax, [wg_mbx]
    add eax, 4
    mov ebx, 72
    mov ecx, 63
    mov ebp, WG_BAR
    call wg_stext
    mov esi, PA(1)
    mov eax, [wg_mbx]
    add eax, 8
    mov ebx, 90
    mov ecx, 0
    mov ebp, 7
    call wg_stext
    mov esi, m_ok
    mov eax, PA(3)
    and eax, 15
    cmp eax, 4                  ; MB_YESNO
    jne .bt
    mov esi, m_yesno
.bt:
    mov eax, 136
    mov ebx, 112
    mov ecx, 0
    mov ebp, 7
    call wg_stext
    call wg_flip
.key:
    mov eax, 35
    mov ebx, 4
    int 0x80
    test eax, eax
    jnz .got
    mov eax, SYS_YIELD
    int 0x80
    jmp .key
.got:
    or al, 0x20
    mov ecx, 1                  ; IDOK
    mov edx, PA(3)
    and edx, 15
    cmp edx, 4
    jne .done
    mov ecx, 6                  ; IDYES
    cmp al, 'y'
    je .done
    mov ecx, 7                  ; IDNO
    cmp al, 'n'
    jne .key
.done:
    mov [esp+28], ecx
    call wg_redraw
    popad
    ret 16

; esi = ASCIIZ -> ecx = its length
wg_strlen:
    xor ecx, ecx
.l:
    cmp byte [esi+ecx], 0
    je .r
    inc ecx
    jmp .l
.r:
    ret

; esi = ASCIIZ at screen eax, ebx; ecx ink, ebp background
wg_stext:
    pushad
.c:
    movzx edx, byte [esi]
    test edx, edx
    jz .r
    cmp eax, 314
    jg .r
    call wg_sglyph
    add eax, 6
    inc esi
    jmp .c
.r:
    popad
    ret

; HCURSOR LoadCursorA(...), HICON LoadIconA(...): a token
u_LoadCursorA:
u_LoadIconA:
    mov eax, 1
    ret 8

; int GetSystemMetrics(index): screen 320 x 200, caption 10
u_GetSystemMetrics:
    mov eax, [esp+4]
    cmp eax, 0
    je .w
    cmp eax, 1
    je .h
    cmp eax, 4
    je .cap
    xor eax, eax
    ret 4
.w:
    mov eax, 320
    ret 4
.h:
    mov eax, 200
    ret 4
.cap:
    mov eax, WG_TITLE
    ret 4

; UINT_PTR SetTimer(hwnd, id, ms, proc)
u_SetTimer:
    pushad
    mov esi, wg_timers
    mov ecx, WG_TMAX
.f:
    mov eax, PA(0)              ; the same window and id: replaced
    cmp [esi], eax
    jne .fn
    mov eax, PA(1)
    cmp [esi+4], eax
    je .set
.fn:
    add esi, 20
    loop .f
    mov esi, wg_timers
    mov ecx, WG_TMAX
.free:
    cmp dword [esi+8], 0
    je .set
    add esi, 20
    loop .free
    mov dword [esp+28], 0
    popad
    ret 16
.set:
    mov eax, PA(0)
    mov [esi], eax
    mov eax, PA(1)
    test eax, eax
    jnz .id
    mov eax, esi                ; hwnd 0: an id of our own
.id:
    mov [esi+4], eax
    mov [esp+28], eax
    mov eax, PA(2)
    xor edx, edx
    mov ecx, 10
    div ecx
    test eax, eax
    jnz .iv
    inc eax
.iv:
    mov [esi+8], eax
    mov eax, PA(3)
    mov [esi+16], eax
    mov eax, 35
    mov ebx, 7
    int 0x80
    add eax, [esi+8]
    mov [esi+12], eax
    popad
    ret 16

; BOOL KillTimer(hwnd, id)
u_KillTimer:
    pushad
    mov esi, wg_timers
    mov ecx, WG_TMAX
.f:
    mov eax, PA(0)
    cmp [esi], eax
    jne .n
    mov eax, PA(1)
    cmp [esi+4], eax
    jne .n
    mov dword [esi+8], 0
.n:
    add esi, 20
    loop .f
    mov dword [esp+28], 1
    popad
    ret 8

; BOOL SetWindowTextA(hwnd, text)
u_SetWindowTextA:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .r
    mov esi, PA(1)
    lea ebx, [edi+W_TITLE]
    call wg_settitle
    call wg_redraw
.r:
    mov dword [esp+28], 1
    popad
    ret 8

; BOOL MessageBeep(type)
u_MessageBeep:
    mov eax, 1
    ret 4

; ---------- GDI32 ----------

; HGDIOBJ GetStockObject(i)
g_GetStockObject:
    mov eax, [esp+4]
    cmp eax, 5
    jbe .brush
    cmp eax, 8
    jbe .pen
    mov eax, H_FONT
    ret 4
.brush:
    movzx eax, byte [wg_stockcol+eax]
    cmp al, 0xFF
    jne .b
    mov eax, H_NULLCOL
.b:
    or eax, H_BRUSH
    ret 4
.pen:
    movzx eax, byte [wg_stockcol+eax]
    cmp al, 0xFF
    jne .p
    mov eax, H_NULLCOL
.p:
    or eax, H_PEN
    ret 4

; HBRUSH CreateSolidBrush(colorref)
g_CreateSolidBrush:
    mov eax, [esp+4]
    call wg_host
    or eax, H_BRUSH
    ret 4

; HPEN CreatePen(style, width, colorref): PS_NULL (5) draws nothing
g_CreatePen:
    mov eax, [esp+12]
    call wg_host
    cmp dword [esp+4], 5
    jne .p
    mov eax, H_NULLCOL
.p:
    or eax, H_PEN
    ret 12

; BOOL DeleteObject(h)
g_DeleteObject:
    mov eax, 1
    ret 4

; HGDIOBJ SelectObject(hdc, h) -> the one it replaces
g_SelectObject:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .no
    mov ebx, PA(1)
    mov eax, ebx
    and eax, 0xF0000000
    cmp eax, H_BRUSH
    je .brush
    cmp eax, H_PEN
    je .pen
    mov dword [esp+28], H_FONT  ; fonts: the system font stays
    popad
    ret 8
.brush:
    mov eax, [edi+W_HBRUSH]
    mov [esp+28], eax
    mov [edi+W_HBRUSH], ebx
    mov eax, ebx
    call wg_brush_col
    mov [edi+W_BRUSH], eax
    popad
    ret 8
.pen:
    mov eax, [edi+W_HPEN]
    mov [esp+28], eax
    mov [edi+W_HPEN], ebx
    and ebx, 0x1FF
    cmp ebx, H_NULLCOL
    jne .pc
    mov ebx, -1
.pc:
    mov [edi+W_PEN], ebx
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; COLORREF SetTextColor(hdc, c) / SetBkColor(hdc, c): the old one
g_SetTextColor:
    mov edx, W_TEXT
    jmp wg_setcol
g_SetBkColor:
    mov edx, W_BK
wg_setcol:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .no
    mov eax, [edi+edx]
    call wg_rgb
    mov [esp+28], eax
    mov eax, PA(1)
    call wg_host
    mov [edi+edx], eax
    popad
    ret 8
.no:
    mov dword [esp+28], 0xFFFFFFFF
    popad
    ret 8

; int SetBkMode(hdc, mode): TRANSPARENT 1, OPAQUE 2
g_SetBkMode:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .no
    mov eax, [edi+W_BKMODE]
    mov [esp+28], eax
    mov eax, PA(1)
    mov [edi+W_BKMODE], eax
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; BOOL TextOutA(hdc, x, y, text, n)
g_TextOutA:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov eax, PA(1)
    mov ebx, PA(2)
    mov esi, PA(3)
    mov ecx, PA(4)
    call wg_text
.r:
    mov dword [esp+28], 1
    popad
    ret 20

; COLORREF SetPixel(hdc, x, y, c): the colour it really got
g_SetPixel:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .no
    mov eax, PA(3)
    call wg_host
    mov ecx, eax
    mov eax, PA(1)
    mov ebx, PA(2)
    call wg_pset
    mov eax, ecx
    call wg_rgb
    mov [esp+28], eax
    popad
    ret 16
.no:
    mov dword [esp+28], -1
    popad
    ret 16

; COLORREF GetPixel(hdc, x, y): CLR_INVALID outside
g_GetPixel:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .no
    mov eax, PA(1)
    mov ebx, PA(2)
    call wg_pget
    cmp eax, -1
    je .no
    call wg_rgb
    mov [esp+28], eax
    popad
    ret 12
.no:
    mov dword [esp+28], -1
    popad
    ret 12

; BOOL MoveToEx(hdc, x, y, POINT *old)
g_MoveToEx:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov esi, PA(3)
    test esi, esi
    jz .s
    mov eax, [edi+W_CURX]
    mov [esi], eax
    mov eax, [edi+W_CURY]
    mov [esi+4], eax
.s:
    mov eax, PA(1)
    mov [edi+W_CURX], eax
    mov eax, PA(2)
    mov [edi+W_CURY], eax
.r:
    mov dword [esp+28], 1
    popad
    ret 16

; BOOL LineTo(hdc, x, y)
g_LineTo:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov eax, [edi+W_CURX]
    mov ebx, [edi+W_CURY]
    mov ecx, PA(1)
    mov edx, PA(2)
    mov [edi+W_CURX], ecx
    mov [edi+W_CURY], edx
    mov ebp, [edi+W_PEN]
    call wg_line
.r:
    mov dword [esp+28], 1
    popad
    ret 12

; BOOL Rectangle(hdc, left, top, right, bottom): brush inside, pen edge
g_Rectangle:
    pushad
    mov eax, PA(0)
    call wg_dc
    jc .r
    mov eax, PA(1)
    mov ebx, PA(2)
    mov ecx, PA(3)
    mov edx, PA(4)
    mov ebp, [edi+W_BRUSH]
    call wg_cfill
    mov ebp, [edi+W_PEN]
    cmp ebp, -1
    je .r
    push edx                    ; top and bottom edges
    lea edx, [ebx+1]
    call wg_cfill
    pop edx
    push ebx
    lea ebx, [edx-1]
    call wg_cfill
    pop ebx
    push ecx                    ; left and right edges
    lea ecx, [eax+1]
    call wg_cfill
    pop ecx
    lea eax, [ecx-1]
    call wg_cfill
.r:
    mov dword [esp+28], 1
    popad
    ret 20

; ---------- the table and the data ----------

%macro U 1
    dd u_%1
    db %str(%1), 0
%endmacro
%macro G 1
    dd g_%1
    db %str(%1), 0
%endmacro
%macro WINGUI_TABLE 0
    U RegisterClassA
    U RegisterClassExA
    U CreateWindowExA
    U ShowWindow
    U UpdateWindow
    U DestroyWindow
    U DefWindowProcA
    U GetMessageA
    U PeekMessageA
    U TranslateMessage
    U DispatchMessageA
    U PostQuitMessage
    U PostMessageA
    U SendMessageA
    U BeginPaint
    U EndPaint
    U GetDC
    U ReleaseDC
    U InvalidateRect
    U ValidateRect
    U GetClientRect
    U FillRect
    U DrawTextA
    U MessageBoxA
    U LoadCursorA
    U LoadIconA
    U GetSystemMetrics
    U SetTimer
    U KillTimer
    U SetWindowTextA
    U MessageBeep
    dd m_sprintf                    ; wsprintfA: cdecl, like sprintf
    db 'wsprintfA', 0
    G GetStockObject
    G CreateSolidBrush
    G CreatePen
    G DeleteObject
    G SelectObject
    G SetTextColor
    G SetBkColor
    G SetBkMode
    G TextOutA
    G SetPixel
    G GetPixel
    G MoveToEx
    G LineTo
    G Rectangle
%endmacro

; stock objects 0-8: white, light grey, grey, dark grey, black brushes,
; the null brush; white, black, null pens
wg_stockcol db 63, 7, 0x38, 0x38, 0, 0xFF, 63, 0, 0xFF
wg_rect dd 0, 0, 320, 200, 0, 320
m_colon db ': ', 0
m_ok db '[ OK ]', 0
m_yesno db '[Y]es [N]o', 0

%macro WINGUI_BSS 0
alignb 4
wg_buf resd 1
wg_font resd 1
wg_mouse resd 1
wg_focus resd 1
wg_qh resd 1
wg_qn resd 1
wg_ox resd 1
wg_oy resd 1
wg_gx resd 1
wg_gy resd 1
wg_gwin resd 1
wg_lx1 resd 1
wg_ly1 resd 1
wg_sx resd 1
wg_sy resd 1
wg_ldx resd 1
wg_ldy resd 1
wg_mbx resd 1
wg_cs resd 12
wg_ps resd 16
wg_wnds resb WG_MAXW*WSIZE
wg_classes resb WG_MAXC*40
wg_queue resb WG_QMAX*20
wg_timers resb WG_TMAX*20
wg_active resb 1
wg_dirty resb 1
wg_rm resb 1
wg_wait resb 1
wg_qascii resb 1
wg_lastascii resb 1
wg_gclient resb 1
%endmacro
