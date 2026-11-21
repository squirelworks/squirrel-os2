; Squirrel-OS/2 — Program Manager (2.3-groups / 2.6-context / W.5-openas).
; Original code.
;
; progman: the desktop as group windows full of icons. Main holds the
; top-level programs; each top-level Folder is a group of its own holding
; the objects whose `in` is that folder. The objects are the desktop's
; (dk_mkobjs, 1.7.6 / 1.9.0): Program and Folder stay underneath.
;
; Keys: the arrows choose an icon, Enter opens it (sends `open`), m moves
; the chosen icon with the arrows until Enter or Esc, a arranges the focused
; group's icons in rows, Esc quits. Mouse: a press on an icon chooses it, a
; second press on it soon after opens it, dragging moves it; the right
; button opens a context menu (Open, Open as..., Settings, Arrange) on the
; icon under the pointer (2.6-context / W.5-openas, wg_menu / wm_popup)
; without arming the double-click timer. Open as cascades to Icon / Tree /
; Details / Settings. Delete is left out until a confirm path exists.
; Settings notebook tab/close events are handled in pm_wm. A group's close
; box minimises it (double-click its icon to restore); Main's close quits.
; Icon places are kept in /desktop/progman.pos, one line per moved or
; arranged icon: "name x y". See documentation/apps/progman.md.
;
; Self-check: dkctx -> dk-ctx: PASS; openas (filemgr) -> openas: PASS.

PM_GMAX     equ 8               ; groups: Main + up to seven folders (#236)
PM_IMAX     equ 8               ; icons in a group
PM_CW       equ 64              ; an icon's cell: the icon and its caption
PM_CH       equ 48
PM_CAP_Y    equ 34              ; the caption, below the 32 x 32 icon
PM_STEP     equ 8               ; keyboard move, pixels a press
PM_DRAG     equ 4               ; a press that moves less than this is a click
PM_DBL      equ 50              ; ticks between the presses of a double-click

PM_CTX_OPEN     equ 0
PM_CTX_OPENAS   equ 1           ; W.5: cascades to Icon/Tree/Details/Settings
PM_CTX_SETTINGS equ 2
PM_CTX_ARRANGE  equ 3           ; Delete left out until a confirm UI exists
PM_CTX_N        equ 4

PM_OA_ICON      equ 0
PM_OA_TREE      equ 1
PM_OA_DETAILS   equ 2
PM_OA_SETTINGS  equ 3
PM_OA_N         equ 4

cmd_progman_run:
    call wm_screen              ; 640 x 480 x 8 VBE, or mode 13h
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    mov eax, [gfx_width]        ; programs opened from here use the
    sub eax, GFX_W              ; desktop's centred 320 x 200 layout
    shr eax, 1
    mov [dk_ox], eax
    mov eax, [gfx_height]
    sub eax, GFX_H
    shr eax, 1
    mov [dk_oy], eax
    call dk_mkobjs
    call stu_run                ; W.6: open Startup contents
    call pm_build
    call pm_load
    mov byte [dk_quit], 0
    mov byte [pm_kmove], 0
    mov dword [pm_drag], -1
    mov eax, [mouse_clicks]
    mov [pm_mclicks], eax
.draw:
    call wm_redraw
    call ptr_show
.key:
    call mouse_poll
    call pm_wm                  ; CF: quit
    jc .quit
    call ptr_show
    cmp byte [pm_open], 0
    je .nokey
    mov byte [pm_open], 0
    call pm_launch
    jmp .draw
.nokey:
    cmp byte [pm_dirty], 0
    je .menu
    mov byte [pm_dirty], 0
    jmp .draw
.menu:                          ; context menu / Open as (2.6 / W.5)
    mov eax, [dk_menu]
    test eax, eax
    jz .k
    mov dword [dk_menu], 0
    dec eax                     ; item index
    cmp byte [pm_oa_pend], 0
    je .top
    mov byte [pm_oa_pend], 0
    call pm_openas_do
    jmp .draw
.top:
    call pm_ctx_do
    jmp .draw
.k:
    call dk_trykey              ; CF clear, al = key
    jc .key
    cmp byte [dk_quit], 0       ; Alt+F4 or Close on Main
    jne .quit
    call pm_focus
    jnc .focused
    cmp al, 27                  ; no group on top: only Esc
    je .quit
    jmp .key
.focused:
    cmp byte [pm_kmove], 0
    jne .moving
    cmp al, 27
    je .quit
    cmp al, 10
    je .open
    cmp al, 'm'
    je .startmove
    cmp al, 'a'
    je .arrange
    call pm_choose              ; the arrows
    jmp .draw
.open:
    call pm_launch
    jmp .draw
.startmove:
    cmp dword [pm_gn+ebp*4], 0
    je .key
    mov byte [pm_kmove], 1
    jmp .key
.moving:
    cmp al, 10
    je .endmove
    cmp al, 27
    je .endmove
    call pm_kstep
    jmp .draw
.endmove:
    mov byte [pm_kmove], 0
    call pm_save
    jmp .key
.arrange:
    call pm_arrange
    call pm_save
    jmp .draw
.quit:
    xor ebp, ebp
.close:
    mov eax, [pm_gwin+ebp*4]
    cmp eax, -1
    je .cn
    call wm_close
.cn:
    inc ebp
    cmp ebp, PM_GMAX
    jb .close
    call dk_freeobjs
    call gfx_text
    mov esi, pm_bye
    jmp puts

; ---------- groups ----------

; The groups from dk_objs: Main, then a group per top-level folder; every
; other object goes in its folder's group, or Main. Opens their windows
; and lays the icons out in rows.
pm_build:
    pushad
    xor eax, eax
    mov [pm_ng], eax
    mov edi, pm_gn
    mov ecx, PM_GMAX
    rep stosd
    mov edi, pm_gwin
    mov ecx, PM_GMAX
    dec eax
    rep stosd                   ; -1: no window
    mov edi, pm_gsel
    xor eax, eax
    mov ecx, PM_GMAX
    rep stosd
    mov dword [pm_last], -1
    mov dword [pm_drag], -1
    mov dword [pm_gname], pm_t_main ; Main: the top level
    mov dword [pm_gfold], dk_empty
    inc dword [pm_ng]
    xor ebx, ebx                ; the folders first
.f:
    cmp ebx, [dk_n]
    jae .items
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .fn
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    jne .fn
    call pm_in
    cmp byte [esi], 0
    jne .fn                     ; folders do not nest (1.9.1)
    mov edx, [pm_ng]
    cmp edx, PM_GMAX
    jae .fn
    push ebx
    xor ebx, ebx
    call obj_get                ; its name
    pop ebx
    mov [pm_gname+edx*4], eax
    mov [pm_gfold+edx*4], eax
    inc dword [pm_ng]
.fn:
    inc ebx
    jmp .f
.items:
    xor ebx, ebx
.i:
    cmp ebx, [dk_n]
    jae .wins
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .in
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    je .in
    call pm_in                  ; esi = the folder holding it
    xor edx, edx                ; the group with that folder, or Main
.g:
    mov edi, [pm_gfold+edx*4]
    call streq
    je .add
    inc edx
    cmp edx, [pm_ng]
    jb .g
    xor edx, edx
.add:
    mov ecx, [pm_gn+edx*4]
    cmp ecx, PM_IMAX
    jae .in
    imul edi, edx, PM_IMAX
    add edi, ecx
    mov [pm_gobj+edi*4], ebx
    inc dword [pm_gn+edx*4]
.in:
    inc ebx
    jmp .i
.wins:
    xor ebp, ebp
.w:
    cmp ebp, [pm_ng]
    jae .done
    call pm_place               ; eax..edx = where its window goes
    mov esi, [pm_gname+ebp*4]
    call wm_create
    mov [pm_gwin+ebp*4], eax
    cmp eax, -1
    je .wn
    imul edi, eax, WIN_SIZE
    mov dword [wm_table+edi+WIN_PAINT], pm_paint
.wn:
    call pm_layout
    inc ebp
    jmp .w
.done:
    mov eax, [pm_gwin]          ; Main is on top, with the focus
    cmp eax, -1
    je .r
    mov [dk_win], eax           ; Alt+F4 / Close on it quit (dk_wmreply)
    call wm_raise
.r:
    popad
    ret

; eax = object -> esi = its `in` ("" at the top level)
pm_in:
    push eax
    push ebx
    mov ebx, 1
    call obj_get
    mov esi, eax
    test esi, esi
    jnz .r
    mov esi, dk_empty
.r:
    pop ebx
    pop eax
    ret

; ebp = group -> eax, ebx, ecx, edx = its window's place: two columns on
; a 640-wide screen, a cascade on a small one
pm_place:
    cmp dword [gfx_width], 640
    jb .small
    mov eax, ebp
    and eax, 1
    imul eax, eax, 312
    add eax, 16
    mov ebx, ebp
    shr ebx, 1
    imul ebx, ebx, 200
    add ebx, 16
    add ebx, [wc_top]          ; shared top chrome (WarpCenter and/or LaunchPad)
    add ebx, [lp_top]
    mov ecx, 296
    mov edx, 180
    ret
.small:
    imul eax, ebp, 16
    add eax, 4
    imul ebx, ebp, 12
    add ebx, 4
    add ebx, [wc_top]          ; shared top chrome (WarpCenter and/or LaunchPad)
    add ebx, [lp_top]
    mov ecx, 220
    mov edx, 120
    ret

; ebp = group: its icons in rows, as many to a row as its client fits
pm_layout:
    pushad
    call pm_cols                ; ecx = icons to a row
    xor esi, esi
.i:
    cmp esi, [pm_gn+ebp*4]
    jae .r
    mov eax, esi
    xor edx, edx
    div ecx                     ; eax = row, edx = column
    imul edx, edx, PM_CW
    add edx, PM_STEP
    imul eax, eax, PM_CH
    add eax, 4
    imul edi, ebp, PM_IMAX
    add edi, esi
    mov [pm_gx+edi*4], edx
    mov [pm_gy+edi*4], eax
    inc esi
    jmp .i
.r:
    popad
    ret

; ebp = group -> ecx = icons to a row (at least one)
pm_cols:
    push eax
    push ebx
    push edx
    call pm_place
    mov eax, ecx
    sub eax, 2 + PM_STEP
    xor edx, edx
    mov ecx, PM_CW
    div ecx
    mov ecx, eax
    test ecx, ecx
    jnz .r
    inc ecx
.r:
    pop edx
    pop ebx
    pop eax
    ret

pm_arrange:
    call pm_layout
    mov byte [pm_dirty], 1
    ret

; -> ebp = the focused group (its window on top), CF set if none
pm_focus:
    push eax
    mov eax, [wm_zn]
    test eax, eax
    jz .no
    movzx eax, byte [wm_z+eax-1]
    call pm_group
    jc .no
    pop eax
    ret
.no:
    pop eax
    stc
    ret

; eax = window id -> ebp = its group, CF set if none
pm_group:
    xor ebp, ebp
.g:
    cmp ebp, [pm_ng]
    jae .no
    cmp [pm_gwin+ebp*4], eax
    je .yes
    inc ebp
    jmp .g
.yes:
    clc
    ret
.no:
    stc
    ret

; ebp = group, al = key: the arrows choose an icon
pm_choose:
    pushad
    mov edx, [pm_gn+ebp*4]
    test edx, edx
    jz .r
    mov ebx, [pm_gsel+ebp*4]
    call pm_cols
    cmp al, WK_LEFT
    je .left
    cmp al, WK_RIGHT
    je .right
    cmp al, WK_UP
    je .up
    cmp al, WK_DOWN
    jne .r
    add ebx, ecx                ; down a row
    jmp .set
.up:
    sub ebx, ecx
    jmp .set
.left:
    dec ebx
    jmp .set
.right:
    inc ebx
.set:
    test ebx, ebx
    js .r
    cmp ebx, edx
    jae .r
    mov [pm_gsel+ebp*4], ebx
.r:
    popad
    ret

; ebp = group, al = key: an arrow moves the chosen icon PM_STEP pixels
pm_kstep:
    pushad
    cmp dword [pm_gn+ebp*4], 0
    je .r
    imul edi, ebp, PM_IMAX
    add edi, [pm_gsel+ebp*4]
    xor ecx, ecx                ; dx
    xor edx, edx                ; dy
    cmp al, WK_LEFT
    jne .a1
    mov ecx, -PM_STEP
.a1:
    cmp al, WK_RIGHT
    jne .a2
    mov ecx, PM_STEP
.a2:
    cmp al, WK_UP
    jne .a3
    mov edx, -PM_STEP
.a3:
    cmp al, WK_DOWN
    jne .a4
    mov edx, PM_STEP
.a4:
    call pm_moveby
.r:
    popad
    ret

; edi = icon slot (group * PM_IMAX + icon), ecx, edx = by how much:
; moves it, kept inside its client area's top left corner
pm_moveby:
    push eax
    mov eax, [pm_gx+edi*4]
    add eax, ecx
    jns .x
    xor eax, eax
.x:
    cmp eax, 600
    jle .x2
    mov eax, 600
.x2:
    mov [pm_gx+edi*4], eax
    mov eax, [pm_gy+edi*4]
    add eax, edx
    jns .y
    xor eax, eax
.y:
    cmp eax, 440
    jle .y2
    mov eax, 440
.y2:
    mov [pm_gy+edi*4], eax
    mov byte [pm_dirty], 1
    pop eax
    ret

; ebp = group: sends its chosen icon's object `open`
pm_launch:
    call pm_focus
    jc .r
    cmp dword [pm_gn+ebp*4], 0
    je .r
    pushad
    imul edi, ebp, PM_IMAX
    add edi, [pm_gsel+ebp*4]
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    mov esi, dk_s_open
    call obj_send
    popad
.r:
    ret

; ---------- painting ----------

; wm_draw's WIN_PAINT for a group: edi = window record, eax..edx = its
; client area. Draws the icons and captions, cut to the client area; the
; chosen icon's caption is highlighted.
pm_paint:
    pushad
    mov [pm_cx], eax
    mov [pm_cy], ebx
    call pm_clipin
    mov eax, edi
    sub eax, wm_table
    xor edx, edx
    mov ecx, WIN_SIZE
    div ecx
    call pm_group
    jc .out
    xor esi, esi
.i:
    cmp esi, [pm_gn+ebp*4]
    jae .out
    imul edi, ebp, PM_IMAX
    add edi, esi
    mov eax, [pm_gx+edi*4]
    add eax, [pm_cx]
    mov ebx, [pm_gy+edi*4]
    add ebx, [pm_cy]
    push esi
    push eax
    push ebx
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    call pm_icon                ; esi = its icon
    pop ebx
    pop eax
    push eax
    add eax, (PM_CW - 32) / 2
    call gfx_drawicon
    pop eax
    pop esi
    push esi
    mov edx, [pm_gobj+edi*4]
    mov edx, [dk_objs+edx*4]
    xchg eax, edx
    push ebx
    xor ebx, ebx
    call obj_get                ; the caption: its name
    pop ebx
    xchg eax, edx
    mov esi, edx
    add ebx, PM_CAP_Y
    mov cl, TH_TEXT
    mov ch, TH_CLIENT
    mov edx, [esp]              ; the icon's number
    cmp edx, [pm_gsel+ebp*4]
    jne .cap
    mov cl, TH_SELECT_TEXT
    mov ch, TH_SELECT
.cap:
    call pm_caption
    pop esi
    inc esi
    jmp .i
.out:
    call pm_clipout
    popad
    ret

; eax, ebx = the cell's top left at the caption row, esi = text, cl =
; ink, ch = background: the caption centred in the cell, on a band of the
; background just its width
pm_caption:
    pushad
    mov [pm_ink], cl
    mov [pm_bg], ch
    mov edi, eax
    mov ecx, FONT_9
    call gfx_strwidth_p         ; eax = width, the spacing column included
    cmp eax, PM_CW - 2
    jbe .fits
    mov eax, PM_CW - 2
.fits:
    mov ecx, eax                ; the room
    mov edx, PM_CW
    sub edx, eax
    shr edx, 1
    add edi, edx                ; its left edge
    push ecx
    lea eax, [edi-1]            ; the band: a pixel more on the left and
    dec ebx                     ; above, the spacing column on the right
    inc ecx
    mov edx, 11
    mov dl, [pm_bg]
    mov [gfx_colour], dl
    mov edx, 11
    call gfx_fillrect
    pop ecx
    inc ebx
    mov dl, [pm_ink]
    mov [gfx_colour], dl
    mov dl, [pm_bg]
    mov [gfx_bg], dl
    mov eax, edi
    call wm_drawtitle           ; FONT_9, as much as fits
    popad
    ret

; eax = object -> esi = its icon: a Folder's, a File's, the program's own
; (named as its entry), a Template's (by of), or the generic program icon
pm_icon:
    push eax
    push ebx
    mov esi, icon_folder
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    je .r
    mov esi, icon_file
    cmp dword [eax+OBJ_CLASS], dk_c_file
    je .r
    cmp dword [eax+OBJ_CLASS], wps_c_tmpl
    je .tmpl
    mov esi, icon_files
    cmp dword [eax+OBJ_CLASS], fo_c_drive
    je .r
    mov esi, icon_shell
    cmp dword [eax+OBJ_CLASS], fo_c_shred
    je .r
    mov esi, icon_program
    cmp dword [eax+OBJ_CLASS], ss_c_setup
    je .r
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .r
    mov ebx, 2
    call obj_get                ; entry
    test eax, eax
    jz .r
    mov esi, eax
    call icon_byname
    jnc .r
    mov esi, icon_program
.r:
    pop ebx
    pop eax
    ret
.tmpl:
    mov ebx, 2
    call obj_get                ; of
    mov esi, icon_folder
    test eax, eax
    jz .r
    push edi
    mov esi, eax
    mov edi, wps_nm_folder
    call streq
    pop edi
    mov esi, icon_folder
    je .r
    mov esi, icon_program
    jmp .r

; eax, ebx, ecx, edx = a rectangle: the clip becomes its overlap with the
; clip already set (saved for pm_clipout)
pm_clipin:
    pushad
    mov esi, [gfx_clip_x]
    mov [pm_sv], esi
    mov esi, [gfx_clip_y]
    mov [pm_sv+4], esi
    mov esi, [gfx_clip_w]
    mov [pm_sv+8], esi
    mov esi, [gfx_clip_h]
    mov [pm_sv+12], esi
    lea ecx, [eax+ecx]          ; right
    lea edx, [ebx+edx]          ; bottom
    mov esi, [gfx_clip_x]       ; left = max
    cmp esi, eax
    jle .l
    mov eax, esi
.l:
    mov esi, [gfx_clip_y]
    cmp esi, ebx
    jle .t
    mov ebx, esi
.t:
    cmp dword [gfx_clip_w], -1  ; right = min
    je .rr
    mov esi, [gfx_clip_x]
    add esi, [gfx_clip_w]
    cmp esi, ecx
    jge .rr
    mov ecx, esi
.rr:
    cmp dword [gfx_clip_h], -1
    je .bb
    mov esi, [gfx_clip_y]
    add esi, [gfx_clip_h]
    cmp esi, edx
    jge .bb
    mov edx, esi
.bb:
    sub ecx, eax
    jg .w
    xor ecx, ecx
.w:
    sub edx, ebx
    jg .h
    xor edx, edx
.h:
    mov [gfx_clip_x], eax
    mov [gfx_clip_y], ebx
    mov [gfx_clip_w], ecx
    mov [gfx_clip_h], edx
    popad
    ret

pm_clipout:
    push eax
    mov eax, [pm_sv]
    mov [gfx_clip_x], eax
    mov eax, [pm_sv+4]
    mov [gfx_clip_y], eax
    mov eax, [pm_sv+8]
    mov [gfx_clip_w], eax
    mov eax, [pm_sv+12]
    mov [gfx_clip_h], eax
    pop eax
    ret

; ---------- mouse ----------

; The mouse to the window manager, and presses in a group's client area
; to pm_press; a release ends a drag. CF set: quit (Main's close box).
pm_wm:
    cmp byte [dk_quit], 0
    je .live
    stc
    ret
.live:
    pushad
    pushfd
    cli
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    mov cl, [mouse_btns]
    popfd
    cmp eax, [dk_lmx]
    jne .go
    cmp ebx, [dk_lmy]
    jne .go
    cmp cl, [dk_lmb]
    je .no
.go:
    mov [dk_lmx], eax
    mov [dk_lmy], ebx
    mov [dk_lmb], cl
    test cl, 2                  ; right button: context menu (2.6-context)
    jz .noright
    test byte [pm_rbtn], 2
    jnz .noright
    mov [pm_rbtn], cl
    call pm_ctx_at
    jmp .upd
.noright:
    mov [pm_rbtn], cl
    test cl, 1
    jnz .down
    cmp dword [pm_drag], -1     ; let go: the end of a drag
    je .wm
    push eax
    push ebx
    sub eax, [pm_dx0]
    sub ebx, [pm_dy0]
    mov ecx, eax
    mov edx, ebx
    call pm_release
    pop ebx
    pop eax
    mov cl, 0
.wm:
.down:
    call wm_mouse
    cmp eax, WME_MENU           ; a context item clicked
    jne .notmenu
    inc ecx
    mov [dk_menu], ecx
    jmp .upd
.notmenu:
    cmp eax, WME_CLOSE
    jne .client
    cmp ebx, [pm_set_win]       ; Settings notebook close (Sarah #186)
    jne .notset
    mov eax, ebx
    call wm_close
    mov dword [pm_set_win], -1
    mov dword [pm_set_nb], -1
    jmp .upd
.notset:
    cmp ebx, [pm_gwin]
    je .quit
    mov eax, ebx                ; another group: minimised
    call wm_minimise
    jmp .upd
.client:
    cmp eax, WME_CLIENT
    jne .upd
    cmp ebx, [pm_set_win]       ; Settings: tab clicks
    jne .grp
    cmp dword [pm_set_nb], -1
    je .upd
    push eax
    push ebx
    push ecx
    call wm_record              ; edi = Settings window
    jc .setbad
    mov eax, [pm_set_nb]
    mov ebx, [dk_lmx]
    sub ebx, [edi+WIN_X]
    dec ebx
    mov ecx, [dk_lmy]
    sub ecx, [edi+WIN_Y]
    sub ecx, WM_TITLE_H + 1
    call wg_nbclick
    jnc .setdirty
.setbad:
    pop ecx
    pop ebx
    pop eax
    jmp .upd
.setdirty:
    mov byte [pm_dirty], 1
    pop ecx
    pop ebx
    pop eax
    jmp .upd
.grp:
    mov eax, ebx
    call pm_group
    jc .upd
    movzx eax, cx               ; client x, y
    shr ecx, 16
    mov ebx, ecx
    mov ecx, [ticks]
    call pm_press
    jnc .armed
    mov byte [pm_open], 1       ; a double-click: the loop opens it
    jmp .upd
.armed:
    mov eax, [dk_lmx]
    mov [pm_dx0], eax
    mov eax, [dk_lmy]
    mov [pm_dy0], eax
.upd:
    cmp dword [wm_dn], 0
    jne .paint
    cmp byte [wm_dfull], 0
    je .no
.paint:
    call wm_update
.no:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; ebp = group, eax, ebx = a press in its client area, ecx = the time
; (ticks). On an icon: chooses it and starts a drag (pm_drag), CF clear;
; a press on the chosen icon within PM_DBL ticks of the last one there is
; a double-click: CF set (open it). Elsewhere: CF clear, nothing.
pm_press:
    pushad
    xor esi, esi
.i:
    cmp esi, [pm_gn+ebp*4]
    jae .none
    imul edi, ebp, PM_IMAX
    add edi, esi
    mov edx, eax
    sub edx, [pm_gx+edi*4]
    cmp edx, PM_CW
    jae .n
    mov edx, ebx
    sub edx, [pm_gy+edi*4]
    cmp edx, PM_CH
    jb .hit
.n:
    inc esi
    jmp .i
.hit:
    cmp esi, [pm_gsel+ebp*4]
    jne .new
    cmp edi, [pm_last]
    jne .new
    mov edx, ecx
    sub edx, [pm_lastt]
    cmp edx, [cp_dbl]           ; the Control Panel's time (2.3-control)
    ja .new
    mov dword [pm_last], -1     ; double-click: no drag
    mov dword [pm_drag], -1
    popad
    stc
    ret
.new:
    mov [pm_gsel+ebp*4], esi
    mov [pm_last], edi
    mov [pm_lastt], ecx
    mov [pm_drag], edi
    mov byte [pm_dirty], 1
.none:
    popad
    clc
    ret

; ecx, edx = how far the pointer went since the press: a drag of at
; least PM_DRAG pixels moves the icon (and saves the places); less is
; a click and changes nothing. A Template (W.2) creates a new object in
; the group under the pointer instead of moving.
pm_release:
    pushad
    mov edi, [pm_drag]
    cmp edi, -1
    je .r
    mov dword [pm_drag], -1
    mov eax, ecx
    cdq
    xor eax, edx
    sub eax, edx                ; |dx|
    mov ebx, eax
    mov eax, [esp+20]           ; edx as it came in: dy
    cdq
    xor eax, edx
    sub eax, edx
    add eax, ebx
    cmp eax, PM_DRAG
    jb .r
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    cmp dword [eax+OBJ_CLASS], wps_c_tmpl
    je .tmpl
    mov edx, [esp+20]
    call pm_moveby
    mov dword [pm_last], -1     ; a drag is not half of a double-click
    call pm_save
.r:
    popad
    ret
.tmpl:
    mov dword [pm_last], -1
    mov [wps_src], eax
    mov eax, [dk_lmx]
    mov ebx, [dk_lmy]
    call pm_group_at            ; ebp = group under the pointer
    jnc .tdrop
    call pm_focus
    jnc .tdrop
    xor ebp, ebp                ; Main
.tdrop:
    mov esi, [pm_gfold+ebp*4]
    mov eax, [wps_src]
    call wps_create_from
    jc .r
    call pm_rebuild             ; new Folder needs a group; else refresh
    mov byte [pm_dirty], 1
    jmp .r

; Close group windows and rebuild from dk_objs (after a template create).
pm_rebuild:
    pushad
    xor ebp, ebp
.c:
    mov eax, [pm_gwin+ebp*4]
    cmp eax, -1
    je .n
    call wm_close
.n:
    inc ebp
    cmp ebp, PM_GMAX
    jb .c
    call pm_build
    call pm_load
    popad
    ret

; eax, ebx = screen point -> ebp = group whose window contains it, CF clear;
; CF set if none.
pm_group_at:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [pm_atx], eax
    mov [pm_aty], ebx
    xor ebp, ebp
.g:
    cmp ebp, [pm_ng]
    jae .no
    mov eax, [pm_gwin+ebp*4]
    cmp eax, -1
    je .n
    call wm_record             ; edi = window record
    jc .n
    mov eax, [pm_atx]
    mov ebx, [pm_aty]
    cmp eax, [edi+WIN_X]
    jl .n
    mov ecx, [edi+WIN_X]
    add ecx, [edi+WIN_W]
    cmp eax, ecx
    jge .n
    cmp ebx, [edi+WIN_Y]
    jl .n
    mov edx, [edi+WIN_Y]
    add edx, [edi+WIN_H]
    cmp ebx, edx
    jge .n
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.n:
    inc ebp
    jmp .g
.no:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

; ---------- places file ----------

; Writes "name x y" for every icon to /desktop/progman.pos.
pm_save:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov edi, pm_fbuf
    xor ebp, ebp
.g:
    cmp ebp, [pm_ng]
    jae .write
    xor esi, esi
.i:
    cmp esi, [pm_gn+ebp*4]
    jae .gn
    imul ebx, ebp, PM_IMAX
    add ebx, esi
    mov eax, [pm_gobj+ebx*4]
    mov eax, [dk_objs+eax*4]
    push ebx
    xor ebx, ebx
    call obj_get                ; the name
    pop ebx
    call pm_puts
    mov al, ' '
    stosb
    mov eax, [pm_gx+ebx*4]
    call pm_putn
    mov al, ' '
    stosb
    mov eax, [pm_gy+ebx*4]
    call pm_putn
    mov al, 10
    stosb
    inc esi
    jmp .i
.gn:
    inc ebp
    jmp .g
.write:
    sub edi, pm_fbuf
    mov [pm_flen], edi
    mov esi, pm_path
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov esi, pm_fbuf
    mov ecx, [pm_flen]
    call fs_write
    call fs_close
.r:
    popad
    ret

; eax = string, edi = where (at most 15 characters copied)
pm_puts:
    push esi
    push ecx
    mov esi, eax
    mov ecx, 15
.c:
    lodsb
    test al, al
    jz .r
    stosb
    loop .c
.r:
    pop ecx
    pop esi
    ret

; eax = a number (0..9999), edi = where
pm_putn:
    push esi
    push edi
    call itoa                   ; -> num_buf
    pop edi
    mov esi, num_buf
.c:
    lodsb
    test al, al
    jz .r
    stosb
    jmp .c
.r:
    pop esi
    ret

; Reads /desktop/progman.pos, if there is one: each icon named there goes
; where it says.
pm_load:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, pm_path
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov edi, pm_fbuf
    mov ecx, PM_FBUF - 1
    call fs_read
    push eax
    call fs_close
    pop eax
    cmp eax, -1
    je .r
    mov byte [pm_fbuf+eax], 0
    mov esi, pm_fbuf
.line:
    cmp byte [esi], 0
    je .r
    mov edi, pm_word            ; the name, up to a space
    mov ecx, 15
.n:
    lodsb
    cmp al, ' '
    je .nd
    test al, al
    jz .r
    cmp al, 10
    je .line
    jecxz .n
    stosb
    dec ecx
    jmp .n
.nd:
    mov byte [edi], 0
    call pm_getn
    mov [pm_lx], eax
    call pm_getn
    mov [pm_ly], eax
.eol:
    lodsb                       ; to the next line
    test al, al
    jz .last
    cmp al, 10
    jne .eol
    call pm_setpos
    jmp .line
.last:
    call pm_setpos
.r:
    popad
    ret

; esi = text -> eax = the number at it (spaces skipped), esi past it
pm_getn:
    xor eax, eax
.sp:
    cmp byte [esi], ' '
    jne .d
    inc esi
    jmp .sp
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .r
    imul eax, eax, 10
    add eax, edx
    inc esi
    jmp .d
.r:
    ret

; the icon named pm_word goes to pm_lx, pm_ly
pm_setpos:
    pushad
    xor ebp, ebp
.g:
    cmp ebp, [pm_ng]
    jae .r
    xor ebx, ebx
.i:
    cmp ebx, [pm_gn+ebp*4]
    jae .gn
    imul edi, ebp, PM_IMAX
    add edi, ebx
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    push ebx
    xor ebx, ebx
    call obj_get
    pop ebx
    mov esi, eax
    push edi
    mov edi, pm_word
    call streq
    pop edi
    jne .in
    mov eax, [pm_lx]
    mov [pm_gx+edi*4], eax
    mov eax, [pm_ly]
    mov [pm_gy+edi*4], eax
.in:
    inc ebx
    jmp .i
.gn:
    inc ebp
    jmp .g
.r:
    popad
    ret

; ---------- context menu (2.6-context) ----------

; Right-button at (dk_lmx, dk_lmy): if over an icon, select it (without
; arming the double-click timer) and open the context menu there.
pm_ctx_at:
    pushad
    mov eax, [dk_lmx]
    mov ebx, [dk_lmy]
    call wm_hit
    cmp eax, -1
    je .r
    cmp ebx, HT_CLIENT
    jne .r
    call pm_group               ; eax = window -> ebp = group
    jc .r
    push eax
    call wm_record              ; edi = window record
    pop eax
    jc .r
    mov eax, [dk_lmx]
    sub eax, [edi+WIN_X]
    dec eax                     ; client x
    mov ebx, [dk_lmy]
    sub ebx, [edi+WIN_Y]
    sub ebx, WM_TITLE_H + 1     ; client y
    call pm_pick                ; select only; not half a double-click
    call pm_ctx_popup
.r:
    popad
    ret

; ebp = group, eax, ebx = client press: choose the icon under the pointer
; without updating pm_last / pm_lastt / pm_drag (right-click must not count
; as half a double-click; Sarah #186).
pm_pick:
    pushad
    xor esi, esi
.i:
    cmp esi, [pm_gn+ebp*4]
    jae .r
    imul edi, ebp, PM_IMAX
    add edi, esi
    mov edx, eax
    sub edx, [pm_gx+edi*4]
    cmp edx, PM_CW
    jae .n
    mov edx, ebx
    sub edx, [pm_gy+edi*4]
    cmp edx, PM_CH
    jb .hit
.n:
    inc esi
    jmp .i
.hit:
    mov [pm_gsel+ebp*4], esi
    mov byte [pm_dirty], 1
.r:
    popad
    ret

; Opens the context menu under the pointer for the focused/selected icon.
pm_ctx_popup:
    pushad
    mov eax, [dk_lmx]
    mov ebx, [dk_lmy]
    mov esi, pm_ctx_items
    mov edx, PM_CTX_N
    mov ecx, -1                 ; owner: not a window; WME_MENU still fires
    call wg_menu
    mov byte [pm_dirty], 1
    popad
    ret

; eax = menu item index: Open / Open as... / Settings / Arrange.
pm_ctx_do:
    pushad
    mov [pm_ctx_last], eax
    cmp eax, PM_CTX_OPEN
    je .open
    cmp eax, PM_CTX_OPENAS
    je .openas
    cmp eax, PM_CTX_SETTINGS
    je .settings
    cmp eax, PM_CTX_ARRANGE
    je .arrange
    jmp .r
.open:
    call pm_launch
    jmp .r
.openas:
    call pm_openas_popup
    mov byte [pm_oa_pend], 1
    jmp .r
.settings:
    call pm_settings
    jmp .r
.arrange:
    call pm_focus
    jc .r
    call pm_arrange
    call pm_save
.r:
    popad
    ret

; Open as submenu (W.5): Icon / Tree / Details / Settings.
pm_openas_popup:
    pushad
    mov eax, [dk_lmx]
    mov ebx, [dk_lmy]
    add eax, 8
    add ebx, 8
    mov esi, pm_oaitems
    mov edx, PM_OA_N
    mov ecx, -1
    call wg_menu
    mov byte [pm_dirty], 1
    popad
    ret

; eax = PM_OA_*: open File Manager in that view, or Settings on the object.
pm_openas_do:
    pushad
    mov [pm_oa_last], eax
    cmp eax, PM_OA_SETTINGS
    je .set
    cmp eax, PM_OA_DETAILS
    ja .r
    ; Icon / Tree / Details: open the folder view through File Manager.
    mov ebx, eax                ; keep FMV_* across fm_scan
    call fm_scan                ; refresh from fm_cur (cwd / last dir)
    mov eax, ebx
    call fm_setview
    cmp dword [fm_win], -1
    jne .drawn
    cmp dword [gfx_width], 640
    jb .small
    mov eax, 40
    mov ebx, 40
    mov ecx, 560
    mov edx, 400
    jmp .mk
.small:
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
.mk:
    mov esi, fm_title
    call wm_create
    cmp eax, -1
    je .r
    mov [fm_win], eax
    imul edi, eax, WIN_SIZE
    mov dword [wm_table+edi+WIN_PAINT], fm_paint
.drawn:
    call wm_redraw
    jmp .r
.set:
    call pm_settings
.r:
    popad
    ret

; Opens a small settings notebook for the chosen icon (General / View).
pm_settings:
    pushad
    call pm_focus
    jc .r
    cmp dword [pm_gn+ebp*4], 0
    je .r
    call wps_settings           ; W.2: same notebook path for every object
.r:
    popad
    ret

; ---------- dkctx (2.6-context / Sarah #186 follow-up) ----------
; Builds Program Manager groups, opens the context menu on calc, chooses
; Open / Settings / Arrange through wm_menuchoose (Open as is on the menu
; too; W.5 exercises it in openas), checks a settings notebook tab pixel,
; switches the View tab via wg_nbclick, and checks that pm_pick does not
; arm the double-click timer. Prints `dk-ctx: PASS` or `dk-ctx: FAIL`.
cmd_dkctx_run:
    call wm_screen
    mov esi, dkctx_fail
    jc .say
    mov byte [pm_tok], 1
    mov byte [pm_tstep], '0'
    call dk_mkobjs
    call pm_build
    mov byte [pm_tstep], '1'
    cmp dword [pm_ng], 0
    je .bad
    xor ebp, ebp                ; Main
    mov esi, pm_t_calc
    call pm_find
    mov byte [pm_tstep], '2'
    jc .bad
    mov [pm_tslot], edi
    mov [pm_ticon], ebx
    mov [pm_gsel], ebx          ; select calc in Main
    mov dword [pm_set_win], -1
    mov dword [pm_set_nb], -1
    ; pointer over calc's cell
    mov edx, edi                ; slot
    mov eax, [pm_gwin]
    call wm_record              ; edi = Main window record
    jc .bad
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    add eax, 1
    add eax, [pm_gx+edx*4]
    add ebx, 1 + WM_TITLE_H
    add ebx, [pm_gy+edx*4]
    add eax, 10
    add ebx, 10
    mov [dk_lmx], eax
    mov [dk_lmy], ebx
    mov byte [pm_tstep], '3'
    call pm_ctx_popup
    cmp dword [wm_mn], PM_CTX_N
    jne .bad
    ; Open (menu choice only — launching calc would enter its window)
    mov dword [wm_msel], PM_CTX_OPEN
    call wm_menuchoose
    cmp eax, WME_MENU
    jne .bad
    cmp ecx, PM_CTX_OPEN
    jne .bad
    mov [pm_ctx_last], ecx
    mov byte [pm_tstep], '4'
    ; Settings -> notebook window
    call pm_ctx_popup
    mov dword [wm_msel], PM_CTX_SETTINGS
    call wm_menuchoose
    cmp eax, WME_MENU
    jne .bad
    mov eax, ecx
    call pm_ctx_do
    cmp dword [pm_ctx_last], PM_CTX_SETTINGS
    jne .bad
    cmp dword [pm_set_win], -1
    je .bad
    cmp dword [pm_set_nb], -1
    je .bad
    mov eax, [pm_set_win]
    call wm_record
    jc .bad
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    add eax, 1 + 8 + TH_BEVEL_W + 2
    add ebx, 1 + WM_TITLE_H + 8 + TH_BEVEL_W + 1
    mov dl, TH_FACE
    call .probe
    jc .bad
    mov byte [pm_tstep], '5'
    ; tab click: switch to View (tab 1) via wg_nbclick (as nbtest)
    mov esi, pm_set_t0
    mov ecx, FONT_9
    call gfx_strwidth_p
    add eax, NB_TAB_PAD
    add eax, 4
    mov ebx, eax
    mov eax, [pm_set_nb]
    mov ecx, 4                  ; in the tab strip
    call wg_nbclick
    jc .bad
    mov eax, [pm_set_nb]
    imul eax, WG_SIZE
    cmp dword [wg_table+eax+WG_SEL], 1
    jne .bad
    mov byte [pm_tstep], '6'
    ; close settings so Main is focused again for Arrange
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
    mov dword [pm_set_nb], -1
    mov eax, [pm_gwin]
    call wm_raise
    ; Arrange
    call pm_ctx_popup
    mov dword [wm_msel], PM_CTX_ARRANGE
    call wm_menuchoose
    mov eax, ecx
    call pm_ctx_do
    cmp dword [pm_ctx_last], PM_CTX_ARRANGE
    jne .bad
    mov byte [pm_tstep], '7'
    ; pm_pick must not arm the double-click timer
    mov dword [pm_last], -1
    mov dword [pm_lastt], 0
    xor ebp, ebp
    mov edi, [pm_tslot]
    mov eax, [pm_gx+edi*4]
    mov ebx, [pm_gy+edi*4]
    add eax, 10
    add ebx, 10
    call pm_pick
    mov eax, [pm_ticon]
    cmp [pm_gsel], eax
    jne .bad
    cmp dword [pm_last], -1
    jne .bad
    cmp dword [pm_lastt], 0
    jne .bad
    mov byte [pm_tstep], '8'
    ; a left-press soon after pick must NOT be a double-click
    mov edi, [pm_tslot]
    mov eax, [pm_gx+edi*4]
    mov ebx, [pm_gy+edi*4]
    add eax, 10
    add ebx, 10
    mov ecx, 100
    call pm_press
    jc .bad                     ; pick did not arm; first press is single
    mov byte [pm_tstep], '9'
    ; Open as is present (W.5); openas self-check drives the cascade
    call pm_ctx_popup
    cmp dword [wm_mn], PM_CTX_N
    jne .bad
    call wm_menuclose
    jmp .end
.probe:                         ; dl = expected at (eax, ebx); CF set on miss
    push edx
    call gfx_getpixel
    pop edx
    cmp cl, dl
    je .pok
    stc
    ret
.pok:
    clc
    ret
.bad:
    mov byte [pm_tok], 0
.end:
    cmp dword [pm_set_win], -1
    je .noset
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.noset:
    xor ebp, ebp
.close:
    mov eax, [pm_gwin+ebp*4]
    cmp eax, -1
    je .cn
    call wm_close
.cn:
    inc ebp
    cmp ebp, PM_GMAX
    jb .close
    call dk_freeobjs
    call gfx_text
    mov esi, dkctx_pass
    cmp byte [pm_tok], 1
    je .say
    mov esi, dkctx_fail
.say:
    jmp puts

; ---------- pmtest ----------
; Builds the groups without the loop and checks them: Main has the five
; programs plus System Setup and Shredder (W.6), and Tools is a group of
; its own; a press on calc chooses it, a drag of (40, 16) moves it and
; saves; the places read back put it there again; a second press soon
; after on calc is a double-click, a late one is not; arrange puts it
; back in its row. Prints `pm: PASS` or `pm: FAIL`.
cmd_pmtest_run:
    call wm_screen
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    call dk_mkobjs
    call pm_build
    mov byte [pm_tok], 1
    cmp dword [pm_ng], 4        ; Main + Tools + Templates + Startup (#236)
    mov byte [pm_tstep], 1
    jb .bad
    cmp dword [pm_gn], 7        ; 5 programs + System Setup + Shredder
    mov byte [pm_tstep], 2
    jne .bad
    mov esi, [pm_gname+4]
    mov edi, pm_t_tools
    call streq
    mov byte [pm_tstep], 3
    jne .bad
    mov esi, [pm_gname+8]
    mov edi, pm_t_templates
    call streq
    mov byte [pm_tstep], 'A'
    jne .bad
    mov esi, [pm_gname+12]
    mov edi, pm_t_startup
    call streq
    mov byte [pm_tstep], 'B'
    jne .bad
    xor ebp, ebp                ; Main: find calc
    mov esi, pm_t_calc
    call pm_find                ; -> edi = slot, ebx = icon
    mov byte [pm_tstep], 4
    jc .bad
    mov [pm_tslot], edi
    mov [pm_ticon], ebx
    mov eax, [pm_gx+edi*4]
    mov [pm_tx], eax
    mov ebx, [pm_gy+edi*4]
    mov [pm_ty], ebx
    add eax, 10                 ; a press inside its cell at time 1000
    add ebx, 10
    mov ecx, 1000
    call pm_press
    jc .bad                     ; not a double-click
    mov eax, [pm_ticon]
    cmp [pm_gsel], eax
    mov byte [pm_tstep], 5
    jne .bad
    mov ecx, 40                 ; dragged by (40, 16)
    mov edx, 16
    call pm_release
    mov edi, [pm_tslot]
    mov eax, [pm_tx]
    add eax, 40
    cmp [pm_gx+edi*4], eax
    mov byte [pm_tstep], 6
    jne .bad
    mov eax, [pm_ty]
    add eax, 16
    cmp [pm_gy+edi*4], eax
    mov byte [pm_tstep], 7
    jne .bad
    call pm_layout              ; back in its row, then the file read:
    call pm_load                ; moved again
    mov edi, [pm_tslot]
    mov eax, [pm_tx]
    add eax, 40
    cmp [pm_gx+edi*4], eax
    mov byte [pm_tstep], 8
    jne .bad
    mov eax, [pm_gx+edi*4]      ; two presses 20 ticks apart: a double-click
    mov ebx, [pm_gy+edi*4]
    add eax, 4
    add ebx, 4
    mov ecx, 2000
    call pm_press
    mov byte [pm_tstep], 9
    jc .bad
    mov ecx, 0                  ; (no drag)
    mov edx, 0
    call pm_release
    mov ecx, 2020
    call pm_press
    mov byte [pm_tstep], 10
    jnc .bad
    mov ecx, 3000               ; then one press, and another much later
    call pm_press
    mov byte [pm_tstep], 11
    jc .bad
    xor ecx, ecx
    xor edx, edx
    call pm_release
    mov ecx, 3000 + PM_DBL + 10
    call pm_press
    mov byte [pm_tstep], 12
    jc .bad
    xor ecx, ecx
    xor edx, edx
    call pm_release
    call pm_arrange             ; arrange: back in its row, and saved so
    call pm_save
    mov edi, [pm_tslot]
    mov eax, [pm_tx]
    cmp [pm_gx+edi*4], eax
    mov byte [pm_tstep], 13
    jne .bad
    jmp .end
.bad:
    mov byte [pm_tok], 0
.end:
    xor ebp, ebp
.close:
    mov eax, [pm_gwin+ebp*4]
    cmp eax, -1
    je .cn
    call wm_close
.cn:
    inc ebp
    cmp ebp, PM_GMAX
    jb .close
    call dk_freeobjs
    call gfx_text
    mov esi, pm_pass
    cmp byte [pm_tok], 1
    je .say
    mov esi, pm_fail
    call puts
    movzx eax, byte [pm_tstep]  ; which check failed
    call itoa
    mov esi, num_buf
    call puts
    mov esi, pm_nl
.say:
    jmp puts

; ebp = group, esi = a name -> edi = its icon's slot, ebx = the icon, CF
; clear; CF set if the group has none by that name
pm_find:
    push eax
    xor ebx, ebx
.i:
    cmp ebx, [pm_gn+ebp*4]
    jae .no
    imul edi, ebp, PM_IMAX
    add edi, ebx
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    push ebx
    push edi
    xor ebx, ebx
    call obj_get
    mov edi, eax
    call streq
    pop edi
    pop ebx
    je .yes
    inc ebx
    jmp .i
.yes:
    pop eax
    clc
    ret
.no:
    pop eax
    stc
    ret

PM_FBUF equ 512
align 4
pm_ng dd 0
pm_gwin times PM_GMAX dd -1
pm_gname times PM_GMAX dd 0
pm_gfold times PM_GMAX dd 0
pm_gn times PM_GMAX dd 0
pm_gsel times PM_GMAX dd 0
pm_gobj times PM_GMAX * PM_IMAX dd 0   ; the object's index in dk_objs
pm_gx times PM_GMAX * PM_IMAX dd 0     ; its cell in the client area
pm_gy times PM_GMAX * PM_IMAX dd 0
pm_drag dd -1                   ; the slot being dragged, or -1
pm_dx0 dd 0                     ; where the drag started on the screen
pm_dy0 dd 0
pm_last dd -1                   ; the last press: slot and time
pm_lastt dd 0
pm_mclicks dd 0
pm_cx dd 0
pm_cy dd 0
pm_sv dd 0, 0, 0, 0
pm_flen dd 0
pm_lx dd 0
pm_ly dd 0
pm_tslot dd 0
pm_ticon dd 0
pm_tx dd 0
pm_ty dd 0
pm_atx dd 0
pm_aty dd 0
pm_kmove db 0
pm_dirty db 0
pm_open db 0
pm_ink db 0
pm_bg db 0
pm_tok db 0
pm_tstep db 0
pm_nl db 10, 0
pm_word times 16 db 0
pm_fbuf times PM_FBUF db 0
pm_path db '/desktop/progman.pos', 0
pm_t_main db 'Main', 0
pm_t_tools db 'Tools', 0
pm_t_templates db 'Templates', 0
pm_t_startup db 'Startup', 0
pm_t_calc db 'calc', 0
pm_bye db 'Program Manager closed.', 10, 0
pm_pass db 'pm: PASS', 10, 0
pm_fail db 'pm: FAIL at ', 0
pm_ctx_items dd pm_ctx_open, pm_ctx_oas, pm_ctx_set, pm_ctx_arr
pm_ctx_open db 'Open', 0
pm_ctx_oas db 'Open as...', 0
pm_ctx_set db 'Settings', 0
pm_ctx_arr db 'Arrange', 0
align 4
pm_oaitems dd pm_oa_icon, pm_oa_tree, pm_oa_det, pm_oa_set
pm_oa_icon db 'Icon', 0
pm_oa_tree db 'Tree', 0
pm_oa_det db 'Details', 0
pm_oa_set db 'Settings', 0
pm_set_title db 'Settings', 0
pm_set_t0 db 'General', 0
pm_set_t1 db 'View', 0
pm_set_tabs dd pm_set_t0, pm_set_t1
dkctx_pass db 'dk-ctx: PASS', 10, 0
dkctx_fail db 'dk-ctx: FAIL', 10, 0
align 4
pm_ctx_last dd -1
pm_oa_last dd -1
pm_set_win dd -1
pm_set_nb dd -1
pm_rbtn db 0
pm_oa_pend db 0
