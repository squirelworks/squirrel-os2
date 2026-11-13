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
WIN_SIZE        equ 60
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
    call wm_markwin             ; its place needs painting (2.2-clip-z)
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
    mov byte [gfx_colour], WM_DESKTOP
    call gfx_fillrect
    xor ebp, ebp
.w:
    cmp ebp, [wm_zn]
    jae .done
    movzx eax, byte [wm_z+ebp]
    imul edi, eax, WIN_SIZE
    add edi, wm_table
    inc ebp
    mov byte [wm_drawbar], WM_BAR_IDLE
    cmp ebp, [wm_zn]
    jne .draw
    mov byte [wm_drawbar], WM_BAR   ; the top window has the focus
.draw:
    call wm_draw
    jmp .w
.done:
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
    mov dl, [wm_drawbar]
    mov [gfx_colour], dl
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
    mov byte [gfx_colour], WM_BAR_TEXT
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
    mov byte [gfx_colour], WM_CLIENT
    call gfx_fillrect
    call wg_drawall             ; the window's widgets (widget.asm)
    add eax, 2                  ; the typed text, 2 pixels in
    add ebx, 2
    sub ecx, 4
    mov byte [gfx_colour], WM_TEXT
    mov byte [gfx_bg], WM_CLIENT
    lea esi, [edi+WIN_BUF]
    call wm_drawtitle
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
