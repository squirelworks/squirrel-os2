; Squirrel-OS/2 — Character map (A.2, OS2-APPS)
; Original code. run charmap
;
; Shows the 95 characters of the system font (0x20-0x7E) in a grid of
; 16 columns, the chosen one four times larger with its code in hex and
; decimal, and a line of collected characters:
;
;   arrows, Home, End     choose a character   left click   choose it
;   Enter or Space        add it to the line   Backspace    remove the last
;   F2                    save the line as the file charmap.txt
;   typing a character    jumps to it          Esc          quit
;
; See documentation/apps/gui-programs.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

FIRST       equ 0x20
COUNT       equ 95
GCOLS       equ 16
GROWS       equ (COUNT + GCOLS - 1) / GCOLS     ; 6
GCW          equ 12                              ; grid cell
GCH          equ 12
WIN_W       equ GCOLS * GCW + 2 + 8 + 60
WIN_H       equ 2 + WIN_TITLE_H + 4 + GROWS * GCH + 4 + 3 * CELL_H + 8
WIN_X       equ (SCR_W - WIN_W) / 2
WIN_Y       equ (SCR_H - WIN_H) / 2
GX          equ WIN_X + 1 + 4                   ; the grid
GY          equ WIN_Y + 1 + WIN_TITLE_H + 4
BIGX          equ GX + GCOLS * GCW + 8             ; the big glyph
SCALE       equ 4
LINE_MAX    equ 40

main:
    call gui_open
    jc .nogfx
    mov dword [sel], 'A' - FIRST
.draw:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .key
    cmp ah, K_ESC
    je .quit
    cmp ah, K_LEFT
    je .l
    cmp ah, K_RIGHT
    je .r
    cmp ah, K_UP
    je .u
    cmp ah, K_DOWN
    je .d
    cmp ah, K_HOME
    je .home
    cmp ah, K_END
    je .end
    cmp ah, K_ENTER
    je .add
    cmp ah, K_BKSP
    je .bs
    cmp ah, K_F2
    je .save
    cmp al, ' '
    je .add
    jb .key
    cmp al, '~'
    ja .key
    movzx eax, al               ; a typed character: jump to it
    sub eax, FIRST
    mov [sel], eax
    jmp .draw
.l:
    dec dword [sel]
    jmp .clamp
.r:
    inc dword [sel]
    jmp .clamp
.u:
    sub dword [sel], GCOLS
    jmp .clamp
.d:
    add dword [sel], GCOLS
    jmp .clamp
.home:
    mov dword [sel], 0
    jmp .draw
.end:
    mov dword [sel], COUNT - 1
    jmp .draw
.clamp:
    mov eax, [sel]
    test eax, eax
    jns .c1
    xor eax, eax
.c1:
    cmp eax, COUNT
    jb .c2
    mov eax, COUNT - 1
.c2:
    mov [sel], eax
    mov dword [msg], 0
    jmp .draw
.click:
    mov eax, [gui_mx]
    sub eax, GX
    jb .key
    mov ebx, [gui_my]
    sub ebx, GY
    jb .key
    xor edx, edx
    mov ecx, GCW
    div ecx
    cmp eax, GCOLS
    jae .key
    mov esi, eax
    mov eax, ebx
    xor edx, edx
    mov ecx, GCH
    div ecx
    imul eax, GCOLS
    add eax, esi
    cmp eax, COUNT
    jae .key
    mov [sel], eax
    jmp .draw
.add:
    mov ecx, [len]
    cmp ecx, LINE_MAX
    jae .draw
    mov eax, [sel]
    add al, FIRST
    mov [line+ecx], al
    inc dword [len]
    mov dword [msg], 0
    jmp .draw
.bs:
    cmp dword [len], 0
    je .key
    dec dword [len]
    jmp .draw
.save:
    call save
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

draw:
    pushad
    mov al, C_CYAN
    call gui_clear
    mov eax, WIN_X
    mov ebx, WIN_Y
    mov ecx, WIN_W
    mov edx, WIN_H
    mov esi, title
    call gui_window
    ; the grid: white cells, the chosen one blue with white ink
    xor ebp, ebp
.cell:
    mov eax, ebp
    xor edx, edx
    mov ecx, GCOLS
    div ecx
    imul ebx, eax, GCH
    add ebx, GY
    imul eax, edx, GCW
    add eax, GX
    mov ecx, GCW - 1
    mov edx, GCH - 1
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_WHITE
    cmp ebp, [sel]
    jne .f
    mov byte [gui_ink], C_BLUE
    mov byte [gui_bg], C_BLUE
.f:
    call gui_fill
    mov cl, C_BLACK
    cmp ebp, [sel]
    jne .ink
    mov cl, C_WHITE
.ink:
    mov [gui_ink], cl
    add eax, (GCW - 1 - CELL_W) / 2 + 1
    add ebx, (GCH - 1 - CELL_H) / 2 + 1
    mov edx, ebp
    add dl, FIRST
    call gui_char
    inc ebp
    cmp ebp, COUNT
    jb .cell
    ; the chosen character, large, and its codes
    mov eax, BIGX
    mov ebx, GY
    mov ecx, 6 * SCALE + 4
    mov edx, 8 * SCALE + 4
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_bevel_up], 0
    call gui_bevel
    call big_glyph
    mov edi, info               ; "0x41 65"
    mov eax, [sel]
    add eax, FIRST
    push eax
    mov word [edi], '0x'
    add edi, 2
    mov ah, al
    shr al, 4
    call hexdig
    mov al, ah
    and al, 0x0F
    call hexdig
    mov byte [edi], 0
    mov esi, info
    mov eax, BIGX
    mov ebx, GY + 8 * SCALE + 8
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    pop eax
    mov edi, info
    call gui_utoa
    mov esi, info
    add ebx, CELL_H + 1
    mov eax, BIGX
    call gui_text
    ; the collected line, in a white field
    mov eax, GX
    mov ebx, GY + GROWS * GCH + 4
    mov ecx, WIN_W - 10
    mov edx, CELL_H + 4
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_bevel_up], 0
    call gui_bevel
    mov ecx, [len]
    mov byte [line+ecx], 0
    mov esi, line
    add eax, 2
    add ebx, 2
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    mov ecx, WIN_W - 14
    call gui_textn
    ; help or the last message
    mov esi, [msg]
    test esi, esi
    jnz .m
    mov esi, help
.m:
    mov eax, GX
    mov ebx, GY + GROWS * GCH + 4 + CELL_H + 4 + 3
    mov ecx, WIN_W - 10
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
    popad
    ret

; al = 0..15 -> a hex digit at edi
hexdig:
    add al, '0'
    cmp al, '9'
    jbe .s
    add al, 'A' - '9' - 1
.s:
    stosb
    ret

; The chosen glyph, SCALE times larger, from the font copy in gui_font.
big_glyph:
    pushad
    mov esi, [sel]
    imul esi, FONT_H
    add esi, gui_font
    xor ebp, ebp                ; row
.row:
    movzx edx, byte [esi+ebp]
    xor edi, edi                ; column
.col:
    mov ecx, 4
    sub ecx, edi
    bt edx, ecx
    jnc .n
    imul eax, edi, SCALE
    add eax, BIGX + 2 + SCALE
    imul ebx, ebp, SCALE
    add ebx, GY + 2 + SCALE / 2
    mov ecx, SCALE
    push edx
    mov edx, SCALE
    mov byte [gui_ink], C_BLACK
    call gui_fill
    pop edx
.n:
    inc edi
    cmp edi, 5
    jb .col
    inc ebp
    cmp ebp, FONT_H
    jb .row
    popad
    ret

save:
    pushad
    mov eax, SYS_OPEN
    mov ebx, fname
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, line
    mov edx, [len]
    int 0x80
    mov eax, SYS_CLOSE
    int 0x80
    mov dword [msg], m_saved
    popad
    ret
.fail:
    mov dword [msg], m_fail
    popad
    ret

title db 'Character map', 0
help db 'Enter: add  F2: save  Esc: quit', 0
fname db 'charmap.txt', 0
m_saved db 'Saved as charmap.txt', 0
m_fail db 'Not saved!', 0
m_nogfx db 'charmap: no graphics', 10, 0

SQX_BSS
GUI_BSS
sel resd 1
len resd 1
msg resd 1
info resb 16
line resb LINE_MAX + 1
SQX_END
