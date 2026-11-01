; Squirrel-OS/2 — pixel canvas for draw (1.6.5)
; Included from pm.asm. Original code.
;
; 'g' in draw opens an 80 x 50 pixel canvas, shown three times larger in
; graphics mode (or over the desktop, which is in graphics mode already).
; The image is one colour byte per pixel in a page from pg_alloc, after a
; 6-byte header ('SQPX', width, height); that page is also the file.
; drawpx is the self-check. See documentation/apps/draw.md.

DP_W        equ 80
DP_H        equ 50
DP_S        equ 3                   ; screen pixels per canvas pixel
DP_X0       equ (GFX_W - DP_W * DP_S) / 2
DP_Y0       equ 24
DP_HDR      equ 6
DP_FILE     equ DP_HDR + DP_W * DP_H
DP_PAPER    equ 0x3F                ; white (bright colours are 0x38-0x3F)
DP_BG       equ 0x01                ; around the canvas
DP_CURSOR   equ 0x3C                ; light red

; Opens the canvas from draw. The image is loaded from <drawing>.px
; (drawing.px when the drawing has no name) and saved there with F2.
dp_run:
    pushad
    call pg_alloc
    test eax, eax
    jz .out
    mov [dp_page], eax
    call dp_mkname
    call dp_new
    call dp_load
    mov eax, [kbd_wait_hook]    ; the desktop's refresh would paint over us
    mov [dp_hook], eax
    mov dword [kbd_wait_hook], 0
    mov byte [dp_own], 0
    cmp byte [gfx_saved], 0
    jne .go                     ; already in graphics mode (the desktop)
    call gfx_mode13
    jc .back
    mov byte [dp_own], 1
.go:
    mov dword [dp_msg], dp_m_ready
.loop:
    call dp_render
    call fb_waitkey
    call dp_key
    jnc .loop
    cmp byte [dp_own], 0
    je .back
    call gfx_text
.back:
    mov eax, [dp_hook]
    mov [kbd_wait_hook], eax
    mov byte [txt_dirty], 1     ; a desktop window draws itself again
    mov eax, [dp_page]
    call pg_free
.out:
    popad
    ret

; dp_name = dr_name + '.px', or drawing.px
dp_mkname:
    mov esi, dr_name
    mov edi, dp_name
    cmp byte [esi], 0
    jne .copy
    mov esi, dp_default
    mov ecx, 11
    rep movsb
    ret
.copy:
    mov ecx, FS_PATHMAX - 4
.c:
    lodsb
    test al, al
    jz .ext
    stosb
    loop .c
.ext:
    mov eax, '.px'              ; with its terminating zero
    stosd
    ret

; A blank image in [dp_page]
dp_new:
    pushad
    mov edi, [dp_page]
    mov dword [edi], 'SQPX'
    mov byte [edi+4], DP_W
    mov byte [edi+5], DP_H
    add edi, DP_HDR
    mov ecx, DP_W * DP_H
    mov al, DP_PAPER
    rep stosb
    mov dword [dp_x], DP_W / 2
    mov dword [dp_y], DP_H / 2
    mov byte [dp_pen], 0
    mov byte [dp_ink], 0
    popad
    ret

; Loads dp_name into [dp_page] if it is a canvas file -> CF set if not
dp_load:
    pushad
    cmp byte [fs_mounted], 0
    je .no
    mov esi, dp_name
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .no
    mov ebx, eax
    mov edi, DR_FILEBUF         ; read aside: a wrong file leaves the image
    mov ecx, DP_FILE
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, DP_FILE
    jne .no
    cmp dword [DR_FILEBUF], 'SQPX'
    jne .no
    cmp word [DR_FILEBUF+4], DP_W | (DP_H << 8)
    jne .no
    mov esi, DR_FILEBUF
    mov edi, [dp_page]
    mov ecx, DP_FILE
    rep movsb
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; Saves [dp_page] as dp_name -> CF set if it failed
dp_save:
    pushad
    cmp byte [fs_mounted], 0
    je .no
    mov esi, dp_name
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .no
    mov ebx, eax
    mov esi, [dp_page]
    mov ecx, DP_FILE
    call fs_write
    mov edx, eax
    call fs_close
    cmp edx, DP_FILE
    jne .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; al = scan code -> CF set for Esc (close the canvas)
dp_key:
    pushad
    cmp al, 0x01
    je .quit
    cmp al, 0x3C                ; F2
    je .save
    cmp al, 0x48
    je .up
    cmp al, 0x50
    je .down
    cmp al, 0x4B
    je .left
    cmp al, 0x4D
    je .right
    cmp al, 0x39                ; Space
    je .plot
    cmp al, 0x0E                ; Backspace
    je .erase
    cmp al, 0x2D                ; x
    je .erase
    cmp al, 0x19                ; p
    je .pen
    cmp al, 0x2E                ; c
    je .colour
    jmp .out
.up:
    cmp dword [dp_y], 0
    je .out
    dec dword [dp_y]
    jmp .moved
.down:
    cmp dword [dp_y], DP_H - 1
    jae .out
    inc dword [dp_y]
    jmp .moved
.left:
    cmp dword [dp_x], 0
    je .out
    dec dword [dp_x]
    jmp .moved
.right:
    cmp dword [dp_x], DP_W - 1
    jae .out
    inc dword [dp_x]
.moved:
    cmp byte [dp_pen], 0
    je .out
.plot:
    movzx eax, byte [dp_ink]
    mov al, [dp_inks+eax]
    jmp .set
.erase:
    mov al, DP_PAPER
.set:
    mov edi, [dp_y]
    imul edi, DP_W
    add edi, [dp_x]
    add edi, [dp_page]
    mov [edi+DP_HDR], al
    jmp .out
.pen:
    xor byte [dp_pen], 1
    mov dword [dp_msg], dp_m_penup
    cmp byte [dp_pen], 0
    je .out
    mov dword [dp_msg], dp_m_pendown
    jmp .plot                   ; the stroke starts here
.colour:
    inc byte [dp_ink]
    cmp byte [dp_ink], DP_INKS
    jb .out
    mov byte [dp_ink], 0
    jmp .out
.save:
    call dp_save
    mov dword [dp_msg], dp_m_saved
    jnc .out
    mov dword [dp_msg], dp_m_nosave
.out:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; Draws the whole screen: title, message, canvas, cursor, keys
dp_render:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
    mov byte [gfx_colour], DP_BG
    call gfx_fillrect
    mov byte [gfx_colour], DP_PAPER
    mov byte [gfx_bg], DP_BG
    mov eax, 4
    mov ebx, 3
    mov esi, dp_t_title
    call gfx_drawstr
    mov eax, 4 + 8 * GFX_CELL_W
    mov esi, dp_name
    call gfx_drawstr
    mov eax, 4
    mov ebx, 12
    mov esi, [dp_msg]
    call gfx_drawstr
    mov eax, 4
    mov ebx, DP_Y0 + DP_H * DP_S + 4
    mov esi, dp_t_keys
    call gfx_drawstr
    ; the ink: a swatch at the right of the title
    movzx eax, byte [dp_ink]
    mov al, [dp_inks+eax]
    mov [gfx_colour], al
    mov eax, GFX_W - 16
    mov ebx, 3
    mov ecx, 12
    mov edx, FONT_H
    call gfx_fillrect
    ; frame and pixels
    mov byte [gfx_colour], 0x00
    mov eax, DP_X0 - 1
    mov ebx, DP_Y0 - 1
    mov ecx, DP_W * DP_S + 2
    mov edx, DP_H * DP_S + 2
    call gfx_fillrect
    mov esi, [dp_page]
    add esi, DP_HDR
    xor ebp, ebp                ; canvas y
.row:
    xor edi, edi                ; canvas x
.px:
    lodsb
    mov [gfx_colour], al
    mov eax, edi
    imul eax, DP_S
    add eax, DP_X0
    mov ebx, ebp
    imul ebx, DP_S
    add ebx, DP_Y0
    mov ecx, DP_S
    mov edx, DP_S
    call gfx_fillrect
    inc edi
    cmp edi, DP_W
    jb .px
    inc ebp
    cmp ebp, DP_H
    jb .row
    ; the cursor: a ring around its pixel
    mov byte [gfx_colour], DP_CURSOR
    mov eax, [dp_x]
    imul eax, DP_S
    add eax, DP_X0 - 1
    mov ebx, [dp_y]
    imul ebx, DP_S
    add ebx, DP_Y0 - 1
    mov ecx, DP_S + 2
    mov edx, 1
    call gfx_fillrect           ; top
    add ebx, DP_S + 1
    call gfx_fillrect           ; bottom
    sub ebx, DP_S
    mov ecx, 1
    mov edx, DP_S
    call gfx_fillrect           ; left
    add eax, DP_S + 1
    call gfx_fillrect           ; right
    popad
    ret

; drawpx: a stroke, read back off the screen, then saved, cleared and
; loaded again. Needs the data disk.
cmd_drawpx_run:
    call pg_alloc
    test eax, eax
    jz .nomem
    mov [dp_page], eax
    mov esi, dp_selfname
    mov edi, dp_name
    mov ecx, 10
    rep movsb
    call dp_new
    call gfx_mode13
    jc .nomemp
    mov byte [dp_ok], 1
    mov dword [dp_msg], dp_m_ready
    mov dword [dp_x], 10
    mov dword [dp_y], 20
    mov al, 0x2E                ; c: the second ink (red)
    call dp_key
    mov al, 0x19                ; p: pen down
    call dp_key
    mov ecx, 4
.stroke:
    mov al, 0x4D                ; right, drawing
    call dp_key
    loop .stroke
    call dp_render
    mov dl, 0x04
    call dp_probe               ; (12, 20) on the stroke
    mov eax, 12
    mov ebx, 22                 ; below it: still paper
    mov dl, DP_PAPER
    call dp_probe2
    call dp_save
    jnc .saved
    mov byte [dp_ok], 0
.saved:
    call dp_new
    call dp_render
    mov dl, DP_PAPER
    call dp_probe               ; cleared
    call dp_load
    jnc .loaded
    mov byte [dp_ok], 0
.loaded:
    call dp_render
    mov dl, 0x04
    call dp_probe               ; back from the file
    call gfx_text
    mov eax, [dp_page]
    call pg_free
    mov esi, dp_pass
    cmp byte [dp_ok], 1
    je .say
    mov esi, dp_fail
.say:
    jmp puts
.nomemp:
    mov eax, [dp_page]
    call pg_free
.nomem:
    mov esi, dp_nomem
    jmp puts

; dl = expected colour of canvas pixel (12, 20) in the image and on screen
dp_probe:
    mov eax, 12
    mov ebx, 20
; eax, ebx = canvas pixel, dl = expected colour; clears dp_ok on a mismatch
dp_probe2:
    pushad
    mov edi, ebx
    imul edi, DP_W
    add edi, eax
    add edi, [dp_page]
    cmp [edi+DP_HDR], dl
    jne .bad
    imul eax, DP_S
    add eax, DP_X0 + 1          ; the middle of its square
    imul ebx, DP_S
    add ebx, DP_Y0 + 1
    call gfx_getpixel
    cmp cl, dl
    je .ok
.bad:
    mov byte [dp_ok], 0
.ok:
    popad
    ret

DP_INKS equ 6
dp_inks db 0x00, 0x04, 0x02, 0x01, 0x3E, 0x05
dp_default db 'drawing.px', 0
dp_selfname db 'drawpx.px', 0
dp_t_title db 'Pixels:', 0
dp_t_keys db 'Space plot  p pen  x erase  c ink  F2 save  Esc', 0
dp_m_ready db 'Arrows move. Esc goes back to the text canvas.', 0
dp_m_penup db 'Pen up.', 0
dp_m_pendown db 'Pen down: moving draws.', 0
dp_m_saved db 'Saved.', 0
dp_m_nosave db 'Not saved (no data disk, or the name is too long).', 0
dp_pass db 'drawpx: PASS', 10, 0
dp_fail db 'drawpx: FAIL', 10, 0
dp_nomem db 'drawpx: no memory for graphics', 10, 0
align 4
dp_page dd 0
dp_hook dd 0
dp_msg dd 0
dp_x dd 0
dp_y dd 0
dp_pen db 0
dp_ink db 0
dp_own db 0
dp_ok db 0
dp_name times FS_PATHMAX db 0
