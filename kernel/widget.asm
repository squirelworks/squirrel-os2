; Squirrel-OS/2 — widgets (1.5)
; Included from pm.asm. Original code.
;
; Widgets live inside windows (wm.asm). Each one belongs to a window and
; sits at a place relative to the window's client area; wm_draw draws a
; window's widgets after its client area, and wm_close drops them.
; See documentation/kernel/widgets.md.

WG_MAX          equ 16          ; widgets at most, in all windows

; widget record
WG_USED         equ 0           ; byte: 1 while the widget exists
WG_KIND         equ 1           ; byte: WGK_*
WG_WIN          equ 2           ; byte: the window's id
WG_X            equ 4           ; relative to the client area's top left
WG_Y            equ 8
WG_TEXT         equ 12          ; zero-terminated string
WG_SIZE         equ 16

WGK_LABEL       equ 1           ; a line of text

; eax = window id, ebx = x, ecx = y (in the client area), esi = text
; -> eax = widget id, or -1 if the window is not open or the table is full.
; The caller redraws.
wg_label:
    push edi
    push edx
    mov dl, WGK_LABEL
    call wg_new
    pop edx
    pop edi
    ret

; dl = kind, eax = window id, ebx = x, ecx = y, esi = text -> eax = id or -1
wg_new:
    push ebp
    push edi
    call wm_record              ; the window must be open
    jc .bad
    mov edi, wg_table
    xor ebp, ebp
.find:
    cmp byte [edi+WG_USED], 0
    je .got
    add edi, WG_SIZE
    inc ebp
    cmp ebp, WG_MAX
    jb .find
.bad:
    mov eax, -1
    jmp .out
.got:
    mov byte [edi+WG_USED], 1
    mov [edi+WG_KIND], dl
    mov [edi+WG_WIN], al
    mov [edi+WG_X], ebx
    mov [edi+WG_Y], ecx
    mov [edi+WG_TEXT], esi
    mov eax, ebp
.out:
    pop edi
    pop ebp
    ret

; eax = window id: removes all of its widgets.
wg_drop:
    pushad
    mov edi, wg_table
    mov ecx, WG_MAX
.w:
    cmp byte [edi+WG_USED], 0
    je .n
    cmp [edi+WG_WIN], al
    jne .n
    mov byte [edi+WG_USED], 0
.n:
    add edi, WG_SIZE
    loop .w
    popad
    ret

; edi = window record, eax/ebx = its client area's top left, ecx/edx = its
; width and height: draws the window's widgets, each cut to the client area
; (a widget whose text row does not fit is not drawn).
wg_drawall:
    pushad
    mov [wg_cx], eax
    mov [wg_cy], ebx
    mov [wg_cw], ecx
    mov [wg_ch], edx
    mov eax, edi                ; the window's id
    sub eax, wm_table
    xor edx, edx
    mov ecx, WIN_SIZE
    div ecx
    mov edi, wg_table
    mov ebp, WG_MAX
.w:
    cmp byte [edi+WG_USED], 0
    je .n
    cmp [edi+WG_WIN], al
    jne .n
    call wg_draw
.n:
    add edi, WG_SIZE
    dec ebp
    jnz .w
    popad
    ret

; edi = widget record; the client area in wg_cx/cy/cw/ch.
wg_draw:
    pushad
    mov eax, [edi+WG_Y]
    add eax, GFX_CELL_H
    cmp eax, [wg_ch]
    jg .out                     ; below the client area
    mov ecx, [wg_cw]
    sub ecx, [edi+WG_X]
    jle .out                    ; right of it
    mov eax, [wg_cx]
    add eax, [edi+WG_X]
    mov ebx, [wg_cy]
    add ebx, [edi+WG_Y]
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    mov esi, [edi+WG_TEXT]
    call wm_drawtitle           ; as many characters as fit
.out:
    popad
    ret

; labeltest: a window with a label; an ink pixel and a background pixel
; of the label read back. Then the window is closed and a new one opened
; in its place: the label must be gone with the old window.
LT_X equ 60
LT_Y equ 40
LT_LX equ 4                     ; the label, in the client area
LT_LY equ 4
LT_PX equ LT_X + 1 + LT_LX      ; its first glyph's top left on the screen
LT_PY equ LT_Y + 1 + WM_TITLE_H + LT_LY

cmd_labeltest_run:
    call gfx_mode13
    mov esi, lt_fail
    jc .say
    mov byte [gfxt_ok], 1
    call .open
    jc .fail
    mov dl, WM_CLIENT           ; nothing there before the label
    call .probe
    mov eax, [lt_win]
    mov ebx, LT_LX
    mov ecx, LT_LY
    mov esi, lt_text
    call wg_label
    cmp eax, -1
    je .fail
    call wm_redraw
    mov dl, WM_TEXT             ; 'N': ink in the top left corner
    call .probe
    mov eax, LT_PX + 1          ; ... and background next to it
    mov ebx, LT_PY
    call gfx_getpixel
    cmp cl, WM_CLIENT
    jne .fail
    mov eax, [lt_win]           ; a new window in the same slot
    call wm_close
    call .open
    jc .fail
    mov dl, WM_CLIENT           ; has no label
    call .probe
    mov eax, [lt_win]
    call wm_close
    jmp .end
.fail:
    mov byte [gfxt_ok], 0
    mov eax, [lt_win]
    call wm_close
.end:
    call gfx_text
    mov esi, lt_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, lt_fail
.say:
    jmp puts
.open:                          ; -> CF if no window
    mov eax, LT_X
    mov ebx, LT_Y
    mov ecx, 200
    mov edx, 100
    mov esi, lt_title
    call wm_create
    mov [lt_win], eax
    cmp eax, -1
    stc
    je .r
    call wm_redraw
    clc
.r:
    ret
.probe:                         ; dl = expected colour at the glyph's corner
    mov eax, LT_PX
    mov ebx, LT_PY
    call gfx_getpixel
    cmp cl, dl
    je .same
    mov byte [gfxt_ok], 0
.same:
    ret

lt_title db 'Labels', 0
lt_text db 'Name: Squirrel', 0
lt_pass db 'label: PASS', 10, 0
lt_fail db 'label: FAIL', 10, 0
align 4
lt_win dd -1
wg_cx dd 0
wg_cy dd 0
wg_cw dd 0
wg_ch dd 0
wg_table times WG_MAX * WG_SIZE db 0
