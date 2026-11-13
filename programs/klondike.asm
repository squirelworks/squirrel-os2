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
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"

NCOL  equ 7
CSTR  equ 24                    ; bytes per column (6 down + 13 up fit)
SRC_W equ 7                     ; source index for the waste
DST_F equ 8                     ; destination index for the foundations

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
SQX_END
