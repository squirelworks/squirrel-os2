; Squirrel-OS/2 — IPv4 and ICMP echo (1.9.6)
; Included from pm.asm. Original code.
;
; No options and no fragments. The guest is 10.0.2.15/24, gateway
; 10.0.2.2. 127.0.0.0/8 and our own address stay on loopback.
; ping sends four echoes and counts the replies.
; See documentation/kernel/network.md.

IP_TTL      equ 64
IP_ICMP     equ 1
IP_UDP      equ 17
IP_TCP      equ 6
ICMP_MAX    equ 128
PING_WAIT   equ 100                 ; one second, in ticks, for each reply
PING_DATA   equ 8

; esi = bytes, ecx = length -> ax = checksum, stored as a word on the wire.
; A valid packet, checksum included, comes back as 0.
net_cksum:
    push ebx
    push ecx
    push esi
    xor ebx, ebx
    test ecx, ecx
    jz .fold
.w:
    cmp ecx, 1
    je .odd
    movzx eax, word [esi]
    add ebx, eax
    add esi, 2
    sub ecx, 2
    jnz .w
    jmp .fold
.odd:
    movzx eax, byte [esi]
    add ebx, eax
.fold:
    mov eax, ebx
    shr eax, 16
    jz .inv
    and ebx, 0xFFFF
    add ebx, eax
    jmp .fold
.inv:
    not bx
    movzx eax, bx
    pop esi
    pop ecx
    pop ebx
    ret

; eax = destination, dl = protocol, esi = payload, ecx = its length
; -> CF set if it could not be sent
ip_output:
    cmp ecx, NET_MTU - ETH_HDR - 20
    ja .bad
    mov [ip_dst], eax
    mov [ip_proto], dl
    mov [ip_plen], ecx
    mov [ip_pay], esi
    mov eax, [net_our_ip]
    cmp byte [ip_dst], 127
    jne .src
    mov eax, [net_lo_ip]
.src:
    mov [ip_src], eax
    mov eax, [ip_dst]
    cmp al, 127
    je .lo
    cmp eax, [net_our_ip]
    je .lo
    cmp byte [ne_up], 0
    je .bad
    mov ebx, eax
    xor ebx, [net_our_ip]
    and ebx, [net_netmask]      ; same network? (1.9.11)
    jnz .gw
    call arp_resolve
    jc .bad
    jmp .havemac
.gw:
    mov eax, [net_gw_ip]
    call arp_resolve
    jc .bad
.havemac:
    mov edi, ip_dmac
    mov ecx, 6
    cld
    rep movsb
    mov ebx, ne_if
    mov [ip_if], ebx
    mov dword [ip_smac], ne_mac
    jmp .build
.lo:
    mov edi, ip_dmac
    mov ecx, 6
    xor eax, eax
    cld
    rep stosb
    mov ebx, net_lo
    mov [ip_if], ebx
    mov dword [ip_smac], ip_zmac
.build:
    mov edi, net_pkt
    cld
    mov esi, ip_dmac
    mov ecx, 6
    rep movsb
    mov esi, [ip_smac]
    mov ecx, 6
    rep movsb
    mov ax, ETH_IPV4
    stosw
    mov al, 0x45
    stosb
    xor al, al
    stosb
    mov eax, [ip_plen]
    add eax, 20
    mov [ip_tot], eax
    xchg al, ah
    stosw
    inc word [ip_ident]
    mov ax, [ip_ident]
    xchg al, ah
    stosw
    mov ax, 0x0040              ; don't fragment: bytes 40 00
    stosw
    mov al, IP_TTL
    stosb
    mov al, [ip_proto]
    stosb
    xor ax, ax
    stosw                       ; checksum filled in below
    mov eax, [ip_src]
    stosd
    mov eax, [ip_dst]
    stosd
    mov esi, [ip_pay]
    mov ecx, [ip_plen]
    rep movsb
    mov esi, net_pkt + ETH_HDR
    mov ecx, 20
    call net_cksum
    mov [net_pkt + ETH_HDR + 10], ax
    mov ebx, [ip_if]
    mov esi, net_pkt
    mov ecx, [ip_tot]
    add ecx, ETH_HDR
    call net_send
    ret
.bad:
    stc
    ret

; eax = Ethernet length, IPv4 frame in net_rx
ip_input:
    mov bl, [net_rx + ETH_HDR]
    mov bh, bl
    shr bl, 4
    cmp bl, 4
    jne .r
    and bh, 0x0F
    cmp bh, 5                   ; no options
    jne .r
    mov dl, [net_rx + ETH_HDR + 6]
    and dl, 0x3F                ; fragment offset high, and more-fragments
    or dl, [net_rx + ETH_HDR + 7]
    jnz .r
    movzx ebx, byte [net_rx + ETH_HDR + 2]
    shl ebx, 8
    mov bl, [net_rx + ETH_HDR + 3]
    cmp ebx, 20
    jb .r
    lea edx, [ebx + ETH_HDR]
    cmp edx, eax
    ja .r
    mov esi, net_rx + ETH_HDR
    mov ecx, 20
    push ebx
    call net_cksum
    pop ebx
    test ax, ax
    jnz .r
    mov eax, [net_rx + ETH_HDR + 12]
    test eax, eax
    jz .dest
    cmp al, 127
    je .dest
    cmp eax, [net_our_ip]
    je .dest
    lea esi, [net_rx + 6]       ; remember who sent this, for the reply
    call arp_learn
.dest:
    mov eax, [net_rx + ETH_HDR + 16]
    cmp eax, [net_our_ip]
    je .ours
    cmp al, 127
    jne .r
.ours:
    cmp byte [net_rx + ETH_HDR + 9], IP_ICMP
    jne .udp
    call icmp_input
    ret
.udp:
    cmp byte [net_rx + ETH_HDR + 9], IP_UDP
    jne .tcp
    call udp_input
    ret
.tcp:
    cmp byte [net_rx + ETH_HDR + 9], IP_TCP
    jne .r
    call tcp_input
.r:
    ret

; ebx = IPv4 total length. Echo requests are answered. An echo reply
; that matches the ping in progress is counted.
icmp_input:
    mov eax, ebx
    sub eax, 20
    cmp eax, 8
    jb .r
    cmp eax, ICMP_MAX
    ja .r
    mov esi, net_rx + ETH_HDR + 20
    mov ecx, eax
    push eax
    call net_cksum
    test ax, ax
    pop eax
    jnz .r
    cmp byte [net_rx + ETH_HDR + 20], 8
    je .req
    cmp byte [net_rx + ETH_HDR + 20], 0
    jne .r
    cmp byte [net_rx + ETH_HDR + 21], 0
    jne .r
    mov ax, [net_rx + ETH_HDR + 24]
    cmp ax, [ping_id_wire]
    jne .r
    mov ax, [net_rx + ETH_HDR + 26]
    cmp ax, [ping_seq_wire]
    jne .r
    mov byte [ping_got], 1
    ret
.req:
    cmp byte [net_rx + ETH_HDR + 21], 0
    jne .r
    mov esi, net_rx + ETH_HDR + 20
    mov edi, icmp_buf
    mov ecx, eax
    cld
    rep movsb
    mov byte [icmp_buf], 0
    mov word [icmp_buf + 2], 0
    mov ecx, eax
    mov esi, icmp_buf
    push ecx
    call net_cksum
    pop ecx
    mov [icmp_buf + 2], ax
    mov eax, [net_rx + ETH_HDR + 12]
    mov esi, icmp_buf
    mov dl, IP_ICMP
    call ip_output
.r:
    ret

; ecx = sequence 1..4. CF clear when a reply arrives.
ping_one:
    mov byte [ping_got], 0
    mov edi, icmp_buf
    cld
    mov al, 8
    stosb
    xor al, al
    stosb
    xor ax, ax
    stosw
    mov ax, 0x3517
    stosw
    mov ax, cx
    xchg al, ah
    stosw
    mov eax, 'SQOS'
    stosd
    mov eax, 'ping'
    stosd
    mov ax, [icmp_buf + 4]
    mov [ping_id_wire], ax
    mov ax, [icmp_buf + 6]
    mov [ping_seq_wire], ax
    mov esi, icmp_buf
    mov ecx, 8 + PING_DATA
    call net_cksum
    mov [icmp_buf + 2], ax
    mov eax, [ping_dst]
    mov esi, icmp_buf
    mov ecx, 8 + PING_DATA
    mov dl, IP_ICMP
    call ip_output
    jc .no
    mov edx, [ticks]
    add edx, PING_WAIT
.w:
    cmp byte [ping_got], 0
    jne .yes
    cmp [ticks], edx
    jae .no
    call net_pump
    jmp .w
.yes:
    clc
    ret
.no:
    stc
    ret

; ping <ip> — four echoes
cmd_ping_run:
.sp:
    cmp byte [esi], ' '
    jne .go
    inc esi
    jmp .sp
.go:
    call ip_aton
    jc .bad
    mov [ping_dst], eax
    xor ebx, ebx
    mov ecx, 1
.seq:
    push ebx
    push ecx
    call ping_one
    pop ecx
    pop ebx
    jc .next
    inc ebx
.next:
    inc ecx
    cmp ecx, 4
    jbe .seq
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, [lstr + LS_NET_OF4 * 4]
    jmp lputs_nl
.bad:
    mov esi, [lstr + LS_NET_BADADDR * 4]
    jmp lputs_nl

; ifconfig [ip mask gw] — show or set the guest address (1.9.11)
cmd_ifconfig_run:
    cmp byte [esi], 0
    je .show
    call next_word              ; esi = ip, edi = rest
    push edi
    call ip_aton
    pop esi
    jc .bad
    mov [ifc_ip], eax
    cmp byte [esi], 0
    je .bad
    call next_word
    push edi
    call ip_aton
    pop esi
    jc .bad
    mov [ifc_mask], eax
    cmp byte [esi], 0
    je .bad
    call next_word
    call ip_aton
    jc .bad
    mov [net_gw_ip], eax
    mov eax, [ifc_ip]
    mov [net_our_ip], eax
    mov eax, [ifc_mask]
    mov [net_netmask], eax
.show:
    mov esi, ifc_lab_ip
    call puts
    mov eax, [net_our_ip]
    call ip_ntoa
    mov al, 10
    call putc
    mov esi, ifc_lab_mask
    call puts
    mov eax, [net_netmask]
    call ip_ntoa
    mov al, 10
    call putc
    mov esi, ifc_lab_gw
    call puts
    mov eax, [net_gw_ip]
    call ip_ntoa
    mov al, 10
    jmp putc
.bad:
    mov esi, [lstr + LS_NET_BADADDR * 4]
    jmp lputs_nl

; eax = address: print dotted quad (no newline)
ip_ntoa:
    push eax
    push ebx
    push ecx
    mov ebx, eax
    mov ecx, 4
.o:
    movzx eax, bl
    shr ebx, 8
    call itoa
    mov esi, num_buf
    call puts
    dec ecx
    jz .d
    mov al, '.'
    call putc
    jmp .o
.d:
    pop ecx
    pop ebx
    pop eax
    ret

; bare ifconfig (no arguments): same as show
cmd_ifconfig_show:
    mov esi, ifc_empty
    jmp cmd_ifconfig_run

ifc_empty db 0
ifc_lab_ip db 'inet ', 0
ifc_lab_mask db 'mask ', 0
ifc_lab_gw db 'gw ', 0
align 4
ifc_ip dd 0
ifc_mask dd 0

net_lo_ip   db 127, 0, 0, 1
net_gw_ip   db 10, 0, 2, 2
net_netmask db 255, 255, 255, 0
ip_zmac     times 6 db 0
ip_dmac     times 6 db 0
ip_proto    db 0
ping_got    db 0
align 2
ip_ident    dw 0
ping_id_wire dw 0
ping_seq_wire dw 0
align 4
ip_dst      dd 0
ip_src      dd 0
ip_plen     dd 0
ip_pay      dd 0
ip_tot      dd 0
ip_if       dd 0
ip_smac     dd 0
ping_dst    dd 0
icmp_buf    times ICMP_MAX db 0
