; Squirrel-OS/2 — windows for programs (2.2-progwin)
; Included from pm.asm (high image). Original code.
;
; Syscalls 37-44 let a loaded program open windows, draw in their client
; areas and read window events. The window manager runs in the program's
; own syscalls: SYS_WINEVENT pumps the mouse and keyboard through it while
; it waits. There is no backing store: when part of a program's window has
; to be painted again, the frame and a plain client area are painted and
; the program gets WE_PAINT, and draws again. Drawing is clipped to the
; client area and kept off every window above (gfx_occ). If the screen was
; in text mode, the first window enters the window manager's screen and the
; last one to close goes back to text. See documentation/kernel/windows.md.

WE_KEY      equ 1
WE_DOWN     equ 2
WE_CLOSE    equ 6
WE_PAINT    equ 8

WD_FILL     equ 0
WD_LINE     equ 1
WD_TEXT     equ 2
WD_BLIT     equ 4
WD_BEVEL    equ 5
WD_PIXEL    equ 7

WS_RING     equ 16              ; events per process
WS_EVSIZE   equ 16

; ---------- helpers ----------

; -> eax = the calling process's slot (0..PROC_MAX-1)
ws_slot:
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 6                  ; PCB_SIZE is 64
    ret

; -> eax = the calling process's pid
ws_pid:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    ret

; esi = address, ecx = bytes: CF if a program passed memory not its own.
; Kernel callers (no address space of their own) are trusted.
ws_uchk:
    push eax
    mov eax, [proc_cur]
    cmp dword [eax+PCB_AS], 0
    pop eax
    je .ok
    jmp ua_range
.ok:
    clc
    ret

; esi = string: as ws_uchk for a zero-terminated string
ws_ustr:
    push eax
    mov eax, [proc_cur]
    cmp dword [eax+PCB_AS], 0
    pop eax
    je .ok
    jmp ua_str
.ok:
    clc
    ret

; eax = window id -> edi = its record, CF if it is not open or not the
; caller's.
ws_mine:
    call wm_record
    jc .r
    push eax
    call ws_pid
    cmp [edi+WIN_OWNER], eax
    pop eax
    je .r
    stc
.r:
    ret

; edx = pid, eax = type, ebx = window, ecx = p1, esi = p2: queues an event
; for that process; dropped when its ring is full or there is no such pid.
ws_post:
    pushad
    mov edi, proc_table
    xor ebp, ebp
.f:
    cmp dword [edi+PCB_STATE], 0
    je .n
    cmp [edi+PCB_PID], edx
    je .got
.n:
    add edi, PCB_SIZE
    inc ebp
    cmp ebp, PROC_MAX
    jb .f
    jmp .r
.got:
    mov edx, [ws_cnt+ebp*4]
    cmp edx, WS_RING
    jae .r                      ; full: dropped
    add edx, [ws_head+ebp*4]
    and edx, WS_RING - 1
    shl edx, 4
    imul edi, ebp, WS_RING * WS_EVSIZE
    add edi, ws_ring
    add edi, edx
    mov [edi], eax
    mov [edi+4], ebx
    mov [edi+8], ecx
    mov [edi+12], esi
    inc dword [ws_cnt+ebp*4]
.r:
    popad
    ret

; edi = record of a program window: post WE_PAINT for its whole client
ws_postpaint:
    pushad
    mov edx, [edi+WIN_OWNER]
    cmp edx, -1
    je .r
    mov ebx, edi
    sub ebx, wm_table
    mov eax, ebx
    xor edx, edx
    mov ecx, WIN_SIZE
    div ecx
    mov ebx, eax                ; window id
    mov edx, [edi+WIN_OWNER]
    mov eax, WE_PAINT
    xor ecx, ecx
    mov esi, [edi+WIN_H]
    sub esi, WM_TITLE_H + 2
    shl esi, 16
    mov si, [edi+WIN_W]
    sub si, 2
    call ws_post
.r:
    popad
    ret

; wm_update, and WE_PAINT for every program window an updated area
; touches (all of them when the whole screen is repainted).
ws_update:
    pushad
    mov edi, wm_table
    xor ecx, ecx
.w:
    cmp byte [edi+WIN_USED], 0
    je .next
    cmp dword [edi+WIN_OWNER], -1
    je .next
    cmp dword [edi+WIN_ICONIC], 0
    jne .next
    cmp byte [wm_dfull], 0
    jne .paint
    xor esi, esi                ; any dirty area overlapping it?
.d:
    cmp esi, [wm_dn]
    jae .next
    mov ebx, esi
    shl ebx, 4
    mov eax, [wm_drect+ebx]     ; overlap on x: a < wx + ww and wx < a + aw
    mov edx, [edi+WIN_X]
    add edx, [edi+WIN_W]
    cmp eax, edx
    jge .dn
    add eax, [wm_drect+ebx+8]
    cmp [edi+WIN_X], eax
    jge .dn
    mov eax, [wm_drect+ebx+4]
    mov edx, [edi+WIN_Y]
    add edx, [edi+WIN_H]
    cmp eax, edx
    jge .dn
    add eax, [wm_drect+ebx+12]
    cmp [edi+WIN_Y], eax
    jl .paint
.dn:
    inc esi
    jmp .d
.paint:
    call ws_postpaint
.next:
    add edi, WIN_SIZE
    inc ecx
    cmp ecx, WM_MAX
    jb .w
    call wm_update
    popad
    ret

; Runs the window manager once for whoever waits: mouse changes and keys.
; Clicks in a program's client area and keys for its focused window become
; its events; the close box and Alt+F4 become WE_CLOSE.
ws_pump:
    pushad
    pushfd
    cli
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    mov cl, [mouse_btns]
    popfd
    cmp eax, [ws_lmx]
    jne .mouse
    cmp ebx, [ws_lmy]
    jne .mouse
    cmp cl, [ws_lmb]
    je .keys
.mouse:
    mov [ws_lmx], eax
    mov [ws_lmy], ebx
    mov [ws_lmb], cl
    movzx esi, cl
    call wm_mouse
    call ws_reply               ; esi = buttons for WE_DOWN
.keys:
    cli
    call kbd_dequeue
    sti
    jc .done
    cmp al, 0xB8
    jne .notup
    call wm_altup
.notup:
    call kbd_shift_track
    je .keys
    cmp al, 0x80
    jae .keys
    cmp byte [kbd_alt], 0
    je .plain
    push eax
    call wm_altkey
    jc .altno
    add esp, 4
    call ws_reply
    jmp .keys
.altno:
    pop eax
.plain:
    mov ah, WK_LEFT
    cmp al, 0x4B
    je .wmk
    mov ah, WK_RIGHT
    cmp al, 0x4D
    je .wmk
    call ws_map                 ; al = key as wg_key takes it
    jc .keys
    mov ah, al
    cmp byte [wm_kmode], 0
    jne .wmk
    cmp dword [wm_mn], 0
    je .tofocus
.wmk:
    mov al, ah
    call wm_menukey
    jc .tofocus2
    call ws_reply
    jmp .keys
.tofocus2:
    mov ah, al
.tofocus:                       ; the focused window's program gets it
    mov [ws_key], ah
    call wm_focus
    cmp eax, -1
    je .keys
    mov ebx, eax
    call wm_record
    mov edx, [edi+WIN_OWNER]
    cmp edx, -1
    je .keys
    movzx ecx, byte [ws_key]
    mov eax, WE_KEY
    movzx esi, byte [kbd_shift]
    call ws_post
    jmp .keys
.done:
    cmp dword [wm_dn], 0
    jne .upd
    cmp byte [wm_dfull], 0
    je .ptr
.upd:
    call ws_update
.ptr:
    call ptr_show
    popad
    ret

; eax, ebx, ecx = a window manager reply, esi = buttons: client presses and
; close requests go to the window's program as events.
ws_reply:
    pushad
    cmp eax, WME_CLIENT
    je .client
    cmp eax, WME_CLOSE
    jne .r
    push eax
    mov eax, ebx
    call wm_record
    pop eax
    jc .r
    mov edx, [edi+WIN_OWNER]
    cmp edx, -1
    je .r
    mov eax, WE_CLOSE
    call ws_post
    jmp .r
.client:
    push eax
    mov eax, ebx
    call wm_record
    pop eax
    jc .r
    mov edx, [edi+WIN_OWNER]
    cmp edx, -1
    je .r
    mov eax, WE_DOWN
    call ws_post                ; ecx = x | y << 16, esi = buttons
.r:
    popad
    ret

; al = make code -> al = key as wg_key takes it, CF set if none
ws_map:
    mov ah, 27
    cmp al, 0x01
    je .got
    mov ah, 8
    cmp al, 0x0E
    je .got
    mov ah, WK_UP
    cmp al, 0x48
    je .got
    mov ah, WK_DOWN
    cmp al, 0x50
    je .got
    call kbd_ascii
    mov ah, al
    test al, al
    jnz .got
    stc
    ret
.got:
    mov al, ah
    clc
    ret

; A process ends: close every window it opened (proc_exit).
ws_procgone:
    pushad
    call ws_pid
    mov edx, eax
    call ws_slot
    mov dword [ws_cnt+eax*4], 0 ; and forget its events
    mov dword [ws_head+eax*4], 0
    xor eax, eax
.w:
    push eax
    call wm_record
    jc .n
    cmp [edi+WIN_OWNER], edx
    jne .n
    call ws_close
.n:
    pop eax
    inc eax
    cmp eax, WM_MAX
    jb .w
    popad
    ret

; eax = window id (open): closes it; the last program window to close on
; a screen winsys entered goes back to text mode.
ws_close:
    pushad
    call wm_close
    cmp byte [ws_own], 0
    je .upd
    mov edi, wm_table           ; any program windows left?
    xor ecx, ecx
.w:
    cmp byte [edi+WIN_USED], 0
    je .n
    cmp dword [edi+WIN_OWNER], -1
    jne .upd
.n:
    add edi, WIN_SIZE
    inc ecx
    cmp ecx, WM_MAX
    jb .w
    mov byte [ws_own], 0
    mov dword [wm_dn], 0
    mov byte [wm_dfull], 0
    call gfx_text
    jmp .r
.upd:
    call ws_update
.r:
    popad
    ret

; ---------- the calls ----------

sys_winopen:
    mov esi, ebx
    mov ecx, 24
    call ws_uchk
    jc .bad
    mov esi, [ebx+16]
    call ws_ustr
    jc .bad
    cmp byte [gfx_saved], 0     ; text mode: enter the window manager's screen
    jne .scr
    push ebx
    call wm_screen
    pop ebx
    jc .bad
    mov byte [ws_own], 1
    mov dword [ws_lmx], -1
    call wm_redraw
.scr:
    mov eax, [ebx]
    mov ecx, [ebx+8]
    mov edx, [ebx+12]
    push ebx
    mov ebx, [ebx+4]
    mov esi, ws_untitled
    call wm_create
    pop ebx
    cmp eax, -1
    je .bad
    push eax
    call wm_record
    call ws_pid
    mov [edi+WIN_OWNER], eax
    mov eax, [ebx+20]           ; flags, 0 = the default
    test eax, eax
    jz .flags
    mov [edi+WIN_FLAGS], eax
.flags:
    mov esi, [ebx+16]
    call ws_settitle
    pop eax
    ret
.bad:
    mov eax, -1
    ret

; edi = record, esi = title (already checked): copy it into WIN_TBUF
ws_settitle:
    push ecx
    lea ecx, [edi+WIN_TBUF]
    mov [edi+WIN_TITLE], ecx
    push edi
    lea edi, [edi+WIN_TBUF]
    mov ecx, WM_TBUF - 1
.c:
    lodsb
    test al, al
    jz .z
    stosb
    loop .c
.z:
    mov byte [edi], 0
    pop edi
    call wm_markwin
    pop ecx
    ret

sys_winclose:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    call ws_close
    xor eax, eax
    ret

sys_winmove:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    mov ebx, ecx                ; x | y << 16, 0 keeps
    movsx esi, bx
    sar ebx, 16
    test ecx, ecx
    jnz .xy
    mov esi, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
.xy:
    push edx
    movzx ecx, dx               ; w | h << 16, 0 keeps
    shr edx, 16
    pop ebp
    test ebp, ebp
    jnz .wh
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
.wh:
    push esi                    ; wm_place: eax id, ebx x, ecx y, edx w, esi h
    mov esi, edx
    mov edx, ecx
    mov ecx, ebx
    pop ebx
    call wm_place
    jc sys_winopen.bad
    call ws_update
    xor eax, eax
    ret

sys_wintitle:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    mov esi, ecx
    call ws_ustr
    jc sys_winopen.bad
    call ws_settitle
    xor eax, eax
    ret

; ebx = id, ecx = command: op, x, y, a, b, colour, ptr (dwords)
sys_windraw:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    cmp dword [edi+WIN_ICONIC], 0
    jne .zero                   ; minimised: nothing to draw on
    mov esi, ecx
    mov ecx, 28
    call ws_uchk
    jc sys_winopen.bad
    mov ebp, esi                ; the command
    mov eax, [edi+WIN_X]        ; clip: the client area
    inc eax
    mov ebx, [edi+WIN_Y]
    add ebx, WM_TITLE_H + 1
    mov ecx, [edi+WIN_W]
    sub ecx, 2
    mov edx, [edi+WIN_H]
    sub edx, WM_TITLE_H + 2
    mov [ws_cx], eax
    mov [ws_cy], ebx
    call gfx_setclip
    call ws_occlude             ; and not on the windows above
    mov eax, [ebp]
    cmp eax, WD_PIXEL
    je .pixel
    mov al, [ebp+20]
    mov [gfx_colour], al
    mov eax, [ebp+4]            ; x, y on the screen
    add eax, [ws_cx]
    mov ebx, [ebp+8]
    add ebx, [ws_cy]
    mov ecx, [ebp+12]
    mov edx, [ebp+16]
    mov esi, [ebp]
    cmp esi, WD_FILL
    je .fill
    cmp esi, WD_LINE
    je .line
    cmp esi, WD_TEXT
    je .text
    cmp esi, WD_BEVEL
    je .bevel
    cmp esi, WD_BLIT
    je .blit
    call gfx_noclip
    jmp sys_winopen.bad
.fill:
    call gfx_fillrect
    jmp .done
.line:
    add ecx, [ws_cx]
    add edx, [ws_cy]
    call gfx_line
    jmp .done
.text:
    mov esi, [ebp+24]
    call ws_ustr
    jc .badc
    mov dl, [ebp+12]            ; a = background, -1 = none (drawn as the client)
    cmp dword [ebp+12], -1
    jne .tbg
    mov dl, TH_CLIENT
.tbg:
    mov [gfx_bg], dl
    call gfx_drawstr
    jmp .done
.bevel:
    movzx esi, byte [ebp+20]    ; colour: 0 raised, 1 sunken
    call gfx_bevel
    jmp .done
.blit:                          ; a x b bytes at ptr, colour = transparent or -1
    mov byte [ws_ton], 0
    cmp dword [ebp+20], -1
    je .bt
    mov byte [ws_ton], 1
.bt:
    push ecx
    imul ecx, edx
    mov esi, [ebp+24]
    call ws_uchk
    pop ecx
    jc .badc
    mov [ws_bx], eax
    xor edi, edi                ; row
.brow:
    cmp edi, edx
    jge .done
    push eax
    xor ebp, ebp                ; column; ebp is free now
.bcol:
    cmp ebp, ecx
    jge .bnext
    push ecx
    mov cl, [esi]
    inc esi
    cmp byte [ws_ton], 0
    je .bput
    cmp cl, [gfx_colour]        ; the transparent index
    je .bskip
.bput:
    call gfx_putpixel
.bskip:
    pop ecx
    inc eax
    inc ebp
    jmp .bcol
.bnext:
    pop eax
    inc ebx
    inc edi
    jmp .brow
.pixel:                         ; read back from the visible page
    mov eax, [ebp+4]
    add eax, [ws_cx]
    mov ebx, [ebp+8]
    add ebx, [ws_cy]
    call gfx_noclip
    cmp byte [vbe_dbl], 0
    je .pget
    call vbe_front_getpixel
    movzx eax, cl
    ret
.pget:
    call gfx_getpixel
    movzx eax, cl
    ret
.done:
    call gfx_noclip             ; the client reaches the screen on flush
    xor eax, eax
    ret
.zero:
    xor eax, eax
    ret
.badc:
    call gfx_noclip
    jmp sys_winopen.bad

; edi = a window's record: gfx_occ gets the rectangles of the windows
; above it in the z-order.
ws_occlude:
    pushad
    mov eax, edi
    sub eax, wm_table
    xor edx, edx
    mov ecx, WIN_SIZE
    div ecx                     ; eax = its id
    xor ecx, ecx                ; find it in wm_z
.f:
    cmp ecx, [wm_zn]
    jae .r
    cmp [wm_z+ecx], al
    je .above
    inc ecx
    jmp .f
.above:
    mov esi, gfx_occ
    xor edx, edx
.a:
    inc ecx
    cmp ecx, [wm_zn]
    jae .set
    movzx eax, byte [wm_z+ecx]
    imul edi, eax, WIN_SIZE
    add edi, wm_table
    mov eax, [edi+WIN_X]
    mov [esi], eax
    mov eax, [edi+WIN_Y]
    mov [esi+4], eax
    mov eax, [edi+WIN_W]
    mov [esi+8], eax
    mov eax, [edi+WIN_H]
    mov [esi+12], eax
    add esi, 16
    inc edx
    jmp .a
.set:
    cmp dword [wm_mn], 0        ; an open menu is above everything too
    je .tab
    mov eax, [wm_mx]
    mov [esi], eax
    mov eax, [wm_my]
    mov [esi+4], eax
    mov eax, [wm_mw]
    mov [esi+8], eax
    mov eax, [wm_mh]
    mov [esi+12], eax
    inc edx
.tab:
    mov [gfx_occn], edx
.r:
    popad
    ret

sys_winflush:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    call ws_update              ; the window manager's own changes first
    mov eax, [edi+WIN_X]        ; then the client area to the visible page
    mov ebx, [edi+WIN_Y]
    mov ecx, [edi+WIN_W]
    mov edx, [edi+WIN_H]
    call vbe_dirty
    call vbe_flip
    mov byte [ptr_vis], 0       ; the pointer may have been drawn over
    call ptr_show
    xor eax, eax
    ret

; ebx = 16-byte buffer, ecx = 0 wait / 1 poll
sys_winevent:
    mov esi, ebx
    push ecx
    mov ecx, WS_EVSIZE
    call ws_uchk
    pop ecx
    jc sys_winopen.bad
    mov edi, ebx
.again:
    cmp byte [gfx_saved], 0     ; on a graphics screen: run the window manager
    je .look
    call ws_pump
.look:
    call ws_slot
    cmp dword [ws_cnt+eax*4], 0
    jne .take
    test ecx, ecx
    jnz sys_winopen.bad         ; poll: nothing
    push ecx
    push edi
    call proc_idle
    pop edi
    pop ecx
    jmp .again
.take:
    mov edx, eax
    imul esi, edx, WS_RING * WS_EVSIZE
    add esi, ws_ring
    mov eax, [ws_head+edx*4]
    shl eax, 4
    add esi, eax
    mov ecx, 4
    rep movsd
    inc dword [ws_head+edx*4]
    and dword [ws_head+edx*4], WS_RING - 1
    dec dword [ws_cnt+edx*4]
    xor eax, eax
    ret

; ebx = id or -1 (the screen), ecx = 16-byte buffer: x, y, w, h of the
; client area on the screen (the screen: 0, 0, width, height)
sys_wininfo:
    mov esi, ecx
    push ecx
    mov ecx, 16
    call ws_uchk
    pop esi
    jc sys_winopen.bad
    cmp ebx, -1
    jne .win
    mov dword [esi], 0
    mov dword [esi+4], 0
    mov eax, [gfx_width]
    mov [esi+8], eax
    mov eax, [gfx_height]
    mov [esi+12], eax
    xor eax, eax
    ret
.win:
    mov eax, ebx
    call ws_mine
    jc sys_winopen.bad
    mov eax, [edi+WIN_X]
    inc eax
    mov [esi], eax
    mov eax, [edi+WIN_Y]
    add eax, WM_TITLE_H + 1
    mov [esi+4], eax
    mov eax, [edi+WIN_W]
    sub eax, 2
    mov [esi+8], eax
    mov eax, [edi+WIN_H]
    sub eax, WM_TITLE_H + 2
    mov [esi+12], eax
    xor eax, eax
    ret

ws_untitled db 0

align 4
ws_cx dd 0
ws_cy dd 0
ws_bx dd 0
ws_lmx dd -1
ws_lmy dd -1
ws_head times PROC_MAX dd 0
ws_cnt times PROC_MAX dd 0
ws_ring times PROC_MAX * WS_RING * WS_EVSIZE db 0
ws_lmb db 0
ws_key db 0
ws_own db 0                     ; 1: winsys entered the graphics screen
ws_ton db 0                     ; WD_BLIT: a transparent colour is set
