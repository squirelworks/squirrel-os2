; Squirrel-OS/2 — Control Panel v1 (2.3-control). Original code.
;
; control: one window with eight rows. Colours (a scheme: desktop, focused
; and idle title bars), mouse (double-click time, button swap, speed),
; keyboard (repeat rate and delay, sent to the keyboard with command 0xF3)
; and the date and time (read from and written to the CMOS clock). Up and
; down choose a row, left and right change it; Enter on the date or time
; row asks for a new one. Esc (or the close box) saves the settings to
; /desktop/control.cfg, one "name value" line each, and quits.
; cp_boot reads that file at boot and applies it.
; "control show" prints the settings; "control NAME VALUE" sets one and
; saves (NAME: scheme dblclick swap speed rate delay date time).
; cptest checks the parts and prints cp: PASS.
; See documentation/apps/control.md.

CP_ROWS     equ 8
CP_ROW      equ 11              ; a row's height, as the File Manager's
CP_VALX     equ 96              ; the value column, from the client's left
CP_INMAX    equ 10              ; characters typed for a date or time
CP_FBUF     equ 160

CPR_SCHEME  equ 0
CPR_DBL     equ 1
CPR_SWAP    equ 2
CPR_SPEED   equ 3
CPR_RATE    equ 4
CPR_DELAY   equ 5
CPR_DATE    equ 6
CPR_TIME    equ 7

CP_NSCHEME  equ 4

; ---------- applying ----------

; Copies the scheme's colours to th_desk, th_bar, th_bar_idle and sends
; the repeat rate and delay to the keyboard.
cp_apply:
    pushad
    mov eax, [cp_scheme]
    lea esi, [cp_schemes+eax*4]
    mov al, [esi]
    mov [th_desk], al
    mov al, [esi+1]
    mov [th_bar], al
    mov al, [esi+2]
    mov [th_bar_idle], al
    call cp_kbd
    popad
    ret

; Sends 0xF3 and (delay << 5 | rate) to the keyboard; cp_kack = 1 when it
; acknowledged both bytes. Interrupts are off while the replies are read.
cp_kbd:
    pushad
    pushfd
    cli
    mov byte [cp_kack], 0
    mov al, 0xF3
    call cp_kbdbyte
    jc .r
    mov eax, [cp_delay]
    shl eax, 5
    or eax, [cp_rate]
    call cp_kbdbyte
    jc .r
    mov byte [cp_kack], 1
.r:
    popfd
    popad
    ret

; al = a byte for the keyboard -> CF clear when it answered 0xFA. A mouse
; byte that turns up first goes to mouse_byte.
cp_kbdbyte:
    push ecx
    push eax
    call mouse_wait_in
    pop eax
    out 0x60, al
    mov ecx, 8                  ; a few mouse bytes may come first
.next:
    call mouse_wait_out
    in al, 0x64
    test al, 1
    jz .no
    test al, 0x20
    jz .kbd
    in al, 0x60
    test byte [mouse_up], 1
    jz .skip
    call mouse_byte
.skip:
    loop .next
    jmp .no
.kbd:
    in al, 0x60
    cmp al, 0xFA
    jne .no
    pop ecx
    clc
    ret
.no:
    pop ecx
    stc
    ret

; mouse_byte's motion (eax = dx, ebx = dy) scaled by cp_speed: 1 halves
; it, 2 keeps it, 3 doubles it.
cp_mspeed:
    cmp dword [cp_speed], 2
    je .r
    jb .slow
    add eax, eax
    add ebx, ebx
    ret
.slow:
    sar eax, 1
    sar ebx, 1
.r:
    ret

; al = button bits (1 left, 2 right) -> swapped when cp_swap is set.
cp_mswap:
    cmp dword [cp_swap], 0
    je .r
    push ebx
    mov bl, al
    and al, 0xFC
    test bl, 1
    jz .l
    or al, 2
.l:
    test bl, 2
    jz .rr
    or al, 1
.rr:
    pop ebx
.r:
    ret

; ---------- the settings file ----------

; At boot, after the data disk is mounted: the saved settings, then apply.
cp_boot:
    call cp_load
    jmp cp_apply

; Reads /desktop/control.cfg, if there is one. Unknown names and values
; out of range are left as they are.
cp_load:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, cp_path
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov edi, cp_fbuf
    mov ecx, CP_FBUF - 1
    call fs_read
    push eax
    call fs_close
    pop eax
    cmp eax, -1
    je .r
    mov byte [cp_fbuf+eax], 0
    call cp_parse
.r:
    popad
    ret

; cp_fbuf = "name value" lines, zero-terminated -> each one set (cp_set)
cp_parse:
    pushad
    mov esi, cp_fbuf
.line:
    cmp byte [esi], 0
    je .r
    mov edi, cp_word            ; the name, up to a space
    mov ecx, 15
.n:
    lodsb
    test al, al
    jz .r
    cmp al, 10
    je .line
    cmp al, ' '
    je .nd
    jecxz .n
    stosb
    dec ecx
    jmp .n
.nd:
    mov byte [edi], 0
    call pm_getn                ; (progman.asm)
    push esi
    mov esi, cp_word
    call cp_set
    pop esi
.eol:
    lodsb
    test al, al
    jz .r
    cmp al, 10
    jne .eol
    jmp .line
.r:
    popad
    ret

; esi = a name, eax = a value -> the setting changed, CF clear; CF set if
; there is no such name or the value is out of its range.
cp_set:
    pushad
    mov ebx, cp_keys
.k:
    mov edi, [ebx]
    test edi, edi
    jz .no
    push eax
    call streq
    pop eax
    je .found
    add ebx, 16
    jmp .k
.found:
    cmp eax, [ebx+8]
    jl .no
    cmp eax, [ebx+12]
    jg .no
    mov edi, [ebx+4]
    mov [edi], eax
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; Writes every setting to /desktop/control.cfg. -> CF set if it could not.
cp_save:
    pushad
    cmp byte [fs_mounted], 0
    je .no
    mov esi, dk_dir
    call fs_mkdir               ; (already there: fine)
    mov edi, cp_fbuf
    mov ebx, cp_keys
.k:
    mov esi, [ebx]
    test esi, esi
    jz .write
.c:
    lodsb
    test al, al
    jz .cd
    stosb
    jmp .c
.cd:
    mov al, ' '
    stosb
    mov eax, [ebx+4]
    mov eax, [eax]
    call pm_putn
    mov al, 10
    stosb
    add ebx, 16
    jmp .k
.write:
    sub edi, cp_fbuf
    mov [cp_flen], edi
    mov esi, cp_path
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .no
    mov ebx, eax
    mov esi, cp_fbuf
    mov ecx, [cp_flen]
    call fs_write
    push eax
    call fs_close
    pop eax
    cmp eax, [cp_flen]
    jne .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ---------- the clock ----------

; eax = hours << 16 | minutes << 8 | seconds -> the CMOS clock is set.
cp_settime:
    pushad
    mov esi, gui_rtc_time
    jmp cp_setrtc

; eax = year << 16 | month << 8 | day -> the CMOS clock is set (and the
; century register).
cp_setdate:
    pushad
    push eax
    shr eax, 16
    xor edx, edx
    mov ecx, 100
    div ecx                     ; eax = century, edx = year in it
    push edx
    mov ah, al
    mov al, 0x32
    call cp_cmos
    pop edx
    pop eax
    and eax, 0xFFFF
    shl edx, 16
    or eax, edx
    mov esi, gui_rtc_date
; esi = three register numbers, eax = their values, high byte first
cp_setrtc:
    mov ebx, eax
    shl ebx, 8                  ; the first value to the top byte
    pushfd
    cli
    mov al, 0x0B                ; stop the updates while it is set
    out 0x70, al
    in al, 0x71
    mov [cp_regb], al
    or al, 0x80
    mov ah, al
    mov al, 0x0B
    call cp_cmos0
    mov ecx, 3
.reg:
    rol ebx, 8                  ; the next value is in bl
    mov ah, bl
    lodsb
    call cp_cmos0
    loop .reg
    mov ah, [cp_regb]
    and ah, 0x7F
    mov al, 0x0B
    call cp_cmos0
    popfd
    popad
    ret

; al = register, ah = a binary value -> written (as BCD when the clock
; counts in BCD)
cp_cmos:
    pushfd
    cli
    call cp_cmos0
    popfd
    ret
cp_cmos0:
    push eax
    push ecx
    mov cl, al
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    cmp cl, 0x0B
    je .bin                     ; register B itself: as it is
    test al, 4
    jnz .bin
    movzx eax, ah               ; binary -> BCD
    push edx
    xor edx, edx
    push ecx
    mov ecx, 10
    div ecx
    pop ecx
    shl eax, 4
    or eax, edx
    pop edx
    mov ah, al
.bin:
    mov al, cl
    out 0x70, al
    mov al, ah
    out 0x71, al
    pop ecx
    pop eax
    ret

; esi = "HH:MM:SS" -> eax = h << 16 | m << 8 | s, CF set if it is not a time
cp_ptime:
    push ebx
    push ecx
    push edx
    xor edx, edx
    mov ecx, 3
    mov ebx, cp_tmax
.f:
    call cp_digits2
    jc .bad
    cmp al, [ebx]
    ja .bad
    inc ebx
    shl edx, 8
    or dl, al
    dec ecx
    jz .end
    cmp byte [esi], ':'
    jne .bad
    inc esi
    jmp .f
.end:
    cmp byte [esi], 0
    jne .bad
    mov eax, edx
    clc
    jmp .r
.bad:
    stc
.r:
    pop edx
    pop ecx
    pop ebx
    ret

; esi = "YYYY-MM-DD" -> eax = year << 16 | month << 8 | day, CF set if it
; is not a date (years 1980..2099)
cp_pdate:
    push ebx
    push edx
    call cp_digits2
    jc .bad
    movzx edx, al
    imul edx, edx, 100
    call cp_digits2
    jc .bad
    movzx eax, al
    add edx, eax
    cmp edx, 1980
    jb .bad
    cmp edx, 2099
    ja .bad
    shl edx, 16
    cmp byte [esi], '-'
    jne .bad
    inc esi
    call cp_digits2
    jc .bad
    cmp al, 1
    jb .bad
    cmp al, 12
    ja .bad
    mov dh, al
    cmp byte [esi], '-'
    jne .bad
    inc esi
    call cp_digits2
    jc .bad
    cmp al, 1
    jb .bad
    cmp al, 31
    ja .bad
    mov dl, al
    cmp byte [esi], 0
    jne .bad
    mov eax, edx
    clc
    jmp .r
.bad:
    stc
.r:
    pop edx
    pop ebx
    ret

; esi -> eax = the two digits there as a number, esi past them; CF if not
cp_digits2:
    push ecx
    movzx eax, byte [esi]
    sub eax, '0'
    cmp eax, 9
    ja .bad
    movzx ecx, byte [esi+1]
    sub ecx, '0'
    cmp ecx, 9
    ja .bad
    imul eax, eax, 10
    add eax, ecx
    add esi, 2
    pop ecx
    clc
    ret
.bad:
    pop ecx
    stc
    ret

; eax = a packed time -> "HH:MM:SS" at edi, edi at the zero after it
cp_ftime:
    push eax
    shr eax, 16
    call cp_put2
    mov byte [edi], ':'
    inc edi
    mov eax, [esp]
    shr eax, 8
    call cp_put2
    mov byte [edi], ':'
    inc edi
    mov eax, [esp]
    call cp_put2
    mov byte [edi], 0
    pop eax
    ret

; eax = a packed date -> "YYYY-MM-DD" at edi, edi at the zero after it
cp_fdate:
    push ecx
    push edx
    push eax
    shr eax, 16
    xor edx, edx
    mov ecx, 100
    div ecx
    call cp_put2                ; the century
    mov eax, edx
    call cp_put2
    mov byte [edi], '-'
    inc edi
    mov eax, [esp]
    shr eax, 8
    call cp_put2
    mov byte [edi], '-'
    inc edi
    mov eax, [esp]
    call cp_put2
    mov byte [edi], 0
    pop eax
    pop edx
    pop ecx
    ret

; al = 0..99 -> two digits at edi
cp_put2:
    push eax
    push edx
    movzx eax, al
    mov dl, 10
    div dl
    add ax, '00'
    stosw
    pop edx
    pop eax
    ret

; ---------- the shell command ----------

; "control show" or "control NAME VALUE" (esi after "control ")
cmd_control_arg:
    call next_word
    push edi
    mov edi, cp_m_show
    call streq
    pop edi
    je cp_show
    mov [cp_argname], esi
    mov esi, edi
    call next_word              ; the value
    mov ebx, esi
    mov esi, [cp_argname]
    mov edi, cp_k_time
    call streq
    je .time
    mov edi, cp_k_date
    call streq
    je .date
    push esi
    mov esi, ebx
    call cp_num
    pop esi
    jc .bad
    call cp_set
    jc .bad
    call cp_apply
    jmp .save
.time:
    mov esi, ebx
    call cp_ptime
    jc .bad
    call cp_settime
    jmp cp_show
.date:
    mov esi, ebx
    call cp_pdate
    jc .bad
    call cp_setdate
    jmp cp_show
.save:
    call cp_save
    jc .nosave
    jmp cp_show
.nosave:
    mov esi, cp_m_nosave
    jmp puts
.bad:
    mov esi, cp_m_bad
    jmp puts

; esi = digits -> eax = the number, CF if there are none or more follows
cp_num:
    cmp byte [esi], '0'
    jb .bad
    cmp byte [esi], '9'
    ja .bad
    call pm_getn
    cmp byte [esi], 0
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; Prints the settings, the keyboard's answer and the clock.
cp_show:
    mov edi, cp_line
    call cp_fsettings
    mov esi, cp_line
    call puts
    mov edi, cp_line
    mov esi, cp_m_date
    call fm_cat
    call gui_date
    call cp_fdate
    mov esi, cp_m_time
    call fm_cat
    call gui_time
    call cp_ftime
    mov al, 10
    stosb
    mov byte [edi], 0
    mov esi, cp_line
    jmp puts

; edi -> "control: scheme N NAME, dblclick N, ..., keyboard ok|no answer\n"
cp_fsettings:
    mov esi, cp_m_head
    call fm_cat
    mov ebx, cp_keys
.k:
    mov esi, [ebx]
    call fm_cat
    mov al, ' '
    stosb
    mov eax, [ebx+4]
    mov eax, [eax]
    call pm_putn
    cmp ebx, cp_keys            ; the scheme's name after its number
    jne .comma
    mov al, ' '
    stosb
    mov eax, [cp_scheme]
    mov esi, [cp_snames+eax*4]
    call fm_cat
.comma:
    mov al, ','
    stosb
    mov al, ' '
    stosb
    add ebx, 16
    cmp dword [ebx], 0
    jne .k
    mov esi, cp_m_kok
    cmp byte [cp_kack], 0
    jne .kb
    mov esi, cp_m_kno
.kb:
    call fm_cat
    mov al, 10
    stosb
    mov byte [edi], 0
    ret

; ---------- the window ----------

cmd_control_run:
    call wm_screen
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    mov dword [cp_sel], 0
    mov byte [cp_edit], 0
    mov byte [cp_changed], 0
    mov dword [cp_stat], cp_s_help
    mov eax, [ticks]
    mov [cp_tick], eax
    cmp dword [gfx_width], 640
    jb .small
    mov eax, 150
    mov ebx, 100
    mov ecx, 340
    mov edx, 124
    jmp .win
.small:
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
.win:
    mov esi, cp_title
    call wm_create
    mov [cp_win], eax
    cmp eax, -1
    je .quit
    mov [dk_win], eax           ; Alt+F4 / Close quit (dk_wmreply)
    imul edi, eax, WIN_SIZE
    mov dword [wm_table+edi+WIN_PAINT], cp_paint
    mov byte [dk_quit], 0
.draw:
    call wm_redraw
    call ptr_show
.key:
    call mouse_poll
    call cp_wm                  ; CF: quit
    jc .quit
    call ptr_show
    mov eax, [ticks]            ; the clock moves on: once a second
    sub eax, [cp_tick]
    cmp eax, 100
    jb .k
    add [cp_tick], eax
    cmp byte [cp_edit], 0
    je .draw
.k:
    cmp byte [cp_dirty], 0
    je .k2
    mov byte [cp_dirty], 0
    jmp .draw
.k2:
    call dk_trykey
    jc .menu
    cmp byte [dk_quit], 0
    jne .quit
    cmp byte [cp_edit], 0
    jne .edit
    cmp al, 27
    je .quit
    call cp_key
    jmp .draw
.edit:
    call cp_ekey
    jmp .draw
.menu:
    mov dword [dk_menu], 0
    jmp .key
.quit:
    mov eax, [cp_win]
    cmp eax, -1
    je .gone
    call wm_close
.gone:
    call gfx_text
    mov esi, cp_bye
    cmp byte [cp_changed], 0
    je .say
    call cp_save
    mov esi, cp_saved
    jnc .say
    mov esi, cp_m_nosave
.say:
    jmp puts

; al = a key (not while typing a date or time)
cp_key:
    pushad
    mov ebx, [cp_sel]
    cmp al, WK_UP
    je .up
    cmp al, WK_DOWN
    je .down
    mov edx, 1
    cmp al, WK_RIGHT
    je .change
    cmp al, '+'
    je .change
    mov edx, -1
    cmp al, WK_LEFT
    je .change
    cmp al, '-'
    je .change
    cmp al, 10                  ; Enter
    je .enter
    jmp .r
.up:
    test ebx, ebx
    jz .r
    dec dword [cp_sel]
    jmp .r
.down:
    cmp ebx, CP_ROWS - 1
    jae .r
    inc dword [cp_sel]
    jmp .r
.enter:
    cmp ebx, CPR_DATE
    jb .r
    call cp_ask
    jmp .r
.change:
    cmp ebx, CPR_DATE
    jae .r
    call cp_step
.r:
    popad
    ret

; ebx = a setting's row, edx = +1 or -1 -> the next value (wrapping),
; applied at once and saved when the panel closes
cp_step:
    pushad
    shl ebx, 4
    add ebx, cp_keys
    mov edi, [ebx+4]
    mov eax, [edi]
    mov ecx, edx
    cmp ebx, cp_keys + CPR_DBL * 16
    jne .one
    imul ecx, ecx, 10           ; double-click time: steps of 10 ticks
.one:
    add eax, ecx
    cmp eax, [ebx+8]
    jge .lo
    mov eax, [ebx+12]
.lo:
    cmp eax, [ebx+12]
    jle .hi
    mov eax, [ebx+8]
.hi:
    mov [edi], eax
    mov byte [cp_changed], 1
    call cp_apply
    popad
    ret

; Starts typing a date or time on the status line.
cp_ask:
    mov byte [cp_edit], 1
    mov byte [cp_in], 0
    mov dword [cp_inlen], 0
    mov dword [cp_stat], 0
    ret

; al = a key while typing: digits, '-' and ':', Backspace, Enter, Esc
cp_ekey:
    pushad
    cmp al, 27
    je .stop
    cmp al, 8
    je .back
    cmp al, 10                  ; Enter
    je .enter
    cmp al, '-'
    je .add
    cmp al, ':'
    je .add
    cmp al, '0'
    jb .r
    cmp al, '9'
    ja .r
.add:
    mov ecx, [cp_inlen]
    cmp ecx, CP_INMAX
    jae .r
    mov [cp_in+ecx], al
    mov byte [cp_in+ecx+1], 0
    inc dword [cp_inlen]
    jmp .r
.back:
    mov ecx, [cp_inlen]
    jecxz .r
    dec ecx
    mov [cp_inlen], ecx
    mov byte [cp_in+ecx], 0
    jmp .r
.enter:
    mov esi, cp_in
    cmp dword [cp_sel], CPR_TIME
    je .time
    call cp_pdate
    jc .bad
    call cp_setdate
    jmp .done
.time:
    call cp_ptime
    jc .bad
    call cp_settime
.done:
    mov dword [cp_stat], cp_s_set
    jmp .end
.bad:
    mov dword [cp_stat], cp_s_bad
    jmp .end
.stop:
    mov dword [cp_stat], cp_s_help
.end:
    mov byte [cp_edit], 0
.r:
    popad
    ret

; wm_draw's WIN_PAINT: edi = the record, eax..edx = the client area
cp_paint:
    pushad
    mov [cp_cx], eax
    mov [cp_cy], ebx
    mov [cp_cw], ecx
    mov [cp_ch], edx
    call pm_clipin
    xor ebp, ebp
.row:
    cmp ebp, CP_ROWS
    jae .stat
    call cp_rowtext             ; -> cp_line = the value
    mov eax, [cp_cx]
    add eax, 4
    imul ebx, ebp, CP_ROW
    add ebx, [cp_cy]
    add ebx, 4
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_CLIENT
    cmp ebp, [cp_sel]
    jne .plain
    mov byte [gfx_colour], TH_SELECT
    push eax
    push ebx
    dec eax
    dec ebx
    mov ecx, [cp_cw]
    sub ecx, 6
    mov edx, CP_ROW
    call gfx_fillrect
    pop ebx
    pop eax
    mov byte [gfx_colour], TH_SELECT_TEXT
    mov byte [gfx_bg], TH_SELECT
.plain:
    mov esi, [cp_rnames+ebp*4]
    mov ecx, CP_VALX - 6
    call wm_drawtitle
    add eax, CP_VALX - 4
    mov ecx, [cp_cw]
    sub ecx, CP_VALX + 6
    mov esi, cp_line
    call wm_drawtitle
    inc ebp
    jmp .row
.stat:
    mov eax, [cp_cx]
    add eax, 4
    mov ebx, [cp_cy]
    add ebx, [cp_ch]
    sub ebx, CP_ROW + 2
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_CLIENT
    mov esi, [cp_stat]
    test esi, esi
    jnz .say
    mov edi, cp_line            ; the question, what was typed, a cursor
    mov esi, cp_s_date
    cmp dword [cp_sel], CPR_TIME
    jne .q
    mov esi, cp_s_time
.q:
    call fm_cat
    mov esi, cp_in
    call fm_cat
    mov byte [edi], '_'
    mov byte [edi+1], 0
    mov esi, cp_line
.say:
    mov ecx, [cp_cw]
    sub ecx, 8
    call wm_drawtitle
    call pm_clipout
    popad
    ret

; ebp = a row -> cp_line = its value as text
cp_rowtext:
    pushad
    mov edi, cp_line
    cmp ebp, CPR_DATE
    je .date
    cmp ebp, CPR_TIME
    je .time
    mov ebx, ebp
    shl ebx, 4
    mov eax, [cp_keys+ebx+4]
    mov eax, [eax]
    cmp ebp, CPR_SCHEME
    je .scheme
    cmp ebp, CPR_SWAP
    je .swap
    cmp ebp, CPR_SPEED
    je .speed
    cmp ebp, CPR_DELAY
    je .delay
    call pm_putn                ; double-click ticks, repeat rate
    mov esi, cp_u_ticks
    cmp ebp, CPR_DBL
    je .unit
    mov esi, cp_u_rate
.unit:
    call fm_cat
    jmp .r
.scheme:
    mov esi, [cp_snames+eax*4]
    jmp .name
.swap:
    mov esi, [cp_yesno+eax*4]
    jmp .name
.speed:
    mov esi, [cp_speeds+eax*4-4]
    jmp .name
.delay:
    inc eax
    imul eax, eax, 250
    call pm_putn
    mov esi, cp_u_ms
.name:
    call fm_cat
    jmp .r
.date:
    call gui_date
    call cp_fdate
    jmp .r
.time:
    call gui_time
    call cp_ftime
.r:
    mov byte [edi], 0
    popad
    ret

; The mouse to the window manager; a press on a row chooses it, a press
; on the chosen row's value changes it (as Right), or asks for the date
; or time. CF set: quit (the close box).
cp_wm:
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
    mov dl, [cp_lbtn]
    mov [dk_lmb], cl
    mov [cp_lbtn], cl
    test cl, 1
    jz .move                    ; only a press of the left button acts
    test dl, 1
    jnz .move
    call wm_mouse
    cmp eax, WME_CLOSE
    jne .client
    cmp ebx, [cp_win]
    je .quit
    jmp .upd
.client:
    cmp eax, WME_CLIENT
    jne .upd
    cmp byte [cp_edit], 0
    jne .upd
    mov eax, [dk_lmy]
    sub eax, [cp_cy]
    sub eax, 3
    js .upd
    xor edx, edx
    mov ecx, CP_ROW
    div ecx
    cmp eax, CP_ROWS
    jae .upd
    mov byte [cp_dirty], 1
    mov ebx, eax
    cmp eax, [cp_sel]
    mov [cp_sel], eax
    jne .upd
    mov eax, [dk_lmx]           ; the chosen row again: on the value?
    sub eax, [cp_cx]
    cmp eax, CP_VALX
    jb .upd
    cmp ebx, CPR_DATE
    jae .ask
    mov edx, 1
    call cp_step
    jmp .upd
.ask:
    call cp_ask
    jmp .upd
.move:
    call wm_mouse
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

; ---------- self-check ----------

; cptest: parsing and formatting, the clock set and read back, the scheme
; on the screen, button swap and speed on made-up mouse packets, the
; keyboard's answer, and a settings line read back by cp_load's parser.
; Every setting is put back as it was. Prints cp: PASS or cp: FAIL at N.
cmd_cptest_run:
    pushad
    mov esi, cp_keys            ; keep the settings
    mov edi, cp_keep
    mov ecx, 6
.keep:
    mov eax, [esi+4]
    mov eax, [eax]
    stosd
    add esi, 16
    loop .keep
    mov dword [cp_tn], 0
    mov eax, [cp_scheme]        ; 0: the live colours are the saved scheme's
    mov al, [cp_schemes+eax*4]
    cmp al, [th_desk]
    jne .fail
    mov dword [cp_tn], 1
    ; 1: a time and a date parse and print back
    mov esi, cp_t_time
    call cp_ptime
    jc .fail
    cmp eax, (23 << 16) | (59 << 8) | 58
    jne .fail
    mov edi, cp_line
    call cp_ftime
    mov esi, cp_t_time
    mov edi, cp_line
    call streq
    jne .fail
    inc dword [cp_tn]           ; 2
    mov esi, cp_t_date
    call cp_pdate
    jc .fail
    cmp eax, (2031 << 16) | (2 << 8) | 28
    jne .fail
    mov edi, cp_line
    call cp_fdate
    mov esi, cp_t_date
    mov edi, cp_line
    call streq
    jne .fail
    inc dword [cp_tn]           ; 3: nonsense is refused
    mov esi, cp_t_badt
    call cp_ptime
    jnc .fail
    mov esi, cp_t_badd
    call cp_pdate
    jnc .fail
    inc dword [cp_tn]           ; 4: the clock, set and read back
    call gui_date
    mov [cp_kd], eax
    call gui_time
    mov [cp_kt], eax
    mov eax, (2031 << 16) | (2 << 8) | 28
    call cp_setdate
    call gui_date
    cmp eax, (2031 << 16) | (2 << 8) | 28
    jne .fail
    mov eax, (10 << 16) | (20 << 8) | 0
    call cp_settime
    call gui_time
    and eax, 0xFFFF00           ; (a second may pass)
    cmp eax, (10 << 16) | (20 << 8)
    jne .fail
    mov eax, [cp_kd]
    call cp_setdate
    mov eax, [cp_kt]
    call cp_settime
    inc dword [cp_tn]           ; 5: settings by name, range checked
    mov esi, cp_k_speed
    mov eax, 4
    call cp_set
    jnc .fail
    mov esi, cp_t_nokey
    mov eax, 1
    call cp_set
    jnc .fail
    mov esi, cp_k_scheme
    mov eax, 2
    call cp_set
    jc .fail
    call cp_apply
    mov al, [cp_schemes+2*4]
    cmp al, [th_desk]
    jne .fail
    inc dword [cp_tn]           ; 6: the desktop is drawn in it
    call gfx_mode13
    jc .fail
    call wm_redraw
    mov eax, 100
    mov ebx, GFX_SAFE_Y + 10    ; (below the text's font, graphics.md)
    call gfx_getpixel
    push ecx
    call gfx_text
    pop ecx
    cmp cl, [cp_schemes+2*4]
    jne .fail
    inc dword [cp_tn]           ; 7: swapped buttons
    mov dword [cp_swap], 1
    mov esi, cp_t_pkt_l         ; a left press, no motion
    call cp_tpkt
    cmp byte [mouse_btns], 2
    jne .fail
    mov dword [cp_swap], 0
    mov esi, cp_t_pkt_0
    call cp_tpkt
    inc dword [cp_tn]           ; 8: speed 3 doubles a move, 1 halves it
    push dword [mouse_x]
    mov dword [cp_speed], 3
    mov dword [mouse_x], 100
    mov esi, cp_t_pkt_x
    call cp_tpkt
    mov ecx, [mouse_x]
    mov dword [cp_speed], 1
    mov dword [mouse_x], 100
    call cp_tpkt
    mov edx, [mouse_x]
    pop dword [mouse_x]
    cmp ecx, 108                ; the packet moves 4 to the right
    jne .fail
    cmp edx, 102
    jne .fail
    inc dword [cp_tn]           ; 9: the keyboard takes a repeat rate
    mov dword [cp_rate], 0x1F
    mov dword [cp_delay], 3
    call cp_kbd
    cmp byte [cp_kack], 1
    jne .fail
    inc dword [cp_tn]           ; 10: a settings text read back
    mov esi, cp_t_cfg
    mov edi, cp_fbuf
    mov ecx, cp_t_cfglen
    rep movsb
    call cp_parse
    cmp dword [cp_scheme], 3
    jne .fail
    cmp dword [cp_dbl], 70
    jne .fail
    cmp dword [cp_speed], 1     ; 9 is out of range: left as it was
    jne .fail
    call cp_restore
    mov esi, cp_m_pass
    call puts
    popad
    ret
.fail:
    call cp_restore
    mov esi, cp_m_fail
    call puts
    mov eax, [cp_tn]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    popad
    ret

cp_restore:
    pushad
    mov esi, cp_keep
    mov ebx, cp_keys
    mov ecx, 6
.r:
    lodsd
    mov edi, [ebx+4]
    mov [edi], eax
    add ebx, 16
    loop .r
    call cp_apply
    popad
    ret

; esi = three packet bytes -> through mouse_byte, as from the mouse
cp_tpkt:
    pushad
    pushfd
    cli
    mov byte [mouse_pkt_n], 0
    mov ecx, 3
.b:
    lodsb
    call mouse_byte
    loop .b
    popfd
    popad
    ret

; ---------- data ----------

; colour schemes: desktop, focused title bar, idle title bar, (spare)
cp_schemes:
    db TH_DESKTOP, TH_TITLE, TH_TITLE_IDLE, 0   ; Warp
    db 0x02, 0x14, 0x38, 0                      ; Forest: green, brown
    db 0x05, 0x04, 0x38, 0                      ; Plum: magenta, red
    db 0x38, 0x01, 0x00, 0                      ; Slate: dark grey, blue
cp_snames dd cp_n_warp, cp_n_forest, cp_n_plum, cp_n_slate
cp_n_warp db 'Warp', 0
cp_n_forest db 'Forest', 0
cp_n_plum db 'Plum', 0
cp_n_slate db 'Slate', 0

; the live colours wm_paint draws with (2.3-control)
th_desk db TH_DESKTOP
th_bar db TH_TITLE
th_bar_idle db TH_TITLE_IDLE
cp_kack db 0                    ; 1: the keyboard took the repeat rate
cp_regb db 0
cp_edit db 0
cp_changed db 0
cp_dirty db 0
cp_lbtn db 0
cp_tmax db 23, 59, 59
align 4
; the settings, in the order of the file and of the panel's rows
cp_scheme dd 0
cp_dbl dd PM_DBL                ; ticks between the presses of a double-click
cp_swap dd 0
cp_speed dd 2
cp_rate dd 11                   ; 0 fastest (30 a second) .. 31 slowest (2)
cp_delay dd 1                   ; (delay + 1) * 250 ms
; name, the setting, lowest, highest
cp_keys:
    dd cp_k_scheme, cp_scheme, 0, CP_NSCHEME - 1
    dd cp_k_dbl, cp_dbl, 10, 200
    dd cp_k_swap, cp_swap, 0, 1
    dd cp_k_speed, cp_speed, 1, 3
    dd cp_k_rate, cp_rate, 0, 31
    dd cp_k_delay, cp_delay, 0, 3
    dd 0
cp_keep times 6 dd 0
cp_win dd -1
cp_sel dd 0
cp_stat dd 0
cp_tick dd 0
cp_inlen dd 0
cp_flen dd 0
cp_argname dd 0
cp_cx dd 0
cp_cy dd 0
cp_cw dd 0
cp_ch dd 0
cp_tn dd 0
cp_kd dd 0
cp_kt dd 0
cp_rnames dd cp_r0, cp_r1, cp_r2, cp_r3, cp_r4, cp_r5, cp_r6, cp_r7
cp_yesno dd cp_no, cp_yes
cp_speeds dd cp_sp1, cp_sp2, cp_sp3
cp_k_scheme db 'scheme', 0
cp_k_dbl db 'dblclick', 0
cp_k_swap db 'swap', 0
cp_k_speed db 'speed', 0
cp_k_rate db 'rate', 0
cp_k_delay db 'delay', 0
cp_k_date db 'date', 0
cp_k_time db 'time', 0
cp_m_show db 'show', 0
cp_r0 db 'Colours', 0
cp_r1 db 'Double-click', 0
cp_r2 db 'Swap buttons', 0
cp_r3 db 'Mouse speed', 0
cp_r4 db 'Key repeat', 0
cp_r5 db 'Key delay', 0
cp_r6 db 'Date', 0
cp_r7 db 'Time', 0
cp_no db 'No', 0
cp_yes db 'Yes', 0
cp_sp1 db 'Slow', 0
cp_sp2 db 'Normal', 0
cp_sp3 db 'Fast', 0
cp_u_ticks db ' ticks', 0
cp_u_rate db ' (0 fast, 31 slow)', 0
cp_u_ms db ' ms', 0
cp_title db 'Control Panel', 0
cp_s_help db 'Up/Down row  Left/Right change  Enter date/time  Esc quit', 0
cp_s_set db 'The clock is set.', 0
cp_s_bad db 'That is not a date or time.', 0
cp_s_date db 'Date (YYYY-MM-DD): ', 0
cp_s_time db 'Time (HH:MM:SS): ', 0
cp_path db '/desktop/control.cfg', 0
cp_bye db 'Control Panel closed.', 10, 0
cp_saved db 'Control Panel closed; settings saved.', 10, 0
cp_m_nosave db 'control: the settings could not be saved', 10, 0
cp_m_bad db 'control: show | scheme 0-3 | dblclick 10-200 | swap 0-1 | speed 1-3 | rate 0-31 | delay 0-3 | date YYYY-MM-DD | time HH:MM:SS', 10, 0
cp_m_head db 'control: ', 0
cp_m_kok db 'kbd ok', 0
cp_m_kno db 'kbd no answer', 0
cp_m_date db 'control: date ', 0
cp_m_time db ' time ', 0
cp_m_pass db 'cp: PASS', 10, 0
cp_m_fail db 'cp: FAIL at ', 0
cp_t_time db '23:59:58', 0
cp_t_date db '2031-02-28', 0
cp_t_badt db '24:00:00', 0
cp_t_badd db '2031-13-01', 0
cp_t_nokey db 'colour', 0
cp_t_pkt_l db 0x09, 0, 0
cp_t_pkt_0 db 0x08, 0, 0
cp_t_pkt_x db 0x08, 4, 0
cp_t_cfg db 'scheme 3', 10, 'bogus 5', 10, 'dblclick 70', 10, 'speed 9', 10, 0
cp_t_cfglen equ $ - cp_t_cfg
cp_word times 16 db 0
cp_in times CP_INMAX + 2 db 0
cp_line times 200 db 0
cp_fbuf times CP_FBUF db 0
