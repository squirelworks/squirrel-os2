; Squirrel-OS/2 — graphics primitives (1.3)
; Included from pm.asm. Original code.
;
; 320 x 200, 256 colours (VGA mode 13h), set by writing the VGA registers
; directly: protected mode has no BIOS. gfx_text puts the 80 x 25 text mode
; back. Pixel (x, y) is the byte at GFX_FB + y * 320 + x.
; See documentation/kernel/graphics.md.

GFX_FB          equ 0xA0000
GFX_W           equ 320
GFX_H           equ 200

; Live framebuffer description (mode 13h by default; VBE updates these).
align 4
gfx_base        dd GFX_FB
gfx_width       dd GFX_W
gfx_height      dd GFX_H
gfx_pitch       dd GFX_W
gfx_bpp         db 8
gfx_vbe         db 0            ; 1 while a VBE linear mode is active
; Clip region (2.1-blit-clip): draws/blit dests limited to
; [gfx_clip_x, gfx_clip_r) x [gfx_clip_y, gfx_clip_b). Mode entry resets
; it to the full screen. gfx_getpixel ignores the clip.
align 4
gfx_clip_x      dd 0
gfx_clip_y      dd 0
gfx_clip_r      dd GFX_W
gfx_clip_b      dd GFX_H

; Register sets: misc output, 5 sequencer, 25 CRTC, 9 graphics
; controller and 21 attribute controller values (standard VGA values for
; each mode).
gfx_regs_13h:
    db 0x63
    db 0x03, 0x01, 0x0F, 0x00, 0x0E
    db 0x5F, 0x4F, 0x50, 0x82, 0x54, 0x80, 0xBF, 0x1F
    db 0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x9C, 0x0E, 0x8F, 0x28, 0x40, 0x96, 0xB9, 0xA3, 0xFF
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x05, 0x0F, 0xFF
    db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
    db 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
    db 0x41, 0x00, 0x0F, 0x00, 0x00

gfx_regs_text:
    db 0x67
    db 0x03, 0x00, 0x03, 0x00, 0x02
    db 0x5F, 0x4F, 0x50, 0x82, 0x55, 0x81, 0xBF, 0x1F
    db 0x00, 0x4F, 0x0D, 0x0E, 0x00, 0x00, 0x00, 0x00
    db 0x9C, 0x0E, 0x8F, 0x28, 0x1F, 0x96, 0xB9, 0xA3, 0xFF
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0E, 0x00, 0xFF
    db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07
    db 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F
    db 0x0C, 0x00, 0x0F, 0x08, 0x00

; esi = register set (above). Clobbers eax, ecx, edx, esi.
gfx_load_regs:
    mov dx, 0x3C2
    lodsb
    out dx, al
    xor ecx, ecx                ; sequencer
.seq:
    mov dx, 0x3C4
    mov al, cl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc ecx
    cmp ecx, 5
    jb .seq
    mov dx, 0x3D4               ; unlock CRTC 0-7: clear bit 7 of reg 0x11
    mov al, 0x11
    out dx, al
    inc dx
    in al, dx
    and al, 0x7F
    out dx, al
    xor ecx, ecx
.crtc:
    mov dx, 0x3D4
    mov al, cl
    out dx, al
    inc dx
    lodsb
    cmp ecx, 0x11
    jne .crtc_out
    and al, 0x7F                ; keep them unlocked while we write
.crtc_out:
    out dx, al
    inc ecx
    cmp ecx, 25
    jb .crtc
    xor ecx, ecx                ; graphics controller
.gc:
    mov dx, 0x3CE
    mov al, cl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc ecx
    cmp ecx, 9
    jb .gc
    mov dx, 0x3DA               ; attribute controller: reset the flip-flop
    in al, dx
    xor ecx, ecx
.ac:
    mov dx, 0x3C0
    mov al, cl
    out dx, al
    lodsb
    out dx, al
    inc ecx
    cmp ecx, 21
    jb .ac
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, 0x20                ; video on again
    out dx, al
    ret

; Since 1.3.3 the switch saves the text screen and the font, which share
; video memory with the graphics, in GFX_SAVE_PAGES pages from pg_alloc, and
; gfx_text puts them back, so a caller may draw anywhere. CF set (and still
; in text mode) when there are no pages for the copy.
gfx_mode13:
    pushad
    call gfx_save
    jc .r
    mov esi, gfx_regs_13h
    call gfx_load_regs
    mov dword [gfx_base], GFX_FB
    mov dword [gfx_width], GFX_W
    mov dword [gfx_height], GFX_H
    mov dword [gfx_pitch], GFX_W
    mov byte [gfx_bpp], 8
    mov byte [gfx_vbe], 0
    call gfx_resetclip
    clc
.r:
    popad
    ret

; Back to 80 x 25 text, with the text and the font as they were.
gfx_text:
    pushad
    cmp byte [gfx_vbe], 0
    je .regs
    call vbe_disable            ; leave a linear mode before VGA text regs
.regs:
    mov esi, gfx_regs_text
    call gfx_load_regs
    call gfx_restore
    mov dword [gfx_base], GFX_FB
    mov dword [gfx_width], GFX_W
    mov dword [gfx_height], GFX_H
    mov dword [gfx_pitch], GFX_W
    mov byte [gfx_bpp], 8
    mov byte [gfx_vbe], 0
    call gfx_resetclip
    call cursor_sync
    popad
    ret

; ---------- clip region (2.1-blit-clip) ----------
; Reset clip to the full live mode. Keeps registers.
gfx_resetclip:
    push eax
    xor eax, eax
    mov [gfx_clip_x], eax
    mov [gfx_clip_y], eax
    mov eax, [gfx_width]
    mov [gfx_clip_r], eax
    mov eax, [gfx_height]
    mov [gfx_clip_b], eax
    pop eax
    ret

; eax=x ebx=y ecx=w edx=h. Clip = rect ∩ screen (empty if none). Keeps regs.
gfx_setclip:
    pushad
    test ecx, ecx
    jle .empty
    test edx, edx
    jle .empty
    test eax, eax
    jns .x0
    add ecx, eax
    xor eax, eax
    test ecx, ecx
    jle .empty
.x0:
    test ebx, ebx
    jns .y0
    add edx, ebx
    xor ebx, ebx
    test edx, edx
    jle .empty
.y0:
    cmp eax, [gfx_width]
    jae .empty
    cmp ebx, [gfx_height]
    jae .empty
    lea esi, [eax+ecx]
    cmp esi, [gfx_width]
    jbe .w_ok
    mov ecx, [gfx_width]
    sub ecx, eax
.w_ok:
    lea esi, [ebx+edx]
    cmp esi, [gfx_height]
    jbe .h_ok
    mov edx, [gfx_height]
    sub edx, ebx
.h_ok:
    test ecx, ecx
    jle .empty
    test edx, edx
    jle .empty
    mov [gfx_clip_x], eax
    mov [gfx_clip_y], ebx
    add eax, ecx
    mov [gfx_clip_r], eax
    add ebx, edx
    mov [gfx_clip_b], ebx
    popad
    ret
.empty:
    xor eax, eax
    mov [gfx_clip_x], eax
    mov [gfx_clip_y], eax
    mov [gfx_clip_r], eax
    mov [gfx_clip_b], eax
    popad
    ret

; ---------- keeping the text screen (1.3.3) ----------
; Page 0 holds the 4000 bytes of text from 0xB8000. Pages 1 and 2 hold the
; 8 KB of font in plane 2, read and written through 0xA0000 with plane 2
; selected and odd/even addressing off (gfx_plane2).
GFX_SAVE_PAGES equ 3
GFX_TEXT_BYTES equ 80 * 25 * 2
GFX_FONT_BYTES equ 8192

gfx_save:
    xor ebx, ebx
.a:
    call pg_alloc
    mov [gfx_pages+ebx*4], eax
    test eax, eax
    jz .nomem
    inc ebx
    cmp ebx, GFX_SAVE_PAGES
    jb .a
    mov esi, 0xB8000
    mov edi, [gfx_pages]
    mov ecx, GFX_TEXT_BYTES / 4
    rep movsd
    call gfx_plane2
    mov esi, 0xA0000
    mov edi, [gfx_pages+4]
    mov ecx, 4096 / 4
    rep movsd
    mov edi, [gfx_pages+8]
    mov ecx, (GFX_FONT_BYTES - 4096) / 4
    rep movsd
    call gfx_plane2_off
    mov byte [gfx_saved], 1
    clc
    ret
.nomem:
    call gfx_free_pages
    stc
    ret

; In text mode again: the font back into plane 2, then the text.
gfx_restore:
    cmp byte [gfx_saved], 0
    je .r
    call gfx_plane2
    mov esi, [gfx_pages+4]
    mov edi, 0xA0000
    mov ecx, 4096 / 4
    rep movsd
    mov esi, [gfx_pages+8]
    mov ecx, (GFX_FONT_BYTES - 4096) / 4
    rep movsd
    call gfx_plane2_off
    mov esi, [gfx_pages]
    mov edi, 0xB8000
    mov ecx, GFX_TEXT_BYTES / 4
    rep movsd
    mov byte [gfx_saved], 0
    call gfx_free_pages
.r:
    ret

gfx_free_pages:
    xor ebx, ebx
.f:
    mov eax, [gfx_pages+ebx*4]
    test eax, eax
    jz .n
    call pg_free
    mov dword [gfx_pages+ebx*4], 0
.n:
    inc ebx
    cmp ebx, GFX_SAVE_PAGES
    jb .f
    ret

; Plane 2 alone at 0xA0000, for reading and writing (from text mode)
gfx_plane2:
    mov dx, 0x3C4
    mov ax, 0x0402              ; map mask: plane 2 only
    out dx, ax
    mov ax, 0x0604              ; memory mode: sequential, no odd/even
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0204              ; read map: plane 2
    out dx, ax
    mov ax, 0x0005              ; mode: write mode 0, read mode 0
    out dx, ax
    mov ax, 0x0406              ; misc: 0xA0000, 64 KB, no odd/even
    out dx, ax
    ret

; the text-mode values of the same registers (gfx_regs_text)
gfx_plane2_off:
    mov dx, 0x3C4
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0204
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06
    out dx, ax
    ret

gfx_saved db 0
align 4
gfx_pages times GFX_SAVE_PAGES dd 0

; eax = x, ebx = y, cl = colour. Pixels outside the clip are ignored
; (clip is inside the screen after setclip/resetclip).
; 8 bpp: one byte at gfx_base + y * pitch + x.
; 16 bpp: a word; cl is the low byte (blue-ish), high byte 0.
; 32 bpp: a dword 0x000000|cl (blue channel); other channels stay 0.
; In mode 13h byte n of the window lands in plane n & 3. The text lives in
; planes 0 and 1 below 4000 and the font in plane 2, so drawing over them
; changes the text screen; gfxtest uses a pixel clear of both.
gfx_putpixel:
    cmp eax, [gfx_clip_x]
    jb .r
    cmp eax, [gfx_clip_r]
    jae .r
    cmp ebx, [gfx_clip_y]
    jb .r
    cmp ebx, [gfx_clip_b]
    jae .r
    push eax
    push ebx
    push edx
    imul ebx, [gfx_pitch]
    add ebx, [gfx_base]
    cmp byte [gfx_bpp], 32
    je .b32
    cmp byte [gfx_bpp], 16
    je .b16
    mov [ebx+eax], cl
    jmp .done
.b16:
    lea edx, [eax*2]
    movzx eax, cl
    mov [ebx+edx], ax
    jmp .done
.b32:
    lea edx, [eax*4]
    movzx eax, cl
    mov [ebx+edx], eax
.done:
    pop edx
    pop ebx
    pop eax
.r:
    ret

; eax = x, ebx = y -> cl = colour (0 off screen). At 16/32 bpp, cl is the
; low byte of the pixel. eax and ebx are preserved.
gfx_getpixel:
    push eax
    push ebx
    push edx
    xor ecx, ecx
    cmp eax, [gfx_width]
    jae .done
    cmp ebx, [gfx_height]
    jae .done
    imul ebx, [gfx_pitch]
    add ebx, [gfx_base]
    cmp byte [gfx_bpp], 32
    je .b32
    cmp byte [gfx_bpp], 16
    je .b16
    mov cl, [ebx+eax]
    jmp .done
.b16:
    mov cx, [ebx+eax*2]
    movzx ecx, cl
    jmp .done
.b32:
    mov ecx, [ebx+eax*4]
    movzx ecx, cl
.done:
    pop edx
    pop ebx
    pop eax
    ret

; gfxtest: mode 13h, write two colours to one pixel and read each back,
; then text mode again and the verdict.
GFXT_X equ 160                  ; byte 32160: plane 0, past the text
GFXT_Y equ 100

cmd_gfxtest_run:
    call gfx_mode13
    mov byte [gfxt_ok], 1
    mov cl, 0x2A
    call .one
    mov cl, 0x15
    call .one
    call gfx_text
    mov esi, gfxt_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, gfxt_fail
.say:
    jmp puts
.one:
    mov dl, cl
    mov eax, GFXT_X
    mov ebx, GFXT_Y
    call gfx_putpixel
    call gfx_getpixel
    cmp cl, dl
    je .same
    mov byte [gfxt_ok], 0
.same:
    ret

gfxt_ok db 0
gfxt_pass db 'gfxtest: PASS', 10, 0
gfxt_fail db 'gfxtest: FAIL', 10, 0

; ---------- lines and rectangles (1.3.1) ----------

; eax = x0, ebx = y0, ecx = x1, edx = y1, colour in [gfx_colour].
; Bresenham: every step moves x, y or both by one toward the end, so the
; line is unbroken in any direction. Off-screen pixels are skipped.
gfx_line:
    pushad
    mov [gl_x], eax
    mov [gl_y], ebx
    mov [gl_x1], ecx
    mov [gl_y1], edx
    mov esi, 1                  ; sx
    sub ecx, eax
    jge .dxpos
    neg ecx
    neg esi
.dxpos:
    mov [gl_dx], ecx            ; |x1 - x0|
    mov edi, 1                  ; sy
    sub edx, ebx
    jge .dypos
    neg edx
    neg edi
.dypos:
    neg edx
    mov [gl_dy], edx            ; -|y1 - y0|
    add ecx, edx
    mov [gl_err], ecx
.plot:
    mov eax, [gl_x]
    mov ebx, [gl_y]
    mov cl, [gfx_colour]
    call gfx_putpixel
    cmp eax, [gl_x1]
    jne .step
    cmp ebx, [gl_y1]
    je .done
.step:
    mov edx, [gl_err]
    add edx, edx                ; e2 = 2 * err
    cmp edx, [gl_dy]
    jl .noxstep
    mov ecx, [gl_dy]
    add [gl_err], ecx
    add [gl_x], esi
.noxstep:
    cmp edx, [gl_dx]
    jg .plot
    mov ecx, [gl_dx]
    add [gl_err], ecx
    add [gl_y], edi
    jmp .plot
.done:
    popad
    ret

; eax = x, ebx = y, ecx = width, edx = height, colour in [gfx_colour].
; Fills the rectangle clipped to the current clip region. x and y may be
; negative: the edges are compared signed.
gfx_fillrect:
    pushad
    lea esi, [eax+ecx]          ; right edge (exclusive)
    lea edi, [ebx+edx]          ; bottom edge (exclusive)
    cmp esi, [gfx_clip_r]
    jle .wok
    mov esi, [gfx_clip_r]
.wok:
    cmp edi, [gfx_clip_b]
    jle .hok
    mov edi, [gfx_clip_b]
.hok:
    cmp eax, [gfx_clip_x]
    jge .xok
    mov eax, [gfx_clip_x]
.xok:
    cmp ebx, [gfx_clip_y]
    jge .yok
    mov ebx, [gfx_clip_y]
.yok:
    mov edx, eax                ; left edge
.row:
    cmp ebx, edi
    jge .done
    mov eax, edx
.col:
    cmp eax, esi
    jge .next
    mov cl, [gfx_colour]
    call gfx_putpixel
    inc eax
    jmp .col
.next:
    inc ebx
    jmp .row
.done:
    popad
    ret

; ---------- blitter (2.1-blit-clip) ----------
; eax,ebx = dest; ecx,edx = size; esi,edi = source (same buffer).
; Dest clipped to clip region; source must stay on-screen and must not
; overlap dest. Marks dirty when vbe_dbl is set.
gfx_blit:
    pushad
    test ecx, ecx
    jle .done
    test edx, edx
    jle .done
    mov ebp, [gfx_clip_x]
    cmp eax, ebp
    jge .dx
    sub ebp, eax
    add esi, ebp
    add eax, ebp
    sub ecx, ebp
    jle .done
.dx:
    mov ebp, [gfx_clip_y]
    cmp ebx, ebp
    jge .dy
    sub ebp, ebx
    add edi, ebp
    add ebx, ebp
    sub edx, ebp
    jle .done
.dy:
    lea ebp, [eax+ecx]
    cmp ebp, [gfx_clip_r]
    jle .dr
    mov ecx, [gfx_clip_r]
    sub ecx, eax
    jle .done
.dr:
    lea ebp, [ebx+edx]
    cmp ebp, [gfx_clip_b]
    jle .db
    mov edx, [gfx_clip_b]
    sub edx, ebx
    jle .done
.db:
    cmp esi, [gfx_width]
    jae .done
    cmp edi, [gfx_height]
    jae .done
    lea ebp, [esi+ecx]
    cmp ebp, [gfx_width]
    jbe .sw
    mov ecx, [gfx_width]
    sub ecx, esi
    jle .done
.sw:
    lea ebp, [edi+edx]
    cmp ebp, [gfx_height]
    jbe .go
    mov edx, [gfx_height]
    sub edx, edi
    jle .done
.go:
    mov [gb_dx], eax
    mov [gb_dy], ebx
    mov [gb_dw], ecx
    mov [gb_dh], edx
    movzx ebp, byte [gfx_bpp]
    shr ebp, 3
    mov eax, esi
    mov ebx, edi
    mov esi, [gfx_base]
    mov edi, esi
    imul ebx, [gfx_pitch]
    add esi, ebx
    imul eax, ebp
    add esi, eax
    mov eax, [gb_dy]
    imul eax, [gfx_pitch]
    add edi, eax
    mov eax, [gb_dx]
    imul eax, ebp
    add edi, eax
    mov eax, [gb_dw]
    imul eax, ebp
    mov edx, [gb_dh]
    mov ebx, [gfx_pitch]
.row:
    mov ecx, eax
    push esi
    push edi
    push eax
    shr ecx, 2
    rep movsd
    mov ecx, [esp]
    and ecx, 3
    rep movsb
    pop eax
    pop edi
    pop esi
    add esi, ebx
    add edi, ebx
    dec edx
    jnz .row
    cmp byte [vbe_dbl], 0
    je .done
    mov eax, [gb_dx]
    mov ebx, [gb_dy]
    mov ecx, [gb_dw]
    mov edx, [gb_dh]
    call vbe_dirty
.done:
    popad
    ret

gb_dx dd 0
gb_dy dd 0
gb_dw dd 0
gb_dh dd 0

; gfxprim: clears the lower part of the screen, draws a line and two filled
; rectangles there (the second starting at x = -10) and reads back pixels on
; the line, inside each rectangle and just outside them. Everything stays
; at y >= GFX_SAFE_Y, past the text and the font (graphics.md).
GFX_SAFE_Y equ 103

cmd_gfxprim_run:
    call gfx_mode13
    mov byte [gfxt_ok], 1
    mov byte [gfx_colour], 0
    xor eax, eax
    mov ebx, GFX_SAFE_Y
    mov ecx, GFX_W
    mov edx, GFX_H - GFX_SAFE_Y
    call gfx_fillrect
    mov byte [gfx_colour], 0x0C
    mov eax, 20                 ; slope 1/4: passes through (160, 155)
    mov ebx, 120
    mov ecx, 300
    mov edx, 190
    call gfx_line
    mov byte [gfx_colour], 0x0A
    mov eax, 200                ; x 200..259, y 105..124
    mov ebx, 105
    mov ecx, 60
    mov edx, 20
    call gfx_fillrect
    mov byte [gfx_colour], 0x09
    mov eax, -10                ; starts off the left edge: x 0..9 drawn
    mov ebx, 130                ; y 130..139
    mov ecx, 20
    mov edx, 10
    call gfx_fillrect
    mov esi, gfxp_expect
.check:
    lodsd
    cmp eax, -1
    je .end
    mov ebx, [esi]
    mov dl, [esi+4]
    add esi, 5
    call gfx_getpixel
    cmp cl, dl
    je .check
    mov byte [gfxt_ok], 0
    jmp .check
.end:
    call gfx_text
    mov esi, gfxp_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, gfxp_fail
.say:
    jmp puts

; x (dd), y (dd), expected colour (db); x = -1 ends the list
gfxp_expect:
    dd 160, 155
    db 0x0C                     ; on the line
    dd 20, 120
    db 0x0C                     ; its first end
    dd 300, 190
    db 0x0C                     ; its last end
    dd 230, 115
    db 0x0A                     ; inside the rectangle
    dd 199, 115
    db 0                        ; just left of it
    dd 260, 115
    db 0                        ; just right of it
    dd 230, 125
    db 0                        ; just below it
    dd 0, 135
    db 0x09                     ; the clipped rectangle at x = 0
    dd 9, 135
    db 0x09                     ; its last column
    dd 10, 135
    db 0                        ; just right of it
    dd -1

gfx_colour db 0
gfxp_pass db 'gfxprim: PASS', 10, 0
gfxp_fail db 'gfxprim: FAIL', 10, 0
align 4
gl_x dd 0
gl_y dd 0
gl_x1 dd 0
gl_y1 dd 0
gl_dx dd 0
gl_dy dd 0
gl_err dd 0

; ---------- text in graphics mode (1.3.2) ----------
; 5 x 7 glyphs from font5x7 (font.inc, built by tools/mkfont.py from
; tools/font5x7.txt). Each character takes a 6 x 8 cell: the glyph, a
; column and a row of background after it.

GFX_CELL_W equ FONT_W + 1
GFX_CELL_H equ FONT_H + 1

; eax = x, ebx = y (top left of the cell), dl = character.
; Ink in [gfx_colour], background in [gfx_bg]. A code outside the font
; draws as '?'.
gfx_drawchar:
    pushad
    movzx esi, dl
    cmp esi, FONT_FIRST
    jb .unknown
    cmp esi, FONT_LAST
    jbe .known
.unknown:
    mov esi, '?'
.known:
    sub esi, FONT_FIRST
    imul esi, FONT_H
    add esi, font5x7
    mov edi, eax                ; left edge
    xor edx, edx                ; row
.row:
    xor ebp, ebp                ; column
    mov dh, 0                   ; the row's bits; row FONT_H is all background
    cmp dl, FONT_H
    jae .bits
    mov dh, [esi]
    inc esi
.bits:
    lea eax, [edi+ebp]
    mov ecx, 8 + FONT_W - 1     ; dh is bits 8-15 of edx; column 0 is bit 4 of dh
    sub ecx, ebp                ; the spacing column lands on bit 7, which is
    bt edx, ecx                 ; clear: dl, the row number, is below 8
    mov cl, [gfx_bg]
    jnc .put
    mov cl, [gfx_colour]
.put:
    call gfx_putpixel
    inc ebp
    cmp ebp, GFX_CELL_W
    jb .bits
    inc ebx
    inc dl
    cmp dl, GFX_CELL_H
    jb .row
    popad
    ret

; esi = zero-terminated string, eax = x, ebx = y. Colours as gfx_drawchar.
gfx_drawstr:
    pushad
.next:
    mov dl, [esi]
    test dl, dl
    jz .done
    call gfx_drawchar
    add eax, GFX_CELL_W
    inc esi
    jmp .next
.done:
    popad
    ret

; gfxtext: clears the lower part of the screen, draws a string and reads
; back ink and background pixels of its first glyph, the spacing column
; after it, and a pixel left of the string that must stay clear.
GFXX_X equ 40
GFXX_Y equ 140

cmd_gfxtext_run:
    call gfx_mode13
    mov byte [gfxt_ok], 1
    mov byte [gfx_colour], 0
    xor eax, eax
    mov ebx, GFX_SAFE_Y
    mov ecx, GFX_W
    mov edx, GFX_H - GFX_SAFE_Y
    call gfx_fillrect
    mov byte [gfx_colour], 0x0F
    mov byte [gfx_bg], 0x01
    mov esi, gfxx_str
    mov eax, GFXX_X
    mov ebx, GFXX_Y
    call gfx_drawstr
    mov esi, gfxx_expect
.check:
    lodsd
    cmp eax, -1
    je .end
    mov ebx, [esi]
    mov dl, [esi+4]
    add esi, 5
    call gfx_getpixel
    cmp cl, dl
    je .check
    mov byte [gfxt_ok], 0
    jmp .check
.end:
    call gfx_text
    mov esi, gfxx_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, gfxx_fail
.say:
    jmp puts

; 'S' is .#### / #.... / ... : its top row starts with background, then ink
gfxx_expect:
    dd GFXX_X + 1, GFXX_Y
    db 0x0F                     ; ink: top row, second column of 'S'
    dd GFXX_X, GFXX_Y + 1
    db 0x0F                     ; ink: second row, first column
    dd GFXX_X, GFXX_Y
    db 0x01                     ; background: top left corner of 'S'
    dd GFXX_X + FONT_W, GFXX_Y + 1
    db 0x01                     ; background: the spacing column
    dd GFXX_X - 1, GFXX_Y
    db 0                        ; left of the string: untouched
    dd -1

gfxx_str db 'Squirrel-OS/2', 0
gfx_bg db 0
gfxx_pass db 'gfxtext: PASS', 10, 0
gfxx_fail db 'gfxtext: FAIL', 10, 0

%include "font.inc"
