; reversi — Reversi against the computer (G.8). Original code.
;
;   run reversi [seed]     you play X (moves first), the computer plays O
;   run reversi test       rules self-check (perft from the start, AI), "reversi: PASS"
;
; Commands: a move is a column letter and a row number ("d3"); the
; squares you may play are marked + on the board. n new game, q quits.
; A side with no move passes automatically.
;
; The board is a 10 x 10 mailbox: square (x, y) is index (y+1)*10 + x+1,
; and the border squares hold WALL, so walking a direction stops there.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"

EMPTY equ 0
BLACK equ 1                     ; X, the player
WHITE equ 2                     ; O, the computer
WALL  equ 3
BSIZE equ 100

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov esi, m_title
    call g_puts
.new:
    mov edi, board
    call setup
.loop:
    call draw
    call game_over
    test eax, eax
    jnz .over
    mov edi, board
    mov al, BLACK
    call count_moves
    test eax, eax
    jnz .ask
    mov esi, m_youpass
    call g_puts
    call computer
    jmp .loop
.over:
    call result
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
    call parsesq
    jc .bad
    mov edi, board
    mov al, BLACK
    mov ecx, 1
    call play
    test eax, eax
    jz .bad
    ; the computer answers, and keeps playing while you must pass
.reply:
    mov edi, board
    mov al, WHITE
    call count_moves
    test eax, eax
    jz .loop
    call computer
    mov edi, board
    mov al, BLACK
    call count_moves
    test eax, eax
    jnz .loop
    call game_over
    test eax, eax
    jnz .loop
    call draw
    mov esi, m_youpass
    call g_puts
    jmp .reply
.bad:
    mov esi, m_help
    call g_puts
    jmp .ask
.quit:
    xor eax, eax
    ret

; ---------- rules ----------

; edi = board: the start position
setup:
    pushad
    mov ecx, BSIZE
    xor eax, eax
.c: mov byte [edi+eax], WALL
    mov edx, eax
    push eax
    xor edx, edx
    mov ebx, 10
    div ebx                     ; eax = row, edx = column (0..9)
    cmp eax, 1
    jb .w
    cmp eax, 8
    ja .w
    cmp edx, 1
    jb .w
    cmp edx, 8
    ja .w
    pop eax
    mov byte [edi+eax], EMPTY
    jmp .n
.w: pop eax
.n: inc eax
    loop .c
    mov byte [edi+44], WHITE    ; d4
    mov byte [edi+55], WHITE    ; e5
    mov byte [edi+45], BLACK    ; e4
    mov byte [edi+54], BLACK    ; d5
    popad
    ret

; play wrapper that sets pl_me / pl_opp from al
%macro SETWHO 0
    mov [pl_me], al
    push eax
    xor al, 3
    mov [pl_opp], al
    pop eax
%endmacro

; edi = board, ebx = square, al = player, ecx = 1 to play the move
; (place and flip) or 0 to only count -> eax = discs it flips (0 = illegal)
play:
    SETWHO
play_raw:
    push ebx
    push ecx
    push edx
    push esi
    push ebp
    mov [pl_do], ecx
    mov ah, al
    xor ah, 3                   ; ah = opponent
    xor ebp, ebp                ; total flipped
    cmp byte [edi+ebx], EMPTY
    jne .out
    mov esi, dirs
.dir:
    movsx edx, byte [esi]
    test edx, edx
    jz .done
    inc esi
    ; walk over opponent discs
    xor ecx, ecx
    lea eax, [ebx+edx]          ; (ah/al kept in [pl_who] below)
    jmp .walk0
.walk:
    add eax, edx
.walk0:
    push eax
    movzx eax, byte [edi+eax]
    cmp al, [pl_opp]
    pop eax
    jne .end
    inc ecx
    jmp .walk
.end:
    test ecx, ecx
    jz .dir
    push eax
    movzx eax, byte [edi+eax]
    cmp al, [pl_me]
    pop eax
    jne .dir
    add ebp, ecx
    cmp dword [pl_do], 0
    je .dir
    ; flip them back toward the move
.flip:
    sub eax, edx
    cmp eax, ebx
    je .dir
    push ecx
    mov cl, [pl_me]
    mov [edi+eax], cl
    pop ecx
    jmp .flip
.done:
    test ebp, ebp
    jz .out
    cmp dword [pl_do], 0
    je .out
    mov cl, [pl_me]
    mov [edi+ebx], cl
.out:
    mov eax, ebp
    pop ebp
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; edi = board, al = player -> eax = number of legal moves
count_moves:
    push ebx
    push ecx
    push edx
    SETWHO
    xor edx, edx
    mov ebx, 11
.l: push eax
    xor ecx, ecx
    call play_raw
    test eax, eax
    pop eax
    jz .n
    inc edx
.n: inc ebx
    cmp ebx, 89
    jb .l
    mov eax, edx
    pop edx
    pop ecx
    pop ebx
    ret

; -> eax = 1 when neither side can move
game_over:
    push edi
    mov edi, board
    mov al, BLACK
    call count_moves
    test eax, eax
    jnz .no
    mov al, WHITE
    call count_moves
    test eax, eax
    jnz .no
    mov eax, 1
    pop edi
    ret
.no:
    xor eax, eax
    pop edi
    ret

; edi = board, al = colour -> eax = number of its discs
count_discs:
    push ecx
    push edx
    xor edx, edx
    mov ecx, BSIZE
.l: cmp [edi+ecx-1], al
    jne .n
    inc edx
.n: loop .l
    mov eax, edx
    pop edx
    pop ecx
    ret

; ---------- computer player ----------

; edi = board -> eax = sum of square weights, WHITE minus BLACK
evaluate:
    push ebx
    push ecx
    push edx
    xor eax, eax
    mov ecx, 11
.l: movzx edx, byte [edi+ecx]
    movsx ebx, byte [weights+ecx]
    cmp edx, WHITE
    jne .b
    add eax, ebx
    jmp .n
.b: cmp edx, BLACK
    jne .n
    sub eax, ebx
.n: inc ecx
    cmp ecx, 89
    jb .l
    pop edx
    pop ecx
    pop ebx
    ret

; Two-ply search for WHITE on board: picks the move whose worst BLACK
; reply leaves the best evaluation. Ties are broken by the seeded random
; numbers. -> eax = square, or 0 when WHITE has no move.
choose:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov dword [best_sq], 0
    mov dword [best_sc], -999999
    mov ebx, 11
.mv:
    mov esi, board
    mov edi, ply1
    mov ecx, BSIZE
    rep movsb
    mov edi, ply1
    mov al, WHITE
    mov ecx, 1
    call play
    test eax, eax
    jz .next
    cmp byte [quick], 0         ; one ply only (the self-test's fast games)
    jne .noreply
    ; worst reply for us
    mov dword [worst], 999999
    xor edx, edx                ; replies found
    push ebx
    mov ebx, 11
.rp:
    mov esi, ply1
    mov edi, ply2
    mov ecx, BSIZE
    rep movsb
    mov edi, ply2
    mov al, BLACK
    mov ecx, 1
    call play
    test eax, eax
    jz .rn
    inc edx
    call evaluate
    cmp eax, [worst]
    jge .rn
    mov [worst], eax
.rn:
    inc ebx
    cmp ebx, 89
    jb .rp
    pop ebx
    test edx, edx
    jnz .have
.noreply:
    mov edi, ply1
    call evaluate
    mov [worst], eax
.have:
    mov eax, [worst]
    cmp eax, [best_sc]
    jg .take
    jl .next
    call g_rand
    test eax, 0x100
    jz .next
.take:
    mov eax, [worst]
    mov [best_sc], eax
    mov [best_sq], ebx
.next:
    inc ebx
    cmp ebx, 89
    jb .mv
    mov eax, [best_sq]
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

computer:                       ; WHITE moves on board and says where
    pushad
    call choose
    test eax, eax
    jz .r
    mov ebx, eax
    mov edi, board
    mov al, WHITE
    mov ecx, 1
    call play
    mov esi, m_iplay
    call g_puts
    mov eax, ebx
    call putsq
    call g_nl
.r: popad
    ret

; ---------- screen ----------

; ebx = square -> prints it like "d3"
putsq:
    push eax
    push edx
    push ebx
    mov eax, ebx
    xor edx, edx
    mov ebx, 10
    div ebx
    pop ebx
    push eax
    lea eax, [edx+'a'-1]
    call g_putc
    pop eax
    add al, '0'
    call g_putc
    pop edx
    pop eax
    ret

; esi = text like "d3" -> ebx = square, CF set when not a square
parsesq:
    push eax
    call g_skipsp
    movzx ebx, byte [esi]
    sub ebx, 'a'
    cmp ebx, 8
    jae .bad
    inc esi
    call g_parsenum
    jc .bad
    dec eax
    cmp eax, 8
    jae .bad
    inc eax
    imul eax, 10
    lea ebx, [ebx+eax+1]
    pop eax
    clc
    ret
.bad:
    pop eax
    stc
    ret

draw:
    pushad
    call g_nl
    mov esi, m_cols
    call g_puts
    mov edi, board
    mov edx, 1
.row:
    mov eax, edx
    mov ecx, 3
    call g_putdec_w
    mov al, ' '
    call g_putc
    mov ecx, 1
.sq:
    mov ebx, edx
    imul ebx, 10
    add ebx, ecx
    movzx eax, byte [edi+ebx]
    mov al, [glyph+eax]
    cmp al, '.'
    jne .put
    push eax
    push ecx
    mov al, BLACK
    xor ecx, ecx
    call play
    test eax, eax
    pop ecx
    pop eax
    jz .put
    mov al, '+'
.put:
    call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, 8
    jbe .sq
    call g_nl
    inc edx
    cmp edx, 8
    jbe .row
    mov esi, m_you
    call g_puts
    mov al, BLACK
    call count_discs
    call g_putdec
    mov esi, m_me
    call g_puts
    mov al, WHITE
    call count_discs
    call g_putdec
    call g_nl
    popad
    ret

result:
    pushad
    mov edi, board
    mov al, BLACK
    call count_discs
    mov edx, eax
    mov al, WHITE
    call count_discs
    mov esi, m_draw
    cmp edx, eax
    je .p
    mov esi, m_youwin
    ja .p
    mov esi, m_iwin
.p: call g_puts
    popad
    ret

; ---------- self-test ----------

; edi = board, al = side to move, ecx = depth -> eax = leaf count.
; A side with no move passes (one ply); two passes end the game (a leaf).
PF_MOVES equ BSIZE
PF_DEPTH equ BSIZE+4
PF_LEAVES equ BSIZE+8
PF_SRC equ BSIZE+12
perft:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    test ecx, ecx
    jnz .go
    mov eax, 1
    jmp .r
.go:
    sub esp, BSIZE+16
    mov ebp, esp
    movzx edx, al
    mov [ebp+PF_DEPTH], ecx
    mov [ebp+PF_SRC], edi
    mov dword [ebp+PF_MOVES], 0
    mov dword [ebp+PF_LEAVES], 0
    mov ebx, 11
.mv:
    mov esi, [ebp+PF_SRC]
    mov edi, ebp
    mov ecx, BSIZE
    rep movsb
    mov edi, ebp
    mov al, dl
    mov ecx, 1
    call play
    test eax, eax
    jz .skip
    inc dword [ebp+PF_MOVES]
    mov al, dl
    xor al, 3
    mov ecx, [ebp+PF_DEPTH]
    dec ecx
    call perft
    add [ebp+PF_LEAVES], eax
.skip:
    inc ebx
    cmp ebx, 89
    jb .mv
    cmp dword [ebp+PF_MOVES], 0
    jne .done
    ; no move: pass, unless the other side cannot move either
    mov edi, [ebp+PF_SRC]
    mov al, dl
    xor al, 3
    call count_moves
    test eax, eax
    jz .leaf
    mov al, dl
    xor al, 3
    mov ecx, [ebp+PF_DEPTH]
    dec ecx
    call perft
    mov [ebp+PF_LEAVES], eax
    jmp .done
.leaf:
    mov dword [ebp+PF_LEAVES], 1
.done:
    mov eax, [ebp+PF_LEAVES]
    add esp, BSIZE+16
.r: pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

selftest:
    mov eax, 11
    call g_srand
    ; 1. the start position: four moves for X, d3 among them
    mov edi, board
    call setup
    mov al, BLACK
    call count_moves
    mov ebx, 4
    call g_expect               ; 1
    mov esi, t_d3
    call parsesq
    mov eax, ebx
    mov ebx, 34
    call g_expect               ; 2: d3 = (3+1)*10 + 3+1... = 34
    ; 2. d3 flips d4 only
    mov edi, board
    mov ebx, 34
    mov al, BLACK
    mov ecx, 1
    call play
    mov ebx, 1
    call g_expect               ; 3
    mov al, BLACK
    call count_discs
    mov ebx, 4
    call g_expect               ; 4
    mov al, WHITE
    call count_discs
    mov ebx, 1
    call g_expect               ; 5
    ; 3. a move that flips nothing is refused and changes nothing
    mov ebx, 11                 ; a1
    mov al, BLACK
    mov ecx, 1
    call play
    xor ebx, ebx
    call g_expect               ; 6
    movzx eax, byte [edi+11]
    xor ebx, ebx
    call g_expect               ; 7
    ; 4. perft from the start: 4, 12, 56, 244 positions
    mov ecx, 1
.pf:
    mov edi, board
    call setup
    mov al, BLACK
    call perft
    mov ebx, [perft_want+ecx*4-4]
    call g_expect               ; 8..11
    inc ecx
    cmp ecx, 4
    jbe .pf
    ; 5. the computer takes a corner when it can
    mov edi, board
    call setup
    mov byte [edi+44], EMPTY    ; clear the centre
    mov byte [edi+55], EMPTY
    mov byte [edi+45], EMPTY
    mov byte [edi+54], EMPTY
    mov byte [edi+12], BLACK    ; b1 X, c1 O: O plays a1 to flip b1
    mov byte [edi+13], WHITE
    mov byte [edi+66], BLACK    ; f6 X, g7 O: O could also play e5
    mov byte [edi+77], WHITE
    call choose
    mov ebx, 11
    call g_expect               ; 12
    ; 6. a board with only X discs is over, and X has won
    mov edi, board
    call setup
    mov byte [edi+44], BLACK
    mov byte [edi+55], BLACK
    call game_over
    mov ebx, 1
    call g_expect               ; 13
    ; 7. the computer plays itself to the end: 64 squares accounted for
    mov edi, board
    call setup
    mov dword [moves], 0
    mov byte [quick], 1
.self:
    call game_over
    test eax, eax
    jnz .end
    call computer_quiet
    ; mirror the board so the same search plays the other side
    call swap_colours
    inc dword [moves]
    cmp dword [moves], 200
    jb .self
.end:
    mov edi, board
    mov al, BLACK
    call count_discs
    mov edx, eax
    mov al, WHITE
    call count_discs
    add edx, eax
    mov al, EMPTY
    call count_discs
    add eax, edx
    mov ebx, 64
    call g_expect               ; 14
    mov eax, [moves]
    cmp eax, 200
    setb al
    movzx eax, al
    mov ebx, 1
    call g_expect               ; 15: the game ended
    call g_report
    ret

computer_quiet:                 ; WHITE moves (or passes) without printing
    pushad
    call choose
    test eax, eax
    jz .r
    mov ebx, eax
    mov edi, board
    mov al, WHITE
    mov ecx, 1
    call play
.r: popad
    ret

swap_colours:
    push ecx
    mov ecx, 11
.l: mov al, [board+ecx]
    cmp al, BLACK
    je .w
    cmp al, WHITE
    jne .n
    mov byte [board+ecx], BLACK
    jmp .n
.w: mov byte [board+ecx], WHITE
.n: inc ecx
    cmp ecx, 89
    jb .l
    pop ecx
    ret

dirs db -11, -10, -9, -1, 1, 9, 10, 11, 0
glyph db '.XO#'
perft_want dd 4, 12, 56, 244
; square weights on the mailbox (corners good, the squares next to them bad)
weights:
    db 0,   0,   0,  0,  0,  0,  0,   0,   0, 0
    db 0, 100, -20, 10,  5,  5, 10, -20, 100, 0
    db 0, -20, -50, -2, -2, -2, -2, -50, -20, 0
    db 0,  10,  -2,  1,  1,  1,  1,  -2,  10, 0
    db 0,   5,  -2,  1,  0,  0,  1,  -2,   5, 0
    db 0,   5,  -2,  1,  0,  0,  1,  -2,   5, 0
    db 0,  10,  -2,  1,  1,  1,  1,  -2,  10, 0
    db 0, -20, -50, -2, -2, -2, -2, -50, -20, 0
    db 0, 100, -20, 10,  5,  5, 10, -20, 100, 0
    db 0,   0,   0,  0,  0,  0,  0,   0,   0, 0

m_name db 'reversi', 0
m_title db 'Squirrel Reversi - you are X and move first; + marks your moves', 10
        db 'Type a square like d3, n for a new game, q to quit', 10, 0
m_cols db '    a b c d e f g h', 10, 0
m_you db 'You (X): ', 0
m_me db '   Computer (O): ', 0
m_prompt db 'reversi> ', 0
m_help db 'Type a square marked + (like d3), n or q', 10, 0
m_iplay db 'Computer plays ', 0
m_youpass db 'You have no move and pass.', 10, 0
m_youwin db 'Game over: you win! n for a new game, q to quit', 10, 0
m_iwin db 'Game over: the computer wins. n for a new game, q to quit', 10, 0
m_draw db 'Game over: a draw. n for a new game, q to quit', 10, 0
t_d3 db 'd3', 0

SQX_BSS
G_BSS
pl_do resd 1
best_sq resd 1
best_sc resd 1
worst resd 1
moves resd 1
pl_me resb 1
pl_opp resb 1
quick resb 1
alignb 4
board resb BSIZE
ply1 resb BSIZE
ply2 resb BSIZE
SQX_END
