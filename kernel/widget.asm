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
WG_PID          equ 16          ; button: the process its events go to
WG_CODE         equ 20          ; button: the low 24 bits of its event;
                                ; field: the most characters it holds
WG_SIZE         equ 24

WGK_LABEL       equ 1           ; a line of text
WGK_BUTTON      equ 2           ; text in a box; Enter or Space posts an event
WGK_FIELD       equ 3           ; a one-line edit field over a caller's buffer

MSG_BUTTON      equ 0x42000000  ; 'B' in the top byte, the button's code below
WG_BTN_PAD      equ 2           ; pixels between a button's box and its text
WG_BTN_FILL     equ 0x3F        ; white

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

; al = ASCII of a key (8 for Backspace) -> CF clear if a widget used it,
; CF set if not (the caller can use it itself). The key goes to the first
; widget of the focused window that takes keys:
;   button: Enter (10 or 13) or Space posts its event;
;   field:  a printable character is appended if there is room (a key
;           that does not fit is still used), Backspace deletes the last.
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
    mov esi, [edi+WG_TEXT]
    cmp byte [edi+WG_KIND], WGK_BUTTON
    je .button
    cmp byte [edi+WG_KIND], WGK_FIELD
    je .field
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    call wm_drawtitle           ; as many characters as fit
.out:
    popad
    ret
.field:                         ; a box as wide as its most characters, an
    push eax                    ; underline cursor after the text
    mov eax, [edi+WG_CODE]
    jmp .boxw
.button:                        ; a black box, white inside, the text in it
    push eax
    call strlen                 ; eax = characters
.boxw:
    imul edx, eax, GFX_CELL_W
    pop eax
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
    mov byte [gfx_colour], WM_TEXT
    call gfx_fillrect
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    mov byte [gfx_colour], WG_BTN_FILL
    call gfx_fillrect
    add eax, WG_BTN_PAD
    add ebx, WG_BTN_PAD
    sub ecx, 2 * WG_BTN_PAD
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WG_BTN_FILL
    call wm_drawtitle
    cmp byte [edi+WG_KIND], WGK_FIELD
    jne .out
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
    mov eax, LT_X + 1 + BT_BX   ; the box's top left: black
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
    cmp byte [bt_box], WM_TEXT
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
align 4
bt_n dd 0
bt_other dd 0

; fieldtest: a window with a label and an edit field. Keys go to the
; widgets until Enter or Esc (which the field does not use). Then a pixel
; of the field's box is read back and the field's text is printed:
; field: PASS "text".
FT_FX equ 40                    ; the field, in the client area
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
    mov ah, 8
    cmp al, 0x0E                ; Backspace
    je .send
    call kbd_ascii
    mov ah, al
    test al, al
    jz .key
.send:
    mov al, ah
    call wg_key
    jnc .draw
    cmp al, 10                  ; Enter: not the field's
    jne .key
.end:
    mov eax, LT_X + 1 + FT_FX   ; the box's top left: black
    mov ebx, LT_Y + 1 + WM_TITLE_H + FT_FY
    call gfx_getpixel
    mov [bt_box], cl
    mov eax, [lt_win]
    call wm_close
    call gfx_text
    mov esi, fd_fail
    cmp byte [bt_box], WM_TEXT
    jne .say
    mov esi, fd_pass
    call puts
    mov esi, fd_buf
    call puts
    mov esi, fd_end
.say:
    jmp puts

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
wg_table times WG_MAX * WG_SIZE db 0
