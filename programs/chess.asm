; chess — chess against the computer (G.5). Original code.
;
;   run chess [seed]       you play White against an alpha-beta engine
;   run chess gui [seed]   the same on the graphics screen: click a piece,
;                          then where it goes; 1-4 set the level, n, q
;   run chess test         move generator perft, search, SAN and PGN self-check,
;                          prints "chess: PASS"
;
; Commands:
;   e2e4      a move in coordinate notation (e7e8n under-promotes;
;             a promotion without a letter makes a queen; o-o and o-o-o castle)
;   moves     print the game so far as PGN move text
;   save F    save the game as a PGN file F on the data disk
;   level N   search depth 1-4 (default 3)
;   n         new game            q   quit
;
; The board is 0x88: square = rank * 16 + file (a1 = 0x00, h8 = 0x77);
; any square with bit 0x88 set is off the board. A piece is its type
; (1 pawn .. 6 king) plus 8 for Black. The engine is a negamax
; alpha-beta search over legal moves (captures first) with material and
; small piece-square bonuses; equal root scores are broken with the seeded
; random numbers. No code from any other chess program is used.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"
%include "gui.inc"
%include "gamegui.inc"

PAWN   equ 1
KNIGHT equ 2
BISHOP equ 3
ROOK   equ 4
QUEEN  equ 5
KING   equ 6
BLACKP equ 8                    ; colour bit of a piece; also "side = Black"
NOSQ   equ 0x80                 ; no en-passant square

; a move is a dword: from | to << 8 | promotion type << 16 | flags
MF_CAP    equ 1 << 20
MF_EP     equ 1 << 21
MF_CASTLE equ 1 << 22
MF_DOUBLE equ 1 << 23

CR_WK equ 1                     ; castling rights
CR_WQ equ 2
CR_BK equ 4
CR_BQ equ 8

MATE    equ 30000
INF     equ 32000
MOVEBUF equ 3072                ; dwords for move lists of every ply
UNDOMAX equ 400                 ; plies of game + search history
UNDOSZ  equ 16

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov dword [depth], 3
    cmp byte [g_gui], 0
    jne gui_play
    mov esi, m_title
    call g_puts
.new:
    mov esi, fen_start
    call fen_load
    call pgn_reset
.loop:
    call draw
    call status                 ; eax = 0 playing, 1 mate, 2 stalemate
    test eax, eax
    jz .ask
    call pgn_result
    mov esi, m_over
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
    mov edi, w_moves
    call g_word
    jnc .moves
    mov edi, w_save
    call g_word
    jnc .save
    mov edi, w_level
    call g_word
    jnc .level
    call status
    test eax, eax
    jnz .bad
    cmp dword [side], 0
    jne .bad
    call parse_move             ; eax = legal move, or 0
    test eax, eax
    jz .illegal
    call play_san
    call status
    test eax, eax
    jnz .loop
    call draw
    mov esi, m_think
    call g_puts
    call think                  ; eax = move
    test eax, eax
    jz .loop
    mov esi, m_iplay
    call g_puts
    call play_san
    mov esi, san_buf
    call g_puts
    call g_nl
    jmp .loop
.moves:
    mov esi, pgn_text
    call g_puts
    call g_nl
    jmp .ask
.save:
    call save_pgn
    jmp .ask
.level:
    call g_parsenum
    jc .bad
    cmp eax, 1
    jb .bad
    cmp eax, 4
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

; ---------- position ----------

; esi = FEN text: sets up the position (pieces, side, castling, en passant)
fen_load:
    pushad
    mov edi, board
    mov ecx, 128
    xor eax, eax
    rep stosb
    mov dword [hply], 0
    mov dword [ply], 0
    mov dword [msp], movebuf
    mov edx, 0x70               ; a8
.p: lodsb
    cmp al, ' '
    je .side
    test al, al
    jz .done
    cmp al, '/'
    jne .np
    and edx, 0x70
    sub edx, 16
    jmp .p
.np:
    cmp al, '1'
    jb .pc
    cmp al, '8'
    ja .pc
    sub al, '0'
    movzx eax, al
    add edx, eax
    jmp .p
.pc:
    xor ebx, ebx
.f: cmp al, [fen_pieces+ebx]
    je .found
    inc ebx
    cmp ebx, 16
    jb .f
    jmp .p
.found:
    mov [board+edx], bl
    mov eax, ebx
    and eax, 7
    cmp eax, KING
    jne .nk
    mov eax, ebx
    shr eax, 3
    mov [ksq+eax], dl
.nk:
    inc edx
    jmp .p
.side:
    mov dword [side], 0
    lodsb
    cmp al, 'b'
    jne .cr
    mov dword [side], BLACKP
.cr:
    inc esi                     ; the blank
    mov dword [castle], 0
.c: lodsb
    cmp al, 'K'
    jne .c1
    or dword [castle], CR_WK
.c1:
    cmp al, 'Q'
    jne .c2
    or dword [castle], CR_WQ
.c2:
    cmp al, 'k'
    jne .c3
    or dword [castle], CR_BK
.c3:
    cmp al, 'q'
    jne .c4
    or dword [castle], CR_BQ
.c4:
    cmp al, ' '
    je .ep
    test al, al
    jz .done
    jmp .c
.ep:
    mov dword [ep], NOSQ
    lodsb
    cmp al, '-'
    je .done
    sub al, 'a'
    movzx ebx, al
    lodsb
    sub al, '1'
    movzx eax, al
    shl eax, 4
    or eax, ebx
    mov [ep], eax
.done:
    popad
    ret

; ---------- attacks ----------

; ecx = square, edx = attacking side (0 or BLACKP) -> eax = 1 if attacked
attacked:
    push ebx
    push esi
    push edi
    ; pawns
    mov ebx, ecx
    sub ebx, 15
    test edx, edx
    jz .wp
    add ebx, 32                 ; Black pawns attack from above
.wp:
    mov al, PAWN
    or al, dl
    test ebx, 0x88
    jnz .wp2
    cmp [board+ebx], al
    je .yes
.wp2:
    sub ebx, 2
    test ebx, 0x88
    jnz .kn
    cmp [board+ebx], al
    je .yes
.kn:
    ; knights and king
    mov esi, knight_off
    mov al, KNIGHT
    call .leaper
    jc .yes
    mov esi, king_off
    mov al, KING
    call .leaper
    jc .yes
    ; sliders
    mov esi, bishop_dir
    mov al, BISHOP
    call .slider
    jc .yes
    mov esi, rook_dir
    mov al, ROOK
    call .slider
    jc .yes
    xor eax, eax
    jmp .r
.yes:
    mov eax, 1
.r: pop edi
    pop esi
    pop ebx
    ret
.leaper:                        ; al = piece type, esi = offsets (0-ended)
    or al, dl
.l: movsx ebx, byte [esi]
    test ebx, ebx
    jz .ln
    inc esi
    add ebx, ecx
    test ebx, 0x88
    jnz .l
    cmp [board+ebx], al
    jne .l
    stc
    ret
.ln:
    clc
    ret
.slider:                        ; al = BISHOP or ROOK (queens too)
    mov ah, QUEEN
    or ah, dl
    or al, dl
.d: movsx edi, byte [esi]
    test edi, edi
    jz .ln
    inc esi
    mov ebx, ecx
.s: add ebx, edi
    test ebx, 0x88
    jnz .d
    cmp byte [board+ebx], 0
    je .s
    cmp [board+ebx], al
    je .hit
    cmp [board+ebx], ah
    je .hit
    jmp .d
.hit:
    stc
    ret

; -> eax = 1 if the side to move is in check
in_check:
    push ecx
    push edx
    mov eax, [side]
    shr eax, 3
    movzx ecx, byte [ksq+eax]
    mov edx, [side]
    xor edx, BLACKP
    call attacked
    pop edx
    pop ecx
    ret

; ---------- move generation ----------

; edi = where to write: generates the pseudo-legal moves of the side to
; move -> eax = how many (edi is kept)
gen:
    pushad
    mov [gen_out], edi
    mov dword [gen_n], 0
    xor ecx, ecx                ; square
.sq:
    test ecx, 0x88
    jnz .next
    movzx eax, byte [board+ecx]
    test eax, eax
    jz .next
    mov edx, eax
    and edx, BLACKP
    cmp edx, [side]
    jne .next
    and eax, 7
    cmp eax, PAWN
    je .pawn
    cmp eax, KNIGHT
    je .knight
    cmp eax, KING
    je .king
    cmp eax, BISHOP
    je .bishop
    cmp eax, ROOK
    je .rook
    mov esi, bishop_dir         ; queen: both
    call gen_slide
    mov esi, rook_dir
    call gen_slide
    jmp .next
.bishop:
    mov esi, bishop_dir
    call gen_slide
    jmp .next
.rook:
    mov esi, rook_dir
    call gen_slide
    jmp .next
.knight:
    mov esi, knight_off
    call gen_leap
    jmp .next
.king:
    mov esi, king_off
    call gen_leap
    call gen_castle
    jmp .next
.pawn:
    call gen_pawn
.next:
    inc ecx
    cmp ecx, 128
    jb .sq
    mov eax, [gen_n]
    mov [esp+28], eax
    popad
    ret

; eax = move: appends it
addmove:
    push edi
    mov edi, [gen_out]
    mov [edi], eax
    add dword [gen_out], 4
    inc dword [gen_n]
    pop edi
    ret

; ecx = from, ebx = to: adds a move, marking captures
add_ft:
    push eax
    mov eax, ebx
    shl eax, 8
    or eax, ecx
    cmp byte [board+ebx], 0
    je .q
    or eax, MF_CAP
.q: call addmove
    pop eax
    ret

; ebx = target square -> CF set when it is off the board or holds a
; piece of the side to move; ZF... (al = the piece there)
own_or_off:
    test ebx, 0x88
    jnz .no
    mov al, [board+ebx]
    test al, al
    jz .ok
    and al, BLACKP
    cmp al, [side]
    je .no
.ok:
    clc
    ret
.no:
    stc
    ret

gen_leap:                       ; ecx = from, esi = offsets
    push eax
    push ebx
    push esi
.l: movsx ebx, byte [esi]
    test ebx, ebx
    jz .d
    inc esi
    add ebx, ecx
    call own_or_off
    jc .l
    call add_ft
    jmp .l
.d: pop esi
    pop ebx
    pop eax
    ret

gen_slide:                      ; ecx = from, esi = directions
    push eax
    push ebx
    push edx
    push esi
.d: movsx edx, byte [esi]
    test edx, edx
    jz .r
    inc esi
    mov ebx, ecx
.s: add ebx, edx
    call own_or_off
    jc .d
    call add_ft
    cmp byte [board+ebx], 0
    je .s
    jmp .d
.r: pop esi
    pop edx
    pop ebx
    pop eax
    ret

gen_pawn:                       ; ecx = from
    pushad
    mov edx, 16                 ; direction
    mov esi, 1                  ; start rank
    mov edi, 7                  ; promotion rank
    cmp dword [side], 0
    je .w
    mov edx, -16
    mov esi, 6
    xor edi, edi
.w: mov [pw_last], edi
    ; one step, two steps
    lea ebx, [ecx+edx]
    test ebx, 0x88
    jnz .caps
    cmp byte [board+ebx], 0
    jne .caps
    mov eax, ebx
    shl eax, 8
    or eax, ecx
    call add_pawn
    mov eax, ecx
    shr eax, 4
    cmp eax, esi
    jne .caps
    add ebx, edx
    cmp byte [board+ebx], 0
    jne .caps
    mov eax, ebx
    shl eax, 8
    or eax, ecx
    or eax, MF_DOUBLE
    call addmove
.caps:
    lea ebx, [ecx+edx-1]
    call .cap
    lea ebx, [ecx+edx+1]
    call .cap
    popad
    ret
.cap:
    test ebx, 0x88
    jnz .cr
    cmp ebx, [ep]
    je .ep
    mov al, [board+ebx]
    test al, al
    jz .cr
    and al, BLACKP
    cmp al, [side]
    je .cr
    mov eax, ebx
    shl eax, 8
    or eax, ecx
    or eax, MF_CAP
    call add_pawn
.cr:
    ret
.ep:
    mov eax, ebx
    shl eax, 8
    or eax, ecx
    or eax, MF_CAP | MF_EP
    call addmove
    ret

; eax = pawn move: adds it, or its four promotions on the last rank
add_pawn:
    push ebx
    mov ebx, eax
    shr ebx, 12
    and ebx, 7                  ; rank of the target (bits 12-14)
    cmp ebx, [pw_last]
    jne .one
    or eax, QUEEN << 16
    call addmove
    xor eax, (QUEEN ^ ROOK) << 16
    call addmove
    xor eax, (ROOK ^ BISHOP) << 16
    call addmove
    xor eax, (BISHOP ^ KNIGHT) << 16
.one:
    call addmove
    pop ebx
    ret

gen_castle:                     ; ecx = king square
    pushad
    mov edx, [side]
    xor edx, BLACKP             ; the attacker
    cmp dword [side], 0
    jne .black
    cmp ecx, 0x04
    jne .r
    mov eax, CR_WK
    mov ebx, CR_WQ
    jmp .go
.black:
    cmp ecx, 0x74
    jne .r
    mov eax, CR_BK
    mov ebx, CR_BQ
.go:
    mov [cs_k], eax
    mov [cs_q], ebx
    push ecx
    call attacked               ; no castling out of check
    pop ecx
    test eax, eax
    jnz .r
    ; king side: f, g empty and not attacked
    mov eax, [cs_k]
    test [castle], eax
    jz .qs
    cmp byte [board+ecx+1], 0
    jne .qs
    cmp byte [board+ecx+2], 0
    jne .qs
    push ecx
    inc ecx
    call attacked
    pop ecx
    test eax, eax
    jnz .qs
    push ecx
    add ecx, 2
    call attacked
    pop ecx
    test eax, eax
    jnz .qs
    lea eax, [ecx+2]
    shl eax, 8
    or eax, ecx
    or eax, MF_CASTLE
    call addmove
.qs:
    mov eax, [cs_q]
    test [castle], eax
    jz .r
    cmp byte [board+ecx-1], 0
    jne .r
    cmp byte [board+ecx-2], 0
    jne .r
    cmp byte [board+ecx-3], 0
    jne .r
    push ecx
    dec ecx
    call attacked
    pop ecx
    test eax, eax
    jnz .r
    push ecx
    sub ecx, 2
    call attacked
    pop ecx
    test eax, eax
    jnz .r
    lea eax, [ecx-2]
    shl eax, 8
    or eax, ecx
    or eax, MF_CASTLE
    call addmove
.r: popad
    ret

; ---------- make and unmake ----------

; eax = move: plays it (keeps registers); history in undo[hply]
make:
    pushad
    mov ebp, [hply]
    shl ebp, 4
    add ebp, undo
    mov [ebp], eax              ; move
    mov ecx, eax
    and ecx, 0xFF               ; from
    mov ebx, eax
    shr ebx, 8
    and ebx, 0xFF               ; to
    movzx edx, byte [board+ebx]
    mov [ebp+4], dl             ; captured piece
    mov dl, [castle]
    mov [ebp+5], dl
    mov dl, [ep]
    mov [ebp+6], dl
    inc dword [hply]
    inc dword [ply]
    movzx edx, byte [board+ecx] ; the moving piece
    mov byte [board+ecx], 0
    test eax, MF_EP
    jz .noep
    lea esi, [ebx-16]           ; the pawn taken en passant
    cmp dword [side], 0
    je .epw
    add esi, 32
.epw:
    mov byte [board+esi], 0
.noep:
    mov esi, eax
    shr esi, 16
    and esi, 7
    jz .put
    mov edx, esi                ; promotion
    or edx, [side]
.put:
    mov [board+ebx], dl
    and edx, 7
    cmp edx, KING
    jne .nk
    mov edx, [side]
    shr edx, 3
    mov [ksq+edx], bl
.nk:
    test eax, MF_CASTLE
    jz .nc
    ; the rook: h-file to f-file, or a-file to d-file
    lea esi, [ecx+3]
    lea edi, [ecx+1]
    cmp ebx, ecx
    ja .ks
    lea esi, [ecx-4]
    lea edi, [ecx-1]
.ks:
    mov dl, [board+esi]
    mov [board+edi], dl
    mov byte [board+esi], 0
.nc:
    mov dl, [castle_mask+ecx]
    and dl, [castle_mask+ebx]
    and [castle], dl
    mov dword [ep], NOSQ
    test eax, MF_DOUBLE
    jz .side
    lea edx, [ecx+ebx]
    shr edx, 1
    mov [ep], edx
.side:
    xor dword [side], BLACKP
    popad
    ret

; takes back the last move made
unmake:
    pushad
    dec dword [hply]
    dec dword [ply]
    xor dword [side], BLACKP
    mov ebp, [hply]
    shl ebp, 4
    add ebp, undo
    mov eax, [ebp]
    mov ecx, eax
    and ecx, 0xFF
    mov ebx, eax
    shr ebx, 8
    and ebx, 0xFF
    movzx edx, byte [board+ebx]
    test eax, 7 << 16
    jz .np
    mov edx, PAWN
    or edx, [side]
.np:
    mov [board+ecx], dl
    and edx, 7
    cmp edx, KING
    jne .nk
    mov edx, [side]
    shr edx, 3
    mov [ksq+edx], cl
.nk:
    mov dl, [ebp+4]
    mov [board+ebx], dl
    test eax, MF_EP
    jz .noep
    lea esi, [ebx-16]
    mov dl, PAWN | BLACKP
    cmp dword [side], 0
    je .epw
    add esi, 32
    mov dl, PAWN
.epw:
    mov [board+esi], dl
.noep:
    test eax, MF_CASTLE
    jz .nc
    lea esi, [ecx+3]
    lea edi, [ecx+1]
    cmp ebx, ecx
    ja .ks
    lea esi, [ecx-4]
    lea edi, [ecx-1]
.ks:
    mov dl, [board+edi]
    mov [board+esi], dl
    mov byte [board+edi], 0
.nc:
    movzx edx, byte [ebp+5]
    mov [castle], edx
    movzx edx, byte [ebp+6]
    mov [ep], edx
    popad
    ret

; eax = move -> eax = 1 if it is legal (it does not leave the king in
; check); the position is unchanged
is_legal:
    call make
    push ecx
    push edx
    mov edx, [side]             ; the side now to move attacks...
    mov ecx, edx
    xor ecx, BLACKP
    shr ecx, 3
    movzx ecx, byte [ksq+ecx]   ; ...the king of the side that moved
    call attacked
    pop edx
    pop ecx
    call unmake
    xor eax, 1
    ret

; edi = buffer -> eax = number of legal moves written there
gen_legal:
    push ebx
    push ecx
    push esi
    push edi
    call gen
    mov ecx, eax
    mov esi, edi
    xor ebx, ebx
.l: jecxz .d
    mov eax, [esi]
    push eax
    call is_legal
    test eax, eax
    pop eax
    jz .n
    mov [edi+ebx*4], eax
    inc ebx
.n: add esi, 4
    dec ecx
    jmp .l
.d: mov eax, ebx
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; -> eax = 0 game on, 1 checkmate, 2 stalemate (for the side to move)
status:
    push edi
    mov edi, [msp]
    call gen_legal
    test eax, eax
    jnz .on
    call in_check
    test eax, eax
    jz .stale
    mov eax, 1
    pop edi
    ret
.stale:
    mov eax, 2
    pop edi
    ret
.on:
    xor eax, eax
    pop edi
    ret

; ---------- perft ----------

; ecx = depth -> eax = leaf nodes
perft:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    test ecx, ecx
    jnz .go
    mov eax, 1
    jmp .r
.go:
    mov edi, [msp]
    call gen
    mov ebx, eax                ; moves
    lea eax, [edi+ebx*4]
    mov [msp], eax
    xor edx, edx                ; leaves
    mov esi, edi
.l: test ebx, ebx
    jz .d
    mov eax, [esi]
    call make
    push ecx
    push edx
    mov edx, [side]
    mov ecx, edx
    xor ecx, BLACKP
    shr ecx, 3
    movzx ecx, byte [ksq+ecx]
    call attacked
    pop edx
    pop ecx
    test eax, eax
    jnz .skip
    push ecx
    dec ecx
    call perft
    pop ecx
    add edx, eax
.skip:
    call unmake
    add esi, 4
    dec ebx
    jmp .l
.d: mov [msp], edi
    mov eax, edx
.r: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- evaluation and search ----------

; -> eax = score for the side to move (material + placement)
evaluate:
    push ebx
    push ecx
    push edx
    push esi
    xor esi, esi                ; White minus Black
    xor ecx, ecx
.sq:
    test ecx, 0x88
    jnz .n
    movzx eax, byte [board+ecx]
    test eax, eax
    jz .n
    mov ebx, eax
    and ebx, 7
    mov edx, [piece_value+ebx*4]
    ; placement: centre table for knights, bishops and pawns, pawns gain
    ; as they advance
    push eax
    mov eax, ecx
    shr eax, 4                  ; rank
    mov ebx, ecx
    and ebx, 7
    lea ebx, [ebx+eax*8]
    movzx ebx, byte [centre+ebx]
    pop eax
    push eax
    and eax, 7
    cmp eax, KNIGHT
    je .c
    cmp eax, BISHOP
    je .c
    cmp eax, PAWN
    jne .nc
    shr ebx, 1
.c: add edx, ebx
.nc:
    pop eax
    cmp eax, PAWN
    jne .nwp
    mov ebx, ecx
    shr ebx, 4
    imul ebx, 6
    add edx, ebx
.nwp:
    cmp eax, PAWN | BLACKP
    jne .nbp
    mov ebx, ecx
    shr ebx, 4
    neg ebx
    add ebx, 7
    imul ebx, 6
    add edx, ebx
.nbp:
    test eax, BLACKP
    jz .w
    sub esi, edx
    jmp .n
.w: add esi, edx
.n: inc ecx
    cmp ecx, 128
    jb .sq
    mov eax, esi
    cmp dword [side], 0
    je .r
    neg eax
.r: pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; edi = moves, ecx = count: puts the captures first
order:
    pushad
    xor esi, esi                ; next slot for a capture
    xor ebx, ebx
.l: cmp ebx, ecx
    jae .d
    mov eax, [edi+ebx*4]
    test eax, MF_CAP
    jz .n
    mov edx, [edi+esi*4]
    mov [edi+esi*4], eax
    mov [edi+ebx*4], edx
    inc esi
.n: inc ebx
    jmp .l
.d: popad
    ret

; ecx = depth, ebx = alpha, edx = beta -> eax = score (negamax)
SR_ALPHA equ 0
SR_BETA  equ 4
SR_LIST  equ 8
SR_N     equ 12
SR_I     equ 16
SR_LEGAL equ 20
SR_DEPTH equ 24
SR_SIZE  equ 28
search:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    test ecx, ecx
    jnz .go
    call qsearch
    jmp .r
.go:
    sub esp, SR_SIZE
    mov ebp, esp
    mov [ebp+SR_ALPHA], ebx
    mov [ebp+SR_BETA], edx
    mov [ebp+SR_DEPTH], ecx
    mov edi, [msp]
    mov [ebp+SR_LIST], edi
    call gen
    mov [ebp+SR_N], eax
    lea edx, [edi+eax*4]
    mov [msp], edx
    mov ecx, eax
    call order
    mov dword [ebp+SR_I], 0
    mov dword [ebp+SR_LEGAL], 0
.l: mov eax, [ebp+SR_I]
    cmp eax, [ebp+SR_N]
    jae .end
    inc dword [ebp+SR_I]
    mov edi, [ebp+SR_LIST]
    mov eax, [edi+eax*4]
    call make
    mov edx, [side]
    mov ecx, edx
    xor ecx, BLACKP
    shr ecx, 3
    movzx ecx, byte [ksq+ecx]
    call attacked
    test eax, eax
    jnz .undo
    inc dword [ebp+SR_LEGAL]
    mov ecx, [ebp+SR_DEPTH]
    dec ecx
    mov ebx, [ebp+SR_BETA]
    neg ebx
    mov edx, [ebp+SR_ALPHA]
    neg edx
    call search
    neg eax
    call unmake
    cmp eax, [ebp+SR_BETA]
    jge .cut
    cmp eax, [ebp+SR_ALPHA]
    jle .l
    mov [ebp+SR_ALPHA], eax
    jmp .l
.undo:
    call unmake
    jmp .l
.cut:
    mov eax, [ebp+SR_BETA]
    jmp .out
.end:
    mov eax, [ebp+SR_ALPHA]
    cmp dword [ebp+SR_LEGAL], 0
    jne .out
    call in_check
    test eax, eax
    jz .out                     ; stalemate: 0
    mov eax, [ply]
    sub eax, MATE               ; mated: worse the sooner
.out:
    mov edi, [ebp+SR_LIST]
    mov [msp], edi
    add esp, SR_SIZE
.r: pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebx = alpha, edx = beta -> eax = score of the quiet position reached
; by trying the captures only (so a search never stops in the middle of
; an exchange); "standing pat" on the evaluation is always allowed
qsearch:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    sub esp, SR_SIZE
    mov ebp, esp
    mov [ebp+SR_ALPHA], ebx
    mov [ebp+SR_BETA], edx
    call evaluate
    cmp eax, edx
    jge .cut
    cmp eax, ebx
    jle .gen
    mov [ebp+SR_ALPHA], eax
.gen:
    mov edi, [msp]
    mov [ebp+SR_LIST], edi
    call gen
    mov [ebp+SR_N], eax
    lea edx, [edi+eax*4]
    mov [msp], edx
    mov dword [ebp+SR_I], 0
.l: mov eax, [ebp+SR_I]
    cmp eax, [ebp+SR_N]
    jae .end
    inc dword [ebp+SR_I]
    mov edi, [ebp+SR_LIST]
    mov eax, [edi+eax*4]
    test eax, MF_CAP
    jz .l
    call make
    mov edx, [side]
    mov ecx, edx
    xor ecx, BLACKP
    shr ecx, 3
    movzx ecx, byte [ksq+ecx]
    call attacked
    test eax, eax
    jnz .undo
    mov ebx, [ebp+SR_BETA]
    neg ebx
    mov edx, [ebp+SR_ALPHA]
    neg edx
    call qsearch
    neg eax
    call unmake
    cmp eax, [ebp+SR_BETA]
    jge .cutl
    cmp eax, [ebp+SR_ALPHA]
    jle .l
    mov [ebp+SR_ALPHA], eax
    jmp .l
.undo:
    call unmake
    jmp .l
.cutl:
    mov edi, [ebp+SR_LIST]
    mov [msp], edi
.cut:
    mov eax, [ebp+SR_BETA]
    jmp .out
.end:
    mov edi, [ebp+SR_LIST]
    mov [msp], edi
    mov eax, [ebp+SR_ALPHA]
.out:
    add esp, SR_SIZE
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Picks the computer's move at the set depth -> eax = move (0 if none)
think:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov dword [ply], 0
    mov edi, [msp]
    call gen_legal
    mov [th_n], eax
    mov [th_list], edi
    lea edx, [edi+eax*4]
    mov [msp], edx
    mov ecx, eax
    call order
    mov dword [th_best], 0
    mov dword [th_score], -INF
    xor esi, esi
.l: cmp esi, [th_n]
    jae .d
    mov edi, [th_list]
    mov eax, [edi+esi*4]
    call make
    mov ecx, [depth]
    dec ecx
    mov ebx, -INF
    mov edx, [th_score]
    neg edx
    inc edx                     ; window (-INF, -best+1) keeps ties visible
    call search
    neg eax
    call unmake
    cmp eax, [th_score]
    jg .take
    jl .n
    call g_rand
    test eax, 0x100
    jz .n
.take_eq:
    mov edi, [th_list]
    mov eax, [edi+esi*4]
    mov [th_best], eax
    jmp .n
.take:
    mov [th_score], eax
    jmp .take_eq
.n: inc esi
    jmp .l
.d: mov edi, [th_list]
    mov [msp], edi
    mov eax, [th_best]
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- notation ----------

; eax = legal move -> san_buf = its SAN (with + or #); position unchanged
san:
    pushad
    mov [sn_move], eax
    mov edi, san_buf
    test eax, MF_CASTLE
    jz .normal
    mov esi, s_oo
    mov ecx, eax
    shr ecx, 8
    and ecx, 0xFF
    and eax, 0xFF
    cmp ecx, eax
    ja .copy
    mov esi, s_ooo
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
    dec edi
    jmp .check
.normal:
    mov ecx, eax
    and ecx, 0xFF               ; from
    mov ebx, eax
    shr ebx, 8
    and ebx, 0xFF               ; to
    movzx edx, byte [board+ecx]
    and edx, 7                  ; piece type
    cmp edx, PAWN
    je .pawn
    mov al, [piece_letter+edx]
    stosb
    call disambig               ; writes the file and/or rank if needed
    jmp .cap
.pawn:
    test dword [sn_move], MF_CAP
    jz .to
    mov al, cl
    and al, 7
    add al, 'a'
    stosb
.cap:
    test dword [sn_move], MF_CAP
    jz .to
    mov al, 'x'
    stosb
.to:
    mov eax, ebx
    call put_sq_buf
    mov eax, [sn_move]
    shr eax, 16
    and eax, 7
    jz .check
    mov byte [edi], '='
    mov al, [piece_letter+eax]
    mov [edi+1], al
    add edi, 2
.check:
    mov eax, [sn_move]
    call make
    call in_check
    test eax, eax
    jz .done
    push edi
    mov edi, [msp]
    call gen_legal
    pop edi
    mov byte [edi], '+'
    test eax, eax
    jnz .plus
    mov byte [edi], '#'
.plus:
    inc edi
.done:
    call unmake
    mov byte [edi], 0
    popad
    ret

; ecx = from, ebx = to, edx = piece type, edi = output: writes the file,
; the rank or both of the from square when another piece of that type
; can also go to the target (edi advanced)
disambig:
    push eax
    push esi
    push ebp
    mov [db_out], edi
    mov dword [db_same], 0      ; another one can go there
    mov dword [db_file], 0      ; ...and one of them shares the file
    mov dword [db_rank], 0      ; ...or the rank
    mov edi, [msp]
    call gen_legal
    mov esi, edi
    mov ebp, eax
.l: test ebp, ebp
    jz .d
    mov eax, [esi]
    add esi, 4
    dec ebp
    push eax
    shr eax, 8
    and eax, 0xFF
    cmp eax, ebx
    pop eax
    jne .l
    and eax, 0xFF
    cmp eax, ecx
    je .l
    push eax
    movzx eax, byte [board+eax]
    and eax, 7
    cmp eax, edx
    pop eax
    jne .l
    mov dword [db_same], 1
    push eax
    xor eax, ecx
    test eax, 0x07
    jnz .nf
    mov dword [db_file], 1
.nf:
    test eax, 0x70
    jnz .nr
    mov dword [db_rank], 1
.nr:
    pop eax
    jmp .l
.d: mov edi, [db_out]
    cmp dword [db_same], 0
    je .r
    cmp dword [db_file], 0
    jne .rank
    mov al, cl                  ; the file is enough
    and al, 7
    add al, 'a'
    stosb
    jmp .r
.rank:
    cmp dword [db_rank], 0
    jne .both
    mov al, cl
    shr al, 4
    add al, '1'
    stosb
    jmp .r
.both:
    mov eax, ecx
    call put_sq_buf
.r: pop ebp
    pop esi
    pop eax
    ret

; eax = square, edi = output: writes it like "e4" (edi advanced)
put_sq_buf:
    push eax
    push ebx
    mov ebx, eax
    and al, 7
    add al, 'a'
    stosb
    mov eax, ebx
    shr al, 4
    add al, '1'
    stosb
    pop ebx
    pop eax
    ret

; esi = text -> eax = the legal move it names (coordinate notation, or
; o-o / o-o-o), or 0
parse_move:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    call g_skipsp
    mov edi, w_ooo
    call g_word
    jnc .ooo
    mov edi, w_oo
    call g_word
    jnc .oo
    call .square
    jc .no
    mov ecx, eax                ; from
    call .square
    jc .no
    mov ebx, eax                ; to
    xor edx, edx                ; promotion (0 = queen if needed)
    mov al, [esi]
    test al, al
    jz .find
    cmp al, ' '
    je .find
    mov edi, promo_letters
    mov edx, KNIGHT
.pl: cmp al, [edi+edx]
    je .pok
    inc edx
    cmp edx, QUEEN
    jbe .pl
    jmp .no
.pok:
    inc esi
    jmp .find
.oo:
    mov edx, 2
    jmp .castle
.ooo:
    mov edx, -2
.castle:
    mov eax, [side]
    shr eax, 3
    movzx ecx, byte [ksq+eax]
    lea ebx, [ecx+edx]
    xor edx, edx
.find:
    push edx
    mov edi, [msp]
    call gen_legal
    pop edx
    test edx, edx
    jnz .scan
    mov edx, QUEEN              ; a promotion without a letter: queen
.scan:
    test eax, eax
    jz .no
    mov esi, [edi]
    add edi, 4
    dec eax
    push esi
    and esi, 0xFF
    cmp esi, ecx
    pop esi
    jne .scan
    push esi
    shr esi, 8
    and esi, 0xFF
    cmp esi, ebx
    pop esi
    jne .scan
    push esi
    shr esi, 16
    and esi, 7
    jz .nopromo
    cmp esi, edx
    pop esi
    jne .scan
    mov eax, esi
    jmp .r
.nopromo:
    pop esi
    mov eax, esi
    jmp .r
.no:
    xor eax, eax
.r: pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
.square:                        ; esi -> eax = square, CF if none
    movzx eax, byte [esi]
    sub eax, 'a'
    cmp eax, 8
    jae .sbad
    movzx edx, byte [esi+1]
    sub edx, '1'
    cmp edx, 8
    jae .sbad
    shl edx, 4
    or eax, edx
    add esi, 2
    clc
    ret
.sbad:
    stc
    ret

; ---------- game record (PGN) ----------

pgn_reset:
    mov dword [pgn_len], 0
    mov byte [pgn_text], 0
    mov dword [moveno], 1
    mov byte [pgn_done], 0
    ret

; esi = ASCIIZ: appends it to the move text
pgn_add:
    push eax
    push edi
    mov edi, [pgn_len]
    add edi, pgn_text
.l: lodsb
    cmp edi, pgn_text + PGN_MAX - 2
    jae .full
    mov [edi], al
    inc edi
    test al, al
    jnz .l
    dec edi
.full:
    mov byte [edi], 0
    sub edi, pgn_text
    mov [pgn_len], edi
    pop edi
    pop eax
    ret

; eax = legal move: writes its SAN to the record and plays it
play_san:
    pushad
    mov [ps_move], eax
    call san
    cmp dword [side], 0
    jne .black
    mov eax, [moveno]
    mov edi, num_buf
    call itoa
    mov esi, num_buf
    call pgn_add
    mov esi, s_dot
    call pgn_add
    jmp .san
.black:
    inc dword [moveno]
.san:
    mov esi, san_buf
    call pgn_add
    mov esi, s_space
    call pgn_add
    mov eax, [ps_move]
    call make
    popad
    ret

; adds the result to the move text once the game has ended
pgn_result:
    pushad
    cmp byte [pgn_done], 0
    jne .r
    mov byte [pgn_done], 1
    call status
    mov esi, s_draw
    cmp eax, 2
    je .add
    mov esi, s_w
    cmp dword [side], 0
    jne .add                    ; Black to move and mated
    mov esi, s_b
.add:
    call pgn_add
.r: popad
    ret

; eax = number, edi = buffer: writes it in decimal, 0-terminated
itoa:
    pushad
    mov ebx, 10
    xor ecx, ecx
.d: xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.p: pop eax
    add al, '0'
    stosb
    loop .p
    mov byte [edi], 0
    popad
    ret

; esi = the rest of the command: the file name. Writes the PGN tags,
; the move text and the result.
save_pgn:
    pushad
    call g_skipsp
    cmp byte [esi], 0
    je .bad
    mov ebx, esi
    mov eax, SYS_OPEN
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    cmp eax, -1
    je .bad
    mov [fd], eax
    mov esi, pgn_head
    call .write
    mov esi, pgn_text
    call .write
    cmp byte [pgn_done], 0
    jne .closed
    mov esi, s_star
    call .write
.closed:
    mov esi, s_nl
    call .write
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    mov esi, m_saved
    call g_puts
    popad
    ret
.bad:
    mov esi, m_nosave
    call g_puts
    popad
    ret
.write:                         ; esi = ASCIIZ
    push esi
    mov edi, esi
    xor ecx, ecx
.len:
    cmp byte [edi+ecx], 0
    je .w
    inc ecx
    jmp .len
.w: mov edx, ecx
    mov ecx, esi
    mov ebx, [fd]
    mov eax, SYS_WRITE
    int 0x80
    pop esi
    ret

; ---------- screen ----------

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
    or ebx, ecx
    movzx eax, byte [board+ebx]
    mov al, [fen_pieces+eax]
    test al, al
    jnz .pc
    mov al, '.'
.pc:
    call g_putc
    mov al, ' '
    call g_putc
    inc ecx
    cmp ecx, 8
    jb .f
    call g_nl
    dec edx
    jns .r
    call status
    mov esi, m_mate
    cmp eax, 1
    je .say
    mov esi, m_stale
    cmp eax, 2
    je .say
    call in_check
    mov esi, m_check
    test eax, eax
    jnz .say
    mov esi, m_white
    cmp dword [side], 0
    je .say
    mov esi, m_black
.say:
    call g_puts
    popad
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%macro PERFT 3                  ; FEN, depth, expected leaves
    mov esi, %1
    call fen_load
    mov ecx, %2
    call perft
    EXPECT %3
%endmacro

; esi = a string, edi = another -> eax = 1 if equal
streq:
    push esi
    push edi
.l: mov al, [esi]
    cmp al, [edi]
    jne .no
    inc esi
    inc edi
    test al, al
    jnz .l
    mov eax, 1
    jmp .r
.no:
    xor eax, eax
.r: pop edi
    pop esi
    ret

; esi = coordinate move text -> plays it with its SAN recorded
%macro PLAYS 1
    mov esi, %1
    call parse_move
    call play_san
%endmacro

; ---------- graphics ----------

; The board on the left (22-pixel squares, White at the bottom), the
; moves and the state of the game on the right. Click one of your pieces
; and then where it goes (or use the arrows and Enter); the squares it
; may go to are dotted. Pawns promote to a queen here.
SQ      equ 22
BX0     equ 12
BY0     equ 12
PX      equ BX0 + 8 * SQ + 10   ; the panel on the right

gui_play:
    call gui_open
    jnc .new
    mov esi, m_nogui
    call g_puts
    mov eax, 1
    ret
.new:
    mov esi, fen_start
    call fen_load
    call pgn_reset
    mov dword [cursor], 0x14    ; e2
    mov dword [gsel], -1
    mov dword [glast], -1
    mov byte [gyou], 0
    mov byte [gme], 0
.turn:
    call gstate                 ; gmsg from the state of the game
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
    je .esc
    cmp al, 'q'
    je .quit
    cmp al, 'n'
    je .new
    cmp al, '1'
    jb .k
    cmp al, '4'
    ja .k
    sub al, '0'
    movzx eax, al
    mov [depth], eax
    jmp .turn
.k: cmp al, 13
    je .act
    cmp al, ' '
    je .act
    shr eax, 8
    cmp al, K_ENTER
    je .act
    call gmove
    jmp .draw
.esc:
    cmp dword [gsel], -1
    je .quit
    mov dword [gsel], -1        ; Esc first drops the piece
    jmp .draw
.click:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    call ghit
    cmp eax, -1
    je .draw
    mov [cursor], eax
.act:
    call status
    test eax, eax
    jnz .draw                   ; the game is over
    mov ebx, [cursor]
    movzx eax, byte [board+ebx]
    test eax, eax
    jz .to
    test eax, BLACKP
    jnz .to
    mov [gsel], ebx             ; one of yours: pick it (again)
    jmp .draw
.to:
    cmp dword [gsel], -1
    je .draw
    mov eax, [gsel]
    call gfind                  ; eax = the move, or 0
    test eax, eax
    jnz .play
    mov dword [gmsg], m_g_illegal
    jmp .draw
.play:
    mov dword [gsel], -1
    mov [glast], eax
    call play_san
    mov esi, san_buf
    mov edi, gyou
    call gcopy
    mov byte [gme], 0
    call status
    test eax, eax
    jnz .turn
    mov dword [gmsg], m_g_think
    call gdraw
    call gui_flip
    call think
    test eax, eax
    jz .turn
    mov [glast], eax
    call play_san
    mov esi, san_buf
    mov edi, gme
    call gcopy
    jmp .turn
.quit:
    call gui_close
    xor eax, eax
    ret

; esi -> edi: copies a short ASCIIZ text (at most 15 characters)
gcopy:
    push eax
    push ecx
    mov ecx, 15
.l: lodsb
    stosb
    test al, al
    loopnz .l
    mov byte [edi], 0
    pop ecx
    pop eax
    ret

; Sets gmsg from the game: your move, check, mate or stalemate
gstate:
    push eax
    call status
    mov esi, m_g_mated
    cmp eax, 1
    jne .st
    cmp dword [side], 0
    je .s
    mov esi, m_g_mate
    jmp .s
.st:mov esi, m_g_stale
    cmp eax, 2
    je .s
    mov esi, m_g_check
    call in_check
    test eax, eax
    jnz .s
    mov esi, m_g_help
.s: mov [gmsg], esi
    pop eax
    ret

; eax = from square, [cursor] = to -> eax = the legal move (a queen for
; a promotion), or 0
gfind:
    push ebx
    push ecx
    push edx
    push edi
    mov edx, [cursor]
    shl edx, 8
    or edx, eax                 ; from | to << 8
    mov edi, [msp]
    call gen_legal
    mov ecx, eax
.l: jecxz .no
    mov eax, [edi]
    mov ebx, eax
    and ebx, 0xFFFF
    cmp ebx, edx
    jne .n
    mov ebx, eax
    shr ebx, 16
    and ebx, 7
    jz .r
    cmp ebx, QUEEN
    je .r
.n: add edi, 4
    dec ecx
    jmp .l
.no:
    xor eax, eax
.r: pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; al = scancode: the arrows move the cursor over the board
gmove:
    push eax
    push ebx
    mov ebx, [cursor]
    cmp al, K_LEFT
    jne .rt
    dec ebx
.rt:cmp al, K_RIGHT
    jne .up
    inc ebx
.up:cmp al, K_UP
    jne .dn
    add ebx, 16
.dn:cmp al, K_DOWN
    jne .ck
    sub ebx, 16
.ck:test ebx, 0xFFFFFF88
    jnz .r
    mov [cursor], ebx
.r: pop ebx
    pop eax
    ret

; eax, ebx = a point -> eax = the square there, or -1
ghit:
    push ecx
    push edx
    sub eax, BX0
    js .no
    sub ebx, BY0
    js .no
    xor edx, edx
    mov ecx, SQ
    div ecx
    cmp eax, 8
    jae .no
    xchg eax, ebx               ; ebx = file
    xor edx, edx
    div ecx
    cmp eax, 8
    jae .no
    neg eax
    add eax, 7                  ; rank
    shl eax, 4
    add eax, ebx
    jmp .r
.no:
    mov eax, -1
.r: pop edx
    pop ecx
    ret

; ebx = square -> eax, ebx = its top left corner
gpos:
    mov eax, ebx
    and eax, 7
    imul eax, SQ
    add eax, BX0
    shr ebx, 4
    neg ebx
    add ebx, 7
    imul ebx, SQ
    add ebx, BY0
    ret

; eax, ebx = top left, dl = piece: its shape, outlined
gpiece:
    pushad
    movzx esi, dl
    and esi, 7
    dec esi
    shl esi, 5
    add esi, gpieces
    mov cl, C_WHITE             ; White: white with a black rim
    mov ch, C_BLACK
    test dl, BLACKP
    jz .c
    mov cl, C_BLACK             ; Black: black with a light rim
    mov ch, C_LGREY
.c: mov [gox], eax
    mov [goy], ebx
    mov [gink], cx
    ; the rim: every pixel of the shape moved one step four ways
    mov cl, ch
    mov eax, -1
    xor ebx, ebx
    call .shape
    mov eax, 1
    call .shape
    xor eax, eax
    mov ebx, -1
    call .shape
    mov ebx, 1
    call .shape
    mov cl, [gink]
    xor ebx, ebx
    call .shape
    popad
    ret
; eax, ebx = shift, cl = colour, esi = shape
.shape:
    pushad
    add eax, [gox]
    add ebx, [goy]
    mov edi, eax
    xor edx, edx                ; row
.row:
    movzx ebp, word [esi+edx*2]
    mov eax, edi
.col:
    test ebp, 0x8000
    jz .n
    call gui_pset
.n: inc eax
    shl ebp, 1
    and ebp, 0xFFFF
    jnz .col
    inc ebx
    inc edx
    cmp edx, 16
    jb .row
    popad
    ret

gdraw:
    pushad
    call gg_table
    ; file letters above, rank numbers to the left
    mov byte [gbuf+1], 0
    xor ecx, ecx
.fl:lea eax, ['a'+ecx]
    mov [gbuf], al
    imul eax, ecx, SQ
    add eax, BX0 + SQ / 2 - 3
    mov ebx, 2
    mov esi, gbuf
    push ecx
    mov cl, C_WHITE
    call gg_textc
    pop ecx
    lea eax, ['8'+0]
    sub eax, ecx
    mov [gbuf], al
    mov eax, 3
    imul ebx, ecx, SQ
    add ebx, BY0 + SQ / 2 - 4
    push ecx
    mov cl, C_WHITE
    call gg_textc
    pop ecx
    inc ecx
    cmp ecx, 8
    jb .fl
    ; the moves the picked piece may make
    mov dword [gdests], 0
    cmp dword [gsel], -1
    je .sq0
    mov edi, [msp]
    call gen_legal
    mov [gdests], eax
    mov [gdlist], edi
.sq0:
    xor ebx, ebx
.sq:test ebx, 0x88
    jnz .sn
    push ebx
    mov ecx, ebx
    shr ecx, 4
    add ecx, ebx
    and ecx, 1                  ; 1 = light square
    call gpos
    mov byte [gui_ink], C_BROWN
    jecxz .dk
    mov byte [gui_ink], C_LGREY
.dk:mov ecx, SQ
    mov edx, SQ
    call gui_fill
    mov esi, [esp]
    ; the last move, lightly marked
    cmp dword [glast], -1
    je .pc
    movzx ebp, byte [glast]
    cmp esi, ebp
    je .lm
    movzx ebp, byte [glast+1]
    cmp esi, ebp
    jne .pc
.lm:mov byte [gui_ink], C_YELLOW
    call gui_box
.pc:movzx edx, byte [board+esi]
    test edx, edx
    jz .dot
    add eax, 3
    add ebx, 3
    call gpiece
    sub eax, 3
    sub ebx, 3
.dot:
    ; a dot where the picked piece may go
    mov ecx, [gdests]
    mov edi, [gdlist]
.dl:jecxz .sd
    movzx edx, byte [edi]
    cmp edx, [gsel]
    jne .dn
    movzx edx, byte [edi+1]
    cmp edx, esi
    jne .dn
    add eax, SQ / 2 - 2
    add ebx, SQ / 2 - 2
    mov ecx, 4
    mov edx, 4
    mov byte [gui_ink], C_LGREEN
    call gui_fill
    jmp .sd
.dn:add edi, 4
    dec ecx
    jmp .dl
.sd:pop ebx
.sn:inc ebx
    cmp ebx, 0x78
    jb .sq
    ; the picked piece and the cursor
    cmp dword [gsel], -1
    je .cu
    mov ebx, [gsel]
    call gpos
    mov ecx, SQ
    mov edx, SQ
    mov byte [gui_ink], C_LGREEN
    call gui_box
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    call gui_box
.cu:mov ebx, [cursor]
    call gpos
    mov ecx, SQ
    mov edx, SQ
    mov byte [gui_ink], C_WHITE
    call gui_box
    ; the panel: who plays, the last two moves, the level
    mov esi, m_g_name
    mov eax, PX
    mov ebx, 14
    mov cl, C_WHITE
    call gg_textc
    mov esi, m_g_youare
    mov ebx, 30
    mov cl, C_LGREY
    call gg_textc
    mov edi, gbuf
    call gg_sb_start
    mov esi, m_g_you
    call gg_sb_str
    mov esi, gyou
    call gg_sb_str
    mov esi, gbuf
    mov ebx, 54
    mov cl, C_WHITE
    call gg_textc
    call gg_sb_start
    mov esi, m_g_me
    call gg_sb_str
    mov esi, gme
    call gg_sb_str
    mov esi, gbuf
    mov ebx, 66
    call gg_textc
    call gg_sb_start
    mov esi, m_g_level
    call gg_sb_str
    mov eax, [depth]
    call gg_sb_num
    mov esi, gbuf
    mov eax, PX
    mov ebx, 90
    mov cl, C_LGREY
    call gg_textc
    mov esi, m_g_keys
    mov ebx, 102
    call gg_textc
    mov esi, m_g_keys2
    mov ebx, 114
    call gg_textc
    mov esi, [gmsg]
    call gg_status
    popad
    ret

; piece shapes, 16 x 16, bit 15 = left column: pawn, knight, bishop,
; rook, queen, king (original drawings)
gpieces:
    dw 0x0000, 0x0000, 0x0000, 0x0180, 0x03C0, 0x03C0, 0x0180, 0x03C0   ; pawn
    dw 0x0180, 0x0180, 0x03C0, 0x07E0, 0x0FF0, 0x0FF0, 0x0000, 0x0000
    dw 0x0000, 0x0000, 0x0340, 0x07E0, 0x0FF0, 0x1F70, 0x1FF8, 0x0EF8   ; knight
    dw 0x01F8, 0x03F0, 0x07F0, 0x07F0, 0x0FF8, 0x0FF8, 0x0000, 0x0000
    dw 0x0000, 0x0180, 0x03C0, 0x0760, 0x06E0, 0x07E0, 0x03C0, 0x0180   ; bishop
    dw 0x03C0, 0x03C0, 0x07E0, 0x0180, 0x0FF0, 0x0FF0, 0x0000, 0x0000
    dw 0x0000, 0x0000, 0x0DB0, 0x0FF0, 0x0FF0, 0x07E0, 0x07E0, 0x07E0   ; rook
    dw 0x07E0, 0x07E0, 0x07E0, 0x0FF0, 0x1FF8, 0x1FF8, 0x0000, 0x0000
    dw 0x0000, 0x1188, 0x1188, 0x1998, 0x1DB8, 0x0FF0, 0x0FF0, 0x07E0   ; queen
    dw 0x07E0, 0x07E0, 0x0FF0, 0x1FF8, 0x1FF8, 0x0FF0, 0x0000, 0x0000
    dw 0x0000, 0x0180, 0x03C0, 0x0180, 0x1DB8, 0x3FFC, 0x3FFC, 0x3FFC   ; king
    dw 0x1FF8, 0x0FF0, 0x07E0, 0x07E0, 0x0FF0, 0x1FF8, 0x1FF8, 0x0000

selftest:
    mov eax, 1
    call g_srand
    ; 1. perft: the start position, a castling and en-passant test
    ;    position, and an endgame with pins and en passant
    PERFT fen_start, 1, 20      ; 1
    PERFT fen_start, 2, 400     ; 2
    PERFT fen_start, 3, 8902    ; 3
    PERFT fen_kiwi, 1, 48       ; 4
    PERFT fen_kiwi, 2, 2039     ; 5
    PERFT fen_end, 1, 14        ; 6
    PERFT fen_end, 2, 191       ; 7
    PERFT fen_end, 3, 2812      ; 8
    ; 2. make and unmake leave the board exactly as it was
    mov esi, fen_kiwi
    call fen_load
    call board_hash
    mov [t_hash], eax
    mov ecx, 2
    call perft
    call board_hash
    EXPECT [t_hash]             ; 9
    ; 3. the engine finds a mate in one on the back rank
    mov esi, fen_mate1
    call fen_load
    mov dword [depth], 2
    call think
    and eax, 0xFFFF
    EXPECT 0x7000               ; 10: a1 to a8
    ; and wins the queen when it is hanging
    mov esi, fen_hang
    call fen_load
    mov dword [depth], 2
    call think
    and eax, 0xFFFF
    EXPECT 0x4325               ; 11: the bishop on f3 (0x25) takes d5 (0x43)
    ; 4. checkmate and stalemate
    mov esi, fen_stale
    call fen_load
    call status
    EXPECT 2                    ; 12
    ; 5. SAN and PGN: the fastest mate
    mov esi, fen_start
    call fen_load
    call pgn_reset
    PLAYS t_f3
    PLAYS t_e5
    PLAYS t_g4
    PLAYS t_qh4
    call status
    EXPECT 1                    ; 13: White is mated
    call pgn_result
    mov esi, pgn_text
    mov edi, t_pgn
    call streq
    EXPECT 1                    ; 14: "1. f3 e5 2. g4 Qh4# 0-1"
    ; disambiguation, castling, promotion in SAN
    mov esi, fen_dis
    call fen_load
    mov esi, t_b1d2
    call parse_move
    call san
    mov esi, san_buf
    mov edi, t_nbd2
    call streq
    EXPECT 1                    ; 15: Nbd2
    mov esi, w_oo
    call parse_move
    call san
    mov esi, san_buf
    mov edi, s_oo
    call streq
    EXPECT 1                    ; 16: O-O
    mov esi, t_a7a8
    call parse_move
    shr eax, 16
    and eax, 7
    EXPECT QUEEN                ; 17: a7a8 promotes to a queen
    mov esi, t_a7a8n
    call parse_move
    call san
    mov esi, san_buf
    mov edi, t_a8n
    call streq
    EXPECT 1                    ; 18: a8=N
    ; 6. illegal input is refused
    mov esi, fen_start
    call fen_load
    mov esi, t_e2e5
    call parse_move
    EXPECT 0                    ; 19
    call g_report
    ret

board_hash:                     ; -> eax
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
.l: movzx edx, byte [board+ecx]
    imul eax, 31
    add eax, edx
    inc ecx
    cmp ecx, 128
    jb .l
    add eax, [castle]
    add eax, [ep]
    add eax, [side]
    pop edx
    pop ecx
    ret

; ---------- data ----------

fen_pieces db 0, 'PNBRQK', 0, 0, 'pnbrqk', 0
piece_letter db 0, 'PNBRQK'
promo_letters db 0, 0, 'nbrq'
knight_off db 14, 18, 31, 33, -14, -18, -31, -33, 0
king_off db 1, 15, 16, 17, -1, -15, -16, -17, 0
bishop_dir db 15, 17, -15, -17, 0
rook_dir db 1, 16, -1, -16, 0
alignb 4
piece_value dd 0, 100, 320, 330, 500, 900, 0, 0
; centre bonus by square (rank * 8 + file)
centre:
    db 0, 2, 4, 6, 6, 4, 2, 0
    db 2, 6, 8,10,10, 8, 6, 2
    db 4, 8,14,16,16,14, 8, 4
    db 6,10,16,20,20,16,10, 6
    db 6,10,16,20,20,16,10, 6
    db 4, 8,14,16,16,14, 8, 4
    db 2, 6, 8,10,10, 8, 6, 2
    db 0, 2, 4, 6, 6, 4, 2, 0
; castling rights kept after a move from or to each square
castle_mask:
    db 0x0D, 0x0F, 0x0F, 0x0F, 0x0C, 0x0F, 0x0F, 0x0E   ; a1 .. h1
    times 8 + 16*6 db 0x0F
    db 0x07, 0x0F, 0x0F, 0x0F, 0x03, 0x0F, 0x0F, 0x0B   ; a8 .. h8
    times 8 db 0x0F

fen_start db 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 0
fen_kiwi db 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', 0
fen_end db '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', 0
fen_mate1 db '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', 0
fen_hang db '4k3/8/8/3q4/8/5B2/8/4K3 w - - 0 1', 0
fen_stale db '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', 0
fen_dis db '4k3/P7/8/8/8/5N2/8/1N2K2R w K - 0 1', 0
t_f3 db 'f2f3', 0
t_e5 db 'e7e5', 0
t_g4 db 'g2g4', 0
t_qh4 db 'd8h4', 0
t_pgn db '1. f3 e5 2. g4 Qh4# 0-1', 0
t_b1d2 db 'b1d2', 0
t_nbd2 db 'Nbd2', 0
t_a7a8 db 'a7a8', 0
t_a7a8n db 'a7a8n', 0
t_a8n db 'a8=N', 0
t_e2e5 db 'e2e5', 0
s_oo db 'O-O', 0
s_ooo db 'O-O-O', 0
s_dot db '. ', 0
s_space db ' ', 0
s_w db '1-0', 0
s_b db '0-1', 0
s_draw db '1/2-1/2', 0
s_star db '*', 0
s_nl db 10, 0
w_oo db 'o-o', 0
w_ooo db 'o-o-o', 0
w_moves db 'moves', 0
w_save db 'save', 0
w_level db 'level', 0
pgn_head db '[Event "Squirrel Chess game"]', 10
         db '[Site "Squirrel-OS/2"]', 10
         db '[Date "????.??.??"]', 10
         db '[Round "-"]', 10
         db '[White "You"]', 10
         db '[Black "Squirrel Chess"]', 10, 10, 0

m_name db 'chess', 0
m_nogui db 'chess: no graphics screen', 10, 0
m_g_help db 'Your move: click a piece, then where it goes', 0
m_g_illegal db 'That move is not legal here', 0
m_g_think db 'Thinking...', 0
m_g_check db 'Check! Your move', 0
m_g_mate db 'Checkmate: you win! n new game, q quit', 0
m_g_mated db 'Checkmate: Squirrel Chess wins. n new game', 0
m_g_stale db 'Stalemate: a draw. n new game, q quit', 0
m_g_name db 'Squirrel Chess', 0
m_g_youare db 'You play White', 0
m_g_you db 'You: ', 0
m_g_me db 'Me:  ', 0
m_g_level db 'Level ', 0
m_g_keys db '1-4 level', 0
m_g_keys2 db 'n new  q quit', 0
m_title db 'Squirrel Chess - you play White (capitals). Moves like e2e4, e7e8q, o-o;', 10
        db 'moves shows the game, save F writes it as PGN, level 1-4, n new, q quits', 10, 0
m_cols db '    a b c d e f g h', 10, 0
m_prompt db 'chess> ', 0
m_help db 'Type a move like e2e4 (or moves, save F, level N, n, q)', 10, 0
m_illegal db 'That move is not legal here', 10, 0
m_think db 'Thinking...', 10, 0
m_iplay db 'Squirrel Chess plays ', 0
m_white db 'White to move', 10, 0
m_black db 'Black to move', 10, 0
m_check db 'Check!', 10, 0
m_mate db 'Checkmate.', 10, 0
m_stale db 'Stalemate: a draw.', 10, 0
m_over db 'The game is over: moves, save F, n for a new game, q to quit', 10, 0
m_saved db 'Saved.', 10, 0
m_nosave db 'Could not save: give a file name, like save game.pgn', 10, 0

PGN_MAX equ 3072

SQX_BSS
G_BSS
side resd 1
castle resd 1
ep resd 1
hply resd 1
ply resd 1
msp resd 1
depth resd 1
gen_out resd 1
gen_n resd 1
pw_last resd 1
cs_k resd 1
cs_q resd 1
th_n resd 1
th_list resd 1
th_best resd 1
th_score resd 1
sn_move resd 1
db_out resd 1
db_same resd 1
db_file resd 1
db_rank resd 1
ps_move resd 1
pgn_len resd 1
moveno resd 1
fd resd 1
t_hash resd 1
ksq resb 2
pgn_done resb 1
alignb 4
board resb 128
san_buf resb 16
num_buf resb 12
undo resb UNDOMAX*UNDOSZ
movebuf resd MOVEBUF
pgn_text resb PGN_MAX
alignb 4
cursor resd 1
gsel resd 1
glast resd 1
gmsg resd 1
gdests resd 1
gdlist resd 1
gox resd 1
goy resd 1
gink resw 1
gyou resb 16
gme resb 16
gbuf resb GG_SBMAX
GUI_BSS
GG_BSS
SQX_END
