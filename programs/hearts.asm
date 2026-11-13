; hearts — Hearts against three computer players (G.4). Original code.
;
;   run hearts [seed]      play to 100 points; the lowest score wins
;   run hearts test        rules and AI self-check, prints "hearts: PASS"
;
; You sit South; West, North and East are the computer. Play goes
; clockwise: You, West, North, East. Each round starts with passing three
; cards (left, right, across, then no pass), the 2 of clubs leads the
; first trick, you must follow suit when you can, hearts cannot be led
; until one has been played (unless you hold nothing else), and no
; points may be played on the first trick unless you hold nothing else.
; Each heart is 1 point and the queen of spades 13; taking all 26 points
; "shoots the moon" and gives 26 to everyone else instead.
;
; Commands: a card is rank and suit, like "qs", "10h", "th", "2c".
;   qs        play the queen of spades
;   qs kh 2c  (when passing) pass these three cards
;   n         new game            q   quit
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"

HAND   equ 13
S_CLUB equ 0x00
S_DIAM equ 0x10
S_HEART equ 0x20
S_SPADE equ 0x30
C_2C   equ 0x02
C_QS   equ 0x3C
YOU    equ 0

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov esi, m_title
    call g_puts
.newgame:
    mov dword [score], 0
    mov dword [score+4], 0
    mov dword [score+8], 0
    mov dword [score+12], 0
    mov dword [round], 0
.newround:
    call deal
    mov eax, [round]
    and eax, 3
    mov [passdir], eax
    cmp eax, 3
    je .play
.askpass:
    call show_scores
    call show_hand
    mov esi, m_pass1
    call g_puts
    mov eax, [passdir]
    call pass_target
    call put_name
    mov esi, m_pass2
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
    jnc .newgame
    call parse_pass
    jc .badpass
    mov ebx, 1
.aip:
    call ai_pass
    inc ebx
    cmp ebx, 4
    jb .aip
    call exchange
    mov esi, m_got
    call g_puts
    mov ecx, 3
    mov ebx, (YOU*3)
.gotl:
    mov al, ' '
    call g_putc
    mov al, [recv+ebx]
    call c_print
    inc ebx
    loop .gotl
    call g_nl
    jmp .play
.badpass:
    mov esi, m_badpass
    call g_puts
    jmp .askpass
.play:
    call start_play
.trick:
    mov dword [nplayed], 0
    mov eax, [leader]
    mov [cur], eax
    mov dword [trick], 0
.turn:
    cmp dword [nplayed], 4
    je .endtrick
    cmp dword [cur], YOU
    je .human
    mov ebx, [cur]
    call ai_choose
    call play
    push eax
    mov eax, ebx
    call put_name
    mov esi, m_plays
    call g_puts
    pop eax
    call c_print
    call g_nl
    jmp .next
.human:
    call show_trick
    call show_hand
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
    jnc .newgame
    call c_parse
    jc .badcard
    mov ebx, YOU
    call legal
    jc .illegal
    call play
.next:
    mov eax, [cur]
    inc eax
    and eax, 3
    mov [cur], eax
    jmp .turn
.badcard:
    mov esi, m_badcard
    call g_puts
    jmp .human
.illegal:
    mov esi, m_illegal
    call g_puts
    jmp .human
.endtrick:
    call end_trick              ; eax = winner, edx = points
    call put_name
    mov esi, m_takes
    call g_puts
    mov eax, edx
    call g_putdec
    mov esi, m_points
    call g_puts
    cmp dword [trickno], HAND
    jb .trick
    call end_round
    call show_scores
    call game_done
    test eax, eax
    jnz .gameover
    mov esi, m_nextround
    call g_puts
    call g_readline
    cmp eax, -1
    je .quit
    mov esi, g_line
    mov edi, g_w_quit
    call g_word
    jnc .quit
    jmp .newround
.gameover:
    call winner_text
    mov esi, m_again
    call g_puts
    call g_readline
    cmp eax, -1
    je .quit
    mov esi, g_line
    mov edi, g_w_new
    call g_word
    jnc .newgame
.quit:
    xor eax, eax
    ret

; ---------- cards and hands ----------

; al = card -> eax = sort key: suit * 16 + power (2..14, ace high)
key:
    movzx eax, al
    push ebx
    mov ebx, eax
    and ebx, CARD_RANK
    cmp ebx, 1
    jne .r
    add eax, 13
.r: pop ebx
    ret

; al = card -> eax = power 2..14
power:
    call key
    and eax, 0x0F
    ret

; ebx = player -> edi = its hand
handptr:
    imul edi, ebx, HAND
    add edi, hand
    ret

; ebx = player: sorts the hand by suit, then power
sorthand:
    pushad
    call handptr
    mov ecx, [hn+ebx*4]
    xor esi, esi
.i: lea edx, [esi+1]
    cmp edx, ecx
    jae .d
.j: cmp edx, ecx
    jae .ni
    mov al, [edi+edx]
    call key
    mov ebp, eax
    mov al, [edi+esi]
    call key
    cmp ebp, eax
    jae .nj
    mov al, [edi+esi]
    mov ah, [edi+edx]
    mov [edi+esi], ah
    mov [edi+edx], al
.nj:
    inc edx
    jmp .j
.ni:
    inc esi
    jmp .i
.d: popad
    ret

; A seeded deal: 13 cards each, sorted
deal:
    pushad
    mov edi, deck
    call c_newdeck
    mov ecx, 52
    call g_shuffle
    mov esi, deck
    mov edi, hand
    mov ecx, 52
    rep movsb
    xor ebx, ebx
.p: mov dword [hn+ebx*4], HAND
    call sorthand
    inc ebx
    cmp ebx, 4
    jb .p
    popad
    ret

; ebx = player, al = card -> eax = index in the hand, or -1
findcard:
    push ecx
    push edi
    call handptr
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .no
    cmp [edi+ecx], al
    je .yes
    inc ecx
    jmp .l
.yes:
    mov eax, ecx
    jmp .r
.no:
    mov eax, -1
.r: pop edi
    pop ecx
    ret

; ebx = player, al = card: takes it out of the hand (if it is there)
removecard:
    pushad
    call findcard
    cmp eax, -1
    je .r
    call handptr
    mov ecx, [hn+ebx*4]
    dec ecx
    mov [hn+ebx*4], ecx
.l: cmp eax, ecx
    jae .r
    mov dl, [edi+eax+1]
    mov [edi+eax], dl
    inc eax
    jmp .l
.r: popad
    ret

; ebx = player, al = card: adds it and re-sorts
addcard:
    pushad
    call handptr
    mov ecx, [hn+ebx*4]
    mov [edi+ecx], al
    inc dword [hn+ebx*4]
    call sorthand
    popad
    ret

; ebx = player, edx = suit (0x00..0x30) -> eax = how many of it
countsuit:
    push ecx
    push edi
    push esi
    call handptr
    xor eax, eax
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .r
    movzx esi, byte [edi+ecx]
    and esi, CARD_SUIT
    cmp esi, edx
    jne .n
    inc eax
.n: inc ecx
    jmp .l
.r: pop esi
    pop edi
    pop ecx
    ret

; al = card -> eax = its points (heart 1, queen of spades 13)
cardpoints:
    push ebx
    movzx ebx, al
    xor eax, eax
    cmp ebx, C_QS
    jne .h
    mov eax, 13
.h: and ebx, CARD_SUIT
    cmp ebx, S_HEART
    jne .r
    mov eax, 1
.r: pop ebx
    ret

; ---------- rules ----------

start_play:                     ; the 2 of clubs leads the first trick
    pushad
    mov dword [trickno], 0
    mov byte [broken], 0
    mov edi, pts
    mov ecx, 4
    xor eax, eax
    rep stosd
    xor ebx, ebx
.f: mov al, C_2C
    call findcard
    cmp eax, -1
    jne .got
    inc ebx
    cmp ebx, 3
    jb .f
.got:
    mov [leader], ebx
    popad
    ret

; ebx = player, al = card -> CF clear when playing it now is legal
legal:
    pushad
    mov [lg_card], al
    call findcard
    cmp eax, -1
    je .no
    movzx ecx, byte [lg_card]
    and ecx, CARD_SUIT          ; ecx = suit of the card
    cmp dword [nplayed], 0
    jne .follow
    ; leading
    cmp dword [trickno], 0
    jne .lead
    cmp byte [lg_card], C_2C
    jne .no
    jmp .yes
.lead:
    cmp ecx, S_HEART
    jne .yes
    cmp byte [broken], 0
    jne .yes
    mov edx, S_HEART            ; hearts unbroken: only from a hand of hearts
    call countsuit
    cmp eax, [hn+ebx*4]
    je .yes
    jmp .no
.follow:
    call ledsuit
    cmp ecx, edx
    je .first
    call countsuit
    test eax, eax
    jnz .no                     ; must follow suit
.first:
    cmp dword [trickno], 0
    jne .yes
    mov al, [lg_card]           ; no points on the first trick...
    call cardpoints
    test eax, eax
    jz .yes
    call has_safe               ; ...unless every card has points
    test eax, eax
    jnz .no
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; -> edx = the suit led to the current trick
ledsuit:
    mov edx, [leader]
    movzx edx, byte [trick+edx]
    and edx, CARD_SUIT
    ret

; ebx = player -> eax = 1 if it holds a card without points
has_safe:
    push ecx
    push edi
    call handptr
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .none
    mov al, [edi+ecx]
    call cardpoints
    test eax, eax
    jnz .n
    mov eax, 1
    jmp .r
.n: inc ecx
    jmp .l
.none:
    xor eax, eax
.r: pop edi
    pop ecx
    ret

; ebx = player, al = card: plays it to the trick
play:
    push eax
    call removecard
    mov [trick+ebx], al
    inc dword [nplayed]
    and al, CARD_SUIT
    cmp al, S_HEART
    jne .r
    mov byte [broken], 1
.r: pop eax
    ret

; Ends the trick: -> eax = the player who took it, edx = its points.
; Books the points; the taker leads the next trick.
end_trick:
    push ebx
    push ecx
    push esi
    push edi
    call ledsuit
    mov ecx, edx                ; led suit
    mov esi, [leader]           ; best player so far
    mov al, [trick+esi]
    call power
    mov edi, eax                ; best power
    xor edx, edx
    xor ebx, ebx
.l: mov al, [trick+ebx]
    call cardpoints
    add edx, eax
    movzx eax, byte [trick+ebx]
    and eax, CARD_SUIT
    cmp eax, ecx
    jne .n
    mov al, [trick+ebx]
    call power
    cmp eax, edi
    jbe .n
    mov edi, eax
    mov esi, ebx
.n: inc ebx
    cmp ebx, 4
    jb .l
    add [pts+esi*4], edx
    mov [leader], esi
    inc dword [trickno]
    mov eax, esi
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; Adds the round's points to the scores (shooting the moon gives 26 to
; the others instead) -> eax = the moon shooter, or -1
end_round:
    push ebx
    push ecx
    mov eax, -1
    xor ebx, ebx
.m: cmp dword [pts+ebx*4], 26
    jne .mn
    mov eax, ebx
.mn:
    inc ebx
    cmp ebx, 4
    jb .m
    xor ebx, ebx
.s: mov ecx, [pts+ebx*4]
    cmp eax, -1
    je .add
    xor ecx, ecx
    cmp eax, ebx
    je .add
    mov ecx, 26
.add:
    add [score+ebx*4], ecx
    inc ebx
    cmp ebx, 4
    jb .s
    inc dword [round]
    pop ecx
    pop ebx
    ret

; -> eax = 1 when someone has 100 points or more
game_done:
    push ebx
    xor eax, eax
    xor ebx, ebx
.l: cmp dword [score+ebx*4], 100
    jl .n
    mov eax, 1
.n: inc ebx
    cmp ebx, 4
    jb .l
    pop ebx
    ret

; eax = pass direction (0 left, 1 right, 2 across) -> eax = the offset
; to the player passed to
pass_offset:
    push ebx
    mov ebx, eax
    mov eax, 1
    cmp ebx, 0
    je .r
    mov eax, 3
    cmp ebx, 1
    je .r
    mov eax, 2
.r: pop ebx
    ret

; eax = pass direction -> eax = the player YOU pass to
pass_target:
    call pass_offset
    ret

; ebx = player: picks three cards to pass into passbuf[ebx*3]
; (the queen, king and ace of spades first, then high hearts, then the
; highest of the rest)
ai_pass:
    pushad
    lea eax, [ebx+ebx*2]
    mov byte [passbuf+eax], 0
    mov byte [passbuf+eax+1], 0
    mov byte [passbuf+eax+2], 0
    mov ecx, 3
.pick:
    push ecx
    call handptr
    mov dword [pk_best], -1
    xor esi, esi
.c: cmp esi, [hn+ebx*4]
    jae .chosen
    mov al, [edi+esi]
    call pass_score
    ; skip cards already picked
    push ecx
    mov ecx, 0
.dup:
    cmp ecx, 3
    jae .nd
    lea edx, [ebx+ebx*2]
    add edx, ecx
    push eax
    mov al, [edi+esi]
    cmp al, [passbuf+edx]
    pop eax
    je .skip
    inc ecx
    jmp .dup
.nd:
    pop ecx
    cmp eax, [pk_best]
    jle .cn
    mov [pk_best], eax
    mov [pk_idx], esi
    jmp .cn
.skip:
    pop ecx
.cn:
    inc esi
    jmp .c
.chosen:
    pop ecx
    mov edx, 3
    sub edx, ecx
    lea eax, [ebx+ebx*2]
    add edx, eax
    mov esi, [pk_idx]
    mov al, [edi+esi]
    mov [passbuf+edx], al
    loop .pick
    popad
    ret

; al = card -> eax = how much a computer player wants to pass it
pass_score:
    push ebx
    movzx ebx, al
    call power
    cmp ebx, C_QS
    je .top
    cmp ebx, 0x3D               ; king of spades
    je .top2
    cmp ebx, 0x31               ; ace of spades
    je .top2
    and ebx, CARD_SUIT
    cmp ebx, S_HEART
    jne .r
    add eax, 20
    jmp .r
.top:
    mov eax, 100
    jmp .r
.top2:
    mov eax, 90
.r: pop ebx
    ret

; Passes everyone's three cards in passbuf to their neighbour for this
; round (passdir); what each player gets is kept in recv
exchange:
    pushad
    xor ebx, ebx
.take:                          ; take the passed cards out
    mov ecx, 3
    lea esi, [ebx+ebx*2]
.t: mov al, [passbuf+esi]
    call removecard
    inc esi
    loop .t
    inc ebx
    cmp ebx, 4
    jb .take
    mov eax, [passdir]
    call pass_offset
    mov ebp, eax
    xor ebx, ebx
.give:
    lea edx, [ebx+ebp]
    and edx, 3                  ; receiver
    lea esi, [ebx+ebx*2]
    lea edi, [edx+edx*2]
    mov ecx, 3
.g: mov al, [passbuf+esi]
    mov [recv+edi], al
    push ebx
    mov ebx, edx
    call addcard
    pop ebx
    inc esi
    inc edi
    loop .g
    inc ebx
    cmp ebx, 4
    jb .give
    popad
    ret

; esi = text: three different cards of YOU's hand -> passbuf[0..2],
; CF set when the text is not that
parse_pass:
    pushad
    xor ecx, ecx
.c: call c_parse
    jc .bad
    push eax
    xor ebx, ebx
    call findcard
    cmp eax, -1
    pop eax
    je .bad
    xor edx, edx
.dup:
    cmp edx, ecx
    jae .ok
    cmp al, [passbuf+edx]
    je .bad
    inc edx
    jmp .dup
.ok:
    mov [passbuf+ecx], al
    inc ecx
    cmp ecx, 3
    jb .c
    call g_skipsp
    cmp byte [esi], 0
    jne .bad
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; ---------- computer player ----------

; ebx = player -> al = the card it plays (always legal)
;   leading: its lowest legal card
;   following suit: the highest card that still loses the trick; if it
;     must win, the highest card when it plays last, else the lowest
;   void in the suit: the queen of spades, else its highest heart, else
;     its highest card
ai_choose:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    call handptr
    mov byte [ai_card], 0
    cmp dword [nplayed], 0
    je .lead
    call ledsuit
    call countsuit
    test eax, eax
    jz .void
    ; the card winning the trick so far
    call trick_best             ; eax = best power of the led suit
    mov ebp, eax
    ; highest legal card below it
    mov dword [ai_val], -1
    xor esi, esi
.du:
    cmp esi, [hn+ebx*4]
    jae .dud
    mov al, [edi+esi]
    call legal
    jc .dun
    call power
    cmp eax, ebp
    jae .dun
    cmp eax, [ai_val]
    jle .dun
    mov [ai_val], eax
    mov al, [edi+esi]
    mov [ai_card], al
.dun:
    inc esi
    jmp .du
.dud:
    cmp byte [ai_card], 0
    jne .done
    cmp dword [nplayed], 3
    je .high
    jmp .low
.void:
    mov al, C_QS
    call legal
    jc .noqs
    mov [ai_card], al
    jmp .done
.noqs:
    ; highest legal heart, else highest legal card
    mov ecx, S_HEART
    call best_of_suit
    test al, al
    jnz .set
.high:
    mov dword [ai_val], -1
    xor esi, esi
.h: cmp esi, [hn+ebx*4]
    jae .done
    mov al, [edi+esi]
    call legal
    jc .hn
    call key_points             ; highest power; points break ties
    cmp eax, [ai_val]
    jle .hn
    mov [ai_val], eax
    mov al, [edi+esi]
    mov [ai_card], al
.hn:
    inc esi
    jmp .h
.lead:
.low:
    mov dword [ai_val], 999
    xor esi, esi
.l: cmp esi, [hn+ebx*4]
    jae .done
    mov al, [edi+esi]
    call legal
    jc .ln
    call power
    cmp eax, [ai_val]
    jge .ln
    mov [ai_val], eax
    mov al, [edi+esi]
    mov [ai_card], al
.ln:
    inc esi
    jmp .l
.set:
    mov [ai_card], al
.done:
    mov al, [ai_card]
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; al = card -> eax = power * 32 + points (for "highest, points first")
key_points:
    push ebx
    push eax
    call cardpoints
    mov ebx, eax
    pop eax
    call power
    shl eax, 5
    add eax, ebx
    pop ebx
    ret

; ebx = player, ecx = suit -> al = its highest legal card of that suit, or 0
best_of_suit:
    push esi
    push edi
    push edx
    call handptr
    xor edx, edx                ; best card
    xor esi, esi
.l: cmp esi, [hn+ebx*4]
    jae .d
    mov al, [edi+esi]
    movzx eax, al
    and eax, CARD_SUIT
    cmp eax, ecx
    jne .n
    mov al, [edi+esi]
    call legal
    jc .n
    mov dl, al                  ; sorted by power: the last one wins
.n: inc esi
    jmp .l
.d: mov al, dl
    pop edx
    pop edi
    pop esi
    ret

; -> eax = the highest power of the led suit in the trick so far
trick_best:
    push ebx
    push ecx
    push edx
    call ledsuit
    xor ecx, ecx
    mov ebx, [leader]
    push dword [nplayed]
.l: cmp dword [esp], 0
    je .d
    dec dword [esp]
    movzx eax, byte [trick+ebx]
    and eax, CARD_SUIT
    cmp eax, edx
    jne .n
    mov al, [trick+ebx]
    call power
    cmp eax, ecx
    jbe .n
    mov ecx, eax
.n: inc ebx
    and ebx, 3
    jmp .l
.d: add esp, 4
    mov eax, ecx
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- screen ----------

put_name:                       ; eax = player
    push esi
    mov esi, [names+eax*4]
    call g_puts
    pop esi
    ret

show_hand:
    pushad
    mov esi, m_hand
    call g_puts
    xor ebx, ebx
    call handptr
    xor ecx, ecx
    mov dl, 0xFF                ; suit of the previous card
.l: cmp ecx, [hn]
    jae .d
    mov al, [edi+ecx]
    mov ah, al
    and ah, CARD_SUIT
    cmp ah, dl
    je .same
    cmp dl, 0xFF
    je .first
    mov esi, m_bar
    call g_puts
.first:
    mov dl, ah
.same:
    push eax
    mov al, ' '
    call g_putc
    pop eax
    call c_print
    inc ecx
    jmp .l
.d: call g_nl
    popad
    ret

show_trick:
    pushad
    mov esi, m_trick
    call g_puts
    mov ebx, [leader]
    mov ecx, [nplayed]
    test ecx, ecx
    jnz .l
    mov esi, m_lead
    call g_puts
    jmp .d
.l: mov eax, ebx
    call put_name
    mov al, [trick+ebx]
    call c_print
    mov al, ' '
    call g_putc
    inc ebx
    and ebx, 3
    loop .l
.d: call g_nl
    popad
    ret

show_scores:
    pushad
    mov esi, m_scores
    call g_puts
    xor ebx, ebx
.l: mov eax, ebx
    call put_name
    mov al, ' '
    call g_putc
    mov eax, [score+ebx*4]
    call g_putdec
    mov esi, m_gap
    call g_puts
    inc ebx
    cmp ebx, 4
    jb .l
    call g_nl
    popad
    ret

winner_text:                    ; the lowest score wins
    pushad
    xor ebx, ebx
    xor ecx, ecx
.l: mov eax, [score+ecx*4]
    cmp eax, [score+ebx*4]
    jge .n
    mov ebx, ecx
.n: inc ecx
    cmp ecx, 4
    jb .l
    mov eax, ebx
    call put_name
    mov esi, m_wins
    call g_puts
    popad
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%macro ISLEGAL 2                ; player, card -> eax = 1 if legal
    mov ebx, %1
    mov al, %2
    call legal
    setnc al
    movzx eax, al
%endmacro
%macro PLAY 2
    mov ebx, %1
    mov al, %2
    call play
%endmacro

; Plays one whole round with the computer in every seat, checking that
; every card it picks is legal -> eax = illegal picks (0), and the
; points stay in pts
ai_round:
    pushad
    xor ebp, ebp
    call start_play
.trick:
    mov dword [nplayed], 0
    mov eax, [leader]
    mov [cur], eax
.turn:
    cmp dword [nplayed], 4
    je .end
    mov ebx, [cur]
    call ai_choose
    call legal
    jnc .ok
    inc ebp
.ok:
    call play
    mov eax, ebx
    inc eax
    and eax, 3
    mov [cur], eax
    jmp .turn
.end:
    call end_trick
    cmp dword [trickno], HAND
    jb .trick
    mov [esp+28], ebp
    popad
    ret

selftest:
    ; 1. the deal: 13 cards each, every card once, sorted
    mov eax, 4
    call g_srand
    call deal
    call all_cards
    EXPECT 52                   ; 1
    xor ebx, ebx
    call handptr
    mov al, [edi]
    call key
    mov edx, eax
    mov al, [edi+12]
    call key
    cmp edx, eax
    setb al
    movzx eax, al
    EXPECT 1                    ; 2: sorted
    ; 2. legality on a fixed position
    call clear_hands
    xor ebx, ebx                ; You: 2C 5C 3H QS
    mov esi, t_you
    call sethand
    mov ebx, 1                  ; West: 9C 4H
    mov esi, t_west
    call sethand
    mov ebx, 2                  ; North: KD 7H
    mov esi, t_north
    call sethand
    call start_play
    mov eax, [leader]
    EXPECT 0                    ; 3: the 2C holder leads
    ISLEGAL 0, 0x05
    EXPECT 0                    ; 4: 5C may not lead the first trick
    ISLEGAL 0, C_2C
    EXPECT 1                    ; 5
    PLAY 0, C_2C
    ISLEGAL 1, 0x24
    EXPECT 0                    ; 6: West holds 9C and must follow clubs
    PLAY 1, 0x09
    ISLEGAL 2, 0x27
    EXPECT 0                    ; 7: North is void: KD, not 7H, on trick 1
    ISLEGAL 2, 0x1D
    EXPECT 1                    ; 8
    PLAY 2, 0x1D
    mov dword [nplayed], 4      ; (East sits out of this little test)
    mov byte [trick+3], 0
    call end_trick
    EXPECT 1                    ; 9: West's 9C wins
    mov eax, edx
    EXPECT 0                    ; 10: no points
    ; hearts are not led before they are broken
    mov dword [nplayed], 0
    mov dword [leader], 0
    ISLEGAL 0, 0x23
    EXPECT 0                    ; 11: 3H refused
    ISLEGAL 0, C_QS
    EXPECT 1                    ; 12: QS may lead
    mov byte [broken], 1
    ISLEGAL 0, 0x23
    EXPECT 1                    ; 13: after a heart, 3H may lead
    ; 3. points and the moon
    mov byte [trick+0], C_QS
    mov byte [trick+1], 0x2E    ; AH
    mov byte [trick+2], 0x23
    mov byte [trick+3], 0x31    ; AS
    mov dword [leader], 0
    mov dword [pts+12], 0
    call end_trick
    EXPECT 3                    ; 14: the ace of spades takes it
    mov eax, edx
    EXPECT 15                   ; 15: 13 + 1 + 1
    mov dword [score], 0
    mov dword [score+4], 0
    mov dword [score+8], 0
    mov dword [score+12], 0
    mov dword [pts], 0
    mov dword [pts+4], 26
    mov dword [pts+8], 0
    mov dword [pts+12], 0
    call end_round
    EXPECT 1                    ; 16: West shot the moon
    mov eax, [score+4]
    EXPECT 0                    ; 17
    mov eax, [score+12]
    EXPECT 26                   ; 18
    ; 4. passing: three cards each way, everyone keeps 13
    mov eax, 9
    call g_srand
    call deal
    mov dword [passdir], 0
    xor ebx, ebx
.pp:
    call ai_pass
    inc ebx
    cmp ebx, 4
    jb .pp
    mov al, [passbuf+3]         ; West's first pick
    mov [t_card], al
    call exchange
    mov eax, [hn]
    add eax, [hn+4]
    add eax, [hn+8]
    add eax, [hn+12]
    EXPECT 52                   ; 19
    mov ebx, 2                  ; passing left: West's cards went to North
    mov al, [t_card]
    call findcard
    cmp eax, -1
    setne al
    movzx eax, al
    EXPECT 1                    ; 20
    call all_cards
    EXPECT 52                   ; 21
    ; 5. the computer plays whole rounds legally; 26 points each time
    mov dword [t_seed], 1
.rounds:
    mov eax, [t_seed]
    call g_srand
    call deal
    call ai_round
    EXPECT 0                    ; 22, 24, ...: no illegal card
    mov eax, [pts]
    add eax, [pts+4]
    add eax, [pts+8]
    add eax, [pts+12]
    EXPECT 26                   ; 23, 25, ...
    inc dword [t_seed]
    cmp dword [t_seed], 8
    jbe .rounds
    ; 6. the card parser
    mov esi, t_cards
    call c_parse
    movzx eax, al
    EXPECT 0x3C                 ; qs
    call c_parse
    movzx eax, al
    EXPECT 0x2A                 ; 10h
    call c_parse
    movzx eax, al
    EXPECT 0x0A                 ; tc
    call c_parse
    setc al
    movzx eax, al
    EXPECT 1                    ; zz
    call g_report
    ret

clear_hands:
    pushad
    mov edi, hand
    mov ecx, 52
    xor eax, eax
    rep stosb
    mov edi, hn
    mov ecx, 4
    rep stosd
    popad
    ret

; ebx = player, esi = cards (0-terminated)
sethand:
    pushad
    call handptr
    xor ecx, ecx
.l: lodsb
    test al, al
    jz .d
    mov [edi+ecx], al
    inc ecx
    jmp .l
.d: mov [hn+ebx*4], ecx
    popad
    ret

all_cards:                      ; -> eax = different cards in the hands
    pushad
    mov edi, seen
    mov ecx, 64
    xor eax, eax
    rep stosb
    xor ebx, ebx
.p: call handptr
    mov ecx, [hn+ebx*4]
.c: jecxz .n
    movzx eax, byte [edi+ecx-1]
    mov byte [seen+eax], 1
    dec ecx
    jmp .c
.n: inc ebx
    cmp ebx, 4
    jb .p
    xor eax, eax
    mov ecx, 64
.cnt:
    movzx ebx, byte [seen+ecx-1]
    add eax, ebx
    loop .cnt
    mov [esp+28], eax
    popad
    ret

t_you db 0x02, 0x05, 0x23, 0x3C, 0
t_west db 0x09, 0x24, 0
t_north db 0x1D, 0x27, 0
t_cards db 'qs 10h tc zz', 0

names dd n_you, n_west, n_north, n_east
n_you db 'You', 0
n_west db 'West', 0
n_north db 'North', 0
n_east db 'East', 0

m_name db 'hearts', 0
m_title db 'Squirrel Hearts - take as few hearts (1) and the queen of spades (13)', 10
        db 'as you can. Play a card by name (qs, 10h, 2c), n new game, q quits', 10, 0
m_pass1 db 'Pass three cards to ', 0
m_pass2 db ' (like qs kh 2c): ', 0
m_got db 'You received:', 0
m_badpass db 'Name three different cards from your hand', 10, 0
m_plays db ' plays', 0
m_prompt db 'hearts> ', 0
m_badcard db 'Type a card like qs or 10h (or n, q)', 10, 0
m_illegal db 'You cannot play that card now', 10, 0
m_takes db ' takes the trick: ', 0
m_points db ' points', 10, 0
m_nextround db 'Press Enter for the next round (q quits) ', 0
m_again db 'n for a new game, q to quit ', 0
m_hand db 'Your hand:', 0
m_bar db ' |', 0
m_trick db 'Trick: ', 0
m_lead db '(your lead)', 0
m_scores db 'Scores: ', 0
m_gap db '   ', 0
m_wins db ' wins the game!', 10, 0

SQX_BSS
G_BSS
hn resd 4
pts resd 4
score resd 4
round resd 1
passdir resd 1
leader resd 1
cur resd 1
nplayed resd 1
trickno resd 1
pk_best resd 1
pk_idx resd 1
ai_val resd 1
t_seed resd 1
trick resb 4
broken resb 1
lg_card resb 1
ai_card resb 1
t_card resb 1
hand resb 4*HAND
deck resb 52
passbuf resb 12
recv resb 12
seen resb 64
SQX_END
