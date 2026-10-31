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
    clc
.r:
    popad
    ret

; Back to 80 x 25 text, with the text and the font as they were.
gfx_text:
    pushad
    mov esi, gfx_regs_text
    call gfx_load_regs
    call gfx_restore
    call cursor_sync
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

; eax = x, ebx = y, cl = colour. Off-screen pixels are ignored.
; In mode 13h byte n of the window lands in plane n & 3. The text lives in
; planes 0 and 1 below 4000 and the font in plane 2, so drawing over them
; changes the text screen; gfxtest uses a pixel clear of both.
gfx_putpixel:
    cmp eax, GFX_W
    jae .r
    cmp ebx, GFX_H
    jae .r
    push ebx
    imul ebx, GFX_W
    mov [GFX_FB+ebx+eax], cl
    pop ebx
.r:
    ret

; eax = x, ebx = y -> cl = colour (0 off screen)
gfx_getpixel:
    xor ecx, ecx
    cmp eax, GFX_W
    jae .r
    cmp ebx, GFX_H
    jae .r
    push ebx
    imul ebx, GFX_W
    mov cl, [GFX_FB+ebx+eax]
    pop ebx
.r:
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
; Fills the rectangle; the part off the screen is clipped.
gfx_fillrect:
    pushad
    lea esi, [eax+ecx]          ; right edge (exclusive)
    lea edi, [ebx+edx]          ; bottom edge (exclusive)
    cmp esi, GFX_W
    jbe .wok
    mov esi, GFX_W
.wok:
    cmp edi, GFX_H
    jbe .hok
    mov edi, GFX_H
.hok:
    mov edx, eax                ; left edge
.row:
    cmp ebx, edi
    jae .done
    mov eax, edx
.col:
    cmp eax, esi
    jae .next
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

; gfxprim: clears the lower part of the screen, draws a line and a filled
; rectangle there and reads back a pixel on the line, one inside the
; rectangle and three just outside it. Everything stays at y >= GFX_SAFE_Y,
; past the text and the font (graphics.md).
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
