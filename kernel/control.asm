; Squirrel-OS/2 — Control Panel v1 (2.3-control). Original code.
;
; Colours (named theme schemes), mouse (double-click time, button swap,
; speed), date and time (CMOS RTC), and keyboard (repeat rate and delay).
; Settings live in /desktop/control.cfg and are applied at boot when the
; file is there. Shell: `control` (window), `control show`, `control set
; ...`, `control save`, `control load`, `cptest`. See
; documentation/apps/control.md.

; ---------- live settings (defaults match Warp / PM_DBL) ----------
CP_SCHEME_WARP  equ 0
CP_SCHEME_NIGHT equ 1
CP_SCHEME_ROSE  equ 2
CP_NSCHEME      equ 3

CP_SPEED_MIN    equ 1
CP_SPEED_MAX    equ 4
CP_DBL_MIN      equ 10
CP_DBL_MAX      equ 200
CP_REP_MIN      equ 2
CP_REP_MAX      equ 30
CP_DEL_MIN      equ 10
CP_DEL_MAX      equ 100

CP_FBUF         equ 512

; Runtime theme colours. Drawing in wm.asm reads these; TH_* in theme.inc
; are the Warp defaults and the starting values.
th_desktop  db TH_DESKTOP
th_face     db TH_FACE
th_light    db TH_LIGHT
th_shadow   db TH_SHADOW
th_dark     db TH_DARK
th_frame    db TH_FRAME
th_title    db TH_TITLE
th_title_idle db TH_TITLE_IDLE
th_title_text db TH_TITLE_TEXT
th_client   db TH_CLIENT
th_text     db TH_TEXT

cp_scheme   db CP_SCHEME_WARP
cp_dbl      dd 50               ; ticks between the presses of a double-click
cp_swap     db 0                ; 1: left and right buttons swapped
cp_speed    db 1                ; motion multiplier 1..4
cp_repeat   db 10               ; typematic: chars per second-ish (period ticks)
cp_delay    db 50               ; ticks before the first repeat

; ---------- scheme tables: desktop, face, light, shadow, dark, frame,
; title, title_idle, title_text, client, text ----------
cp_schemes:
    ; warp (W.1 defaults)
    db 0x03, 0x07, 0x3F, 0x38, 0x00, 0x3F, 0x01, 0x38, 0x3F, 0x07, 0x00
    ; night: black desktop, white text, dark grey face, cyan title
    db 0x00, 0x38, 0x3F, 0x07, 0x00, 0x07, 0x03, 0x08, 0x3F, 0x00, 0x3F
    ; rose: magenta desktop, pink-ish title (light red), light face
    db 0x05, 0x07, 0x3F, 0x38, 0x00, 0x3F, 0x0C, 0x38, 0x3F, 0x07, 0x00

cp_scheme_names:
    dd cp_n_warp, cp_n_night, cp_n_rose
cp_n_warp  db 'warp', 0
cp_n_night db 'night', 0
cp_n_rose  db 'rose', 0

; At boot, after the data disk is mounted: apply /desktop/control.cfg
; when it is there. Missing file or a bad line leaves the defaults.
cp_boot:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    call cp_load
.r:
    popad
    ret

; Copies the current scheme into th_* and rewrites bev_cols so bevels
; match. Mouse / keyboard live values are already in cp_*.
cp_apply:
    pushad
    movzx eax, byte [cp_scheme]
    cmp eax, CP_NSCHEME
    jb .ok
    xor eax, eax
    mov [cp_scheme], al
.ok:
    imul eax, eax, 11
    lea esi, [cp_schemes+eax]
    mov edi, th_desktop
    mov ecx, 11
    rep movsb
    ; bevel rings from the live colours
    mov al, [th_light]
    mov [bev_cols], al
    mov [bev_cols+1], al
    mov al, [th_dark]
    mov [bev_cols+2], al
    mov al, [th_shadow]
    mov [bev_cols+3], al
    mov [bev_cols+4], al
    mov al, [th_dark]
    mov [bev_cols+5], al
    mov al, [th_light]
    mov [bev_cols+6], al
    mov al, [th_face]
    mov [bev_cols+7], al
    call cp_kbd_apply           ; typematic rate and delay on the keyboard
    popad
    ret

; Programs the PS/2 keyboard's typematic rate and delay (command 0xF3).
; cp_delay is ticks (10..100 at ~100 Hz) -> 250/500/750/1000 ms bits.
; cp_repeat is 2..30 -> the 5-bit rate field (higher = faster).
cp_kbd_apply:
    pushad
    call mouse_wait_in
    mov al, 0xF3
    out 0x60, al
    call mouse_wait_out
    in al, 0x60                 ; ACK
    ; delay bits 5-6
    movzx eax, byte [cp_delay]
    xor edx, edx
    mov ebx, 25                 ; 25 ticks ~ 250 ms
    div ebx
    cmp eax, 3
    jbe .d
    mov eax, 3
.d:
    mov cl, al
    shl cl, 5
    ; rate bits 0-4: map 2..30 -> 31..0 roughly
    movzx eax, byte [cp_repeat]
    cmp eax, 30
    jbe .rmax
    mov eax, 30
.rmax:
    mov ebx, 30
    sub ebx, eax                ; slow repeat -> larger period code
    cmp ebx, 31
    jbe .rok
    mov ebx, 31
.rok:
    or cl, bl
    call mouse_wait_in
    mov al, cl
    out 0x60, al
    call mouse_wait_out
    in al, 0x60                 ; ACK
    popad
    ret

; ---------- /desktop/control.cfg ----------

cp_path db '/desktop/control.cfg', 0
cp_dir  db '/desktop', 0

; Writes the live settings. Makes /desktop if needed. CF if it fails.
cp_save:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    mov esi, cp_dir
    call fs_mkdir               ; ok if it is already there
    mov edi, cp_fbuf
    mov esi, cp_k_scheme
    call cp_puts
    mov al, ' '
    stosb
    movzx eax, byte [cp_scheme]
    mov esi, [cp_scheme_names+eax*4]
    call cp_puts
    mov al, 10
    stosb
    mov esi, cp_k_dbl
    call cp_puts
    mov al, ' '
    stosb
    mov eax, [cp_dbl]
    call cp_putn
    mov al, 10
    stosb
    mov esi, cp_k_swap
    call cp_puts
    mov al, ' '
    stosb
    movzx eax, byte [cp_swap]
    call cp_putn
    mov al, 10
    stosb
    mov esi, cp_k_speed
    call cp_puts
    mov al, ' '
    stosb
    movzx eax, byte [cp_speed]
    call cp_putn
    mov al, 10
    stosb
    mov esi, cp_k_repeat
    call cp_puts
    mov al, ' '
    stosb
    movzx eax, byte [cp_repeat]
    call cp_putn
    mov al, 10
    stosb
    mov esi, cp_k_delay
    call cp_puts
    mov al, ' '
    stosb
    movzx eax, byte [cp_delay]
    call cp_putn
    mov al, 10
    stosb
    sub edi, cp_fbuf
    mov [cp_flen], edi
    mov esi, cp_path
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov esi, cp_fbuf
    mov ecx, [cp_flen]
    call fs_write
    cmp eax, [cp_flen]
    jne .bad
    call fs_close
    popad
    clc
    ret
.bad:
    call fs_close
.fail:
    popad
    stc
    ret

; Reads and applies the file. CF if missing or nothing useful was read.
cp_load:
    pushad
    cmp byte [fs_mounted], 0
    je .fail
    mov esi, cp_path
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov edi, cp_fbuf
    mov ecx, CP_FBUF-1
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, 0
    jle .fail
    mov byte [cp_fbuf+edx], 0
    mov esi, cp_fbuf
.line:
    cmp byte [esi], 0
    je .done
    cmp byte [esi], 10
    je .nl
    cmp byte [esi], 13
    je .nl
    cmp byte [esi], '#'
    je .skip
    call cp_parse_line
    jmp .next
.skip:
.next:
    cmp byte [esi], 0
    je .done
    cmp byte [esi], 10
    je .nl
    cmp byte [esi], 13
    je .nl
    inc esi
    jmp .next
.nl:
    inc esi
    jmp .line
.done:
    call cp_apply
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; esi -> "key value...": updates one setting. Leaves esi on the newline
; or the end. Unknown keys are ignored.
cp_parse_line:
    pushad
    mov edi, cp_word
    mov ecx, 15
.k:
    lodsb
    cmp al, ' '
    je .kend
    cmp al, 9
    je .kend
    cmp al, 10
    je .kend0
    cmp al, 13
    je .kend0
    test al, al
    jz .kend0
    jecxz .k
    stosb
    dec ecx
    jmp .k
.kend0:
    dec esi
.kend:
    mov byte [edi], 0
.sp:
    cmp byte [esi], ' '
    je .s1
    cmp byte [esi], 9
    jne .val
.s1:
    inc esi
    jmp .sp
.val:
    mov edi, cp_k_scheme
    call cp_streq
    je .scheme
    mov edi, cp_k_dbl
    call cp_streq
    je .dbl
    mov edi, cp_k_swap
    call cp_streq
    je .swap
    mov edi, cp_k_speed
    call cp_streq
    je .speed
    mov edi, cp_k_repeat
    call cp_streq
    je .repeat
    mov edi, cp_k_delay
    call cp_streq
    je .delay
    jmp .out
.scheme:
    xor ecx, ecx
.sl:
    mov edi, [cp_scheme_names+ecx*4]
    call cp_streq_val
    je .sgot
    inc ecx
    cmp ecx, CP_NSCHEME
    jb .sl
    jmp .out
.sgot:
    mov [cp_scheme], cl
    jmp .out
.dbl:
    call cp_atoi
    cmp eax, CP_DBL_MIN
    jb .out
    cmp eax, CP_DBL_MAX
    ja .out
    mov [cp_dbl], eax
    jmp .out
.swap:
    call cp_atoi
    cmp eax, 1
    ja .out
    mov [cp_swap], al
    jmp .out
.speed:
    call cp_atoi
    cmp eax, CP_SPEED_MIN
    jb .out
    cmp eax, CP_SPEED_MAX
    ja .out
    mov [cp_speed], al
    jmp .out
.repeat:
    call cp_atoi
    cmp eax, CP_REP_MIN
    jb .out
    cmp eax, CP_REP_MAX
    ja .out
    mov [cp_repeat], al
    jmp .out
.delay:
    call cp_atoi
    cmp eax, CP_DEL_MIN
    jb .out
    cmp eax, CP_DEL_MAX
    ja .out
    mov [cp_delay], al
.out:
    popad
    ret

; ---------- string / number helpers (local; keep registers as noted) ----------

; esi = value text (cp_word holds the key). edi = name -> ZF if equal.
cp_streq:
    push esi
    mov esi, cp_word
.l:
    mov al, [esi]
    cmp al, [edi]
    jne .no
    test al, al
    jz .yes
    inc esi
    inc edi
    jmp .l
.yes:
    pop esi
    xor eax, eax
    ret
.no:
    pop esi
    or eax, 1
    ret

; esi = value text, edi = name -> ZF if the value starts with the name
; and then a space/newline/end. Advances esi past the name when equal.
cp_streq_val:
    push edi
.l:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, ' '
    je .yes
    cmp al, 10
    je .yes
    cmp al, 13
    je .yes
.no:
    pop edi
    or eax, 1
    ret
.yes:
    pop edi
    xor eax, eax
    ret

; esi = digits -> eax = number; leaves esi on the first non-digit
cp_atoi:
    xor eax, eax
    xor ebx, ebx
.l:
    mov bl, [esi]
    cmp bl, '0'
    jb .r
    cmp bl, '9'
    ja .r
    sub bl, '0'
    imul eax, eax, 10
    add eax, ebx
    inc esi
    jmp .l
.r:
    ret

; esi = ASCIIZ, edi = where
cp_puts:
    push eax
.l:
    lodsb
    test al, al
    jz .r
    stosb
    jmp .l
.r:
    pop eax
    ret

; eax = number, edi = where
cp_putn:
    push esi
    push edi
    call itoa
    pop edi
    mov esi, num_buf
.l:
    lodsb
    test al, al
    jz .r
    stosb
    jmp .l
.r:
    pop esi
    ret

; ---------- RTC set (CMOS) ----------

; eax = hour<<16|min<<8|sec (binary) -> written as BCD. Keeps other regs.
cp_set_time:
    pushad
    call cp_rtc_wait
    mov edx, eax
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    or al, 0x80                 ; SET bit: stop updates
    mov ah, al
    mov al, 0x0B
    out 0x70, al
    mov al, ah
    out 0x71, al
    mov eax, edx
    mov ecx, eax
    and eax, 0xFF               ; sec
    call cp_bin_bcd
    mov bl, al
    mov al, 0
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov eax, ecx
    shr eax, 8
    and eax, 0xFF               ; min
    call cp_bin_bcd
    mov bl, al
    mov al, 2
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov eax, ecx
    shr eax, 16
    and eax, 0xFF               ; hour
    call cp_bin_bcd
    mov bl, al
    mov al, 4
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    and al, 0x7F                ; run again
    mov ah, al
    mov al, 0x0B
    out 0x70, al
    mov al, ah
    out 0x71, al
    popad
    ret

; eax = year<<16|month<<8|day (year 0..9999) -> CMOS day/month/year/century
cp_set_date:
    pushad
    call cp_rtc_wait
    mov edx, eax
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    or al, 0x80
    mov ah, al
    mov al, 0x0B
    out 0x70, al
    mov al, ah
    out 0x71, al
    mov eax, edx
    mov ecx, eax
    and eax, 0xFF               ; day
    call cp_bin_bcd
    mov bl, al
    mov al, 7
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov eax, ecx
    shr eax, 8
    and eax, 0xFF               ; month
    call cp_bin_bcd
    mov bl, al
    mov al, 8
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov eax, ecx
    shr eax, 16                 ; year
    mov ebx, eax
    mov ecx, 100
    xor edx, edx
    div ecx                     ; eax = century, edx = yy
    push edx
    call cp_bin_bcd
    mov bl, al
    mov al, 0x32
    out 0x70, al
    mov al, bl
    out 0x71, al
    pop eax
    call cp_bin_bcd
    mov bl, al
    mov al, 9
    out 0x70, al
    mov al, bl
    out 0x71, al
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    and al, 0x7F
    mov ah, al
    mov al, 0x0B
    out 0x70, al
    mov al, ah
    out 0x71, al
    popad
    ret

cp_rtc_wait:
    push eax
.w:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jnz .w
    pop eax
    ret

; al = 0..99 binary -> al BCD
cp_bin_bcd:
    push ebx
    movzx eax, al
    mov bl, 10
    xor ah, ah
    div bl                      ; al = tens, ah = units
    shl al, 4
    or al, ah
    pop ebx
    ret

; ---------- mouse helpers used from mouse.asm ----------

; After mouse_decode: eax = dx, ebx = dy. Scales by cp_speed.
cp_mouse_scale:
    push ecx
    movzx ecx, byte [cp_speed]
    cmp ecx, 1
    jbe .r
    imul eax, ecx
    imul ebx, ecx
.r:
    pop ecx
    ret

; al = button bits from the packet -> al with left/right swapped when set
cp_mouse_btns:
    cmp byte [cp_swap], 0
    je .r
    mov ah, al
    and al, ~3
    test ah, 1
    jz .no_l
    or al, 2
.no_l:
    test ah, 2
    jz .r
    or al, 1
.r:
    ret

; ---------- shell: control / cptest ----------
cmd_control_run:
    call next_word              ; esi = word, edi = rest of the line
    cmp byte [esi], 0
    je cp_window
    push edi
    mov edi, cp_w_show
    call streq
    pop edi
    je cp_cmd_show
    push edi
    mov edi, cp_w_save
    call streq
    pop edi
    je cp_cmd_save
    push edi
    mov edi, cp_w_load
    call streq
    pop edi
    je cp_cmd_load
    push edi
    mov edi, cp_w_set
    call streq
    pop edi
    je .set
    mov esi, cp_m_usage
    call puts
    ret
.set:
    mov esi, edi                ; "scheme night" / "dbl 77" / ...
    jmp cp_cmd_set

cp_cmd_show:
    call cp_print
    ret

cp_cmd_save:
    call cp_save
    jc .bad
    mov esi, cp_m_saved
    call puts
    ret
.bad:
    mov esi, cp_m_nosave
    call puts
    ret

cp_cmd_load:
    call cp_load
    jc .bad
    mov esi, cp_m_loaded
    call puts
    call cp_print
    ret
.bad:
    mov esi, cp_m_noload
    call puts
    ret

; esi = "scheme night" | "dbl N" | ... (rest after "set")
cp_cmd_set:
    call next_word
    cmp byte [esi], 0
    je .usage
    push edi
    mov edi, cp_k_scheme
    call streq
    pop edi
    je .scheme
    push edi
    mov edi, cp_k_dbl
    call streq
    pop edi
    je .dbl
    push edi
    mov edi, cp_k_swap
    call streq
    pop edi
    je .swap
    push edi
    mov edi, cp_k_speed
    call streq
    pop edi
    je .speed
    push edi
    mov edi, cp_k_repeat
    call streq
    pop edi
    je .repeat
    push edi
    mov edi, cp_k_delay
    call streq
    pop edi
    je .delay
    push edi
    mov edi, cp_w_time
    call streq
    pop edi
    je .time
    push edi
    mov edi, cp_w_date
    call streq
    pop edi
    je .date
.usage:
    mov esi, cp_m_usage
    call puts
    ret
.scheme:
    mov esi, edi
    call next_word
    xor ecx, ecx
.sl:
    push edi
    mov edi, [cp_scheme_names+ecx*4]
    call streq
    pop edi
    je .sgot
    inc ecx
    cmp ecx, CP_NSCHEME
    jb .sl
    mov esi, cp_m_bad
    call puts
    ret
.sgot:
    mov [cp_scheme], cl
    call cp_apply
    jmp cp_cmd_show
.dbl:
    mov esi, edi
    call next_word
    call cp_atoi
    cmp eax, CP_DBL_MIN
    jb .badn
    cmp eax, CP_DBL_MAX
    ja .badn
    mov [cp_dbl], eax
    jmp cp_cmd_show
.swap:
    mov esi, edi
    call next_word
    call cp_atoi
    cmp eax, 1
    ja .badn
    mov [cp_swap], al
    jmp cp_cmd_show
.speed:
    mov esi, edi
    call next_word
    call cp_atoi
    cmp eax, CP_SPEED_MIN
    jb .badn
    cmp eax, CP_SPEED_MAX
    ja .badn
    mov [cp_speed], al
    jmp cp_cmd_show
.repeat:
    mov esi, edi
    call next_word
    call cp_atoi
    cmp eax, CP_REP_MIN
    jb .badn
    cmp eax, CP_REP_MAX
    ja .badn
    mov [cp_repeat], al
    jmp cp_cmd_show
.delay:
    mov esi, edi
    call next_word
    call cp_atoi
    cmp eax, CP_DEL_MIN
    jb .badn
    cmp eax, CP_DEL_MAX
    ja .badn
    mov [cp_delay], al
    jmp cp_cmd_show
.time:
    mov esi, edi
    call next_word
    call cp_atoi
    mov [cp_th], eax            ; hour
    mov esi, edi
    call next_word
    call cp_atoi
    mov [cp_tm], eax
    mov esi, edi
    call next_word
    call cp_atoi
    mov ecx, [cp_th]
    shl ecx, 16
    mov ebx, [cp_tm]
    shl ebx, 8
    or ecx, ebx
    or ecx, eax
    mov eax, ecx
    call cp_set_time
    jmp cp_cmd_show
.date:
    mov esi, edi
    call next_word
    call cp_atoi
    mov [cp_th], eax            ; year
    mov esi, edi
    call next_word
    call cp_atoi
    mov [cp_tm], eax            ; month
    mov esi, edi
    call next_word
    call cp_atoi
    mov ecx, [cp_th]
    shl ecx, 16
    mov ebx, [cp_tm]
    shl ebx, 8
    or ecx, ebx
    or ecx, eax
    mov eax, ecx
    call cp_set_date
    jmp cp_cmd_show
.badn:
    mov esi, cp_m_bad
    call puts
    ret

cp_print:
    pushad
    mov esi, cp_m_scheme
    call puts
    movzx eax, byte [cp_scheme]
    mov esi, [cp_scheme_names+eax*4]
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_dbl
    call puts
    mov eax, [cp_dbl]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_swap
    call puts
    movzx eax, byte [cp_swap]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_speed
    call puts
    movzx eax, byte [cp_speed]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_repeat
    call puts
    movzx eax, byte [cp_repeat]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_delay
    call puts
    movzx eax, byte [cp_delay]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov esi, cp_m_time
    call puts
    call gui_time
    mov [cp_tv], eax
    mov eax, [cp_tv]
    shr eax, 16
    and eax, 0xFF
    call cp_print2
    mov al, ':'
    call putc
    mov eax, [cp_tv]
    shr eax, 8
    and eax, 0xFF
    call cp_print2
    mov al, ':'
    call putc
    mov eax, [cp_tv]
    and eax, 0xFF
    call cp_print2
    mov al, 10
    call putc
    mov esi, cp_m_date
    call puts
    call gui_date
    mov [cp_tv], eax
    mov eax, [cp_tv]
    shr eax, 16
    call itoa
    mov esi, num_buf
    call puts
    mov al, '-'
    call putc
    mov eax, [cp_tv]
    shr eax, 8
    and eax, 0xFF
    call cp_print2
    mov al, '-'
    call putc
    mov eax, [cp_tv]
    and eax, 0xFF
    call cp_print2
    mov al, 10
    call putc
    popad
    ret

; eax = 0..99 -> two digits
cp_print2:
    push eax
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    call putc
    mov al, dl
    add al, '0'
    call putc
    pop eax
    ret

; ---------- Control Panel window ----------
; A simple settings window on the window manager's screen. Up/Down pick a
; row, Left/Right change it, S saves, L loads, T sets the clock from the
; time/date rows, Esc quits. Prints nothing on the text screen; the shell
; sees the prompt again when it closes.

CP_WIN_W    equ 280
CP_WIN_H    equ 160
CP_ROWS     equ 6               ; scheme, dbl, swap, speed, repeat, delay

cp_window:
    pushad
    call wm_screen
    jc .nogfx
    mov eax, [gfx_width]
    sub eax, CP_WIN_W
    shr eax, 1
    mov ebx, [gfx_height]
    sub ebx, CP_WIN_H
    shr ebx, 1
    mov ecx, CP_WIN_W
    mov edx, CP_WIN_H
    mov esi, cp_title
    call wm_create
    cmp eax, -1
    je .nogfx
    mov [cp_win], eax
    mov dword [cp_row], 0
    call cp_paint
.loop:
    call wm_update
    call kbd_getscan
    call kbd_shift_track
    cmp al, 0x01                ; Esc
    je .close
    cmp al, 0x1F                ; S
    je .save
    cmp al, 0x26                ; L
    je .load
    cmp al, 0x48                ; Up
    je .up
    cmp al, 0x50                ; Down
    je .down
    cmp al, 0x4B                ; Left
    je .left
    cmp al, 0x4D                ; Right
    je .right
    jmp .loop
.up:
    cmp dword [cp_row], 0
    je .loop
    dec dword [cp_row]
    call cp_paint
    jmp .loop
.down:
    cmp dword [cp_row], CP_ROWS-1
    jae .loop
    inc dword [cp_row]
    call cp_paint
    jmp .loop
.left:
    mov eax, -1
    call cp_nudge
    call cp_paint
    jmp .loop
.right:
    mov eax, 1
    call cp_nudge
    call cp_paint
    jmp .loop
.save:
    call cp_save
    call cp_paint
    jmp .loop
.load:
    call cp_load
    call cp_paint
    jmp .loop
.close:
    mov eax, [cp_win]
    call wm_close
    call gfx_text
    popad
    ret
.nogfx:
    mov esi, cp_m_nogfx
    call puts
    popad
    ret

; eax = -1 or +1: change the selected row
cp_nudge:
    pushad
    mov ebx, [cp_row]
    cmp ebx, 0
    je .scheme
    cmp ebx, 1
    je .dbl
    cmp ebx, 2
    je .swap
    cmp ebx, 3
    je .speed
    cmp ebx, 4
    je .repeat
    ; delay
    movzx ecx, byte [cp_delay]
    add ecx, eax
    cmp ecx, CP_DEL_MIN
    jl .r
    cmp ecx, CP_DEL_MAX
    jg .r
    mov [cp_delay], cl
    jmp .r
.scheme:
    movzx ecx, byte [cp_scheme]
    add ecx, eax
    cmp ecx, 0
    jl .r
    cmp ecx, CP_NSCHEME
    jge .r
    mov [cp_scheme], cl
    call cp_apply
    jmp .r
.dbl:
    mov ecx, [cp_dbl]
    add ecx, eax
    cmp ecx, CP_DBL_MIN
    jl .r
    cmp ecx, CP_DBL_MAX
    jg .r
    mov [cp_dbl], ecx
    jmp .r
.swap:
    xor byte [cp_swap], 1
    jmp .r
.speed:
    movzx ecx, byte [cp_speed]
    add ecx, eax
    cmp ecx, CP_SPEED_MIN
    jl .r
    cmp ecx, CP_SPEED_MAX
    jg .r
    mov [cp_speed], cl
    jmp .r
.repeat:
    movzx ecx, byte [cp_repeat]
    add ecx, eax
    cmp ecx, CP_REP_MIN
    jl .r
    cmp ecx, CP_REP_MAX
    jg .r
    mov [cp_repeat], cl
.r:
    popad
    ret

cp_paint:
    pushad
    call wm_redraw
    mov eax, [cp_win]
    call wm_record
    jc .r
    ; client top-left
    mov eax, [edi+WIN_X]
    add eax, 2
    mov ebx, [edi+WIN_Y]
    add ebx, WM_TITLE_H + 2
    mov [cp_px], eax
    mov [cp_py], ebx
    xor ebp, ebp
.row:
    mov eax, [cp_px]
    mov ebx, [cp_py]
    mov ecx, ebp
    imul ecx, ecx, 12
    add ebx, ecx
    mov dl, [th_client]
    mov [gfx_bg], dl
    cmp ebp, [cp_row]
    jne .lab
    mov byte [gfx_colour], 0x01 ; highlight bar (blue)
    push eax
    push ebx
    mov ecx, CP_WIN_W - 8
    mov edx, 10
    call gfx_fillrect
    pop ebx
    pop eax
    mov byte [gfx_bg], 0x01
    mov byte [gfx_colour], 0x3F ; white on blue
    jmp .txt
.lab:
    mov dl, [th_text]
    mov [gfx_colour], dl        ; scheme text on the client
.txt:
    mov esi, [cp_row_lab+ebp*4]
    push ebp
    call cp_draw_str
    add eax, 90
    pop ebp
    push ebp
    call cp_row_value           ; -> cp_val
    mov esi, cp_val
    call cp_draw_str
    pop ebp
    inc ebp
    cmp ebp, CP_ROWS
    jb .row
    ; help
    mov eax, [cp_px]
    mov ebx, [cp_py]
    add ebx, CP_ROWS * 12 + 4
    mov dl, [th_client]
    mov [gfx_bg], dl
    mov dl, [th_text]
    mov [gfx_colour], dl
    mov esi, cp_help
    call cp_draw_str
    call vbe_flip
.r:
    popad
    ret

; eax, ebx = where, esi = ASCIIZ. Uses the 5x7 font.
cp_draw_str:
    pushad
.l:
    movzx ecx, byte [esi]
    test ecx, ecx
    jz .r
    push esi
    mov dl, cl
    call gfx_drawchar
    pop esi
    inc esi
    add eax, 6
    jmp .l
.r:
    popad
    ret

; ebp = row -> cp_val filled
cp_row_value:
    pushad
    mov edi, cp_val
    cmp ebp, 0
    je .scheme
    cmp ebp, 1
    je .dbl
    cmp ebp, 2
    je .swap
    cmp ebp, 3
    je .speed
    cmp ebp, 4
    je .repeat
    movzx eax, byte [cp_delay]
    jmp .num
.scheme:
    movzx eax, byte [cp_scheme]
    mov esi, [cp_scheme_names+eax*4]
    call cp_puts
    mov byte [edi], 0
    jmp .r
.dbl:
    mov eax, [cp_dbl]
    jmp .num
.swap:
    movzx eax, byte [cp_swap]
    jmp .num
.speed:
    movzx eax, byte [cp_speed]
    jmp .num
.repeat:
    movzx eax, byte [cp_repeat]
.num:
    push edi
    call itoa
    pop edi
    mov esi, num_buf
    call cp_puts
    mov byte [edi], 0
.r:
    popad
    ret

; Warp defaults in memory and rewritten to the cfg file when possible.
cp_restore_defaults:
    pushad
    mov byte [cp_scheme], CP_SCHEME_WARP
    mov dword [cp_dbl], 50
    mov byte [cp_swap], 0
    mov byte [cp_speed], 1
    mov byte [cp_repeat], 10
    mov byte [cp_delay], 50
    call cp_apply
    call cp_save                ; leave a clean file (ignore failure)
    popad
    ret

; ---------- self-test ----------
cmd_cptest_run:
    pushad
    mov byte [cp_ok], 1
    ; scheme round-trip through the file
    mov byte [cp_scheme], CP_SCHEME_NIGHT
    mov dword [cp_dbl], 77
    mov byte [cp_swap], 1
    mov byte [cp_speed], 3
    mov byte [cp_repeat], 8
    mov byte [cp_delay], 33
    call cp_apply
    call cp_save
    jc .fail
    mov byte [cp_scheme], CP_SCHEME_WARP
    mov dword [cp_dbl], 50
    mov byte [cp_swap], 0
    mov byte [cp_speed], 1
    mov byte [cp_repeat], 10
    mov byte [cp_delay], 50
    call cp_apply
    call cp_load
    jc .fail
    cmp byte [cp_scheme], CP_SCHEME_NIGHT
    jne .fail
    cmp dword [cp_dbl], 77
    jne .fail
    cmp byte [cp_swap], 1
    jne .fail
    cmp byte [cp_speed], 3
    jne .fail
    cmp byte [cp_repeat], 8
    jne .fail
    cmp byte [cp_delay], 33
    jne .fail
    cmp byte [th_desktop], 0x00 ; night desktop
    jne .fail
    ; RTC: set a time and read it back
    mov eax, (14 << 16) | (25 << 8) | 36
    call cp_set_time
    call gui_time
    mov ebx, eax
    shr eax, 16
    and eax, 0xFF
    cmp eax, 14
    jne .fail
    mov eax, ebx
    shr eax, 8
    and eax, 0xFF
    cmp eax, 25
    jne .fail
    mov eax, ebx
    and eax, 0xFF
    cmp eax, 36
    jne .fail
    ; restore Warp defaults in memory and on disk for later checks
    call cp_restore_defaults
    jmp .say
.fail:
    mov byte [cp_ok], 0
    call cp_restore_defaults
.say:
    mov esi, cp_pass
    cmp byte [cp_ok], 1
    je .out
    mov esi, cp_fail
.out:
    call puts
    popad
    ret

; ---------- data ----------
cp_k_scheme db 'scheme', 0
cp_k_dbl    db 'dbl', 0
cp_k_swap   db 'swap', 0
cp_k_speed  db 'speed', 0
cp_k_repeat db 'repeat', 0
cp_k_delay  db 'delay', 0
cp_w_show   db 'show', 0
cp_w_save   db 'save', 0
cp_w_load   db 'load', 0
cp_w_set    db 'set', 0
cp_w_time   db 'time', 0
cp_w_date   db 'date', 0
cp_m_usage  db 'Usage: control [show|save|load|set ...]', 10, 0
cp_m_saved  db 'control: saved /desktop/control.cfg', 10, 0
cp_m_nosave db 'control: cannot write /desktop/control.cfg', 10, 0
cp_m_loaded db 'control: loaded /desktop/control.cfg', 10, 0
cp_m_noload db 'control: no /desktop/control.cfg', 10, 0
cp_m_bad    db 'control: bad value', 10, 0
cp_m_nogfx  db 'control: no graphics', 10, 0
cp_m_scheme db 'scheme ', 0
cp_m_dbl    db 'dbl ', 0
cp_m_swap   db 'swap ', 0
cp_m_speed  db 'speed ', 0
cp_m_repeat db 'repeat ', 0
cp_m_delay  db 'delay ', 0
cp_m_time   db 'time ', 0
cp_m_date   db 'date ', 0
cp_title    db 'Control Panel', 0
cp_help     db 'Left/Right change  S save  L load  Esc', 0
cp_pass     db 'control: PASS', 10, 0
cp_fail     db 'control: FAIL', 10, 0
cp_lab0     db 'Colours', 0
cp_lab1     db 'Dbl-click', 0
cp_lab2     db 'Btn swap', 0
cp_lab3     db 'Speed', 0
cp_lab4     db 'Repeat', 0
cp_lab5     db 'Delay', 0
cp_row_lab  dd cp_lab0, cp_lab1, cp_lab2, cp_lab3, cp_lab4, cp_lab5

align 4
cp_flen     dd 0
cp_win      dd -1
cp_row      dd 0
cp_px       dd 0
cp_py       dd 0
cp_th       dd 0
cp_tm       dd 0
cp_tv       dd 0
cp_ok       db 0
cp_word     times 16 db 0
cp_val      times 16 db 0
cp_fbuf     times CP_FBUF db 0
