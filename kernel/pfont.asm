; Proportional fonts (2.2-propfont): two original faces, 9 and 12 pixels
; high, from tools/fontp9.txt and tools/fontp12.txt (kernel/fontp.inc,
; built by tools/mkfont.py). A glyph is one to eight columns wide and is
; followed by one spacing column; a face's rows run from the top of its
; tallest letters to the bottom of its descenders. The 5 x 7 font
; (gfx_drawstr) stays for consoles and the regress screen reader.

PF_SPACE equ 1                  ; columns after each glyph

; esi = zero-terminated string, eax, ebx = top left, ecx = face (FONT_9 /
; FONT_12). Ink in [gfx_colour]; the background (the spacing columns and
; the glyphs' clear pixels) in [gfx_bg], or nothing where gfx_bg is 0xFF
; (transparent). -> eax = x after the last spacing column. Every pixel
; goes through gfx_putpixel, so the clip and the occluders apply.
gfx_drawstr_p:
    push edx
    push esi
    push ebp
    call pf_face
.next:
    movzx edx, byte [esi]
    test edx, edx
    jz .done
    call pf_index
    call pf_glyph
    inc esi
    jmp .next
.done:
    pop ebp
    pop esi
    pop edx
    ret

; esi = zero-terminated string, ecx = face -> eax = its width in pixels,
; spacing columns included (what gfx_drawstr_p advances x by).
gfx_strwidth_p:
    push edx
    push esi
    push ebp
    call pf_face
    xor eax, eax
.next:
    movzx edx, byte [esi]
    test edx, edx
    jz .done
    call pf_index
    push esi
    mov esi, [ebp]
    movzx edx, byte [esi+edx]
    pop esi
    lea eax, [eax+edx+PF_SPACE]
    inc esi
    jmp .next
.done:
    pop ebp
    pop esi
    pop edx
    ret

; ecx = face -> ebp = its record in fontp_faces (an unknown face is FONT_9)
pf_face:
    cmp ecx, FONTP_FACES
    jb .ok
    xor ecx, ecx
.ok:
    imul ebp, ecx, 12
    add ebp, fontp_faces
    ret

; edx = character code -> edx = glyph index ('?' for codes outside the font)
pf_index:
    sub edx, FONT_FIRST
    cmp edx, FONT_LAST - FONT_FIRST
    jbe .ok
    mov edx, '?' - FONT_FIRST
.ok:
    ret

; eax, ebx = top left, edx = glyph index, ebp = face -> eax += its advance
pf_glyph:
    pushad
    mov [pf_x], eax
    mov [pf_y], ebx
    mov esi, [ebp]
    movzx edi, byte [esi+edx]
    mov [pf_w], edi
    mov ecx, [ebp+8]            ; height
    imul edx, ecx
    add edx, [ebp+4]
    mov esi, edx                ; the glyph's rows
    xor edx, edx                ; row
.row:
    cmp edx, [ebp+8]
    jae .done
    mov ah, [esi+edx]           ; the row's bits, leftmost in bit 7
    xor edi, edi                ; column; column pf_w is the spacing one
.col:
    mov cl, [gfx_colour]
    test ah, 0x80
    jnz .put
    mov cl, [gfx_bg]
    cmp cl, 0xFF
    je .skip
.put:
    push eax
    mov eax, [pf_x]
    add eax, edi
    mov ebx, [pf_y]
    add ebx, edx
    call gfx_putpixel
    pop eax
.skip:
    shl ah, 1
    inc edi
    cmp edi, [pf_w]
    jbe .col
    inc edx
    jmp .row
.done:
    popad
    add eax, [pf_w]
    add eax, PF_SPACE
    ret

pf_x dd 0
pf_y dd 0
pf_w dd 0

; pfont: draws a line in each face on a blue band, reads back ink, clear
; and spacing pixels, a descender, a transparent background and what is
; left of the string, and checks gfx_strwidth_p against the x that
; gfx_drawstr_p returns. The lines stay up until a key (the regress
; screen reader reads them), then text mode and "pfont: PASS".
PFT_X equ 20
PFT_Y equ 120                   ; FONT_9 line; FONT_12 at PFT_Y + 16
cmd_pfont_run:
    call gfx_mode13
    mov byte [gfxt_ok], 1
    mov byte [gfx_colour], 0
    xor eax, eax
    mov ebx, GFX_SAFE_Y
    mov ecx, GFX_W
    mov edx, GFX_H - GFX_SAFE_Y
    call gfx_fillrect
    mov byte [gfx_colour], 0x01
    mov eax, PFT_X - 4
    mov ebx, PFT_Y - 2
    mov ecx, 280
    mov edx, 36
    call gfx_fillrect
    mov byte [gfx_colour], 0x0F
    mov byte [gfx_bg], 0x01
    mov esi, pft_s9             ; 'Wg' leads: W is #...# on top, g's tail is ...# / .##.
    mov eax, PFT_X
    mov ebx, PFT_Y
    xor ecx, ecx                ; FONT_9
    call gfx_drawstr_p
    sub eax, PFT_X
    mov edx, eax
    call gfx_strwidth_p
    cmp eax, edx
    jne .bad
    mov esi, pft_wg             ; 'Wg' alone: 5 + 1 + 4 + 1
    call gfx_strwidth_p
    cmp eax, 11
    jne .bad
    mov ecx, FONT_12            ; bold: 6 + 1 + 5 + 1
    call gfx_strwidth_p
    cmp eax, 13
    jne .bad
    mov esi, pft_s12
    mov eax, PFT_X
    mov ebx, PFT_Y + 16
    call gfx_drawstr_p
    sub eax, PFT_X
    mov edx, eax
    call gfx_strwidth_p
    cmp eax, edx
    jne .bad
    mov byte [gfx_colour], 0x0E ; transparent: 'i' over the yellow-free band
    mov byte [gfx_bg], 0xFF
    mov esi, pft_i
    mov eax, PFT_X + 260
    mov ebx, PFT_Y
    xor ecx, ecx
    call gfx_drawstr_p
    cmp eax, PFT_X + 262
    jne .bad
    mov byte [gfx_bg], 0
    mov esi, pft_expect
    call gfx_expect
    jmp .shown
.bad:
    mov byte [gfxt_ok], 0
.shown:
    call fb_waitkey
    call gfx_text
    mov esi, pft_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, pft_fail
.say:
    jmp puts

; x (dd), y (dd), expected colour (db); x = -1 ends the list
pft_expect:
    dd PFT_X, PFT_Y
    db 0x0F                     ; W: top left is ink
    dd PFT_X + 1, PFT_Y
    db 0x01                     ; W: then clear
    dd PFT_X + 5, PFT_Y
    db 0x01                     ; W's spacing column
    dd PFT_X + 6 + 3, PFT_Y + 7
    db 0x0F                     ; g's descender, below the baseline
    dd PFT_X + 6 + 1, PFT_Y + 8
    db 0x0F                     ; g's tail
    dd PFT_X + 6, PFT_Y + 8
    db 0x01                     ; left of the tail
    dd PFT_X - 1, PFT_Y
    db 0x01                     ; left of the string: the band, untouched
    dd PFT_X + 260, PFT_Y
    db 0x0E                     ; transparent 'i': its dot
    dd PFT_X + 260, PFT_Y + 1
    db 0x01                     ; the gap under the dot shows the band
    dd PFT_X + 261, PFT_Y
    db 0x01                     ; and so does its spacing column
    dd PFT_X + 1, PFT_Y + 16 + 2
    db 0x0F                     ; FONT_12 W: bold, two columns of ink
    dd PFT_X, PFT_Y + 16
    db 0x01                     ; FONT_12: the blank top row
    dd -1

pft_s9 db 'Wg Squirrel window face', 0
pft_s12 db 'Wg Display face, bold', 0
pft_wg db 'Wg', 0
pft_i db 'i', 0
pft_pass db 'pfont: PASS', 10, 0
pft_fail db 'pfont: FAIL', 10, 0

%include "fontp.inc"
