; dosvga.inc — VGA mode 13h and the DOS text screen in a 2.2 window (P.8).
; Original code.
;
; INT 10h AX=0013h opens a program window (SYS_WINOPEN) whose client is the
; 320 x 200 DOS screen at 1x or 2x (WD_BLIT / WD_SBLIT). A000:0000 is the
; program's buffer; dosrun copies it through the colour table when the
; program waits for a key, reads the clock or the retrace port, ends, and
; at least every VGA_SLICE instructions. Keys while the window is focused
; arrive as WE_KEY. Mode 03h (and any other mode) closes the window and
; returns to text. A leading "2x" argument selects scale 2; "win" forces a
; text-mode DOS window (kept until a key after the program ends) so the
; text screen is visible beside the desktop.
;
; Colours: the program's 256-entry DAC goes to the display's entries 64-255
; as they are; entries 0-63 show as the nearest of the fixed 64 EGA colours.
; The BIOS teletype writes into A000 with the kernel's 5 x 7 font in 6 x 8
; cells (53 x 25). Outside the window the desktop is left alone.

SYS_GUI_    equ 35
VG_FONT     equ 6
VG_TICKS    equ 7
VG_PALETTE  equ 11
VGA_SEG     equ 0xA000
VGA_COLS    equ 53
VGA_ROWS    equ 25
VGA_SLICE   equ 200000
TXT_COLS    equ 80
TXT_ROWS    equ 25
WM_TITLE_H_ equ 8               ; FONT_H+1 + 2 = 10 would need theme; frame:
                                ; outer = client + 2 width, + WM_TITLE_H+2 height
                                ; WM_TITLE_H = 7+1+2 = 10
WIN_FRAME_X equ 2
WIN_FRAME_Y equ 12              ; WM_TITLE_H (10) + 2

; INT 10h AH=00h: AL = mode
vga_setmode:
    mov al, [rAX]
    and al, 0x7F
    cmp al, 0x13
    je .gfx
    jmp vga_leave
.gfx:
    cmp byte [vmode], 0x13
    je .clear
    cmp dword [vframe], 0
    jne .have
    mov eax, SYS_SBRK           ; the display copy and the font
    mov ebx, 64000 + 96*7
    int 0x80
    cmp eax, -1
    je .r
    mov [vframe], eax
    add eax, 64000
    mov [vfont], eax
    mov ecx, eax
    mov eax, SYS_GUI_
    mov ebx, VG_FONT
    int 0x80
.have:
    ; mode 13h needs a 320x200 (scaled) window; replace a text window
    cmp byte [vtextwin], 0
    je .open
    mov byte [vhold], 0
    call vga_win_close
    mov byte [vtextwin], 0
.open:
    call vga_win_open
    cmp dword [vwin], -1
    je .r                       ; no window: stay in text
    mov byte [vmode], 0x13
    call vga_default_dac
.clear:
    mov dword [vcur], 0
    test byte [rAX], 0x80       ; bit 7: keep the screen
    jnz .flush
    mov edi, [mem]
    add edi, VGA_SEG*16
    mov ecx, 64000/4
    xor eax, eax
    rep stosd
.flush:
    jmp vga_flush
.r:
    ret

; back to text mode (any mode but 13h, and the program's end)
vga_leave:
    cmp byte [vmode], 0x13
    je .from13
    cmp dword [vwin], -1
    je .r
    ; text window forced with "win": keep it until vga_win_hold finishes
    cmp byte [vhold], 0
    jne .r
    call vga_win_close
.r:
    ret
.from13:
    call vga_flush
    call vga_desk_sample        ; compare outside pixel; report after close
    call vga_win_close
    mov byte [vmode], 3
    call vga_desk_report        ; B800 is back: print doswin: lines
    ret

; open the DOS window at the current scale; title from the program name
vga_win_open:
    cmp dword [vwin], -1
    jne .r
    pushad
    mov eax, 320
    mov ebx, 200
    movzx ecx, byte [vscale]
    cmp byte [vtextwin], 0
    je .sz
    mov eax, TXT_COLS * 6       ; text cells: 6 wide, 10 tall for OCR
    mov ebx, TXT_ROWS * 10
    mov ecx, 1                  ; text window is always 1x (WD_TEXT)
.sz:
    imul eax, ecx
    imul ebx, ecx
    add eax, WIN_FRAME_X        ; outer size
    add ebx, WIN_FRAME_Y
    mov dword [vopen], 40       ; x
    mov dword [vopen+4], 30     ; y
    cmp byte [vtextwin], 0
    jne .pos
    cmp byte [vscale], 2
    jne .pos
    mov dword [vopen], 0        ; 2x: origin so the client stays on screen
    mov dword [vopen+4], 0
.pos:
    mov [vopen+8], eax
    mov [vopen+12], ebx
    mov dword [vopen+16], vtitle
    mov dword [vopen+20], 0     ; WF_DEFAULT
    call vga_set_title
    mov eax, SYS_WINOPEN
    mov ebx, vopen
    int 0x80
    mov [vwin], eax
    cmp eax, -1
    je .no
    mov eax, SYS_WINFLUSH
    mov ebx, [vwin]
    int 0x80
.no:
    popad
.r:
    ret

vga_set_title:
    pushad
    mov esi, exe_name
    mov edi, vtitle
    mov ecx, 28
.cp:
    lodsb
    test al, al
    jz .z
    cmp al, ' '
    je .z
    stosb
    loop .cp
.z:
    mov byte [edi], 0
    cmp byte [vtitle], 0
    jne .r
    mov byte [vtitle], 'D'
    mov byte [vtitle+1], 'O'
    mov byte [vtitle+2], 'S'
    mov byte [vtitle+3], 0
.r:
    popad
    ret

vga_win_close:
    cmp dword [vwin], -1
    je .r
    pushad
    mov eax, SYS_WINCLOSE
    mov ebx, [vwin]
    int 0x80
    mov dword [vwin], -1
    popad
.r:
    ret

; after a "win" text session: redraw, wait for a key, then close
vga_win_hold:
    cmp byte [vhold], 0
    je .r
    cmp dword [vwin], -1
    je .r
    pushad
    call vga_text_flush
.w:
    call vga_key
    test eax, eax
    jnz .d
    mov eax, SYS_YIELD
    int 0x80
    jmp .w
.d:
    mov byte [vhold], 0
    call vga_win_close
    popad
.r:
    ret

; a pixel outside the DOS window, for the "desktop untouched" check.
; Uses a stack rect so it cannot disturb other state; GUI_READ of 1x1.
vga_desk_read:                  ; -> al = colour at (620,460)
    push ebx
    push ecx
    sub esp, 28
    mov dword [esp], 620
    mov dword [esp+4], 460
    mov dword [esp+8], 1
    mov dword [esp+12], 1
    lea eax, [esp+24]
    mov dword [esp+16], eax     ; 1-byte buffer at esp+24
    mov dword [esp+20], 1
    mov byte [esp+24], 0
    mov eax, SYS_GUI_
    mov ebx, 3                  ; GUI_READ
    mov ecx, esp
    int 0x80
    mov al, [esp+24]
    add esp, 28
    pop ecx
    pop ebx
    ret

vga_desk_snap:
    pushad
    call vga_desk_read
    mov [vdesk], al
    mov byte [vdesk_have], 1
    popad
    ret

vga_desk_sample:
    cmp byte [vdesk_have], 0
    je .r
    pushad
    call vga_desk_read
    cmp al, [vdesk]
    sete byte [vdesk_ok]
    popad
.r:
    ret

; after the window has closed (text mode): report desk / scale / pixels
vga_desk_report:
    cmp byte [vdesk_have], 0
    je .r
    pushad
    mov eax, SYS_PUTS
    mov ebx, m_desk
    cmp byte [vdesk_ok], 0
    jne .desk
    mov ebx, m_deskbad
.desk:
    int 0x80
    movzx eax, byte [vscale]
    add al, '0'
    mov [m_scale+14], al        ; "doswin: scale N"
    mov eax, SYS_PUTS
    mov ebx, m_scale
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, m_pix
    cmp byte [vpix_ok], 0
    jne .pix
    mov ebx, m_pixbad
.pix:
    int 0x80
    mov byte [vdesk_have], 0
    mov byte [vpix_ok], 0
    popad
.r:
    ret

; the DAC a VGA starts mode 13h with: 16 EGA colours, 16 greys, then
; 24 hues in nine brightness and saturation steps (made here, not copied)
vga_default_dac:
    pushad
    mov esi, vga_ega16
    mov edi, vdac
    mov ecx, 16*3
    rep movsb
    xor eax, eax                ; 16-31: grey 0 .. 63
.grey:
    imul ebx, eax, 63
    push eax
    mov eax, ebx
    xor edx, edx
    mov ebx, 15
    div ebx
    mov bl, al
    pop eax
    mov [edi], bl
    mov [edi+1], bl
    mov [edi+2], bl
    add edi, 3
    inc eax
    cmp eax, 16
    jb .grey
    xor ebp, ebp                ; 32-255: step 0..8, hue 0..23
.step:
    xor edx, edx
.hue:
    mov eax, edx
    call .ramp
    mov [edi], al
    lea eax, [edx+16]
    call .ramp
    mov [edi+1], al
    lea eax, [edx+8]
    call .ramp
    mov [edi+2], al
    mov ecx, 3
.ch:
    movzx eax, byte [edi+ecx-1]
    mov ebx, ebp
    push edx
    xor edx, edx
    push eax
    mov eax, ebx
    mov ebx, 3
    div ebx                     ; eax = group, edx = paleness
    mov ebx, edx
    mov edx, eax
    pop eax
    imul ebx, 21                ; pale: lift towards white
    push ecx
    mov ecx, 63
    sub ecx, eax
    imul ecx, ebx
    shr ecx, 6
    add eax, ecx
    pop ecx
    mov ebx, 3                  ; dim by the group
    sub ebx, edx
    imul eax, ebx
    xor edx, edx
    push ecx
    mov ecx, 3
    div ecx
    pop ecx
    pop edx
    mov [edi+ecx-1], al
    loop .ch
    add edi, 3
    inc edx
    cmp edx, 24
    jb .hue
    inc ebp
    cmp ebp, 9
    jb .step
    popad
    jmp vga_lut
.ramp:
    push edx
    xor edx, edx
    push ecx
    mov ecx, 24
    div ecx
    pop ecx
    mov eax, edx
    pop edx
    cmp eax, 4
    jb .up
    cmp eax, 12
    jb .full
    cmp eax, 16
    jb .down
    xor eax, eax
    ret
.up:
    imul eax, 16
    ret
.full:
    mov eax, 63
    ret
.down:
    sub eax, 16
    neg eax
    imul eax, 16
    cmp eax, 63
    jbe .d
    mov eax, 63
.d:
    ret

vga_lut:
    pushad
    xor ebx, ebx
.c:
    cmp ebx, 64
    jae .same
    lea esi, [vdac+ebx*2]
    add esi, ebx
    mov ebp, 0x7FFFFFFF
    xor edi, edi
.cand:
    xor edx, edx
    mov ecx, 2
    call .dist
    mov ecx, 1
    call .dist
    xor ecx, ecx
    call .dist
    cmp edx, ebp
    jae .worse
    mov ebp, edx
    mov eax, edi
    mov [vlut+ebx], al
.worse:
    inc edi
    cmp edi, 64
    jb .cand
    jmp .nx
.same:
    mov [vlut+ebx], bl
.nx:
    inc ebx
    cmp ebx, 256
    jb .c
    cmp byte [vmode], 0x13
    jne .r
    mov eax, SYS_GUI_
    mov ebx, VG_PALETTE
    mov ecx, 64 | (192 << 16)
    mov edx, vdac+64*3
    int 0x80
.r:
    popad
    ret
.dist:
    xor eax, eax
    bt edi, ecx
    jnc .lo
    add eax, 42
.lo:
    add ecx, 3
    bt edi, ecx
    jnc .hi
    add eax, 21
.hi:
    sub ecx, 3
    push ebx
    mov ebx, 2
    sub ebx, ecx
    movzx ebx, byte [esi+ebx]
    sub eax, ebx
    pop ebx
    imul eax, eax
    add edx, eax
    ret

; A000 through the LUT into the window at vscale.
; WINFLUSH runs ws_update first; if the window is dirty that paints an empty
; client over the back buffer. Flush once to clear dirty, blit, flush again.
vga_flush:
    cmp byte [vmode], 0x13
    jne .r
    cmp dword [vwin], -1
    je .r
    pushad
    mov esi, [mem]
    add esi, VGA_SEG*16
    mov edi, [vframe]
    test edi, edi
    jz .pop
    mov ecx, 64000
    xor eax, eax
.t:
    lodsb
    mov al, [vlut+eax]
    stosb
    loop .t
    mov eax, SYS_WINFLUSH
    mov ebx, [vwin]
    int 0x80
    mov dword [vcmd], WD_BLIT
    cmp byte [vscale], 1
    je .blit1
    mov dword [vcmd], WD_SBLIT
    movzx eax, byte [vscale]
    mov [vcmd+20], eax
    jmp .cmd
.blit1:
    mov dword [vcmd+20], -1
.cmd:
    mov dword [vcmd+4], 0
    mov dword [vcmd+8], 0
    mov dword [vcmd+12], 320
    mov dword [vcmd+16], 200
    mov eax, [vframe]
    mov [vcmd+24], eax
    mov eax, SYS_WINDRAW
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    mov eax, SYS_WINFLUSH
    mov ebx, [vwin]
    int 0x80
    mov dword [vcmd], WD_PIXEL
    mov dword [vcmd+4], 150
    mov dword [vcmd+8], 130
    cmp byte [vscale], 2
    jne .pix
    mov dword [vcmd+4], 300
    mov dword [vcmd+8], 260
.pix:
    mov eax, SYS_WINDRAW
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    mov edx, [mem]
    movzx edx, byte [edx+VGA_SEG*16+130*320+150]
    mov dl, [vlut+edx]
    cmp al, dl
    jne .ticks
    mov byte [vpix_ok], 1
.ticks:
    mov eax, SYS_GUI_
    mov ebx, VG_TICKS
    int 0x80
    mov [vticks], eax
    mov dword [vslice], VGA_SLICE
    cmp byte [vdesk_have], 0
    jne .pop
    call vga_desk_snap          ; once, after the first successful flush
.pop:
    popad
.r:
    ret

vga_tick:
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

; al = character, bl = colour: the BIOS teletype in graphics
vga_tty:
    pushad
    movzx eax, al
    movzx edx, word [vcur]
    movzx ecx, word [vcur+2]
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    cmp al, 7
    je .done
    call vga_glyph
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
    push ecx
    mov edi, [mem]
    add edi, VGA_SEG*16
    lea esi, [edi+320*8]
    mov ecx, 320*192/4
    rep movsd
    mov ecx, 320*8/4
    xor eax, eax
    rep stosd
    pop ecx
.done:
    mov [vcur], dx
    mov [vcur+2], cx
    popad
    ret

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
    movzx eax, word [rCX]
    movzx edx, word [rDX]
    cmp eax, 320
    jae .r
    cmp edx, 200
    jae .r
    imul edx, 320
    add edx, eax
    add edx, [mem]
    add edx, VGA_SEG*16
    cmp byte [rAX+1], 0x0D
    je .get
    mov al, [rAX]
    mov [edx], al
.r:
    ret
.get:
    mov al, [edx]
    mov [rAX], al
    ret

vga_dac:
    movzx ebx, word [rBX]
    and ebx, 0xFF
    lea edi, [vdac+ebx*2]
    add edi, ebx
    mov al, [rAX]
    cmp al, 0x10
    je .one
    cmp al, 0x15
    je .get1
    cmp al, 0x12
    je .block
    cmp al, 0x17
    je .block
    ret
.one:
    mov al, [rDX+1]
    mov [edi], al
    mov al, [rCX+1]
    mov [edi+1], al
    mov al, [rCX]
    mov [edi+2], al
    jmp .chg
.get1:
    mov al, [edi]
    mov [rDX+1], al
    mov al, [edi+1]
    mov [rCX+1], al
    mov al, [edi+2]
    mov [rCX], al
    ret
.block:
    movzx ecx, word [rCX]
    mov eax, 256
    sub eax, ebx
    cmp ecx, eax
    jbe .n
    mov ecx, eax
.n:
    imul ecx, 3
    mov ax, [sES]
    mov dx, [rDX]
    call lin
    mov esi, eax
    cmp byte [rAX], 0x17
    je .read
    rep movsb
    jmp .chg
.read:
    xchg esi, edi
    rep movsb
    ret
.chg:
    jmp vga_lut

vga_out:
    cmp dx, 0x3C8
    jne .data
    mov [vdac_idx], al
    mov byte [vdac_rgb], 0
    ret
.data:
    cmp dx, 0x3C9
    jne .r
    and al, 63
    movzx ecx, byte [vdac_idx]
    lea ecx, [ecx*2+ecx]
    movzx ebx, byte [vdac_rgb]
    mov [vdac+ecx+ebx], al
    inc ebx
    cmp ebx, 3
    jb .keep
    xor ebx, ebx
    inc byte [vdac_idx]
    call vga_lut
.keep:
    mov [vdac_rgb], bl
.r:
    ret
vga_in:
    cmp dx, 0x3DA
    jne .dac
    xor byte [vretrace], 0x09
    mov al, [vretrace]
    jmp vga_tick
.dac:
    mov al, 0xFF
    cmp dx, 0x3C9
    jne .r
    movzx ecx, byte [vdac_idx]
    lea ecx, [ecx*2+ecx]
    movzx ebx, byte [vdac_rgb]
    mov al, [vdac+ecx+ebx]
    inc ebx
    cmp ebx, 3
    jb .k
    xor ebx, ebx
    inc byte [vdac_idx]
.k:
    mov [vdac_rgb], bl
.r:
    ret

; keys while the DOS window is focused (WE_KEY); also drains WE_PAINT
vga_key:
    cmp dword [vwin], -1
    je .none
    pushad
.again:
    mov eax, SYS_WINEVENT
    mov ebx, vev
    mov ecx, 1                  ; poll
    int 0x80
    cmp eax, -1
    je .none2
    mov eax, [vev]
    cmp eax, WE_PAINT
    je .paint
    cmp eax, WE_CLOSE
    je .close
    cmp eax, WE_KEY
    jne .again
    movzx eax, byte [vev+8]     ; p1: key as wg_key (ASCII)
    cmp al, 10
    jne .got
    mov al, 13
.got:
    mov [esp+28], eax           ; return in eax of popad
    popad
    ret
.paint:
    cmp byte [vmode], 0x13
    je .pg
    call vga_text_flush
    jmp .again
.pg:
    call vga_flush
    jmp .again
.close:
    mov byte [vhold], 0
    call vga_leave
.none2:
    popad
.none:
    xor eax, eax
    ret

; ---------- text-mode DOS window ("win" or already on a VBE desktop) ----------

; open a text window when forced or when the screen is already the wm's
vga_text_maybe:
    cmp dword [vwin], -1
    jne .r
    cmp byte [vwantwin], 0
    jne .open
    ; already on a VBE desktop? SYS_WININFO -1 width >= 640
    pushad
    mov eax, SYS_WININFO
    mov ebx, -1
    mov ecx, vinfo
    int 0x80
    cmp dword [vinfo+8], 640
    popad
    jb .r
.open:
    mov byte [vtextwin], 1
    mov byte [vhold], 1
    call vga_win_open
    cmp dword [vwin], -1
    je .r
    ; clear the text buffer
    mov edi, tbuf
    mov ecx, TXT_COLS*TXT_ROWS
    mov al, ' '
    rep stosb
    mov dword [tcur], 0
    call vga_text_flush
.r:
    ret

; al -> the text buffer and the window (when open)
; tcur is the absolute offset row*TXT_COLS+col (not the column alone).
vga_text_putc:
    cmp dword [vwin], -1
    je .r
    pushad
    movzx eax, al
    mov edx, [tcur]
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    cmp al, 7
    je .done
    cmp edx, TXT_COLS*TXT_ROWS
    jae .done
    mov [tbuf+edx], al
    inc edx
    cmp edx, TXT_COLS*TXT_ROWS
    jb .store
    ; past the last cell: scroll and stay on the last row
    call vga_text_scroll
    mov edx, TXT_COLS*(TXT_ROWS-1)
    jmp .store
.cr:
    mov eax, edx
    xor edx, edx
    mov ecx, TXT_COLS
    div ecx
    imul eax, TXT_COLS
    mov edx, eax
    jmp .store
.bs:
    test edx, edx
    jz .done
    dec edx
    mov byte [tbuf+edx], ' '
    jmp .store
.lf:
    mov eax, edx
    xor edx, edx
    mov ecx, TXT_COLS
    div ecx
    inc eax
    cmp eax, TXT_ROWS
    jb .nl
    call vga_text_scroll
    mov eax, TXT_ROWS-1
.nl:
    imul edx, eax, TXT_COLS
.store:
    mov [tcur], edx
.done:
    call vga_text_flush
    popad
.r:
    ret

vga_text_scroll:
    pushad
    mov esi, tbuf+TXT_COLS
    mov edi, tbuf
    mov ecx, TXT_COLS*(TXT_ROWS-1)
    rep movsb
    mov edi, tbuf+TXT_COLS*(TXT_ROWS-1)
    mov ecx, TXT_COLS
    mov al, ' '
    rep stosb
    popad
    ret

; redraw the text buffer into the window with WD_TEXT per row
vga_text_flush:
    cmp dword [vwin], -1
    je .r
    pushad
    mov eax, SYS_WINFLUSH       ; clear dirty before painting
    mov ebx, [vwin]
    int 0x80
    mov dword [vcmd], WD_FILL
    mov dword [vcmd+4], 0
    mov dword [vcmd+8], 0
    mov dword [vcmd+12], TXT_COLS * 6
    mov dword [vcmd+16], TXT_ROWS * 10
    mov dword [vcmd+20], 0      ; black
    mov eax, SYS_WINDRAW
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
    xor ebx, ebx                ; row (not ebp: keep a stable counter)
    mov [trow], ebx
.row:
    mov ebx, [trow]
    cmp ebx, TXT_ROWS
    jae .flip
    mov esi, tbuf
    imul eax, ebx, TXT_COLS
    add esi, eax
    mov edi, tline
    mov ecx, TXT_COLS
    rep movsb
    mov ecx, TXT_COLS
.trim:
    test ecx, ecx
    jz .empty
    cmp byte [tline+ecx-1], ' '
    jne .term
    dec ecx
    jmp .trim
.empty:
.term:
    mov byte [tline+ecx], 0
    test ecx, ecx
    jz .next                    ; blank row: skip
    mov dword [vcmd], WD_TEXT
    mov dword [vcmd+4], 2
    mov eax, [trow]
    imul eax, 10                ; 10 px/row so OCR keeps lines apart
    mov [vcmd+8], eax
    mov dword [vcmd+12], 0      ; black background
    mov dword [vcmd+16], 0
    mov dword [vcmd+20], 0x0F   ; white ink
    mov dword [vcmd+24], tline
    mov eax, SYS_WINDRAW
    mov ebx, [vwin]
    mov ecx, vcmd
    int 0x80
.next:
    inc dword [trow]
    jmp .row
.flip:
    mov eax, SYS_WINFLUSH
    mov ebx, [vwin]
    int 0x80
    popad
.r:
    ret

vga_ega16 db 0,0,0, 0,0,42, 0,42,0, 0,42,42, 42,0,0, 42,0,42, 42,21,0, 42,42,42
          db 21,21,21, 21,21,63, 21,63,21, 21,63,63, 63,21,21, 63,21,63, 63,63,21, 63,63,63
vtitle db 'DOS', 0
       times 28 db 0
m_desk db 'doswin: desk', 10, 0
m_deskbad db 'doswin: desk BAD', 10, 0
m_scale db 'doswin: scale 1', 10, 0
m_pix db 'doswin: pixels', 10, 0
m_pixbad db 'doswin: pixels BAD', 10, 0
; mutable state (vwin, vcmd, vmode, tbuf, ...) lives in dosrun's BSS
