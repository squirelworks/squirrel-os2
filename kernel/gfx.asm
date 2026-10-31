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
