; Squirrel-OS/2 — WarpCenter bar (2.5-bar / 2.5-menu / 2.5-clock). Original code.
;
; A raised strip along the top of the window manager's screen: a Squirrel
; menu on the left that lists top-level desktop programs (and folders) and
; launches the chosen Program; a tray clock on the right that shows the
; CMOS time and redraws when the second changes. While the bar is live,
; Program Manager group windows sit below it (wc_top). Drawn by wc_paint
; from wm_paint, above the windows and under pop-up menus.
;
; Commands: warpcenter (interactive), wcbar / wcmenu / wcclock (self-checks
; that print wc-bar / wc-menu / wc-clock: PASS). See documentation/apps/desktop.md.

WPC_H        equ 28              ; bar height in pixels
WPC_PAD      equ 4
WPC_BTN_X    equ WPC_PAD
WPC_BTN_Y    equ WPC_PAD
WPC_BTN_W    equ 80
WPC_BTN_H    equ WPC_H - 2 * WPC_PAD
WPC_CLK_W    equ 72              ; room for "HH:MM:SS"
WPC_MMAX     equ 8               ; menu items at most (wm_popup limit)

; ---------- interactive ----------

cmd_warpcenter_run:
    call wm_screen
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    mov eax, [gfx_width]
    sub eax, GFX_W
    shr eax, 1
    mov [dk_ox], eax
    mov eax, [gfx_height]
    sub eax, GFX_H
    shr eax, 1
    mov [dk_oy], eax
    call wc_on
    call dk_mkobjs
    call pm_build
    call pm_load
    mov byte [dk_quit], 0
    mov byte [pm_kmove], 0
    mov dword [pm_drag], -1
    mov dword [dk_menu], 0
    mov eax, [mouse_clicks]
    mov [pm_mclicks], eax
    call wc_tick                ; first clock face
.draw:
    call wm_redraw
    call ptr_show
.key:
    call mouse_poll
    call wc_barhit              ; Squirrel button press
    call pm_wm
    jc .quit
    call ptr_show
    call wc_tick                ; redraw the clock when the second changes
    mov eax, [dk_menu]
    test eax, eax
    jz .nomenu
    mov dword [dk_menu], 0
    dec eax                     ; item index
    call wc_launch
    jmp .draw
.nomenu:
    cmp byte [pm_open], 0
    je .nokey
    mov byte [pm_open], 0
    call pm_launch
    jmp .draw
.nokey:
    cmp byte [pm_dirty], 0
    je .k
    mov byte [pm_dirty], 0
    jmp .draw
.k:
    call dk_trykey
    jc .key
    cmp byte [dk_quit], 0
    jne .quit
    cmp al, 27
    je .quit
    cmp al, 's'
    je .menu
    cmp al, 'S'
    je .menu
    call pm_focus
    jnc .focused
    jmp .key
.focused:
    cmp byte [pm_kmove], 0
    jne .moving
    cmp al, 10
    je .open
    cmp al, 'm'
    je .startmove
    cmp al, 'a'
    je .arrange
    call pm_choose
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
.menu:
    call wc_openmenu
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
    call wc_off
    call gfx_text
    mov esi, [lstr+LS_WC_BYE*4]
    call puts
    mov al, 10
    jmp putc

; ---------- enable / disable ----------

; Marks the bar live and reserves its strip for pm_place.
wc_on:
    mov byte [wc_live], 1
    mov dword [wc_top], WPC_H
    mov dword [wc_last], -1
    mov dword [wc_mbtn], 0
    ret

wc_off:
    call wm_menuclose
    mov byte [wc_live], 0
    mov dword [wc_top], 0
    mov dword [wc_last], -1
    ret

; ---------- painting (called from wm_paint) ----------

; The raised WarpCenter strip, the Squirrel button and the tray clock.
wc_paint:
    cmp byte [wc_live], 0
    je .r
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, [gfx_width]
    mov edx, WPC_H
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi                ; raised
    call gfx_bevel
    ; Squirrel button
    mov eax, WPC_BTN_X
    mov ebx, WPC_BTN_Y
    mov ecx, WPC_BTN_W
    mov edx, WPC_BTN_H
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi
    call gfx_bevel
    mov esi, [lstr+LS_WC_BTN*4]
    add eax, TH_BEVEL_W + 4
    add ebx, TH_BEVEL_W + 2
    mov ecx, WPC_BTN_W - 2 * TH_BEVEL_W - 8
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_FACE
    call wm_drawtitle
    ; tray clock on the right
    call wc_fmtclock
    mov eax, [gfx_width]
    sub eax, WPC_CLK_W
    sub eax, WPC_PAD
    mov ebx, WPC_BTN_Y + TH_BEVEL_W + 2
    mov ecx, WPC_CLK_W
    mov esi, wc_clkbuf
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_FACE
    call wm_drawtitle
    popad
.r:
    ret

; Reads the CMOS time into wc_clkbuf as "HH:MM:SS".
wc_fmtclock:
    pushad
    call gui_time
    mov edi, wc_clkbuf
    call cp_ftime
    popad
    ret

; If the second has changed, marks the clock strip and repaints.
wc_tick:
    cmp byte [wc_live], 0
    je .r
    pushad
    call gui_time
    cmp eax, [wc_last]
    je .out
    mov [wc_last], eax
    mov eax, [gfx_width]
    sub eax, WPC_CLK_W
    sub eax, WPC_PAD
    mov ebx, 0
    mov ecx, WPC_CLK_W + WPC_PAD
    mov edx, WPC_H
    call wm_mark
    call wm_update
    call ptr_show
.out:
    popad
.r:
    ret

; ---------- Squirrel menu ----------

; Builds the menu from top-level desktop objects and opens it under the
; Squirrel button.
wc_openmenu:
    pushad
    call wc_fillmenu
    test edx, edx
    jz .r
    mov eax, WPC_BTN_X
    mov ebx, WPC_H
    mov esi, wc_mitems
    mov ecx, -1                 ; owner: not a window; WME_MENU still fires
    call wm_popup
    call wm_update
    call ptr_show
.r:
    popad
    ret

; Fills wc_mitems / wc_mobjs from top-level Programs and Folders.
; -> edx = how many (at most WPC_MMAX).
wc_fillmenu:
    push eax
    push ebx
    push esi
    push edi
    xor edx, edx
    xor ebx, ebx
.i:
    cmp ebx, [dk_n]
    jae .done
    cmp edx, WPC_MMAX
    jae .done
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .n
    call pm_in                  ; esi = its `in`
    cmp byte [esi], 0
    jne .n                      ; only the top level
    push ebx
    xor ebx, ebx
    call obj_get                ; name
    pop ebx
    test eax, eax
    jz .n
    mov [wc_mitems+edx*4], eax
    mov [wc_mobjs+edx*4], ebx   ; index in dk_objs
    inc edx
.n:
    inc ebx
    jmp .i
.done:
    mov [wc_mn], edx
    pop edi
    pop esi
    pop ebx
    pop eax
    ret

; eax = menu item index: opens that Program (Folders open nothing here).
wc_launch:
    pushad
    cmp eax, [wc_mn]
    jae .r
    mov ebx, [wc_mobjs+eax*4]
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .r
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .r
    cmp byte [wc_test], 0
    jne .tested
    mov esi, dk_s_open
    call obj_send
    jmp .r
.tested:
    ; self-check: confirm the entry is the program named in wc_want
    mov byte [wc_ok], 0
    mov ebx, 2
    call obj_get
    test eax, eax
    jz .r
    mov esi, eax
    mov edi, [wc_want]
    call streq
    jne .r
    mov byte [wc_ok], 1
.r:
    popad
    ret

; A left-button press on the Squirrel button opens the menu.
wc_barhit:
    cmp byte [wc_live], 0
    je .r
    pushad
    pushfd
    cli
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    mov cl, [mouse_btns]
    popfd
    test cl, 1
    jz .up
    cmp byte [wc_mbtn], 0
    jne .out                    ; already held
    mov byte [wc_mbtn], 1
    cmp ebx, WPC_H
    jae .out
    cmp eax, WPC_BTN_X
    jb .out
    cmp eax, WPC_BTN_X + WPC_BTN_W
    jae .out
    cmp ebx, WPC_BTN_Y
    jb .out
    cmp ebx, WPC_BTN_Y + WPC_BTN_H
    jae .out
    call wc_openmenu
    jmp .out
.up:
    mov byte [wc_mbtn], 0
.out:
    popad
.r:
    ret

; ---------- self-checks ----------

; Pixel probe of the bar face and raised bevel -> wc-bar: PASS
cmd_wcbar_run:
    call wm_screen
    mov esi, wc_bar_fail
    jc .say
    mov byte [wc_ok], 1
    mov byte [wc_stage], '0'
    call wc_on
    call wm_redraw
    ; outer top-left of the raised bevel
    mov byte [wc_stage], '1'
    xor eax, eax
    xor ebx, ebx
    mov dl, TH_LIGHT
    call .probe
    jc .bad
    ; face just inside the bevel, between the button and the clock
    mov byte [wc_stage], '2'
    mov eax, WPC_BTN_X + WPC_BTN_W + 8
    mov ebx, TH_BEVEL_W + 2
    mov dl, TH_FACE
    call .probe
    jc .bad
    ; outer bottom edge
    mov byte [wc_stage], '3'
    xor eax, eax
    mov ebx, WPC_H - 1
    mov dl, TH_DARK
    call .probe
    jc .bad
    ; Squirrel button's raised top-left
    mov byte [wc_stage], '4'
    mov eax, WPC_BTN_X
    mov ebx, WPC_BTN_Y
    mov dl, TH_LIGHT
    call .probe
    jc .bad
    jmp .end
.bad:
    mov byte [wc_ok], 0
.end:
    call wc_off
    call gfx_text
    mov esi, wc_bar_pass
    cmp byte [wc_ok], 1
    je .say
    mov esi, wc_bar_fail
.say:
    jmp puts
.probe:                         ; dl = expected; CF set on mismatch
    push edx
    call gfx_getpixel
    pop edx
    cmp cl, dl
    je .same
    stc
    ret
.same:
    clc
    ret

; Menu lists calc and selecting it would launch that Program -> wc-menu: PASS
cmd_wcmenu_run:
    call wm_screen
    mov esi, wc_menu_fail
    jc .say
    mov byte [wc_ok], 0
    mov byte [wc_stage], '0'
    mov byte [wc_test], 1
    mov dword [wc_want], dk_a1  ; "calc"
    call wc_on
    call dk_mkobjs
    mov byte [wc_stage], '1'
    cmp dword [dk_n], 0
    je .fail                    ; no desktop objects at all
    mov byte [wc_stage], '2'
    call wc_fillmenu
    mov edx, [wc_mn]
    test edx, edx
    jz .fail
    ; find calc among the items (by name); streq clobbers eax
    xor ebx, ebx
.find:
    cmp ebx, edx
    jae .nofind
    mov esi, [wc_mitems+ebx*4]
    test esi, esi
    jz .next
    mov edi, dk_a1
    call streq
    je .got
.next:
    inc ebx
    jmp .find
.nofind:
    mov byte [wc_stage], 'a'    ; menu filled but no calc name
    jmp .fail
.got:
    mov eax, ebx                ; item index
    mov byte [wc_stage], '3'
    call wc_launch              ; sets wc_ok when entry is calc
    cmp byte [wc_ok], 1
    jne .fail
    ; also open the pop-up and choose that item through wm_menuchoose
    mov byte [wc_stage], '4'
    push eax
    call wc_openmenu
    pop eax
    mov [wm_msel], eax
    call wm_menuchoose          ; -> WME_MENU, ecx = item
    cmp eax, WME_MENU
    jne .fail
    mov byte [wc_stage], '5'
    mov eax, ecx
    call wc_launch
    cmp byte [wc_ok], 1
    jne .fail
    jmp .end
.fail:
    mov byte [wc_ok], 0
.end:
    call dk_freeobjs
    call wc_off
    mov byte [wc_test], 0
    call gfx_text
    mov esi, wc_menu_pass
    cmp byte [wc_ok], 1
    je .say
    mov esi, wc_menu_fail
.say:
    jmp puts

; Tray clock shows the RTC and changes after a scripted set -> wc-clock: PASS
cmd_wcclock_run:
    call wm_screen
    mov esi, wc_clock_fail
    jc .say
    mov byte [wc_ok], 1
    mov byte [wc_stage], '0'
    call gui_time               ; keep the live clock
    mov [wc_keep], eax
    call wc_on
    mov eax, (12 << 16) | (34 << 8) | 56
    call cp_settime
    call wc_fmtclock
    call wm_redraw
    mov byte [wc_stage], '1'
    mov esi, wc_clkbuf
    mov edi, wc_t1
    call streq
    jne .bad
    ; some ink in the clock band (FONT_9 digits on the face)
    mov byte [wc_stage], '2'
    call .ink
    jc .bad
    mov byte [wc_stage], '3'
    mov eax, (12 << 16) | (34 << 8) | 57
    call cp_settime
    call wc_fmtclock
    call wm_redraw              ; full repaint so the new digits are drawn
    mov esi, wc_clkbuf
    mov edi, wc_t2
    call streq
    jne .bad
    mov byte [wc_stage], '4'
    ; the two faces differ
    mov esi, wc_t1
    mov edi, wc_t2
    call streq
    je .bad
    jmp .rest
.bad:
    mov byte [wc_ok], 0
.rest:
    mov eax, [wc_keep]
    call cp_settime
    call wc_off
    call gfx_text
    mov esi, wc_clock_pass
    cmp byte [wc_ok], 1
    je .say
    mov esi, wc_clock_fail
.say:
    jmp puts
.ink:                           ; CF clear if a non-face pixel sits in the clock band
    pushad
    mov eax, [gfx_width]
    sub eax, WPC_CLK_W
    sub eax, WPC_PAD
    mov ebx, WPC_BTN_Y + TH_BEVEL_W + 2
    mov edx, 10                 ; rows
.row:
    push eax
    mov ecx, WPC_CLK_W - 4
.col:
    push eax
    push ebx
    push ecx
    call gfx_getpixel
    pop ecx
    pop ebx
    pop eax
    cmp cl, TH_FACE
    jne .found
    inc eax
    loop .col
    pop eax
    inc ebx
    dec edx
    jnz .row
    popad
    stc
    ret
.found:
    pop eax
    popad
    clc
    ret

; ---------- data ----------

wc_bar_pass db 'wc-bar: PASS', 10, 0
wc_bar_fail db 'wc-bar: FAIL', 10, 0
wc_menu_pass db 'wc-menu: PASS', 10, 0
wc_menu_fail db 'wc-menu: FAIL', 10, 0
wc_clock_pass db 'wc-clock: PASS', 10, 0
wc_clock_fail db 'wc-clock: FAIL', 10, 0
wc_t1 db '12:34:56', 0
wc_t2 db '12:34:57', 0
wc_clkbuf times 16 db 0
wc_live db 0
wc_ok db 0
wc_test db 0
wc_mbtn db 0
wc_stage db '0'
align 4
wc_top dd 0                     ; added to group window Y in pm_place
wc_last dd -1
wc_keep dd 0
wc_want dd 0
wc_mn dd 0
wc_mitems times WPC_MMAX dd 0
wc_mobjs times WPC_MMAX dd 0
