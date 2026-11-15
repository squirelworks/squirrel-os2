; checkers — draughts against the computer (G.9). Original code.
;
;   run checkers [seed]    you play Black (b, B) and move first; the
;                          computer plays White (w, W)
;   run checkers test      rules self-check (perft, captures, crowning, AI),
;                          prints "checkers: PASS"
;
; The rules of English draughts, on the dark squares of an 8 x 8 board:
; men move one square diagonally forward, kings (B, W) forward and back.
; A capture jumps an enemy piece next to it onto the empty square beyond,
; and goes on jumping while it can; capturing is compulsory, but when
; there are several captures any of them may be chosen. A man reaching
; the far row is crowned, and its move ends there. A side with no move
; (or no pieces) loses; 80 moves in a row without a capture and without
; a man moving are a draw.
;
; Commands: a move lists its squares, like "c3d4" or "c3-d4"; a jump
; lists every landing square, "c3e5g3" or "c3xe5xg3" (the first and the
; last square are enough when only one jump joins them).
;   level N   the computer's search depth, 1-8 (default 6)
;   n         new game            q   quit
;
; The board is 0x88-style: square = rank * 16 + file (a1 = 0x00,
; h8 = 0x77); a square with bit 0x88 set is off the board. The computer
; is a negamax alpha-beta search that goes on searching while captures
; are pending; equal moves are chosen between with the seeded random
; numbers.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"

EMPTY  equ 0
BMAN   equ 1                    ; Black: you
BKING  equ 2
WMAN   equ 3                    ; White: the computer
WKING  equ 4
CAPT   equ 5                    ; a piece already jumped in this move
; a move: +0 how many squares, +1.. the squares (from, landing squares),
; +M_NCAP how many it captures, +M_CAPS.. the squares captured
MOVESZ equ 32
M_NCAP equ 14
M_CAPS equ 15
MAXMV  equ 48                   ; moves kept per position
MAXPLY equ 24
WIN    equ 10000
INF    equ 30000
DRAWN  equ 80
YOU    equ 0
ME     equ 1

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov dword [depth], 6
    mov esi, m_title
    call g_puts
.new:
    call setup
    mov byte [winner], 0
.loop:
    call draw
    call outcome
    mov esi, [res_msg+eax*4]
    test eax, eax
    jz .ask
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
    mov edi, w_level
    call g_word
    jnc .level
    cmp byte [winner], 0
    jne .bad
    call parse_move             ; esi = the move, or 0
    test esi, esi
    jz .illegal
    call play_move
    call outcome
    test eax, eax
    jnz .loop
    call draw
    mov esi, m_think
    call g_puts
    call think                  ; esi = the move
    test esi, esi
    jz .loop
    push esi
    mov esi, m_iplay
    call g_puts
    pop esi
    call put_move
    call g_nl
    call play_move
    jmp .loop
.level:
    call g_parsenum
    jc .bad
    cmp eax, 1
    jb .bad
    cmp eax, 8
    ja .bad
    mov [depth], eax
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

; The start position in board, Black to move
setup:
    pushad
    mov edi, board
    mov ecx, 32
    xor eax, eax
    rep stosd
    xor ebx, ebx
.sq:test ebx, 0x88
    jnz .n
    call dark
    jnz .n
    mov eax, ebx
    shr eax, 4                  ; rank 0-7
    cmp eax, 3
    jae .w
    mov byte [board+ebx], BMAN
    jmp .n
.w: cmp eax, 5
    jb .n
    mov byte [board+ebx], WMAN
.n: inc ebx
    cmp ebx, 0x78
    jb .sq
    mov byte [side], YOU
    mov dword [quiet], 0
    popad
    ret

; ebx = square -> ZF set when it is a dark (playing) square
dark:
    push eax
    mov eax, ebx
    shr eax, 4
    add eax, ebx
    test eax, 1
    pop eax
    ret

; edi = buffer, [bd] = board, [gside] = side -> eax = its legal moves
; (MOVESZ bytes each) written there; [gcap] = 1 when they are captures
gen:
    pushad
    mov [gen_out], edi
    mov dword [gen_n], 0
    mov byte [gcap], 1
    mov esi, [bd]
    ; captures first: a jump search from every piece of the side
    xor ebx, ebx
.cs:test ebx, 0x88
    jnz .cn
    movzx eax, byte [esi+ebx]
    mov dl, [side_of+eax]
    cmp dl, [gside]
    jne .cn
    mov [jp_piece], al
    mov byte [esi+ebx], EMPTY   ; lift the piece while it jumps
    mov byte [w_mv], 1
    mov [w_mv+1], bl
    mov byte [w_mv+M_NCAP], 0
    mov ecx, ebx
    call jump
    mov al, [jp_piece]
    mov [esi+ebx], al
.cn:inc ebx
    cmp ebx, 0x78
    jb .cs
    cmp dword [gen_n], 0
    jne .done
    ; no capture: the plain moves
    mov byte [gcap], 0
    xor ebx, ebx
.ms:test ebx, 0x88
    jnz .mn
    movzx edx, byte [esi+ebx]
    mov al, [side_of+edx]
    cmp al, [gside]
    jne .mn
    movzx ecx, byte [dlo+edx]
.md:cmp cl, [dhi+edx]
    jae .mn
    mov eax, ebx
    add eax, [dirs+ecx*4]
    test eax, 0xFFFFFF88
    jnz .mdn
    cmp byte [esi+eax], EMPTY
    jne .mdn
    mov byte [w_mv], 2
    mov [w_mv+1], bl
    mov [w_mv+2], al
    mov byte [w_mv+M_NCAP], 0
    call record
.mdn:
    inc ecx
    jmp .md
.mn:inc ebx
    cmp ebx, 0x78
    jb .ms
.done:
    popad
    mov eax, [gen_n]
    ret

; ecx = the square the jumping piece ([jp_piece]) stands on, w_mv = the
; jump so far, esi = board: records every way the jump can end
jump:
    pushad
    xor ebp, ebp                ; 1 once a further jump is found
    movzx edx, byte [jp_piece]
    movzx ebx, byte [dlo+edx]   ; direction
.k: cmp bl, [dhi+edx]
    jae .end
    mov edi, ecx
    add edi, [dirs+ebx*4]       ; edi = the square jumped
    test edi, 0xFFFFFF88
    jnz .nk
    mov eax, edi
    add eax, [dirs+ebx*4]       ; eax = the landing square
    test eax, 0xFFFFFF88
    jnz .nk
    cmp byte [esi+eax], EMPTY
    jne .nk
    push eax
    movzx eax, byte [esi+edi]
    mov al, [side_of+eax]
    xor al, [gside]
    cmp al, 1                   ; an enemy piece not jumped yet
    pop eax
    jne .nk
    ; jump it
    mov ebp, 1
    push ebx
    movzx edx, byte [esi+edi]
    push edx
    mov byte [esi+edi], CAPT
    movzx edx, byte [w_mv]
    mov [w_mv+1+edx], al
    inc byte [w_mv]
    movzx edx, byte [w_mv+M_NCAP]
    push eax
    mov eax, edi
    mov [w_mv+M_CAPS+edx], al
    pop eax
    inc byte [w_mv+M_NCAP]
    call crowns
    jc .rec                     ; a man crowned here stops
    push ecx
    mov ecx, eax
    call jump
    pop ecx
    jmp .undo
.rec:
    call record
.undo:
    dec byte [w_mv]
    dec byte [w_mv+M_NCAP]
    pop edx
    mov [esi+edi], dl
    pop ebx
    movzx edx, byte [jp_piece]
.nk:inc ebx
    jmp .k
.end:
    test ebp, ebp
    jnz .r
    cmp byte [w_mv+M_NCAP], 0
    je .r
    call record                 ; no further jump: the move ends here
.r: popad
    ret

; eax = square -> CF set when [jp_piece] is a man that is crowned there
crowns:
    cmp byte [jp_piece], BMAN
    jne .w
    cmp eax, 0x70
    jae .yes
    clc
    ret
.w: cmp byte [jp_piece], WMAN
    jne .no
    cmp eax, 8
    jb .yes
.no:clc
    ret
.yes:
    stc
    ret

; copies w_mv to the next free move of the list
record:
    push ecx
    push esi
    push edi
    mov edi, [gen_n]
    cmp edi, MAXMV
    jae .r
    shl edi, 5
    add edi, [gen_out]
    mov esi, w_mv
    mov ecx, MOVESZ / 4
    rep movsd
    inc dword [gen_n]
.r: pop edi
    pop esi
    pop ecx
    ret

; esi = move: plays it on [bd] (captures removed, a man crowned)
make:
    pushad
    mov edi, [bd]
    movzx ebx, byte [esi+1]
    movzx eax, byte [edi+ebx]   ; the piece
    mov byte [edi+ebx], EMPTY
    movzx ecx, byte [esi+M_NCAP]
.c: jecxz .land
    movzx edx, byte [esi+M_CAPS+ecx-1]
    mov byte [edi+edx], EMPTY
    dec ecx
    jmp .c
.land:
    movzx ecx, byte [esi]
    movzx edx, byte [esi+ecx]   ; the last square
    cmp al, BMAN
    jne .w
    cmp edx, 0x70
    jb .put
    mov al, BKING
    jmp .put
.w: cmp al, WMAN
    jne .put
    cmp edx, 8
    jae .put
    mov al, WKING
.put:
    mov [edi+edx], al
    popad
    ret

; esi = a legal move of [side]: plays it on the game board, counts
; quiet moves and passes the turn
play_move:
    pushad
    mov dword [bd], board
    movzx ebx, byte [esi+1]
    mov al, [board+ebx]
    inc dword [quiet]
    cmp byte [esi+M_NCAP], 0
    jne .reset
    cmp al, BMAN
    je .reset
    cmp al, WMAN
    jne .mk
.reset:
    mov dword [quiet], 0
.mk:call make
    xor byte [side], 1
    popad
    ret

; -> eax = the state of the game: 0 on, 1 you win, 2 the computer wins,
; 3 a draw (and [winner] = eax); gamelist = the moves of the side to move
outcome:
    push edi
    mov dword [bd], board
    mov al, [side]
    mov [gside], al
    mov edi, gamelist
    call gen
    mov [game_n], eax
    test eax, eax
    jnz .on
    mov eax, 2                  ; you cannot move: the computer wins
    cmp byte [side], YOU
    je .r
    mov eax, 1
    jmp .r
.on:xor eax, eax
    cmp dword [quiet], DRAWN
    jb .r
    mov eax, 3
.r: mov [winner], al
    pop edi
    ret

; ---------- computer player ----------

; [bd] -> eax = the position's value for Black: men 100 (and 4 a rank
; forward), kings 160
evaluate:
    push ebx
    push ecx
    push esi
    mov esi, [bd]
    xor eax, eax
    xor ebx, ebx
.l: test ebx, 0x88
    jnz .n
    movzx ecx, byte [esi+ebx]
    cmp ecx, BMAN
    jne .bk
    mov ecx, ebx
    shr ecx, 4
    lea eax, [eax+ecx*4+100]
    jmp .n
.bk:cmp ecx, BKING
    jne .wm
    add eax, 160
    jmp .n
.wm:cmp ecx, WMAN
    jne .wk
    mov ecx, ebx
    shr ecx, 4
    neg ecx
    add ecx, 7
    lea ecx, [ecx*4+100]
    sub eax, ecx
    jmp .n
.wk:cmp ecx, WKING
    jne .n
    sub eax, 160
.n: inc ebx
    cmp ebx, 0x78
    jb .l
    pop esi
    pop ecx
    pop ebx
    ret

; ecx = depth, ebx = alpha, edx = beta; [bd] = boards + [ply] * 128,
; [sside] = side to move -> eax = the value for the side to move
; (fail-hard). At depth 0 it goes on while captures are pending.
search:
    push ebp
    mov ebp, esp
    sub esp, 16                 ; -4 alpha, -8 beta, -12 depth, -16 moves
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [ebp-4], ebx
    mov [ebp-8], edx
    mov [ebp-12], ecx
    mov eax, [ply]
    imul edi, eax, MAXMV * MOVESZ
    add edi, movebuf
    mov al, [sside]
    mov [gside], al
    call gen
    mov [ebp-16], eax
    test eax, eax
    jnz .some
    mov eax, [ply]              ; no move: lost (later is better)
    sub eax, WIN
    jmp .ret
.some:
    cmp dword [ebp-12], 0
    jg .go
    cmp byte [gcap], 0
    je .leaf
    cmp dword [ply], MAXPLY - 1
    jb .go
.leaf:
    call evaluate
    cmp byte [sside], 0
    je .ret
    neg eax
    jmp .ret
.go:xor esi, esi
.l: cmp esi, [ebp-16]
    jae .done
    ; the next ply's board: a copy with the move made
    push esi
    push edi
    mov eax, [ply]
    inc eax
    shl eax, 7
    add eax, boards
    mov esi, [bd]
    mov edi, eax
    mov ecx, 32
    rep movsd
    mov [bd], eax
    pop edi
    pop esi
    push esi
    shl esi, 5
    add esi, edi
    call make
    pop esi
    inc dword [ply]
    xor byte [sside], 1
    mov ecx, [ebp-12]
    dec ecx
    mov ebx, [ebp-8]
    neg ebx
    mov edx, [ebp-4]
    neg edx
    call search
    neg eax
    xor byte [sside], 1
    dec dword [ply]
    mov edx, [ply]
    shl edx, 7
    add edx, boards
    mov [bd], edx
    cmp eax, [ebp-4]
    jle .n
    mov [ebp-4], eax
    cmp eax, [ebp-8]
    jge .done
.n: inc esi
    jmp .l
.done:
    mov eax, [ebp-4]
.ret:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    mov esp, ebp
    pop ebp
    ret

; The computer's move for [side] on the game board, searched [depth]
; plies -> esi = the move (in rootlist), or 0 when there is none
think:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov esi, board
    mov edi, boards
    mov ecx, 32
    rep movsd
    mov dword [bd], boards
    mov dword [ply], 0
    mov al, [side]
    mov [sside], al
    mov [gside], al
    mov edi, movebuf
    call gen
    mov [th_n], eax
    xor esi, esi
    test eax, eax
    jz .r
    mov esi, movebuf
    cmp eax, 1
    je .r                       ; a forced move needs no thought
    mov dword [th_best], 0
    mov dword [th_score], -INF
    xor ecx, ecx
.l: cmp ecx, [th_n]
    jae .d
    push ecx
    mov esi, boards
    mov edi, boards + 128
    mov ecx, 32
    rep movsd
    pop ecx
    mov dword [bd], boards + 128
    mov esi, ecx
    shl esi, 5
    add esi, movebuf
    call make
    mov dword [ply], 1
    xor byte [sside], 1
    push ecx
    mov ecx, [depth]
    dec ecx
    mov ebx, -INF
    mov edx, [th_score]
    neg edx
    inc edx                     ; (-INF, -best + 1): ties stay visible
    call search
    neg eax
    pop ecx
    xor byte [sside], 1
    mov dword [ply], 0
    mov dword [bd], boards
    cmp eax, [th_score]
    jg .take
    jl .n
    push eax
    call g_rand
    test eax, 0x100
    pop eax
    jz .n
    jmp .pick
.take:
    mov [th_score], eax
.pick:
    mov eax, ecx
    shl eax, 5
    add eax, movebuf
    mov [th_best], eax
.n: inc ecx
    jmp .l
.d: mov esi, [th_best]
.r: pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------- notation and screen ----------

; esi = text -> esi = the legal move in gamelist it names, or 0
parse_move:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    xor ecx, ecx                ; squares read
.sq:call g_skipsp
    mov al, [esi]
    cmp al, '-'
    je .sep
    cmp al, 'x'
    je .sep
    test al, al
    jz .end
    movzx ebx, al
    sub ebx, 'a'
    cmp ebx, 8
    jae .no
    movzx eax, byte [esi+1]
    sub eax, '1'
    cmp eax, 8
    jae .no
    cmp ecx, 13
    jae .no
    shl eax, 4
    add eax, ebx
    mov [psq+ecx], al
    inc ecx
    add esi, 2
    jmp .sq
.sep:
    inc esi
    jmp .sq
.end:
    cmp ecx, 2
    jb .no
    ; the move with exactly these squares
    mov edi, gamelist
    mov edx, [game_n]
.ex:test edx, edx
    jz .ends
    cmp [edi], cl
    jne .exn
    push ecx
    push esi
    push edi
    lea esi, [psq]
    inc edi
    repe cmpsb
    pop edi
    pop esi
    pop ecx
    je .found
.exn:
    add edi, MOVESZ
    dec edx
    jmp .ex
.ends:
    ; or, for two squares, the only move from the first to the last
    cmp ecx, 2
    jne .no
    xor ebx, ebx                ; matches
    mov edi, gamelist
    mov edx, [game_n]
.e2:test edx, edx
    jz .e2d
    mov al, [edi+1]
    cmp al, [psq]
    jne .e2n
    movzx eax, byte [edi]
    mov al, [edi+eax]
    cmp al, [psq+1]
    jne .e2n
    inc ebx
    mov [pm_hit], edi
.e2n:
    add edi, MOVESZ
    dec edx
    jmp .e2
.e2d:
    cmp ebx, 1
    jne .no
    mov edi, [pm_hit]
.found:
    mov esi, edi
    jmp .r
.no:xor esi, esi
.r: pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ebx = square: prints it like "c3"
put_sq:
    push eax
    mov eax, ebx
    and al, 7
    add al, 'a'
    call g_putc
    mov eax, ebx
    shr al, 4
    add al, '1'
    call g_putc
    pop eax
    ret

; esi = move: prints it like "c3-d4" or "c3xe5xg3"
put_move:
    push eax
    push ebx
    push ecx
    movzx ebx, byte [esi+1]
    call put_sq
    mov ecx, 2
.l: movzx eax, byte [esi]
    cmp ecx, eax
    ja .r
    mov al, '-'
    cmp byte [esi+M_NCAP], 0
    je .s
    mov al, 'x'
.s: call g_putc
    movzx ebx, byte [esi+ecx]
    call put_sq
    inc ecx
    jmp .l
.r: pop ecx
    pop ebx
    pop eax
    ret

draw:
    pushad
    call g_nl
    mov esi, m_cols
    call g_puts
    mov edx, 7                  ; rank
.r: lea eax, [edx+1]
    mov ecx, 3
    call g_putdec_w
    mov al, ' '
    call g_putc
    xor ecx, ecx
.f: mov ebx, edx
    shl ebx, 4
    add ebx, ecx
    movzx eax, byte [board+ebx]
    mov al, [glyph+eax]
    call dark
    jz .p
    mov al, ' '
.p: call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, 8
    jb .f
    lea eax, [edx+1]
    call g_putdec
    call g_nl
    dec edx
    jns .r
    mov esi, m_cols
    call g_puts
    mov esi, m_you
    call g_puts
    mov ecx, BMAN
    call count
    call g_putdec
    mov esi, m_me
    call g_puts
    mov ecx, WMAN
    call count
    call g_putdec
    call g_nl
    popad
    ret

; ecx = BMAN or WMAN -> eax = that side's pieces (men and kings) on board
count:
    push ebx
    push edx
    xor eax, eax
    xor ebx, ebx
.l: movzx edx, byte [board+ebx]
    cmp edx, ecx
    je .y
    dec edx
    cmp edx, ecx
    jne .n
.y: inc eax
.n: inc ebx
    cmp ebx, 128
    jb .l
    pop edx
    pop ebx
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%macro PUT 2                    ; square, piece
    mov byte [board + %1], %2
%endmacro
; Generates the moves of side %1 on board -> eax = how many, edi = list
%macro GEN 1
    mov dword [bd], board
    mov byte [gside], %1
    mov edi, gamelist
    call gen
    mov [game_n], eax
%endmacro

selftest:
    mov eax, 7
    call g_srand
    ; 1-5. perft from the start: 7, 49, 302, 1469, 7361
    mov ecx, 1
.pf:call setup
    call perft_root
    mov ebx, [perft_want+ecx*4-4]
    call g_expect
    inc ecx
    cmp ecx, 5
    jbe .pf
    ; 6-8. a capture is compulsory: c3 must take d4 (landing on e5)
    call clear
    PUT 0x22, BMAN              ; c3
    PUT 0x33, WMAN              ; d4
    PUT 0x26, BMAN              ; g3, which could only make a plain move
    GEN 0
    EXPECT 1
    movzx eax, byte [gcap]
    EXPECT 1
    movzx eax, byte [gamelist+2]
    EXPECT 0x44
    ; 9-11. a double jump: a1 over b2 and d4 to e5
    call clear
    PUT 0x00, BMAN
    PUT 0x11, WMAN
    PUT 0x33, WMAN
    GEN 0
    EXPECT 1
    movzx eax, byte [gamelist]
    EXPECT 3
    movzx eax, byte [gamelist+M_NCAP]
    EXPECT 2
    ; 12-13. crowning ends a jump: b6 x d8 is crowned and stops, though a
    ; king on d8 could go on over e7
    call clear
    PUT 0x51, BMAN              ; b6
    PUT 0x62, WMAN              ; c7
    PUT 0x64, WMAN              ; e7
    GEN 0
    movzx eax, byte [gamelist]
    EXPECT 2
    mov esi, gamelist
    call make
    movzx eax, byte [board+0x73]
    EXPECT BKING
    ; 14-15. a king moves both ways; a white man moves down
    call clear
    PUT 0x33, BKING
    GEN 0
    EXPECT 4
    call clear
    PUT 0x33, WMAN
    GEN 1
    EXPECT 2
    movzx eax, byte [gamelist+2]
    shr eax, 4
    EXPECT 2                    ; to rank 3
    ; 17. a side without pieces has no move
    call clear
    PUT 0x33, BMAN
    GEN 1
    EXPECT 0
    ; 18-20. the parser
    call setup
    GEN 0
    mov esi, t_c3d4
    call parse_move
    test esi, esi
    setnz al
    movzx eax, al
    EXPECT 1
    mov esi, t_c3d5
    call parse_move
    mov eax, esi
    EXPECT 0
    mov esi, t_bad
    call parse_move
    mov eax, esi
    EXPECT 0
    ; 21-22. the double capture e5xc3xe1 beats the single e5xg3
    call clear
    PUT 0x44, WMAN              ; e5
    PUT 0x33, BMAN              ; d4
    PUT 0x35, BMAN              ; f4
    PUT 0x13, BMAN              ; d2
    mov byte [side], ME
    mov dword [depth], 4
    call think
    movzx eax, byte [esi+M_NCAP]
    EXPECT 2
    movzx eax, byte [esi+2+1]
    EXPECT 0x04                 ; e1, crowned there
    ; 23-24. the computer plays itself: the game ends, and the same seed
    ; plays the same game
    mov eax, 99
    call selfplay
    mov [t_hash], eax
    mov eax, edx
    EXPECT 1
    mov eax, 99
    call selfplay
    mov ebx, [t_hash]
    call g_expect
    call g_report
    ret

; eax = seed: the computer plays both sides at depth 3 from the start,
; for at most 300 moves -> eax = a hash of the end position, edx = 1 when
; the game ended (a side could not move, or the draw rule)
selfplay:
    call g_srand
    call setup
    mov dword [depth], 3
    xor ecx, ecx
.l: call outcome
    test eax, eax
    jnz .end
    cmp ecx, 300
    jae .stop
    call think
    call play_move
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
    cmp ebx, 128
    jb .hl
    ret

clear:
    push eax
    push ecx
    push edi
    mov edi, board
    mov ecx, 32
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret

; ecx = depth: perft of the game board, Black to move -> eax = leaves
perft_root:
    push esi
    push edi
    push ecx
    mov esi, board
    mov edi, boards
    mov ecx, 32
    rep movsd
    pop ecx
    mov dword [bd], boards
    mov dword [ply], 0
    mov byte [sside], 0
    call perft
    pop edi
    pop esi
    ret

; ecx = depth, [bd], [ply], [sside] -> eax = leaf positions
perft:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov eax, 1
    test ecx, ecx
    jz .r
    mov eax, [ply]
    imul edi, eax, MAXMV * MOVESZ
    add edi, movebuf
    mov al, [sside]
    mov [gside], al
    call gen
    cmp ecx, 1
    je .r
    mov edx, eax                ; moves
    xor ebx, ebx                ; leaves
    xor esi, esi
.l: cmp esi, edx
    jae .d
    push ecx
    push esi
    push edi
    mov eax, [ply]
    inc eax
    shl eax, 7
    add eax, boards
    mov esi, [bd]
    mov edi, eax
    mov ecx, 32
    rep movsd
    mov [bd], eax
    pop edi
    pop esi
    pop ecx
    push esi
    shl esi, 5
    add esi, edi
    call make
    pop esi
    inc dword [ply]
    xor byte [sside], 1
    push ecx
    dec ecx
    call perft
    pop ecx
    add ebx, eax
    xor byte [sside], 1
    dec dword [ply]
    mov eax, [ply]
    shl eax, 7
    add eax, boards
    mov [bd], eax
    inc esi
    jmp .l
.d: mov eax, ebx
.r: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- data ----------

; up-left, up-right, down-left, down-right; men use the first two
; (Black) or the last two (White), kings all four
dirs dd 15, 17, -17, -15
;              -  bm bk wm wk capt
dlo  db        0, 0, 0, 2, 0, 0
dhi  db        0, 2, 4, 4, 4, 0
side_of db 0xFF, 0, 0, 1, 1, 0xFF
glyph db '.bBwW?'
perft_want dd 7, 49, 302, 1469, 7361
res_msg dd 0, m_youwin, m_iwin, m_drawn
t_c3d4 db 'c3-d4', 0
t_c3d5 db 'c3d5', 0
t_bad db 'z9', 0

m_name db 'checkers', 0
m_title db 'Squirrel Checkers - you are Black (b, B) and move first.', 10
        db 'Moves like c3d4 or c3-d4, jumps like c3e5g3; level N, n, q', 10, 0
m_cols db '    a b c d e f g h', 10, 0
m_you db 'You (b): ', 0
m_me db '   Computer (w): ', 0
m_prompt db 'checkers> ', 0
m_help db 'Type a move like c3d4 (or level N, n, q)', 10, 0
m_illegal db 'That move is not legal here (a capture must be taken)', 10, 0
m_think db 'Thinking...', 10, 0
m_iplay db 'Computer plays ', 0
m_youwin db 'The computer cannot move: you win! n for a new game, q to quit', 10, 0
m_iwin db 'You cannot move: the computer wins. n for a new game, q to quit', 10, 0
m_drawn db 'Forty moves each without a capture: a draw. n or q', 10, 0
w_level db 'level', 0

SQX_BSS
G_BSS
depth resd 1
quiet resd 1
bd resd 1
ply resd 1
gen_out resd 1
gen_n resd 1
game_n resd 1
th_n resd 1
th_best resd 1
th_score resd 1
pm_hit resd 1
t_hash resd 1
side resb 1
sside resb 1
gside resb 1
gcap resb 1
jp_piece resb 1
winner resb 1
psq resb 16
alignb 4
w_mv resb MOVESZ
board resb 128
boards resb 128 * (MAXPLY + 1)
gamelist resb MAXMV * MOVESZ
movebuf resb MAXMV * MOVESZ * MAXPLY
SQX_END
