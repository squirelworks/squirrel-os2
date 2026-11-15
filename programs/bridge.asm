; bridge — Contract Bridge with computer bidding and play (G.6). Original code.
;
;   run bridge [seed]      play rubber-free deals, scored like duplicate
;   run bridge test        auction, play and scoring self-check, "bridge: PASS"
;
; You sit South; your partner North and the opponents West and East are
; the computer. Calls go clockwise from the dealer (South, West, North,
; East in turn): "1c" .. "7nt" bid, "p" passes, "x" doubles, "xx"
; redoubles. The side that wins the auction declares: its first player
; to name the final strain plays the hand, and partner's cards go face up
; as dummy after the opening lead. When North-South declare, you play
; both North's and South's cards, whoever of you is declarer; when
; East-West declare, you defend from South.
; Play a card by name: "qs", "10h", "th".  n = next deal, q = quit.
;
; Scoring is non-vulnerable duplicate scoring: trick values (20 minors,
; 30 majors, 40 + 30 notrump), game 300 or part score 50, slams 500 and
; 1000, overtricks, doubled undertricks 100/200/200/300..., insult 50.
;
; The computer bids a small natural system: opens 1NT with 15-17 and a
; balanced hand, otherwise one of its longest suit with 12+ points
; (majors first), overcalls a five-card suit with 10+, raises partner's
; suit by its strength with support, answers 1NT with 2NT or 3NT, bids a
; new suit or notrump with 6+, and bids game (or slam) when the
; partnership has the points. Conventions: Stayman over 1NT and
; Blackwood (4NT asks for aces) before a slam. It never doubles.
%include "sqx.inc"
SQX_HEADER main
%include "games.inc"
%include "cards.inc"

HAND   equ 13
SOUTH  equ 0
WEST   equ 1
NORTH  equ 2
EAST   equ 3
C_PASS equ 0
C_X    equ 36
C_XX   equ 37
NT     equ 4
MAXCALL equ 96

main:
    mov ebx, m_name
    call g_start
    jc selftest
    mov esi, m_title
    call g_puts
    mov dword [total], 0
    mov dword [total+4], 0
    mov dword [dealno], 0
.newdeal:
    call deal
    mov eax, [dealno]
    and eax, 3
    mov [dealer], eax
    call auction_start
    mov esi, m_dealer
    call g_puts
    mov eax, [dealer]
    call put_name
    call g_nl
.call:
    call auction_over
    test eax, eax
    jnz .bidding_done
    cmp dword [cur], SOUTH
    je .yourcall
    mov ebx, [cur]
    call ai_bid
    call apply_call
    mov eax, ebx
    call put_name
    mov esi, m_calls
    call g_puts
    mov eax, [lastcall]
    call put_call
    call g_nl
    jmp .call
.yourcall:
    call show_auction
    xor ebx, ebx
    call show_hand_of
    mov esi, m_bidprompt
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
    jnc .next
    call parse_call
    jc .badcall
    xor ebx, ebx
    call legal_call
    jc .badcall
    call apply_call
    jmp .call
.badcall:
    mov esi, m_badcall
    call g_puts
    jmp .yourcall
.bidding_done:
    call show_auction
    cmp dword [lastbid], 0
    jne .contract
    mov esi, m_passout
    call g_puts
    jmp .endprompt
.contract:
    call set_contract
    call show_contract
    call play_start
.trick:
    mov dword [nplayed], 0
    mov eax, [leader]
    mov [cur], eax
.turn:
    cmp dword [nplayed], 4
    je .endtrick
    mov ebx, [cur]
    call controller
    test eax, eax
    jz .human
    call ai_play
    call play
    call say_play
    jmp .next_seat
.human:
    call show_table
    mov esi, m_playprompt
    call g_puts
    mov eax, [cur]
    call put_name
    mov esi, m_playprompt2
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
    jnc .next
    call c_parse
    jc .badcard
    mov ebx, [cur]
    call legal
    jc .illegal
    call play
    cmp ebx, SOUTH
    je .next_seat
    call say_play               ; a card from dummy is announced too
.next_seat:
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
    call end_trick
    call put_name
    mov esi, m_wins
    call g_puts
    cmp dword [trickno], HAND
    jb .trick
    call score_deal             ; eax = score for N-S (negative: E-W scored)
    call show_result
.endprompt:
    inc dword [dealno]
    call show_totals
    mov esi, m_nextdeal
    call g_puts
    call g_readline
    cmp eax, -1
    je .quit
    mov esi, g_line
    mov edi, g_w_quit
    call g_word
    jnc .quit
    jmp .newdeal
.next:
    inc dword [dealno]
    jmp .newdeal
.quit:
    xor eax, eax
    ret

; ---------- cards and hands ----------

; al = card -> eax = suit * 16 + power (2..14, ace high)
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

power:                          ; al = card -> eax = 2..14
    call key
    and eax, 0x0F
    ret

suitof:                         ; al = card -> eax = suit 0..3
    movzx eax, al
    shr eax, 4
    and eax, 3
    ret

handptr:                        ; ebx = seat -> edi = its hand
    imul edi, ebx, HAND
    add edi, hand
    ret

sorthand:                       ; ebx = seat: by suit, then power
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

findcard:                       ; ebx = seat, al = card -> eax = index or -1
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

removecard:                     ; ebx = seat, al = card
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

countsuit:                      ; ebx = seat, edx = suit 0..3 -> eax
    push ecx
    push edi
    push esi
    call handptr
    xor eax, eax
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .r
    movzx esi, byte [edi+ecx]
    shr esi, 4
    cmp esi, edx
    jne .n
    inc eax
.n: inc ecx
    jmp .l
.r: pop esi
    pop edi
    pop ecx
    ret

; ebx = seat -> eax = high-card points (A 4, K 3, Q 2, J 1)
hcp:
    push ecx
    push edx
    push edi
    call handptr
    xor edx, edx
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .d
    mov al, [edi+ecx]
    call power
    sub eax, 10
    jle .n
    add edx, eax                ; J 1, Q 2, K 3, A 4
.n: inc ecx
    jmp .l
.d: mov eax, edx
    pop edi
    pop edx
    pop ecx
    ret

; ebx = seat -> eax = 1 if balanced (no void or singleton, at most one
; doubleton)
balanced:
    push ecx
    push edx
    xor ecx, ecx                ; doubletons
    xor edx, edx
.s: call countsuit
    cmp eax, 2
    jb .no
    jne .n
    inc ecx
.n: inc edx
    cmp edx, 4
    jb .s
    xor eax, eax
    cmp ecx, 1
    ja .r
    inc eax
    jmp .r
.no:
    xor eax, eax
.r: pop edx
    pop ecx
    ret

; ---------- the auction ----------

auction_start:
    pushad
    mov eax, [dealer]
    mov [cur], eax
    xor eax, eax
    mov [ncalls], eax
    mov [lastbid], eax
    mov [lastbidder], eax
    mov [dbl], eax
    mov [passes], eax
    mov edi, firstname
    mov ecx, 10
    mov al, 0xFF
    rep stosb
    mov edi, nbids
    mov ecx, 4
    xor eax, eax
    rep stosd
    popad
    ret

; ebx = seat, eax = call -> CF clear when it may be made now
legal_call:
    push eax
    push edx
    test eax, eax
    jz .yes                     ; pass
    cmp eax, C_X
    je .x
    cmp eax, C_XX
    je .xx
    cmp eax, 35
    ja .no
    cmp eax, [lastbid]
    jbe .no
    jmp .yes
.x: cmp dword [lastbid], 0
    je .no
    cmp dword [dbl], 0
    jne .no
    mov edx, [lastbidder]
    xor edx, ebx
    test edx, 1                 ; the opponents' bid
    jz .no
    jmp .yes
.xx:
    cmp dword [dbl], 1
    jne .no
    mov edx, [lastbidder]
    xor edx, ebx
    test edx, 1                 ; our bid, doubled
    jnz .no
.yes:
    pop edx
    pop eax
    clc
    ret
.no:
    pop edx
    pop eax
    stc
    ret

; ebx = seat (must be cur), eax = legal call: records it, next seat
apply_call:
    pushad
    mov ecx, [ncalls]
    cmp ecx, MAXCALL
    jae .full
    mov [calls+ecx], al
    inc dword [ncalls]
.full:
    mov [lastcall], eax
    test eax, eax
    jz .pass
    cmp eax, C_X
    je .x
    cmp eax, C_XX
    je .xx
    mov [lastbid], eax
    mov [lastbidder], ebx
    mov dword [dbl], 0
    mov dword [passes], 0
    inc dword [nbids+ebx*4]
    dec eax
    xor edx, edx
    mov ecx, 5
    div ecx                     ; edx = strain
    mov ecx, ebx
    and ecx, 1                  ; side
    imul ecx, 5
    add ecx, edx
    cmp byte [firstname+ecx], 0xFF
    jne .next
    mov [firstname+ecx], bl
    jmp .next
.x: mov dword [dbl], 1
    mov dword [passes], 0
    jmp .next
.xx:
    mov dword [dbl], 2
    mov dword [passes], 0
    jmp .next
.pass:
    inc dword [passes]
.next:
    mov eax, ebx
    inc eax
    and eax, 3
    mov [cur], eax
    popad
    ret

; -> eax = 1 when the auction has ended
auction_over:
    xor eax, eax
    cmp dword [lastbid], 0
    jne .bid
    cmp dword [passes], 4
    jb .r
    inc eax
    ret
.bid:
    cmp dword [passes], 3
    jb .r
    inc eax
.r: ret

; From the last bid: level, strain, declarer, dummy, doubling
set_contract:
    pushad
    mov eax, [lastbid]
    dec eax
    xor edx, edx
    mov ecx, 5
    div ecx
    inc eax
    mov [level], eax
    mov [trump], edx
    mov ecx, [lastbidder]
    and ecx, 1
    imul ecx, 5
    add ecx, edx
    movzx eax, byte [firstname+ecx]
    mov [declarer], eax
    xor eax, 2
    mov [dummy], eax
    popad
    ret

; esi = text: "1c" .. "7nt", "p", "pass", "x", "xx" -> eax = call,
; CF set if it is none of these
parse_call:
    push ebx
    push edi
    mov edi, w_pass
    call g_word
    jnc .pass
    mov edi, w_p
    call g_word
    jnc .pass
    mov edi, w_xx
    call g_word
    jnc .xx
    mov edi, w_x
    call g_word
    jnc .x
    call g_skipsp
    movzx eax, byte [esi]
    sub eax, '1'
    cmp eax, 7
    jae .no
    imul eax, 5
    inc esi
    movzx ebx, byte [esi]
    inc esi
    cmp bl, 'n'
    jne .suit
    cmp byte [esi], 't'
    jne .nt
    inc esi
.nt:
    add eax, NT
    jmp .end
.suit:
    xor edi, edi
.s: cmp bl, [c_suits_lc+edi]
    je .found
    inc edi
    cmp edi, 4
    jb .s
    jmp .no
.found:
    add eax, edi
.end:
    inc eax
    call g_skipsp
    cmp byte [esi], 0
    jne .no
    clc
    jmp .r
.pass:
    xor eax, eax
    clc
    jmp .r
.x: mov eax, C_X
    clc
    jmp .r
.xx:
    mov eax, C_XX
    clc
    jmp .r
.no:
    stc
.r: pop edi
    pop ebx
    ret

; ---------- computer bidding ----------

; edx = strain, ebx = seat -> eax = the cheapest legal bid in that strain
cheapest:
    push ecx
    mov eax, [lastbid]
    test eax, eax
    jz .one
    dec eax
    push edx
    xor edx, edx
    mov ecx, 5
    div ecx                     ; eax = level - 1, edx = strain of last bid
    mov ecx, edx
    pop edx
    cmp edx, ecx
    jg .same
    inc eax
.same:
    imul eax, 5
    lea eax, [eax+edx+1]
    pop ecx
    ret
.one:
    lea eax, [edx+1]
    pop ecx
    ret

; edx = strain, ecx = level -> eax = that bid
mkbid:
    lea eax, [ecx-1]
    imul eax, 5
    lea eax, [eax+edx+1]
    ret

; ebx = seat -> edx = its longest suit (majors win ties, then the higher)
longest:
    push eax
    push ecx
    push esi
    mov esi, -1
    xor ecx, ecx                ; best length
    mov edx, 3
.l: push edx
    call countsuit
    pop edx
    cmp eax, ecx
    jbe .n
    mov ecx, eax
    mov esi, edx
.n: dec edx
    jns .l
    mov edx, esi
    pop esi
    pop ecx
    pop eax
    ret

; ebx = seat -> eax = the call it makes (always legal)
ai_bid:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    call hcp
    mov ebp, eax                ; points
    cmp dword [nbids+ebx*4], 4
    jae .pass                   ; four bids are enough
    ; partner's last bid, if any, and our own
    mov eax, ebx
    xor eax, 2
    mov [ab_partner], eax
    call last_bid_of            ; eax = partner's last bid or 0
    mov [ab_pbid], eax
    mov eax, ebx
    call last_bid_of
    mov [ab_mybid], eax
    call conventions            ; eax = a conventional call, or -1
    cmp eax, -1
    jne .try
    cmp dword [nbids+ebx*4], 0
    jne .rebid
    cmp dword [ab_pbid], 0
    jne .respond
    ; --- open or overcall ---
    cmp dword [lastbid], 0
    jne .overcall
    cmp ebp, 15
    jb .open_suit
    cmp ebp, 17
    ja .open_suit
    call balanced
    test eax, eax
    jz .open_suit
    mov eax, 5                  ; 1NT
    jmp .try
.open_suit:
    cmp ebp, 12
    jb .pass
    call open_suit              ; edx = suit
    call cheapest
    jmp .try
.overcall:
    cmp ebp, 10
    jb .pass
    call longest
    push edx
    call countsuit
    pop edx
    cmp eax, 5
    jb .pass
    call cheapest
    cmp eax, 10                 ; no higher than the two level
    ja .pass
    jmp .try
    ; --- answer partner ---
.respond:
    mov eax, [ab_pbid]
    call bid_strain             ; edx = strain, ecx = level
    cmp edx, NT
    je .r_nt
    ; support: 3 cards for a major, 4 for a minor
    push edx
    call countsuit
    pop edx
    mov ecx, 3
    cmp edx, 2
    jae .maj
    mov ecx, 4
.maj:
    cmp eax, ecx
    jb .newsuit
    cmp ebp, 6
    jb .pass
    mov ecx, 2
    cmp ebp, 10
    jb .raise
    mov ecx, 3
    cmp ebp, 13
    jb .raise
    mov ecx, 4                  ; game
    cmp edx, 2
    jae .raise
    mov ecx, 5
.raise:
    call mkbid
    jmp .try
.r_nt:
    cmp ebp, 8
    jb .pass
    mov edx, NT
    mov ecx, 2
    cmp ebp, 10
    jb .raise
    mov ecx, 3
    jmp .raise
.newsuit:
    cmp ebp, 6
    jb .pass
    call longest
    push edx
    call countsuit
    pop edx
    cmp eax, 4
    jb .ntresp
    call cheapest
    cmp eax, 5                  ; a new suit at the one level
    jbe .try
    cmp ebp, 11                 ; or the two level with 11+
    jb .ntresp
    cmp eax, 10
    jbe .try
.ntresp:
    mov edx, NT
    mov ecx, 1
    cmp ebp, 10
    jb .ntl
    mov ecx, 2
    cmp ebp, 13
    jb .ntl
    mov ecx, 3
.ntl:
    call mkbid
    cmp eax, [lastbid]
    ja .try
    jmp .pass
    ; --- rebid: game or slam when the partnership has it ---
.rebid:
    cmp dword [ab_pbid], 0
    je .pass
    mov eax, [ab_pbid]
    call partner_points         ; eax = what partner showed
    add ebp, eax
    cmp ebp, 25
    jb .pass
    ; a fit: partner's strain if we hold support, or our own suit if
    ; partner raised it, else notrump
    mov eax, [ab_pbid]
    call bid_strain
    cmp edx, NT
    je .gamebid
    push edx
    call countsuit
    pop edx
    cmp eax, 3
    jae .gamebid
    mov edx, NT
.gamebid:
    mov ecx, 3                  ; 3NT, 4 of a major, 5 of a minor
    cmp edx, NT
    je .lev
    mov ecx, 4
    cmp edx, 2
    jae .lev
    mov ecx, 5
.lev:
    cmp ebp, 33
    jb .g
    mov [bw_strain+ebx*4], edx  ; slam values: ask for aces first
    mov eax, 20                 ; 4NT
    push eax
    call legal_call
    pop eax
    jnc .r
    mov ecx, 6
.g: call mkbid
.try:
    push eax
    call legal_call
    pop eax
    jnc .r
.pass:
    xor eax, eax
.r: pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; The conventions, tried before the natural bids. ebx = seat, ebp =
; points, ab_pbid / ab_mybid = partner's and our last bids.
; -> eax = the call, or -1 when none applies
;   Stayman: over partner's 1NT, 2C with 8+ points and a four-card major;
;     the 1NT opener answers 2H, 2S or 2D (no major); the asker then
;     raises a fitting major (3 with 8-9, 4 with 10+) or bids 2NT / 3NT.
;   Blackwood: 4NT asks for aces; the answer is 5C (0 or 4), 5D (1),
;     5H (2), 5S (3); with three aces between them the asker bids six of
;     the suit agreed, else five of it.
conventions:
    push ebx
    push ecx
    push edx
    ; --- answer Blackwood ---
    cmp dword [ab_pbid], 20
    jne .stay
    cmp dword [ab_mybid], 20
    je .stay
    call aces
    and eax, 3                  ; 4 aces answer like 0
    add eax, 21                 ; 5C + aces
    jmp .r
.stay:
    ; --- Stayman, asking ---
    cmp dword [ab_pbid], 5
    jne .answer
    cmp dword [ab_mybid], 0
    jne .answer
    cmp dword [lastbid], 5      ; no interference
    jne .none
    cmp ebp, 8
    jb .none
    call fourmajor
    test eax, eax
    jz .none
    mov eax, 6                  ; 2C
    jmp .r
.answer:
    ; --- Stayman, the opener's answer ---
    cmp dword [ab_mybid], 5
    jne .after
    cmp dword [ab_pbid], 6
    jne .after
    mov edx, 2
    call countsuit
    cmp eax, 4
    mov eax, 8                  ; 2H
    jae .r
    mov edx, 3
    call countsuit
    cmp eax, 4
    mov eax, 9                  ; 2S
    jae .r
    mov eax, 7                  ; 2D: no four-card major
    jmp .r
.after:
    ; --- Stayman, the asker's next bid ---
    cmp dword [ab_mybid], 6
    jne .bw
    mov eax, [ab_pbid]
    cmp eax, 7
    jb .bw
    cmp eax, 9
    ja .bw
    cmp eax, 7
    je .nt
    sub eax, 6                  ; 2H -> hearts (2), 2S -> spades (3)
    mov edx, eax
    call countsuit
    cmp eax, 4
    jb .nt
    mov ecx, 3
    cmp ebp, 10
    jb .mk
    mov ecx, 4
    jmp .mk
.nt:
    mov edx, NT
    mov ecx, 2
    cmp ebp, 10
    jb .mk
    mov ecx, 3
.mk:
    call mkbid
    jmp .r
.bw:
    ; --- the Blackwood asker, after the answer ---
    cmp dword [ab_mybid], 20
    jne .none
    mov eax, [ab_pbid]
    cmp eax, 21
    jb .none
    cmp eax, 24
    ja .none
    sub eax, 21                 ; aces shown (0 taken as 0)
    mov ecx, eax
    call aces
    add ecx, eax
    mov edx, [bw_strain+ebx*4]
    cmp ecx, 3
    mov ecx, 6
    jae .mk
    mov ecx, 5
    call mkbid
    cmp eax, [lastbid]
    ja .r
.none:
    mov eax, -1
.r: pop edx
    pop ecx
    pop ebx
    ret

; ebx = seat -> eax = its aces
aces:
    push ecx
    push edx
    push edi
    call handptr
    xor edx, edx
    xor ecx, ecx
.l: cmp ecx, [hn+ebx*4]
    jae .d
    mov al, [edi+ecx]
    and al, CARD_RANK
    cmp al, 1
    jne .n
    inc edx
.n: inc ecx
    jmp .l
.d: mov eax, edx
    pop edi
    pop edx
    pop ecx
    ret

; ebx = seat -> eax = 1 if it holds four or more hearts or spades
fourmajor:
    push edx
    mov edx, 2
    call countsuit
    cmp eax, 4
    jae .y
    mov edx, 3
    call countsuit
    cmp eax, 4
    jae .y
    xor eax, eax
    pop edx
    ret
.y: mov eax, 1
    pop edx
    ret

; eax = bid -> edx = strain, ecx = level
bid_strain:
    push eax
    dec eax
    xor edx, edx
    mov ecx, 5
    div ecx
    lea ecx, [eax+1]
    pop eax
    ret

; eax = partner's last bid -> eax = points it is taken to show
partner_points:
    push ecx
    push edx
    call bid_strain
    mov eax, 16                 ; 1NT
    cmp edx, NT
    jne .s
    cmp ecx, 1
    je .r
    mov eax, 11                 ; 2NT answer
    cmp ecx, 2
    je .r
    mov eax, 13
    jmp .r
.s: mov eax, 12                 ; a suit opening (or answer at the two level)
    cmp ecx, 2
    jb .r
    mov eax, 8                  ; a raise to two
    je .r
    mov eax, 11                 ; to three
    cmp ecx, 3
    je .r
    mov eax, 13
.r: pop edx
    pop ecx
    ret

; eax = seat -> eax = its last bid in this auction, or 0
last_bid_of:
    push ebx
    push ecx
    push edx
    push esi
    mov ebx, eax
    xor edx, edx                ; result
    xor ecx, ecx
    mov eax, [dealer]
.l: cmp ecx, [ncalls]
    jae .d
    cmp eax, ebx
    jne .n
    movzx esi, byte [calls+ecx]
    test esi, esi
    jz .n
    cmp esi, 35
    ja .n
    mov edx, esi
.n: inc ecx
    inc eax
    and eax, 3
    jmp .l
.d: mov eax, edx
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebx = seat -> edx = the suit to open: a five-card major (spades on a
; tie), else the longer minor (diamonds with 4-4, clubs with 3-3)
open_suit:
    push eax
    push ecx
    mov edx, 3
    call countsuit
    mov ecx, eax                ; spades
    mov edx, 2
    call countsuit              ; hearts
    cmp ecx, 5
    jb .h
    cmp ecx, eax
    jb .h
    mov edx, 3
    jmp .r
.h: cmp eax, 5
    jb .minor
    mov edx, 2
    jmp .r
.minor:
    mov edx, 1
    call countsuit
    mov ecx, eax                ; diamonds
    xor edx, edx
    call countsuit              ; clubs
    cmp ecx, eax
    ja .d
    jb .c
    cmp ecx, 4
    jae .d
.c: xor edx, edx
    jmp .r
.d: mov edx, 1
.r: pop ecx
    pop eax
    ret

; ---------- the play ----------

play_start:
    pushad
    mov eax, [declarer]
    inc eax
    and eax, 3
    mov [leader], eax
    xor eax, eax
    mov [trickno], eax
    mov [tricks], eax
    mov [tricks+4], eax
    mov [dummy_shown], eax
    mov edi, seen
    mov ecx, 64
    rep stosb
    popad
    ret

; ebx = seat -> eax = 0 if you play its cards, 1 if the computer does
controller:
    xor eax, eax
    cmp ebx, SOUTH
    je .r
    cmp ebx, NORTH
    jne .ai
    test dword [declarer], 1
    jz .r                       ; North-South declare: you play North too
.ai:
    inc eax
.r: ret

; -> edx = the suit led to this trick
ledsuit:
    push eax
    mov edx, [leader]
    mov al, [trick+edx]
    call suitof
    mov edx, eax
    pop eax
    ret

; ebx = seat, al = card -> CF clear when it may be played now
legal:
    pushad
    mov [lg_card], al
    call findcard
    cmp eax, -1
    je .no
    cmp dword [nplayed], 0
    je .yes
    call ledsuit
    mov al, [lg_card]
    call suitof
    cmp eax, edx
    je .yes
    call countsuit
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

; ebx = seat, al = card: plays it to the trick
play:
    pushad
    call removecard
    mov [trick+ebx], al
    movzx eax, al
    mov byte [seen+eax], 1
    inc dword [nplayed]
    mov dword [dummy_shown], 1
    popad
    ret

; al = card, dl = card it is compared with -> CF clear if al beats dl
; (same suit and higher, or a trump on a non-trump)
beats:
    pushad
    mov bl, al
    call suitof
    mov ecx, eax                ; suit of al
    mov al, dl
    call suitof                 ; suit of dl
    cmp ecx, eax
    jne .diff
    mov al, bl
    call power
    mov ecx, eax
    mov al, dl
    call power
    cmp ecx, eax
    ja .yes
    jmp .no
.diff:
    cmp ecx, [trump]
    jne .no
.yes:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; -> eax = the seat winning the trick so far (over the cards played)
winning:
    push ebx
    push ecx
    push edx
    mov ebx, [leader]
    mov ecx, ebx                ; winner
    mov edx, [nplayed]
.l: dec edx
    jz .d
    js .d
    inc ebx
    and ebx, 3
    push edx
    mov al, [trick+ebx]
    mov dl, [trick+ecx]
    call beats
    pop edx
    jc .l
    mov ecx, ebx
    jmp .l
.d: mov eax, ecx
    pop edx
    pop ecx
    pop ebx
    ret

; Ends the trick -> eax = winner; books it; the winner leads next
end_trick:
    call winning
    push ebx
    mov ebx, eax
    and ebx, 1
    inc dword [tricks+ebx*4]
    pop ebx
    mov [leader], eax
    inc dword [trickno]
    ret

; ebx = seat, al = card -> eax = 1 if no card of its suit that is higher
; is still out (unplayed and not in this seat's hand)
is_top:
    pushad
    mov dl, al
    call power
    mov ecx, eax
.l: inc ecx
    cmp ecx, 14
    ja .yes
    mov eax, ecx
    cmp eax, 14
    jne .r
    mov eax, 1
.r: mov ah, dl
    and ah, CARD_SUIT
    or al, ah
    movzx esi, al
    cmp byte [seen+esi], 0
    jne .l
    call findcard
    cmp eax, -1
    jne .l
    popad
    xor eax, eax
    ret
.yes:
    popad
    mov eax, 1
    ret

; ebx = seat, edx = suit (or -1 for any), ecx = 0 lowest / 1 highest
; -> al = that card of the seat's legal cards in the suit (0 if none)
pick:
    push esi
    push edi
    push ebp
    call handptr
    xor ebp, ebp                ; chosen card
    mov dword [pk_val], -1
    cmp ecx, 0
    jne .h
    mov dword [pk_val], 99
.h: xor esi, esi
.l: cmp esi, [hn+ebx*4]
    jae .d
    mov al, [edi+esi]
    call legal
    jc .n
    cmp edx, -1
    je .any
    call suitof
    cmp eax, edx
    jne .n
    mov al, [edi+esi]
.any:
    call power
    cmp ecx, 0
    jne .hi
    cmp eax, [pk_val]
    jae .n
    jmp .take
.hi:
    cmp eax, [pk_val]
    jle .n
.take:
    mov [pk_val], eax
    movzx ebp, byte [edi+esi]
.n: inc esi
    jmp .l
.d: mov eax, ebp
    pop ebp
    pop edi
    pop esi
    ret

; ebx = seat -> al = the card the computer plays (always legal)
ai_play:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    cmp dword [nplayed], 0
    jne .follow
    ; --- lead ---
    mov eax, [declarer]
    xor eax, ebx
    test eax, 1
    jnz .notdecl
    cmp dword [trump], NT
    je .tops
    call trumps_out
    test eax, eax
    jz .tops
    mov edx, [trump]
    mov ecx, 1
    call pick
    test al, al
    jnz .done                   ; draw trumps with the highest
.notdecl:
.tops:
    ; a card that is the best left in its suit (not a trump if possible)
    call handptr
    xor esi, esi
    xor ecx, ecx                ; a trump top, kept for later
.t: cmp esi, [hn+ebx*4]
    jae .notop
    mov al, [edi+esi]
    call is_top
    test eax, eax
    jz .tn
    mov al, [edi+esi]
    call suitof
    cmp eax, [trump]
    jne .topok
    mov cl, [edi+esi]
    jmp .tn
.topok:
    mov al, [edi+esi]
    jmp .done
.tn:
    inc esi
    jmp .t
.notop:
    ; the lowest card of the longest side suit
    call longest_side
    mov ecx, 0
    call pick
    test al, al
    jnz .done
    mov edx, -1
    call pick
    jmp .done
    ; --- follow ---
.follow:
    call ledsuit
    mov [ap_led], edx
    call countsuit
    test eax, eax
    jz .void
    call winning
    mov [ap_win], eax
    xor eax, ebx
    cmp eax, 2
    jne .contest
    ; partner is winning: low, unless partner may still be beaten
    cmp dword [nplayed], 3
    je .low
    push ebx
    mov ebx, [ap_win]
    mov al, [trick+ebx]
    call is_top
    pop ebx
    test eax, eax
    jnz .low
.contest:
    cmp dword [nplayed], 1
    je .low                     ; second hand low
    call cheapest_winner
    test al, al
    jnz .done
.low:
    mov edx, [ap_led]
    xor ecx, ecx
    call pick
    jmp .done
.void:
    call winning
    xor eax, ebx
    cmp eax, 2
    je .discard
    cmp dword [trump], NT
    je .discard
    call cheapest_winner        ; a ruff that wins
    test al, al
    jnz .done
.discard:
    call longest_side
    xor ecx, ecx
    call pick
    test al, al
    jnz .done
    mov edx, -1
    xor ecx, ecx
    call pick
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebx = seat -> al = its cheapest legal card that beats the trick so far
cheapest_winner:
    push ecx
    push edx
    push esi
    push edi
    call winning
    mov dl, [trick+eax]
    call handptr
    mov dh, 0                   ; best card
    mov dword [cw_val], 999
    xor esi, esi
.l: cmp esi, [hn+ebx*4]
    jae .d
    mov al, [edi+esi]
    call legal
    jc .n
    call beats
    jc .n
    call key                    ; trumps sort above by suit*16, fine for "cheapest"
    mov ecx, eax
    mov al, [edi+esi]
    call suitof
    cmp eax, [trump]
    jne .nt
    add ecx, 100                ; spend a trump last
.nt:
    cmp ecx, [cw_val]
    jae .n
    mov [cw_val], ecx
    mov dh, [edi+esi]
.n: inc esi
    jmp .l
.d: mov al, dh
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

; ebx = seat -> edx = its longest suit that is not trumps (-1 if none)
longest_side:
    push eax
    push ecx
    push esi
    mov esi, -1
    xor ecx, ecx
    mov edx, 3
.l: cmp edx, [trump]
    je .n
    push edx
    call countsuit
    pop edx
    cmp eax, ecx
    jbe .n
    mov ecx, eax
    mov esi, edx
.n: dec edx
    jns .l
    mov edx, esi
    pop esi
    pop ecx
    pop eax
    ret

; ebx = seat -> eax = trumps the opponents may still hold
trumps_out:
    push ecx
    push edx
    push esi
    mov edx, [trump]
    mov esi, 13
    call countsuit
    sub esi, eax
    push ebx
    xor ebx, 2
    call countsuit
    pop ebx
    sub esi, eax
    xor ecx, ecx                ; trumps played
.l: mov eax, ecx
    shr eax, 4
    cmp eax, edx
    jne .n
    cmp byte [seen+ecx], 0
    je .n
    dec esi
.n: inc ecx
    cmp ecx, 64
    jb .l
    mov eax, esi
    pop esi
    pop edx
    pop ecx
    ret

; ---------- scoring ----------

; -> eax = the declaring side's score (negative when it went down);
; also adds it to the totals
score_deal:
    push ebx
    push ecx
    push edx
    push esi
    mov ebx, [declarer]
    and ebx, 1
    mov eax, [tricks+ebx*4]
    mov [made], eax
    mov eax, [level]
    mov edx, [trump]
    mov ecx, [dbl]
    mov esi, [made]
    call contract_score
    mov [result], eax
    test eax, eax
    js .def
    add [total+ebx*4], eax
    jmp .r
.def:
    xor ebx, 1
    neg eax
    add [total+ebx*4], eax
    neg eax
.r: pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; eax = level, edx = strain, ecx = 0/1/2 (doubled), esi = tricks taken
; -> eax = score for the declaring side (non-vulnerable)
contract_score:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ebp, eax                ; level
    lea edi, [ebp+6]            ; tricks needed
    cmp esi, edi
    jb .down
    ; per-trick value
    mov ebx, 20
    cmp edx, 2
    jb .v
    mov ebx, 30
.v: mov eax, ebp
    imul eax, ebx
    cmp edx, NT
    jne .nt
    add eax, 10
.nt:
    shl eax, cl                 ; x2 doubled, x4 redoubled
    mov [cs_trick], eax
    mov edx, 50                 ; part score...
    cmp eax, 100
    jb .ps
    mov edx, 300                ; ...or game
.ps:
    add eax, edx
    cmp ebp, 6
    jb .noslam
    add eax, 500
    cmp ebp, 7
    jb .noslam
    add eax, 500
.noslam:
    ; insult
    test ecx, ecx
    jz .over
    mov edx, 50
    shl edx, cl
    shr edx, 1
    add eax, edx
.over:
    sub esi, edi                ; overtricks
    jz .done
    test ecx, ecx
    jnz .dover
    imul esi, ebx
    add eax, esi
    jmp .done
.dover:
    imul esi, esi, 50
    shl esi, cl                 ; 100 doubled, 200 redoubled
    add eax, esi
    jmp .done
.down:
    sub edi, esi                ; undertricks
    test ecx, ecx
    jnz .ddown
    imul eax, edi, -50
    jmp .done
.ddown:
    ; 100, then 200, 200, then 300 each (doubled)
    mov eax, 100
    cmp edi, 1
    je .dd
    add eax, 200
    cmp edi, 2
    je .dd
    add eax, 200
    sub edi, 3
    imul edi, 300
    add eax, edi
.dd:
    shl eax, cl
    shr eax, 1                  ; x1 doubled, x2 redoubled
    neg eax
.done:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- screen ----------

put_name:                       ; eax = seat
    push esi
    mov esi, [names+eax*4]
    call g_puts
    pop esi
    ret

put_call:                       ; eax = call
    push eax
    push ecx
    push edx
    push esi
    mov esi, m_pass
    test eax, eax
    jz .s
    mov esi, m_x
    cmp eax, C_X
    je .s
    mov esi, m_xx
    cmp eax, C_XX
    je .s
    call bid_strain
    lea eax, [ecx+'0']
    call g_putc
    call put_strain
    jmp .r
.s: call g_puts
.r: pop esi
    pop edx
    pop ecx
    pop eax
    ret

put_strain:                     ; edx = strain
    push eax
    push esi
    cmp edx, NT
    jne .s
    mov esi, m_nt
    call g_puts
    jmp .r
.s: mov al, [c_suits+edx]
    call g_putc
.r: pop esi
    pop eax
    ret

show_auction:
    pushad
    mov esi, m_auction
    call g_puts
    mov ebx, [dealer]
    xor ecx, ecx
.l: cmp ecx, [ncalls]
    jae .d
    mov al, [seat_letter+ebx]
    call g_putc
    mov al, ' '
    call g_putc
    movzx eax, byte [calls+ecx]
    call put_call
    mov esi, m_comma
    call g_puts
    inc ebx
    and ebx, 3
    inc ecx
    jmp .l
.d: call g_nl
    popad
    ret

show_hand_of:                   ; ebx = seat
    pushad
    mov eax, ebx
    call put_name
    mov al, ':'
    call g_putc
    call handptr
    xor ecx, ecx
    mov dl, 0xFF
.l: cmp ecx, [hn+ebx*4]
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

show_contract:
    pushad
    mov esi, m_contract
    call g_puts
    mov eax, [level]
    add al, '0'
    call g_putc
    mov edx, [trump]
    call put_strain
    mov esi, m_dbl
    cmp dword [dbl], 1
    je .p
    mov esi, m_rdbl
    cmp dword [dbl], 2
    je .p
    mov esi, m_none
.p: call g_puts
    mov esi, m_by
    call g_puts
    mov eax, [declarer]
    call put_name
    call g_nl
    popad
    ret

show_table:
    pushad
    call show_contract
    mov esi, m_tricks
    call g_puts
    mov eax, [tricks]
    call g_putdec
    mov esi, m_ew
    call g_puts
    mov eax, [tricks+4]
    call g_putdec
    call g_nl
    cmp dword [dummy_shown], 0
    je .nodummy
    mov ebx, [dummy]
    cmp ebx, SOUTH
    je .nodummy
    mov esi, m_dummy
    call g_puts
    call show_hand_of
.nodummy:
    test dword [declarer], 1
    jnz .south
    mov ebx, NORTH              ; you play North too
    cmp ebx, [dummy]
    je .south
    call show_hand_of
.south:
    xor ebx, ebx
    call show_hand_of
    mov esi, m_trick
    call g_puts
    mov ebx, [leader]
    mov ecx, [nplayed]
    jecxz .tn
.t: mov eax, ebx
    call put_name
    mov al, [trick+ebx]
    call c_print
    mov al, ' '
    call g_putc
    inc ebx
    and ebx, 3
    loop .t
.tn:
    call g_nl
    popad
    ret

say_play:                       ; ebx = seat, al = card
    push eax
    mov eax, ebx
    call put_name
    mov esi, m_plays
    call g_puts
    pop eax
    call c_print
    call g_nl
    ret

show_result:
    pushad
    call show_contract
    mov esi, m_took
    call g_puts
    mov eax, [made]
    call g_putdec
    mov esi, m_trickstxt
    call g_puts
    mov eax, [declarer]
    and eax, 1
    mov esi, m_ns
    test eax, eax
    jz .s
    mov esi, m_ews
.s: call g_puts
    mov eax, [result]
    test eax, eax
    js .neg
    mov al, '+'
    call g_putc
    mov eax, [result]
.neg:
    call g_putdec
    call g_nl
    popad
    ret

show_totals:
    pushad
    mov esi, m_totals
    call g_puts
    mov eax, [total]
    call g_putdec
    mov esi, m_ew
    call g_puts
    mov eax, [total+4]
    call g_putdec
    call g_nl
    popad
    ret

; ---------- self-test ----------

%macro EXPECT 1
    mov ebx, %1
    call g_expect
%endmacro
%macro CALL_ 2                  ; seat, call: must be legal, then made
    mov ebx, %1
    mov eax, %2
    call apply_call
%endmacro
%macro SCORE 5                  ; level, strain, doubled, tricks, expected
    mov eax, %1
    mov edx, %2
    mov ecx, %3
    mov esi, %4
    call contract_score
    EXPECT %5
%endmacro

; ebx = seat, esi = cards (0-ended)
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

; A whole deal with the computer in every seat -> eax = mistakes
; (illegal calls or cards, or an auction that never ends); tricks in tricks[]
ai_deal:
    pushad
    xor ebp, ebp
    call auction_start
    xor esi, esi
.call:
    call auction_over
    test eax, eax
    jnz .bid_done
    inc esi
    cmp esi, 80
    ja .bad
    mov ebx, [cur]
    call ai_bid
    call legal_call
    jnc .ok
    inc ebp
    xor eax, eax
.ok:
    call apply_call
    jmp .call
.bad:
    inc ebp
    jmp .r
.bid_done:
    cmp dword [lastbid], 0
    je .r
    call set_contract
    call play_start
.trick:
    mov dword [nplayed], 0
    mov eax, [leader]
    mov [cur], eax
.turn:
    cmp dword [nplayed], 4
    je .end
    mov ebx, [cur]
    call ai_play
    call legal
    jnc .lok
    inc ebp
    jmp .r
.lok:
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
.r: mov [esp+28], ebp
    popad
    ret

selftest:
    ; 1. the deal: every card once, 40 points in all
    mov eax, 6
    call g_srand
    call deal
    call all_cards
    EXPECT 52                   ; 1
    xor ecx, ecx
    xor ebx, ebx
.hp:
    call hcp
    add ecx, eax
    inc ebx
    cmp ebx, 4
    jb .hp
    mov eax, ecx
    EXPECT 40                   ; 2
    ; 2. the call parser
    mov esi, t_1c
    call parse_call
    EXPECT 1                    ; 3
    mov esi, t_3nt
    call parse_call
    EXPECT 15                   ; 4
    mov esi, t_7s
    call parse_call
    EXPECT 34                   ; 5
    mov esi, t_p
    call parse_call
    EXPECT C_PASS               ; 6
    mov esi, t_xx
    call parse_call
    EXPECT C_XX                 ; 7
    mov esi, t_8c
    call parse_call
    setc al
    movzx eax, al
    EXPECT 1                    ; 8
    ; 3. legal calls: South 1H; West may not bid 1H but may double;
    ;    North may not double partner, but may redouble the double
    mov dword [dealer], SOUTH
    call auction_start
    CALL_ SOUTH, 13             ; 1H
    mov ebx, WEST
    mov eax, 13
    call legal_call
    setc al
    movzx eax, al
    EXPECT 1                    ; 9
    mov ebx, WEST
    mov eax, C_X
    call legal_call
    setc al
    movzx eax, al
    EXPECT 0                    ; 10
    mov ebx, NORTH
    mov eax, C_X
    call legal_call
    setc al
    movzx eax, al
    EXPECT 1                    ; 11
    CALL_ WEST, C_X
    mov ebx, NORTH
    mov eax, C_XX
    call legal_call
    setc al
    movzx eax, al
    EXPECT 0                    ; 12
    ; 4. the declarer is the first of the side to name the strain
    mov dword [dealer], SOUTH
    call auction_start
    CALL_ SOUTH, 4              ; 1S
    CALL_ WEST, 0
    CALL_ NORTH, 8              ; 2H
    CALL_ EAST, 0
    CALL_ SOUTH, 18             ; 4H
    CALL_ WEST, C_X
    CALL_ NORTH, 0
    call auction_over
    EXPECT 0                    ; 13: two passes after the double
    CALL_ EAST, 0
    CALL_ SOUTH, 0
    call auction_over
    EXPECT 1                    ; 14
    call set_contract
    mov eax, [declarer]
    EXPECT NORTH                ; 15
    mov eax, [level]
    EXPECT 4                    ; 16
    mov eax, [trump]
    EXPECT 2                    ; 17
    mov eax, [dbl]
    EXPECT 1                    ; 18
    ; four passes: passed out
    mov dword [dealer], EAST
    call auction_start
    CALL_ EAST, 0
    CALL_ SOUTH, 0
    CALL_ WEST, 0
    call auction_over
    EXPECT 0                    ; 19
    CALL_ NORTH, 0
    call auction_over
    EXPECT 1                    ; 20
    ; 5. trick winners: notrump and trumps
    mov dword [trump], NT
    mov dword [leader], WEST
    mov dword [nplayed], 3
    mov byte [trick+WEST], 0x25     ; 5H
    mov byte [trick+NORTH], 0x2D    ; KH
    mov byte [trick+EAST], 0x31     ; AS: no trumps, it does not win
    call winning
    EXPECT NORTH                ; 21
    mov dword [trump], 3
    call winning
    EXPECT EAST                 ; 22: spades are trumps now
    ; 6. scores
    SCORE 4, 3, 0, 10, 420      ; 23: 4S made
    SCORE 3, NT, 0, 10, 430     ; 24: 3NT +1
    SCORE 1, NT, 0, 7, 90       ; 25
    SCORE 2, 2, 1, 6, -300      ; 26: 2H doubled, two down
    SCORE 6, 3, 0, 12, 980      ; 27: small slam
    SCORE 2, 0, 0, 10, 130      ; 28: 2C +2
    SCORE 4, 2, 1, 10, 590      ; 29: 4H doubled made
    SCORE 3, 1, 2, 9, 640       ; 30: 3D redoubled made: 240+300+100
    SCORE 7, NT, 0, 13, 1520    ; 31: grand slam
    SCORE 4, 3, 0, 6, -200      ; 32: four down undoubled
    SCORE 3, NT, 1, 4, -1100    ; 33: five down doubled: 100+200+200+300+300
    ; 7. the computer opens 1NT with 15-17 balanced, else its suit
    mov dword [dealer], SOUTH
    call auction_start
    xor ebx, ebx
    mov esi, t_nt_hand
    call sethand
    call ai_bid
    EXPECT 5                    ; 34: 1NT
    xor ebx, ebx
    mov esi, t_s_hand
    call sethand
    call ai_bid
    EXPECT 4                    ; 35: 1S
    xor ebx, ebx
    mov esi, t_weak
    call sethand
    call ai_bid
    EXPECT 0                    ; 36: pass
    ; 8. Stayman: South opens 1NT (four spades), North with four of
    ;    each major and 9 points asks 2C, South shows 2S, North raises to 3S
    mov dword [dealer], SOUTH
    call auction_start
    xor ebx, ebx
    mov esi, t_nt_hand
    call sethand
    mov ebx, NORTH
    mov esi, t_stay_hand
    call sethand
    CALL_ SOUTH, 5
    CALL_ WEST, 0
    mov ebx, NORTH
    call ai_bid
    EXPECT 6                    ; 37: 2C, Stayman
    CALL_ NORTH, 6
    CALL_ EAST, 0
    xor ebx, ebx
    call ai_bid
    EXPECT 9                    ; 38: 2S
    CALL_ SOUTH, 9
    CALL_ WEST, 0
    mov ebx, NORTH
    call ai_bid
    EXPECT 14                   ; 39: 3S (8-9 points)
    ; 9. Blackwood: North asks 4NT, South (one ace in the 1NT hand)
    ;    answers 5D (one ace); North with two aces of its own bids six
    mov dword [dealer], SOUTH
    call auction_start
    CALL_ SOUTH, 4              ; 1S
    CALL_ WEST, 0
    CALL_ NORTH, 20             ; 4NT
    CALL_ EAST, 0
    xor ebx, ebx
    mov esi, t_nt_hand
    call sethand
    call ai_bid
    EXPECT 22                   ; 40: 5D, one ace (the 1NT hand holds AS)
    CALL_ SOUTH, 22
    CALL_ WEST, 0
    mov ebx, NORTH
    mov esi, t_two_aces
    call sethand
    mov dword [bw_strain+NORTH*4], 3
    call ai_bid
    EXPECT 29                   ; 41: 6S
    ; 10. whole computer deals: legal calls and cards, 13 tricks
    mov dword [t_seed], 1
.deals:
    mov eax, [t_seed]
    call g_srand
    call deal
    mov eax, [t_seed]
    and eax, 3
    mov [dealer], eax
    call ai_deal
    EXPECT 0                    ; no mistakes
    cmp dword [lastbid], 0
    je .po
    mov eax, [tricks]
    add eax, [tricks+4]
    EXPECT 13
.po:
    inc dword [t_seed]
    cmp dword [t_seed], 12
    jbe .deals
    call g_report
    ret

all_cards:
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

; ---------- data ----------

; 15 points, 4-3-3-3: AS KS 5S 2S, KH QH 3H, QD 8D 4D, JC 9C 6C
t_nt_hand db 0x31, 0x3D, 0x35, 0x32, 0x2D, 0x2C, 0x23, 0x1C, 0x18, 0x14, 0x0B, 0x09, 0x06, 0
; 13 points, five spades: AS QS 10S 7S 3S, KH 5H, AD 6D 2D, 8C 4C 2C
t_s_hand db 0x31, 0x3C, 0x3A, 0x37, 0x33, 0x2D, 0x25, 0x11, 0x16, 0x12, 0x08, 0x04, 0x02, 0
; 5 points
t_weak db 0x3B, 0x35, 0x32, 0x2C, 0x27, 0x23, 0x19, 0x16, 0x14, 0x0A, 0x08, 0x04, 0x02, 0
; 9 points, four hearts and four spades: KH JH 6H 2H, QS JS 7S 3S, QD 5D, 9C 7C 4C
t_stay_hand db 0x2D, 0x2B, 0x26, 0x22, 0x3C, 0x3B, 0x37, 0x33, 0x1C, 0x15, 0x09, 0x07, 0x04, 0
; two aces: AH AD and 11 more
t_two_aces db 0x21, 0x11, 0x3D, 0x3C, 0x3A, 0x38, 0x2D, 0x2C, 0x1D, 0x18, 0x0D, 0x07, 0x05, 0
t_1c db '1c', 0
t_3nt db '3nt', 0
t_7s db '7s', 0
t_p db 'p', 0
t_xx db 'xx', 0
t_8c db '8c', 0

names dd n_s, n_w, n_n, n_e
n_s db 'South', 0
n_w db 'West', 0
n_n db 'North', 0
n_e db 'East', 0
seat_letter db 'SWNE'
w_pass db 'pass', 0
w_p db 'p', 0
w_x db 'x', 0
w_xx db 'xx', 0

m_name db 'bridge', 0
m_title db 'Squirrel Bridge - you are South, partner North; West and East oppose', 10
        db 'Bid 1c..7nt, p, x, xx; play cards by name (qs, 10h); n next deal, q quits', 10, 0
m_dealer db 'New deal. Dealer: ', 0
m_calls db ' calls ', 0
m_pass db 'pass', 0
m_x db 'X', 0
m_xx db 'XX', 0
m_nt db 'NT', 0
m_comma db '  ', 0
m_auction db 'Auction: ', 0
m_bidprompt db 'Your call: ', 0
m_badcall db 'That call is not possible now (like 1h, 2nt, p, x, xx)', 10, 0
m_passout db 'All four passed: no play.', 10, 0
m_contract db 'Contract: ', 0
m_dbl db ' doubled', 0
m_rdbl db ' redoubled', 0
m_none db 0
m_by db ' by ', 0
m_tricks db 'Tricks: N-S ', 0
m_ew db '  E-W ', 0
m_dummy db 'Dummy ', 0
m_trick db 'Trick: ', 0
m_plays db ' plays', 0
m_playprompt db 'Play from ', 0
m_playprompt2 db ': ', 0
m_badcard db 'Type a card like qs or 10h (or n, q)', 10, 0
m_illegal db 'You cannot play that card now', 10, 0
m_wins db ' wins the trick', 10, 0
m_took db 'Declarer took ', 0
m_trickstxt db ' tricks. ', 0
m_ns db 'N-S ', 0
m_ews db 'E-W ', 0
m_totals db 'Totals: N-S ', 0
m_nextdeal db 'Press Enter for the next deal (q quits) ', 0
m_bar db ' |', 0

SQX_BSS
G_BSS
hn resd 4
total resd 2
tricks resd 2
dealno resd 1
dealer resd 1
cur resd 1
ncalls resd 1
lastbid resd 1
lastbidder resd 1
lastcall resd 1
dbl resd 1
passes resd 1
nbids resd 4
level resd 1
trump resd 1
declarer resd 1
dummy resd 1
leader resd 1
nplayed resd 1
trickno resd 1
dummy_shown resd 1
made resd 1
result resd 1
ab_partner resd 1
ab_pbid resd 1
ab_mybid resd 1
bw_strain resd 4
ap_led resd 1
ap_win resd 1
pk_val resd 1
cw_val resd 1
cs_trick resd 1
t_seed resd 1
trick resb 4
lg_card resb 1
alignb 4
firstname resb 10
calls resb MAXCALL
hand resb 4*HAND
deck resb 52
seen resb 64
SQX_END
