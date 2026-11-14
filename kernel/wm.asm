; Squirrel-OS/2 — window manager (1.4)
; Included from pm.asm. Original code.
;
; Windows in graphics mode, drawn with the 1.3 primitives (gfx.asm). A
; window is a rectangle with a one-pixel frame, a title bar with its title,
; and a client area. wm_redraw paints the desktop and then every open
; window, bottom of the z-order first. The top window has the keyboard
; focus. Keyboard only. See documentation/kernel/windows.md.

WM_MAX          equ 16          ; open windows at most (4 before 2.2-clip-z)

; window record
%include "theme.inc"     ; W.1: colours and sizes

WIN_USED        equ 0           ; byte: 1 while the window is open
WIN_X           equ 4
WIN_Y           equ 8
WIN_W           equ 12          ; outer size, frame included
WIN_H           equ 16
WIN_TITLE       equ 20          ; zero-terminated string
WIN_LEN         equ 24          ; characters typed into the window
WIN_BUF         equ 28          ; WM_BUF characters and a zero
WIN_FLAGS       equ 56          ; WF_* (2.2-frame)
WIN_STATE       equ 60          ; WS_* (2.2-mouse)
WIN_REST        equ 64          ; x, y, w, h to restore from maximised
WIN_ICONIC      equ 80          ; 1 while minimised to an icon (2.2-minmax)
WIN_OWNER       equ 84          ; pid whose program opened it, -1 = kernel
WIN_TBUF        equ 88          ; a program window's title, copied (2.2-progwin)
WM_TBUF         equ 32
WIN_PAINT       equ WIN_TBUF + WM_TBUF  ; 0, or code that paints the client (2.3-groups)
WIN_SIZE        equ WIN_PAINT + 4
WS_NORMAL       equ 0
WS_MAX          equ 1
WS_MIN          equ 2
WM_BUF          equ 24

WM_TITLE_H      equ GFX_CELL_H + 2  ; title bar: one text row and a margin
WM_BOX          equ WM_TITLE_H  ; a title-bar box: square, the bar's height
WM_GRIP         equ 3           ; the sizing band along each edge (wm_hit)
WM_CORNER       equ 8           ; how far a corner reaches along an edge
WF_SIZABLE      equ 1           ; flags (2.2-frame)
WF_MINBOX       equ 2
WF_MAXBOX       equ 4
WF_SYSMENU      equ 8
WF_CLOSEBOX     equ 16
WF_DEFAULT      equ 31
HT_CLIENT       equ 0           ; wm_hit parts
HT_TITLE        equ 1
HT_SYSMENU      equ 2
HT_MIN          equ 3
HT_MAX          equ 4
HT_CLOSE        equ 5
HT_L            equ 6
HT_R            equ 7
HT_T            equ 8
HT_B            equ 9
HT_TL           equ 10
HT_TR           equ 11
HT_BL           equ 12
HT_BR           equ 13
HT_ICON         equ 14          ; a minimised window's icon (2.2-minmax)
WM_ICON_W       equ 72
WM_ICON_H       equ 20
WM_ICON_GAP     equ 8
WM_MIN_W        equ 5 * WM_BOX + 8  ; room for the boxes and a little title
WM_MIN_H        equ WM_TITLE_H + 4

; colours: aliases of the theme's names (kernel/theme.inc)
WM_DESKTOP      equ TH_DESKTOP     ; theme.inc
WM_FRAME        equ TH_FRAME     ; theme.inc
WM_BAR          equ TH_TITLE     ; theme.inc
WM_BAR_IDLE     equ TH_TITLE_IDLE     ; theme.inc
WM_BAR_TEXT     equ TH_TITLE_TEXT     ; theme.inc
WM_CLIENT       equ TH_CLIENT     ; theme.inc
WM_TEXT         equ TH_TEXT     ; theme.inc

; eax = x, ebx = y, ecx = width, edx = height, esi = title
; -> eax = window id (0..WM_MAX-1), or -1 if the table is full or the
; window is too small or not wholly on the screen. The new window goes on
; top of the z-order and gets the focus. Does not draw.
wm_create:
    call wm_fits
    jc .bad
    push edi
    push ebp
    mov edi, wm_table
    xor ebp, ebp
.find:
    cmp byte [edi+WIN_USED], 0
    je .got
    add edi, WIN_SIZE
    inc ebp
    cmp ebp, WM_MAX
    jb .find
    pop ebp
    pop edi
.bad:
    mov eax, -1
    ret
.got:
    mov byte [edi+WIN_USED], 1
    mov [edi+WIN_X], eax
    mov [edi+WIN_Y], ebx
    mov [edi+WIN_W], ecx
    mov [edi+WIN_H], edx
    mov [edi+WIN_TITLE], esi
    mov dword [edi+WIN_LEN], 0
    mov byte [edi+WIN_BUF], 0
    mov dword [edi+WIN_FLAGS], WF_DEFAULT
    mov dword [edi+WIN_STATE], WS_NORMAL
    mov dword [edi+WIN_ICONIC], 0
    mov dword [edi+WIN_OWNER], -1
    mov dword [edi+WIN_PAINT], 0
    call wm_markwin             ; its place needs painting (2.2-clip-z)
    call wm_marktop             ; the old top loses the focus colour
    mov eax, ebp
    mov ebp, [wm_zn]            ; on top
    mov [wm_z+ebp], al
    inc dword [wm_zn]
    pop ebp
    pop edi
    ret

; eax = x, ebx = y, ecx = width, edx = height -> CF if the window would be
; smaller than WM_MIN_W x WM_MIN_H, or its title bar would not be on the
; screen: since 2.2-clip-z a window may hang off the left, right and bottom
; edges, but its top edge stays on the screen and the bar keeps at least
; one column and its whole height there, so the mouse can still grab it.
wm_fits:
    push ebp
    cmp ecx, WM_MIN_W
    jl .no
    cmp edx, WM_MIN_H
    jl .no
    test ebx, ebx
    js .no
    lea ebp, [ebx+WM_TITLE_H+1]
    cmp ebp, [gfx_height]
    jg .no
    cmp eax, [gfx_width]
    jge .no
    lea ebp, [eax+ecx]
    cmp ebp, 1
    jl .no
    pop ebp
    clc
    ret
.no:
    pop ebp
    stc
    ret

; eax = window id -> edi = its record, or CF if the id is not an open window.
wm_record:
    cmp eax, WM_MAX
    jae .no
    imul edi, eax, WIN_SIZE
    add edi, wm_table
    cmp byte [edi+WIN_USED], 0
    je .no
    clc
    ret
.no:
    stc
    ret

; eax = window id, ebx = new x, ecx = new y. CF (and the window unchanged)
; if the id is not open or the window would leave the screen. The caller
; redraws.
wm_move:
    pushad
    call wm_record
    jc .out
    mov eax, ebx
    mov ebx, ecx
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
    call wm_fits
    jc .out
    call wm_markwin             ; where it was
    mov [edi+WIN_X], eax
    mov [edi+WIN_Y], ebx
    call wm_markwin             ; and where it is now
.out:
    popad
    ret

; eax = window id, ebx = new width, ecx = new height; the top left corner
; stays. CF (and the window unchanged) as wm_move, or if it is too small.
wm_resize:
    pushad
    call wm_record
    jc .out
    mov edx, ecx
    mov ecx, ebx
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    call wm_fits
    jc .out
    call wm_markwin
    mov [edi+WIN_W], ecx
    mov [edi+WIN_H], edx
    call wm_markwin
.out:
    popad
    ret

; eax = window id. Closes it (nothing to do for an id that is not open).
; The caller redraws.
wm_close:
    push edi
    call wm_record
    jc .r
    call wm_markwin             ; what was under it shows again
    mov byte [edi+WIN_USED], 0
    call wm_zremove
    call wg_drop                ; and its widgets
.r:
    pop edi
    ret

; eax = an open window's id: takes it out of the z-order list.
wm_zremove:
    pushad
    xor ecx, ecx
.f:
    cmp [wm_z+ecx], al
    je .shift
    inc ecx
    cmp ecx, [wm_zn]
    jb .f
    jmp .out
.shift:
    dec dword [wm_zn]
.s:
    cmp ecx, [wm_zn]
    jae .out
    mov dl, [wm_z+ecx+1]
    mov [wm_z+ecx], dl
    inc ecx
    jmp .s
.out:
    popad
    ret

; eax = window id: puts it on top of the z-order, which gives it the focus.
; CF if the id is not open. The caller redraws.
wm_raise:
    push edi
    call wm_record
    jc .r
    call wm_markwin             ; all of it is on top now
    call wm_marktop             ; and the old top's title bar goes idle
    call wm_zremove
    push ebp
    mov ebp, [wm_zn]
    mov [wm_z+ebp], al
    inc dword [wm_zn]
    pop ebp
    clc
.r:
    pop edi
    ret

; The bottom window comes to the top (Tab): with two windows, the focus
; goes back and forth. The caller redraws.
wm_cycle:
    cmp dword [wm_zn], 2
    jb .r
    push eax
    movzx eax, byte [wm_z]
    call wm_raise
    pop eax
.r:
    ret

; -> eax = the focused window's id (the top one), or -1 if none is open.
wm_focus:
    mov eax, -1
    cmp dword [wm_zn], 0
    je .r
    mov eax, [wm_zn]
    movzx eax, byte [wm_z+eax-1]
.r:
    ret

; al = character: appended to the focused window's text, if there is a
; focused window and room. The caller redraws.
wm_putc:
    pushad
    mov bl, al
    call wm_focus
    call wm_record
    jc .out
    mov ecx, [edi+WIN_LEN]
    cmp ecx, WM_BUF
    jae .out
    mov [edi+WIN_BUF+ecx], bl
    mov byte [edi+WIN_BUF+ecx+1], 0
    inc dword [edi+WIN_LEN]
    call wm_markwin
.out:
    popad
    ret

; Paints the desktop, then each open window, and shows the whole screen
; (a full flip when double buffering). Clears the dirty list.
wm_redraw:
    pushad
    mov byte [ptr_vis], 0       ; the repaint covers the pointer (2.0.1)
    mov dword [wm_dn], 0
    mov byte [wm_dfull], 0
    call wm_paint
    call vbe_flip               ; no marks: the whole page (CF if single)
    popad
    ret

; Paints the desktop and the windows, bottom first, within the clip.
wm_paint:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, [gfx_width]
    mov edx, [gfx_height]
    mov al, [th_desktop]        ; 2.3-control: live scheme
    mov [gfx_colour], al
    call gfx_fillrect
    call wm_icons               ; minimised windows (2.2-minmax)
    xor ebp, ebp
.w:
    cmp ebp, [wm_zn]
    jae .done
    movzx eax, byte [wm_z+ebp]
    imul edi, eax, WIN_SIZE
    add edi, wm_table
    inc ebp
    mov al, [th_title_idle]     ; 2.3-control
    mov [wm_drawbar], al
    cmp ebp, [wm_zn]
    jne .draw
    mov al, [th_title]          ; the top window has the focus
    mov [wm_drawbar], al
.draw:
    call wm_draw
    jmp .w
.done:
    call wm_menudraw            ; a pop-up menu and the Alt+Tab box are on
    call wm_tabdraw             ; top of everything (2.2-sysmenu, 2.2-alttab)
    popad
    ret

; edi = window record. Frame, title bar with the title, client area.
wm_draw:
    pushad
    mov eax, [edi+WIN_X]        ; the frame: the whole window in th_frame,
    mov ebx, [edi+WIN_Y]        ; then the inside painted over it
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
    push edx
    mov dl, [th_frame]          ; 2.3-control
    mov [gfx_colour], dl
    pop edx
    call gfx_fillrect
    inc eax                     ; title bar, inside the frame
    inc ebx
    sub ecx, 2
    push edx
    mov dl, [wm_drawbar]
    mov [gfx_colour], dl
    pop edx
    mov edx, WM_TITLE_H
    call gfx_fillrect
    call wm_boxes               ; the title-bar boxes (2.2-frame)
    push eax
    push ebx
    push ecx
    add eax, [wm_tl]            ; the title, 2 pixels in from the boxes
    sub ecx, [wm_tl]
    sub ecx, [wm_tr]
    add eax, 2
    inc ebx
    sub ecx, 4
    mov dl, [th_title_text]
    mov [gfx_colour], dl
    mov dl, [wm_drawbar]
    mov [gfx_bg], dl
    mov esi, [edi+WIN_TITLE]
    call wm_drawtitle
    pop ecx
    pop ebx
    pop eax
    add ebx, WM_TITLE_H         ; client area, below the bar
    mov edx, [edi+WIN_H]
    sub edx, WM_TITLE_H + 2
    push edx
    mov dl, [th_client]
    mov [gfx_colour], dl
    pop edx
    call gfx_fillrect
    call wg_drawall             ; the window's widgets (widget.asm)
    cmp dword [edi+WIN_PAINT], 0    ; its own painting (2.3-groups): edi =
    je .nopaint                     ; the record, eax..edx = the client area;
    call [edi+WIN_PAINT]            ; keeps every register
.nopaint:
    add eax, 2                  ; the typed text, 2 pixels in
    add ebx, 2
    sub ecx, 4
    mov dl, [th_text]
    mov [gfx_colour], dl
    mov dl, [th_client]
    mov [gfx_bg], dl
    lea esi, [edi+WIN_BUF]
    call wm_drawtext5
    popad
    ret

; esi = title, eax/ebx = where, ecx = room in pixels: draws as many
; characters as fit, in the proportional window face (FONT_9, 2.2-propfont).
; Title bars, menus, icons, Alt+Tab, labels and buttons use it.
wm_drawtitle:
    pushad
    mov edi, eax
    add ecx, eax                ; right end of the room
    push ecx
    mov ecx, FONT_9
    call pf_face
    pop ecx
.c:
    movzx edx, byte [esi]
    test edx, edx
    jz .done
    call pf_index
    mov eax, [ebp]
    movzx eax, byte [eax+edx]
    lea eax, [edi+eax+PF_SPACE]
    cmp eax, ecx
    jg .done
    mov eax, edi
    call pf_glyph
    mov edi, eax
    inc esi
    jmp .c
.done:
    popad
    ret

; As wm_drawtitle in the 5 x 7 font, in 6 x 8 cells: typed text, fields
; and lists, where a character's cell is its place.
wm_drawtext5:
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
    mov eax, WT_X + 4 + WM_BOX  ; the title's first glyph ('T' top row),
                                ; after the system-menu box (2.2-frame)
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

; winmove: a window moved, then resized. After each step the old frame
; pixel must show the desktop and the new one the frame. A move off the
; screen and a resize below the minimum must fail and change nothing.
WM2_X equ 100
WM2_Y equ 60
WM2_W equ 100
WM2_H equ 60

cmd_winmove_run:
    call gfx_mode13
    mov esi, wtm_fail
    jc .say
    mov byte [gfxt_ok], 1
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
    mov esi, wtm_before
    call wt_probes
    mov eax, [wt_id]            ; move
    mov ebx, WM2_X
    mov ecx, WM2_Y
    call wm_move
    jc .fail
    call wm_redraw
    mov esi, wtm_moved
    call wt_probes
    mov eax, [wt_id]            ; resize, top left corner kept
    mov ebx, WM2_W
    mov ecx, WM2_H
    call wm_resize
    jc .fail
    call wm_redraw
    mov esi, wtm_sized
    call wt_probes
    mov eax, [wt_id]            ; the title bar off the right edge: refused
    mov ebx, GFX_W
    mov ecx, WM2_Y
    call wm_move
    jnc .fail
    mov eax, [wt_id]            ; too small: refused
    mov ebx, WM_MIN_W - 1
    mov ecx, WM2_H
    call wm_resize
    jnc .fail
    call wm_redraw              ; so the window must be where it was
    mov esi, wtm_sized
    call wt_probes
    mov eax, [wt_id]
    call wm_close
    jmp .end
.fail:
    mov byte [gfxt_ok], 0
.end:
    call gfx_text
    mov esi, wtm_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wtm_fail
.say:
    jmp puts

; esi = list of (x dd, y dd, colour db), ended by x = -1. Clears gfxt_ok
; if a pixel differs.
wt_probes:
    pushad
.p:
    lodsd
    cmp eax, -1
    je .done
    mov ebx, [esi]
    mov dl, [esi+4]
    add esi, 5
    call gfx_getpixel
    cmp cl, dl
    je .p
    mov byte [gfxt_ok], 0
    jmp .p
.done:
    popad
    ret

wtm_before:                     ; the window at its first place
    dd WT_X, WT_Y + WT_H / 2
    db WM_FRAME
    dd WM2_X, WM2_Y + WM2_H / 2
    db WM_CLIENT                ; inside it, where the moved frame will be
    dd -1
wtm_moved:
    dd WT_X, WT_Y + WT_H / 2
    db WM_DESKTOP               ; the old left edge is gone
    dd WM2_X, WM2_Y + WM2_H / 2
    db WM_FRAME                 ; the new left edge
    dd WM2_X + WT_W - 1, WM2_Y + WT_H - 1
    db WM_FRAME                 ; the new bottom right corner
    dd -1
wtm_sized:
    dd WM2_X + WT_W - 1, WM2_Y + WT_H - 1
    db WM_DESKTOP               ; the old corner is gone
    dd WM2_X + WM2_W - 1, WM2_Y + WM2_H - 1
    db WM_FRAME                 ; the new bottom right corner
    dd WM2_X + WM2_W, WM2_Y + WM2_H / 2
    db WM_DESKTOP               ; just right of the new right edge
    dd -1

; winfocus: two overlapping windows, One and Two (Two on top). Keys:
; Tab brings the other window to the top and gives it the focus, other
; characters go to the focused window, Enter or Esc ends. Then a pixel
; where Two's left edge crosses One's client area tells which window is
; drawn on top, and each window's text is printed.
WF1_X equ 40
WF1_Y equ 30
WF2_X equ 100
WF2_Y equ 70
WF_W equ 160
WF_H equ 100

cmd_winfocus_run:
    call gfx_mode13
    jnc .ok
    mov esi, wf_nomem
    jmp puts
.ok:
    mov dword [wf_end], wf_tail
    mov byte [wf_tail], 0
    mov eax, WF1_X
    mov ebx, WF1_Y
    mov ecx, WF_W
    mov edx, WF_H
    mov esi, wf_one
    call wm_create
    mov [wf_ids], eax
    mov eax, WF2_X
    mov ebx, WF2_Y
    mov esi, wf_two
    call wm_create
    mov [wf_ids+4], eax
.draw:
    call wm_redraw
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key                    ; releases
    cmp al, 0x0F
    je .tab
    cmp al, 0x1C
    je .end
    cmp al, 0x01
    je .end
    call kbd_ascii
    cmp al, ' '
    jb .key
    call wm_putc
    jmp .draw
.tab:
    call wm_cycle
    jmp .draw
.end:
    mov eax, WF2_X              ; Two's left edge, inside One's client area
    mov ebx, WF2_Y + 30
    call gfx_getpixel
    mov esi, wf_two
    cmp cl, WM_FRAME
    je .top
    mov esi, wf_one             ; One covers it
.top:
    mov [wf_top], esi
    mov ebx, wf_one             ; the text typed into each window
    mov eax, [wf_ids]
    call .take
    mov ebx, wf_two
    mov eax, [wf_ids+4]
    call .take
    mov esi, wf_topis
    call .cat
    mov esi, [wf_top]
    call .cat
    mov esi, wf_nl
    call .cat
    call gfx_text
    mov esi, wf_out
    jmp puts
.take:                          ; eax = id, ebx = name: line into wf_out
    push eax
    call wm_record
    pop eax
    jc .gone
    call wm_close
    mov esi, ebx
    call .cat
    mov esi, wf_got
    call .cat
    lea esi, [edi+WIN_BUF]
    call .cat
    mov esi, wf_endq
.cat:                           ; esi appended at [wf_end]
    push edi
    mov edi, [wf_end]
.c:
    lodsb
    test al, al
    jz .z
    stosb
    jmp .c
.z:
    mov byte [edi], 0
    mov [wf_end], edi
    pop edi
.gone:
    ret

wf_one db 'One', 0
wf_two db 'Two', 0
wf_got db ' got "', 0
wf_endq db '"', 10, 0
wf_nomem db 'winfocus: no memory for graphics', 10, 0
align 4
wf_ids dd 0, 0
wf_top dd 0
wf_end dd 0
wf_topis db 'top: ', 0
wf_nl db 10, 0
wf_out db 'winfocus:', 10           ; then a line for each window and 'top: '
wf_tail times 2 * (WM_BUF + 16) + 16 db 0

wtm_pass db 'winmove: PASS', 10, 0
wtm_fail db 'winmove: FAIL', 10, 0
wt_title db 'Test window', 0
wt_pass db 'win: PASS', 10, 0
wt_fail db 'win: FAIL', 10, 0
align 4
wt_id dd 0
wm_table times WM_MAX * WIN_SIZE db 0
wm_z times WM_MAX db 0          ; open window ids, bottom first
wm_zn dd 0                      ; how many
wm_drawbar db WM_BAR            ; title bar colour for wm_draw

; ---------- the window manager's screen (2.2-vbe-wm) ----------

; Enters the screen the window manager draws on: 640 x 480 at 8 bpp through
; VBE, or mode 13h when VBE is not there or refuses the mode. Colours are
; palette indices either way (the DAC keeps the EGA palette). CF set when
; neither could be entered (no pages to save the text screen).
wm_screen:
    call vbe_setup
    jc .vga
    push eax
    push ebx
    push ecx
    mov eax, WM_SCR_W
    mov ebx, WM_SCR_H
    mov cl, 8
    call vbe_mode
    pop ecx
    pop ebx
    pop eax
    jc .vga
    call vbe_dblbuf             ; draw on the back page (2.2-clip-z); a mode
    clc                         ; without room for two pages draws on the front
    ret
.vga:
    jmp gfx_mode13
.r:
    ret

WM_SCR_W equ 640
WM_SCR_H equ 480

; winvbe: a window right of x = 320 and below y = 200 in the window
; manager's VBE screen; reads back its frame, title bar and title text, then
; closes it and reads the desktop there. Prints `winvbe: PASS`, or
; `winvbe: FAIL` (also when VBE was not entered).
WV_X equ 400
WV_Y equ 300
cmd_winvbe_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 0
    cmp byte [gfx_vbe], 0
    je .text
    mov byte [gfxt_ok], 1
    mov eax, WV_X
    mov ebx, WV_Y
    mov ecx, WT_W
    mov edx, WT_H
    mov esi, wt_title
    call wm_create
    push eax
    call wm_redraw
    mov esi, wv_open
    call wv_expect
    pop eax
    call wm_close
    call wm_redraw
    mov esi, wv_shut
    call wv_expect
.text:
    call gfx_text
.out:
    mov esi, wv_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wv_fail
.say:
    jmp puts

; esi = x (dd), y (dd), colour (db) ..., x = -1 ends; a miss clears gfxt_ok
wv_expect:
    lodsd
    cmp eax, -1
    je .r
    mov ebx, [esi]
    mov dl, [esi+4]
    add esi, 5
    call gfx_getpixel
    cmp cl, dl
    je wv_expect
    mov byte [gfxt_ok], 0
    jmp wv_expect
.r:
    ret

wv_open:
    dd WV_X, WV_Y + WT_H / 2
    db WM_FRAME                 ; left edge
    dd WV_X + WT_W - 1, WV_Y + WT_H - 1
    db WM_FRAME                 ; bottom right corner
    dd WV_X + WT_W / 2, WV_Y + 1
    db WM_BAR                   ; title bar (focused)
    dd WV_X + WT_W / 2, WV_Y + WT_H / 2
    db WM_CLIENT                ; client area
    dd WV_X - 1, WV_Y + WT_H / 2
    db WM_DESKTOP               ; just left of it
    dd -1
wv_shut:
    dd WV_X, WV_Y + WT_H / 2
    db WM_DESKTOP               ; the frame is gone
    dd -1

wv_pass db 'winvbe: PASS', 10, 0
wv_fail db 'winvbe: FAIL', 10, 0

; ---------- dirty areas and partial repaint (2.2-clip-z) ----------
; wm_create, wm_close, wm_move, wm_resize, wm_raise and wm_putc mark the
; screen areas they change. wm_update repaints only those: for each area it
; sets the clip to it and paints the desktop and every window bottom first,
; so a window shows exactly where nothing above it covers it, and pixels
; outside the areas are not written. With double buffering it then flips
; only those areas. More than WM_DIRTY_MAX areas, or wm_invalidate -1,
; repaint the whole screen.

WM_DIRTY_MAX equ 8

; edi = window record: marks its rectangle.
wm_markwin:
    pushad
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
    call wm_mark
    popad
    ret

; eax, ebx = top left, ecx = width, edx = height: marks an area.
wm_mark:
    pushad
    mov edi, [wm_dn]
    cmp edi, WM_DIRTY_MAX
    jb .add
    mov byte [wm_dfull], 1      ; too many: the whole screen
    jmp .r
.add:
    shl edi, 4
    mov [wm_drect+edi], eax
    mov [wm_drect+edi+4], ebx
    mov [wm_drect+edi+8], ecx
    mov [wm_drect+edi+12], edx
    inc dword [wm_dn]
.r:
    popad
    ret

; eax = window id, or -1 for the whole screen: marks it for wm_update.
wm_invalidate:
    cmp eax, -1
    jne .win
    mov byte [wm_dfull], 1
    ret
.win:
    push edi
    call wm_record
    jc .r
    call wm_markwin
.r:
    pop edi
    ret

; Repaints the marked areas (see above) and clears the marks.
wm_update:
    cmp byte [wm_dfull], 0
    jne wm_redraw
    pushad
    xor esi, esi
.a:
    cmp esi, [wm_dn]
    jae .flip
    mov edi, esi
    shl edi, 4
    mov eax, [wm_drect+edi]
    mov ebx, [wm_drect+edi+4]
    mov ecx, [wm_drect+edi+8]
    mov edx, [wm_drect+edi+12]
    call gfx_setclip
    call wm_paint
    call vbe_dirty              ; flip just this (nothing if single)
    inc esi
    jmp .a
.flip:
    call gfx_noclip
    cmp dword [wm_dn], 0
    je .r
    mov byte [ptr_vis], 0       ; the pointer may have been painted over
    call vbe_flip
.r:
    mov dword [wm_dn], 0
    popad
    ret

align 4
wm_dn dd 0
wm_drect times WM_DIRTY_MAX * 4 dd 0
wm_dfull db 0

; winclip: two overlapping windows on the window manager's screen (double
; buffered when VBE is there). A pixel of the desktop, outside both, is
; changed on the back buffer only. The top window is moved away and
; wm_update repaints: the uncovered part of the lower window shows on the
; visible page, the moved window's frame is there, and the changed desktop
; pixel was neither repainted nor flipped. Then a move that leaves the
; window hanging off the right edge is allowed and one past the edge is
; refused, and the table takes 16 windows but not 17. Prints
; `winclip: PASS` or `winclip: FAIL`.
WC_AX equ 100
WC_AY equ 100
WC_BX equ 150
WC_BY equ 150
WC_W equ 200
WC_H equ 150
WC_MX equ 380                   ; where B moves
WC_MY equ 250
WC_PX equ 600                   ; the desktop pixel outside every change
WC_PY equ 20
WC_PC equ 0x2A
cmd_winclip_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 0
    cmp byte [gfx_vbe], 0
    je .text
    call vbe_dblbuf
    jc .text
    mov byte [gfxt_ok], 1
    mov eax, WC_AX
    mov ebx, WC_AY
    mov ecx, WC_W
    mov edx, WC_H
    mov esi, wc_one
    call wm_create
    mov [wc_a], eax
    mov eax, WC_BX
    mov ebx, WC_BY
    mov esi, wc_two
    call wm_create
    mov [wc_b], eax
    call wm_redraw
    mov eax, WC_PX              ; back buffer only
    mov ebx, WC_PY
    mov cl, WC_PC
    call gfx_putpixel
    mov eax, [wc_b]
    mov ebx, WC_MX
    mov ecx, WC_MY
    call wm_move
    jc .fail
    call wm_update
    mov esi, wc_front
    call wc_probes
    mov eax, WC_PX              ; still on the back: not repainted
    mov ebx, WC_PY
    call gfx_getpixel
    cmp cl, WC_PC
    jne .fail
    mov eax, [wc_b]             ; hanging off the right edge: allowed
    mov ebx, WM_SCR_W - 40
    mov ecx, WC_MY
    call wm_move
    jc .fail
    mov eax, [wc_b]             ; the bar wholly past it: refused
    mov ebx, WM_SCR_W
    call wm_move
    jnc .fail
    call wm_update
    mov eax, WM_SCR_W - 40      ; its left edge, on the visible page
    mov ebx, WC_MY + WC_H / 2
    call vbe_front_getpixel
    cmp cl, WM_FRAME
    jne .fail
    mov ebp, 2                  ; fill the table: 16 open, the 17th refused
.more:
    mov eax, ebp
    mov ebx, ebp
    mov ecx, WM_MIN_W
    mov edx, WM_MIN_H
    mov esi, wc_one
    call wm_create
    cmp ebp, WM_MAX
    jae .last
    cmp eax, -1
    je .fail
    inc ebp
    jmp .more
.last:
    cmp eax, -1
    jne .fail
    xor eax, eax                ; close them all
.close:
    push eax
    call wm_close
    pop eax
    inc eax
    cmp eax, WM_MAX
    jb .close
    jmp .text
.fail:
    mov byte [gfxt_ok], 0
    xor eax, eax
    jmp .close
.text:
    call gfx_text
.out:
    mov esi, wc_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wc_fail
.say:
    jmp puts

; esi = x (dd), y (dd), colour (db) ..., read from the visible page
wc_probes:
    lodsd
    cmp eax, -1
    je .r
    mov ebx, [esi]
    mov dl, [esi+4]
    add esi, 5
    call vbe_front_getpixel
    cmp cl, dl
    je wc_probes
    mov byte [gfxt_ok], 0
    jmp wc_probes
.r:
    ret

wc_front:
    dd WC_BX + 20, WC_BY + 40
    db WM_CLIENT                ; where B covered A's client: A shows
    dd WC_BX, WC_AY + WC_H - 20
    db WM_CLIENT                ; B's old left edge, inside A: A's client
    dd WC_AX + WC_W + 10, WC_BY + 40
    db WM_DESKTOP               ; B's old place, beyond A: the desktop
    dd WC_MX, WC_MY + WC_H / 2
    db WM_FRAME                 ; B's new left edge
    dd WC_MX + WC_W / 2, WC_MY + 1
    db WM_BAR                   ; its title bar, still focused
    dd WC_PX, WC_PY
    db WM_DESKTOP               ; the changed pixel was not flipped
    dd -1

align 4
wc_a dd 0
wc_b dd 0
wc_one db 'One', 0
wc_two db 'Two', 0
wc_pass db 'winclip: PASS', 10, 0
wc_fail db 'winclip: FAIL', 10, 0

; ---------- frame: title-bar boxes and hit testing (2.2-frame) ----------

; eax, ebx = the title bar's top left (inside the frame), ecx = its width,
; edi = window record. Draws the system-menu box at the left and the
; minimise, maximise and close boxes at the right, as the flags ask, each a
; raised bevel on the face colour with a small original glyph. Sets wm_tl
; and wm_tr to the room they take on each side.
wm_boxes:
    pushad
    mov dword [wm_tl], 0
    mov dword [wm_tr], 0
    mov ebp, [edi+WIN_FLAGS]
    test ebp, WF_SYSMENU
    jz .right
    mov dl, 0                   ; glyph 0: a bar across the middle
    call wm_box
    mov dword [wm_tl], WM_BOX
.right:
    lea eax, [eax+ecx-WM_BOX]   ; boxes from the right edge leftwards
    test ebp, WF_CLOSEBOX
    jz .max
    mov dl, 1                   ; an X
    call wm_box
    sub eax, WM_BOX
    add dword [wm_tr], WM_BOX
.max:
    test ebp, WF_MAXBOX
    jz .min
    mov dl, 2                   ; a square outline
    call wm_box
    sub eax, WM_BOX
    add dword [wm_tr], WM_BOX
.min:
    test ebp, WF_MINBOX
    jz .r
    mov dl, 3                   ; a short bar at the bottom
    call wm_box
    add dword [wm_tr], WM_BOX
.r:
    popad
    ret

; eax, ebx = a box's top left, dl = glyph (0 sysmenu, 1 close, 2 max, 3 min)
wm_box:
    pushad
    mov ecx, WM_BOX
    push edx
    mov edx, WM_BOX
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi                ; raised
    call gfx_bevel
    pop edx
    mov byte [gfx_colour], TH_TEXT
    add eax, 3                  ; the glyph's square: inside the bevel
    add ebx, 3
    cmp dl, 1
    je .x
    cmp dl, 2
    je .sq
    mov ecx, WM_BOX - 6         ; sysmenu: a bar 2 high across the middle
    mov edx, 2
    cmp byte [esp+20], 3        ; (pushad's edx: dl is the glyph)
    jne .bar
    add ebx, WM_BOX - 8         ; min: the same bar at the bottom
    jmp .fill
.bar:
    add ebx, (WM_BOX - 6) / 2 - 1
.fill:
    call gfx_fillrect
    jmp .r
.x:
    lea ecx, [eax+WM_BOX-7]     ; corner to corner, both ways
    lea edx, [ebx+WM_BOX-7]
    call gfx_line
    xchg eax, ecx
    call gfx_line
    jmp .r
.sq:
    mov ecx, WM_BOX - 6         ; an outline: fill, then the inside back
    mov edx, WM_BOX - 6
    call gfx_fillrect
    inc eax
    add ebx, 2                  ; a thicker top, like a title bar
    sub ecx, 2
    sub edx, 3
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
.r:
    popad
    ret

; eax = x, ebx = y -> eax = the top window under the point, or -1, and
; ebx = the part of it there (HT_*). Edges and corners are a WM_GRIP band
; inside the window's edge, only on a sizable window; a corner reaches
; WM_CORNER along each edge. The top band is the frame row and the one
; below it, so the title-bar boxes stay clickable.
wm_hit:
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ebp, [wm_zn]
.next:
    dec ebp
    js .none
    movzx esi, byte [wm_z+ebp]
    imul edi, esi, WIN_SIZE
    add edi, wm_table
    mov ecx, eax
    sub ecx, [edi+WIN_X]        ; ecx = x within the window
    js .next
    cmp ecx, [edi+WIN_W]
    jge .next
    mov edx, ebx
    sub edx, [edi+WIN_Y]        ; edx = y within it
    js .next
    cmp edx, [edi+WIN_H]
    jge .next
    mov eax, esi                ; found: now which part
    call wm_part
    jmp .out
.none:
    call wm_iconat              ; an icon on the desktop? (2.2-minmax)
    jnc .out
    mov eax, -1
    xor ebx, ebx
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

; edi = record, ecx, edx = a point within it -> ebx = HT_*
wm_part:
    push eax
    mov eax, [edi+WIN_FLAGS]
    test eax, WF_SIZABLE
    jz .inner
    ; the vertical zone: 0 top band, 1 middle, 2 bottom band
    mov ebx, HT_T
    cmp edx, 2
    jb .corner
    mov ebx, [edi+WIN_H]
    sub ebx, WM_GRIP
    cmp edx, ebx
    mov ebx, HT_B
    jge .corner
    mov ebx, HT_L
    cmp ecx, WM_GRIP
    jb .r
    mov ebx, [edi+WIN_W]
    sub ebx, WM_GRIP
    cmp ecx, ebx
    mov ebx, HT_R
    jge .r
    jmp .inner
.corner:                        ; ebx = HT_T or HT_B: a corner near the ends
    cmp ecx, WM_CORNER
    jae .rc
    add ebx, HT_TL - HT_T       ; HT_TL / HT_BL
    cmp ebx, HT_TL
    je .r
    mov ebx, HT_BL
    jmp .r
.rc:
    push eax
    mov eax, [edi+WIN_W]
    sub eax, WM_CORNER
    cmp ecx, eax
    pop eax
    jb .r
    cmp ebx, HT_T
    mov ebx, HT_TR
    je .r
    mov ebx, HT_BR
    jmp .r
.inner:
    mov ebx, HT_CLIENT
    cmp edx, WM_TITLE_H + 1
    jae .r
    mov ebx, HT_TITLE           ; in the bar: maybe a box
    dec ecx                     ; x within the bar
    js .r
    test eax, WF_SYSMENU
    jz .rt
    cmp ecx, WM_BOX
    mov ebx, HT_SYSMENU
    jb .r
    mov ebx, HT_TITLE
.rt:
    push edx
    mov edx, [edi+WIN_W]
    sub edx, 2                  ; the bar's width
    sub edx, ecx                ; edx = 1.. from the bar's right end
    dec edx                     ; 0 for its last column
    js .rtpop
    test eax, WF_CLOSEBOX
    jz .rmax
    cmp edx, WM_BOX
    mov ebx, HT_CLOSE
    jb .rtpop
    sub edx, WM_BOX
.rmax:
    test eax, WF_MAXBOX
    jz .rmin
    cmp edx, WM_BOX
    mov ebx, HT_MAX
    jb .rtpop
    sub edx, WM_BOX
.rmin:
    test eax, WF_MINBOX
    jz .rtitle
    cmp edx, WM_BOX
    mov ebx, HT_MIN
    jb .rtpop
.rtitle:
    mov ebx, HT_TITLE
.rtpop:
    pop edx
.r:
    pop eax
    ret

; eax = window id, ebx = WF_* flags. CF if the id is not open.
wm_setflags:
    push edi
    call wm_record
    jc .r
    mov [edi+WIN_FLAGS], ebx
    call wm_markwin
.r:
    pop edi
    ret

align 4
wm_tl dd 0
wm_tr dd 0

; winhit: in mode 13h, two overlapping windows; wm_hit at each part of the
; lower one (title, the four boxes, the edges, corners, client), of the one
; on top where they overlap, and outside both. Also draws them and reads the
; close box's bevel and glyph. Prints `winhit: PASS` or `winhit: FAIL`.
WH_AX equ 40
WH_AY equ 30
WH_AW equ 200
WH_AH equ 120
WH_BX equ 150
WH_BY equ 100
cmd_winhit_run:
    call gfx_mode13
    mov esi, wh_fail
    jc .say
    mov byte [gfxt_ok], 1
    mov eax, WH_AX
    mov ebx, WH_AY
    mov ecx, WH_AW
    mov edx, WH_AH
    mov esi, wc_one
    call wm_create
    mov [wh_ids], eax
    mov eax, WH_BX
    mov ebx, WH_BY
    mov ecx, 120
    mov edx, 80
    mov esi, wc_two
    call wm_create
    mov [wh_ids+4], eax
    call wm_redraw
    mov esi, wh_probes
.p:
    lodsd
    cmp eax, -1
    je .draw
    mov ebx, [esi]
    movzx edx, byte [esi+4]     ; 0 = One, 1 = Two, 0xFF = none
    movzx ecx, byte [esi+5]
    add esi, 6
    call wm_hit
    cmp dl, 0xFF
    jne .some
    cmp eax, -1
    jne .bad
    jmp .p
.some:
    cmp eax, [wh_ids+edx*4]
    jne .bad
    cmp ebx, ecx
    je .p
.bad:
    mov byte [gfxt_ok], 0
    jmp .p
.draw:
    mov eax, WH_AX + WH_AW - 1 - WM_BOX ; One's close box: outer top left
    mov ebx, WH_AY + 1
    call gfx_getpixel
    cmp cl, TH_LIGHT
    jne .fail
    add eax, 3                  ; the X starts in its glyph square's corner
    add ebx, 3
    call gfx_getpixel
    cmp cl, TH_TEXT
    jne .fail
    mov eax, WH_AX + 1 + WM_BOX / 2 ; the system-menu bar
    mov ebx, WH_AY + 1 + WM_BOX / 2
    call gfx_getpixel
    cmp cl, TH_TEXT
    je .close
.fail:
    mov byte [gfxt_ok], 0
.close:
    mov eax, [wh_ids]
    call wm_close
    mov eax, [wh_ids+4]
    call wm_close
    call gfx_text
    mov esi, wh_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wh_fail
.say:
    jmp puts

; x, y (dd), window (db: 0 One, 1 Two, 0xFF none), part (db); x = -1 ends
wh_probes:
    dd WH_AX + 100, WH_AY + 5
    db 0, HT_TITLE
    dd WH_AX + 5, WH_AY + 5
    db 0, HT_SYSMENU
    dd WH_AX + WH_AW - 7, WH_AY + 5
    db 0, HT_CLOSE
    dd WH_AX + WH_AW - 7 - WM_BOX, WH_AY + 5
    db 0, HT_MAX
    dd WH_AX + WH_AW - 7 - 2 * WM_BOX, WH_AY + 5
    db 0, HT_MIN
    dd WH_AX + WH_AW - 7 - 3 * WM_BOX, WH_AY + 5
    db 0, HT_TITLE
    dd WH_AX + 1, WH_AY + 50
    db 0, HT_L
    dd WH_AX + WH_AW - 2, WH_AY + 50
    db 0, HT_R
    dd WH_AX + 60, WH_AY
    db 0, HT_T
    dd WH_AX + 60, WH_AY + WH_AH - 2
    db 0, HT_B
    dd WH_AX + 1, WH_AY + 1
    db 0, HT_TL
    dd WH_AX + WH_AW - 3, WH_AY
    db 0, HT_TR
    dd WH_AX + 2, WH_AY + WH_AH - 1
    db 0, HT_BL
    dd WH_AX + 60, WH_AY + 50
    db 0, HT_CLIENT
    dd WH_BX - 5, WH_BY + 40
    db 0, HT_CLIENT             ; One, just left of Two
    dd WH_BX + 50, WH_BY + 40
    db 1, HT_CLIENT             ; Two covers One here
    dd WH_BX + 1, WH_BY + 40
    db 1, HT_L
    dd WH_BX + 50, WH_BY + 5
    db 1, HT_TITLE
    dd WH_BX + 119, WH_BY + 79
    db 1, HT_BR
    dd 5, 5
    db 0xFF, 0                  ; the desktop
    dd 300, 190
    db 0xFF, 0
    dd -1

align 4
wh_ids dd 0, 0
wh_pass db 'winhit: PASS', 10, 0
wh_fail db 'winhit: FAIL', 10, 0

; ---------- mouse window management (2.2-mouse) ----------
; wm_mouse takes one mouse state (position and buttons) at a time, from the
; desktop loop or from a script (wm_inject, the same routine). A left-button
; press raises and focuses the window under the pointer, then by part:
; the title starts a move, an edge or corner of a sizable window starts a
; size, the maximise box maximises or restores, the close box and the
; client are reported to the caller. While the button stays down the move
; or size follows the pointer; the release ends it. Nothing is drawn: the
; caller calls wm_update.
;
; In: eax = x, ebx = y, cl = buttons (bit 0 left).
; Out: eax = WME_NONE, or WME_CLIENT (ebx = window, ecx = x | y << 16 in
; the client area), WME_CLOSE (ebx = window: the caller closes it or not),
; WME_SYSMENU (ebx = window). The minimise box minimises (2.2-minmax).

WME_NONE    equ 0
WME_CLIENT  equ 1
WME_CLOSE   equ 2
WME_MIN     equ 3
WME_SYSMENU equ 4

wm_inject:
wm_mouse:
    push edx
    push esi
    push edi
    push ebp
    mov [wm_px], eax
    mov [wm_py], ebx
    mov dl, [wm_mbtn]
    mov [wm_mbtn], cl
    test cl, 1
    jz .up
    test dl, 1
    jz .press
    ; held: follow a move or size
    cmp byte [wm_mmode], 0
    je .none
    call wm_mdrag
    jmp .none
.up:
    mov byte [wm_mmode], 0      ; a release ends any drag
    jmp .none
.press:
    cmp dword [wm_mn], 0        ; a menu is open: it takes the press
    je .nomenu
    call wm_menuclick
    jmp .out
.nomenu:
    call wm_hit
    cmp eax, -1
    je .nolast
    cmp ebx, HT_ICON
    je .icon
    mov dword [wm_lasticon], -1
    mov [wm_mwin], eax
    call wm_raise               ; a click focuses
    call wm_record
    mov esi, [wm_px]            ; the press point and the rectangle now
    mov [wm_mx0], esi
    mov esi, [wm_py]
    mov [wm_my0], esi
    lea esi, [edi+WIN_X]
    push edi
    mov edi, wm_mrect
    movsd
    movsd
    movsd
    movsd
    pop edi
    cmp ebx, HT_CLIENT
    je .client
    cmp ebx, HT_TITLE
    je .title
    cmp ebx, HT_MAX
    je .max
    cmp ebx, HT_CLOSE
    je .close
    cmp ebx, HT_MIN
    je .minbox
    cmp ebx, HT_SYSMENU
    je .sys
    cmp dword [edi+WIN_STATE], WS_MAX
    je .none                    ; a maximised window keeps its size
    mov [wm_mpart], ebx         ; an edge or corner
    mov byte [wm_mmode], 2
    jmp .none
.title:
    cmp dword [edi+WIN_STATE], WS_MAX
    je .none                    ; and its place
    mov byte [wm_mmode], 1
    jmp .none
.max:
    call wm_togglemax
    jmp .none
.minbox:
    mov eax, [wm_mwin]
    jmp .min
.client:
    mov ecx, [wm_py]
    sub ecx, [edi+WIN_Y]
    sub ecx, WM_TITLE_H + 1
    shl ecx, 16
    mov edx, [wm_px]
    sub edx, [edi+WIN_X]
    dec edx
    mov cx, dx
    mov eax, WME_CLIENT
    mov ebx, [wm_mwin]
    jmp .out
.close:
    mov eax, WME_CLOSE
    jmp .ret_win
.min:
    call wm_minimise            ; eax = the window (2.2-minmax)
    jmp .none
.icon:                          ; a second press on the same icon restores
    cmp eax, [wm_lasticon]
    mov [wm_lasticon], eax
    jne .none
    mov dword [wm_lasticon], -1
    call wm_restore
    jmp .none
.nolast:
    mov dword [wm_lasticon], -1
    jmp .none
.sys:
    mov eax, [wm_mwin]          ; the system menu, under its box
    call wm_sysmenu
    jmp .none
.ret_win:
    mov ebx, [wm_mwin]
    jmp .out
.none:
    xor eax, eax
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    ret

; The pointer moved with the button down: move or size [wm_mwin] from the
; rectangle it had at the press (wm_mrect) by the pointer's travel. A place
; wm_fits refuses is skipped (the window stays where it last fitted).
wm_mdrag:
    pushad
    mov ebp, [wm_px]
    sub ebp, [wm_mx0]           ; ebp = dx
    mov esi, [wm_py]
    sub esi, [wm_my0]           ; esi = dy
    mov eax, [wm_mrect]
    mov ebx, [wm_mrect+4]
    mov ecx, [wm_mrect+8]
    mov edx, [wm_mrect+12]
    cmp byte [wm_mmode], 1
    jne .size
    add eax, ebp
    add ebx, esi
    jmp .place
.size:
    mov edi, [wm_mpart]
    movzx edi, byte [wm_sides+edi-HT_L]
    test edi, 1                 ; left edge
    jz .r
    sub ecx, ebp
    add eax, ebp
    cmp ecx, WM_MIN_W
    jge .r
    add eax, ecx                ; too narrow: keep the right edge
    sub eax, WM_MIN_W
    mov ecx, WM_MIN_W
.r:
    test edi, 2                 ; right edge
    jz .t
    add ecx, ebp
    cmp ecx, WM_MIN_W
    jge .t
    mov ecx, WM_MIN_W
.t:
    test edi, 4                 ; top edge
    jz .b
    sub edx, esi
    add ebx, esi
    cmp edx, WM_MIN_H
    jge .b
    add ebx, edx
    sub ebx, WM_MIN_H
    mov edx, WM_MIN_H
.b:
    test edi, 8                 ; bottom edge
    jz .place
    add edx, esi
    cmp edx, WM_MIN_H
    jge .place
    mov edx, WM_MIN_H
.place:
    mov esi, edx
    mov edx, ecx
    mov ecx, ebx
    mov ebx, eax
    mov eax, [wm_mwin]
    call wm_place
    popad
    ret

; which edges each part moves: 1 left, 2 right, 4 top, 8 bottom
wm_sides db 1, 2, 4, 8, 5, 6, 9, 10   ; HT_L, R, T, B, TL, TR, BL, BR

; eax = window id, ebx = x, ecx = y, edx = width, esi = height: moves and
; sizes it in one step. CF (and nothing changed) if the id is not open or
; wm_fits refuses the rectangle.
wm_place:
    pushad
    call wm_record
    jc .out
    mov eax, ebx
    mov ebx, ecx
    mov ecx, edx
    mov edx, esi
    call wm_fits
    jc .out
    call wm_markwin
    mov [edi+WIN_X], eax
    mov [edi+WIN_Y], ebx
    mov [edi+WIN_W], ecx
    mov [edi+WIN_H], edx
    call wm_markwin
    clc
.out:
    popad
    ret

; edi = record of window [wm_mwin]: maximise it to the whole screen, saving
; its rectangle, or restore that rectangle if it is maximised.
wm_togglemax:
    pushad
    test dword [edi+WIN_FLAGS], WF_MAXBOX
    jz .r
    cmp dword [edi+WIN_STATE], WS_MAX
    je .restore
    lea esi, [edi+WIN_X]
    push edi
    add edi, WIN_REST
    movsd
    movsd
    movsd
    movsd
    pop edi
    mov eax, [wm_mwin]
    xor ebx, ebx
    xor ecx, ecx
    mov edx, [gfx_width]
    mov esi, [gfx_height]
    call wm_place
    jc .r
    mov dword [edi+WIN_STATE], WS_MAX
    jmp .r
.restore:
    mov eax, [wm_mwin]
    mov ebx, [edi+WIN_REST]
    mov ecx, [edi+WIN_REST+4]
    mov edx, [edi+WIN_REST+8]
    mov esi, [edi+WIN_REST+12]
    call wm_place
    jc .r
    mov dword [edi+WIN_STATE], WS_NORMAL
.r:
    popad
    ret

align 4
wm_px dd 0
wm_py dd 0
wm_mwin dd 0
wm_mpart dd 0
wm_mx0 dd 0
wm_my0 dd 0
wm_mrect dd 0, 0, 0, 0
wm_mbtn db 0
wm_mmode db 0                   ; 0 none, 1 moving, 2 sizing

; windrag: on the window manager's screen, One at (100, 100) and Two over
; it at (200, 180), both 200 x 150. Scripted mouse states (wm_inject):
; a click on One's title raises it; dragging the title moves it by
; (20, 20); dragging its bottom-right corner sizes it by (30, 20); its left
; edge by 20 to the left; its right edge far to the left stops at the
; minimum width; the maximise box fills the screen and a second click on it
; restores; a client click is reported with client coordinates; the close
; box is reported and the window closed. Each step checks the window's
; rectangle (or the reply). Prints the windows left, then
; `windrag: PASS` or `windrag: FAIL`.
cmd_windrag_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 1
    mov eax, 100
    mov ebx, 100
    mov ecx, 200
    mov edx, 150
    mov esi, wc_one
    call wm_create
    mov [wc_a], eax
    mov eax, 200
    mov ebx, 180
    mov esi, wc_two
    call wm_create
    mov [wc_b], eax
    call wm_redraw
    mov esi, wd_script
.step:
    lodsd                       ; x, or -1 at the end
    cmp eax, -1
    je .done
    mov ebx, [esi]
    mov cl, [esi+4]
    add esi, 5
    call wm_inject
    mov [wd_r], eax             ; the reply
    mov [wd_r+4], ebx
    mov [wd_r+8], ecx
    call wm_update
    lodsb                       ; what to check after it
    cmp al, 0
    je .step
    cmp al, 1
    je .rect
    cmp al, 2
    je .reply
    jmp .step
.rect:                          ; One's x, y, w, h follow
    push esi
    mov eax, [wc_a]
    call wm_record
    pop esi
    jc .bad4
    lea edi, [edi+WIN_X]
    mov ecx, 4
    repe cmpsd
    je .step
    lea esi, [esi+ecx*4]        ; skip what was not compared
    jmp .bad
.bad4:
    add esi, 16
    jmp .bad
.reply:                         ; the reply, its window (0 One) and ecx
    mov eax, [wd_r]
    mov ebx, [wd_r+4]
    mov ecx, [wd_r+8]
    cmp eax, [esi]
    jne .badr
    mov edx, [esi+4]
    mov edx, [wc_a+edx*4]
    cmp ebx, edx
    jne .badr
    cmp eax, WME_CLIENT
    jne .okr
    cmp ecx, [esi+8]
    jne .badr
.okr:
    add esi, 12
    jmp .step
.badr:
    add esi, 12
.bad:
    mov byte [gfxt_ok], 0
    jmp .step
.done:
    mov eax, [wc_a]             ; the close box asked; close One
    call wm_close
    call wm_update
    call wm_focus               ; Two is left, and has the focus
    cmp eax, [wc_b]
    je .closeb
    mov byte [gfxt_ok], 0
.closeb:
    call wm_close
    call gfx_text
.out:
    mov esi, wd_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wd_fail
.say:
    jmp puts

; x, y (dd), buttons (db), check (db: 0 none, 1 One's rect follows as four
; dd, 2 reply: WME_* dd, window dd (0 One, 1 Two), client x | y << 16 dd)
wd_script:
    dd 150, 105                 ; press on One's title (under Two? no: above it)
    db 1, 0
    dd 170, 125                 ; drag
    db 1, 0
    dd 170, 125                 ; release
    db 0, 1
    dd 120, 120, 200, 150
    dd 319, 269                 ; One's bottom-right corner
    db 1, 0
    dd 349, 289
    db 1, 0
    dd 349, 289
    db 0, 1
    dd 120, 120, 230, 170
    dd 121, 200                 ; its left edge, 20 to the left
    db 1, 0
    dd 101, 200
    db 1, 0
    dd 101, 200
    db 0, 1
    dd 100, 120, 250, 170
    dd 348, 200                 ; its right edge, far to the left
    db 1, 0
    dd 0, 200
    db 1, 0
    dd 0, 200
    db 0, 1
    dd 100, 120, WM_MIN_W, 170
    dd 100 + WM_MIN_W - 7 - WM_BOX, 125 ; the maximise box
    db 1, 0
    dd 100 + WM_MIN_W - 7 - WM_BOX, 125
    db 0, 1
    dd 0, 0, WM_SCR_W, WM_SCR_H
    dd WM_SCR_W - 7 - WM_BOX, 5 ; it again, at its new place: restore
    db 1, 0
    dd WM_SCR_W - 7 - WM_BOX, 5
    db 0, 1
    dd 100, 120, WM_MIN_W, 170
    dd 120, 160                 ; a client click
    db 1, 2
    dd WME_CLIENT, 0, 19 | ((160 - 120 - WM_TITLE_H - 1) << 16)
    dd 120, 160
    db 0, 0
    dd 100 + WM_MIN_W - 7, 125  ; the close box
    db 1, 2
    dd WME_CLOSE, 0, 0
    dd 100 + WM_MIN_W - 7, 125
    db 0, 0
    dd -1

align 4
wd_r dd 0, 0, 0
wd_pass db 'windrag: PASS', 10, 0
wd_fail db 'windrag: FAIL', 10, 0

; ---------- minimise to icons (2.2-minmax) ----------
; A minimised window leaves the z-order (so it is not drawn, hit, focused
; or cycled) and shows as an icon along the bottom of the desktop: the
; k-th minimised window in table order has the k-th place from the left.
; The icon is a raised button with the start of the title. Pressing it
; twice in a row (a double click; another press in between starts over)
; restores the window on top, with the size and state it had.

; eax = window id: minimise it. CF if not open or already minimised, or it
; has no minimise box.
wm_minimise:
    pushad
    call wm_record
    jc .out
    test dword [edi+WIN_FLAGS], WF_MINBOX
    jz .no
    cmp dword [edi+WIN_ICONIC], 0
    jne .no
    call wm_zremove
    mov dword [edi+WIN_ICONIC], 1
    mov byte [wm_dfull], 1      ; the icons may all shift: repaint
    clc
    jmp .out
.no:
    stc
.out:
    popad
    ret

; eax = window id: restore a minimised window to the top. CF if it is not
; open or not minimised.
wm_restore:
    pushad
    call wm_record
    jc .out
    cmp dword [edi+WIN_ICONIC], 0
    je .no
    mov dword [edi+WIN_ICONIC], 0
    push ebp
    mov ebp, [wm_zn]
    mov [wm_z+ebp], al
    inc dword [wm_zn]
    pop ebp
    mov byte [wm_dfull], 1
    clc
    jmp .out
.no:
    stc
.out:
    popad
    ret

; eax = window id, ebx = WS_NORMAL, WS_MAX or WS_MIN: minimise, maximise
; or restore it. From WS_MIN, WS_NORMAL / WS_MAX restore the icon first.
wm_setstate:
    pushad
    call wm_record
    jc .out
    mov [wm_mwin], eax
    cmp ebx, WS_MIN
    jne .notmin
    call wm_minimise
    jmp .out
.notmin:
    cmp dword [edi+WIN_ICONIC], 0
    je .size
    call wm_restore
.size:
    cmp [edi+WIN_STATE], ebx
    je .ok
    call wm_togglemax
.ok:
    clc
.out:
    popad
    ret

; Draws the icon of every minimised window.
wm_icons:
    pushad
    mov edi, wm_table
    xor ebp, ebp                ; slot
    xor ecx, ecx
.w:
    cmp byte [edi+WIN_USED], 0
    je .next
    cmp dword [edi+WIN_ICONIC], 0
    je .next
    call wm_iconrect            ; ebp = slot -> eax, ebx
    push ecx
    mov ecx, WM_ICON_W
    mov edx, WM_ICON_H
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi
    call gfx_bevel
    add eax, 4
    add ebx, (WM_ICON_H - GFX_CELL_H) / 2
    mov ecx, WM_ICON_W - 8
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_FACE
    mov esi, [edi+WIN_TITLE]
    call wm_drawtitle
    pop ecx
    inc ebp
.next:
    add edi, WIN_SIZE
    inc ecx
    cmp ecx, WM_MAX
    jb .w
    popad
    ret

; ebp = icon slot -> eax, ebx = its top left
wm_iconrect:
    imul eax, ebp, WM_ICON_W + WM_ICON_GAP
    add eax, WM_ICON_GAP
    mov ebx, [gfx_height]
    sub ebx, WM_ICON_H + WM_ICON_GAP
    ret

; eax = x, ebx = y -> eax = the minimised window whose icon is there and
; ebx = HT_ICON, CF clear; CF set (eax, ebx kept) if none.
wm_iconat:
    pushad
    mov [wm_ix], eax
    mov [wm_iy], ebx
    mov edi, wm_table
    xor ebp, ebp
    xor ecx, ecx
.w:
    cmp byte [edi+WIN_USED], 0
    je .next
    cmp dword [edi+WIN_ICONIC], 0
    je .next
    call wm_iconrect
    mov edx, [wm_ix]
    sub edx, eax
    cmp edx, WM_ICON_W          ; unsigned: left of it wraps and fails
    jae .slot
    mov edx, [wm_iy]
    sub edx, ebx
    cmp edx, WM_ICON_H
    jae .slot
    mov [esp+28], ecx           ; pushad's eax: the window
    mov dword [esp+16], HT_ICON ; pushad's ebx
    popad
    clc
    ret
.slot:
    inc ebp
.next:
    add edi, WIN_SIZE
    inc ecx
    cmp ecx, WM_MAX
    jb .w
    popad
    stc
    ret

align 4
wm_ix dd 0
wm_iy dd 0
wm_lasticon dd -1

; winmin: One and Two on the window manager's screen. One's minimise box
; (clicked through wm_inject) makes it an icon: Two gets the focus and the
; icon is hit-tested and read back on the visible page. Two is minimised
; with wm_setstate; one press on One's icon, or a press on Two's icon in
; between, does not restore it; two presses do, with its rectangle and the
; focus, and Two's icon moves to the first place. A maximised window comes
; back maximised. Prints `winmin: PASS` or `winmin: FAIL`.
WN_IX equ WM_ICON_GAP + WM_ICON_W / 2               ; first icon's centre
WN_IX2 equ WN_IX + WM_ICON_W + WM_ICON_GAP          ; second icon's
WN_IY equ WM_SCR_H - WM_ICON_GAP - WM_ICON_H / 2
cmd_winmin_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 1
    mov eax, 100
    mov ebx, 100
    mov ecx, 200
    mov edx, 150
    mov esi, wc_one
    call wm_create
    mov [wc_a], eax
    mov eax, 200
    mov ebx, 180
    mov esi, wc_two
    call wm_create
    mov [wc_b], eax
    call wm_redraw
    mov eax, 100 + 200 - 7 - 2 * WM_BOX ; One's minimise box
    mov ebx, 105
    call wn_click
    call wm_update
    call wm_focus
    cmp eax, [wc_b]
    jne .fail
    mov eax, WN_IX
    mov ebx, WN_IY
    call wm_hit
    cmp eax, [wc_a]
    jne .fail
    cmp ebx, HT_ICON
    jne .fail
    mov eax, WM_ICON_GAP        ; the icon's bevel, on the visible page
    mov ebx, WM_SCR_H - WM_ICON_GAP - WM_ICON_H
    call vbe_front_getpixel
    cmp cl, TH_LIGHT
    jne .fail
    mov eax, [wc_b]
    mov ebx, WS_MIN
    call wm_setstate
    call wm_focus
    cmp eax, -1                 ; nothing left to focus
    jne .fail
    mov eax, WN_IX              ; One once, Two, One once: not restored
    mov ebx, WN_IY
    call wn_click
    mov eax, WN_IX2
    call wn_click
    mov eax, WN_IX
    call wn_click
    mov eax, [wc_a]
    call wm_record
    cmp dword [edi+WIN_ICONIC], 1
    jne .fail
    mov eax, WN_IX              ; and again: restored
    call wn_click
    call wm_update
    call wm_focus
    cmp eax, [wc_a]
    jne .fail
    cmp dword [edi+WIN_ICONIC], 0
    jne .fail
    cmp dword [edi+WIN_X], 100
    jne .fail
    cmp dword [edi+WIN_W], 200
    jne .fail
    mov eax, WN_IX              ; Two's icon is first now
    call wm_hit
    cmp eax, [wc_b]
    jne .fail
    mov eax, [wc_a]             ; maximised, minimised, restored: maximised
    mov ebx, WS_MAX
    call wm_setstate
    mov ebx, WS_MIN
    call wm_setstate
    mov eax, WN_IX              ; One's icon is first again (table order)
    mov ebx, WN_IY
    call wn_click
    call wn_click
    call wm_update
    mov eax, [wc_a]
    call wm_record
    cmp dword [edi+WIN_ICONIC], 0
    jne .fail
    cmp dword [edi+WIN_STATE], WS_MAX
    jne .fail
    cmp dword [edi+WIN_W], WM_SCR_W
    je .end
.fail:
    mov byte [gfxt_ok], 0
.end:
    mov eax, [wc_a]
    call wm_close
    mov eax, [wc_b]
    call wm_close
    call gfx_text
.out:
    mov esi, wn_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wn_fail
.say:
    jmp puts

; eax, ebx = a point: a left press and release there (wm_inject)
wn_click:
    pushad
    mov cl, 1
    call wm_inject
    mov eax, [esp+28]
    mov ebx, [esp+16]
    xor ecx, ecx
    call wm_inject
    popad
    ret

wn_pass db 'winmin: PASS', 10, 0
wn_fail db 'winmin: FAIL', 10, 0

; ---------- system menu and keyboard move / size (2.2-sysmenu) ----------
; A pop-up menu is a column of items in a raised box drawn above every
; window. One is open at a time: wm_popup opens it, the arrows, Enter and
; Esc (wm_menukey) or a click (wm_mouse) choose or dismiss it. The system
; menu is a pop-up whose choice the window manager carries out itself:
; Restore, Move, Size, Minimise, Maximise, Close. Move and Size then take
; the arrow keys, 8 pixels a press, until Enter or Esc (wm_kmode).

WM_MENU_MAX equ 8
WM_MENU_ROW equ GFX_CELL_H + 2
WM_KSTEP    equ 8
WME_MENU    equ 5               ; a pop-up item chosen: ebx = owner, ecx = item

SM_RESTORE  equ 0
SM_MOVE     equ 1
SM_SIZE     equ 2
SM_MIN      equ 3
SM_MAX      equ 4
SM_CLOSE    equ 5

; eax, ebx = top left, esi = item addresses, edx = how many (at most
; WM_MENU_MAX), ecx = owner window (its id comes back with the choice).
; Replaces any open menu. Marks it for painting; the first item is chosen.
wm_popup:
    pushad
    call wm_menuclose
    mov [wm_mx], eax
    mov [wm_my], ebx
    mov [wm_mitems], esi
    mov [wm_mn], edx
    mov [wm_mown], ecx
    mov dword [wm_msel], 0
    mov dword [wm_msys], 0
    xor ebp, ebp                ; widest item, in pixels
    xor edi, edi
.w:
    push esi
    mov esi, [esi+edi*4]
    mov ecx, FONT_9
    call gfx_strwidth_p
    pop esi
    cmp eax, ebp
    jbe .nx
    mov ebp, eax
.nx:
    inc edi
    cmp edi, edx
    jb .w
    add ebp, 2 * TH_BEVEL_W + 8
    mov [wm_mw], ebp
    imul edx, edx, WM_MENU_ROW
    add edx, 2 * TH_BEVEL_W + 2
    mov [wm_mh], edx
    call wm_menumark
    popad
    ret

wm_menumark:
    pushad
    mov eax, [wm_mx]
    mov ebx, [wm_my]
    mov ecx, [wm_mw]
    mov edx, [wm_mh]
    call wm_mark
    popad
    ret

; Closes the open menu, if any.
wm_menuclose:
    cmp dword [wm_mn], 0
    je .r
    call wm_menumark
    mov dword [wm_mn], 0
.r:
    ret

wm_menudraw:
    cmp dword [wm_mn], 0
    je .r
    pushad
    mov eax, [wm_mx]
    mov ebx, [wm_my]
    mov ecx, [wm_mw]
    mov edx, [wm_mh]
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi
    call gfx_bevel
    add eax, TH_BEVEL_W
    add ebx, TH_BEVEL_W + 1
    sub ecx, 2 * TH_BEVEL_W
    xor ebp, ebp
.row:
    mov dl, TH_FACE
    mov dh, TH_TEXT
    cmp ebp, [wm_msel]
    jne .paint
    mov dl, TH_SELECT
    mov dh, TH_SELECT_TEXT
.paint:
    mov [gfx_colour], dl
    mov [gfx_bg], dl
    push edx
    mov edx, WM_MENU_ROW
    call gfx_fillrect
    pop edx
    mov [gfx_colour], dh
    push eax
    push ebx
    push ecx
    add eax, 4
    inc ebx
    sub ecx, 8
    mov esi, [wm_mitems]
    mov esi, [esi+ebp*4]
    call wm_drawtitle
    pop ecx
    pop ebx
    pop eax
    add ebx, WM_MENU_ROW
    inc ebp
    cmp ebp, [wm_mn]
    jb .row
    popad
.r:
    ret

; A press while a menu is open (wm_px, wm_py): on an item, choose it;
; anywhere else, close the menu. -> eax, ebx, ecx as wm_mouse.
wm_menuclick:
    mov eax, [wm_px]
    sub eax, [wm_mx]
    cmp eax, [wm_mw]
    jae .out
    mov eax, [wm_py]
    sub eax, [wm_my]
    sub eax, TH_BEVEL_W + 1
    js .out
    xor edx, edx
    mov ecx, WM_MENU_ROW
    div ecx
    cmp eax, [wm_mn]
    jae .out
    mov [wm_msel], eax
    jmp wm_menuchoose
.out:
    call wm_menuclose
    xor eax, eax
    ret

; Keys for an open menu or for keyboard move / size. al = key as wg_key
; takes it (WK_UP, WK_DOWN, WK_LEFT, WK_RIGHT, 10 / 13 Enter, 27 Esc).
; -> CF set if neither is active (the key is not taken); otherwise CF clear
; and eax, ebx, ecx as wm_mouse.
wm_menukey:
    cmp byte [wm_kmode], 0
    jne wm_kkey
    cmp dword [wm_mn], 0
    jne .menu
    stc
    ret
.menu:
    call wm_menumark
    cmp al, WK_DOWN
    je .down
    cmp al, WK_UP
    je .up
    cmp al, 27
    je .esc
    cmp al, 10
    je .enter
    cmp al, 13
    je .enter
    jmp .none
.down:
    mov eax, [wm_msel]
    inc eax
    cmp eax, [wm_mn]
    jb .set
    xor eax, eax                ; past the last: the first
    jmp .set
.up:
    mov eax, [wm_msel]
    dec eax
    jns .set
    mov eax, [wm_mn]
    dec eax
.set:
    mov [wm_msel], eax
.none:
    xor eax, eax
    clc
    ret
.esc:
    call wm_menuclose
    jmp .none
.enter:
    call wm_menuchoose
    clc
    ret

; The open menu's item wm_msel is chosen. The system menu acts here;
; another menu reports WME_MENU (ebx = owner, ecx = item).
wm_menuchoose:
    mov ecx, [wm_msel]
    mov ebx, [wm_mown]
    cmp dword [wm_msys], 0
    jne .sys
    call wm_menuclose
    mov eax, WME_MENU
    ret
.sys:
    call wm_menuclose
    push edi
    mov eax, ebx
    mov [wm_mwin], eax
    call wm_record
    jc .no
    cmp ecx, SM_RESTORE
    je .restore
    cmp ecx, SM_MOVE
    je .move
    cmp ecx, SM_SIZE
    je .size
    cmp ecx, SM_MIN
    je .min
    cmp ecx, SM_MAX
    je .max
    pop edi                     ; SM_CLOSE: the owner decides
    mov eax, WME_CLOSE
    ret
.restore:
    cmp dword [edi+WIN_STATE], WS_MAX
    jne .no
    call wm_togglemax
    jmp .no
.max:
    cmp dword [edi+WIN_STATE], WS_MAX
    je .no
    call wm_togglemax
    jmp .no
.min:
    call wm_minimise
    jmp .no
.move:
    mov byte [wm_kmode], 1
    jmp .no
.size:
    mov byte [wm_kmode], 2
.no:
    pop edi
    xor eax, eax
    ret

; Keyboard move (wm_kmode 1) or size (2) of [wm_mwin]: an arrow moves the
; window, or its right / bottom edge, WM_KSTEP pixels; Enter or Esc ends.
wm_kkey:
    pushad
    cmp al, 10
    je .end
    cmp al, 13
    je .end
    cmp al, 27
    je .end
    xor ebp, ebp                ; dx
    xor esi, esi                ; dy
    cmp al, WK_LEFT
    jne .k1
    mov ebp, -WM_KSTEP
.k1:
    cmp al, WK_RIGHT
    jne .k2
    mov ebp, WM_KSTEP
.k2:
    cmp al, WK_UP
    jne .k3
    mov esi, -WM_KSTEP
.k3:
    cmp al, WK_DOWN
    jne .k4
    mov esi, WM_KSTEP
.k4:
    mov eax, [wm_mwin]
    call wm_record
    jc .end
    mov ebx, [edi+WIN_X]
    mov ecx, [edi+WIN_Y]
    mov edx, [edi+WIN_W]
    mov edi, [edi+WIN_H]
    cmp byte [wm_kmode], 1
    jne .sz
    add ebx, ebp
    add ecx, esi
    jmp .place
.sz:
    add edx, ebp
    add edi, esi
.place:
    mov esi, edi
    call wm_place               ; refused (too small, off the screen): stays
    jmp .r
.end:
    mov byte [wm_kmode], 0
.r:
    popad
    xor eax, eax
    clc
    ret

; eax = window id: open its system menu under its system-menu box.
wm_sysmenu:
    pushad
    call wm_record
    jc .r
    mov ecx, eax
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    add ebx, WM_TITLE_H + 1
    mov esi, wm_smitems
    mov edx, 6
    call wm_popup
    mov dword [wm_msys], 1
.r:
    popad
    ret

; ---------- Alt+Tab, Alt+Esc, Alt+Space, Alt+F4 (2.2-alttab) ----------
; al = scancode of a key pressed with Alt down -> CF set if it is not one
; of these; else CF clear and eax, ebx, ecx as wm_mouse. Alt+Tab steps a
; switcher through the windows, most recently used first (the z-order from
; the top), showing the chosen title in a box in the middle of the screen;
; letting go of Alt (wm_altup) raises that window. Alt+Esc sends the top
; window to the bottom. Alt+Space opens the focused window's system menu,
; Alt+F4 reports WME_CLOSE for it.
wm_altkey:
    cmp al, 0x0F
    je .tab
    cmp al, 0x01
    je .esc
    cmp al, 0x39
    je .space
    cmp al, 0x3E
    je .f4
    stc
    ret
.tab:
    mov eax, [wm_zn]
    cmp eax, 2
    jb .none
    inc dword [wm_tabn]
    mov eax, [wm_tabn]
    cmp eax, [wm_zn]
    jb .tabok
    mov dword [wm_tabn], 1      ; wrapped past the bottom: the second again
.tabok:
    call wm_tabmark
    jmp .none
.esc:
    cmp dword [wm_zn], 2
    jb .none
    call wm_focus
    push eax
    call wm_zremove
    mov ecx, [wm_zn]            ; shift up, put it at the bottom
.sh:
    test ecx, ecx
    jz .put
    mov dl, [wm_z+ecx-1]
    mov [wm_z+ecx], dl
    dec ecx
    jmp .sh
.put:
    pop eax
    mov [wm_z], al
    inc dword [wm_zn]
    mov byte [wm_dfull], 1
    jmp .none
.space:
    call wm_focus
    cmp eax, -1
    je .none
    call wm_sysmenu
    jmp .none
.f4:
    call wm_focus
    cmp eax, -1
    je .none
    mov ebx, eax
    mov eax, WME_CLOSE
    clc
    ret
.none:
    xor eax, eax
    clc
    ret

; Alt was let go: if Alt+Tab was stepping, raise the chosen window.
wm_altup:
    cmp dword [wm_tabn], 0
    je .r
    pushad
    call wm_tabmark
    call wm_tabwin
    mov dword [wm_tabn], 0
    call wm_raise
    popad
.r:
    ret

; -> eax = the window Alt+Tab has chosen (wm_tabn down from the top)
wm_tabwin:
    mov eax, [wm_zn]
    dec eax
    sub eax, [wm_tabn]
    movzx eax, byte [wm_z+eax]
    ret

WM_TAB_W equ 200
WM_TAB_H equ 3 * GFX_CELL_H

wm_tabrect:
    mov eax, [gfx_width]
    sub eax, WM_TAB_W
    shr eax, 1
    mov ebx, [gfx_height]
    sub ebx, WM_TAB_H
    shr ebx, 1
    mov ecx, WM_TAB_W
    mov edx, WM_TAB_H
    ret

wm_tabmark:
    pushad
    call wm_tabrect
    call wm_mark
    popad
    ret

wm_tabdraw:
    cmp dword [wm_tabn], 0
    je .r
    pushad
    call wm_tabrect
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi
    call gfx_bevel
    push eax
    push ebx
    call wm_tabwin
    imul edi, eax, WIN_SIZE
    add edi, wm_table
    pop ebx
    pop eax
    add eax, 8
    add ebx, GFX_CELL_H
    sub ecx, 16
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_FACE
    mov esi, [edi+WIN_TITLE]
    call wm_drawtitle
    popad
.r:
    ret

wm_smitems dd wm_sm0, wm_sm1, wm_sm2, wm_sm3, wm_sm4, wm_sm5
wm_sm0 db 'Restore', 0
wm_sm1 db 'Move', 0
wm_sm2 db 'Size', 0
wm_sm3 db 'Minimize', 0
wm_sm4 db 'Maximize', 0
wm_sm5 db 'Close', 0

align 4
wm_mx dd 0
wm_my dd 0
wm_mw dd 0
wm_mh dd 0
wm_mn dd 0                      ; items in the open menu, 0 = none
wm_mitems dd 0
wm_msel dd 0
wm_mown dd 0
wm_msys dd 0                    ; 1: the open menu is a system menu
wm_tabn dd 0                    ; Alt+Tab steps so far, 0 = not switching
wm_kmode db 0                   ; 1 keyboard move, 2 keyboard size

; winmenu: One and Two on the window manager's screen. Alt+Space (through
; wm_altkey) opens Two's system menu; Down three times and Enter choose
; Minimize. A click on One's system-menu box opens its menu and a click on
; Maximize maximises it; Alt+Space, Enter (Restore) restores it. Move and
; Size from the menu then take arrows: right, right, down moves One by
; (16, 8); right, right in Size widens it by 16; Esc on an open menu and a
; click outside one close it without acting; Close reports WME_CLOSE.
; Prints `winmenu: PASS` or `winmenu: FAIL`.
cmd_winmenu_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 1
    mov eax, 100
    mov ebx, 100
    mov ecx, 200
    mov edx, 150
    mov esi, wc_one
    call wm_create
    mov [wc_a], eax
    mov eax, 200
    mov ebx, 180
    mov esi, wc_two
    call wm_create
    mov [wc_b], eax
    call wm_redraw
    mov al, 0x39                ; Alt+Space: Two's menu
    call wm_altkey
    cmp dword [wm_mn], 6
    jne .fail
    mov esi, wmn_keys1          ; Down x3, Enter: Minimize
    call wmn_keys
    call wm_update
    mov eax, [wc_b]
    call wm_record
    cmp dword [edi+WIN_ICONIC], 1
    jne .fail
    mov eax, 105                ; One's system-menu box
    mov ebx, 105
    call wn_click
    cmp dword [wm_mn], 6
    jne .fail
    mov eax, 110                ; Maximize: row 4 of the menu below the box
    mov ebx, 100 + WM_TITLE_H + 1 + TH_BEVEL_W + 1 + 4 * WM_MENU_ROW + 3
    call wn_click
    call wm_update
    mov eax, [wc_a]
    call wm_record
    cmp dword [edi+WIN_STATE], WS_MAX
    jne .fail
    mov al, 0x39                ; Alt+Space, Enter: Restore
    call wm_altkey
    mov al, 10
    call wm_menukey
    cmp dword [edi+WIN_STATE], WS_NORMAL
    jne .fail
    mov esi, wmn_keys2          ; Move: right, right, down, Enter
    call wmn_keys
    cmp dword [edi+WIN_X], 116
    jne .fail
    cmp dword [edi+WIN_Y], 108
    jne .fail
    mov esi, wmn_keys3          ; Size: right, right, Enter
    call wmn_keys
    cmp dword [edi+WIN_W], 216
    jne .fail
    cmp byte [wm_kmode], 0
    jne .fail
    mov al, 0x39                ; Esc closes the menu
    call wm_altkey
    mov al, 27
    call wm_menukey
    cmp dword [wm_mn], 0
    jne .fail
    mov al, 0x39                ; a click outside closes it
    call wm_altkey
    mov eax, 600
    mov ebx, 20
    call wn_click
    cmp dword [wm_mn], 0
    jne .fail
    cmp dword [edi+WIN_W], 216  ; and nothing else changed
    jne .fail
    mov al, 0x39                ; Close: reported, not done
    call wm_altkey
    mov al, WK_UP               ; up from the first: the last (Close)
    call wm_menukey
    mov al, 10
    call wm_menukey
    cmp eax, WME_CLOSE
    jne .fail
    cmp ebx, [wc_a]
    jne .fail
    call wm_update
    jmp .end
.fail:
    mov byte [gfxt_ok], 0
.end:
    call wm_menuclose
    mov eax, [wc_a]
    call wm_close
    mov eax, [wc_b]
    call wm_close
    call gfx_text
.out:
    mov esi, wmn_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wmn_fail
.say:
    jmp puts

; esi = keys for wm_menukey, 0 ends; 0xFF = Alt+Space first
wmn_keys:
    pushad
.k:
    lodsb
    test al, al
    jz .r
    cmp al, 0xFF
    jne .key
    mov al, 0x39
    call wm_altkey
    jmp .k
.key:
    call wm_menukey
    jmp .k
.r:
    popad
    ret

wmn_keys1 db WK_DOWN, WK_DOWN, WK_DOWN, 10, 0
wmn_keys2 db 0xFF, WK_DOWN, 10, WK_RIGHT, WK_RIGHT, WK_DOWN, 10, 0
wmn_keys3 db 0xFF, WK_DOWN, WK_DOWN, 10, WK_RIGHT, WK_RIGHT, 13, 0
wmn_pass db 'winmenu: PASS', 10, 0
wmn_fail db 'winmenu: FAIL', 10, 0

; winalttab: One, Two, Three (Three on top). Alt+Tab once and Alt let go:
; Two comes up. Alt+Tab twice: the third from the top (One) comes up, and
; the box shows while Alt is down. Alt+Esc sends the top to the bottom.
; Prints the z-order from the top and `alttab: PASS` or `alttab: FAIL`.
cmd_winalttab_run:
    call wm_screen
    jc .out
    mov byte [gfxt_ok], 1
    mov ebp, 0
.mk:
    imul eax, ebp, 40
    add eax, 60
    mov ebx, eax
    mov ecx, 200
    mov edx, 120
    mov esi, [wat_names+ebp*4]
    call wm_create
    mov [wat_ids+ebp*4], eax
    inc ebp
    cmp ebp, 3
    jb .mk
    call wm_redraw
    mov al, 0x0F                ; Alt+Tab, let go
    call wm_altkey
    call wm_altup
    call wm_focus
    cmp eax, [wat_ids+4]        ; Two
    jne .fail
    mov al, 0x0F                ; Alt+Tab, Tab
    call wm_altkey
    mov al, 0x0F
    call wm_altkey
    call wm_update
    call wm_tabrect             ; the box is up, on the visible page
    call vbe_front_getpixel
    cmp cl, TH_LIGHT
    jne .fail
    call wm_altup
    call wm_update
    call wm_focus
    cmp eax, [wat_ids]          ; One
    jne .fail
    mov al, 0x01                ; Alt+Esc: One to the bottom
    call wm_altkey
    call wm_focus
    cmp eax, [wat_ids+4]        ; Two is on top again
    jne .fail
    movzx eax, byte [wm_z]
    cmp eax, [wat_ids]
    je .end
.fail:
    mov byte [gfxt_ok], 0
.end:
    xor ebp, ebp                ; the order: pushed bottom first, so it
.pr:                            ; prints from the top
    cmp ebp, [wm_zn]
    jae .closeall
    movzx eax, byte [wm_z+ebp]
    imul edi, eax, WIN_SIZE
    mov esi, [wm_table+edi+WIN_TITLE]
    push esi
    inc ebp
    jmp .pr
.closeall:
    mov ebp, 2
.cl:
    mov eax, [wat_ids+ebp*4]
    call wm_close
    dec ebp
    jns .cl
    call gfx_text
    mov ecx, 3
.say3:
    pop esi
    call puts
    mov al, ' '
    call putc
    loop .say3
    mov al, 10
    call putc
.out:
    mov esi, wat_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, wat_fail
.say:
    jmp puts

wat_names dd wc_one, wc_two, wat_three
align 4
wat_ids dd 0, 0, 0
wat_three db 'Three', 0
wat_pass db 'alttab: PASS', 10, 0
wat_fail db 'alttab: FAIL', 10, 0

; Marks the focused (top) window's title bar: the focus is about to move,
; so its colour changes (2.2-progwin).
wm_marktop:
    pushad
    call wm_focus
    cmp eax, -1
    je .r
    call wm_record
    jc .r
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    mov ecx, [edi+WIN_W]
    mov edx, WM_TITLE_H + 1
    call wm_mark
.r:
    popad
    ret
