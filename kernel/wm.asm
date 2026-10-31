; Squirrel-OS/2 — window manager (1.4)
; Included from pm.asm. Original code.
;
; Windows in graphics mode, drawn with the 1.3 primitives (gfx.asm). A
; window is a rectangle with a one-pixel frame, a title bar with its title,
; and a client area. wm_redraw paints the desktop and then every open
; window, lowest slot first. Keyboard only. See documentation/kernel/windows.md.

WM_MAX          equ 4           ; open windows at most

; window record
WIN_USED        equ 0           ; byte: 1 while the window is open
WIN_X           equ 4
WIN_Y           equ 8
WIN_W           equ 12          ; outer size, frame included
WIN_H           equ 16
WIN_TITLE       equ 20          ; zero-terminated string
WIN_SIZE        equ 24

WM_TITLE_H      equ GFX_CELL_H + 2  ; title bar: one text row and a margin
WM_MIN_W        equ 16
WM_MIN_H        equ WM_TITLE_H + 4

; colours (the text mode's EGA palette, as graph uses it)
WM_DESKTOP      equ 0x03        ; cyan
WM_FRAME        equ 0x3F        ; white
WM_BAR          equ 0x01        ; blue
WM_BAR_TEXT     equ 0x3F        ; white
WM_CLIENT       equ 0x07        ; light grey

; eax = x, ebx = y, ecx = width, edx = height, esi = title
; -> eax = window id (0..WM_MAX-1), or -1 if the table is full or the
; window is too small or not wholly on the screen. Does not draw.
wm_create:
    push edi
    push ebp
    cmp ecx, WM_MIN_W
    jl .bad
    cmp edx, WM_MIN_H
    jl .bad
    test eax, eax
    js .bad
    test ebx, ebx
    js .bad
    lea ebp, [eax+ecx]
    cmp ebp, GFX_W
    jg .bad
    lea ebp, [ebx+edx]
    cmp ebp, GFX_H
    jg .bad
    mov edi, wm_table
    xor ebp, ebp
.find:
    cmp byte [edi+WIN_USED], 0
    je .got
    add edi, WIN_SIZE
    inc ebp
    cmp ebp, WM_MAX
    jb .find
.bad:
    mov eax, -1
    jmp .out
.got:
    mov byte [edi+WIN_USED], 1
    mov [edi+WIN_X], eax
    mov [edi+WIN_Y], ebx
    mov [edi+WIN_W], ecx
    mov [edi+WIN_H], edx
    mov [edi+WIN_TITLE], esi
    mov eax, ebp
.out:
    pop ebp
    pop edi
    ret

; eax = window id. Closes it (nothing to do for an id that is not open).
; The caller redraws.
wm_close:
    cmp eax, WM_MAX
    jae .r
    push eax
    imul eax, WIN_SIZE
    mov byte [wm_table+eax+WIN_USED], 0
    pop eax
.r:
    ret

; Paints the desktop, then each open window.
wm_redraw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
    mov byte [gfx_colour], WM_DESKTOP
    call gfx_fillrect
    mov edi, wm_table
    mov ebp, WM_MAX
.w:
    cmp byte [edi+WIN_USED], 0
    je .n
    call wm_draw
.n:
    add edi, WIN_SIZE
    dec ebp
    jnz .w
    popad
    ret

; edi = window record. Frame, title bar with the title, client area.
wm_draw:
    pushad
    mov eax, [edi+WIN_X]        ; the frame: the whole window in WM_FRAME,
    mov ebx, [edi+WIN_Y]        ; then the inside painted over it
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
    mov byte [gfx_colour], WM_FRAME
    call gfx_fillrect
    inc eax                     ; title bar, inside the frame
    inc ebx
    sub ecx, 2
    mov edx, WM_TITLE_H
    mov byte [gfx_colour], WM_BAR
    call gfx_fillrect
    push eax
    push ebx
    push ecx
    add eax, 2                  ; the title, 2 pixels in from each end
    inc ebx
    sub ecx, 4
    mov byte [gfx_colour], WM_BAR_TEXT
    mov byte [gfx_bg], WM_BAR
    mov esi, [edi+WIN_TITLE]
    call wm_drawtitle
    pop ecx
    pop ebx
    pop eax
    add ebx, WM_TITLE_H         ; client area, below the bar
    mov edx, [edi+WIN_H]
    sub edx, WM_TITLE_H + 2
    mov byte [gfx_colour], WM_CLIENT
    call gfx_fillrect
    popad
    ret

; esi = title, eax/ebx = where, ecx = room in pixels: draws as many
; characters as fit.
wm_drawtitle:
    pushad
    mov edi, eax
    add ecx, eax                ; right end of the room
.c:
    mov dl, [esi]
    test dl, dl
    jz .done
    lea ebp, [edi+GFX_CELL_W]
    cmp ebp, ecx
    jg .done
    mov eax, edi
    call gfx_drawchar
    mov edi, ebp
    inc esi
    jmp .c
.done:
    popad
    ret

; wintest: a window on the desktop, a frame pixel read back, then the
; window closed and the same pixel read again (desktop colour now).
WT_X equ 60
WT_Y equ 40
WT_W equ 200
WT_H equ 120

cmd_wintest_run:
    call gfx_mode13
    mov esi, wt_fail
    jc .say                     ; no memory for graphics: still in text mode
    mov byte [gfxt_ok], 1
    call wm_redraw              ; an empty desktop
    mov eax, WT_X
    mov ebx, WT_Y
    mov ecx, WT_W
    mov edx, WT_H
    mov esi, wt_title
    call wm_create
    cmp eax, -1
    je .fail
    mov [wt_id], eax
    call wm_redraw
    mov dl, WM_FRAME            ; left edge, half way down
    call .probe
    mov eax, WT_X + 4           ; the title's first glyph ('T' top row)
    mov ebx, WT_Y + 2
    call gfx_getpixel
    cmp cl, WM_BAR_TEXT
    jne .fail
    mov eax, [wt_id]
    call wm_close
    call wm_redraw
    mov dl, WM_DESKTOP          ; the frame is gone
    call .probe
    jmp .end
.fail:
    mov byte [gfxt_ok], 0
.end:
    call gfx_text
    mov esi, wt_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wt_fail
.say:
    jmp puts
.probe:                         ; dl = expected colour of the frame pixel
    mov eax, WT_X
    mov ebx, WT_Y + WT_H / 2
    call gfx_getpixel
    cmp cl, dl
    je .same
    mov byte [gfxt_ok], 0
.same:
    ret

wt_title db 'Test window', 0
wt_pass db 'win: PASS', 10, 0
wt_fail db 'win: FAIL', 10, 0
align 4
wt_id dd 0
wm_table times WM_MAX * WIN_SIZE db 0
