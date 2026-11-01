; Squirrel-OS/2 — UDP (1.9.7)
; Included from pm.asm. Original code.
;
; Four sockets. A port belongs to one process. net_sendto and
; net_recvfrom are the system calls. A datagram to 127.0.0.1 comes
; back through loopback. See documentation/kernel/network.md.

UDP_NSOCK   equ 4
UDP_Q       equ 4                   ; datagrams waiting on one socket
UDP_MAX     equ 256                 ; payload bytes in one datagram
UDP_EPORT   equ -1                  ; that port is already bound
UDP_ENONE   equ -2                  ; nothing arrived

UDP_PORT    equ 0                   ; host order, 0 = free
UDP_OWNER   equ 4                   ; pid
UDP_HEAD    equ 8
UDP_TAIL    equ 12
UDP_COUNT   equ 16
UDP_SLOTS   equ 20                  ; UDP_Q page addresses
UDP_SIZE    equ UDP_SLOTS + UDP_Q * 4

; A queued datagram's page: source address, source port, length, bytes.
UDP_SRC     equ 0
UDP_SPORT   equ 4
UDP_LEN     equ 8
UDP_DATA    equ 12

; edx = port -> CF clear and ebx = its socket, or CF set
udp_lookup:
    push ecx
    mov ebx, udp_tab
    xor ecx, ecx
.l:
    cmp dword [ebx + UDP_PORT], edx
    je .hit
    add ebx, UDP_SIZE
    inc ecx
    cmp ecx, UDP_NSOCK
    jb .l
    stc
    jmp .o
.hit:
    clc
.o:
    pop ecx
    ret

; ebx = socket: drop its datagrams and forget the port
udp_clear:
    push eax
    push ecx
    push edx
.q:
    cmp dword [ebx + UDP_COUNT], 0
    je .z
    mov edx, [ebx + UDP_HEAD]
    mov eax, [ebx + UDP_SLOTS + edx * 4]
    push edx
    call pg_free
    pop edx
    inc edx
    cmp edx, UDP_Q
    jb .h
    xor edx, edx
.h:
    mov [ebx + UDP_HEAD], edx
    dec dword [ebx + UDP_COUNT]
    jmp .q
.z:
    mov dword [ebx + UDP_PORT], 0
    pop edx
    pop ecx
    pop eax
    ret

; A socket whose process is gone gives the port back.
udp_reap:
    push ebx
    push ecx
    push edx
    push edi
    mov ebx, udp_tab
    xor ecx, ecx
.l:
    cmp dword [ebx + UDP_PORT], 0
    je .n
    mov edx, [ebx + UDP_OWNER]
    push ebx
    push ecx
    mov ebx, edx
    call proc_find
    pop ecx
    pop ebx
    test edi, edi
    jz .free
    cmp dword [edi + PCB_STATE], P_ZOMBIE
    jne .n
.free:
    call udp_clear
.n:
    add ebx, UDP_SIZE
    inc ecx
    cmp ecx, UDP_NSOCK
    jb .l
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; edx = port, 0 picks one from 4096 up.
; -> CF clear, ebx = socket; CF set if another process has the port,
; or no socket is free.
udp_bind:
    push edx
    call udp_reap
    pop edx
    test edx, edx
    jnz .named
    mov edx, 4096
.ep:
    call udp_lookup
    jc udp_claim
    inc edx
    cmp edx, 4096 + 32
    jb .ep
    stc
    ret
.named:
    call udp_lookup
    jc udp_claim
    mov eax, [proc_cur]
    mov eax, [eax + PCB_PID]
    cmp eax, [ebx + UDP_OWNER]
    je .ours
    stc
    ret
.ours:
    clc
    ret

; edx = port that lookup says is free. -> ebx = socket, CF if the table is full
udp_claim:
    push ecx
    mov ebx, udp_tab
    xor ecx, ecx
.l:
    cmp dword [ebx + UDP_PORT], 0
    je .got
    add ebx, UDP_SIZE
    inc ecx
    cmp ecx, UDP_NSOCK
    jb .l
    pop ecx
    stc
    ret
.got:
    mov [ebx + UDP_PORT], edx
    mov eax, [proc_cur]
    mov eax, [eax + PCB_PID]
    mov [ebx + UDP_OWNER], eax
    xor eax, eax
    mov [ebx + UDP_HEAD], eax
    mov [ebx + UDP_TAIL], eax
    mov [ebx + UDP_COUNT], eax
    pop ecx
    clc
    ret

; ebx = socket. Datagram described by udp_srcip, udp_sport, esi = bytes, ecx = length.
; CF set if the queue is full, the datagram is too long, or no page is free.
udp_queue:
    cmp dword [ebx + UDP_COUNT], UDP_Q
    jae .no
    cmp ecx, UDP_MAX
    ja .no
    push ebx
    push ecx
    push esi
    call pg_alloc
    pop esi
    pop ecx
    pop ebx
    test eax, eax
    jz .no
    mov edi, eax
    push eax
    mov eax, [udp_srcip]
    mov [edi + UDP_SRC], eax
    mov eax, [udp_sport]
    mov [edi + UDP_SPORT], eax
    mov [edi + UDP_LEN], ecx
    add edi, UDP_DATA
    cld
    rep movsb
    pop eax
    mov edx, [ebx + UDP_TAIL]
    mov [ebx + UDP_SLOTS + edx * 4], eax
    inc edx
    cmp edx, UDP_Q
    jb .t
    xor edx, edx
.t:
    mov [ebx + UDP_TAIL], edx
    inc dword [ebx + UDP_COUNT]
    clc
    ret
.no:
    stc
    ret

; ebx = socket, edi = buffer, ecx = its size.
; -> eax = bytes copied, udp_srcip and udp_sport filled. CF if none is waiting.
udp_take:
    cmp dword [ebx + UDP_COUNT], 0
    je .no
    push ecx
    push edi
    mov edx, [ebx + UDP_HEAD]
    mov esi, [ebx + UDP_SLOTS + edx * 4]
    mov eax, [esi + UDP_SRC]
    mov [udp_srcip], eax
    mov eax, [esi + UDP_SPORT]
    mov [udp_sport], eax
    mov eax, [esi + UDP_LEN]
    cmp ecx, eax
    jbe .fit
    mov ecx, eax
.fit:
    mov [udp_got], eax
    push esi
    add esi, UDP_DATA
    cld
    rep movsb
    pop eax
    push edx
    call pg_free
    pop edx
    inc edx
    cmp edx, UDP_Q
    jb .h
    xor edx, edx
.h:
    mov [ebx + UDP_HEAD], edx
    dec dword [ebx + UDP_COUNT]
    mov eax, [udp_got]
    pop edi
    pop ecx
    clc
    ret
.no:
    stc
    ret

; esi = UDP packet, ecx = its length, eax = source, edx = destination.
; -> ax = the checksum of the pseudo-header plus the packet.
; A packet that already carries a correct checksum comes back as 0.
; The caller stores the result, and stores FFFF when that result is 0.
udp_csum:
    push ecx
    push esi
    push edi
    mov edi, udp_pseudo
    cld
    stosd
    mov eax, edx
    stosd
    xor al, al
    stosb
    mov al, IP_UDP
    stosb
    mov eax, ecx
    xchg al, ah
    stosw
    mov edi, udp_pseudo + 12
    rep movsb
    pop edi
    pop esi
    pop ecx
    push ecx
    mov esi, udp_pseudo
    add ecx, 12
    call net_cksum
    pop ecx
    ret

; ebx = IPv4 total length. The packet is in net_rx. Deliver it to the
; socket bound to the destination port, if there is one.
udp_input:
    mov eax, ebx
    sub eax, 20
    cmp eax, 8
    jb .r
    movzx ecx, byte [net_rx + ETH_HDR + 20 + 4]
    shl ecx, 8
    mov cl, [net_rx + ETH_HDR + 20 + 5]
    cmp ecx, 8
    jb .r
    cmp ecx, eax
    ja .r
    cmp ecx, 8 + UDP_MAX
    ja .r
    mov ax, [net_rx + ETH_HDR + 20 + 6]
    test ax, ax
    jz .nocheck
    push ecx
    mov eax, [net_rx + ETH_HDR + 12]
    mov edx, [net_rx + ETH_HDR + 16]
    mov esi, net_rx + ETH_HDR + 20
    call udp_csum
    pop ecx
    test ax, ax
    jnz .r                      ; a good packet sums to 0
.nocheck:
    movzx edx, byte [net_rx + ETH_HDR + 20 + 2]
    shl edx, 8
    mov dl, [net_rx + ETH_HDR + 20 + 3]
    call udp_lookup
    jc .r
    mov eax, [net_rx + ETH_HDR + 12]
    mov [udp_srcip], eax
    movzx eax, byte [net_rx + ETH_HDR + 20]
    shl eax, 8
    mov al, [net_rx + ETH_HDR + 20 + 1]
    mov [udp_sport], eax
    lea esi, [net_rx + ETH_HDR + 20 + 8]
    sub ecx, 8
    call udp_queue
.r:
    ret

; Block at ebx:
;   +0 destination address, +4 destination port, +6 local port (0 picks one),
;   +8 bytes, +12 length. -> eax = bytes sent, or -1.
sys_netsendto:
    mov eax, [ebx + 12]
    cmp eax, UDP_MAX
    ja .bad
    mov [udp_len], eax
    mov eax, [ebx]
    mov [udp_dst], eax
    movzx eax, word [ebx + 4]
    mov [udp_dport], eax
    movzx edx, word [ebx + 6]
    mov eax, [ebx + 8]
    mov [udp_pay], eax
    call udp_bind
    jc .bad
    mov eax, [ebx + UDP_PORT]
    mov [udp_sport], eax
    mov eax, [net_our_ip]
    cmp byte [udp_dst], 127
    jne .src
    mov eax, [net_lo_ip]
.src:
    mov [udp_src_fix], eax
    mov edi, udp_pkt
    cld
    mov eax, [udp_sport]
    xchg al, ah
    stosw
    mov eax, [udp_dport]
    xchg al, ah
    stosw
    mov eax, [udp_len]
    add eax, 8
    mov [udp_ulen], eax
    xchg al, ah
    stosw
    xor ax, ax
    stosw
    mov esi, [udp_pay]
    mov ecx, [udp_len]
    rep movsb
    mov eax, [udp_src_fix]
    mov edx, [udp_dst]
    mov ecx, [udp_ulen]
    mov esi, udp_pkt
    call udp_csum
    test ax, ax
    jnz .csum
    mov ax, 0xFFFF
.csum:
    mov [udp_pkt + 6], ax
    mov eax, [udp_dst]
    mov esi, udp_pkt
    mov ecx, [udp_ulen]
    mov dl, IP_UDP
    call ip_output
    jc .bad
    mov eax, [udp_len]
    ret
.bad:
    mov eax, UDP_EPORT
    ret

; Block at ebx:
;   +0 local port, +2 source port (written), +4 buffer, +8 size,
;   +12 source address (written), +16 how many ticks to wait (0 = do not wait).
; -> eax = bytes, -1 if the port is taken, -2 if nothing came.
sys_netrecvfrom:
    movzx edx, word [ebx]
    test edx, edx
    jz .bad
    mov [udp_user], ebx
    call udp_bind
    jc .bad
    mov [udp_sock], ebx
    call udp_recv_once
    jnc .got
    mov ebx, [udp_user]
    mov eax, [ebx + 16]
    test eax, eax
    jz .none
    mov edx, [ticks]
    add edx, eax
.w:
    call net_pump
    call udp_recv_once
    jnc .got
    cmp [ticks], edx
    jb .w
.none:
    mov eax, UDP_ENONE
    ret
.bad:
    mov eax, UDP_EPORT
    ret
.got:
    ret

; Copy one queued datagram into the user's block. CF if the socket is empty.
; Pumps nothing; the caller does that.
udp_recv_once:
    mov ebx, [udp_sock]
    mov edx, [udp_user]
    mov edi, [edx + 4]
    mov ecx, [edx + 8]
    call udp_take
    jc .no
    mov edx, [udp_user]
    mov ecx, [udp_srcip]
    mov [edx + 12], ecx
    mov ecx, [udp_sport]
    mov [edx + 2], cx
    clc
.no:
    ret

align 4
udp_tab     times UDP_NSOCK * UDP_SIZE db 0
udp_pkt     times 8 + UDP_MAX db 0
udp_srcip   dd 0
udp_sport   dd 0
udp_dst     dd 0
udp_dport   dd 0
udp_len     dd 0
udp_ulen    dd 0
udp_pay     dd 0
udp_got     dd 0
udp_user    dd 0
udp_sock    dd 0
udp_src_fix dd 0
udp_pseudo  times 12 + 8 + UDP_MAX db 0
