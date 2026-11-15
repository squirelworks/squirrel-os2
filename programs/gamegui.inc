; Squirrel-OS/2 — drawing shared by the games' graphical front ends. Original code.
;
; Include after gui.inc (and cards.inc for the card routines). Every
; routine keeps all registers. Card art, suit signs, the green table, the
; status bar and the selection frame are original.
;
;   gg_table            the green table and an empty status bar
;   gg_status  esi      status text in the bar at the bottom (read by <gfx>)
;   gg_title   esi      a title on the table's top line
;   gg_card    eax, ebx = x, y; dl = card (0 = empty slot), dh = 1 face up
;   gg_suit    eax, ebx = x, y; dl = suit 0-3: a 7 x 7 sign in its colour
;   gg_frame   eax, ebx, ecx, edx = a rectangle: a yellow selection frame
;   gg_hit     eax, ebx = point; esi = rect (x, y, w, h dwords) -> CF clear inside
;   gg_textc   esi, eax = x, ebx = y, cl = ink: text on the table (no box)
;   gg_column  eax, ebx = x, y; esi = cards, ecx = count, edi = face down,
;              edx = step between face-up cards: a fanned column
;   gg_step    eax = room in pixels, ecx = steps -> edx = step (at most 10)
;   gg_cursor  eax, ebx, ecx, edx = a rectangle: a white keyboard cursor
;   gg_glyph2  eax, ebx = x, y; esi = 7 rows (bit 6 = left), cl = colour:
;              the 7 x 7 sign at twice its size
;   gg_disc    eax, ebx = centre, cl = colour: a disc 19 pixels across
;   gg_sb_start edi = buffer (GG_SBMAX bytes): later gg_sb_* calls append
;   gg_sb_str  esi    gg_sb_num  eax    gg_sb_card  al: text, a number, a card

CARD_W      equ 32
CARD_H      equ 44
STATUS_Y    equ SCR_H - CELL_H - 2
C_TABLE     equ C_GREEN

gg_table:
    push eax
    mov al, C_TABLE
    call gui_clear
    pop eax
    jmp gg_status_clear

gg_status_clear:
    pushad
    xor eax, eax
    mov ebx, STATUS_Y
    mov ecx, SCR_W
    mov edx, SCR_H - STATUS_Y
    mov byte [gui_ink], C_LGREY
    call gui_fill
    popad
    ret

; esi = text: the status bar
gg_status:
    pushad
    call gg_status_clear
    mov eax, 4
    mov ebx, STATUS_Y + 1
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    popad
    ret

; esi = text, eax = x, ebx = y, cl = ink: text straight on the table
gg_textc:
    pushad
    mov [gui_ink], cl
    mov byte [gui_bg], C_TABLE
    call gui_text
    popad
    ret

; esi = title: centred on the top line of the table
gg_title:
    pushad
    call gui_textw
    mov ecx, SCR_W
    sub ecx, eax
    shr ecx, 1
    mov eax, ecx
    mov ebx, 1
    mov cl, C_WHITE
    call gg_textc
    popad
    ret

; eax = x, ebx = y, dl = suit: its sign, 7 x 7, red or black
gg_suit:
    pushad
    movzx esi, dl
    and esi, 3
    mov cl, C_BLACK
    cmp esi, 1
    je .red
    cmp esi, 2
    jne .k
.red:
    mov cl, C_RED
.k: lea esi, [gg_suits+esi*8]
    mov [gg_ox], eax
    xor edx, edx                ; row
.row:
    movzx ebp, byte [esi+edx]
    xor edi, edi                ; column
.col:
    test ebp, 0x40
    jz .n
    mov eax, [gg_ox]
    add eax, edi
    push ebx
    add ebx, edx
    call gui_pset
    pop ebx
.n: shl ebp, 1
    inc edi
    cmp edi, 7
    jb .col
    inc edx
    cmp edx, 7
    jb .row
    popad
    ret

; eax = x, ebx = y, dl = card, dh = 1 face up / 0 face down.
; A card of CARD_W x CARD_H with cut corners; dl = 0 draws an empty slot.
gg_card:
    pushad
    test dl, dl
    jz .slot
    ; the white (or blue) body, corners cut
    push edx
    mov byte [gui_ink], C_BLACK
    inc eax
    mov ecx, CARD_W - 2
    mov edx, 1
    call gui_fill               ; top edge
    add ebx, CARD_H - 1
    call gui_fill               ; bottom edge
    sub ebx, CARD_H - 1
    dec eax
    inc ebx
    mov ecx, 1
    mov edx, CARD_H - 2
    call gui_fill               ; left edge
    add eax, CARD_W - 1
    call gui_fill               ; right edge
    sub eax, CARD_W - 2
    mov ecx, CARD_W - 2
    pop edx
    push edx
    mov byte [gui_ink], C_WHITE
    test dh, dh
    jnz .face
    mov byte [gui_ink], C_BLUE
.face:
    push edx
    mov edx, CARD_H - 2
    call gui_fill
    pop edx
    pop edx
    test dh, dh
    jz .back
    ; rank in the top left corner, the suit sign beside it, and a large
    ; sign in the middle
    dec ebx
    push eax
    push ebx
    add ebx, 2
    inc eax
    movzx esi, dl
    and esi, CARD_RANK
    lea esi, [gg_ranks+esi*4]
    mov byte [gui_bg], C_WHITE
    mov byte [gui_ink], C_BLACK
    mov cl, dl
    and cl, CARD_SUIT
    cmp cl, 0x10
    je .redt
    cmp cl, 0x20
    jne .bt
.redt:
    mov byte [gui_ink], C_RED
.bt:
    call gui_text
    push eax
    call gui_textw
    mov ecx, eax
    pop eax
    add eax, ecx
    push edx
    shr dl, 4
    call gg_suit
    pop edx
    pop ebx
    pop eax
    ; the big sign: the 7 x 7 sign at twice its size
    add eax, CARD_W / 2 - 7
    add ebx, CARD_H / 2 - 5
    shr dl, 4
    call gg_suit2
    jmp .r
.back:
    ; a lattice on the back
    mov byte [gui_ink], C_LBLUE
    add eax, 3
    add ebx, 2
    mov ecx, CARD_W - 8
    mov edx, CARD_H - 6
    call gui_box
    mov ebp, 6
.lat:
    push eax
    push ebx
    add eax, 2
    add ebx, ebp
    mov ecx, CARD_W - 12
    mov edx, 1
    call gui_fill
    pop ebx
    pop eax
    add ebp, 6
    cmp ebp, CARD_H - 8
    jb .lat
    jmp .r
.slot:
    mov byte [gui_ink], C_LGREEN
    mov ecx, CARD_W
    mov edx, CARD_H
    call gui_box
.r: popad
    ret

; eax = x, ebx = y, dl = suit: the sign doubled to 14 x 14
gg_suit2:
    pushad
    movzx esi, dl
    and esi, 3
    mov cl, C_BLACK
    cmp esi, 1
    je .red
    cmp esi, 2
    jne .k
.red:
    mov cl, C_RED
.k: lea esi, [gg_suits+esi*8]
    call gg_glyph2
    popad
    ret

; eax = x, ebx = y, esi = 7 rows of 7 bits (bit 6 = left), cl = colour:
; the sign at twice its size, 14 x 14
gg_glyph2:
    pushad
    mov [gg_ox], eax
    xor edx, edx
.row:
    movzx ebp, byte [esi+edx]
    xor edi, edi                ; column
.col:
    test ebp, 0x40
    jz .n
    lea eax, [edi*2]
    add eax, [gg_ox]
    push ebx
    lea ebx, [ebx+edx*2]
    call gui_pset
    inc eax
    call gui_pset
    inc ebx
    call gui_pset
    dec eax
    call gui_pset
    pop ebx
.n: shl ebp, 1
    inc edi
    cmp edi, 7
    jb .col
    inc edx
    cmp edx, 7
    jb .row
    popad
    ret

; eax, ebx, ecx, edx = rectangle: a two-pixel yellow frame round it
gg_frame:
    pushad
    mov byte [gui_ink], C_YELLOW
    dec eax
    dec ebx
    add ecx, 2
    add edx, 2
    call gui_box
    dec eax
    dec ebx
    add ecx, 2
    add edx, 2
    call gui_box
    popad
    ret

; eax = x, ebx = y, esi = cards, ecx = count, edi = how many of them are
; face down (each 4 pixels below the last), edx = the step after a face-up
; card. An empty column is drawn as an empty slot.
gg_column:
    pushad
    test ecx, ecx
    jnz .cards
    xor edx, edx
    call gg_card
    jmp .r
.cards:
    mov ebp, edx
.k: push edx
    movzx edx, byte [esi]       ; dh = 0: face down
    test edi, edi
    jz .up
    call gg_card
    pop edx
    dec edi
    add ebx, 4
    jmp .n
.up:
    mov dh, 1
    call gg_card
    pop edx
    add ebx, ebp
.n: inc esi
    dec ecx
    jnz .k
.r: popad
    ret

; eax = room in pixels, ecx = steps -> edx = the step, at most 10
gg_step:
    mov edx, 10
    cmp ecx, 0
    jle .r
    push eax
    push ecx
    xor edx, edx
    div ecx
    pop ecx
    mov edx, eax
    pop eax
    cmp edx, 10
    jbe .r
    mov edx, 10
.r: ret

; eax, ebx, ecx, edx = rectangle: a white frame three pixels round it
gg_cursor:
    pushad
    mov byte [gui_ink], C_WHITE
    sub eax, 3
    sub ebx, 3
    add ecx, 6
    add edx, 6
    call gui_box
    popad
    ret

; eax, ebx = point, esi = rectangle (x, y, w, h) -> CF clear if inside
gg_hit:
    push ecx
    mov ecx, eax
    sub ecx, [esi]
    jl .no
    cmp ecx, [esi+8]
    jge .no
    mov ecx, ebx
    sub ecx, [esi+4]
    jl .no
    cmp ecx, [esi+12]
    jge .no
    pop ecx
    clc
    ret
.no:
    pop ecx
    stc
    ret

; eax, ebx = centre, cl = colour: a filled disc, 19 pixels across, with a
; dark grey rim
gg_disc:
    pushad
    mov [gg_ox], eax
    mov esi, -9                 ; row
.row:
    mov edx, esi
    test edx, edx
    jns .p
    neg edx
.p: movzx edx, byte [gg_discw+edx]   ; half width of this row
    mov eax, [gg_ox]
    sub eax, edx
    push ebx
    add ebx, esi
    lea ecx, [edx*2+1]
    push edx
    mov edx, 1
    mov byte [gui_ink], C_DGREY
    call gui_fill               ; the rim: the whole disc in grey
    pop edx
    pop ebx
    inc esi
    cmp esi, 9
    jle .row
    ; the inside: the same rows one pixel narrower, in the colour
    mov esi, -8
.in:
    mov edx, esi
    test edx, edx
    jns .q
    neg edx
.q: movzx edx, byte [gg_discw+edx]
    dec edx
    mov eax, [gg_ox]
    sub eax, edx
    push ebx
    add ebx, esi
    lea ecx, [edx*2+1]
    mov dl, [esp+4+24]          ; the colour: cl of pushad's ecx
    mov [gui_ink], dl
    mov edx, 1
    call gui_fill
    pop ebx
    inc esi
    cmp esi, 8
    jle .in
    popad
    ret

; ---------- building a line of text (status bars, titles) ----------

GG_SBMAX equ 64

; edi = buffer: empties it; the gg_sb_* calls below append to it
gg_sb_start:
    mov [gg_sbp], edi
    mov [gg_sbe], edi
    add dword [gg_sbe], GG_SBMAX - 1
    mov byte [edi], 0
    ret

; al = character
gg_sb_chr:
    push edi
    mov edi, [gg_sbp]
    cmp edi, [gg_sbe]
    jae .r
    mov [edi], al
    mov byte [edi+1], 0
    inc dword [gg_sbp]
.r: pop edi
    ret

; esi = ASCIIZ text
gg_sb_str:
    push eax
    push esi
.l: lodsb
    test al, al
    jz .r
    call gg_sb_chr
    jmp .l
.r: pop esi
    pop eax
    ret

; eax = unsigned number
gg_sb_num:
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
    call gg_sb_chr
    loop .p
    popad
    ret

; al = card: like "QS" or "10H"
gg_sb_card:
    pushad
    movzx ebx, al
    and ebx, CARD_RANK
    cmp ebx, 10
    jne .one
    mov al, '1'
    call gg_sb_chr
    mov al, '0'
    jmp .s
.one:
    mov al, [c_ranks+ebx]
.s: call gg_sb_chr
    movzx ebx, byte [esp+28]    ; the card (saved eax)
    shr ebx, 4
    and ebx, 3
    mov al, [c_suits+ebx]
    call gg_sb_chr
    popad
    ret

; half widths of the rows of gg_disc, from the middle out
gg_discw db 9, 9, 9, 9, 8, 8, 7, 6, 5, 3

; suit signs, 7 x 7, bit 6 = left column: clubs, diamonds, hearts, spades
gg_suits:
    db 0x1C, 0x1C, 0x6B, 0x7F, 0x6B, 0x08, 0x1C, 0
    db 0x08, 0x1C, 0x3E, 0x7F, 0x3E, 0x1C, 0x08, 0
    db 0x36, 0x7F, 0x7F, 0x7F, 0x3E, 0x1C, 0x08, 0
    db 0x08, 0x1C, 0x3E, 0x7F, 0x7F, 0x2A, 0x1C, 0
gg_ranks:
    db '?', 0, 0, 0,  'A', 0, 0, 0,  '2', 0, 0, 0,  '3', 0, 0, 0
    db '4', 0, 0, 0,  '5', 0, 0, 0,  '6', 0, 0, 0,  '7', 0, 0, 0
    db '8', 0, 0, 0,  '9', 0, 0, 0,  '10', 0, 0,    'J', 0, 0, 0
    db 'Q', 0, 0, 0,  'K', 0, 0, 0

%macro GG_BSS 0
gg_ox       resd 1
gg_sbp      resd 1
gg_sbe      resd 1
%endmacro
