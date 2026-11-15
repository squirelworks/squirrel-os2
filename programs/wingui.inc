; wingui.inc — the Win32 GUI subset for winrun (P.6): USER32 and GDI32 on
; the 2.2 program-window calls (SYS_WINOPEN..SYS_WININFO). Original code,
; written from the documented Win32 API; no Wine or ReactOS code. Included
; by winrun.asm after winshim.inc.
;
; Top-level windows (up to WG_MAXW) are real desktop windows: title bar,
; move, size, z-order and close box from the window manager. Drawing goes
; through SYS_WINDRAW into the client area; GetMessage pumps SYS_WINEVENT
; (WE_PAINT, WE_KEY, WE_DOWN, WE_CLOSE → WM_*). Timers still use GUI_TICKS
; (10 ms). COLORREFs go to the nearest of the 64 EGA colours.
;
; Specs: Microsoft Win32 API (CreateWindowEx, the message loop, GDI) and
; the PE subsystem-2 convention; see documentation/architecture/
; foreign-compatibility.md.
;
; Not provided: child windows and controls, menus, dialogs from
; resources, fonts other than the system one, regions, bitmaps, and a
; mouse pointer of our own (the kernel draws it).

WG_MAXW     equ 4
WG_MAXC     equ 4
WG_TITLE    equ 10              ; matches WM_TITLE_H (FONT_H+1+2)
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
W_HPEN      equ 64
W_HBRUSH    equ 68
W_TITLE     equ 72              ; 32 bytes
W_WID       equ 104             ; native SYS_WINOPEN id, or -1
WSIZE       equ 108

H_BRUSH     equ 0x10000000
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

WE_KEY      equ 1
WE_DOWN     equ 2
WE_CLOSE    equ 6
WE_PAINT    equ 8

WD_FILL     equ 0
WD_LINE     equ 1
WD_TEXT     equ 2
WD_PIXEL    equ 7

SYS_WINOPEN  equ 37
SYS_WINCLOSE equ 38
SYS_WINMOVE  equ 39
SYS_WINTITLE equ 40
SYS_WINDRAW  equ 41
SYS_WINFLUSH equ 42
SYS_WINEVENT equ 43
SYS_WININFO  equ 44

%define PA(n) [esp+36+4*(n)]    ; stdcall arguments after pushad

; ---------- life cycle ----------

; Mark the GUI personality as running (windows open through SYS_WIN*).
wg_on:
    mov byte [wg_active], 1
    ret

; Close every native window when the program ends.
gui_end:
    cmp byte [wg_active], 0
    je .r
    pushad
    mov edi, wg_wnds
    mov ecx, WG_MAXW
.w:
    cmp dword [edi+W_USED], 0
    je .n
    cmp dword [edi+W_WID], -1
    je .n
    mov eax, SYS_WINCLOSE
    mov ebx, [edi+W_WID]
    int 0x80
    mov dword [edi+W_WID], -1
.n:
    add edi, WSIZE
    loop .w
    mov byte [wg_active], 0
    popad
.r:
    ret

; edi = window: open it on the desktop if it is not open yet.
; -> CF set when SYS_WINOPEN failed.
wg_native_open:
    cmp dword [edi+W_WID], -1
    jne .ok
    pushad
    call wg_on
    mov eax, [edi+W_X]
    mov [wg_open], eax
    mov eax, [edi+W_Y]
    mov [wg_open+4], eax
    mov eax, [edi+W_W]
    mov [wg_open+8], eax
    mov eax, [edi+W_H]
    mov [wg_open+12], eax
    lea eax, [edi+W_TITLE]
    mov [wg_open+16], eax
    mov dword [wg_open+20], 0       ; WF_DEFAULT
    mov eax, SYS_WINOPEN
    mov ebx, wg_open
    int 0x80
    cmp eax, -1
    je .fail
    mov [edi+W_WID], eax
    mov dword [edi+W_VISIBLE], 1
    mov dword [edi+W_INVALID], 1
    popad
.ok:
    clc
    ret
.fail:
    popad
    stc
    ret

; edi = window: flush its area to the visible page
wg_flush:
    push eax
    push ebx
    cmp dword [edi+W_WID], -1
    je .r
    mov eax, SYS_WINFLUSH
    mov ebx, [edi+W_WID]
    int 0x80
.r:
    pop ebx
    pop eax
    ret

; ---------- window and DC lookup ----------

; eax = hwnd -> edi = its window; CF if none
wg_win:
    sub eax, WG_HBASE
    jmp wg_slot
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

; eax = native window id -> edi = Win32 window, CF if none
wg_from_wid:
    push ecx
    mov edi, wg_wnds
    mov ecx, WG_MAXW
.f:
    cmp dword [edi+W_USED], 0
    je .n
    cmp [edi+W_WID], eax
    je .ok
.n:
    add edi, WSIZE
    loop .f
    stc
    pop ecx
    ret
.ok:
    clc
    pop ecx
    ret

; edi = window -> eax, ebx unused; ecx, edx = client width, height
wg_client:
    mov ecx, [edi+W_W]
    sub ecx, 2
    mov edx, [edi+W_H]
    sub edx, WG_TITLE + 2
    ret

; ---------- drawing through SYS_WINDRAW ----------

; edi = window; [wg_cmd] filled: issue SYS_WINDRAW
wg_draw:
    push eax
    push ebx
    push ecx
    cmp dword [edi+W_WID], -1
    je .r
    mov eax, SYS_WINDRAW
    mov ebx, [edi+W_WID]
    mov ecx, wg_cmd
    int 0x80
.r:
    pop ecx
    pop ebx
    pop eax
    ret

; edi = window, eax, ebx = client point, cl = colour
wg_pset:
    pushad
    movzx ebp, cl               ; colour (wg_client overwrites ecx)
    test eax, eax
    js .r
    test ebx, ebx
    js .r
    call wg_client
    cmp eax, ecx
    jge .r
    cmp ebx, edx
    jge .r
    mov dword [wg_cmd], WD_FILL
    mov [wg_cmd+4], eax
    mov [wg_cmd+8], ebx
    mov dword [wg_cmd+12], 1
    mov dword [wg_cmd+16], 1
    mov [wg_cmd+20], ebp
    mov dword [wg_cmd+24], 0
    call wg_draw
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
    mov esi, eax                ; x
    mov ebp, ebx                ; y
    call wg_client              ; ecx = w, edx = h
    cmp esi, ecx
    jge .no
    cmp ebp, edx
    jge .no
    call wg_flush
    mov dword [wg_cmd], WD_PIXEL
    mov [wg_cmd+4], esi
    mov [wg_cmd+8], ebp
    mov dword [wg_cmd+12], 0
    mov dword [wg_cmd+16], 0
    mov dword [wg_cmd+20], 0
    mov dword [wg_cmd+24], 0
    mov eax, SYS_WINDRAW
    mov ebx, [edi+W_WID]
    mov ecx, wg_cmd
    int 0x80
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
    ; clip exclusive right/bottom to the client size
    mov esi, [edi+W_W]
    sub esi, 2
    cmp ecx, esi
    jle .c
    mov ecx, esi
.c:
    mov esi, [edi+W_H]
    sub esi, WG_TITLE + 2
    cmp edx, esi
    jle .d
    mov edx, esi
.d:
    cmp eax, ecx
    jge .r
    cmp ebx, edx
    jge .r
    sub ecx, eax                ; width
    sub edx, ebx                ; height
    mov dword [wg_cmd], WD_FILL
    mov [wg_cmd+4], eax
    mov [wg_cmd+8], ebx
    mov [wg_cmd+12], ecx
    mov [wg_cmd+16], edx
    mov [wg_cmd+20], ebp
    mov dword [wg_cmd+24], 0
    call wg_draw
.r:
    popad
    ret

; edi = window; eax, ebx = client; esi = text, ecx = length
wg_text:
    pushad
    jecxz .r
    cmp ecx, 127
    jbe .n
    mov ecx, 127
.n:
    push edi
    mov edi, wg_tbuf
    rep movsb
    mov byte [edi], 0
    pop edi
    mov dword [wg_cmd], WD_TEXT
    mov [wg_cmd+4], eax
    mov [wg_cmd+8], ebx
    mov eax, [edi+W_BK]
    cmp dword [edi+W_BKMODE], 1
    jne .bg
    mov eax, -1
.bg:
    mov [wg_cmd+12], eax
    mov dword [wg_cmd+16], 0
    mov eax, [edi+W_TEXT]
    mov [wg_cmd+20], eax
    mov dword [wg_cmd+24], wg_tbuf
    call wg_draw
.r:
    popad
    ret

; edi = window: a line from eax, ebx to ecx, edx in colour ebp (last
; point left out, as LineTo)
wg_line:
    pushad
    cmp ebp, -1
    je .r
    cmp eax, ecx
    jne .go
    cmp ebx, edx
    je .r
.go:
    ; nudge the end back one step toward the start
    cmp ecx, eax
    je .vx
    jl .xl
    dec ecx
    jmp .vy
.xl:
    inc ecx
    jmp .vy
.vx:
.vy:
    cmp edx, ebx
    je .draw
    jl .yl
    dec edx
    jmp .draw
.yl:
    inc edx
.draw:
    mov dword [wg_cmd], WD_LINE
    mov [wg_cmd+4], eax
    mov [wg_cmd+8], ebx
    mov [wg_cmd+12], ecx
    mov [wg_cmd+16], edx
    mov [wg_cmd+20], ebp
    mov dword [wg_cmd+24], 0
    call wg_draw
.r:
    popad
    ret

; ---------- colours ----------

; eax = COLORREF (0x00BBGGRR) -> eax = the nearest EGA colour (0-63)
wg_host:
    push ebx
    push ecx
    push edx
    xor edx, edx
    xor ecx, ecx
.ch:
    movzx ebx, al
    add ebx, 42
    push eax
    mov eax, ebx
    push edx
    xor edx, edx
    mov ebx, 85
    div ebx
    pop edx
    mov ebx, 2
    sub ebx, ecx
    test eax, 2
    jz .lo
    bts edx, ebx
.lo:
    test eax, 1
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
    mov ecx, 2
.ch:
    shl eax, 8
    xor ebx, ebx
    bt edx, ecx
    jnc .l
    add ebx, 170
.l:
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
    cmp eax, 2
    je .desk
    cmp eax, 16
    je .face
    test eax, eax
    jz .none
    mov eax, 63
    ret
.desk:
    mov eax, 3                  ; cyan desktop feel
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

; eax = hwnd, ebx = message, ecx = wParam, edx = lParam, [wg_qascii] ASCII
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

; Pull SYS_WINEVENT into the Win32 queue (poll; always pumps the WM).
wg_poll:
    pushad
.more:
    mov eax, SYS_WINEVENT
    mov ebx, wg_ev
    mov ecx, 1                  ; poll
    int 0x80
    cmp eax, -1
    je .r
    mov eax, [wg_ev]            ; type
    mov ebx, [wg_ev+4]          ; native window id
    push eax
    mov eax, ebx
    call wg_from_wid
    pop eax
    jc .more
    call wg_hwnd_of
    mov ebp, eax                ; hwnd
    mov eax, [wg_ev]
    cmp eax, WE_CLOSE
    je .close
    cmp eax, WE_PAINT
    je .paint
    cmp eax, WE_KEY
    je .key
    cmp eax, WE_DOWN
    je .down
    jmp .more
.close:
    mov eax, ebp
    mov ebx, WM_CLOSE
    xor ecx, ecx
    xor edx, edx
    call wg_post
    jmp .more
.paint:
    mov dword [edi+W_INVALID], 1
    jmp .more
.key:
    movzx ecx, byte [wg_ev+8]   ; key as wg_key / ASCII
    mov [wg_qascii], cl
    call wg_vk
    mov ecx, eax
    mov eax, ebp
    mov ebx, WM_KEYDOWN
    mov edx, 1
    call wg_post
    jmp .more
.down:
    mov eax, ebp
    mov ebx, WM_LBUTTONDOWN
    mov ecx, 1                  ; MK_LBUTTON
    mov edx, [wg_ev+8]          ; client x | y << 16
    call wg_post
    jmp .more
.r:
    popad
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
    cmp dword [esi+8], 0
    je .tn
    cmp eax, [esi+12]
    jb .tn
    cmp byte [wg_rm], 0
    je .tgive
    mov edx, eax
    add edx, [esi+8]
    mov [esi+12], edx
.tgive:
    mov edx, [esi+16]
    mov ecx, [esi+4]
    mov ebx, WM_TIMER
    mov eax, [esi]
    jmp .give
.tn:
    add esi, 20
    loop .tm
    call wg_poll
    cmp dword [wg_qn], 0
    jne .again
    ; any window marked invalid by WE_PAINT?
    mov esi, wg_wnds
    mov ecx, WG_MAXW
.iv:
    cmp dword [esi+W_USED], 0
    je .ivn
    cmp dword [esi+W_INVALID], 0
    jne .again
.ivn:
    add esi, WSIZE
    loop .iv
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
    mov [edi+16], edx
    mov dword [edi+20], 0
    mov dword [edi+24], 0
    clc
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

; ecx = ASCII, edx = scan (unused here) -> eax = virtual-key code
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
    jz .none
    cmp al, 10
    jne .r
    mov al, 13
.r:
    ret
.none:
    xor eax, eax
    ret

; eax = hwnd, ebx = msg, ecx = wParam, edx = lParam -> eax = result
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
    mov eax, [esi+4]
    mov ebx, [esi+28]
    mov edx, [esi+36]
    jmp wg_register
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

; HWND CreateWindowExA(...)
u_CreateWindowExA:
    pushad
    call wg_on
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
    mov dword [edi+W_WID], -1
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
    ; CW_USEDEFAULT: place the close box near the default pointer (160,100)
    mov eax, PA(4)
    mov ebx, PA(5)
    mov ecx, PA(6)
    mov edx, PA(7)
    cmp eax, 0x80000000
    jne .px
    mov eax, 6
    mov ebx, 94
.px:
    cmp ecx, 0x80000000
    jne .ps
    mov ecx, 160
    mov edx, 120
.ps:
    mov [edi+W_X], eax
    mov [edi+W_Y], ebx
    mov [edi+W_W], ecx
    mov [edi+W_H], edx
    mov esi, PA(2)
    lea ebx, [edi+W_TITLE]
    call wg_settitle
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
    call wg_native_open
    jc .refused
.ok:
    mov [esp+28], ebp
    popad
    ret 48
.refused:
    cmp dword [edi+W_WID], -1
    je .cl
    mov eax, SYS_WINCLOSE
    mov ebx, [edi+W_WID]
    int 0x80
.cl:
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

; BOOL ShowWindow(hwnd, cmd)
u_ShowWindow:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    mov eax, [edi+W_VISIBLE]
    mov [esp+28], eax
    xor eax, eax
    cmp dword PA(1), 0
    je .hide
    call wg_native_open
    jc .no
    mov eax, 1
    mov [edi+W_VISIBLE], eax
    popad
    ret 8
.hide:
    mov [edi+W_VISIBLE], eax
    ; still open on the desktop; a real HideWindow can wait
    popad
    ret 8
.no:
    mov dword [esp+28], 0
    popad
    ret 8

; BOOL UpdateWindow(hwnd)
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
    cmp dword [edi+W_WID], -1
    je .gone
    mov eax, SYS_WINCLOSE
    mov ebx, [edi+W_WID]
    int 0x80
    mov dword [edi+W_WID], -1
.gone:
    mov dword [edi+W_USED], 0
    mov eax, PA(0)
    mov esi, wg_timers
    mov ecx, WG_TMAX
.t:
    cmp [esi], eax
    jne .tn
    mov dword [esi+8], 0
.tn:
    add esi, 20
    loop .t
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
    push wg_ps
    push dword [esp+8]
    call u_BeginPaint
    push wg_ps
    push dword [esp+8]
    call u_EndPaint
    xor eax, eax
    ret 16

; BOOL GetMessageA(MSG *, hwnd, min, max)
u_GetMessageA:
    pushad
    mov edi, PA(0)
    mov ax, 0x0101
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
    and eax, 1
    call wg_next
    mov eax, 0
    jc .q
    inc eax
.q:
    mov [esp+28], eax
    popad
    ret 20

; BOOL TranslateMessage(MSG *)
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
    test edx, edx
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

; HDC BeginPaint(hwnd, PAINTSTRUCT *)
u_BeginPaint:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .no
    mov dword [edi+W_INVALID], 0
    mov ebp, [edi+W_BG]
    xor eax, eax
    xor ebx, ebx
    call wg_client
    add ecx, eax
    add edx, ebx
    call wg_cfill
    mov esi, PA(1)
    mov eax, PA(0)
    add eax, WG_DCBASE - WG_HBASE
    mov [esi], eax
    mov [esp+28], eax
    mov dword [esi+4], 0
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

; BOOL EndPaint / int ReleaseDC
u_EndPaint:
u_ReleaseDC:
    pushad
    mov eax, PA(0)
    call wg_win
    jc .r
    call wg_flush
.r:
    popad
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

; BOOL InvalidateRect(hwnd, RECT *, erase)
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

; int DrawTextA(hdc, text, n, RECT *, format): one line
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
    mov eax, [ebp]
    mov ebx, [ebp+4]
    call wg_text
.r:
    mov dword [esp+28], 8
    popad
    ret 20

; int MessageBoxA: console before graphics; a short-lived window after
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
    ; a small window with the caption; wait for a key or close
    mov esi, PA(2)
    test esi, esi
    jnz .cap
    mov esi, m_ok
.cap:
    mov [wg_open+16], esi
    mov dword [wg_open], 120
    mov dword [wg_open+4], 140
    mov dword [wg_open+8], 280
    mov dword [wg_open+12], 100
    mov dword [wg_open+20], 0
    mov eax, SYS_WINOPEN
    mov ebx, wg_open
    int 0x80
    cmp eax, -1
    je .idok
    mov [wg_mbwid], eax
    mov dword [wg_cmd], WD_FILL
    mov dword [wg_cmd+4], 0
    mov dword [wg_cmd+8], 0
    mov dword [wg_cmd+12], 276
    mov dword [wg_cmd+16], 86
    mov dword [wg_cmd+20], 7
    mov dword [wg_cmd+24], 0
    mov ebx, eax
    mov eax, SYS_WINDRAW
    mov ecx, wg_cmd
    int 0x80
    mov esi, PA(1)
    test esi, esi
    jz .flush
    mov ecx, 120
    mov edi, wg_tbuf
.cp:
    lodsb
    stosb
    test al, al
    jz .tx
    loop .cp
    mov byte [edi], 0
.tx:
    mov dword [wg_cmd], WD_TEXT
    mov dword [wg_cmd+4], 8
    mov dword [wg_cmd+8], 8
    mov dword [wg_cmd+12], -1
    mov dword [wg_cmd+16], 0
    mov dword [wg_cmd+20], 0
    mov dword [wg_cmd+24], wg_tbuf
    mov eax, SYS_WINDRAW
    mov ebx, [wg_mbwid]
    mov ecx, wg_cmd
    int 0x80
.flush:
    mov eax, SYS_WINFLUSH
    mov ebx, [wg_mbwid]
    int 0x80
.key:
    mov eax, SYS_WINEVENT
    mov ebx, wg_ev
    xor ecx, ecx
    int 0x80
    mov eax, [wg_ev]
    cmp eax, WE_CLOSE
    je .close
    cmp eax, WE_KEY
    jne .key
    mov al, [wg_ev+8]
    or al, 0x20
    mov ecx, 1
    mov edx, PA(3)
    and edx, 15
    cmp edx, 4
    jne .done
    mov ecx, 6
    cmp al, 'y'
    je .done
    mov ecx, 7
    cmp al, 'n'
    jne .key
    jmp .done
.close:
    mov ecx, 1
.done:
    mov eax, SYS_WINCLOSE
    mov ebx, [wg_mbwid]
    int 0x80
    mov [esp+28], ecx
    popad
    ret 16
.idok:
    mov dword [esp+28], 1
    popad
    ret 16

; HCURSOR / HICON
u_LoadCursorA:
u_LoadIconA:
    mov eax, 1
    ret 8

; int GetSystemMetrics(index)
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
    cmp byte [wg_active], 0
    je .w320
    mov eax, SYS_WININFO
    mov ebx, -1
    mov ecx, wg_info
    int 0x80
    mov eax, [wg_info+8]
    test eax, eax
    jnz .wr
.w320:
    mov eax, 320
.wr:
    ret 4
.h:
    cmp byte [wg_active], 0
    je .h200
    mov eax, SYS_WININFO
    mov ebx, -1
    mov ecx, wg_info
    int 0x80
    mov eax, [wg_info+12]
    test eax, eax
    jnz .hr
.h200:
    mov eax, 200
.hr:
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
    mov eax, PA(0)
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
    mov eax, esi
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
    cmp dword [edi+W_WID], -1
    je .r
    mov eax, SYS_WINTITLE
    mov ebx, [edi+W_WID]
    lea ecx, [edi+W_TITLE]
    int 0x80
.r:
    mov dword [esp+28], 1
    popad
    ret 8

; BOOL MessageBeep(type)
u_MessageBeep:
    mov eax, 1
    ret 4

; ---------- GDI32 ----------

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

g_CreateSolidBrush:
    mov eax, [esp+4]
    call wg_host
    or eax, H_BRUSH
    ret 4

g_CreatePen:
    mov eax, [esp+12]
    call wg_host
    cmp dword [esp+4], 5
    jne .p
    mov eax, H_NULLCOL
.p:
    or eax, H_PEN
    ret 12

g_DeleteObject:
    mov eax, 1
    ret 4

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
    mov dword [esp+28], H_FONT
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
    push edx
    lea edx, [ebx+1]
    call wg_cfill
    pop edx
    push ebx
    lea ebx, [edx-1]
    call wg_cfill
    pop ebx
    push ecx
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
    dd m_sprintf
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

wg_stockcol db 63, 7, 0x38, 0x38, 0, 0xFF, 63, 0, 0xFF
m_colon db ': ', 0
m_ok db '[ OK ]', 0
m_yesno db '[Y]es [N]o', 0

%macro WINGUI_BSS 0
alignb 4
wg_qh resd 1
wg_qn resd 1
wg_cs resd 12
wg_ps resd 16
wg_open resd 6
wg_ev resd 4
wg_cmd resd 7
wg_info resd 4
wg_mbwid resd 1
wg_wnds resb WG_MAXW*WSIZE
wg_classes resb WG_MAXC*40
wg_queue resb WG_QMAX*20
wg_timers resb WG_TMAX*20
wg_tbuf resb 128
wg_active resb 1
wg_rm resb 1
wg_wait resb 1
wg_qascii resb 1
wg_lastascii resb 1
%endmacro
