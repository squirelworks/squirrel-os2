; mahjongg — Mahjongg-style tile solitaire (G.7). Original code and layout.
;
;   run mahjongg [seed]    play a seeded deal (always solvable)
;   run mahjongg test      rules self-check, prints "mahjongg: PASS"
;
; 108 tiles of 27 kinds (three suits, Acorns, Leaves and Stars, 1-9; four
; of each) are stacked in a four-layer pyramid on a 10 x 6 grid. Remove
; the tiles in matching pairs; a tile can be taken when nothing lies on
; it and its left or its right side is open.
;
; The screen shows each grid cell's top tile, the stack height, and * when
; that tile is free. Commands:
;   c3 f5     remove the pair on c3 and f5
;   h         show a pair you can take        n  new deal    q  quit
;
; Deals are made by playing a random game backwards: pairs of free tiles
; are taken off the full pyramid and given the same kind, so the order
; they came off is always a solution.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"

GW     equ 10                   ; grid width
GH     equ 6                    ; grid height
NL     equ 4                    ; layers
NCELL  equ GW*GH
NTILE  equ 108
NKIND  equ 27

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov esi, m_title
    call g_puts
.new:
    call deal
.loop:
    call draw
    cmp dword [left], 0
    jne .moves
    mov esi, m_won
    call g_puts
    jmp .ask
.moves:
    call find_pair
    test eax, eax
    jnz .ask
    mov esi, m_stuck
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
    mov edi, w_hint
    call g_word
    jnc .hint
    call parsecell
    jc .bad
    mov ecx, ebx
    call parsecell
    jc .bad
    call g_skipsp
    cmp byte [esi], 0
    jne .bad
    call take_pair
    test eax, eax
    jnz .loop
    mov esi, m_nomatch
    call g_puts
    jmp .ask
.hint:
    call find_pair
    test eax, eax
    jz .nohint
    mov esi, m_try
    call g_puts
    mov eax, [hint_a]
    call putcell
    mov al, ' '
    call g_putc
    mov eax, [hint_b]
    call putcell
    call g_nl
    jmp .ask
.nohint:
    mov esi, m_stuck
    call g_puts
    jmp .ask
.bad:
    mov esi, m_help
    call g_puts
    jmp .ask
.quit:
    xor eax, eax
    ret

; ---------- layout and rules ----------

; Fills height[] with the pyramid: layer l covers the rectangle in
; layer_rect (x0, y0, x1, y1 inclusive); a cell's height is the number
; of layers over it
layout:
    pushad
    mov edi, height
    mov ecx, NCELL
    xor eax, eax
    rep stosb
    xor ebx, ebx                ; layer
.l: mov esi, ebx
    shl esi, 2
    add esi, layer_rect
    movzx edx, byte [esi+1]     ; y
.y: movzx ecx, byte [esi]       ; x
.x: imul eax, edx, GW
    add eax, ecx
    inc byte [height+eax]
    inc ecx
    cmp cl, [esi+2]
    jbe .x
    inc edx
    cmp dl, [esi+3]
    jbe .y
    inc ebx
    cmp ebx, NL
    jb .l
    mov dword [left], NTILE
    popad
    ret

; eax = cell -> eax = 1 if its top tile is free (0 when the cell is empty)
isfree:
    push ebx
    push ecx
    push edx
    mov ebx, eax
    movzx ecx, byte [height+ebx]
    test ecx, ecx
    jz .no
    xor edx, edx
    div dword [c_gw]            ; edx = x
    test edx, edx
    jz .yes                     ; the left edge is open
    cmp edx, GW-1
    je .yes
    cmp [height+ebx-1], cl      ; left neighbour as high: blocked on the left
    jb .yes
    cmp [height+ebx+1], cl
    jb .yes
.no:
    xor eax, eax
    jmp .r
.yes:
    mov eax, 1
.r: pop edx
    pop ecx
    pop ebx
    ret

; eax = cell -> eax = kind (0..26) of its top tile
topkind:
    push ebx
    movzx ebx, byte [height+eax]
    dec ebx
    imul ebx, NCELL
    add ebx, eax
    movzx eax, byte [tiles+ebx]
    pop ebx
    ret

; ebx, ecx = cells -> eax = 1 if the pair was taken (both free, same kind)
take_pair:
    push ebx
    push ecx
    push edx
    cmp ebx, ecx
    je .no
    mov eax, ebx
    call isfree
    test eax, eax
    jz .no
    mov eax, ecx
    call isfree
    test eax, eax
    jz .no
    mov eax, ebx
    call topkind
    mov edx, eax
    mov eax, ecx
    call topkind
    cmp eax, edx
    jne .no
    dec byte [height+ebx]
    dec byte [height+ecx]
    sub dword [left], 2
    mov eax, 1
    jmp .r
.no:
    xor eax, eax
.r: pop edx
    pop ecx
    pop ebx
    ret

; -> eax = 1 and hint_a / hint_b = a pair that can be taken, or eax = 0
find_pair:
    push ebx
    push ecx
    push edx
    xor ebx, ebx
.a: mov eax, ebx
    call isfree
    test eax, eax
    jz .na
    mov eax, ebx
    call topkind
    mov edx, eax
    lea ecx, [ebx+1]
.b: cmp ecx, NCELL
    jae .na
    mov eax, ecx
    call isfree
    test eax, eax
    jz .nb
    mov eax, ecx
    call topkind
    cmp eax, edx
    jne .nb
    mov [hint_a], ebx
    mov [hint_b], ecx
    mov eax, 1
    jmp .r
.nb:
    inc ecx
    jmp .b
.na:
    inc ebx
    cmp ebx, NCELL
    jb .a
    xor eax, eax
.r: pop edx
    pop ecx
    pop ebx
    ret

; A seeded, solvable deal (see the top of the file); the removal order
; is kept in order[] as 54 pairs of cells
deal:
    pushad
.retry:
    call layout
    mov edi, tiles
    mov ecx, NL*NCELL
    xor eax, eax
    rep stosb
    ; 54 pairs: every kind twice, shuffled
    xor ecx, ecx
.pk:
    mov eax, ecx
    shr eax, 1
    mov [pairs+ecx], al
    inc ecx
    cmp ecx, NTILE/2
    jb .pk
    mov edi, pairs
    mov ecx, NTILE/2
    call g_shuffle
    xor ebp, ebp                ; pair number
.pair:
    ; the free cells now
    xor ecx, ecx                ; how many
    xor ebx, ebx
.f: mov eax, ebx
    call isfree
    test eax, eax
    jz .fn
    mov [freelist+ecx], bl
    inc ecx
.fn:
    inc ebx
    cmp ebx, NCELL
    jb .f
    cmp ecx, 2
    jb .retry                   ; a dead end: deal again
    call g_randn
    movzx esi, byte [freelist+eax]    ; first cell
    dec ecx
    mov edx, eax
    call g_randn
    cmp eax, edx
    jb .j
    inc eax                     ; skip the first one
.j: movzx edi, byte [freelist+eax]    ; second cell
    mov al, [pairs+ebp]
    mov ebx, esi
    call .place
    mov ebx, edi
    call .place
    mov eax, esi
    mov [order+ebp*2], al
    mov eax, edi
    mov [order+ebp*2+1], al
    inc ebp
    cmp ebp, NTILE/2
    jb .pair
    call layout                 ; every tile back in place
    popad
    ret
.place:                         ; ebx = cell, al = kind: names its top tile, takes it off
    push ecx
    push eax
    movzx ecx, byte [height+ebx]
    dec ecx
    mov [height+ebx], cl
    imul ecx, NCELL
    add ecx, ebx
    pop eax
    mov [tiles+ecx], al
    pop ecx
    ret

; esi = text like "c3" -> ebx = cell, CF set when not a cell
parsecell:
    push eax
    call g_skipsp
    movzx ebx, byte [esi]
    sub ebx, 'a'
    cmp ebx, GW
    jae .bad
    inc esi
    call g_parsenum
    jc .bad
    dec eax
    cmp eax, GH
    jae .bad
    imul eax, GW
    add ebx, eax
    pop eax
    clc
    ret
.bad:
    pop eax
    stc
    ret

putcell:                        ; eax = cell: prints it like "c3"
    push eax
    push edx
    xor edx, edx
    div dword [c_gw]
    push eax
    lea eax, [edx+'a']
    call g_putc
    pop eax
    inc eax
    call g_putdec
    pop edx
    pop eax
    ret

; ---------- screen ----------

draw:
    pushad
    call g_nl
    mov esi, m_cols
    call g_puts
    xor edx, edx                ; row
.row:
    lea eax, [edx+1]
    mov ecx, 2
    call g_putdec_w
    mov al, ' '
    call g_putc
    xor ecx, ecx
.cell:
    imul ebx, edx, GW
    add ebx, ecx
    movzx eax, byte [height+ebx]
    test eax, eax
    jz .empty
    mov eax, ebx
    call topkind
    push edx
    xor edx, edx
    div dword [c_nine]          ; eax = suit, edx = number - 1
    mov al, [suits+eax]
    call g_putc
    lea eax, [edx+'1']
    call g_putc
    pop edx
    mov al, [height+ebx]
    add al, '0'
    call g_putc
    mov eax, ebx
    call isfree
    test eax, eax
    mov al, ' '
    jz .mark
    mov al, '*'
.mark:
    call g_putc
    mov al, ' '
    call g_putc
    jmp .nc
.empty:
    mov esi, m_empty
    call g_puts
.nc:
    inc ecx
    cmp ecx, GW
    jb .cell
    call g_nl
    inc edx
    cmp edx, GH
    jb .row
    mov esi, m_left
    call g_puts
    mov eax, [left]
    call g_putdec
    call g_nl
    popad
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro

selftest:
    ; 1. the pyramid holds 108 tiles
    call layout
    call sum_height
    EXPECT NTILE                ; 1
    ; 2. a seeded deal has every kind four times
    mov eax, 3
    call g_srand
    call deal
    call kinds_ok
    EXPECT 1                    ; 2
    call find_pair
    EXPECT 1                    ; 3: there is a move at the start
    call tiles_hash
    mov [t_hash], eax
    ; 3. the order it was dealt in clears the board, pair by pair
    xor ebp, ebp
    xor edx, edx                ; refused pairs
.replay:
    movzx ebx, byte [order+ebp*2]
    movzx ecx, byte [order+ebp*2+1]
    call take_pair
    xor eax, 1
    add edx, eax
    inc ebp
    cmp ebp, NTILE/2
    jb .replay
    mov eax, edx
    EXPECT 0                    ; 4: every pair was allowed
    mov eax, [left]
    EXPECT 0                    ; 5: the board is clear
    ; 4. the same seed deals the same tiles, another seed others
    mov eax, 3
    call g_srand
    call deal
    call tiles_hash
    EXPECT [t_hash]             ; 6
    mov eax, 4
    call g_srand
    call deal
    call tiles_hash
    cmp eax, [t_hash]
    setne al
    movzx eax, al
    EXPECT 1                    ; 7
    ; 5. the rules on a small board: one row of three, kinds A1 A2 A1
    mov edi, height
    mov ecx, NCELL
    xor eax, eax
    rep stosb
    mov byte [height+20], 1     ; a3 b3 c3
    mov byte [height+21], 1
    mov byte [height+22], 1
    mov byte [tiles+20], 0
    mov byte [tiles+21], 1
    mov byte [tiles+22], 0
    mov byte [height+30], 2     ; a4: two tiles stacked
    mov byte [tiles+30], 5
    mov byte [tiles+NCELL+30], 1
    mov dword [left], 5
    mov eax, 21
    call isfree
    EXPECT 0                    ; 8: b3 has tiles on both sides
    mov eax, 20
    call isfree
    EXPECT 1                    ; 9: a3 is on the edge
    mov ebx, 20
    mov ecx, 21
    call take_pair
    EXPECT 0                    ; 10: A1 and A2 do not match (b3 is not free either)
    mov ebx, 20
    mov ecx, 22
    call take_pair
    EXPECT 1                    ; 11: A1 and A1
    mov eax, 21
    call isfree
    EXPECT 1                    ; 12: b3 is free now
    mov eax, 30
    call topkind
    EXPECT 1                    ; 13: the upper tile of a4 is the A2
    mov ebx, 21
    mov ecx, 30
    call take_pair
    EXPECT 1                    ; 14: A2 and A2, from different heights
    mov eax, 30
    call topkind
    EXPECT 5                    ; 15: the A6 under it shows
    ; 6. the cell parser
    mov esi, t_j6
    call parsecell
    mov eax, ebx
    EXPECT 59                   ; 16
    mov esi, t_k1
    call parsecell
    setc al
    movzx eax, al
    EXPECT 1                    ; 17
    call g_report
    ret

sum_height:                     ; -> eax
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: movzx edx, byte [height+ecx]
    add eax, edx
    inc ecx
    cmp ecx, NCELL
    jb .l
    pop edx
    pop ecx
    ret

kinds_ok:                       ; -> eax = 1 if each kind is dealt 4 times
    pushad
    mov edi, count
    mov ecx, NKIND
    xor eax, eax
    rep stosb
    xor ebx, ebx                ; cell
.c: movzx ecx, byte [height+ebx]
    mov esi, ebx
.k: jecxz .nc
    movzx eax, byte [tiles+esi]
    inc byte [count+eax]
    add esi, NCELL
    dec ecx
    jmp .k
.nc:
    inc ebx
    cmp ebx, NCELL
    jb .c
    xor eax, eax
    xor ecx, ecx
.chk:
    cmp byte [count+ecx], 4
    jne .bad
    inc ecx
    cmp ecx, NKIND
    jb .chk
    inc eax
.bad:
    mov [esp+28], eax
    popad
    ret

tiles_hash:                     ; -> eax
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: movzx edx, byte [tiles+ecx]
    imul eax, 31
    add eax, edx
    inc ecx
    cmp ecx, NL*NCELL
    jb .l
    pop edx
    pop ecx
    ret

c_gw dd GW
c_nine dd 9
; layer rectangles: x0, y0, x1, y1
layer_rect db 0, 0, 9, 5,  1, 1, 8, 4,  2, 2, 7, 3,  4, 2, 5, 3
suits db 'ALS'
t_j6 db 'j6', 0
t_k1 db 'k1', 0

m_name db 'mahjongg', 0
m_title db 'Squirrel Mahjongg - remove matching pairs of free tiles', 10
        db 'Each cell shows its top tile (A, L or S and 1-9), the stack height', 10
        db 'and * if the tile is free. c3 f5 takes a pair, h hints, n new, q quits', 10, 0
m_cols db '   a    b    c    d    e    f    g    h    i    j', 10, 0
m_empty db '  .  ', 0
m_left db 'Tiles left: ', 0
m_prompt db 'mahjongg> ', 0
m_help db 'Type two cells like c3 f5 (or h, n, q)', 10, 0
m_nomatch db 'Those two are not a free matching pair', 10, 0
m_try db 'Try ', 0
m_won db 'The board is clear - you win! n for a new deal, q to quit', 10, 0
m_stuck db 'No free pair is left: n for a new deal, q to quit', 10, 0
w_hint db 'h', 0

SQX_BSS
G_BSS
left resd 1
hint_a resd 1
hint_b resd 1
t_hash resd 1
height resb NCELL
tiles resb NL*NCELL
pairs resb NTILE/2
freelist resb NCELL
order resb NTILE
count resb NKIND
SQX_END
