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
WG_STATE        equ 3           ; byte: button: 1 while pressed in (2.3-bevel-default)
WG_X            equ 4           ; relative to the client area's top left
WG_Y            equ 8
WG_TEXT         equ 12          ; zero-terminated string
WG_PID          equ 16          ; button: the process its events go to
WG_CODE         equ 20          ; button: the low 24 bits of its event;
                                ; field: the most characters it holds;
                                ; list: how many items
WG_SEL          equ 24          ; list: the selected item, from 0
WG_TOP          equ 28          ; list: the first item shown (2.0.2)
WG_ROWS         equ 32          ; list: how many rows fit, from the last draw
WG_SIZE         equ 36

WGK_LABEL       equ 1           ; a line of text
WGK_BUTTON      equ 2           ; text in a box; Enter or Space posts an event
WGK_FIELD       equ 3           ; a one-line edit field over a caller's buffer
WGK_LIST        equ 4           ; items in a column, one selected
WGK_CONSOLE     equ 5           ; an 80 x 25 text screen buffer, shown in part
WGK_GROUP       equ 6           ; an etched frame with a caption (2.3-bevel-default)

WK_UP           equ 0x18        ; wg_key codes for the arrow keys (the
WK_DOWN         equ 0x19        ; ASCII control codes CAN and EM)
WK_DEL          equ 0x7F        ; Delete (1.9.2)
WK_LEFT         equ 0x11        ; DC1 / DC2 for the side arrows (2.2-sysmenu)
WK_RIGHT        equ 0x12

MSG_BUTTON      equ 0x42000000  ; 'B' in the top byte, the button's code below
WG_BTN_PAD      equ 2           ; pixels between a button's box and its text
WG_BTN_FILL     equ TH_BTN_FACE ; theme.inc: inside fields and lists
WG_PRESS_T      equ 8           ; ticks a button shows pressed in after a key

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

; eax = window id, ebx = x, ecx = y, esi = text, edx = code
; -> eax = widget id, or -1. Enter or Space, while the button's window has
; the focus, posts MSG_BUTTON | code (low 24 bits) to the process that
; added the button. The caller redraws.
wg_button:
    push edi
    push edx
    push edx
    mov dl, WGK_BUTTON
    call wg_new
    pop edx
    cmp eax, -1
    je .out
    imul edi, eax, WG_SIZE
    add edi, wg_table
    and edx, 0x00FFFFFF
    mov [edi+WG_CODE], edx
    mov edx, [proc_cur]
    mov edx, [edx+PCB_PID]
    mov [edi+WG_PID], edx
.out:
    pop edx
    pop edi
    ret

; eax = window id, ebx = x, ecx = y, esi = buffer (zero-terminated, room
; for edx characters and the zero), edx = most characters
; -> eax = widget id, or -1. Keys typed while its window has the focus
; edit the buffer in place. The caller redraws.
wg_field:
    push edi
    push edx
    push edx
    mov dl, WGK_FIELD
    call wg_new
    pop edx
    cmp eax, -1
    je .out
    imul edi, eax, WG_SIZE
    add edi, wg_table
    mov [edi+WG_CODE], edx
.out:
    pop edx
    pop edi
    ret

; eax = window id, ebx = x, ecx = y, esi = items (an array of edx
; addresses of zero-terminated strings), edx = how many (at least 1)
; -> eax = widget id, or -1. The first item is selected; WK_DOWN and WK_UP
; move the selection. The caller redraws.
wg_list:
    push edi
    push edx
    push edx
    mov dl, WGK_LIST
    call wg_new
    pop edx
    cmp eax, -1
    je .out
    imul edi, eax, WG_SIZE
    add edi, wg_table
    mov [edi+WG_CODE], edx
    mov dword [edi+WG_SEL], 0
    mov dword [edi+WG_TOP], 0
    mov dword [edi+WG_ROWS], 0
.out:
    pop edx
    pop edi
    ret

; eax = window id, ebx = x, ecx = y, esi = caption, edx = width | height
; << 16 -> eax = widget id, or -1. A group box: an etched frame whose top
; edge runs through the caption's middle; it takes no keys. The caller
; redraws. (2.3-bevel-default)
wg_group:
    push edi
    push edx
    push edx
    mov dl, WGK_GROUP
    call wg_new
    pop edx
    cmp eax, -1
    je .out
    imul edi, eax, WG_SIZE
    add edi, wg_table
    push edx
    and edx, 0xFFFF
    mov [edi+WG_CODE], edx      ; width
    pop edx
    shr edx, 16
    mov [edi+WG_SEL], edx       ; height
.out:
    pop edx
    pop edi
    ret

; eax = a button's widget id, dl = 1 pressed in / 0 out. The caller
; redraws. (2.3-bevel-default)
wg_press:
    push edi
    cmp eax, WG_MAX
    jae .r
    imul edi, eax, WG_SIZE
    add edi, wg_table
    mov [edi+WG_STATE], dl
.r:
    pop edi
    ret

; eax = a list's widget id, ebx = a row as drawn (0 = the top row shown)
; -> eax = the item in that row, CF clear; CF set if the row is not shown
; or holds no item. Since 2.0.2 a list scrolls, so row and item differ by
; WG_TOP once it has.
wg_list_item:
    push edi
    imul edi, eax, WG_SIZE
    add edi, wg_table
    cmp ebx, [edi+WG_ROWS]
    jae .no
    mov eax, [edi+WG_TOP]
    add eax, ebx
    cmp eax, [edi+WG_CODE]
    jae .no
    pop edi
    clc
    ret
.no:
    pop edi
    stc
    ret

; eax = window id, ebx = x, ecx = y, esi = an 80 x 25 text buffer (char,
; attribute words, as at 0xB8000), edx = rows shown -> eax = widget id or
; -1. Shows as many columns as fit, and edx rows: the first ones, or the
; ones that end at the cursor row ([cur]) once it is further down. Takes no
; keys. The caller redraws.
wg_console:
    push edi
    push edx
    push edx
    mov dl, WGK_CONSOLE
    call wg_new
    pop edx
    cmp eax, -1
    je .out
    imul edi, eax, WG_SIZE
    add edi, wg_table
    mov [edi+WG_CODE], edx
.out:
    pop edx
    pop edi
    ret

; eax = a list's widget id -> eax = its selected item, from 0
wg_selected:
    imul eax, WG_SIZE
    mov eax, [wg_table+eax+WG_SEL]
    ret

; eax = a list's widget id, ebx = item index: sets the selection if in range
wg_setsel:
    push edi
    imul edi, eax, WG_SIZE
    add edi, wg_table
    cmp ebx, [edi+WG_CODE]
    jae .r
    mov [edi+WG_SEL], ebx
.r:
    pop edi
    ret

; al = ASCII of a key (8 for Backspace, WK_UP and WK_DOWN for the arrows) -> CF clear if a widget used it,
; CF set if not (the caller can use it itself). The key goes to the first
; widget of the focused window that takes keys:
;   button: Enter (10 or 13) or Space posts its event;
;   field:  a printable character is appended if there is room (a key
;           that does not fit is still used), Backspace deletes the last;
;   list:   WK_DOWN and WK_UP move the selection, stopping at the ends.
wg_key:
    pushad
    mov dl, al
    call wm_focus
    cmp eax, -1
    je .no
    mov edi, wg_table
    mov ecx, WG_MAX
.w:
    cmp byte [edi+WG_USED], 0
    je .n
    cmp [edi+WG_WIN], al
    jne .n
    cmp byte [edi+WG_KIND], WGK_BUTTON
    je .button
    cmp byte [edi+WG_KIND], WGK_FIELD
    je .field
    cmp byte [edi+WG_KIND], WGK_LIST
    je .list
.n:
    add edi, WG_SIZE
    loop .w
.no:
    popad
    stc
    ret
.button:
    cmp dl, 10
    je .post
    cmp dl, 13
    je .post
    cmp dl, ' '
    jne .no
.post:
    call wg_flash               ; it presses in for a moment (2.3-bevel-default)
    mov ebx, [edi+WG_PID]
    mov ecx, [edi+WG_CODE]
    or ecx, MSG_BUTTON
    pushfd
    cli                         ; the keyboard IRQ posts to queues too
    call msg_put                ; a full queue drops the event
    popfd
.used:
    popad
    clc
    ret
.field:
    cmp dl, WK_COPY             ; the clipboard keys (2.3-clipboard)
    je .clip
    cmp dl, WK_PASTE
    je .clip
    cmp dl, WK_CUT
    je .clip
    mov esi, [edi+WG_TEXT]
    call strlen                 ; eax = characters now
    cmp dl, 8
    je .bs
    cmp dl, ' '
    jb .no
    cmp dl, 0x7E
    ja .no
    cmp eax, [edi+WG_CODE]
    jae .used                   ; full
    mov [esi+eax], dl
    mov byte [esi+eax+1], 0
    jmp .used
.bs:
    test eax, eax
    jz .used
    mov byte [esi+eax-1], 0
    jmp .used
.clip:
    call clip_field
    jmp .used
.list:
    mov eax, [edi+WG_SEL]
    cmp dl, WK_DOWN
    je .down
    cmp dl, WK_UP
    jne .no
    test eax, eax
    jz .used                    ; at the top already
    dec eax
    jmp .sel
.down:
    inc eax
    cmp eax, [edi+WG_CODE]
    jae .used                   ; at the bottom already
.sel:
    mov [edi+WG_SEL], eax
    jmp .used

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
    mov byte [edi+WG_STATE], 0
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
    mov esi, [edi+WG_TEXT]
    cmp byte [edi+WG_KIND], WGK_BUTTON
    je .button
    cmp byte [edi+WG_KIND], WGK_FIELD
    je .field
    cmp byte [edi+WG_KIND], WGK_LIST
    je .list
    cmp byte [edi+WG_KIND], WGK_CONSOLE
    je .console
    cmp byte [edi+WG_KIND], WGK_GROUP
    je .group
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    call wm_drawtitle           ; as many characters as fit
.out:
    popad
    ret
.console:                       ; rows of the buffer, cut to the client area
    mov edx, [edi+WG_CODE]
    imul edx, GFX_CELL_H
    add edx, [edi+WG_Y]
    cmp edx, [wg_ch]
    jg .out                     ; not all rows fit: not drawn
    mov edx, [cur]              ; the cell the cursor is in (1.6.4)
    lea edx, [esi+edx*2]
    mov [wg_curp], edx
    push eax
    mov eax, [cur]              ; the first row shown
    xor edx, edx
    mov ebp, 80
    div ebp
    sub eax, [edi+WG_CODE]
    inc eax                     ; so that the cursor row is the last one
    jns .first
    xor eax, eax
.first:
    imul eax, 160
    add esi, eax
    pop eax
    mov ebp, [edi+WG_CODE]
.crow:
    push eax
    push ecx
    push esi
.cch:
    cmp ecx, GFX_CELL_W
    jl .crd                     ; no room for another column
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    xor dl, dl
    test byte [esi+1], 0x70     ; a background colour (a status bar)
    setnz dl
    cmp esi, [wg_curp]          ; the cursor's cell
    jne .cinv
    xor dl, 1                   ; is drawn inverted (1.6.4)
.cinv:
    test dl, dl
    jz .cnorm
    mov byte [gfx_colour], WM_CLIENT
    mov byte [gfx_bg], WM_TEXT
.cnorm:
    mov dl, [esi]
    call gfx_drawchar
    add eax, GFX_CELL_W
    sub ecx, GFX_CELL_W
    add esi, 2
    jmp .cch
.crd:
    pop esi
    pop ecx
    pop eax
    add esi, 160
    add ebx, GFX_CELL_H
    dec ebp
    jnz .crow
    jmp .out
.list:                          ; a box as wide as the longest item, one
    push eax                    ; row per item, the selected one inverted
    xor edx, edx
    mov ebp, [edi+WG_CODE]
.lw:
    test ebp, ebp
    jz .lwd
    push esi
    mov esi, [esi]
    call strlen
    pop esi
    cmp eax, edx
    jbe .lws
    mov edx, eax
.lws:
    add esi, 4
    dec ebp
    jmp .lw
.lwd:
    pop eax
    imul edx, GFX_CELL_W
    add edx, 2 * WG_BTN_PAD + 2
    cmp edx, ecx
    jle .lfit
    mov edx, ecx                ; cut at the client area's right edge
.lfit:
    mov ecx, edx
    ; as many rows as fit below WG_Y (2.0.2: before, a list taller than
    ; the client area was not drawn at all), scrolled so that the
    ; selection is one of them
    mov edx, [wg_ch]
    sub edx, [edi+WG_Y]
    sub edx, 2 * WG_BTN_PAD + 2
    jle .out
    push eax
    push ecx
    mov eax, edx
    xor edx, edx
    mov ecx, GFX_CELL_H
    div ecx                     ; eax = rows that fit
    pop ecx
    cmp eax, [edi+WG_CODE]
    jbe .lrows
    mov eax, [edi+WG_CODE]
.lrows:
    mov [edi+WG_ROWS], eax
    test eax, eax
    jnz .lshow
    pop eax
    jmp .out
.lshow:
    mov edx, [edi+WG_SEL]
    cmp edx, [edi+WG_TOP]
    jae .ltop1
    mov [edi+WG_TOP], edx       ; selection above the window: scroll up
.ltop1:
    mov edx, [edi+WG_TOP]
    add edx, eax
    cmp [edi+WG_SEL], edx
    jb .ltop2
    mov edx, [edi+WG_SEL]       ; below it: scroll down to it
    sub edx, eax
    inc edx
    mov [edi+WG_TOP], edx
.ltop2:
    mov edx, [edi+WG_CODE]
    sub edx, eax
    cmp [edi+WG_TOP], edx
    jbe .ltop3
    mov [edi+WG_TOP], edx       ; no empty rows at the bottom
.ltop3:
    imul edx, eax, GFX_CELL_H
    add edx, 2 * WG_BTN_PAD + 2
    pop eax
    mov byte [gfx_colour], WG_BTN_FILL
    call gfx_fillrect           ; white inside a sunken bevel (2.3-bevel-default)
    push esi
    mov esi, 1
    call gfx_bevel
    pop esi
    inc eax
    inc ebx
    sub ecx, 2
    add eax, WG_BTN_PAD
    add ebx, WG_BTN_PAD
    sub ecx, 2 * WG_BTN_PAD
    mov edx, GFX_CELL_H
    mov ebp, [edi+WG_TOP]
.row:
    push eax
    mov eax, [edi+WG_TOP]
    add eax, [edi+WG_ROWS]
    cmp ebp, eax
    pop eax
    jae .out
    mov esi, [edi+WG_TEXT]
    mov esi, [esi+ebp*4]
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WG_BTN_FILL
    cmp ebp, [edi+WG_SEL]
    jne .rowd
    mov byte [gfx_colour], TH_SELECT
    call gfx_fillrect           ; the selected row: the theme's bar,
    mov byte [gfx_colour], TH_SELECT_TEXT
    mov byte [gfx_bg], TH_SELECT ; its text on it
.rowd:
    call wm_drawtext5           ; lists keep the 5 x 7 rows
    add ebx, GFX_CELL_H
    inc ebp
    jmp .row
.field:                         ; a box as wide as its most characters, an
    push eax                    ; underline cursor after the text
    mov eax, [edi+WG_CODE]
    jmp .boxw
.button:                        ; a black box, white inside, the text in it
    push eax
    push ecx
    mov ecx, FONT_9
    call gfx_strwidth_p         ; eax = the text's width (2.2-propfont)
    pop ecx
    mov edx, eax
    pop eax
    jmp .boxp
.boxw:
    imul edx, eax, GFX_CELL_W
    pop eax
.boxp:
    add edx, 2 * WG_BTN_PAD + 2 ; the box's width
.boxh:
    push edx
    mov edx, [edi+WG_Y]
    add edx, GFX_CELL_H + 2 * WG_BTN_PAD + 2
    cmp edx, [wg_ch]
    pop edx
    jg .out
    cmp edx, ecx
    jle .fits
    mov edx, ecx                ; cut at the client area's right edge
.fits:
    mov ecx, edx
    mov edx, GFX_CELL_H + 2 * WG_BTN_PAD + 2
    ; Warp bevels (2.3-bevel-default): a field is white and sunken; a
    ; button is face grey and raised, or sunken while pressed in
    mov byte [gfx_colour], WG_BTN_FILL
    mov byte [wg_ink_bg], WG_BTN_FILL
    push esi
    mov esi, 1
    cmp byte [edi+WG_KIND], WGK_FIELD
    je .bev
    mov byte [gfx_colour], TH_FACE
    mov byte [wg_ink_bg], TH_FACE
    movzx esi, byte [edi+WG_STATE]
.bev:
    call gfx_fillrect
    call gfx_bevel
    mov [wg_pin], esi           ; 1: the text moves down and right by one
    pop esi
    inc eax
    inc ebx
    sub ecx, 2
    add eax, WG_BTN_PAD
    add ebx, WG_BTN_PAD
    sub ecx, 2 * WG_BTN_PAD
    mov byte [gfx_colour], WM_TEXT
    mov dl, [wg_ink_bg]
    mov [gfx_bg], dl
    cmp byte [edi+WG_KIND], WGK_FIELD
    je .ftext
    cmp byte [edi+WG_KIND], WGK_BUTTON
    jne .btext
    add eax, [wg_pin]
    add ebx, [wg_pin]
.btext:
    call wm_drawtitle
    jmp .out
.ftext:
    call wm_drawtext5           ; a field's cursor goes by 6 x 8 cells
    push eax                    ; the cursor: an underline in the next cell
    call strlen
    imul edx, eax, GFX_CELL_W
    pop eax
    add eax, edx
    add edx, FONT_W
    cmp edx, ecx
    jg .out                     ; full, or cut off
    add ebx, GFX_CELL_H - 1
    mov ecx, FONT_W
    mov edx, 1
    call gfx_fillrect
    jmp .out

.group:                         ; an etched frame, the caption on its top edge
    mov edx, [edi+WG_CODE]      ; the width, cut at the client's right edge
    cmp edx, ecx
    jle .gw
    mov edx, ecx
.gw:
    mov ecx, edx
    mov edx, [edi+WG_SEL]       ; the height, cut at its bottom
    mov ebp, [wg_ch]
    sub ebp, [edi+WG_Y]
    cmp edx, ebp
    jle .gh
    mov edx, ebp
.gh:
    sub edx, WG_GROUP_TOP
    cmp edx, 4
    jl .out
    cmp ecx, 4
    jl .out
    push ebx
    add ebx, WG_GROUP_TOP
    call wg_etch
    pop ebx
    cmp byte [esi], 0
    je .out
    add eax, WG_GROUP_CAP       ; the caption, over the top edge
    sub ecx, WG_GROUP_CAP + 2
    jle .out
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    call wm_drawtitle
    jmp .out

WG_GROUP_TOP    equ 4           ; the frame's top edge, below the caption's top
WG_GROUP_CAP    equ 6           ; the caption's left, from the frame's

; eax, ebx = top left, ecx = width, edx = height (at least 2 each): an
; etched frame, a shadow outline with a light one a pixel down and right.
wg_etch:
    pushad
    dec ecx
    dec edx
    inc eax
    inc ebx
    mov byte [gfx_colour], TH_LIGHT
    call wg_outline
    dec eax
    dec ebx
    mov byte [gfx_colour], TH_SHADOW
    call wg_outline
    popad
    ret

; eax, ebx, ecx, edx = a rectangle -> its one-pixel outline in gfx_colour
wg_outline:
    pushad
    push edx
    mov edx, 1
    call gfx_fillrect           ; top
    pop edx
    push ebx
    add ebx, edx
    dec ebx
    push edx
    mov edx, 1
    call gfx_fillrect           ; bottom
    pop edx
    pop ebx
    push ecx
    mov ecx, 1
    call gfx_fillrect           ; left
    pop ecx
    add eax, ecx
    dec eax
    mov ecx, 1
    call gfx_fillrect           ; right
    popad
    ret

; edi = a button: shows it pressed in for WG_PRESS_T ticks, then out again
; (the caller's redraw shows it out). Keeps all registers. If the clock
; does not run (interrupts off), it waits a bounded time instead.
wg_flash:
    pushad
    mov byte [edi+WG_STATE], 1
    call wm_redraw
    mov eax, [ticks]
    mov ecx, 20000000
.w:
    mov edx, [ticks]
    sub edx, eax
    cmp edx, WG_PRESS_T
    jae .up
    pause
    loop .w
.up:
    mov byte [edi+WG_STATE], 0
    popad
    ret

; labeltest: a window with a label; an ink pixel and a background pixel
; of the label read back. Then the window is closed and a new one opened
; in its place: the label must be gone with the old window.
LT_X equ 60
LT_Y equ 40
LT_LX equ 4                     ; the label, in the client area
LT_LY equ 5                     ; level with the text inside a box at y = 2
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

; buttontest: a window with a label and a button. Keys go to the widgets
; until Esc; then the shell's queue is read. One Enter (or Space) on the
; press on the button must have posted one MSG_BUTTON with its code, and
; nothing else may have arrived. Prints the number of events.
BT_CODE equ 0x0B7
BT_BX equ 4                     ; the button, in the client area
BT_BY equ 16

cmd_buttontest_run:
    call .drain                 ; nothing old in the shell's queue
    call gfx_mode13
    jnc .ok
    mov esi, bt_nomem
    jmp puts
.ok:
    mov eax, LT_X
    mov ebx, LT_Y
    mov ecx, 200
    mov edx, 100
    mov esi, bt_title
    call wm_create
    mov [lt_win], eax
    mov ebx, LT_LX
    mov ecx, LT_LY
    mov esi, bt_label
    call wg_label
    mov eax, [lt_win]
    mov ebx, BT_BX
    mov ecx, BT_BY
    mov esi, bt_text
    mov edx, BT_CODE
    call wg_button
    call wm_redraw
    mov eax, LT_X + 1 + BT_BX   ; the box's top left: a raised bevel's light
    mov ebx, LT_Y + 1 + WM_TITLE_H + BT_BY
    call gfx_getpixel
    mov [bt_box], cl
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key
    cmp al, 0x01
    je .end
    call kbd_ascii
    test al, al
    jz .key
    call wg_key
    jmp .key
.end:
    mov eax, [lt_win]
    call wm_close
    call gfx_text
    cmp byte [bt_box], TH_LIGHT
    jne .bad
    mov dword [bt_n], 0
    mov dword [bt_other], 0
.read:                          ; count what arrived
    mov edi, [proc_cur]
    call msg_slot
    cmp byte [msg_count+eax], 0
    je .count
    call sys_recv
    cmp eax, MSG_BUTTON | BT_CODE
    jne .other
    inc dword [bt_n]
    jmp .read
.other:
    inc dword [bt_other]
    jmp .read
.count:
    cmp dword [bt_other], 0
    jne .bad
    mov esi, bt_none
    cmp dword [bt_n], 0
    je .say
    mov esi, bt_pass            ; "button: PASS (n)", n events
    call puts
    mov eax, [bt_n]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, bt_pass2
    jmp .say
.bad:
    mov esi, bt_fail
.say:
    jmp puts
.drain:
    mov edi, [proc_cur]
    call msg_slot
    cmp byte [msg_count+eax], 0
    je .drained
    call sys_recv
    jmp .drain
.drained:
    ret

bt_title db 'Buttons', 0
bt_label db 'Press Enter:', 0
bt_text db 'OK', 0
bt_pass db 'button: PASS (', 0
bt_pass2 db ')', 10, 0
bt_fail db 'button: FAIL', 10, 0
bt_none db 'button: no event', 10, 0
bt_nomem db 'button: no memory for graphics', 10, 0
bt_box db 0
wg_ink_bg db 0
align 4
wg_pin dd 0
bt_n dd 0
bt_other dd 0

; fieldtest: a window with a label and an edit field. Keys go to the
; widgets until Enter or Esc (which the field does not use). Then a pixel
; of the field's box is read back and the field's text is printed:
; field: PASS "text".
FT_FX equ 44                    ; the field, in the client area, 10 pixels
                                ; right of the 5-character label
FT_FY equ 2
FT_MAX equ 16

cmd_fieldtest_run:
    mov byte [fd_buf], 0
    call gfx_mode13
    jnc .ok
    mov esi, fd_nomem
    jmp puts
.ok:
    mov eax, LT_X
    mov ebx, LT_Y
    mov ecx, 200
    mov edx, 100
    mov esi, fd_title
    call wm_create
    mov [lt_win], eax
    mov ebx, LT_LX
    mov ecx, LT_LY
    mov esi, fd_label
    call wg_label
    mov eax, [lt_win]
    mov ebx, FT_FX
    mov ecx, FT_FY
    mov esi, fd_buf
    mov edx, FT_MAX
    call wg_field
.draw:
    call wm_redraw
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key
    cmp al, 0x01
    je .end
    call clip_key               ; Ctrl+Ins, Shift+Ins, ... (2.3-clipboard)
    jnc .send2
    mov ah, 8
    cmp al, 0x0E                ; Backspace
    je .send
    call kbd_ascii
    mov ah, al
    test al, al
    jz .key
.send:
    mov al, ah
.send2:
    call wg_key
    jnc .draw
    cmp al, 10                  ; Enter: not the field's
    jne .key
.end:
    mov eax, LT_X + 1 + FT_FX   ; the box's top left: a sunken bevel's shadow
    mov ebx, LT_Y + 1 + WM_TITLE_H + FT_FY
    call gfx_getpixel
    mov [bt_box], cl
    mov eax, [lt_win]
    call wm_close
    call gfx_text
    mov esi, fd_fail
    cmp byte [bt_box], TH_SHADOW
    jne .say
    mov esi, fd_pass
    call puts
    mov esi, fd_buf
    call puts
    mov esi, fd_end
.say:
    jmp puts

; listtest: a window with a label and a list of four names. Keys go to the
; widgets until Enter or Esc; Down and Up move the selection. Then a pixel
; of the selected row under its text is read back (the theme's selection bar) and the selected
; name is printed: list: <name>.
LS_X equ 44                     ; the list, in the client area, 10 pixels
                                ; right of the 5-character label
LS_Y equ 2

cmd_listtest_run:
    call gfx_mode13
    jnc .ok
    mov esi, ls_nomem
    jmp puts
.ok:
    mov eax, LT_X
    mov ebx, LT_Y
    mov ecx, 200
    mov edx, 100
    mov esi, ls_title
    call wm_create
    mov [lt_win], eax
    mov ebx, LT_LX
    mov ecx, LT_LY
    mov esi, ls_label
    call wg_label
    mov eax, [lt_win]
    mov ebx, LS_X
    mov ecx, LS_Y
    mov esi, ls_items
    mov edx, LS_N
    call wg_list
    mov [ls_id], eax
.draw:
    call wm_redraw
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key                    ; releases, and the 0xE0 before an arrow
    cmp al, 0x01
    je .end
    mov ah, WK_DOWN
    cmp al, 0x50
    je .send
    mov ah, WK_UP
    cmp al, 0x48
    je .send
    call kbd_ascii
    mov ah, al
    test al, al
    jz .key
.send:
    mov al, ah
    call wg_key
    jnc .draw
    cmp al, 10                  ; Enter: not the list's
    jne .key
.end:
    mov eax, [ls_id]
    call wg_selected
    mov [ls_sel], eax
    imul ebx, eax, GFX_CELL_H   ; the selected row's bottom left pixel: in
    add ebx, LT_Y + 1 + WM_TITLE_H + LS_Y + 1 + WG_BTN_PAD + GFX_CELL_H - 1
    mov eax, LT_X + 1 + LS_X + 1 + WG_BTN_PAD  ; the bar, below the glyph
    call gfx_getpixel
    mov [bt_box], cl
    mov eax, [lt_win]
    call wm_close
    call gfx_text
    mov esi, ls_fail
    cmp byte [bt_box], TH_SELECT
    jne .say
    mov esi, ls_pass
    call puts
    mov eax, [ls_sel]
    mov esi, [ls_items+eax*4]
    call puts
    mov esi, wf_nl
.say:
    jmp puts

; scrolltest (2.0.2): a list of ten items in a window that shows only a
; few rows. Moves the selection to item 8, redraws, and checks that the
; list scrolled (WG_TOP > 0, the selection still shown), that
; wg_list_item maps the rows drawn to the right items, and that the
; selection bar is on the screen row the item is drawn in. Prints
; scroll: PASS or scroll: FAIL.
SC_N equ 10
SC_X equ 4
SC_Y equ 2
SC_SEL equ 8

cmd_scrolltest_run:
    call gfx_mode13
    jnc .ok
    mov esi, sc_nomem
    jmp puts
.ok:
    pushad
    mov byte [sc_ok], 1
    mov eax, LT_X
    mov ebx, LT_Y
    mov ecx, 160
    mov edx, 60
    mov esi, sc_title
    call wm_create
    mov [lt_win], eax
    mov ebx, SC_X
    mov ecx, SC_Y
    mov esi, sc_items
    mov edx, SC_N
    call wg_list
    mov [sc_id], eax
    call wm_redraw
    imul edi, eax, WG_SIZE
    add edi, wg_table
    mov eax, [edi+WG_ROWS]
    cmp eax, 2                  ; the window must show some rows ...
    jb .bad
    cmp eax, SC_N               ; ... but not all of them
    jae .bad
    mov ecx, SC_SEL
.down:
    mov al, WK_DOWN
    push ecx
    push edi
    call wg_key
    pop edi
    pop ecx
    loop .down
    call wm_redraw
    cmp dword [edi+WG_SEL], SC_SEL
    jne .bad
    mov eax, [edi+WG_TOP]
    test eax, eax
    jz .bad                     ; did not scroll
    mov edx, SC_SEL
    sub edx, eax                ; the selection's row as drawn
    jb .bad
    cmp edx, [edi+WG_ROWS]
    jae .bad
    mov [sc_row], edx
    ; rows map to items past the scroll
    mov eax, [sc_id]
    xor ebx, ebx
    call wg_list_item
    jc .bad
    cmp eax, [edi+WG_TOP]
    jne .bad
    mov eax, [sc_id]
    mov ebx, [sc_row]
    call wg_list_item
    jc .bad
    cmp eax, SC_SEL
    jne .bad
    mov eax, [sc_id]
    mov ebx, [edi+WG_ROWS]
    call wg_list_item
    jnc .bad                    ; past the last row shown
    ; the bar is drawn in the selection's row, not in row 0
    imul ebx, [sc_row], GFX_CELL_H
    add ebx, LT_Y + 1 + WM_TITLE_H + SC_Y + 1 + WG_BTN_PAD + GFX_CELL_H - 1
    mov eax, LT_X + 1 + SC_X + 1 + WG_BTN_PAD
    call gfx_getpixel
    cmp cl, TH_SELECT
    jne .bad
    mov ebx, LT_Y + 1 + WM_TITLE_H + SC_Y + 1 + WG_BTN_PAD + GFX_CELL_H - 1
    mov eax, LT_X + 1 + SC_X + 1 + WG_BTN_PAD
    call gfx_getpixel
    cmp cl, WG_BTN_FILL
    je .done
.bad:
    mov byte [sc_ok], 0
.done:
    mov eax, [lt_win]
    call wm_close
    call gfx_text
    mov esi, sc_pass
    cmp byte [sc_ok], 1
    je .say
    mov esi, sc_fail
.say:
    call puts
    popad
    ret

sc_title db 'Scroll', 0
sc_i0 db 'Item 0', 0
sc_i1 db 'Item 1', 0
sc_i2 db 'Item 2', 0
sc_i3 db 'Item 3', 0
sc_i4 db 'Item 4', 0
sc_i5 db 'Item 5', 0
sc_i6 db 'Item 6', 0
sc_i7 db 'Item 7', 0
sc_i8 db 'Item 8', 0
sc_i9 db 'Item 9', 0
sc_pass db 'scroll: PASS', 10, 0
sc_fail db 'scroll: FAIL', 10, 0
sc_nomem db 'scroll: no memory for graphics', 10, 0
sc_ok db 0
align 4
sc_items dd sc_i0, sc_i1, sc_i2, sc_i3, sc_i4, sc_i5, sc_i6, sc_i7, sc_i8, sc_i9
sc_id dd 0
sc_row dd 0

LS_N equ 4
ls_title db 'Lists', 0
ls_label db 'Pick:', 0
ls_i0 db 'Acorn', 0
ls_i1 db 'Beech', 0
ls_i2 db 'Cedar', 0
ls_i3 db 'Dogwood', 0
ls_pass db 'list: ', 0
ls_fail db 'list: FAIL', 10, 0
ls_nomem db 'list: no memory for graphics', 10, 0
align 4
ls_items dd ls_i0, ls_i1, ls_i2, ls_i3
ls_id dd 0
ls_sel dd 0

fd_title db 'Fields', 0
fd_label db 'Name:', 0
fd_pass db 'field: PASS "', 0
fd_end db '"', 10, 0
fd_fail db 'field: FAIL', 10, 0
fd_nomem db 'field: no memory for graphics', 10, 0
fd_buf times FT_MAX + 1 db 0

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
wg_curp dd 0                    ; console: address of the cursor's cell
wg_table times WG_MAX * WG_SIZE db 0

; ---------- bevwidgets (2.3-bevel-default) ----------
; A window with a button, a field, a list and a group box in mode 13h; the
; corners and faces of each are read back: the button raised (light top
; left, dark bottom, face grey), then pressed in (shadow top left, light
; bottom); the field and the list sunken (shadow, then dark, light bottom,
; white inside) with the list's selection bar; the group box etched
; (shadow over light) with its caption cutting the top edge. Prints
; bevwidgets: PASS or bevwidgets: FAIL at N.
BW_X    equ 20
BW_Y    equ 110
BW_CX   equ BW_X + 1                    ; the client area's top left
BW_CY   equ BW_Y + 1 + WM_TITLE_H
BW_BX   equ 4                           ; the button
BW_BY   equ 4
BW_FX   equ 4                           ; the field
BW_FY   equ 24
BW_LX   equ 120                         ; the list
BW_LY   equ 4
BW_GX   equ 4                           ; the group box
BW_GY   equ 44
BW_GW   equ 100
BW_GH   equ 26
BW_BOXH equ GFX_CELL_H + 2 * WG_BTN_PAD + 2

cmd_bevwidgets_run:
    call gfx_mode13
    jnc .ok
    mov esi, bt_nomem
    jmp puts
.ok:
    pushad
    mov dword [bw_n], 0
    mov eax, BW_X
    mov ebx, BW_Y
    mov ecx, 280
    mov edx, 86
    mov esi, bw_title
    call wm_create
    mov [lt_win], eax
    cmp eax, -1
    je .fail
    mov ebx, BW_BX
    mov ecx, BW_BY
    mov esi, bt_text
    mov edx, 1
    call wg_button
    mov [bw_btn], eax
    mov eax, [lt_win]
    mov ebx, BW_FX
    mov ecx, BW_FY
    mov esi, bw_ftext
    mov edx, 8
    call wg_field
    mov eax, [lt_win]
    mov ebx, BW_LX
    mov ecx, BW_LY
    mov esi, ls_items
    mov edx, 3
    call wg_list
    mov eax, [lt_win]
    mov ebx, BW_GX
    mov ecx, BW_GY
    mov esi, bw_gtext
    mov edx, BW_GW | (BW_GH << 16)
    call wg_group
    cmp eax, -1
    je .fail
    call wm_redraw
    mov esi, bw_probes1
    call .probes
    jc .fail
    mov eax, [bw_btn]           ; pressed in
    mov dl, 1
    call wg_press
    call wm_redraw
    mov esi, bw_probes2
    call .probes
    jc .fail
    mov edi, BW_CX + BW_GX + WG_GROUP_CAP + 1   ; the caption covers the edge
    mov ebx, BW_CY + BW_GY + WG_GROUP_TOP
    xor edx, edx
.cap:
    mov eax, edi
    call gfx_getpixel
    cmp cl, TH_SHADOW
    je .capn
    inc edx
.capn:
    inc edi
    cmp edi, BW_CX + BW_GX + WG_GROUP_CAP + 20
    jb .cap
    inc dword [bw_n]
    cmp edx, 10                 ; most of those pixels are the caption's
    jb .fail
    mov esi, bw_pass
    jmp .end
.fail:
    mov esi, bw_fail
.end:
    push esi
    mov eax, [lt_win]
    cmp eax, -1
    je .closed
    call wm_close
.closed:
    call gfx_text
    pop esi
    call puts
    cmp esi, bw_fail
    jne .r
    mov eax, [bw_n]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
.r:
    popad
    ret
; esi = probes (x, y as words, colour as a byte; x = 0 ends) -> CF set at
; the first wrong pixel, [bw_n] counting them
.probes:
    movzx eax, word [esi]
    test eax, eax
    jz .pok
    inc dword [bw_n]
    movzx ebx, word [esi+2]
    call gfx_getpixel
    cmp cl, [esi+4]
    jne .pbad
    add esi, 5
    jmp .probes
.pok:
    clc
    ret
.pbad:
    stc
    ret

%macro BWP 3
    dw %1, %2
    db %3
%endmacro
bw_probes1:
    BWP BW_CX + BW_BX, BW_CY + BW_BY, TH_LIGHT                  ; 1 button: raised
    BWP BW_CX + BW_BX + 1, BW_CY + BW_BY + 1, TH_LIGHT          ; 2
    BWP BW_CX + BW_BX, BW_CY + BW_BY + BW_BOXH - 1, TH_DARK     ; 3
    BWP BW_CX + BW_BX + 1, BW_CY + BW_BY + BW_BOXH - 2, TH_SHADOW ; 4
    BWP BW_CX + BW_BX + 2, BW_CY + BW_BY + 2, TH_FACE           ; 5
    BWP BW_CX + BW_FX, BW_CY + BW_FY, TH_SHADOW                 ; 6 field: sunken
    BWP BW_CX + BW_FX + 1, BW_CY + BW_FY + 1, TH_DARK           ; 7
    BWP BW_CX + BW_FX, BW_CY + BW_FY + BW_BOXH - 1, TH_LIGHT    ; 8
    BWP BW_CX + BW_FX + 2, BW_CY + BW_FY + 2, WG_BTN_FILL       ; 9
    BWP BW_CX + BW_LX, BW_CY + BW_LY, TH_SHADOW                 ; 10 list: sunken
    BWP BW_CX + BW_LX + 1, BW_CY + BW_LY + 1, TH_DARK           ; 11
    BWP BW_CX + BW_LX + 2, BW_CY + BW_LY + 2, WG_BTN_FILL       ; 12
    BWP BW_CX + BW_LX + 1 + WG_BTN_PAD, BW_CY + BW_LY + 1 + WG_BTN_PAD + GFX_CELL_H - 1, TH_SELECT ; 13 its bar
    BWP BW_CX + BW_GX + 2, BW_CY + BW_GY + WG_GROUP_TOP, TH_SHADOW     ; 14 group: etched
    BWP BW_CX + BW_GX + 2, BW_CY + BW_GY + WG_GROUP_TOP + 1, TH_LIGHT  ; 15
    BWP BW_CX + BW_GX, BW_CY + BW_GY + 14, TH_SHADOW            ; 16
    BWP BW_CX + BW_GX + 1, BW_CY + BW_GY + 14, TH_LIGHT         ; 17
    BWP BW_CX + BW_GX + 30, BW_CY + BW_GY + 16, WM_CLIENT       ; 18 inside
    dw 0
bw_probes2:
    BWP BW_CX + BW_BX, BW_CY + BW_BY, TH_SHADOW                 ; 19 pressed in
    BWP BW_CX + BW_BX + 1, BW_CY + BW_BY + 1, TH_DARK           ; 20
    BWP BW_CX + BW_BX, BW_CY + BW_BY + BW_BOXH - 1, TH_LIGHT    ; 21
    BWP BW_CX + BW_BX + 2, BW_CY + BW_BY + 2, TH_FACE           ; 22
    dw 0

bw_title db 'Bevels', 0
bw_ftext db 'abc', 0
bw_gtext db 'Mouse', 0
bw_pass db 'bevwidgets: PASS', 10, 0
bw_fail db 'bevwidgets: FAIL at ', 0
align 4
bw_n dd 0
bw_btn dd 0
