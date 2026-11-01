; Squirrel-OS/2 — Ethernet framing and ARP (1.9.5)
; Included from pm.asm. Original code.
;
; The guest is 10.0.2.15 on the NE2000. An ARP request is a broadcast
; Ethernet frame; a reply's sender is remembered in a small table.
; arp_resolve asks, waits, and returns the address. See
; documentation/kernel/network.md.

ARP_SLOTS   equ 8
ARP_WAIT    equ 200                 ; ticks (two seconds) before giving up
ETH_HDR     equ 14
ETH_ARP     equ 0x0608              ; bytes 08 06, as a little-endian word
ETH_IPV4    equ 0x0008              ; bytes 08 00
ARP_ETH     equ 0x0100              ; hardware type: Ethernet (bytes 00 01)
ARP_IP      equ 0x0008              ; protocol: IPv4 (bytes 08 00)
ARP_REQ     equ 0x0100              ; operation: request
ARP_REPLY   equ 0x0200

; esi = dotted quad -> eax = the address (first octet in the low byte),
; CF set if it is not four numbers from 0 to 255
ip_aton:
    push ebx
    push ecx
    push edx
    push edi
    mov edi, ip_oct
    mov ecx, 4
.oct:
    xor eax, eax
    xor ebx, ebx
.dig:
    mov dl, [esi]
    cmp dl, '0'
    jb .endn
    cmp dl, '9'
    ja .endn
    inc esi
    inc ebx
    imul eax, eax, 10
    sub dl, '0'
    movzx edx, dl
    add eax, edx
    cmp eax, 255
    ja .bad
    jmp .dig
.endn:
    test ebx, ebx
    jz .bad
    mov [edi], al
    inc edi
    dec ecx
    jz .last
    cmp byte [esi], '.'
    jne .bad
    inc esi
    jmp .oct
.last:
    cmp byte [esi], 0
    jne .bad
    mov eax, [ip_oct]
    clc
    jmp .out
.bad:
    stc
.out:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; esi = six bytes: prints them as aa:bb:cc:dd:ee:ff and a newline
net_put_mac:
    push eax
    push ecx
    push esi
    mov ecx, 6
.b:
    cmp ecx, 6
    je .hex
    mov al, ':'
    call putc
.hex:
    mov al, [esi]
    inc esi
    call dev_hex2
    loop .b
    mov al, 10
    call putc
    pop esi
    pop ecx
    pop eax
    ret

; Takes every frame the card has, and every frame waiting on loopback,
; and hands each one to net_demux.
net_pump:
    cmp byte [net_pumping], 0   ; a reply sent from inside here must not re-enter
    jne .busy
    mov byte [net_pumping], 1
    push ebx
    cmp byte [ne_up], 0
    je .lo
    call ne_poll
    mov ebx, ne_if
    call net_drain
.lo:
    mov ebx, net_lo
    call net_drain
    pop ebx
    mov byte [net_pumping], 0
.busy:
    ret

; ebx = interface: net_demux each waiting frame. Handlers may reuse ebx.
net_drain:
    push eax
    push ecx
    push edi
.l:
    push ebx
    mov edi, net_rx
    mov ecx, NET_MTU
    call net_recv
    jc .empty
    call net_demux
    pop ebx
    jmp .l
.empty:
    pop ebx
    pop edi
    pop ecx
    pop eax
    ret

; eax = length, frame in net_rx. ARP is handled here; IPv4 goes to ip_input.
net_demux:
    cmp eax, ETH_HDR
    jb .r
    cmp word [net_rx+12], ETH_ARP
    jne .ip
    cmp eax, ETH_HDR + 28
    jb .r
    call arp_input
    ret
.ip:
    cmp word [net_rx+12], ETH_IPV4
    jne .r
    cmp eax, ETH_HDR + 20
    jb .r
    call ip_input
.r:
    ret

; eax = length, ARP frame in net_rx. Remembers the sender. A request
; for our own address is answered.
arp_input:
    cmp word [net_rx+14], ARP_ETH
    jne .r
    cmp word [net_rx+16], ARP_IP
    jne .r
    cmp byte [net_rx+18], 6
    jne .r
    cmp byte [net_rx+19], 4
    jne .r
    mov eax, [net_rx+28]        ; sender address
    test eax, eax
    jz .op
    cmp eax, [net_our_ip]
    je .op
    lea esi, [net_rx+22]        ; sender's Ethernet address
    call arp_learn
.op:
    cmp word [net_rx+20], ARP_REQ
    jne .r
    mov eax, [net_rx+38]        ; the address they asked about
    cmp eax, [net_our_ip]
    jne .r
    cmp byte [ne_up], 0
    je .r
    call arp_reply
.r:
    ret

; eax = address, esi = six-byte Ethernet address. Keeps the newest
; eight. A repeat of an address replaces its old row.
arp_learn:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov ebx, arp_tab
    xor ecx, ecx
.find:
    cmp byte [arp_used+ecx], 0
    je .n
    cmp [ebx], eax
    jne .n
    jmp .put
.n:
    add ebx, 12
    inc ecx
    cmp ecx, ARP_SLOTS
    jb .find
    mov ebx, arp_tab
    xor ecx, ecx
.free:
    cmp byte [arp_used+ecx], 0
    je .slot
    add ebx, 12
    inc ecx
    cmp ecx, ARP_SLOTS
    jb .free
    movzx ecx, byte [arp_turn]
    mov dl, cl
    inc dl
    cmp dl, ARP_SLOTS
    jb .tn
    xor dl, dl
.tn:
    mov [arp_turn], dl
    imul ebx, ecx, 12
    add ebx, arp_tab
.slot:
    mov byte [arp_used+ecx], 1
.put:
    mov [ebx], eax
    lea edi, [ebx+4]
    mov ecx, 6
.cp:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    loop .cp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; eax = address -> CF clear and esi = its Ethernet address, or CF set
arp_lookup:
    push ebx
    push ecx
    mov ebx, arp_tab
    xor ecx, ecx
.l:
    cmp byte [arp_used+ecx], 0
    je .n
    cmp [ebx], eax
    je .hit
.n:
    add ebx, 12
    inc ecx
    cmp ecx, ARP_SLOTS
    jb .l
    stc
    jmp .o
.hit:
    lea esi, [ebx+4]
    clc
.o:
    pop ecx
    pop ebx
    ret

; eax = address -> CF clear and esi = its Ethernet address.
; Our own address is answered from the card. Anything else is asked
; on the wire; CF is set when nobody answers in time, or there is no card.
arp_resolve:
    cmp eax, [net_our_ip]
    jne .tab
    cmp byte [ne_up], 0
    je .no
    mov esi, ne_mac
    clc
    ret
.tab:
    push eax
    call arp_lookup
    jnc .have
    pop eax
    cmp byte [ne_up], 0
    je .no
    mov [arp_who], eax
    call arp_request
    mov ebx, [ticks]
    add ebx, ARP_WAIT
.wait:
    call net_pump
    mov eax, [arp_who]
    call arp_lookup
    jnc .yes
    cmp [ticks], ebx
    jb .wait
.no:
    stc
    ret
.have:
    pop eax
.yes:
    clc
    ret

; Broadcast request for [arp_who]
arp_request:
    pushad
    mov edi, net_pkt
    cld
    mov eax, 0xFFFFFFFF
    stosd
    stosw                       ; destination: everyone
    mov esi, ne_mac
    mov ecx, 6
    rep movsb
    mov ax, ETH_ARP
    stosw
    mov ax, ARP_ETH
    stosw
    mov ax, ARP_IP
    stosw
    mov al, 6
    stosb
    mov al, 4
    stosb
    mov ax, ARP_REQ
    stosw
    mov esi, ne_mac
    mov ecx, 6
    rep movsb
    mov eax, [net_our_ip]
    stosd
    xor eax, eax
    stosd
    stosw                       ; they have no address yet
    mov eax, [arp_who]
    stosd
    mov ebx, ne_if
    mov esi, net_pkt
    mov ecx, 42
    call net_send
    popad
    ret

; Answer the request in net_rx
arp_reply:
    pushad
    mov edi, net_pkt
    cld
    lea esi, [net_rx+22]
    mov ecx, 6
    rep movsb                   ; back to whoever asked
    mov esi, ne_mac
    mov ecx, 6
    rep movsb
    mov ax, ETH_ARP
    stosw
    mov ax, ARP_ETH
    stosw
    mov ax, ARP_IP
    stosw
    mov al, 6
    stosb
    mov al, 4
    stosb
    mov ax, ARP_REPLY
    stosw
    mov esi, ne_mac
    mov ecx, 6
    rep movsb
    mov eax, [net_our_ip]
    stosd
    lea esi, [net_rx+22]
    mov ecx, 6
    rep movsb
    mov eax, [net_rx+28]        ; their address
    stosd
    mov ebx, ne_if
    mov esi, net_pkt
    mov ecx, 42
    call net_send
    popad
    ret

; arp <ip>
cmd_arp_run:
.sp:
    cmp byte [esi], ' '
    jne .go
    inc esi
    jmp .sp
.go:
    call ip_aton
    jc .bad
    call arp_resolve
    jc .none
    jmp net_put_mac
.none:
    mov esi, [lstr+LS_NET_NOREPLY*4]
    jmp lputs_nl
.bad:
    mov esi, [lstr+LS_NET_BADADDR*4]
    jmp lputs_nl

net_our_ip  db 10, 0, 2, 15
align 4
arp_who     dd 0
arp_turn    db 0
net_pumping db 0
arp_used    times ARP_SLOTS db 0
align 4
arp_tab     times ARP_SLOTS * 12 db 0
ip_oct      times 4 db 0
net_pkt     times NET_MTU + 2 db 0
net_rx      times NET_MTU + 2 db 0
