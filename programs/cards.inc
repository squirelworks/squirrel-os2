; Squirrel-OS/2 — playing cards for the card games (G.1, G.2, G.4). Original code.
;
; A card is one byte: suit * 16 + rank, rank 1 (ace) .. 13 (king),
; suit 0 clubs, 1 diamonds, 2 hearts, 3 spades. 0 means "no card".
; Diamonds and hearts are red (suit 1 or 2).
; On screen a card is three characters: rank right-aligned and the suit
; letter, e.g. " AS", "10H", " QC"; a face-down card is " ##".

CARD_RANK  equ 0x0F
CARD_SUIT  equ 0x30

; Fills edi with the 52 cards in order (clubs A..K, diamonds, hearts,
; spades). Keeps registers.
c_newdeck:
    push eax
    push ecx
    push edi
    xor eax, eax                ; al = suit*16
.s: mov ah, 1
.r: mov cl, al
    or cl, ah
    mov [edi], cl
    inc edi
    inc ah
    cmp ah, 13
    jbe .r
    add al, 16
    cmp al, 64
    jb .s
    pop edi
    pop ecx
    pop eax
    ret

; al = card -> eax = 1 if red, 0 if black (0 for no card)
c_isred:
    and eax, CARD_SUIT
    cmp eax, 0x10
    je .red
    cmp eax, 0x20
    je .red
    xor eax, eax
    ret
.red:
    mov eax, 1
    ret

; al = card, dl = card under it -> CF clear when al may go on dl in a
; tableau: one rank lower and the other colour
c_stacks:
    push eax
    push ebx
    push edx
    mov bl, al
    and bl, CARD_RANK
    mov bh, dl
    and bh, CARD_RANK
    inc bl
    cmp bl, bh
    jne .no
    push eax
    call c_isred
    mov ebx, eax
    pop eax
    mov al, dl
    call c_isred
    cmp eax, ebx
    je .no
    clc
    jmp .r
.no:
    stc
.r: pop edx
    pop ebx
    pop eax
    ret

; al = card: prints it in three characters
c_print:
    push eax
    push ebx
    push esi
    test al, al
    jz .none
    movzx ebx, al
    and ebx, CARD_RANK
    cmp ebx, 10
    jne .one
    mov al, '1'
    call g_putc
    mov al, '0'
    jmp .suit0
.one:
    push eax
    mov al, ' '
    call g_putc
    mov al, [c_ranks+ebx]
    call g_putc
    pop eax
    jmp .suit
.suit0:
    call g_putc
    mov eax, [esp+8]
.suit:
    movzx ebx, al
    shr ebx, 4
    and ebx, 3
    mov al, [c_suits+ebx]
    call g_putc
    jmp .r
.none:
    mov esi, c_m_none
    call g_puts
.r: pop esi
    pop ebx
    pop eax
    ret

c_print_back:                   ; a face-down card
    push esi
    mov esi, c_m_back
    call g_puts
    pop esi
    ret

; esi = text: reads a card name like "qh", "10s", "as", "7d".
; -> al = card, esi past it, CF set when it is not a card
c_parse:
    push ebx
    push edx
    call g_skipsp
    push esi
    mov al, [esi]
    cmp al, '1'
    jne .letter
    cmp byte [esi+1], '0'
    jne .letter
    mov bl, 10
    add esi, 2
    jmp .suit
.letter:
    mov ebx, 1
.find:
    cmp al, [c_ranks_lc+ebx]
    je .rk
    inc ebx
    cmp ebx, 13
    jbe .find
    jmp .bad
.rk:
    inc esi
.suit:
    mov al, [esi]
    xor edx, edx
.fs:
    cmp al, [c_suits_lc+edx]
    je .ok
    inc edx
    cmp edx, 4
    jb .fs
    jmp .bad
.ok:
    inc esi
    mov al, dl
    shl al, 4
    or al, bl
    add esp, 4
    clc
    pop edx
    pop ebx
    ret
.bad:
    pop esi
    stc
    pop edx
    pop ebx
    ret

c_ranks db '?A23456789TJQK'
c_ranks_lc db '?a23456789tjqk'
c_suits db 'CDHS'
c_suits_lc db 'cdhs'
c_m_none db '  -', 0
c_m_back db ' ##', 0
