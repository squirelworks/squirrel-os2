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
                                ; field: the most characters it holds;
                                ; list: how many items
WG_SEL          equ 24          ; list: the selected item, from 0
WG_SIZE         equ 28

WGK_LABEL       equ 1           ; a line of text
WGK_BUTTON      equ 2           ; text in a box; Enter or Space posts an event
WGK_FIELD       equ 3           ; a one-line edit field over a caller's buffer
WGK_LIST        equ 4           ; items in a column, one selected

WK_UP           equ 0x18        ; wg_key codes for the arrow keys (the
WK_DOWN         equ 0x19        ; ASCII control codes CAN and EM)

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
.out:
    pop edx
    pop edi
    ret

; eax = a list's widget id -> eax = its selected item, from 0
wg_selected:
    imul eax, WG_SIZE
    mov eax, [wg_table+eax+WG_SEL]
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
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    call wm_drawtitle           ; as many characters as fit
.out:
    popad
    ret
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
    mov edx, [edi+WG_CODE]
    imul edx, GFX_CELL_H
    add edx, 2 * WG_BTN_PAD + 2
    push edx
    add edx, [edi+WG_Y]
    cmp edx, [wg_ch]
    pop edx
    jg .out                     ; not all rows fit: not drawn
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
    mov edx, GFX_CELL_H
    xor ebp, ebp
.row:
    cmp ebp, [edi+WG_CODE]
    jae .out
    mov esi, [edi+WG_TEXT]
    mov esi, [esi+ebp*4]
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WG_BTN_FILL
    cmp ebp, [edi+WG_SEL]
    jne .rowd
    call gfx_fillrect           ; the selected row: a black bar,
    mov byte [gfx_colour], WG_BTN_FILL
    mov byte [gfx_bg], WM_TEXT  ; white text on it
.rowd:
    call wm_drawtitle
    add ebx, GFX_CELL_H
    inc ebp
    jmp .row
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

; listtest: a window with a label and a list of four names. Keys go to the
; widgets until Enter or Esc; Down and Up move the selection. Then a pixel
; of the selected row under its text is read back (black: the bar) and the selected
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
    cmp byte [bt_box], WM_TEXT
    jne .say
    mov esi, ls_pass
    call puts
    mov eax, [ls_sel]
    mov esi, [ls_items+eax*4]
    call puts
    mov esi, wf_nl
.say:
    jmp puts

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
wg_table times WG_MAX * WG_SIZE db 0
