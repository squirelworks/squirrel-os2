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

gfx_mode13:
    pushad
    mov esi, gfx_regs_13h
    call gfx_load_regs
    popad
    ret

; Back to 80 x 25 text. The text and the font are where they were: mode 13h
; only touches what the caller wrote (see gfx_putpixel).
gfx_text:
    pushad
    mov esi, gfx_regs_text
    call gfx_load_regs
    call cursor_sync
    popad
    ret

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
