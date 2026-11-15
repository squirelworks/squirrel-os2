; mines — a Minesweeper-class game (G.3). Original code.
;
;   run mines [seed] [big]     play: 9 x 9 with 10 mines, or 16 x 16 with 40
;   run mines gui [seed] [big]  the same on the graphics screen: click or
;                        Enter opens, f flags, arrows move, n new, q quit
;   run mines test             rules self-check, prints "mines: PASS"
;
; Commands: a cell is a column letter and a row number ("c5").
;   c5        open the cell        f c5   flag or unflag it
;   n         new game             q      quit (Esc on an empty line too)
; The first cell opened is never a mine: the mines are laid after it,
; away from it and its neighbours, from the seeded random numbers.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"
%include "gui.inc"
%include "gamegui.inc"

MAXW    equ 16
MAXN    equ MAXW*MAXW
ST_HID  equ 0
ST_OPEN equ 1
ST_FLAG equ 2

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov dword [width], 9
    mov dword [nmines], 10
    mov edi, w_big
    call g_word
    jc .small
    mov dword [width], 16
    mov dword [nmines], 40
.small:
    cmp byte [g_gui], 0
    jne gui_play
    mov esi, m_title
    call g_puts
.new:
    call newgame
.loop:
    call draw
    cmp byte [over], 0
    je .ask
    mov esi, m_lost
    cmp byte [over], 1
    je .say
    mov esi, m_won
.say:
    call g_puts
.ask:
    mov esi, m_prompt
    call g_puts
    call g_readline
    cmp eax, -1
    je .quit
    mov esi, g_line
    mov edi, g_w_quit
    call g_word
    jnc .quit
    mov edi, g_w_new
    call g_word
    jnc .new
    mov edi, w_flag
    call g_word
    jnc .flag
    call parsecell
    jc .bad
    cmp byte [over], 0
    jne .bad
    call open
    jmp .loop
.flag:
    call parsecell
    jc .bad
    cmp byte [over], 0
    jne .bad
    call flag
    jmp .loop
.bad:
    mov esi, m_help
    call g_puts
    jmp .ask
.quit:
    xor eax, eax
    ret

; ---------- rules ----------

newgame:                        ; empty, unmined board
    push eax
    push ecx
    push edi
    mov edi, mine
    mov ecx, MAXN*3
    xor eax, eax
    rep stosb                   ; mine, adj, state are contiguous
    mov byte [laid], 0
    mov byte [over], 0
    mov dword [opened], 0
    mov dword [flags], 0
    mov eax, [width]
    imul eax, eax
    mov [ncells], eax
    pop edi
    pop ecx
    pop eax
    ret

; ebx = cell index -> eax = 1 if (x,y) of cell edx is a neighbour of ebx
; or the cell itself (Chebyshev distance <= 1)
near_cell:
    push ecx
    push esi
    push edi
    mov eax, ebx
    push edx
    xor edx, edx
    div dword [width]           ; eax = y1, edx = x1
    mov esi, eax
    mov edi, edx
    pop eax
    push eax
    xor edx, edx
    div dword [width]           ; eax = y2, edx = x2
    sub eax, esi
    sub edx, edi
    mov ecx, eax
    xor eax, eax
    cmp ecx, 1
    jg .no
    cmp ecx, -1
    jl .no
    cmp edx, 1
    jg .no
    cmp edx, -1
    jl .no
    inc eax
.no:
    pop edx
    pop edi
    pop esi
    pop ecx
    ret

; ebx = the first cell opened: lays the mines away from it, then counts
layout:
    push eax
    push ecx
    push edx
    mov ecx, [nmines]
.m: push ecx
    mov ecx, [ncells]
    call g_randn
    pop ecx
    mov edx, eax
    cmp byte [mine+edx], 0
    jne .m
    call near_cell
    test eax, eax
    jnz .m
    mov byte [mine+edx], 1
    loop .m
    mov byte [laid], 1
    call count_adj
    pop edx
    pop ecx
    pop eax
    ret

; Recomputes adj[] from mine[]
count_adj:
    pushad
    xor ebx, ebx
.c: xor ecx, ecx
    xor edx, edx
.n: cmp byte [mine+edx], 0
    je .skip
    cmp edx, ebx
    je .skip
    call near_cell
    add ecx, eax
.skip:
    inc edx
    cmp edx, [ncells]
    jb .n
    mov [adj+ebx], cl
    inc ebx
    cmp ebx, [ncells]
    jb .c
    popad
    ret

; ebx = cell: opens it (lays mines on the first open), floods zeros,
; and sets over = 1 (lost) or 2 (won)
open:
    pushad
    cmp byte [state+ebx], ST_HID
    jne .r
    cmp byte [laid], 0
    jne .laid
    call layout
.laid:
    cmp byte [mine+ebx], 0
    je .safe
    mov byte [state+ebx], ST_OPEN
    mov byte [over], 1
    jmp .r
.safe:
    ; flood fill with an explicit queue
    mov dword [qhead], 0
    mov dword [qtail], 0
    call .push
.next:
    mov eax, [qhead]
    cmp eax, [qtail]
    je .done
    inc dword [qhead]
    movzx ebx, word [queue+eax*2]
    cmp byte [adj+ebx], 0
    jne .next
    xor edx, edx
.nb:
    call near_cell
    test eax, eax
    jz .nn
    cmp byte [state+edx], ST_HID
    jne .nn
    push ebx
    mov ebx, edx
    call .push
    pop ebx
.nn:
    inc edx
    cmp edx, [ncells]
    jb .nb
    jmp .next
.done:
    mov eax, [ncells]
    sub eax, [nmines]
    cmp [opened], eax
    jne .r
    mov byte [over], 2
.r: popad
    ret
.push:                          ; ebx = hidden safe cell: open and queue it
    mov byte [state+ebx], ST_OPEN
    inc dword [opened]
    mov eax, [qtail]
    mov [queue+eax*2], bx
    inc dword [qtail]
    ret

flag:                           ; ebx = cell
    cmp byte [state+ebx], ST_OPEN
    je .r
    xor byte [state+ebx], ST_FLAG
    cmp byte [state+ebx], ST_FLAG
    jne .un
    inc dword [flags]
    ret
.un:
    dec dword [flags]
.r: ret

; esi = text like "c5" -> ebx = cell index, CF set when not a cell
parsecell:
    push eax
    call g_skipsp
    movzx ebx, byte [esi]
    sub ebx, 'a'
    cmp ebx, [width]
    jae .bad
    inc esi
    call g_parsenum
    jc .bad
    dec eax
    cmp eax, [width]
    jae .bad
    imul eax, [width]
    add ebx, eax
    pop eax
    clc
    ret
.bad:
    pop eax
    stc
    ret

; ---------- screen ----------

draw:
    pushad
    call g_nl
    mov esi, m_cols
    call g_puts
    xor ecx, ecx
.h: mov al, 'a'
    add al, cl
    call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, [width]
    jb .h
    call g_nl
    xor edx, edx                ; row
.row:
    lea eax, [edx+1]
    push ecx
    mov ecx, 3
    call g_putdec_w
    pop ecx
    mov al, ' '
    call g_putc
    xor ecx, ecx
.cell:
    mov ebx, edx
    imul ebx, [width]
    add ebx, ecx
    call cellchar
    call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, [width]
    jb .cell
    call g_nl
    inc edx
    cmp edx, [width]
    jb .row
    mov esi, m_mines
    call g_puts
    mov eax, [nmines]
    sub eax, [flags]
    call g_putdec
    call g_nl
    popad
    ret

; ebx = cell -> al = its character
cellchar:
    mov al, [state+ebx]
    cmp al, ST_FLAG
    je .flag
    cmp byte [over], 1
    jne .nomine
    cmp byte [mine+ebx], 0
    je .nomine
    mov al, '*'
    ret
.nomine:
    cmp al, ST_OPEN
    je .open
    mov al, '.'
    ret
.flag:
    mov al, 'F'
    ret
.open:
    mov al, [adj+ebx]
    test al, al
    jz .zero
    add al, '0'
    ret
.zero:
    mov al, ' '
    ret

; ---------- self-test ----------

; ---------- graphics ----------

; The field in the middle of the table, 18-pixel cells (11 for the big
; field). A click or Enter opens the cell under the cursor, f flags it.
BY0     equ 12

gui_play:
    call gui_open
    jnc .ok
    mov esi, m_nogui
    call g_puts
    mov eax, 1
    ret
.ok:
    mov eax, 18
    cmp dword [width], 9
    je .cs
    mov eax, 11
.cs:mov [gcs], eax
    imul eax, [width]
    mov ecx, SCR_W
    sub ecx, eax
    shr ecx, 1
    mov [gx0], ecx
.new:
    call newgame
    mov eax, [width]
    shr eax, 1
    mov ecx, [width]
    inc ecx
    imul eax, ecx
    mov [cursor], eax           ; the middle cell
.draw:
    call gdraw
    call gui_flip
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    cmp eax, EV_DRAG
    je .draw
    cmp al, 27
    je .quit
    cmp al, 'q'
    je .quit
    cmp al, 'n'
    je .new
    cmp al, 'f'
    je .flag
    cmp al, 13
    je .open
    cmp al, ' '
    je .open
    shr eax, 8
    cmp al, K_ENTER
    je .open
    call gmove
    jmp .draw
.click:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    call ghit
    cmp eax, -1
    je .draw
    mov [cursor], eax
.open:
    cmp byte [over], 0
    jne .draw
    mov ebx, [cursor]
    call open
    jmp .draw
.flag:
    cmp byte [over], 0
    jne .draw
    mov ebx, [cursor]
    call flag
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret

; al = scancode: the arrows move the cursor
gmove:
    pushad
    movzx esi, al
    mov eax, [cursor]
    xor edx, edx
    div dword [width]           ; eax = row, edx = column
    mov ecx, [width]
    dec ecx                     ; the last row and column
    mov ebx, [width]
    cmp esi, K_LEFT
    jne .rt
    test edx, edx
    jz .r
    dec dword [cursor]
    jmp .r
.rt:cmp esi, K_RIGHT
    jne .up
    cmp edx, ecx
    jae .r
    inc dword [cursor]
    jmp .r
.up:cmp esi, K_UP
    jne .dn
    test eax, eax
    jz .r
    sub [cursor], ebx
    jmp .r
.dn:cmp esi, K_DOWN
    jne .r
    cmp eax, ecx
    jae .r
    add [cursor], ebx
.r: popad
    ret

; eax, ebx = a point -> eax = the cell there, or -1
ghit:
    push ecx
    push edx
    sub eax, [gx0]
    js .no
    sub ebx, BY0
    js .no
    xor edx, edx
    div dword [gcs]
    cmp eax, [width]
    jae .no
    mov ecx, eax                ; column
    mov eax, ebx
    xor edx, edx
    div dword [gcs]
    cmp eax, [width]
    jae .no
    imul eax, [width]
    add eax, ecx
    jmp .r
.no:
    mov eax, -1
.r: pop edx
    pop ecx
    ret

; ecx = cell -> eax, ebx = its top left corner
gpos:
    push edx
    mov eax, ecx
    xor edx, edx
    div dword [width]
    imul ebx, eax, 1
    imul ebx, [gcs]
    add ebx, BY0
    imul eax, edx, 1
    imul eax, [gcs]
    add eax, [gx0]
    pop edx
    ret

gdraw:
    pushad
    call gg_table
    ; the mines left on the top line
    mov edi, gtitle
    call gg_sb_start
    mov esi, m_mines
    call gg_sb_str
    mov eax, [nmines]
    sub eax, [flags]
    jns .ml
    xor eax, eax
.ml:call gg_sb_num
    mov esi, gtitle
    call gg_title
    xor ecx, ecx
.c: call gcell
    inc ecx
    cmp ecx, [ncells]
    jb .c
    ; the cursor
    mov ecx, [cursor]
    call gpos
    dec eax
    dec ebx
    mov ecx, [gcs]
    inc ecx
    mov edx, ecx
    mov byte [gui_ink], C_YELLOW
    call gui_box
    mov esi, m_g_help
    cmp byte [over], 0
    je .s
    mov esi, m_g_lost
    cmp byte [over], 1
    je .s
    mov esi, m_g_won
.s: call gg_status
    popad
    ret

; ecx = cell: draws it
gcell:
    pushad
    call gpos
    mov [gpx], eax
    mov [gpy], ebx
    mov ecx, [gcs]
    dec ecx
    mov edx, ecx
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov esi, [esp+24]           ; the cell (saved ecx)
    cmp byte [state+esi], ST_OPEN
    je .open
    ; hidden: a raised tile, with a flag on it, or its mine at the end
    mov byte [gui_bevel_up], 1
    call gui_bevel
    cmp byte [state+esi], ST_FLAG
    je .flag
    cmp byte [over], 1
    jne .r
    cmp byte [mine+esi], 0
    je .r
    jmp .mine
.flag:
    mov eax, [gpx]
    mov ebx, [gpy]
    mov ecx, [gcs]
    shr ecx, 1
    add eax, ecx                ; the pole in the middle
    add ebx, 2
    mov edx, [gcs]
    sub edx, 5
    mov ecx, 1
    mov byte [gui_ink], C_BLACK
    call gui_fill
    mov ecx, [gcs]
    shr ecx, 2
    sub eax, ecx                ; the cloth to its left
    mov edx, ecx
    mov byte [gui_ink], C_RED
    call gui_fill
    jmp .r
.open:
    mov byte [gui_ink], C_WHITE  ; open cells are flat and light
    call gui_fill
    mov byte [gui_ink], C_LGREY
    call gui_box
    cmp byte [mine+esi], 0
    je .num
    mov byte [gui_ink], C_RED   ; the mine that went off
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    call gui_fill
.mine:
    mov eax, [gpx]
    mov ebx, [gpy]
    mov ecx, [gcs]
    shr ecx, 1
    add eax, ecx
    add ebx, ecx
    sub eax, 2
    sub ebx, 2
    mov ecx, 4
    mov edx, 4
    mov byte [gui_ink], C_BLACK
    call gui_fill
    dec eax
    inc ebx
    mov ecx, 6
    mov edx, 2
    call gui_fill
    add eax, 2
    sub ebx, 2
    mov ecx, 2
    mov edx, 6
    call gui_fill
    jmp .r
.num:
    movzx ecx, byte [adj+esi]
    test ecx, ecx
    jz .r
    mov al, [gnumink+ecx-1]
    mov [gui_ink], al
    mov byte [gui_bg], C_WHITE
    lea eax, [ecx+'0']
    mov [gdigit], ax
    mov esi, gdigit
    mov eax, [gcs]
    sub eax, 5
    shr eax, 1
    add eax, [gpx]
    mov ebx, [gcs]
    sub ebx, 7
    shr ebx, 1
    add ebx, [gpy]
    call gui_text
.r: popad
    ret

selftest:
    ; 1. a seeded game lays exactly 10 mines, none near the first cell,
    ;    and adj[] matches the mines
    mov dword [width], 9
    mov dword [nmines], 10
    mov eax, 7
    call g_srand
    call newgame
    mov ebx, 40                 ; e5, the centre
    call open
    call count_mines
    mov ebx, 10
    call g_expect               ; 1
    mov ebx, 40
    xor edx, edx
    xor ecx, ecx
.near:
    call near_cell
    test eax, eax
    jz .far
    movzx eax, byte [mine+edx]
    add ecx, eax
.far:
    inc edx
    cmp edx, 81
    jb .near
    mov eax, ecx
    xor ebx, ebx
    call g_expect               ; 2: no mine next to the first cell
    call adj_sum
    push eax
    call count_adj
    call adj_sum
    pop ebx
    call g_expect               ; 3: adj[] was already right
    movzx eax, byte [over]
    cmp eax, 1
    setne al
    mov ebx, 1
    call g_expect               ; 4: not lost
    call layout_hash
    mov [hash1], eax
    ; 2. the same seed gives the same board; another seed another
    mov eax, 7
    call g_srand
    call newgame
    mov ebx, 40
    call open
    call layout_hash
    mov ebx, [hash1]
    call g_expect               ; 5
    mov eax, 8
    call g_srand
    call newgame
    mov ebx, 40
    call open
    call layout_hash
    cmp eax, [hash1]
    setne al
    movzx eax, al
    mov ebx, 1
    call g_expect               ; 6
    ; 3. a fixed board: one mine in the corner a1, open i9:
    ;    the flood opens all 80 safe cells and the game is won
    call newgame
    mov byte [mine+0], 1
    mov dword [nmines], 1
    mov byte [laid], 1
    call count_adj
    mov ebx, 80
    call open
    mov eax, [opened]
    mov ebx, 80
    call g_expect               ; 7
    movzx eax, byte [over]
    mov ebx, 2
    call g_expect               ; 8: won
    ; 4. a flagged cell does not open; opening a mine loses
    call newgame
    mov byte [mine+10], 1       ; b2
    mov byte [laid], 1
    call count_adj
    mov ebx, 10
    call flag
    call open
    movzx eax, byte [state+10]
    mov ebx, ST_FLAG
    call g_expect               ; 9
    mov eax, [flags]
    mov ebx, 1
    call g_expect               ; 10
    mov ebx, 10
    call flag
    call open
    movzx eax, byte [over]
    mov ebx, 1
    call g_expect               ; 11: lost
    ; 5. a number cell opens alone: a1 next to the b2 mine
    call newgame
    mov byte [mine+10], 1
    mov byte [laid], 1
    call count_adj
    xor ebx, ebx
    call open
    mov eax, [opened]
    mov ebx, 1
    call g_expect               ; 12
    movzx eax, byte [adj+0]
    mov ebx, 1
    call g_expect               ; 13
    ; 6. the cell parser
    mov esi, t_cell
    call parsecell
    mov eax, ebx
    mov ebx, 4*9+2              ; c5
    call g_expect               ; 14
    mov esi, t_bad
    call parsecell
    setc al
    movzx eax, al
    mov ebx, 1
    call g_expect               ; 15: j1 is off a 9 x 9 board
    ; 7. the big board fits 40 mines
    mov dword [width], 16
    mov dword [nmines], 40
    mov eax, 3
    call g_srand
    call newgame
    mov ebx, 0
    call open
    call count_mines
    mov ebx, 40
    call g_expect               ; 16
    call g_report
    ret

count_mines:                    ; -> eax
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: movzx edx, byte [mine+ecx]
    add eax, edx
    inc ecx
    cmp ecx, [ncells]
    jb .l
    pop edx
    pop ecx
    ret

adj_sum:                        ; -> eax = sum of adj[i] * (i+1)
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: movzx edx, byte [adj+ecx]
    inc ecx
    imul edx, ecx
    add eax, edx
    cmp ecx, [ncells]
    jb .l
    pop edx
    pop ecx
    ret

layout_hash:                    ; -> eax = hash of the mine positions
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: cmp byte [mine+ecx], 0
    je .n
    imul eax, 31
    lea eax, [eax+ecx+1]
.n: inc ecx
    cmp ecx, [ncells]
    jb .l
    pop edx
    pop ecx
    ret

m_name db 'mines', 0
m_nogui db 'mines: no graphics screen', 10, 0
m_g_help db 'Click or Enter: open. f flag, n new, q quit', 0
m_g_lost db 'Boom! You hit a mine. n new game, q quit', 0
m_g_won db 'You cleared the field! n new game, q quit', 0
gnumink db C_BLUE, C_GREEN, C_RED, C_MAGENTA, C_BROWN, C_CYAN, C_BLACK, C_DGREY
m_title db 'Squirrel Mines - open every cell without a mine', 10
        db 'c5 opens a cell, f c5 flags it, n new game, q quits', 10, 0
m_cols db '    ', 0
m_mines db 'Mines left: ', 0
m_prompt db 'mines> ', 0
m_help db 'Type a cell like c5, f c5, n or q', 10, 0
m_lost db 'Boom! You hit a mine. n for a new game, q to quit', 10, 0
m_won db 'You cleared the field! n for a new game, q to quit', 10, 0
w_big db 'big', 0
w_flag db 'f', 0
t_cell db 'c5', 0
t_bad db 'j1', 0

SQX_BSS
G_BSS
width resd 1
nmines resd 1
ncells resd 1
opened resd 1
flags resd 1
qhead resd 1
qtail resd 1
hash1 resd 1
laid resb 1
over resb 1
alignb 4
mine resb MAXN
adj resb MAXN
state resb MAXN
queue resw MAXN
alignb 4
cursor resd 1
gcs resd 1
gx0 resd 1
gpx resd 1
gpy resd 1
gdigit resb 4
gtitle resb GG_SBMAX
GUI_BSS
GG_BSS
SQX_END
