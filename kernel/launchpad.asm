; Squirrel-OS/2 — LaunchPad pads (W.3-launchpad). Original code.
;
; Pads on the shared top chrome with WarpCenter (2.5-bar): when the
; WarpCenter bar is live, pads sit between the Squirrel button and the
; tray clock on that strip (`lp_top` stays 0; `wc_top` reserves the
; height). Alone, LaunchPad owns the same-height strip (`lp_top = LP_H`).
; Drop a Program onto a pad (drag-release or digit), click to launch;
; `/desktop/launchpad.cfg` persists. Drawn by lp_paint from wm_paint after
; wc_paint. See documentation/apps/desktop.md.
;
; Commands: launchpad (interactive), wclp (self-check -> wclp: PASS).

LP_H        equ WPC_H           ; shared top-chrome height with WarpCenter
LP_PAD      equ 4
LP_N        equ 6               ; pads on the strip
LP_PW       equ 72              ; each pad's width
LP_PH       equ LP_H - 2 * LP_PAD
LP_GAP      equ 4
LP_NAMEMAX  equ 15              ; program entry name, cut like progman
LP_FBUF     equ 256

; ---------- interactive ----------

cmd_launchpad_run:
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
    call wc_on                  ; shared top chrome (Squirrel + clock)
    call lp_on                  ; pads on that strip
    call dk_mkobjs
    call pm_build
    call pm_load
    call lp_load
    mov byte [dk_quit], 0
    mov byte [pm_kmove], 0
    mov dword [pm_drag], -1
    mov dword [dk_menu], 0
    mov eax, [mouse_clicks]
    mov [pm_mclicks], eax
    call wc_tick
.draw:
    call wm_redraw
    call ptr_show
.key:
    call mouse_poll
    call wc_barhit              ; Squirrel button
    call lp_barhit              ; pad click / drop
    call pm_wm
    jc .quit
    call ptr_show
    call wc_tick
    mov eax, [dk_menu]
    test eax, eax
    jz .nomenu
    mov dword [dk_menu], 0
    dec eax
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
    ; digit 1..LP_N: drop the chosen icon onto that pad, or launch if
    ; the pad already has a name and nothing is chosen to drop
    cmp al, '1'
    jb .pm
    cmp al, '0' + LP_N
    ja .pm
    sub al, '1'
    movzx eax, al
    call lp_digit
    jmp .draw
.pm:
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
    call lp_save
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
    call lp_off
    call wc_off
    call gfx_text
    mov esi, [lstr+LS_LP_BYE*4]
    call puts
    mov al, 10
    jmp putc

; ---------- enable / disable ----------

; Marks pads live. Alone: reserves LP_H via lp_top. With WarpCenter:
; pads sit on the bar and lp_top stays 0 (wc_top already reserves).
lp_on:
    mov byte [lp_live], 1
    mov dword [lp_mbtn], 0
    call lp_clear
    cmp byte [wc_live], 0
    jne .shared
    mov dword [lp_top], LP_H
    ret
.shared:
    mov dword [lp_top], 0
    ret

lp_off:
    mov byte [lp_live], 0
    mov dword [lp_top], 0
    mov dword [lp_mbtn], 0
    ret

; Clears every pad name.
lp_clear:
    pushad
    mov edi, lp_names
    mov ecx, LP_N * (LP_NAMEMAX + 1)
    xor eax, eax
    rep stosb
    popad
    ret

; ---------- painting (called from wm_paint) ----------

; Pads (and the strip when LaunchPad owns it alone). When WarpCenter is
; live, wc_paint already drew the bar — only the pad faces are painted.
lp_paint:
    cmp byte [lp_live], 0
    je .r
    pushad
    cmp byte [wc_live], 0
    jne .pads                   ; shared chrome: do not refill the strip
    xor eax, eax
    xor ebx, ebx
    mov ecx, [gfx_width]
    mov edx, LP_H
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi                ; raised
    call gfx_bevel
.pads:
    xor ebp, ebp
.pad:
    cmp ebp, LP_N
    jae .out
    call lp_padxy               ; -> eax, ebx, ecx, edx = pad rect
    push eax
    push ebx
    push ecx
    push edx
    ; empty pads are sunken wells; filled pads are raised faces with a name
    call lp_padname             ; -> esi = name
    cmp byte [esi], 0
    je .empty
    mov byte [gfx_colour], TH_FACE
    call gfx_fillrect
    xor esi, esi                ; raised
    call gfx_bevel
    call lp_padname
    pop edx
    pop ecx
    pop ebx
    pop eax
    add eax, TH_BEVEL_W + 2
    add ebx, TH_BEVEL_W + 2
    sub ecx, 2 * TH_BEVEL_W + 4
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_FACE
    call wm_drawtitle
    jmp .next
.empty:
    mov byte [gfx_colour], TH_BTN_FACE
    call gfx_fillrect
    mov esi, 1                  ; sunken
    call gfx_bevel
    pop edx
    pop ecx
    pop ebx
    pop eax
.next:
    inc ebp
    jmp .pad
.out:
    popad
.r:
    ret

; ebp = pad -> eax, ebx = x,y; ecx, edx = w,h
; Alone: pads from the left pad margin. On WarpCenter: after the Squirrel
; button so they sit between the menu and the tray clock.
lp_padxy:
    mov eax, ebp
    imul eax, eax, LP_PW + LP_GAP
    cmp byte [wc_live], 0
    jne .onwc
    add eax, LP_PAD
    jmp .xy
.onwc:
    add eax, WPC_BTN_X + WPC_BTN_W + LP_GAP
.xy:
    mov ebx, LP_PAD
    mov ecx, LP_PW
    mov edx, LP_PH
    ret

; ebp = pad -> esi = its name buffer
lp_padname:
    push eax
    mov eax, ebp
    imul eax, eax, LP_NAMEMAX + 1
    lea esi, [lp_names+eax]
    pop eax
    ret

; ---------- hit / drop / launch ----------

; A left-button press on a named pad launches it; a release over a pad
; while an icon drag is armed drops that Program onto the pad.
lp_barhit:
    cmp byte [lp_live], 0
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
    cmp byte [lp_mbtn], 0
    jne .out
    mov byte [lp_mbtn], 1
    call lp_hit                 ; -> ebp = pad, CF clear if hit
    jc .out
    call lp_padname
    cmp byte [esi], 0
    je .out                     ; empty: wait for a drop
    mov eax, ebp
    call lp_launch
    jmp .out
.up:
    mov byte [lp_mbtn], 0
    ; A drag that started on an icon and is released over a pad drops
    ; onto that pad (lp_mbtn may still be 0 — the press was not on a pad).
    cmp dword [pm_drag], -1
    je .out
    call lp_hit
    jc .out
    call lp_drop
.out:
    popad
.r:
    ret

; eax, ebx = pointer -> ebp = pad index, CF clear on a hit
lp_hit:
    cmp ebx, LP_H
    jae .no
    xor ebp, ebp
.i:
    cmp ebp, LP_N
    jae .no
    push eax
    push ebx
    call lp_padxy
    pop ebx
    pop edx                     ; pointer x
    cmp edx, eax
    jb .n
    add eax, ecx
    cmp edx, eax
    jae .n
    cmp ebx, LP_PAD
    jb .n
    cmp ebx, LP_PAD + LP_PH
    jb .yes
.n:
    inc ebp
    jmp .i
.no:
    stc
    ret
.yes:
    clc
    ret

; ebp = pad, pm_drag = icon slot: copy that Program's entry onto the pad
; and save. Cancels the drag so progman does not also move the icon.
lp_drop:
    pushad
    mov [lp_tmp], ebp           ; the pad
    mov edi, [pm_drag]
    cmp edi, -1
    je .r
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    test eax, eax
    jz .r
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .r
    mov ebx, 2                  ; entry
    call obj_get
    test eax, eax
    jz .r
    mov esi, eax
    mov ebp, [lp_tmp]
    call lp_set
    mov dword [pm_drag], -1
    call lp_save
    call wm_redraw
    call ptr_show
.r:
    popad
    ret

; eax = pad index (0..LP_N-1): if the focused group has a Program chosen,
; assign it to the pad; else launch the pad.
lp_digit:
    pushad
    mov [lp_tmp], eax
    call pm_focus
    jc .launch
    cmp dword [pm_gn+ebp*4], 0
    je .launch
    imul edi, ebp, PM_IMAX
    add edi, [pm_gsel+ebp*4]
    mov eax, [pm_gobj+edi*4]
    mov eax, [dk_objs+eax*4]
    test eax, eax
    jz .launch
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .launch
    mov ebx, 2
    call obj_get
    test eax, eax
    jz .launch
    mov esi, eax
    mov ebp, [lp_tmp]
    call lp_set
    call lp_save
    jmp .r
.launch:
    mov eax, [lp_tmp]
    call lp_launch
.r:
    popad
    ret

; ebp = pad, esi = entry name -> the pad holds that name (cut to LP_NAMEMAX)
lp_set:
    pushad
    mov eax, esi                ; name
    call lp_padname             ; -> esi = pad buffer
    mov edi, esi
    mov esi, eax
    mov ecx, LP_NAMEMAX
.c:
    lodsb
    test al, al
    jz .z
    stosb
    loop .c
.z:
    mov byte [edi], 0
    popad
    ret

; eax = pad: send `open` to the Program whose entry matches the pad name.
; When lp_test is set, only checks the name against lp_want and sets lp_ok.
lp_launch:
    pushad
    cmp eax, LP_N
    jae .r
    mov ebp, eax
    call lp_padname
    cmp byte [esi], 0
    je .r
    mov [lp_want], esi
    ; find a Program whose entry matches
    xor ebx, ebx
.i:
    cmp ebx, [dk_n]
    jae .r
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .n
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .n
    push ebx
    mov ebx, 2
    call obj_get
    pop ebx
    test eax, eax
    jz .n
    push ebx
    mov edi, [lp_want]
    mov esi, eax
    call streq
    pop ebx
    jne .n
    ; found
    cmp byte [lp_test], 0
    jne .tested
    mov eax, [dk_objs+ebx*4]
    mov esi, dk_s_open
    call obj_send
    jmp .r
.tested:
    mov byte [lp_ok], 1
    jmp .r
.n:
    inc ebx
    jmp .i
.r:
    popad
    ret

; ---------- persist ----------

; Writes non-empty pads as "N name" lines to /desktop/launchpad.cfg.
lp_save:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, dk_dir
    call fs_mkdir
    mov edi, lp_fbuf
    xor ebp, ebp
.i:
    cmp ebp, LP_N
    jae .write
    call lp_padname
    cmp byte [esi], 0
    je .n
    mov eax, ebp
    call pm_putn
    mov al, ' '
    stosb
    mov eax, esi
    call pm_puts
    mov al, 10
    stosb
.n:
    inc ebp
    jmp .i
.write:
    sub edi, lp_fbuf
    mov [lp_flen], edi
    mov esi, lp_path
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov esi, lp_fbuf
    mov ecx, [lp_flen]
    call fs_write
    call fs_close
.r:
    popad
    ret

; Reads /desktop/launchpad.cfg into the pads (unknown indices skipped).
lp_load:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, lp_path
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov edi, lp_fbuf
    mov ecx, LP_FBUF - 1
    call fs_read
    push eax
    call fs_close
    pop eax
    cmp eax, -1
    je .r
    mov byte [lp_fbuf+eax], 0
    call lp_clear
    mov esi, lp_fbuf
.line:
    cmp byte [esi], 0
    je .r
    cmp byte [esi], 10
    jne .parse
    inc esi
    jmp .line
.parse:
    call pm_getn                ; eax = pad index, esi past the digits
    cmp eax, LP_N
    jae .skipline
    mov ebp, eax
    cmp byte [esi], ' '
    jne .skipline
    inc esi                     ; skip the space; esi -> name
    push esi
    call lp_padname             ; -> esi = pad buffer
    mov edi, esi
    pop esi
    mov ecx, LP_NAMEMAX
.cname:
    lodsb
    test al, al
    jz .zend
    cmp al, 10
    je .zend
    jecxz .cname                ; eat the rest of a too-long name
    stosb
    dec ecx
    jmp .cname
.zend:
    mov byte [edi], 0
    jmp .line
.skipline:
    lodsb
    test al, al
    jz .r
    cmp al, 10
    jne .skipline
    jmp .line
.r:
    popad
    ret

; ---------- self-check ----------

; Assign calc to pad 0, save, clear, load, confirm, launch-check -> wclp: PASS
cmd_wclp_run:
    call wm_screen
    mov esi, lp_fail
    jc .say
    mov byte [lp_ok], 0
    mov byte [lp_stage], '0'
    mov byte [lp_test], 1
    call lp_on
    call dk_mkobjs
    mov byte [lp_stage], '1'
    cmp dword [dk_n], 0
    je .fail
    ; assign "calc" to pad 0
    mov ebp, 0
    mov esi, dk_a1
    call lp_set
    call lp_padname
    mov edi, dk_a1
    call streq
    mov byte [lp_stage], '2'
    jne .fail
    call lp_save
    mov byte [lp_stage], '3'
    call lp_clear
    call lp_padname
    cmp byte [esi], 0
    mov byte [lp_stage], '4'
    jne .fail
    call lp_load
    mov ebp, 0
    call lp_padname
    mov edi, dk_a1
    call streq
    mov byte [lp_stage], '5'
    jne .fail
    ; launch check (test mode: sets lp_ok when entry matches)
    mov byte [lp_ok], 0
    xor eax, eax
    call lp_launch
    mov byte [lp_stage], '6'
    cmp byte [lp_ok], 1
    jne .fail
    ; paint probe: pad 0 face and raised bevel
    call wm_redraw
    mov byte [lp_stage], '7'
    mov ebp, 0
    call lp_padxy
    mov dl, TH_LIGHT            ; raised top-left
    call .probe
    jc .fail
    mov byte [lp_stage], '8'
    add eax, TH_BEVEL_W + 2
    add ebx, TH_BEVEL_W + 2
    mov dl, TH_FACE
    call .probe
    jc .fail
    mov byte [lp_ok], 1
    jmp .end
.fail:
    mov byte [lp_ok], 0
.end:
    call dk_freeobjs
    call lp_off
    mov byte [lp_test], 0
    call gfx_text
    mov esi, lp_pass
    cmp byte [lp_ok], 1
    je .say
    mov esi, lp_fail
.say:
    jmp puts
.probe:                         ; dl = expected at eax,ebx; CF set on mismatch
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

; ---------- data ----------

lp_pass db 'wclp: PASS', 10, 0
lp_fail db 'wclp: FAIL', 10, 0
lp_path db '/desktop/launchpad.cfg', 0
lp_live db 0
lp_ok db 0
lp_test db 0
lp_mbtn db 0
lp_stage db '0'
align 4
lp_top dd 0                     ; added to group window Y in pm_place
lp_tmp dd 0
lp_want dd 0
lp_flen dd 0
lp_names times LP_N * (LP_NAMEMAX + 1) db 0
lp_fbuf times LP_FBUF db 0
