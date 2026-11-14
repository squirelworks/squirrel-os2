; dosvga.inc — VGA text and mode 13h for dosrun in a 2.2 window (P.8-dos-window).
; Original code.
;
; The DOS screen (text cells or mode 13h) is shown in a program window
; instead of taking the whole display. Mode 13h is blitted with WD_BLIT
; at scale 1 (on 640 x 480) or 2 (when the screen is large enough).
; Keys for the focused window become the DOS keyboard.
; INT 10h AX=0013h still owns A000:0000; the BIOS teletype in graphics
; writes there with the kernel's 5 x 7 font in 6 x 8 cells (53 x 25).
; Leaving graphics or ending the program closes the window; a log of
; text output is then replayed to the console so shell checks still see
; the PASS lines.
;
; Note: the first window id is 0, so "no window" is vwin == -1, not 0.

SYS_GUI_      equ 35
SYS_WINOPEN_  equ 37
SYS_WINCLOSE_ equ 38
SYS_WINMOVE_  equ 39
SYS_WINTITLE_ equ 40
SYS_WINDRAW_  equ 41
SYS_WINFLUSH_ equ 42
SYS_WINEVENT_ equ 43
SYS_WININFO_  equ 44
VG_FONT     equ 6
VG_TICKS    equ 7
VG_READ     equ 3
WE_KEY_     equ 1
WE_CLOSE_   equ 6
WE_PAINT_   equ 8
WD_FILL_    equ 0
WD_TEXT_    equ 2
WD_BLIT_    equ 4
WD_PIXEL_   equ 7
VGA_SEG     equ 0xA000
VGA_COLS    equ 53
VGA_ROWS    equ 25
TXT_COLS    equ 80
TXT_ROWS    equ 25
CELL_W      equ 6
CELL_H      equ 8
VGA_SLICE   equ 2000
WIN_TITLE_H equ 10
TH_DESK_    equ 3

; INT 10h AH=00h: AL = mode
vga_setmode:
    mov al, [rAX]
    and al, 0x7F
    cmp al, 0x13
    je .gfx
    jmp vga_text_mode
.gfx:
    cmp byte [vmode], 0x13
    je .clear
    call vga_ensure_bufs
    jc .r
    call vga_win_open_gfx
    jc .r
.clear:
    mov byte [vmode], 0x13
    mov dword [vcur], 0
    test byte [rAX], 0x80
    jnz .flush
    cld
    mov edi, [mem]
    add edi, VGA_SEG*16
    mov ecx, 64000/4
    xor eax, eax
    rep stosd
.flush:
    call vga_flush
.r:
    ret

vga_text_mode:
    cmp byte [vmode], 0x13
    jne .nowin
    call vga_flush
    call vga_check_win
    call vga_win_open_text
    ret
.nowin:
    cmp dword [vwin], -1
    jne vga_win_open_text
    mov byte [vmode], 3
    ret

vga_leave:
    cmp dword [vwin], -1
    je .r
    cmp byte [vmode], 0x13
    jne .close
    call vga_flush
    call vga_check_win
.close:
    call vga_win_close
    mov byte [vmode], 3
.r:
    ret

vga_ensure_bufs:
    cmp dword [vframe], 0
    jne .ok
    mov eax, SYS_SBRK
    mov ebx, 64000 + 64000*4 + 96*7 + TXT_COLS*TXT_ROWS*2 + 4096
    int 0x80
    cmp eax, -1
    je .bad
    mov [vframe], eax
    add eax, 64000
    mov [vframe2], eax
    add eax, 64000*4
    mov [vfont], eax
    add eax, 96*7
    mov [vtext], eax
    add eax, TXT_COLS*TXT_ROWS*2
    mov [vlog], eax
    mov dword [vlog_n], 0
    mov ecx, [vfont]
    mov eax, SYS_GUI_
    mov ebx, VG_FONT
    int 0x80
.ok:
    clc
    ret
.bad:
    stc
    ret

vga_win_open_gfx:
    pushad
    call vga_ensure_bufs
    jc .fail
    cmp dword [vwin], -1
    je .fresh
    call vga_pick_scale
    mov [vscale], ecx
    mov dword [vtitle], t_gfx
    call vga_win_size
    call vga_win_apply
    jmp .lut
.fresh:
    call vga_pick_scale
    mov [vscale], ecx
    mov dword [vtitle], t_gfx
    call vga_win_size
    mov eax, [vtitle]
    mov [vopen+16], eax
    mov dword [vopen+20], 0
    mov eax, SYS_WINOPEN_
    mov ebx, vopen
    int 0x80
    cmp eax, -1
    je .fail
    mov [vwin], eax
.lut:
    mov byte [vmode], 0x13
    call vga_simple_lut
    mov eax, SYS_WINFLUSH_
    mov ebx, [vwin]
    int 0x80
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

vga_win_open_text:
    pushad
    call vga_ensure_bufs
    jc .fail
    mov dword [vscale], 1
    mov dword [vtitle], t_text
    mov eax, TXT_COLS * CELL_W
    mov ebx, TXT_ROWS * CELL_H
    mov edx, eax
    add edx, 2
    mov esi, ebx
    add esi, WIN_TITLE_H + 2
    call vga_win_place
    cmp dword [vwin], -1
    jne .move
    mov eax, [vtitle]
    mov [vopen+16], eax
    mov dword [vopen+20], 0
    mov eax, SYS_WINOPEN_
    mov ebx, vopen
    int 0x80
    cmp eax, -1
    je .fail
    mov [vwin], eax
    jmp .drawn
.move:
    call vga_win_apply
.drawn:
    cmp byte [vmode], 0x13
    je .shown
    call vga_text_clear
    call vga_text_flush
.shown:
    mov byte [vmode], 3
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

vga_win_size:
    mov eax, 320
    imul eax, [vscale]
    mov ebx, 200
    imul ebx, [vscale]
    mov edx, eax
    add edx, 2
    mov esi, ebx
    add esi, WIN_TITLE_H + 2
    jmp vga_win_place

vga_pick_scale:
    mov eax, SYS_WININFO_
    mov ebx, -1
    mov ecx, vinfo
    int 0x80
    mov ecx, 1
    cmp dword [vinfo+8], 640 + 2 + 16
    jb .r
    cmp dword [vinfo+12], 400 + WIN_TITLE_H + 2 + 16
    jb .r
    mov ecx, 2
.r:
    ret

vga_win_place:
    push eax
    push ebx
    mov eax, SYS_WININFO_
    mov ebx, -1
    mov ecx, vinfo
    int 0x80
    pop ebx
    pop eax
    mov ecx, [vinfo+8]
    sub ecx, edx
    sar ecx, 1
    cmp ecx, 0
    jge .xok
    xor ecx, ecx
.xok:
    mov [vopen], ecx
    mov ecx, [vinfo+12]
    sub ecx, esi
    sar ecx, 1
    cmp ecx, 0
    jge .yok
    xor ecx, ecx
.yok:
    mov [vopen+4], ecx
    mov [vopen+8], edx
    mov [vopen+12], esi
    mov edx, [vtitle]
    mov [vopen+16], edx
    mov dword [vopen+20], 0
    ret

vga_win_apply:
    mov eax, SYS_WINMOVE_
    mov ebx, [vwin]
    mov ecx, [vopen]
    mov edx, [vopen+4]
    shl edx, 16
    or ecx, edx
    mov edx, [vopen+8]
    mov esi, [vopen+12]
    shl esi, 16
    or edx, esi
    int 0x80
    mov eax, SYS_WINTITLE_
    mov ebx, [vwin]
    mov ecx, [vopen+16]
    int 0x80
    mov eax, SYS_WINFLUSH_
    mov ebx, [vwin]
    int 0x80
    ret

vga_win_close:
    cmp dword [vwin], -1
    je .r
    pushad
    mov eax, SYS_WINCLOSE_
    mov ebx, [vwin]
    int 0x80
    mov dword [vwin], -1
    popad
    call vga_replay_log
.r:
    ret

; ---------- mode 13h blit ----------

vga_flush:
    cmp dword [vwin], -1
    je vga_flush_ret
    pushad
    cld
    mov edi, [vframe]
    test edi, edi
    jz .out
    mov esi, [mem]
    add esi, VGA_SEG*16
    mov ecx, 64000
    xor eax, eax
.t:
    mov al, [esi]
    mov al, [vlut+eax]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .t
    cmp dword [vscale], 2
    je .x2
    mov dword [vcmd], WD_BLIT_
    mov dword [vcmd+4], 0
    mov dword [vcmd+8], 0
    mov dword [vcmd+12], 320
    mov dword [vcmd+16], 200
    mov dword [vcmd+20], -1
    mov eax, [vframe]
    mov [vcmd+24], eax
    jmp .draw
.x2:
    mov esi, [vframe]
    mov edi, [vframe2]
    mov ecx, 200
.xr:
    push ecx
    mov ecx, 320
.xp:
    mov al, [esi]
    inc esi
    mov [edi], al
    mov [edi+1], al
    mov [edi+640], al
    mov [edi+641], al
    add edi, 2
    dec ecx
    jnz .xp
    add edi, 640
    pop ecx
    dec ecx
    jnz .xr
    mov dword [vcmd], WD_BLIT_
    mov dword [vcmd+4], 0
    mov dword [vcmd+8], 0
    mov dword [vcmd+12], 640
    mov dword [vcmd+16], 400
    mov dword [vcmd+20], -1
    mov eax, [vframe2]
    mov [vcmd+24], eax
.draw:
    mov eax, SYS_WINDRAW_
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    mov [vdrawrc], eax
    mov eax, SYS_WINFLUSH_
    mov ebx, [vwin]
    int 0x80
    mov eax, SYS_GUI_
    mov ebx, VG_TICKS
    int 0x80
    mov [vticks], eax
    mov dword [vslice], VGA_SLICE
.out:
    popad
vga_flush_ret:
    ret

vga_check_win:
    cmp dword [vwin], -1
    je .r
    cmp byte [vchecked], 0
    jne .r
    mov byte [vchecked], 1
    pushad
    movzx eax, byte [vlut+4]
    mov [vwant], al
    mov eax, 150
    imul eax, [vscale]
    mov [vcmd+4], eax
    mov eax, 130
    imul eax, [vscale]
    mov [vcmd+8], eax
    mov dword [vcmd], WD_PIXEL_
    mov eax, SYS_WINDRAW_
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    cmp al, [vwant]
    jne .fail
    mov eax, SYS_WININFO_
    mov ebx, [vwin]
    mov ecx, vinfo
    int 0x80
    mov eax, [vinfo]
    dec eax
    dec eax
    cmp eax, 0
    jge .ox
    mov eax, [vinfo]
    add eax, [vinfo+8]
    add eax, 2
.ox:
    mov [vrect], eax
    mov eax, [vinfo+4]
    mov [vrect+4], eax
    mov dword [vrect+8], 1
    mov dword [vrect+12], 1
    mov eax, vpix
    mov [vrect+16], eax
    mov dword [vrect+20], 1
    mov eax, SYS_GUI_
    mov ebx, VG_READ
    mov ecx, vrect
    int 0x80
    cmp byte [vpix], TH_DESK_
    jne .fail
    mov byte [vwin_ok], 1
    jmp .done
.fail:
    mov byte [vwin_ok], 0
.done:
    popad
.r:
    ret

vga_tick:
    cmp dword [vwin], -1
    je .r
    cmp byte [vmode], 0x13
    jne .r
    push eax
    push ebx
    mov eax, SYS_GUI_
    mov ebx, VG_TICKS
    int 0x80
    cmp eax, [vticks]
    pop ebx
    pop eax
    je .r
    call vga_flush
.r:
    ret

; ---------- text ----------

vga_text_clear:
    pushad
    mov edi, [vtext]
    test edi, edi
    jz .r
    mov ecx, TXT_COLS*TXT_ROWS
    mov eax, 0x0700
    rep stosw
    mov dword [vcur], 0
    mov byte [vtext_dirty], 1
.r:
    popad
    ret

vga_text_flush:
    cmp dword [vwin], -1
    je .r
    cmp byte [vmode], 0x13
    je .r
    cmp byte [vtext_dirty], 0
    je .r
    mov byte [vtext_dirty], 0
    pushad
    mov dword [vcmd], WD_FILL_
    mov dword [vcmd+4], 0
    mov dword [vcmd+8], 0
    mov dword [vcmd+12], TXT_COLS * CELL_W
    mov dword [vcmd+16], TXT_ROWS * CELL_H
    mov dword [vcmd+20], 0
    mov eax, SYS_WINDRAW_
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    xor edx, edx
.row:
    cmp edx, TXT_ROWS
    jae .flip
    xor ebx, ebx
.col:
    cmp ebx, TXT_COLS
    jae .nr
    mov eax, edx
    imul eax, TXT_COLS
    add eax, ebx
    mov esi, [vtext]
    movzx eax, byte [esi+eax*2]
    test al, al
    jz .nc
    cmp al, 32
    jb .nc
    mov [vch], al
    mov byte [vch+1], 0
    imul eax, ebx, CELL_W
    mov [vcmd+4], eax
    imul eax, edx, CELL_H
    mov [vcmd+8], eax
    mov dword [vcmd], WD_TEXT_
    mov dword [vcmd+12], 0
    mov dword [vcmd+20], 0x0F
    mov dword [vcmd+24], vch
    push edx
    push ebx
    mov eax, SYS_WINDRAW_
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    pop ebx
    pop edx
.nc:
    inc ebx
    jmp .col
.nr:
    inc edx
    jmp .row
.flip:
    mov eax, SYS_WINFLUSH_
    mov ebx, [vwin]
    int 0x80
    popad
.r:
    ret

vga_text_putc:
    cmp dword [vwin], -1
    je .host
    cmp byte [vmode], 0x13
    je .host
    pushad
    call vga_log_char
    movzx edx, word [vcur]
    movzx ecx, word [vcur+2]
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    mov esi, [vtext]
    mov ebx, ecx
    imul ebx, TXT_COLS
    add ebx, edx
    mov [esi+ebx*2], al
    mov ah, [vink]
    mov [esi+ebx*2+1], ah
    mov byte [vtext_dirty], 1
    inc edx
    cmp edx, TXT_COLS
    jb .done
    xor edx, edx
    jmp .lf
.cr:
    xor edx, edx
    jmp .done
.bs:
    test edx, edx
    jz .done
    dec edx
    jmp .done
.lf:
    inc ecx
    cmp ecx, TXT_ROWS
    jb .done
    dec ecx
.done:
    mov [vcur], dx
    mov [vcur+2], cx
    popad
    ret
.host:
    cmp dword [vwin], -1
    je .puts
    push eax
    call vga_log_char
    pop eax
.puts:
    push ebx
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    pop ebx
    ret

vga_log_char:
    pushad
    mov edi, [vlog]
    test edi, edi
    jz .r
    mov ecx, [vlog_n]
    cmp ecx, 4095
    jae .r
    mov [edi+ecx], al
    inc ecx
    mov [vlog_n], ecx
    mov byte [edi+ecx], 0
.r:
    popad
    ret

vga_replay_log:
    pushad
    mov esi, [vlog]
    test esi, esi
    jz .r
    mov ecx, [vlog_n]
    test ecx, ecx
    jz .r
.p:
    lodsb
    push ecx
    push esi
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    pop esi
    pop ecx
    loop .p
    mov dword [vlog_n], 0
.r:
    popad
    ret

vga_report_win:
    cmp byte [vchecked], 0
    je .r
    cmp byte [vreported], 0
    jne .r
    mov byte [vreported], 1
    pushad
    mov ebx, m_win_pass
    cmp byte [vwin_ok], 1
    je .say
    mov ebx, m_win_fail
.say:
    mov eax, SYS_PUTS
    int 0x80
    popad
.r:
    ret

; ---------- teletype / pixels / DAC ----------

vga_tty:
    cmp byte [vmode], 0x13
    jne vga_text_putc
    pushad
    movzx eax, al
    push eax
    call vga_log_char
    pop eax
    movzx edx, word [vcur]
    movzx ecx, word [vcur+2]
    mov bl, [vink]
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    cmp al, 7
    je .done
    call vga_glyph
    mov byte [vneed_blit], 1
    inc edx
    cmp edx, VGA_COLS
    jb .done
    xor edx, edx
    jmp .lf
.cr:
    xor edx, edx
    jmp .done
.bs:
    test edx, edx
    jz .done
    dec edx
    jmp .done
.lf:
    inc ecx
    cmp ecx, VGA_ROWS
    jb .done
    dec ecx
.done:
    mov [vcur], dx
    mov [vcur+2], cx
    popad
    ret

; eax = character, bl = ink, edx = column, ecx = row: one 6 x 8 cell
vga_glyph:
    pushad
    imul edi, ecx, 320*8
    imul edx, 6
    add edi, edx
    add edi, [mem]
    add edi, VGA_SEG*16
    sub eax, 0x20
    cmp eax, 0x7E-0x20
    jbe .ok
    xor eax, eax
.ok:
    imul esi, eax, 7
    add esi, [vfont]
    test bl, bl
    jnz .ink
    mov bl, 15
.ink:
    mov ecx, 8
.row:
    xor eax, eax
    cmp ecx, 1
    je .bits
    lodsb
.bits:
    mov edx, 0x10
    push edi
.px:
    mov byte [edi], 0
    test eax, edx
    jz .bg
    mov [edi], bl
.bg:
    inc edi
    shr edx, 1
    jnz .px
    mov byte [edi], 0
    pop edi
    add edi, 320
    loop .row
    popad
    ret

vga_pixel:
    mov al, [rAX+1]
    cmp al, 0x0C
    je .write
    movzx ecx, word [rCX]
    movzx edx, word [rDX]
    imul edx, 320
    add edx, ecx
    add edx, [mem]
    add edx, VGA_SEG*16
    mov al, [edx]
    mov [rAX], al
    ret
.write:
    movzx ecx, word [rCX]
    movzx edx, word [rDX]
    imul edx, 320
    add edx, ecx
    add edx, [mem]
    add edx, VGA_SEG*16
    mov al, [rAX]
    mov [edx], al
    mov byte [vneed_blit], 1
    ret

vga_key_wait:
    push ebx
    push ecx
    cmp byte [vneed_blit], 0
    je .loop
    mov byte [vneed_blit], 0
    call vga_flush
.loop:
    cmp byte [done], 0
    jne .none
    cmp dword [vwin], -1
    je .none
    mov eax, SYS_WINEVENT_
    mov ebx, vev
    xor ecx, ecx                ; block (winprog pattern)
    int 0x80
    cmp eax, -1
    je .loop
    mov eax, [vev]
    cmp eax, WE_PAINT_
    je .paint
    cmp eax, WE_CLOSE_
    je .close
    cmp eax, WE_KEY_
    jne .loop
    mov eax, [vev+8]
    and eax, 0xFF
    cmp al, 10
    je .cr
    cmp al, 13
    je .cr
    cmp al, 27
    je .esc
    cmp al, 8
    je .bs
    cmp al, 0x80
    jae .loop
    and eax, 0xFF
    pop ecx
    pop ebx
    ret
.paint:
    mov byte [vneed_blit], 1
    mov byte [vtext_dirty], 1
    call vga_flush
    jmp .loop
.close:
    mov byte [done], 1
    mov byte [exit_code], 0
.none:
    xor eax, eax
    pop ecx
    pop ebx
    ret
.cr:
    mov eax, 0x1C0D
    pop ecx
    pop ebx
    ret
.esc:
    mov eax, 0x011B
    pop ecx
    pop ebx
    ret
.bs:
    mov eax, 0x0E08
    pop ecx
    pop ebx
    ret

vga_key:
    cmp dword [vwin], -1
    je .none
    push ebx
    push ecx
    mov eax, SYS_WINEVENT_
    mov ebx, vev
    mov ecx, 1                  ; poll
    int 0x80
    pop ecx
    pop ebx
    cmp eax, 0
    jle .none
    mov eax, [vev]
    cmp eax, WE_KEY_
    jne .none
    mov eax, [vev+8]
    and eax, 0xFF
    ret
.none:
    xor eax, eax
    ret

vga_simple_lut:
    pushad
    xor eax, eax
.s:
    mov [vlut+eax], al
    inc eax
    cmp eax, 256
    jb .s
    mov esi, vga_ega16
    mov edi, vdac
    mov ecx, 16*3
    rep movsb
    popad
    ret

vga_dac:
    mov al, [rAX]
    cmp al, 0x15
    jne .r
    movzx ebx, word [rBX]
    lea esi, [vdac+ebx*2]
    add esi, ebx
    mov dh, [esi]
    mov ch, [esi+1]
    mov cl, [esi+2]
    mov [rDX+1], dh
    mov [rCX+1], ch
    mov [rCX], cl
.r:
    ret

vga_in:
    mov dx, [rDX]
    cmp dx, 0x3DA
    jne .ff
    xor byte [vretrace], 8
    mov al, [vretrace]
    mov [rAX], al
    ret
.ff:
    mov byte [rAX], 0xFF
    ret

vga_out:
    mov dx, [rDX]
    cmp dx, 0x3C8
    je .idx
    cmp dx, 0x3C9
    je .rgb
    ret
.idx:
    mov al, [rAX]
    mov [vdac_idx], al
    mov byte [vdac_rgb], 0
    ret
.rgb:
    movzx ebx, byte [vdac_idx]
    lea edi, [vdac+ebx*2]
    add edi, ebx
    movzx ecx, byte [vdac_rgb]
    mov al, [rAX]
    mov [edi+ecx], al
    inc ecx
    cmp ecx, 3
    jb .n
    xor ecx, ecx
    inc byte [vdac_idx]
.n:
    mov [vdac_rgb], cl
    ret

vga_ega16 db 0,0,0, 0,0,42, 0,42,0, 0,42,42, 42,0,0, 42,0,42, 42,21,0, 42,42,42
          db 21,21,21, 21,21,63, 21,63,21, 21,63,63, 63,21,21, 63,21,63, 63,63,21, 63,63,63
t_gfx db 'DOS 320x200', 0
t_text db 'DOS', 0
m_win_pass db 'doswin: PASS', 10, 0
m_win_fail db 'doswin: FAIL', 10, 0
align 4, db 0
vrect dd 0, 0, 320, 200, 0, 320
vmode db 3
vink db 15
vchecked db 0
vwin_ok db 0
vreported db 0
vtext_dirty db 0
vneed_blit db 0
vwant db 0
vpix db 0
vch db 0, 0
align 4, db 0
vslice dd VGA_SLICE
vwin dd -1                      ; 0 is a valid window id
vscale dd 1
vframe2 dd 0
vdrawrc dd 0
vtitle dd t_text
vtext dd 0
vlog dd 0
vlog_n dd 0
align 4
vopen dd 0, 0, 0, 0, 0, 0
vinfo dd 0, 0, 0, 0
vcmd dd 0, 0, 0, 0, 0, 0, 0
vev dd 0, 0, 0, 0
