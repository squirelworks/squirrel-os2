; freecell — FreeCell solitaire (G.2). Original code.
;
;   run freecell [seed]    play a seeded deal (all cards face up)
;   run freecell test      rules self-check, prints "freecell: PASS"
;
; Columns are 1-8, the free cells a-d, f the foundations.
;   35       move from column 3 to column 5 (the longest run that fits,
;            as long as the free cells and empty columns allow it)
;   3a       column 3 to free cell a
;   a5  bf   free cell a to column 5, free cell b to the foundations
;   3f       column 3 to the foundations
;   auto     move every card that can go to the foundations
;   n        new deal            q   quit
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"

NCOL  equ 8
CSTR  equ 24
NCELL equ 4
; places: 0-7 columns, 8-11 free cells, 12 any free cell, 13 foundations
P_CELL equ 8
P_ANY  equ 12
P_F    equ 13

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
    mov edi, w_auto
    call g_word
    jnc .auto
    call parsemove
    jc .bad
    call domove
    test eax, eax
    jz .refused
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

; A seeded deal, dealt across: columns 1-4 get 7 cards, 5-8 get 6.
deal:
    pushad
    call clear
    mov edi, deck
    call c_newdeck
    mov ecx, 52
    call g_shuffle
    xor esi, esi
.card:
    mov eax, esi
    xor edx, edx
    mov ecx, NCOL
    div ecx                     ; eax = row, edx = column
    imul ecx, edx, CSTR
    add ecx, eax
    mov bl, [deck+esi]
    mov [tab+ecx], bl
    inc byte [tab_n+edx]
    inc esi
    cmp esi, 52
    jb .card
    popad
    ret

; ecx = column -> edi = its cards, eax = how many
colptr:
    mov edi, ecx
    imul edi, CSTR
    add edi, tab
    movzx eax, byte [tab_n+ecx]
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

; ecx = destination column (or -1) -> eax = how many cards one move may
; carry: (free cells + 1) * 2 ^ (empty columns other than the destination)
capacity:
    push ebx
    push edx
    mov eax, 1
    xor ebx, ebx
.c: cmp byte [cell+ebx], 0
    jne .cn
    inc eax
.cn:
    inc ebx
    cmp ebx, NCELL
    jb .c
    xor ebx, ebx
.e: cmp byte [tab_n+ebx], 0
    jne .en
    cmp ebx, ecx
    je .en
    shl eax, 1
.en:
    inc ebx
    cmp ebx, NCOL
    jb .e
    pop edx
    pop ebx
    ret

; ecx = column -> eax = length of the ordered run on its top
; (each card one lower than, and the other colour from, the card under it)
runlen:
    push ecx
    push edx
    push edi
    push esi
    call colptr
    mov esi, eax
    test esi, esi
    jz .zero
    mov ecx, 1
.l: cmp ecx, esi
    jae .done
    mov edx, esi
    sub edx, ecx
    mov al, [edi+edx]           ; the card on top of...
    mov dl, [edi+edx-1]         ; ...this one
    call c_stacks
    jc .done
    inc ecx
    jmp .l
.done:
    mov eax, ecx
    jmp .r
.zero:
    xor eax, eax
.r: pop esi
    pop edi
    pop edx
    pop ecx
    ret

; Takes the top card off a place: ebx = column or cell -> al = card
takecard:
    cmp ebx, P_CELL
    jae .cell
    push ecx
    push edi
    mov ecx, ebx
    call colptr
    mov al, [edi+eax-1]
    dec byte [tab_n+ecx]
    pop edi
    pop ecx
    ret
.cell:
    mov al, [cell+ebx-P_CELL]
    mov byte [cell+ebx-P_CELL], 0
    ret

; ebx = place -> al = its top card (0 if none)
topcard:
    cmp ebx, P_CELL
    jae .cell
    push ecx
    push edi
    mov ecx, ebx
    call colptr
    test eax, eax
    jz .none
    mov al, [edi+eax-1]
.none:
    pop edi
    pop ecx
    ret
.cell:
    mov al, [cell+ebx-P_CELL]
    ret

; ebx = source place, ecx = destination place -> eax = 1 if moved, 0 if not
domove:
    pushad
    cmp ebx, P_ANY
    jae .no
    call topcard
    test al, al
    jz .no
    cmp ecx, P_F
    je .found
    cmp ecx, P_ANY
    je .anycell
    cmp ecx, P_CELL
    jae .tocell
    cmp ebx, ecx
    je .no
    ; to a column
    push eax
    push ecx
    call colptr
    xor edx, edx
    test eax, eax
    jz .empty
    mov dl, [edi+eax-1]
.empty:
    pop ecx
    pop eax
    cmp ebx, P_CELL
    jb .run
    ; one card from a cell
    test dl, dl
    jz .put1
    call c_stacks
    jc .no
.put1:
    call takecard
    call putcol
    jmp .yes
.run:
    ; the longest part of the source's run that fits and is not too big
    xchg ebx, ecx
    call runlen                 ; ecx = source here
    xchg ebx, ecx
    mov esi, eax                ; run length
    call capacity               ; ecx = destination
    cmp esi, eax
    jbe .capok
    test dl, dl
    jnz .capok                  ; a non-empty target needs one exact length
    mov esi, eax                ; an empty one takes as many as fit
.capok:
    mov [cap], eax
    ; k = cards to move, from esi down to 1
.k: test esi, esi
    jz .no
    push ecx
    push edi
    mov ecx, ebx
    call colptr
    sub eax, esi
    mov al, [edi+eax]           ; the bottom card of the k-card run
    pop edi
    pop ecx
    test dl, dl
    jz .kfit                    ; empty column: anything
    call c_stacks
    jnc .kfit
    dec esi
    jmp .k
.kfit:
    cmp esi, [cap]
    ja .no
    ; move esi cards from column ebx to column ecx, in order
    push ecx
    mov ecx, ebx
    call colptr
    sub eax, esi
    lea edx, [edi+eax]          ; first card moved
    sub [tab_n+ecx], esi
    pop ecx
    push esi
.mv:
    mov al, [edx]
    inc edx
    call putcol
    dec esi
    jnz .mv
    pop esi
    jmp .yes
.anycell:
    mov ecx, P_CELL
.ac:
    cmp byte [cell+ecx-P_CELL], 0
    je .tocell
    inc ecx
    cmp ecx, P_ANY
    jb .ac
    jmp .no
.tocell:
    cmp byte [cell+ecx-P_CELL], 0
    jne .no
    call takecard
    mov [cell+ecx-P_CELL], al
    jmp .yes
.found:
    call tofound
    jc .no
    call takecard
.yes:
    mov dword [esp+28], 1
    popad
    ret
.no:
    mov dword [esp+28], 0
    popad
    ret

; al = card, ecx = column: puts it on top
putcol:
    push eax
    push edi
    push eax
    call colptr
    add edi, eax
    pop eax
    mov [edi], al
    inc byte [tab_n+ecx]
    pop edi
    pop eax
    ret

; Moves every card it can to the foundations, until none moves
automove:
    pushad
.again:
    xor ebp, ebp
    mov ebx, P_ANY-1
.src:
    mov ecx, P_F
    call domove
    or ebp, eax
    dec ebx
    jns .src
    test ebp, ebp
    jnz .again
    popad
    ret

won:
    xor eax, eax
    cmp dword [found], 0x0D0D0D0D
    jne .r
    inc eax
.r: ret

; esi = text -> ebx = source place, ecx = destination, CF set if not a move
parsemove:
    push eax
    push esi
    push edi
    mov edi, w_move
    call g_word
    call g_skipsp
    lodsb
    call .place
    jc .bad
    cmp ebx, P_ANY
    jae .bad                    ; f is not a source
    mov ecx, ebx
    call g_skipsp
    lodsb
    push ecx
    call .place
    mov ecx, ebx
    pop ebx
    jc .bad
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
.place:                         ; al = character -> ebx = place, CF if none
    movzx ebx, al
    sub ebx, '1'
    cmp ebx, NCOL
    jb .ok
    movzx ebx, al
    sub ebx, 'a'
    cmp ebx, NCELL
    jae .cf
    add ebx, P_CELL
    jmp .ok
.cf:
    mov ebx, P_F
    cmp al, 'f'
    je .ok
    stc
    ret
.ok:
    clc
    ret

; ---------- screen ----------

draw:
    pushad
    call g_nl
    mov esi, m_cells
    call g_puts
    xor ebx, ebx
.c: mov al, [cell+ebx]
    call c_print
    inc ebx
    cmp ebx, NCELL
    jb .c
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
    xor ebx, ebx
.row:
    cmp ebx, edx
    jae .done
    xor ecx, ecx
.cell:
    mov esi, m_gap
    call g_puts
    cmp bl, [tab_n+ecx]
    jae .blank
    push ecx
    call colptr
    mov al, [edi+ebx]
    call c_print
    pop ecx
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

; ecx = column, esi = cards (0-terminated)
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
    popad
    ret

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%macro MOVE 2
    mov ebx, %1
    mov ecx, %2
    call domove
%endmacro
%macro COL 2
    mov ecx, %1
    mov esi, %2
    call setcol
%endmacro
%macro FILLCOLS 0               ; columns 3-8 hold one card each
    mov ecx, 2
%%l: mov byte [tab_n+ecx], 1
    imul eax, ecx, CSTR
    mov byte [tab+eax], 0x2D
    inc ecx
    cmp ecx, NCOL
    jb %%l
%endmacro
%macro FILLCELLS 0              ; four occupied cells
    mov dword [cell], 0x3B3B3B3B
%endmacro

selftest:
    ; 1. a seeded deal: 7,7,7,7,6,6,6,6 and every card once
    mov eax, 5
    call g_srand
    call deal
    xor eax, eax
    xor ecx, ecx
.sz:
    shl eax, 4
    or al, [tab_n+ecx]
    inc ecx
    cmp ecx, NCOL
    jb .sz
    EXPECT 0x77776666           ; 1
    call all_cards
    EXPECT 52                   ; 2
    ; 2. free cells
    call clear
    COL 0, t_9h8s
    MOVE 0, P_ANY
    EXPECT 1                    ; 3: 8S to a free cell
    movzx eax, byte [cell]
    EXPECT 0x38                 ; 4: the first free one, a
    MOVE 0, P_CELL
    EXPECT 0                    ; 5: cell a is taken
    COL 1, t_9d
    MOVE P_CELL, 1
    EXPECT 1                    ; 6: 8S from a onto 9D
    COL 2, t_8c
    MOVE 2, P_CELL+1
    MOVE P_CELL+1, 0
    EXPECT 1                    ; 7: 8C from cell b onto 9H
    ; 3. runs and capacity
    call clear
    FILLCELLS
    FILLCOLS
    COL 0, t_run                ; 10D 9C 8H
    COL 1, t_jc
    MOVE 0, 1
    EXPECT 0                    ; 8: three cards, room for one
    mov byte [cell], 0          ; one free cell: room for two
    mov byte [cell+1], 0        ; two free cells: room for three
    MOVE 0, 1
    EXPECT 1                    ; 9: the whole run onto JC
    movzx eax, byte [tab_n+1]
    EXPECT 4                    ; 10
    ; an empty column doubles the room; moving onto one takes what fits
    call clear
    FILLCELLS
    COL 0, t_run
    COL 1, t_kc                 ; columns 3-8 empty
    mov ecx, -1
    call capacity
    EXPECT 64                   ; 11: 1 * 2^6 (columns 3-8 empty)
    MOVE 0, 2
    EXPECT 1                    ; 12
    movzx eax, byte [tab_n+2]
    EXPECT 3                    ; 13: the run went over whole
    ; 4. refusals: same colour, wrong rank
    call clear
    COL 0, t_9h8s
    COL 1, t_7c
    MOVE 1, 0
    EXPECT 0                    ; 14: 7C on 8S
    COL 1, t_7d
    MOVE 1, 0
    EXPECT 1                    ; 15: 7D on 8S
    COL 2, t_5h
    MOVE 2, 0
    EXPECT 0                    ; 16: 5H on 7D
    ; 5. foundations and auto
    call clear
    mov dword [found], 0x0D0D0D0C
    mov byte [cell+3], 0x0D     ; KC in cell d
    call won
    EXPECT 0                    ; 17
    call automove
    call won
    EXPECT 1                    ; 18
    ; 6. the parser
    mov esi, t_p1
    call parsemove
    mov eax, ebx
    shl eax, 4
    or eax, ecx
    EXPECT 0x2A                 ; 19: "3c" = column 2 to cell c
    mov esi, t_p2
    call parsemove
    mov eax, ebx
    shl eax, 4
    or eax, ecx
    EXPECT 0x9D                 ; 20: "bf" = cell b to the foundations
    mov esi, t_p3
    call parsemove
    setc al
    movzx eax, al
    EXPECT 1                    ; 21: "f3" is not a move
    call g_report
    ret

all_cards:
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
    xor eax, eax
    mov ecx, 64
.cnt:
    movzx ebx, byte [seen+ecx-1]
    add eax, ebx
    loop .cnt
    mov [esp+28], eax
    popad
    ret

t_9h8s db 0x29, 0x38, 0
t_9d db 0x19, 0
t_8c db 0x08, 0
t_run db 0x1A, 0x09, 0x28, 0
t_jc db 0x0B, 0
t_kc db 0x0D, 0
t_7c db 0x07, 0
t_7d db 0x17, 0
t_5h db 0x25, 0
t_p1 db '3c', 0
t_p2 db 'bf', 0
t_p3 db 'f3', 0

m_name db 'freecell', 0
m_title db 'Squirrel FreeCell - build the four suits up from the aces', 10
        db '35 moves column 3 to 5, 3a to free cell a, a5 back, 3f / af up,', 10
        db 'auto moves all it can up, n new deal, q quits', 10, 0
m_cells db 'Cells (a b c d)', 0
m_found db '   Foundations (C D H S)', 0
m_cols db '    1    2    3    4    5    6    7    8', 10, 0
m_gap db '  ', 0
m_prompt db 'freecell> ', 0
m_help db 'Type a move like 35, 3a, a5, 3f, af, or auto, n, q', 10, 0
m_refused db 'That move is not allowed', 10, 0
m_won db 'All four suits are home - you win! n for a new deal, q to quit', 10, 0
w_auto db 'auto', 0
w_move db 'm', 0

SQX_BSS
G_BSS
cap resd 1
deck resb 52
seen resb 64
alignb 4
tab resb NCOL*CSTR
alignb 4
tab_n resb NCOL
cell resb NCELL
found resb 4
state_end:
SQX_END
