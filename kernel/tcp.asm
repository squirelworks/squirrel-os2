; Squirrel-OS/2 — one TCP client (1.9.8)
; Included from pm.asm. Original code.
;
; One connection. Data is accepted only in order. A segment is sent
; again once when nothing comes back. fetch asks a server for a page.
; See documentation/kernel/network.md.

T_FIN       equ 1
T_SYN       equ 2
T_RST       equ 4
T_PSH       equ 8
T_ACK       equ 16
TCP_WIN     equ 1024
TCP_WAIT    equ 100                 ; one second, then one retry
TCP_READ    equ 300                 ; how long fetch waits for the page
TCP_IDLE    equ 50                  ; stop sooner once bytes have arrived
TCP_BUF     equ 1024
TCP_LOCAL   equ 41000

; eax = value, edi advanced: four bytes, most significant first
tcp_w32:
    push eax
    xchg al, ah
    rol eax, 16
    xchg al, ah
    stosd
    pop eax
    ret

; esi advanced -> eax
tcp_r32:
    push ecx
    movzx eax, byte [esi]
    movzx ecx, byte [esi + 1]
    shl eax, 8
    or eax, ecx
    movzx ecx, byte [esi + 2]
    shl eax, 8
    or eax, ecx
    movzx ecx, byte [esi + 3]
    shl eax, 8
    or eax, ecx
    add esi, 4
    pop ecx
    ret

; Adds the words at esi (ecx bytes) into ebx.
tcp_addsum:
    push eax
    push ecx
    push esi
.w:
    cmp ecx, 1
    jb .d
    je .odd
    movzx eax, word [esi]
    add ebx, eax
    add esi, 2
    sub ecx, 2
    jmp .w
.odd:
    movzx eax, byte [esi]
    add ebx, eax
.d:
    pop esi
    pop ecx
    pop eax
    ret

; esi = TCP segment, ecx = its length, eax = source, edx = destination.
; -> ax = checksum. A segment that already has the right checksum returns 0.
tcp_csum:
    push ebx
    push ecx
    push esi
    push edi
    mov edi, tcp_pseudo
    cld
    stosd
    mov eax, edx
    stosd
    xor al, al
    stosb
    mov al, IP_TCP
    stosb
    mov eax, ecx
    xchg al, ah
    stosw
    xor ebx, ebx
    mov esi, tcp_pseudo
    mov ecx, 12
    call tcp_addsum
    pop edi
    pop esi
    pop ecx
    push ecx
    push esi
    call tcp_addsum
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

; edi = where to write, al = flags, esi = data (if ecx > 0), ecx = data length.
; Uses the current sequence and acknowledgement numbers. -> eax = length written.
tcp_build:
    push ebx
    push ecx
    push eax
    cld
    movzx eax, word [tcp_lport]
    xchg al, ah
    stosw
    movzx eax, word [tcp_rport]
    xchg al, ah
    stosw
    mov eax, [tcp_snd_seq]
    call tcp_w32
    mov eax, [tcp_rcv_nxt]
    call tcp_w32
    mov al, 0x50                    ; twenty-byte header, no options
    stosb
    pop eax
    stosb                           ; flags
    push eax
    mov ax, TCP_WIN
    xchg al, ah
    stosw
    xor ax, ax
    stosw                           ; checksum
    xor ax, ax
    stosw                           ; urgent
    pop eax
    pop ecx
    push ecx
    test ecx, ecx
    jz .nodata
    push esi
    rep movsb
    pop esi
.nodata:
    pop ecx
    add ecx, 20
    push ecx
    push edi
    mov eax, [net_our_ip]
    mov edx, [tcp_rip]
    mov esi, [tcp_built]
    call tcp_csum
    test ax, ax
    jnz .store
    mov ax, 0xFFFF
.store:
    mov edi, [tcp_built]
    mov [edi + 16], ax
    pop edi
    pop eax                         ; length
    pop ebx
    ret

; esi = segment, ecx = length
tcp_xmit:
    push eax
    push edx
    mov eax, [tcp_rip]
    mov dl, IP_TCP
    call ip_output
    pop edx
    pop eax
    ret

; CF clear when an acknowledgement covers tcp_snd_nxt, or a reset arrived
; (tcp_rst is then set). CF set on a timeout.
tcp_wait:
    mov byte [tcp_acked], 0
    mov ebx, [ticks]
    add ebx, TCP_WAIT
.w:
    cmp byte [tcp_rst], 0
    jne .bad
    cmp byte [tcp_acked], 0
    jne .ok
    cmp [ticks], ebx
    jae .bad
    call net_pump
    jmp .w
.ok:
    clc
    ret
.bad:
    stc
    ret

; Send tcp_seg, and once more if nobody answers. CF set if it still fails.
tcp_round:
    mov esi, tcp_seg
    mov ecx, [tcp_seglen]
    call tcp_xmit
    call tcp_wait
    jnc .ok
    mov esi, tcp_seg
    mov ecx, [tcp_seglen]
    call tcp_xmit
    call tcp_wait
.ok:
    ret

; eax = address, edx = port. CF set if the handshake does not finish.
tcp_connect:
    mov [tcp_rip], eax
    mov [tcp_rport], dx
    mov word [tcp_lport], TCP_LOCAL
    mov eax, [ticks]
    shl eax, 4
    add eax, 0x10000
    mov [tcp_iss], eax
    mov [tcp_snd_seq], eax
    mov dword [tcp_snd_nxt], eax
    mov dword [tcp_rcv_nxt], 0
    mov dword [tcp_len], 0
    mov byte [tcp_state], 1
    mov byte [tcp_rst], 0
    mov byte [tcp_gotfin], 0
    mov byte [tcp_synok], 0
    mov byte [tcp_acked], 0
    mov dword [tcp_built], tcp_seg
    mov edi, tcp_seg
    mov al, T_SYN
    xor ecx, ecx
    call tcp_build
    mov [tcp_seglen], eax
    inc dword [tcp_snd_nxt]         ; the SYN takes one sequence number
    call tcp_round
    jc .no
    cmp byte [tcp_synok], 0
    je .no
    mov byte [tcp_state], 2
    mov eax, [tcp_snd_nxt]
    mov [tcp_snd_seq], eax
    mov dword [tcp_built], tcp_ack
    mov edi, tcp_ack
    mov al, T_ACK
    xor ecx, ecx
    call tcp_build
    mov esi, tcp_ack
    mov ecx, eax
    call tcp_xmit
    clc
    ret
.no:
    mov byte [tcp_state], 0
    stc
    ret

; esi = bytes, ecx = length. CF set if they are not acknowledged.
tcp_send:
    mov eax, [tcp_snd_nxt]
    mov [tcp_snd_seq], eax
    mov dword [tcp_built], tcp_seg
    mov edi, tcp_seg
    mov al, T_PSH | T_ACK
    call tcp_build
    mov [tcp_seglen], eax
    sub eax, 20
    add [tcp_snd_nxt], eax
    jmp tcp_round

; ebx = IPv4 total length. The segment is in net_rx.
tcp_input:
    cmp byte [tcp_state], 0
    je .r
    mov eax, [net_rx + ETH_HDR + 12]
    cmp eax, [tcp_rip]
    jne .r
    mov eax, ebx
    sub eax, 20
    cmp eax, 20
    jb .r
    mov [tcp_tlen], eax
    movzx edx, byte [net_rx + ETH_HDR + 20 + 2]
    shl edx, 8
    mov dl, [net_rx + ETH_HDR + 20 + 3]
    cmp dx, [tcp_lport]
    jne .r
    movzx edx, byte [net_rx + ETH_HDR + 20]
    shl edx, 8
    mov dl, [net_rx + ETH_HDR + 20 + 1]
    cmp dx, [tcp_rport]
    jne .r
    mov esi, net_rx + ETH_HDR + 20
    mov ecx, eax
    mov eax, [net_rx + ETH_HDR + 12]
    mov edx, [net_rx + ETH_HDR + 16]
    call tcp_csum
    test ax, ax
    jnz .r
    movzx eax, byte [net_rx + ETH_HDR + 20 + 12]
    shr al, 4
    movzx eax, al
    shl eax, 2
    cmp eax, 20
    jb .r
    cmp eax, [tcp_tlen]
    ja .r
    mov [tcp_hoff], eax
    mov esi, net_rx + ETH_HDR + 20 + 4
    call tcp_r32
    mov [tcp_segseq], eax
    call tcp_r32
    mov [tcp_theirack], eax
    mov al, [net_rx + ETH_HDR + 20 + 13]
    mov [tcp_flags], al
    test al, T_RST
    jz .norst
    mov byte [tcp_rst], 1
    mov byte [tcp_state], 0
    ret
.norst:
    test al, T_ACK
    jz .noack
    mov eax, [tcp_theirack]
    cmp eax, [tcp_snd_nxt]
    jne .noack
    mov byte [tcp_acked], 1
.noack:
    mov al, [tcp_flags]
    test al, T_SYN
    jz .nosyn
    cmp byte [tcp_state], 1
    jne .nosyn
    test al, T_ACK
    jz .nosyn
    cmp byte [tcp_acked], 0
    je .nosyn
    mov eax, [tcp_segseq]
    inc eax
    mov [tcp_rcv_nxt], eax
    mov byte [tcp_synok], 1
.nosyn:
    mov eax, [tcp_tlen]
    sub eax, [tcp_hoff]
    mov [tcp_plen], eax             ; payload bytes
    cmp byte [tcp_state], 2
    jb .ackout                      ; handshake ACK is sent by tcp_connect
    mov eax, [tcp_segseq]
    cmp eax, [tcp_rcv_nxt]
    jne .payload_done
    mov ecx, [tcp_plen]
    test ecx, ecx
    jz .fin
    mov eax, [tcp_len]
    mov edx, TCP_BUF
    sub edx, eax
    jbe .fin
    cmp ecx, edx
    jbe .fits
    mov ecx, edx
.fits:
    push ecx
    mov esi, net_rx + ETH_HDR + 20
    add esi, [tcp_hoff]
    mov edi, tcp_buf
    add edi, [tcp_len]
    cld
    rep movsb
    pop ecx
    add [tcp_len], ecx
    add [tcp_rcv_nxt], ecx
.fin:
    mov al, [tcp_flags]
    test al, T_FIN
    jz .ackout
    mov eax, [tcp_segseq]
    add eax, [tcp_plen]
    cmp eax, [tcp_rcv_nxt]
    jne .ackout
    inc dword [tcp_rcv_nxt]
    mov byte [tcp_gotfin], 1
.ackout:
    cmp byte [tcp_state], 2
    jb .r
    mov eax, [tcp_snd_nxt]
    mov [tcp_snd_seq], eax
    mov dword [tcp_built], tcp_ack
    mov edi, tcp_ack
    mov al, T_ACK
    xor ecx, ecx
    call tcp_build
    mov esi, tcp_ack
    mov ecx, eax
    call tcp_xmit
.r:
    ret
.payload_done:
    jmp .ackout

tcp_close:
    cmp byte [tcp_state], 2
    jne .z
    mov eax, [tcp_snd_nxt]
    mov [tcp_snd_seq], eax
    mov dword [tcp_built], tcp_seg
    mov edi, tcp_seg
    mov al, T_FIN | T_ACK
    xor ecx, ecx
    call tcp_build
    mov [tcp_seglen], eax
    inc dword [tcp_snd_nxt]
    call tcp_round
.z:
    mov byte [tcp_state], 0
    ret

; esi = decimal port -> eax = port, CF if it is not 1..65535
tcp_port:
    xor eax, eax
    xor ecx, ecx
.d:
    mov cl, [esi]
    cmp cl, '0'
    jb .end
    cmp cl, '9'
    ja .bad
    inc esi
    imul eax, eax, 10
    sub cl, '0'
    movzx ecx, cl
    add eax, ecx
    cmp eax, 65535
    ja .bad
    jmp .d
.end:
    cmp byte [esi], 0
    jne .bad
    test eax, eax
    jz .bad
    clc
    ret
.bad:
    stc
    ret

; fetch <ip> <port> <path>
cmd_fetch_run:
.sp:
    cmp byte [esi], ' '
    jne .go
    inc esi
    jmp .sp
.go:
    call next_word
    push edi
    call ip_aton
    pop esi
    jc .bad
    mov [tcp_fetch_ip], eax
    call next_word
    push edi                    ; the path
    call tcp_port
    pop esi
    jc .bad
    mov [tcp_fetch_port], ax
    cmp byte [esi], 0
    je .bad
    mov edi, tcp_req
    cld
    mov eax, 'GET '
    stosd
.pc:
    mov al, [esi]
    inc esi
    test al, al
    jz .pend
    cmp edi, tcp_req + 80
    jae .bad
    stosb
    jmp .pc
.pend:
    mov esi, tcp_http_tail
.tc:
    lodsb
    stosb
    test al, al
    jnz .tc
    dec edi                     ; the copied NUL
    sub edi, tcp_req
    mov [tcp_reqlen], edi
    mov eax, [tcp_fetch_ip]
    movzx edx, word [tcp_fetch_port]
    call tcp_connect
    jc .none
    mov esi, tcp_req
    mov ecx, [tcp_reqlen]
    call tcp_send
    jc .none_close
    mov ebx, [ticks]
    add ebx, TCP_READ
    mov edx, ebx
    mov dword [tcp_last], 0
.rd:
    call net_pump
    cmp byte [tcp_gotfin], 0
    jne .got
    cmp byte [tcp_rst], 0
    jne .got
    mov eax, [tcp_len]
    cmp eax, [tcp_last]
    je .same
    mov [tcp_last], eax
    mov edx, [ticks]
    add edx, TCP_IDLE
.same:
    cmp [ticks], ebx
    jae .got
    cmp [ticks], edx
    jb .rd
.got:
    call tcp_close
    cmp dword [tcp_len], 0
    je .none
    mov esi, tcp_buf
    mov edi, tcp_buf
    mov ecx, [tcp_len]
    cmp ecx, TCP_BUF
    jb .cr
    mov ecx, TCP_BUF
.cr:
    mov al, [esi]
    inc esi
    cmp al, 13                  ; HTTP ends lines with CR LF
    je .crnext
    stosb
.crnext:
    loop .cr
    cmp edi, tcp_buf
    je .none
    cmp byte [edi - 1], 10
    je .term
    mov byte [edi], 10
    inc edi
.term:
    mov byte [edi], 0
    mov esi, tcp_buf
    jmp puts
.none_close:
    call tcp_close
.none:
    mov esi, [lstr + LS_NET_NOREPLY * 4]
    jmp lputs_nl
.bad:
    mov esi, [lstr + LS_NET_BADADDR * 4]
    jmp lputs_nl

tcp_http_tail db ' HTTP/1.0', 13, 10, 13, 10, 0

tcp_state   db 0
tcp_rst     db 0
tcp_gotfin  db 0
tcp_synok   db 0
tcp_acked   db 0
tcp_flags   db 0
align 2
tcp_lport   dw 0
tcp_rport   dw 0
tcp_fetch_port dw 0
align 4
tcp_rip     dd 0
tcp_iss     dd 0
tcp_snd_nxt dd 0
tcp_snd_seq dd 0
tcp_rcv_nxt dd 0
tcp_len     dd 0
tcp_tlen    dd 0
tcp_hoff    dd 0
tcp_plen    dd 0
tcp_segseq  dd 0
tcp_theirack dd 0
tcp_seglen  dd 0
tcp_built   dd 0
tcp_fetch_ip dd 0
tcp_reqlen  dd 0
tcp_last    dd 0
tcp_pseudo  times 12 db 0
tcp_seg     times 128 db 0
tcp_ack     times 24 db 0
tcp_req     times 96 db 0
tcp_buf     times TCP_BUF db 0
