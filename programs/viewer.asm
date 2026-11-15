; Squirrel-OS/2 — Image viewer (A.2, OS2-APPS)
; Original code. run viewer <file.bmp> [test]
;
; Shows an uncompressed 8-bit or 24-bit BMP. The colours go through a
; 4 x 4 ordered dither into a 192-entry colour cube (6 reds x 8 greens x 4 blues) that the viewer puts
; in DAC entries 64-255 with SYS_GUI GUI_PALETTE; text mode only uses 0-63,
; so the shell's colours are unchanged afterwards.
;
;   + -        zoom in / out (1/8 to 8 times)    arrows  scroll
;   Home       fit the picture to the screen     Esc     quit
;
; On quitting it prints "viewer: <file> <w> x <h>, <bits> bits".
; With "test" it draws, reads back the screen pixel of the picture's
; centre and checks it is the cube colour for that pixel, then prints
; "viewer: PASS" (or FAIL) after the line above.
; See documentation/apps/paint.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "bmp.inc"

VIEW_H      equ SCR_H - CELL_H - 2  ; picture area: the rows above the info
CUBE        equ 64                  ; first DAC entry of the cube

main:
    mov esi, [esp+4]
    call skip
    cmp byte [esi], 0
    je .usage
    mov edi, name                   ; the name: up to a space
    mov ecx, 31
.n:
    lodsb
    cmp al, ' '
    jbe .ne
    stosb
    loop .n
.ne:
    mov byte [edi], 0
    dec esi
    call skip
    cmp dword [esi], 'test'
    jne .load
    mov byte [testing], 1
.load:
    mov esi, name
    call bmp_load
    jc .noload
    call gui_open
    jc .nogfx
    call cube
    call fit
.draw:
    call draw
    cmp byte [testing], 0
    jne check
.key:
    xor ecx, ecx
    call gui_event
    cmp ah, K_ESC
    je .quit
    cmp ah, K_HOME
    je .home
    cmp ah, K_LEFT
    je .l
    cmp ah, K_RIGHT
    je .r
    cmp ah, K_UP
    je .u
    cmp ah, K_DOWN
    je .d
    cmp al, '+'
    je .zin
    cmp al, '='
    je .zin
    cmp al, '-'
    je .zout
    jmp .key
.home:
    call fit
    jmp .draw
.l:
    mov eax, -(SCR_W / 4)
    xor ebx, ebx
    jmp .scroll
.r:
    mov eax, SCR_W / 4
    xor ebx, ebx
    jmp .scroll
.u:
    xor eax, eax
    mov ebx, -(VIEW_H / 4)
    jmp .scroll
.d:
    xor eax, eax
    mov ebx, VIEW_H / 4
.scroll:
    call scroll
    jmp .draw
.zin:
    cmp dword [zoom], 3         ; 8 times
    jge .key
    inc dword [zoom]
    call centre
    jmp .draw
.zout:
    cmp dword [zoom], -3        ; 1/8
    jle .key
    dec dword [zoom]
    call centre
    jmp .draw
.quit:
    call gui_close
    call info
    xor eax, eax
    ret
.usage:
    mov esi, m_usage
    call gui_puts
    mov eax, 1
    ret
.noload:
    mov esi, m_noload
    call gui_puts
    mov eax, 1
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; "viewer: name W x H, B bits" on the text screen
info:
    pushad
    mov edi, line
    mov esi, m_viewer
    call scopy
    mov esi, name
    call scopy
    mov al, ' '
    stosb
    call dims
    mov al, 10
    stosb
    mov byte [edi], 0
    mov esi, line
    call gui_puts
    popad
    ret

; "W x H, B bits" at edi
dims:
    mov eax, [bmp_w]
    call gui_utoa
    mov esi, s_x
    call scopy
    mov eax, [bmp_h]
    call gui_utoa
    mov esi, s_comma
    call scopy
    mov eax, [bmp_bpp]
    call gui_utoa
    mov esi, s_bits
    call scopy
    ret

; The colour cube into DAC entries 64-255: red r * 63 / 5, green
; g * 63 / 7, blue b * 63 / 3; entry 64 + r * 32 + g * 4 + b.
cube:
    pushad
    mov edi, line
    xor ebx, ebx                ; r
.r:
    xor ecx, ecx                ; g
.g:
    xor edx, edx                ; b
.b:
    imul eax, ebx, 63
    push edx
    xor edx, edx
    mov esi, 5
    div esi
    pop edx
    stosb
    imul eax, ecx, 63
    push edx
    xor edx, edx
    mov esi, 7
    div esi
    pop edx
    stosb
    imul eax, edx, 21           ; 63 / 3
    stosb
    inc edx
    cmp edx, 4
    jb .b
    inc ecx
    cmp ecx, 8
    jb .g
    ; one red level (32 entries, 96 bytes) at a time
    mov eax, SYS_GUI
    push ebx
    push ecx
    mov ecx, ebx
    shl ecx, 5
    add ecx, CUBE
    or ecx, 32 << 16
    mov edx, line
    mov ebx, GUI_PALETTE
    int 0x80
    pop ecx
    pop ebx
    mov edi, line
    inc ebx
    cmp ebx, 6
    jb .r
    popad
    ret

; eax = 0x00RRGGBB, [thr] = 0..15 (the ordered-dither threshold of the
; screen pixel) -> al = its cube entry. Each channel with L levels becomes
; floor(v * (L - 1) / 255 + (thr + 0.5) / 16), so a flat colour between
; two levels is a pattern of both.
to_cube:
    push ebx
    push ecx
    push edx
    mov ecx, eax
    movzx eax, cl               ; blue: 4 levels
    mov ebx, 3
    call level
    mov edx, eax
    movzx eax, ch               ; green: 8 levels
    mov ebx, 7
    call level
    shl eax, 2
    add edx, eax
    shr ecx, 16                 ; red: 6 levels
    movzx eax, cl
    mov ebx, 5
    call level
    shl eax, 5
    add eax, edx
    add eax, CUBE
    pop edx
    pop ecx
    pop ebx
    ret

; eax = 0..255, ebx = L - 1 -> eax = the level (see to_cube)
level:
    push edx
    imul eax, ebx
    shl eax, 5                  ; v * (L - 1) * 32
    mov edx, [thr]
    lea edx, [edx*2+1]
    imul edx, 255
    add eax, edx                ; + (2 thr + 1) * 255
    xor edx, edx
    mov ebx, 8160               ; / (255 * 32)
    div ebx
    pop edx
    ret

; eax = x, ebx = y on the screen -> thr = the 4 x 4 Bayer threshold there
dither_at:
    push eax
    push ebx
    and eax, 3
    and ebx, 3
    lea eax, [eax+ebx*4]
    movzx eax, byte [bayer+eax]
    mov [thr], eax
    pop ebx
    pop eax
    ret

bayer db 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5

; The largest zoom that shows the whole picture (at most 1:1), centred.
fit:
    mov dword [zoom], 0
.try:
    mov eax, [bmp_w]
    call scaled
    cmp eax, SCR_W
    ja .smaller
    mov eax, [bmp_h]
    call scaled
    cmp eax, VIEW_H
    jbe centre
.smaller:
    cmp dword [zoom], -3
    jle centre
    dec dword [zoom]
    jmp .try

; eax = a length in picture pixels -> eax on the screen at [zoom]
scaled:
    mov ecx, [zoom]
    test ecx, ecx
    js .down
    shl eax, cl
    ret
.down:                          ; rounded up
    neg ecx
    push ebx
    mov ebx, 1
    shl ebx, cl
    dec ebx
    add eax, ebx
    pop ebx
    shr eax, cl
    ret

; ox, oy = the screen position of the picture's top left: centred, or
; when it is larger than the screen, its centre at the screen's.
centre:
    mov eax, [bmp_w]
    call scaled
    mov ebx, SCR_W
    sub ebx, eax
    sar ebx, 1
    mov [ox], ebx
    mov eax, [bmp_h]
    call scaled
    mov ebx, VIEW_H
    sub ebx, eax
    sar ebx, 1
    mov [oy], ebx
    ret

; eax, ebx = how far to move the view (screen pixels), only while the
; picture reaches past that edge.
scroll:
    sub [ox], eax
    sub [oy], ebx
    ret

; screen x, y -> the picture pixel drawn there: eax, ebx (CF if none)
pic_at:
    sub eax, [ox]
    js .no
    sub ebx, [oy]
    js .no
    mov ecx, [zoom]
    test ecx, ecx
    js .down
    shr eax, cl
    shr ebx, cl
    jmp .in
.down:
    neg ecx
    shl eax, cl
    shl ebx, cl
.in:
    cmp eax, [bmp_w]
    jae .no
    cmp ebx, [bmp_h]
    jae .no
    clc
    ret
.no:
    stc
    ret

draw:
    pushad
    mov al, C_BLACK
    call gui_clear
    xor ebx, ebx
.row:
    xor ebp, ebp
.col:
    mov eax, ebp
    push ebx
    call pic_at
    jc .next
    call bmp_rgb
    mov ecx, eax
    mov eax, ebp
    mov ebx, [esp]
    call dither_at
    mov eax, ecx
    call to_cube
    mov cl, al
    mov eax, ebp
    call gui_pset
.next:
    pop ebx
    inc ebp
    cmp ebp, SCR_W
    jb .col
    inc ebx
    cmp ebx, VIEW_H
    jb .row
    ; the info row
    mov eax, 0
    mov ebx, VIEW_H
    mov ecx, SCR_W
    mov edx, SCR_H - VIEW_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov edi, line
    mov esi, name
    call scopy
    mov ax, '  '
    stosw
    call dims
    mov ax, '  '
    stosw
    mov ecx, [zoom]
    test ecx, ecx
    js .zd
    mov eax, 1
    shl eax, cl
    call gui_utoa
    mov esi, s_times
    call scopy
    jmp .zo
.zd:
    mov esi, s_one_in
    call scopy
    neg ecx
    mov eax, 1
    shl eax, cl
    call gui_utoa
.zo:
    mov esi, line
    mov eax, 2
    mov ebx, VIEW_H + 1
    mov ecx, SCR_W - 4
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
    popad
    ret

; test: the screen pixel at the picture's centre must be its cube colour
check:
    mov eax, [bmp_w]
    shr eax, 1
    mov [cx_], eax
    call scaled
    add eax, [ox]
    mov [sx], eax
    mov eax, [bmp_h]
    shr eax, 1
    mov [cy_], eax
    call scaled
    add eax, [oy]
    mov ebx, eax
    mov eax, [sx]
    push eax
    push ebx
    call dither_at
    call pic_at                 ; the pixel really drawn there
    jc .fail2
    call bmp_rgb
    call to_cube
    mov dl, al
    pop ebx
    pop eax
    call gui_peek
    cmp cl, dl
    jne .fail
    call gui_close
    call info
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.fail2:
    pop ebx
    pop eax
.fail:
    call gui_close
    call info
    mov esi, fail
    call gui_puts
    mov eax, 1
    ret

skip:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip
.r:
    ret

scopy:
    lodsb
    test al, al
    jz .r
    stosb
    jmp scopy
.r:
    mov byte [edi], 0
    ret

m_viewer db 'viewer: ', 0
s_x db ' x ', 0
s_comma db ', ', 0
s_bits db ' bits', 0
s_times db ':1', 0
s_one_in db '1:', 0
m_usage db 'usage: run viewer <file.bmp>', 10, 0
m_noload db 'viewer: not an 8- or 24-bit BMP, or not found', 10, 0
m_nogfx db 'viewer: no graphics', 10, 0
pass db 'viewer: PASS', 10, 0
fail db 'viewer: FAIL', 10, 0

SQX_BSS
GUI_BSS
BMP_BSS
zoom resd 1
ox resd 1
oy resd 1
sx resd 1
cx_ resd 1
cy_ resd 1
thr resd 1
testing resb 4
name resb 32
line resb 128
SQX_END
