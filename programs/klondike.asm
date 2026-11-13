; klondike — Klondike solitaire, draw one (G.1). Original code.
;
;   run klondike [seed]    play a seeded deal
;   run klondike test      rules self-check, prints "klondike: PASS"
;
; Commands (columns 1-7, w = waste, f = foundations):
;   d        draw a card from the stock (turns the waste over when empty)
;   35       move from column 3 to column 5 (the longest run that fits);
;            also "m 3 5", "w4", "3f", "w f"
;   a        move every card that can go to the foundations
;   n        new deal            q   quit
;
;   run klondike gui [seed]   the same game on the graphics screen: Left /
;   Right (or the mouse) pick a pile, Enter / Space / a click takes the
;   cards from it, a second one puts them down; d draws, a moves cards up,
;   n deals again, Esc quits.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"
%include "gui.inc"
%include "gamegui.inc"

NCOL  equ 7
CSTR  equ 24                    ; bytes per column (6 down + 13 up fit)
SRC_W equ 7                     ; source index for the waste
DST_F equ 8                     ; destination index for the foundations

main:
    mov ebx, m_name
    call g_start
    jc selftest
    cmp byte [g_gui], 0
    jne gui_play
    mov esi, m_title
    call g_puts
.new:
    call deal
.loop:
    call draw
    call won
    test eax, eax
    jz .ask
    mov esi, m_won
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
    mov edi, w_draw
    call g_word
    jnc .draw
    mov edi, w_auto
    call g_word
    jnc .auto
    call parsemove
    jc .bad
    call domove
    test eax, eax
    jz .refused
    jmp .loop
.draw:
    call drawcard
    jmp .loop
.auto:
    call automove
    jmp .loop
.refused:
    mov esi, m_refused
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

clear:
    push eax
    push ecx
    push edi
    mov edi, tab
    mov ecx, state_end - tab
    xor eax, eax
    rep stosb
    pop edi
    pop ecx
    pop eax
    ret

; A seeded deal: column i gets i+1 cards, the top one face up; the rest
; is the stock.
deal:
    pushad
    call clear
    mov edi, deck
    call c_newdeck
    mov ecx, 52
    call g_shuffle
    mov esi, deck
    xor ecx, ecx                ; column
.col:
    mov edi, ecx
    imul edi, CSTR
    add edi, tab
    lea edx, [ecx+1]
    mov [tab_n+ecx], dl
    mov [tab_down+ecx], cl
.card:
    lodsb
    stosb
    dec edx
    jnz .card
    inc ecx
    cmp ecx, NCOL
    jb .col
    mov edi, stock              ; 52 - 28 = 24 cards
    mov ecx, 24
    rep movsb
    mov dword [stock_n], 24
    popad
    ret

; ecx = column -> edi = its cards, eax = how many
colptr:
    mov edi, ecx
    imul edi, CSTR
    add edi, tab
    movzx eax, byte [tab_n+ecx]
    ret

; al = card, dl = card it would go on (0 = empty column)
; -> CF clear when the move is allowed
fits:
    push eax
    push ebx
    push edx
    test dl, dl
    jnz .on
    and al, CARD_RANK
    cmp al, 13                  ; only a king on an empty column
    jne .no
    jmp .yes
.on:
    call c_stacks
    jc .no
.yes:
    clc
    jmp .r
.no:
    stc
.r: pop edx
    pop ebx
    pop eax
    ret

; al = card -> CF clear (and the card is on its foundation) when it is
; the next one of its suit
tofound:
    push eax
    push ebx
    movzx ebx, al
    shr ebx, 4
    and al, CARD_RANK
    dec al
    cmp al, [found+ebx]
    jne .no
    inc al
    mov [found+ebx], al
    clc
    jmp .r
.no:
    stc
.r: pop ebx
    pop eax
    ret

; ecx = column: turns its top card up if it is face down
turnup:
    push eax
    movzx eax, byte [tab_n+ecx]
    cmp al, [tab_down+ecx]
    jne .r
    test al, al
    jz .r
    dec byte [tab_down+ecx]
.r: pop eax
    ret

; ebx = source (0-6 column, 7 waste), ecx = destination (0-6, 8 = f)
; -> eax = 1 if the move was made, 0 if refused
domove:
    pushad
    mov [mv_src], ebx
    mov [mv_dst], ecx
    cmp ecx, DST_F
    je .found
    cmp ebx, ecx
    je .no
    call colptr                 ; the destination
    mov [dst_ptr], edi
    mov [dst_n], eax
    xor edx, edx
    test eax, eax
    jz .empty
    mov dl, [edi+eax-1]
.empty:
    cmp ebx, SRC_W
    jne .col
    mov eax, [waste_n]
    test eax, eax
    jz .no
    mov al, [waste+eax-1]
    call fits
    jc .no
    dec dword [waste_n]
    mov edi, [dst_ptr]
    add edi, [dst_n]
    mov [edi], al
    mov ecx, [mv_dst]
    inc byte [tab_n+ecx]
    jmp .yes
.col:
    mov ecx, ebx
    call colptr                 ; edi = source cards, eax = count
    mov [src_n], eax
    movzx esi, byte [tab_down+ecx]
.try:
    cmp esi, [src_n]
    jae .no
    mov al, [edi+esi]
    call fits
    jnc .run
    inc esi
    jmp .try
.run:                           ; move cards esi..src_n-1
    mov ecx, [src_n]
    sub ecx, esi
    mov ebx, [mv_dst]
    add [tab_n+ebx], cl
    mov ebx, [mv_src]
    mov eax, esi
    mov [tab_n+ebx], al
    add esi, edi
    mov edi, [dst_ptr]
    add edi, [dst_n]
    rep movsb
    mov ecx, [mv_src]
    call turnup
    jmp .yes
.found:
    cmp ebx, SRC_W
    jne .fcol
    mov eax, [waste_n]
    test eax, eax
    jz .no
    mov al, [waste+eax-1]
    call tofound
    jc .no
    dec dword [waste_n]
    jmp .yes
.fcol:
    mov ecx, ebx
    call colptr
    cmp al, [tab_down+ecx]      ; no face-up card (or empty)
    jbe .no
    mov al, [edi+eax-1]
    call tofound
    jc .no
    dec byte [tab_n+ecx]
    call turnup
.yes:
    mov dword [esp+28], 1
    popad
    ret
.no:
    mov dword [esp+28], 0
    popad
    ret

; Draws one card from the stock to the waste; with the stock empty,
; turns the waste over to make the stock again.
drawcard:
    pushad
    mov ecx, [stock_n]
    test ecx, ecx
    jz .over
    mov al, [stock+ecx-1]
    dec dword [stock_n]
    mov edx, [waste_n]
    mov [waste+edx], al
    inc dword [waste_n]
    jmp .r
.over:
    mov ecx, [waste_n]
    xor edx, edx
.l: test ecx, ecx
    jz .done
    mov al, [waste+ecx-1]
    mov [stock+edx], al
    inc edx
    dec ecx
    jmp .l
.done:
    mov [stock_n], edx
    mov dword [waste_n], 0
.r: popad
    ret

; Moves every card it can to the foundations, until none moves
automove:
    pushad
.again:
    xor ebp, ebp
    mov ebx, SRC_W
.src:
    mov ecx, DST_F
    call domove
    or ebp, eax
    dec ebx
    jns .src
    test ebp, ebp
    jnz .again
    popad
    ret

; -> eax = 1 when all four foundations reach the king
won:
    xor eax, eax
    cmp dword [found], 0x0D0D0D0D
    jne .r
    inc eax
.r: ret

; esi = text: "35", "m 3 5", "w4", "3f", "w f"
; -> ebx = source, ecx = destination, CF set when it is not a move
parsemove:
    push eax
    push esi
    push edi
    mov edi, w_move
    call g_word                 ; an optional "m"
    call g_skipsp
    lodsb
    mov ebx, SRC_W
    cmp al, 'w'
    je .dst
    movzx ebx, al
    sub ebx, '1'
    cmp ebx, NCOL
    jae .bad
.dst:
    call g_skipsp
    lodsb
    mov ecx, DST_F
    cmp al, 'f'
    je .end
    movzx ecx, al
    sub ecx, '1'
    cmp ecx, NCOL
    jae .bad
.end:
    call g_skipsp
    cmp byte [esi], 0
    jne .bad
    pop edi
    pop esi
    pop eax
    clc
    ret
.bad:
    pop edi
    pop esi
    pop eax
    stc
    ret

; ---------- screen ----------

draw:
    pushad
    call g_nl
    mov esi, m_stock
    call g_puts
    mov eax, [stock_n]
    mov ecx, 2
    call g_putdec_w
    mov esi, m_waste
    call g_puts
    xor eax, eax
    mov ecx, [waste_n]
    test ecx, ecx
    jz .w
    mov al, [waste+ecx-1]
.w: call c_print
    mov esi, m_found
    call g_puts
    xor ebx, ebx
.f: mov al, [found+ebx]
    test al, al
    jz .fe
    mov ah, bl
    shl ah, 4
    or al, ah
.fe:
    call c_print
    inc ebx
    cmp ebx, 4
    jb .f
    call g_nl
    mov esi, m_cols
    call g_puts
    ; rows: as many as the longest column
    xor edx, edx
    xor ecx, ecx
.mx:
    cmp dl, [tab_n+ecx]
    jae .mn
    mov dl, [tab_n+ecx]
.mn:
    inc ecx
    cmp ecx, NCOL
    jb .mx
    xor ebx, ebx                ; row
.row:
    cmp ebx, edx
    jae .done
    xor ecx, ecx
.cell:
    mov esi, m_gap
    call g_puts
    cmp bl, [tab_n+ecx]
    jae .blank
    cmp bl, [tab_down+ecx]
    jb .back
    push ecx
    push eax
    call colptr
    mov al, [edi+ebx]
    call c_print
    pop eax
    pop ecx
    jmp .nc
.back:
    call c_print_back
    jmp .nc
.blank:
    push ecx
    mov ecx, 3
    call g_spaces
    pop ecx
.nc:
    inc ecx
    cmp ecx, NCOL
    jb .cell
    call g_nl
    inc ebx
    jmp .row
.done:
    popad
    ret

; ---------- graphics ----------

; Places on the screen: 0 stock, 1 waste, 2-5 foundations (C D H S),
; 6-12 the columns. Top row at y 4, the columns from y 54.
NPLACE  equ 13
TOP_Y   equ 4
COL_Y   equ 54
COL_DX  equ 44
DOWN_DY equ 4
UP_DY   equ 10

gui_play:
    call gui_open
    jnc .ok
    mov esi, m_nogui
    call g_puts
    mov eax, 1
    ret
.ok:
    call deal
    mov dword [cursor], 6
    mov dword [held], -1
    mov dword [gmsg], m_g_help
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
    mov dword [gmsg], m_g_help
    cmp al, 'n'
    je .new
    cmp al, 'd'
    je .drawcard
    cmp al, 'a'
    je .auto
    cmp al, 13
    je .act
    cmp al, 10
    je .act
    cmp al, ' '
    je .act
    shr eax, 8
    cmp al, K_LEFT
    je .left
    cmp al, K_RIGHT
    je .right
    cmp al, K_ENTER
    je .act
    jmp .draw
.left:
    dec dword [cursor]
    jns .draw
    mov dword [cursor], NPLACE-1
    jmp .draw
.right:
    inc dword [cursor]
    cmp dword [cursor], NPLACE
    jb .draw
    mov dword [cursor], 0
    jmp .draw
.new:
    call deal
    mov dword [held], -1
    jmp .draw
.drawcard:
    call drawcard
    mov dword [held], -1
    jmp .draw
.auto:
    call automove
    mov dword [held], -1
    jmp .draw
.click:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    call ghit
    cmp eax, -1
    je .draw
    mov [cursor], eax
.act:
    call gact
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret

; eax, ebx = a point -> eax = the place there, or -1
ghit:
    push ebx
    push ecx
    push edx
    mov ecx, eax
    sub ecx, 4
    js .none
    mov eax, ecx
    xor edx, edx
    mov ecx, COL_DX
    div ecx                     ; eax = column of the grid
    cmp edx, CARD_W
    jae .none
    cmp eax, NCOL
    jae .none
    cmp ebx, COL_Y
    jae .col
    cmp ebx, TOP_Y + CARD_H
    jae .none
    cmp eax, 2
    jb .r                       ; stock 0, waste 1
    je .none
    dec eax                     ; foundations 2-5
    jmp .r
.col:
    add eax, 6
    jmp .r
.none:
    mov eax, -1
.r: pop edx
    pop ecx
    pop ebx
    ret

; Acts on the place under the cursor: draws, picks cards up, puts them down
gact:
    pushad
    mov eax, [cursor]
    cmp dword [held], -1
    jne .drop
    test eax, eax
    jnz .pick
    call drawcard
    jmp .r
.pick:
    cmp eax, 1
    jne .pc
    cmp dword [waste_n], 0
    je .r
    mov dword [held], 1
    jmp .r
.pc:
    cmp eax, 6
    jb .r
    lea ecx, [eax-6]
    mov dl, [tab_n+ecx]
    cmp dl, [tab_down+ecx]
    jbe .r                      ; no face-up card
    mov [held], eax
    jmp .r
.drop:
    mov ebx, [held]
    mov dword [held], -1
    cmp eax, ebx
    je .r                       ; put back
    cmp ebx, 1
    jne .bs
    mov ebx, SRC_W
    jmp .dst
.bs:
    sub ebx, 6
.dst:
    mov ecx, DST_F
    cmp eax, 6
    jb .df
    lea ecx, [eax-6]
.df:
    cmp eax, 2
    jb .no
    call domove
    test eax, eax
    jnz .r
.no:
    mov dword [gmsg], m_refused_g
.r: popad
    ret

; ecx = column -> edx = the step between face-up cards, so the column
; fits above the status bar
gstep:
    push eax
    push ebx
    movzx eax, byte [tab_n+ecx]
    movzx ebx, byte [tab_down+ecx]
    sub eax, ebx
    dec eax                     ; face-up steps
    mov edx, UP_DY
    jle .r
    push eax
    mov eax, STATUS_Y - 2 - COL_Y - CARD_H
    imul ebx, DOWN_DY
    sub eax, ebx
    xor edx, edx
    div dword [esp]
    add esp, 4
    mov edx, eax
    cmp edx, UP_DY
    jbe .r
    mov edx, UP_DY
.r: pop ebx
    pop eax
    ret

; eax = place -> eax, ebx, ecx, edx = its rectangle on the screen
grect:
    cmp eax, 6
    jae .col
    cmp eax, 2
    jb .top
    inc eax
.top:
    imul eax, COL_DX
    add eax, 4
    mov ebx, TOP_Y
    mov ecx, CARD_W
    mov edx, CARD_H
    ret
.col:
    push esi
    lea ecx, [eax-6]
    call gstep                  ; edx = step
    movzx esi, byte [tab_n+ecx]
    movzx eax, byte [tab_down+ecx]
    sub esi, eax
    dec esi
    jns .h
    xor esi, esi
.h: imul esi, edx
    imul eax, DOWN_DY
    add esi, eax
    add esi, CARD_H
    lea eax, [ecx-0]
    imul eax, COL_DX
    add eax, 4
    mov ebx, COL_Y
    mov ecx, CARD_W
    mov edx, esi
    pop esi
    ret

gdraw:
    pushad
    call gg_table
    ; stock and waste
    mov eax, 4
    mov ebx, TOP_Y
    xor edx, edx
    cmp dword [stock_n], 0
    je .st
    mov dl, 1                   ; any card, face down
.st:
    call gg_card
    add eax, COL_DX
    xor edx, edx
    mov ecx, [waste_n]
    jecxz .w
    mov dl, [waste+ecx-1]
    mov dh, 1
.w: call gg_card
    ; foundations
    xor ecx, ecx
.f: lea eax, [ecx+3]
    imul eax, COL_DX
    add eax, 4
    xor edx, edx
    mov dl, [found+ecx]
    test dl, dl
    jz .fe
    mov dh, cl
    shl dh, 4
    or dl, dh
    mov dh, 1
.fe:
    call gg_card
    test dl, dl
    jnz .fn
    push edx
    mov dl, cl                  ; the suit sign in an empty foundation
    add eax, CARD_W / 2 - 3
    add ebx, CARD_H / 2 - 3
    call gg_suit
    sub eax, CARD_W / 2 - 3
    sub ebx, CARD_H / 2 - 3
    pop edx
.fn:
    inc ecx
    cmp ecx, 4
    jb .f
    ; columns: face-down cards close together, face-up ones further apart
    xor ecx, ecx
.c: call gstep
    mov [gstepv], edx
    mov esi, ecx
    imul esi, COL_DX
    add esi, 4                  ; x
    call colptr                 ; edi = cards, eax = count
    test eax, eax
    jnz .cards
    mov eax, esi
    mov ebx, COL_Y
    xor edx, edx
    call gg_card
    jmp .cn
.cards:
    xor ebp, ebp                ; card index
.k: movzx edx, byte [edi+ebp]   ; dh = 0: face down
    movzx ebx, byte [tab_down+ecx]
    cmp ebp, ebx
    jae .up
    imul ebx, ebp, DOWN_DY
    jmp .y
.up:
    mov eax, ebp
    sub eax, ebx
    imul eax, [gstepv]
    imul ebx, DOWN_DY
    add ebx, eax
    mov dh, 1
.y: add ebx, COL_Y
    mov eax, esi
    call gg_card
    inc ebp
    movzx eax, byte [tab_n+ecx]
    cmp ebp, eax
    jb .k
.cn:
    inc ecx
    cmp ecx, NCOL
    jb .c
    ; a yellow frame round what is held, a white one round the cursor
    mov eax, [held]
    cmp eax, -1
    je .nh
    call grect
    call gg_frame
.nh:
    mov eax, [cursor]
    call grect
    mov byte [gui_ink], C_WHITE
    sub eax, 3
    sub ebx, 3
    add ecx, 6
    add edx, 6
    call gui_box
    mov esi, [gmsg]
    call won
    test eax, eax
    jz .s
    mov esi, m_g_won
.s: call gg_status
    popad
    ret
; ---------- self-test ----------

; ecx = column, esi = cards (0-terminated), edx = how many are face down
setcol:
    pushad
    call colptr
    xor eax, eax
.l: mov bl, [esi]
    test bl, bl
    jz .d
    mov [edi+eax], bl
    inc esi
    inc eax
    jmp .l
.d: mov [tab_n+ecx], al
    mov [tab_down+ecx], dl
    popad
    ret

%macro EXPECT 1                 ; eax against a constant
    mov ebx, %1
    call g_expect
%endmacro
%macro MOVE 2                   ; source, destination -> eax
    mov ebx, %1
    mov ecx, %2
    call domove
%endmacro
%macro COL 3                    ; column, cards, face-down count
    mov ecx, %1
    mov esi, %2
    mov edx, %3
    call setcol
%endmacro

selftest:
    ; 1. a seeded deal: 1..7 cards, 0..6 face down, 24 in the stock,
    ;    and all 52 cards present once
    mov eax, 21
    call g_srand
    call deal
    xor ecx, ecx
    xor edx, edx
.sz:
    movzx eax, byte [tab_n+ecx]
    add edx, eax
    movzx eax, byte [tab_down+ecx]
    inc eax
    cmp al, [tab_n+ecx]
    jne .szbad
    inc ecx
    cmp ecx, NCOL
    jb .sz
.szbad:
    mov eax, ecx
    EXPECT NCOL                 ; 1
    mov eax, edx
    EXPECT 28                   ; 2
    mov eax, [stock_n]
    EXPECT 24                   ; 3
    call all_cards
    EXPECT 52                   ; 4
    call deal_hash
    mov [hash1], eax
    mov eax, 21
    call g_srand
    call deal
    call deal_hash
    EXPECT [hash1]              ; 5: the same seed deals the same
    mov eax, 22
    call g_srand
    call deal
    call deal_hash
    cmp eax, [hash1]
    setne al
    movzx eax, al
    EXPECT 1                    ; 6: another seed deals another
    ; 2. moves between columns
    call clear
    COL 0, t_8s, 0
    COL 1, t_7h, 0
    MOVE 1, 0
    EXPECT 1                    ; 7: 7H on 8S
    movzx eax, byte [tab_n+0]
    EXPECT 2                    ; 8
    COL 2, t_7d, 0
    MOVE 2, 0
    EXPECT 0                    ; 9: 7D on 7H refused
    COL 3, t_9h6c, 1
    MOVE 3, 0
    EXPECT 1                    ; 10: 6C on 7H
    movzx eax, byte [tab_down+3]
    EXPECT 0                    ; 11: the 9H turned up
    COL 4, t_9d, 0
    MOVE 0, 4
    EXPECT 1                    ; 12: 8S 7H 6C onto 9D as a run
    movzx eax, byte [tab_n+4]
    EXPECT 4                    ; 13
    movzx eax, byte [tab_n+0]
    EXPECT 0                    ; 14
    COL 5, t_qd, 0
    MOVE 5, 0
    EXPECT 0                    ; 15: only a king on an empty column
    COL 6, t_kc, 0
    MOVE 6, 0
    EXPECT 1                    ; 16
    ; 3. foundations
    mov byte [waste], C_AH
    mov dword [waste_n], 1
    MOVE SRC_W, DST_F
    EXPECT 1                    ; 17: AH up
    COL 5, t_2h, 0
    MOVE 5, DST_F
    EXPECT 1                    ; 18: 2H on AH
    COL 5, t_3s, 0
    MOVE 5, DST_F
    EXPECT 0                    ; 19: 3S has no 2S under it
    movzx eax, byte [found+2]
    EXPECT 2                    ; 20
    ; 4. the stock: three draws, then turning the waste over keeps order
    call clear
    mov dword [stock], C_AH | (C_2H << 8) | (C_3S << 16)
    mov dword [stock_n], 3
    call drawcard
    call drawcard
    call drawcard
    mov eax, [waste_n]
    EXPECT 3                    ; 21
    movzx eax, byte [waste+0]
    EXPECT C_3S                 ; 22: the stock is drawn from its top
    call drawcard               ; empty stock: turn the waste over
    mov eax, [stock_n]
    EXPECT 3                    ; 23
    call drawcard
    movzx eax, byte [waste+0]
    EXPECT C_3S                 ; 24: the same card comes first again
    ; 5. auto-move finishes a game
    call clear
    mov dword [found], 0x0C0D0D0D   ; spades at the queen
    COL 2, t_ks, 0
    call won
    EXPECT 0                    ; 25
    call automove
    call won
    EXPECT 1                    ; 26
    ; 6. the move parser
    mov esi, t_m35
    call parsemove
    mov eax, ebx
    shl eax, 4
    or eax, ecx
    EXPECT 0x24                 ; 27: "m 3 5" = column 2 to column 4
    mov esi, t_wf
    call parsemove
    mov eax, ebx
    shl eax, 4
    or eax, ecx
    EXPECT 0x78                 ; 28: "w f"
    mov esi, t_bad
    call parsemove
    setc al
    movzx eax, al
    EXPECT 1                    ; 29: "9f" is not a column
    call g_report
    ret

all_cards:                      ; -> eax = number of different cards dealt
    pushad
    mov edi, seen
    mov ecx, 64
    xor eax, eax
    rep stosb
    xor ecx, ecx
.c: push ecx
    call colptr
    mov ecx, eax
.k: jecxz .kn
    movzx ebx, byte [edi+ecx-1]
    mov byte [seen+ebx], 1
    dec ecx
    jmp .k
.kn:
    pop ecx
    inc ecx
    cmp ecx, NCOL
    jb .c
    mov ecx, [stock_n]
.s: jecxz .sn
    movzx ebx, byte [stock+ecx-1]
    mov byte [seen+ebx], 1
    dec ecx
    jmp .s
.sn:
    xor eax, eax
    mov ecx, 64
.cnt:
    movzx ebx, byte [seen+ecx-1]
    add eax, ebx
    loop .cnt
    mov [esp+28], eax
    popad
    ret

deal_hash:                      ; -> eax = hash of the columns and stock
    push ecx
    push edx
    xor eax, eax
    mov ecx, tab
.l: movzx edx, byte [ecx]
    imul eax, 33
    add eax, edx
    inc ecx
    cmp ecx, stock+24
    jb .l
    pop edx
    pop ecx
    ret

C_AH equ 0x21
C_2H equ 0x22
C_3S equ 0x33
t_8s db 0x38, 0
t_7h db 0x27, 0
t_7d db 0x17, 0
t_9h6c db 0x29, 0x06, 0
t_9d db 0x19, 0
t_qd db 0x1C, 0
t_kc db 0x0D, 0
t_2h db 0x22, 0
t_3s db 0x33, 0
t_ks db 0x3D, 0
t_m35 db 'm 3 5', 0
t_wf db 'w f', 0
t_bad db '9f', 0

m_name db 'klondike', 0
m_title db 'Squirrel Klondike - build the four suits up from the aces', 10
        db 'd draws, 35 moves column 3 to 5, w4 or 3f moves from the waste or', 10
        db 'to the foundations, a moves all it can up, n new deal, q quits', 10, 0
m_stock db 'Stock ', 0
m_waste db '   Waste', 0
m_found db '   Foundations (C D H S)', 0
m_cols db '    1    2    3    4    5    6    7', 10, 0
m_gap db '  ', 0
m_prompt db 'klondike> ', 0
m_help db 'Type d, a, a move like 35 / w4 / 3f, n or q', 10, 0
m_refused db 'That move is not allowed', 10, 0
m_nogui db 'klondike: no graphics screen', 10, 0
m_g_help db 'Click or arrows+Enter. d draw a auto n new q quit', 0
m_refused_g db 'That move is not allowed', 0
m_g_won db 'All four suits are home - you win! n: new deal', 0
m_won db 'All four suits are home - you win! n for a new deal, q to quit', 10, 0
w_draw db 'd', 0
w_auto db 'a', 0
w_move db 'm', 0

SQX_BSS
G_BSS
mv_src resd 1
mv_dst resd 1
dst_ptr resd 1
dst_n resd 1
src_n resd 1
hash1 resd 1
deck resb 52
seen resb 64
alignb 4
; the game state (cleared by clear, from tab to state_end)
tab resb NCOL*CSTR
stock resb 24
waste resb 24
alignb 4
stock_n resd 1
waste_n resd 1
tab_n resb 8
tab_down resb 8
found resb 4
state_end:
alignb 4
cursor resd 1
held resd 1
gmsg resd 1
gstepv resd 1
GUI_BSS
GG_BSS
SQX_END
