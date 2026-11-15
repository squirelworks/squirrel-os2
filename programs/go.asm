; go — Go on a 9 x 9 board against the computer (G.9). Original code.
;
;   run go [seed]          you play Black (X) and move first; the computer
;                          plays White (O)
;   run go test            rules self-check (captures, suicide, ko,
;                          scoring, the computer), prints "go: PASS"
;
; Stones are placed on the empty points; a group with no liberty left is
; taken off the board. A move that leaves its own group without a
; liberty (and takes nothing) is not allowed, and neither is retaking a
; ko at once: a single stone may not take back the single stone that has
; just taken it. The game ends when both players pass in a row and is
; scored by area: every stone on the board and every empty point
; surrounded only by one colour counts a point for that colour, and
; White gets 7 points of komi for moving second. Stones that are dead
; are not taken off at the end, so capture them before you pass.
;
; Commands: a point is a column letter a-i and a row 1-9 ("e5").
;   pass      pass            score     count the board as it stands
;   n         new game        q         quit
;
; The computer looks one move ahead with rules of thumb: take stones,
; save its own groups from atari, put yours in atari, keep liberties,
; never fill its own eyes, and early on prefer the third and fourth lines.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"

EMPTY  equ 0
BLACK  equ 1                    ; X, you
WHITE  equ 2                    ; O, the computer
WALL   equ 3
N      equ 9
W      equ N + 2                ; the board with a wall round it
BSIZE  equ W * W
NOSQ   equ 0
KOMI   equ 7
MAXMOVES equ 300

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov esi, m_title
    call g_puts
.new:
    call setup
.loop:
    call draw
    cmp byte [over], 0
    je .ask
    call show_score
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
    mov edi, w_score
    call g_word
    jnc .score
    cmp byte [over], 0
    jne .bad
    mov edi, w_pass
    call g_word
    jnc .pass
    call parsept
    jc .bad
    mov al, BLACK
    call play
    test eax, eax
    jz .illegal
    mov byte [passes], 0
    jmp .reply
.pass:
    mov dword [ko], NOSQ        ; a pass ends a ko
    inc byte [passes]
    cmp byte [passes], 2
    jae .end
.reply:
    mov al, WHITE
    call choose                 ; ebx = point, or NOSQ to pass
    test ebx, ebx
    jz .ipass
    mov al, WHITE
    call play
    mov byte [passes], 0
    mov esi, m_iplay
    call g_puts
    call putpt
    call g_nl
    jmp .loop
.ipass:
    mov dword [ko], NOSQ
    mov esi, m_ipass
    call g_puts
    inc byte [passes]
    cmp byte [passes], 2
    jb .loop
.end:
    mov byte [over], 1
    jmp .loop
.score:
    call show_score
    jmp .ask
.illegal:
    mov esi, m_illegal
    call g_puts
    jmp .ask
.bad:
    mov esi, m_help
    call g_puts
    jmp .ask
.quit:
    xor eax, eax
    ret

; ---------- rules ----------

; An empty board with its wall; nobody has passed
setup:
    pushad
    mov edi, pos
    mov ecx, 128 / 4
    xor eax, eax
    rep stosd
    xor ebx, ebx
.l: mov eax, ebx
    xor edx, edx
    mov ecx, W
    div ecx                     ; eax = row, edx = column (0..W-1)
    cmp eax, 0
    je .w
    cmp eax, W - 1
    je .w
    cmp edx, 0
    je .w
    cmp edx, W - 1
    jne .n
.w: mov byte [board+ebx], WALL
.n: inc ebx
    cmp ebx, BSIZE
    jb .l
    mov dword [ko], NOSQ
    mov byte [passes], 0
    mov byte [over], 0
    mov dword [nmoves], 0
    popad
    ret

; ebx = a stone -> eax = its group's liberties; g_n = its stones, listed
; in g_list; g_lib = one of the liberties
group:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    inc dword [stamp]
    mov edx, [stamp]
    mov cl, [board+ebx]         ; the colour
    mov [g_list], bl
    mov [mark+ebx*4], edx
    mov dword [g_n], 1
    xor eax, eax                ; liberties
    xor esi, esi                ; next stone to look round
.s: cmp esi, [g_n]
    jae .d
    movzx ebx, byte [g_list+esi]
    xor edi, edi
.nb:push ebx
    add ebx, [nbr+edi*4]
    mov ch, [board+ebx]
    cmp ch, cl
    jne .lib
    cmp [mark+ebx*4], edx
    je .nn
    mov [mark+ebx*4], edx       ; a stone of the group
    push eax
    mov eax, [g_n]
    mov [g_list+eax], bl
    inc dword [g_n]
    pop eax
    jmp .nn
.lib:
    cmp ch, EMPTY
    jne .nn
    cmp [lmark+ebx*4], edx
    je .nn
    mov [lmark+ebx*4], edx      ; a liberty not counted yet
    inc eax
    mov [g_lib], ebx
.nn:pop ebx
    inc edi
    cmp edi, 4
    jb .nb
    inc esi
    jmp .s
.d: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebx = point, al = colour: plays a stone there -> eax = 1 if it was
; legal (stones taken off, ko set), 0 if not (nothing changed);
; [taken] = stones it took
play:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov dword [taken], 0
    cmp byte [board+ebx], EMPTY
    jne .no
    cmp ebx, [ko]
    je .no
    mov [board+ebx], al
    mov cl, al
    xor cl, 3                   ; the other colour
    xor edi, edi
.nb:mov esi, ebx
    add esi, [nbr+edi*4]
    cmp [board+esi], cl
    jne .nn
    push ebx
    mov ebx, esi
    call group
    pop ebx
    test eax, eax
    jnz .nn
    ; no liberty left: off the board
    mov eax, [g_n]
    add [taken], eax
    xor edx, edx
.rm:movzx esi, byte [g_list+edx]
    mov byte [board+esi], EMPTY
    mov [ko_cand], esi
    inc edx
    cmp edx, [g_n]
    jb .rm
.nn:inc edi
    cmp edi, 4
    jb .nb
    call group                  ; the new stone's own group
    test eax, eax
    jnz .ok
    mov byte [board+ebx], EMPTY ; suicide
    jmp .no
.ok:mov dword [ko], NOSQ
    cmp dword [taken], 1
    jne .yes
    cmp dword [g_n], 1
    jne .yes
    cmp eax, 1
    jne .yes
    mov eax, [ko_cand]          ; a ko: the stone taken may not come back now
    mov [ko], eax
.yes:
    inc dword [nmoves]
    mov eax, 1
    jmp .r
.no:xor eax, eax
.r: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; -> eax = Black's area, edx = White's area (stones and surrounded points)
area:
    push ebx
    push ecx
    push esi
    push edi
    xor eax, eax
    xor edx, edx
    mov [ar_b], eax
    mov [ar_w], eax
    inc dword [stamp]
    mov ebx, W + 1
.p: mov cl, [board+ebx]
    cmp cl, BLACK
    jne .pw
    inc dword [ar_b]
    jmp .pn
.pw:cmp cl, WHITE
    jne .pe
    inc dword [ar_w]
    jmp .pn
.pe:cmp cl, EMPTY
    jne .pn
    mov edi, [stamp]
    cmp [mark+ebx*4], edi
    je .pn
    call region                 ; eax = size, ecx = colours it touches
    cmp ecx, BLACK
    jne .rw
    add [ar_b], eax
    jmp .pn
.rw:cmp ecx, WHITE
    jne .pn
    add [ar_w], eax
.pn:inc ebx
    cmp ebx, BSIZE - W - 1
    jb .p
    mov eax, [ar_b]
    mov edx, [ar_w]
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; ebx = an empty point not marked yet with [stamp] -> eax = the size of
; its empty region, ecx = the colours round it (1 Black, 2 White, 3 both)
region:
    push ebx
    push edx
    push esi
    push edi
    mov edx, [stamp]
    mov [mark+ebx*4], edx
    mov [g_list], bl
    mov dword [g_n], 1
    xor ecx, ecx
    xor esi, esi
.s: cmp esi, [g_n]
    jae .d
    movzx ebx, byte [g_list+esi]
    xor edi, edi
.nb:push ebx
    add ebx, [nbr+edi*4]
    movzx eax, byte [board+ebx]
    cmp eax, EMPTY
    jne .c
    cmp [mark+ebx*4], edx
    je .nn
    mov [mark+ebx*4], edx
    mov eax, [g_n]
    mov [g_list+eax], bl
    inc dword [g_n]
    jmp .nn
.c: cmp eax, WALL
    je .nn
    or ecx, eax
.nn:pop ebx
    inc edi
    cmp edi, 4
    jb .nb
    inc esi
    jmp .s
.d: mov eax, [g_n]
    pop edi
    pop esi
    pop edx
    pop ebx
    ret

; ---------- computer player ----------

; al = colour to play -> ebx = the point it chooses, or NOSQ to pass
choose:
    push eax
    push ecx
    push edx
    push esi
    push edi
    mov [ai_col], al
    mov dword [ai_best], NOSQ
    mov dword [ai_bsc], 0       ; a move must be worth more than passing
    ; how many stones there are: the opening prefers the third line
    xor ecx, ecx
    xor ebx, ebx
.cnt:
    mov al, [board+ebx]
    cmp al, BLACK
    je .c1
    cmp al, WHITE
    jne .c2
.c1:inc ecx
.c2:inc ebx
    cmp ebx, BSIZE
    jb .cnt
    mov [ai_stones], ecx
    mov ebx, W + 1
.pt:cmp byte [board+ebx], EMPTY
    jne .next
    call rate                   ; eax = the move's worth, or -1 if not
    cmp eax, [ai_bsc]
    jle .next
    mov [ai_bsc], eax
    mov [ai_best], ebx
.next:
    inc ebx
    cmp ebx, BSIZE - W - 1
    jb .pt
    mov ebx, [ai_best]
    pop edi
    pop esi
    pop edx
    pop ecx
    pop eax
    ret

; ebx = an empty point, [ai_col] = colour -> eax = the worth of playing
; there (higher is better), or -1 when it is illegal or fills an eye
rate:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    ; an eye of its own (every neighbour its stone or the wall, none of
    ; them in atari) is never filled
    xor edi, edi
    xor edx, edx                ; neighbours that are its own or wall
.eye:
    mov esi, ebx
    add esi, [nbr+edi*4]
    mov al, [board+esi]
    cmp al, WALL
    je .ey
    cmp al, [ai_col]
    jne .en
    push ebx
    mov ebx, esi
    call group
    pop ebx
    cmp eax, 1
    je .en
.ey:inc edx
.en:inc edi
    cmp edi, 4
    jb .eye
    cmp edx, 4
    je .never
    ; what the point's neighbours are now: own groups in atari, enemy
    ; groups in atari (taken by this move), contacts
    xor ecx, ecx                ; worth
    xor edi, edi
.nb:mov esi, ebx
    add esi, [nbr+edi*4]
    movzx eax, byte [board+esi]
    cmp al, EMPTY
    je .nn
    cmp al, WALL
    je .nn
    push ebx
    mov ebx, esi
    push eax
    call group                  ; eax = liberties
    mov edx, eax
    pop eax
    pop ebx
    cmp al, [ai_col]
    jne .enemy
    inc ecx                     ; next to its own stone
    cmp edx, 1
    jne .nn
    mov eax, [g_n]              ; its group in atari: saving it is worth
    imul eax, 40                ; a lot (if the move does save it, below)
    add [ai_save], eax
    jmp .nn
.enemy:
    add ecx, 3                  ; contact with the other side
    cmp edx, 1
    jne .e2
    mov eax, [g_n]              ; taken by this move
    imul eax, 60
    add ecx, eax
    add ecx, 20
    jmp .nn
.e2:cmp edx, 2
    jne .nn
    mov eax, [g_n]              ; put in atari by this move
    imul eax, 12
    add ecx, eax
.nn:inc edi
    cmp edi, 4
    jb .nb
    ; play it on a copy of the position
    push ecx
    mov esi, pos
    mov edi, pos_save
    mov ecx, 128 / 4
    rep movsd
    pop ecx
    mov al, [ai_col]
    call play
    test eax, eax
    jz .undo_never
    call group                  ; its own group now
    mov edx, eax                ; liberties
    cmp edx, 1
    jne .safe
    cmp dword [taken], 0
    jne .safe
    mov eax, [g_n]              ; self-atari
    imul eax, 50
    add eax, 25
    sub ecx, eax
    mov dword [ai_save], 0
.safe:
    cmp edx, 2
    jb .ns
    add ecx, [ai_save]          ; the group in atari is out of it
.ns:mov dword [ai_save], 0
    cmp edx, 6
    jbe .lb
    mov edx, 6
.lb:lea ecx, [ecx+edx*2]
    ; where it is: the edge is poor, the third and fourth lines are good
    ; in the opening
    mov eax, ebx
    xor edx, edx
    push ecx
    mov ecx, W
    div ecx
    pop ecx
    dec eax                     ; row 0-8
    dec edx                     ; column 0-8
    mov esi, eax
    cmp edx, esi
    jae .l1
    mov esi, edx
.l1:mov edi, N - 1
    sub edi, eax
    cmp edi, esi
    jae .l2
    mov esi, edi
.l2:mov edi, N - 1
    sub edi, edx
    cmp edi, esi
    jae .l3
    mov esi, edi                ; esi = line, 0 = the edge
.l3:movsx eax, byte [linev+esi]
    cmp dword [ai_stones], 12
    jb .open
    sar eax, 1                  ; later on it matters less
.open:
    add ecx, eax
    call g_rand
    and eax, 7
    add ecx, eax
    ; put the position back
    push ecx
    mov esi, pos_save
    mov edi, pos
    mov ecx, 128 / 4
    rep movsd
    pop ecx
    dec dword [nmoves]
    mov eax, ecx
    jmp .r
.undo_never:
    mov dword [ai_save], 0
.never:
    mov eax, -1
.r: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- screen ----------

; esi = text like "e5" -> ebx = the point, CF set when it is not one
parsept:
    push eax
    call g_skipsp
    movzx ebx, byte [esi]
    sub ebx, 'a'
    cmp ebx, N
    jae .bad
    inc esi
    call g_parsenum
    jc .bad
    dec eax
    cmp eax, N
    jae .bad
    inc eax
    imul eax, W
    lea ebx, [ebx+eax+1]
    pop eax
    clc
    ret
.bad:
    pop eax
    stc
    ret

; ebx = point: prints it like "e5"
putpt:
    push eax
    push edx
    push ecx
    mov eax, ebx
    xor edx, edx
    mov ecx, W
    div ecx
    push eax
    lea eax, [edx-1+'a']
    call g_putc
    pop eax
    call g_putdec
    pop ecx
    pop edx
    pop eax
    ret

draw:
    pushad
    call g_nl
    mov esi, m_cols
    call g_puts
    mov edx, N                  ; row
.r: mov eax, edx
    mov ecx, 3
    call g_putdec_w
    mov al, ' '
    call g_putc
    mov ecx, 1
.c: imul ebx, edx, W
    add ebx, ecx
    movzx eax, byte [board+ebx]
    mov al, [glyph+eax]
    cmp al, '.'
    jne .p
    call star
    jnz .p
    mov al, '+'
.p: call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, N
    jbe .c
    mov eax, edx
    call g_putdec
    call g_nl
    dec edx
    jnz .r
    mov esi, m_cols
    call g_puts
    popad
    ret

; ebx = point -> ZF set on the five marked points (c3 g3 e5 c7 g7)
star:
    push eax
    push ecx
    mov ecx, 5
.l: movzx eax, byte [stars+ecx-1]
    cmp eax, ebx
    je .r
    loop .l
    or ecx, 1                   ; ZF clear
.r: pop ecx
    pop eax
    ret

show_score:
    pushad
    call area
    push edx
    push eax
    mov esi, m_sb
    call g_puts
    pop eax
    push eax
    call g_putdec
    mov esi, m_sw
    call g_puts
    mov eax, [esp+4]
    add eax, KOMI
    call g_putdec
    mov esi, m_komi
    call g_puts
    pop eax
    pop edx
    cmp byte [over], 0
    je .r
    add edx, KOMI
    mov esi, m_drawn
    cmp eax, edx
    je .p
    mov esi, m_youwin
    ja .p
    mov esi, m_iwin
.p: call g_puts
.r: popad
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%define PT(c, r) ((r) * W + (c) - 'a' + 1)
%macro STONE 2                  ; point, colour
    mov byte [board + %1], %2
%endmacro
%macro PLAY 2                   ; point, colour -> eax = legal
    mov ebx, %1
    mov al, %2
    call play
%endmacro

selftest:
    mov eax, 5
    call g_srand
    ; 1-2. a stone with no liberty is taken
    call setup
    STONE PT('d',5), BLACK
    STONE PT('f',5), BLACK
    STONE PT('e',4), BLACK
    STONE PT('e',5), WHITE
    PLAY PT('e',6), BLACK
    EXPECT 1
    movzx eax, byte [board+PT('e',5)]
    EXPECT EMPTY
    ; 3-4. a group of two in the corner
    call setup
    STONE PT('a',1), WHITE
    STONE PT('b',1), WHITE
    STONE PT('a',2), BLACK
    STONE PT('b',2), BLACK
    PLAY PT('c',1), BLACK
    mov eax, [taken]
    EXPECT 2
    movzx eax, byte [board+PT('a',1)]
    EXPECT EMPTY
    ; 5-6. suicide is refused and changes nothing
    call setup
    STONE PT('a',2), BLACK
    STONE PT('b',1), BLACK
    PLAY PT('a',1), WHITE
    EXPECT 0
    movzx eax, byte [board+PT('a',1)]
    EXPECT EMPTY
    ; 7-12. ko: Black takes at f5, White may not take back at once, but
    ; may after a move elsewhere
    call setup
    STONE PT('d',5), BLACK
    STONE PT('e',6), BLACK
    STONE PT('e',4), BLACK
    STONE PT('e',5), WHITE
    STONE PT('f',6), WHITE
    STONE PT('f',4), WHITE
    STONE PT('g',5), WHITE
    PLAY PT('f',5), BLACK
    EXPECT 1
    movzx eax, byte [board+PT('e',5)]
    EXPECT EMPTY
    PLAY PT('e',5), WHITE
    EXPECT 0
    PLAY PT('a',9), WHITE
    PLAY PT('a',1), BLACK
    PLAY PT('e',5), WHITE
    EXPECT 1
    movzx eax, byte [board+PT('f',5)]
    EXPECT EMPTY
    mov eax, [ko]
    EXPECT PT('f',5)
    ; 13-15. area: one black stone owns the whole board
    call setup
    call area
    EXPECT 0
    STONE PT('e',5), BLACK
    call area
    push edx
    EXPECT 81
    pop eax
    EXPECT 0
    ; 16. the computer takes a stone in atari
    call setup
    STONE PT('e',5), BLACK
    STONE PT('d',5), WHITE
    STONE PT('f',5), WHITE
    STONE PT('e',6), WHITE
    mov al, WHITE
    call choose
    mov eax, ebx
    EXPECT PT('e',4)
    ; 17. it saves its own stone in atari
    call setup
    STONE PT('e',5), WHITE
    STONE PT('d',5), BLACK
    STONE PT('f',5), BLACK
    STONE PT('e',6), BLACK
    mov al, WHITE
    call choose
    mov eax, ebx
    EXPECT PT('e',4)
    ; 18. it does not fill its own eye in the corner
    call setup
    STONE PT('a',2), WHITE
    STONE PT('b',2), WHITE
    STONE PT('b',1), WHITE
    STONE PT('a',3), WHITE
    STONE PT('b',3), WHITE
    STONE PT('c',1), WHITE
    STONE PT('c',2), WHITE
    STONE PT('c',3), WHITE
    mov al, WHITE
    call rate_at_a1
    EXPECT -1
    ; 19-21. the computer plays itself to two passes; the areas fit on
    ; the board, and the same seed plays the same game
    mov eax, 21
    call selfplay
    mov [t_hash], eax
    mov eax, edx
    EXPECT 1
    call area
    add eax, edx
    cmp eax, BSIZE
    setbe al
    movzx eax, al
    EXPECT 1
    mov eax, 21
    call selfplay
    mov ebx, [t_hash]
    call g_expect
    call g_report
    ret

; al = colour -> eax = rate of a1 for it
rate_at_a1:
    mov [ai_col], al
    mov dword [ai_stones], 20
    mov dword [ai_save], 0
    push ebx
    mov ebx, PT('a',1)
    call rate
    pop ebx
    ret

; eax = seed: the computer plays both colours from the empty board until
; both pass (at most MAXMOVES moves) -> eax = hash of the board, edx = 1
; when the game ended with two passes
selfplay:
    call g_srand
    call setup
    mov byte [t_col], BLACK
    xor ecx, ecx
    xor edx, edx                ; passes in a row
.l: cmp ecx, MAXMOVES
    jae .stop
    mov al, [t_col]
    call choose
    test ebx, ebx
    jz .pass
    mov al, [t_col]
    call play
    xor edx, edx
    jmp .n
.pass:
    mov dword [ko], NOSQ
    inc edx
    cmp edx, 2
    jae .end
.n: xor byte [t_col], 3
    inc ecx
    jmp .l
.end:
    mov edx, 1
    jmp .h
.stop:
    xor edx, edx
.h: xor eax, eax
    xor ebx, ebx
.hl:imul eax, 31
    movzx esi, byte [board+ebx]
    add eax, esi
    inc ebx
    cmp ebx, BSIZE
    jb .hl
    ret

; ---------- data ----------

nbr dd -1, 1, -W, W
glyph db '.XO#'
stars db PT('c',3), PT('g',3), PT('e',5), PT('c',7), PT('g',7)
; the worth of a point by its line (0 = the edge) in the opening
linev db -12, -3, 6, 5, 3

m_name db 'go', 0
m_title db 'Squirrel Go - 9 x 9, you are Black (X) and move first, komi 7.', 10
        db 'Type a point like e5, pass, score, n or q', 10, 0
m_cols db '    a b c d e f g h i', 10, 0
m_prompt db 'go> ', 0
m_help db 'Type a point like e5 (or pass, score, n, q)', 10, 0
m_illegal db 'You cannot play there (taken, suicide, or ko)', 10, 0
m_iplay db 'Computer plays ', 0
m_ipass db 'Computer passes', 10, 0
m_sb db 'Black (you) ', 0
m_sw db ', White ', 0
m_komi db ' with komi', 10, 0
m_youwin db 'Game over: you win! n for a new game, q to quit', 10, 0
m_iwin db 'Game over: the computer wins. n for a new game, q to quit', 10, 0
m_drawn db 'Game over: a draw. n for a new game, q to quit', 10, 0
w_pass db 'pass', 0
w_score db 'score', 0

SQX_BSS
G_BSS
stamp resd 1
g_n resd 1
g_lib resd 1
taken resd 1
ko_cand resd 1
ar_b resd 1
ar_w resd 1
ai_best resd 1
ai_bsc resd 1
ai_save resd 1
ai_stones resd 1
t_hash resd 1
passes resb 1
over resb 1
ai_col resb 1
t_col resb 1
alignb 4
pos:                            ; what play changes, copied as a block
board resb 124
ko resd 1
nmoves resd 1
alignb 4
pos_save resb 128
g_list resb BSIZE
alignb 4
mark resd BSIZE
lmark resd BSIZE
SQX_END
