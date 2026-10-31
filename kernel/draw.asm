; Squirrel-OS/2 — ASCII drawing program (draw), polished for 0.3.3
; Included from pm.asm. Original code.
;
; 64x18 character canvas drawn in place, pen, brush choice, lines,
; rectangles, flood fill and load/save as a text file.
; See documentation/apps/draw.md.

DR_W        equ 64
DR_H        equ 18
DR_CANVAS   equ KSCRATCH+0x8000     ; DR_W*DR_H bytes
DR_STACK    equ KSCRATCH+0x9000     ; flood-fill work stack (dwords)
DR_STACKMAX equ 0x1400              ; entries: > 1 + 4*DR_W*DR_H, so never full
DR_X0       equ 8                   ; screen column of canvas column 0
DR_Y0       equ 2                   ; screen row of canvas row 0
DR_FILEMAX  equ DR_H*(DR_W+1)

run_draw:
    mov byte [dr_brush], '*'
    mov byte [dr_pen], 0
    mov byte [dr_mode], 0
    mov byte [dr_mod], 0
    mov dword [dr_x], 0
    mov dword [dr_y], 0
    mov dword [ed_msgp], dr_m_help
    mov byte [kbd_ctrl], 0
    call dr_clear
    mov esi, run_arg
    mov edi, dr_name
    mov ecx, FS_PATHMAX
    rep movsb
    mov byte [run_arg], 0
    call dr_load
    call dr_frame
.loop:
    call dr_draw
    call fb_waitkey
    cmp byte [kbd_ctrl], 0
    jne .ctrl
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
    cmp al, 0x39                ; Space: plot
    je .plot
    cmp al, 0x0E                ; Backspace: erase
    je .erase
    call kbd_ascii
    cmp al, 'x'
    je .erase
    cmp al, 'p'
    je .pen
    cmp al, 'b'
    je .brush
    cmp al, 'l'
    je .line
    cmp al, 'r'
    je .rect
    cmp al, 'f'
    je .fill
    cmp al, 'c'
    je .clear
    jmp .loop
.ctrl:
    cmp al, 0x1F
    je .save
    cmp al, 0x10
    je .quit
    jmp .loop
.up:
    cmp dword [dr_y], 0
    je .loop
    dec dword [dr_y]
    jmp .moved
.down:
    cmp dword [dr_y], DR_H-1
    jae .loop
    inc dword [dr_y]
    jmp .moved
.left:
    cmp dword [dr_x], 0
    je .loop
    dec dword [dr_x]
    jmp .moved
.right:
    cmp dword [dr_x], DR_W-1
    jae .loop
    inc dword [dr_x]
.moved:
    cmp byte [dr_pen], 0
    je .loop
.plot:
    mov al, [dr_brush]
    call dr_set_here
    jmp .loop
.erase:
    mov al, ' '
    call dr_set_here
    jmp .loop
.pen:
    xor byte [dr_pen], 1
    mov dword [ed_msgp], dr_m_penup
    cmp byte [dr_pen], 0
    je .loop
    mov dword [ed_msgp], dr_m_pendown
    mov al, [dr_brush]
    call dr_set_here
    jmp .loop
.brush:
    mov dword [ed_msgp], dr_m_brush
    call dr_draw
    call fb_waitkey
    call kbd_ascii
    cmp al, ' '
    jbe .bcancel
    mov [dr_brush], al
    mov dword [ed_msgp], dr_m_brushset
    jmp .loop
.bcancel:
    mov dword [ed_msgp], ed_m_cancel
    jmp .loop
.line:
    mov bl, 1
    jmp .shape
.rect:
    mov bl, 2
.shape:
    ; first press marks a corner, the same key again draws to the cursor
    cmp [dr_mode], bl
    je .finish
    mov [dr_mode], bl
    mov eax, [dr_x]
    mov [dr_mx], eax
    mov eax, [dr_y]
    mov [dr_my], eax
    mov dword [ed_msgp], dr_m_mark
    jmp .loop
.finish:
    mov byte [dr_mode], 0
    cmp bl, 1
    je .doline
    call dr_rect
    jmp .shaped
.doline:
    call dr_line
.shaped:
    mov byte [dr_mod], 1
    mov dword [ed_msgp], dr_m_drawn
    jmp .loop
.fill:
    call dr_fill
    jmp .loop
.clear:
    call dr_clear
    mov byte [dr_mod], 1
    mov dword [ed_msgp], dr_m_cleared
    jmp .loop
.save:
    call dr_save
    jmp .loop
.quit:
    cmp byte [dr_mod], 0
    je .bye
    mov dword [ed_msgp], ed_m_unsaved
    call dr_draw
    call fb_waitkey
    cmp al, 0x1F
    je .savequit
    cmp al, 0x20
    je .bye
    mov dword [ed_msgp], ed_m_cancel
    jmp .loop
.savequit:
    call dr_save
    cmp byte [dr_mod], 0
    jne .loop
.bye:
    call app_home
    xor eax, eax
    ret

; ---------- canvas primitives ----------

dr_clear:
    push ecx
    push edi
    push eax
    mov edi, DR_CANVAS
    mov ecx, DR_W*DR_H
    mov al, ' '
    rep stosb
    pop eax
    pop edi
    pop ecx
    ret

; al = char at the cursor
dr_set_here:
    push ebx
    push ecx
    mov ebx, [dr_x]
    mov ecx, [dr_y]
    call dr_set
    pop ecx
    pop ebx
    mov byte [dr_mod], 1
    ret

; ebx = x, ecx = y, al = char (ignored outside the canvas)
dr_set:
    cmp ebx, DR_W
    jae .out
    cmp ecx, DR_H
    jae .out
    push ecx
    imul ecx, DR_W
    mov [DR_CANVAS+ecx+ebx], al
    pop ecx
.out:
    ret

; rectangle outline from the mark to the cursor with the brush
dr_rect:
    pushad
    call dr_order                ; ebx..edx = x0,y0,x1,y1 sorted
    mov al, [dr_brush]
    mov esi, ebx
.h:                             ; top and bottom edges
    push ebx
    push ecx
    mov ebx, esi
    call dr_set
    mov ecx, [dr_y1]
    call dr_set
    pop ecx
    pop ebx
    inc esi
    cmp esi, [dr_x1]
    jbe .h
    mov esi, ecx
.v:                             ; left and right edges
    push ecx
    mov ecx, esi
    call dr_set
    push ebx
    mov ebx, [dr_x1]
    call dr_set
    pop ebx
    pop ecx
    inc esi
    cmp esi, [dr_y1]
    jbe .v
    popad
    ret

; mark/cursor -> ebx = min x, ecx = min y, [dr_x1], [dr_y1] = max
dr_order:
    mov ebx, [dr_mx]
    mov eax, [dr_x]
    cmp ebx, eax
    jbe .x
    xchg ebx, eax
.x:
    mov [dr_x1], eax
    mov ecx, [dr_my]
    mov eax, [dr_y]
    cmp ecx, eax
    jbe .y
    xchg ecx, eax
.y:
    mov [dr_y1], eax
    ret

; straight line from the mark to the cursor (integer Bresenham)
dr_line:
    pushad
    mov ebx, [dr_mx]            ; x
    mov ecx, [dr_my]            ; y
    mov eax, [dr_x]
    sub eax, ebx
    mov esi, 1                  ; sx
    jge .dxp
    neg eax
    neg esi
.dxp:
    mov [dr_dx], eax
    mov eax, [dr_y]
    sub eax, ecx
    mov edi, 1                  ; sy
    jge .dyp
    neg eax
    neg edi
.dyp:
    neg eax
    mov [dr_dy], eax            ; dy = -|dy|
    add eax, [dr_dx]
    mov edx, eax                ; err = dx + dy
.step:
    mov al, [dr_brush]
    call dr_set
    cmp ebx, [dr_x]
    jne .go
    cmp ecx, [dr_y]
    je .done
.go:
    mov eax, edx
    shl eax, 1                  ; e2 = 2 * err
    cmp eax, [dr_dy]
    jl .noy
    add edx, [dr_dy]
    add ebx, esi
.noy:
    cmp eax, [dr_dx]
    jg .step
    add edx, [dr_dx]
    add ecx, edi
    jmp .step
.done:
    popad
    ret

; 4-connected flood fill from the cursor with the brush
dr_fill:
    pushad
    mov ebx, [dr_x]
    mov ecx, [dr_y]
    mov eax, ecx
    imul eax, DR_W
    mov dl, [DR_CANVAS+eax+ebx] ; target character
    mov dh, [dr_brush]
    cmp dl, dh
    je .done                    ; nothing to change
    xor esi, esi                ; stack depth
    call .push
.pop:
    test esi, esi
    jz .done
    dec esi
    mov eax, [DR_STACK+esi*4]
    movzx ebx, ax               ; x
    shr eax, 16
    mov ecx, eax                ; y
    imul eax, DR_W
    cmp [DR_CANVAS+eax+ebx], dl
    jne .pop
    mov [DR_CANVAS+eax+ebx], dh
    test ebx, ebx
    jz .r
    dec ebx
    call .push
    inc ebx
.r:
    cmp ebx, DR_W-1
    jae .u
    inc ebx
    call .push
    dec ebx
.u:
    test ecx, ecx
    jz .d
    dec ecx
    call .push
    inc ecx
.d:
    cmp ecx, DR_H-1
    jae .pop
    inc ecx
    call .push
    jmp .pop
.push:                          ; ebx, ecx -> stack (skipped when full)
    cmp esi, DR_STACKMAX
    jae .pr
    mov eax, ecx
    shl eax, 16
    mov ax, bx
    mov [DR_STACK+esi*4], eax
    inc esi
.pr:
    ret
.done:
    mov byte [dr_mod], 1
    mov dword [ed_msgp], dr_m_filled
    popad
    ret

; ---------- load / save (plain text, one line per canvas row) ----------

dr_load:
    cmp byte [dr_name], 0
    je .out
    cmp byte [fs_mounted], 0
    je .nodisk
    mov esi, dr_name
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .new
    mov ebx, eax
    mov edi, DR_FILEBUF
    mov ecx, DR_FILEMAX
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, -1
    je .out
    ; copy lines into the canvas, clipping long lines and extra rows
    mov esi, DR_FILEBUF
    add edx, esi                ; end
    xor ecx, ecx                ; row
    xor ebx, ebx                ; column
.c:
    cmp esi, edx
    jae .loaded
    lodsb
    cmp al, 10
    je .nl
    cmp al, 13
    je .c
    cmp al, ' '
    jae .p
    mov al, ' '
.p:
    call dr_set
    inc ebx
    jmp .c
.nl:
    xor ebx, ebx
    inc ecx
    jmp .c
.loaded:
    mov dword [ed_msgp], ed_m_loaded
.out:
    ret
.new:
    call ed_open_why
    mov [ed_msgp], esi
    jc .r
    mov byte [dr_name], 0       ; a directory, say: Ctrl+S asks for a name
.r:
    ret
.nodisk:
    mov dword [ed_msgp], ed_m_nodisk
    ret

dr_save:
    pushad
    cmp byte [fs_mounted], 0
    je .nodisk
    cmp byte [dr_name], 0
    jne .named
    mov esi, ed_m_saveas
    mov edi, dr_name
    call ed_prompt
    jc .cancel
.named:
    ; build text: each row with trailing spaces trimmed, then a newline
    mov edi, DR_FILEBUF
    xor ecx, ecx
.row:
    mov esi, ecx
    imul esi, DR_W
    add esi, DR_CANVAS
    mov edx, DR_W
.trim:
    test edx, edx
    jz .copy
    cmp byte [esi+edx-1], ' '
    jne .copy
    dec edx
    jmp .trim
.copy:
    push ecx
    mov ecx, edx
    rep movsb
    pop ecx
    mov byte [edi], 10
    inc edi
    inc ecx
    cmp ecx, DR_H
    jb .row
    ; drop trailing blank rows
.tail:
    cmp edi, DR_FILEBUF+1
    jbe .sized
    cmp byte [edi-2], 10
    jne .sized
    dec edi
    jmp .tail
.sized:
    sub edi, DR_FILEBUF
    mov [dr_flen], edi
    mov esi, dr_name
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .openerr
    mov ebx, eax
    mov esi, DR_FILEBUF
    mov ecx, [dr_flen]
    call fs_write
    mov edx, eax
    call fs_close
    cmp edx, [dr_flen]
    jne .err
    mov byte [dr_mod], 0
    mov dword [ed_msgp], ed_m_saved
    popad
    ret
.cancel:
    mov byte [dr_name], 0
    mov dword [ed_msgp], ed_m_cancel
    popad
    ret
.nodisk:
    mov dword [ed_msgp], ed_m_nodisk
    popad
    ret
.openerr:
    mov byte [dr_name], 0       ; the next save asks for another name
.err:
    movzx eax, byte [fs_errno]
    call fs_errstr
    mov [ed_msgp], esi
    popad
    ret

; ---------- screen ----------

; static parts: title, border, key help
dr_frame:
    pushad
    call cls
    call sb_reset
    mov al, ' '
    call sb_char
    mov esi, [lstr+LS_DRAW*4]   ; title in the current language (1.0.6)
    call sb_str
    mov esi, dr_title
    call sb_str
    xor ebx, ebx
    mov ah, ATTR_STATUS
    call sb_row
    ; border rows above and below the canvas
    mov ebx, DR_Y0-1
    call .hline
    mov ebx, DR_Y0+DR_H
    call .hline
    mov ecx, DR_Y0
.side:
    mov edi, ecx
    imul edi, 160
    add edi, 0xB8000+(DR_X0-1)*2
    mov word [edi], (ATTR_DIM<<8)|'|'
    mov word [edi+(DR_W+1)*2], (ATTR_DIM<<8)|'|'
    inc ecx
    cmp ecx, DR_Y0+DR_H
    jb .side
    call sb_reset
    mov esi, dr_keys1
    call sb_str
    mov ebx, 22
    mov ah, ATTR_TEXT
    call sb_row
    call sb_reset
    mov esi, dr_keys2
    call sb_str
    mov ebx, 23
    mov ah, ATTR_TEXT
    call sb_row
    popad
    ret
.hline:
    mov edi, ebx
    imul edi, 160
    add edi, 0xB8000+(DR_X0-1)*2
    mov ax, (ATTR_DIM<<8)|'+'
    stosw
    mov ecx, DR_W
    mov al, '-'
    rep stosw
    mov al, '+'
    stosw
    ret

dr_draw:
    pushad
    xor ecx, ecx                ; row
.row:
    mov edi, ecx
    add edi, DR_Y0
    imul edi, 160
    add edi, 0xB8000+DR_X0*2
    mov esi, ecx
    imul esi, DR_W
    add esi, DR_CANVAS
    xor ebx, ebx
.col:
    lodsb
    mov ah, ATTR_TEXT
    cmp byte [dr_mode], 0       ; highlight the marked corner
    je .nomark
    cmp ebx, [dr_mx]
    jne .nomark
    cmp ecx, [dr_my]
    jne .nomark
    mov ah, ATTR_STATUS
.nomark:
    stosw
    inc ebx
    cmp ebx, DR_W
    jb .col
    inc ecx
    cmp ecx, DR_H
    jb .row
    ; status row
    call sb_reset
    mov esi, dr_s_pos
    call sb_str
    mov eax, [dr_x]
    call sb_num
    mov al, ','
    call sb_char
    mov eax, [dr_y]
    call sb_num
    mov esi, dr_s_brush
    call sb_str
    mov al, [dr_brush]
    call sb_char
    mov al, 39
    call sb_char
    mov esi, dr_s_penup
    cmp byte [dr_pen], 0
    je .pen
    mov esi, dr_s_pendown
.pen:
    call sb_str
    mov esi, dr_s_line
    cmp byte [dr_mode], 1
    je .md
    mov esi, dr_s_rect
    cmp byte [dr_mode], 2
    je .md
    mov esi, dr_s_none
.md:
    call sb_str
    mov esi, dr_name
    cmp byte [esi], 0
    jne .nm
    mov esi, ed_s_noname
.nm:
    call sb_str
    cmp byte [dr_mod], 0
    je .clean
    mov esi, ed_s_mod
    call sb_str
.clean:
    mov ebx, DR_Y0+DR_H+1
    mov ah, ATTR_TEXT
    call sb_row
    ; message row
    call sb_reset
    mov esi, [ed_msgp]
    call sb_str
    mov ebx, 24
    mov ah, ATTR_TEXT
    call sb_row
    ; cursor
    mov eax, [dr_y]
    add eax, DR_Y0
    imul eax, 80
    add eax, [dr_x]
    add eax, DR_X0
    mov [cur], eax
    call cursor_sync
    popad
    ret

DR_FILEBUF  equ KSCRATCH+0xE000

dr_x dd 0
dr_y dd 0
dr_mx dd 0
dr_my dd 0
dr_x1 dd 0
dr_y1 dd 0
dr_dx dd 0
dr_dy dd 0
dr_flen dd 0
dr_brush db '*'
dr_pen db 0
dr_mode db 0                    ; 0 none, 1 line, 2 rectangle (corner marked)
dr_mod db 0
dr_name times FS_PATHMAX db 0
dr_title db ' - ASCII canvas 64x18', 0
dr_keys1 db 'Arrows move  Space plot  x/Bksp erase  p pen up/down  b brush  c clear', 0
dr_keys2 db 'l line, r rectangle (press at both corners)  f fill  Ctrl+S/F2 save  Esc quit', 0
dr_s_pos db 'Pos ', 0
dr_s_brush db "  Brush '", 0
dr_s_penup db '  Pen up', 0
dr_s_pendown db '  Pen DOWN', 0
dr_s_line db '  [line: move, press l]  ', 0
dr_s_rect db '  [rect: move, press r]  ', 0
dr_s_none db '  ', 0
dr_m_help db 'Ready.', 0
dr_m_penup db 'Pen up.', 0
dr_m_pendown db 'Pen down: moving draws.', 0
dr_m_brush db 'Type the new brush character (Esc cancels).', 0
dr_m_brushset db 'Brush set.', 0
dr_m_mark db 'Corner marked. Move and press the same key again.', 0
dr_m_drawn db 'Drawn.', 0
dr_m_filled db 'Filled.', 0
dr_m_cleared db 'Canvas cleared.', 0
