; Squirrel-OS/2 — DNS resolver (3.0)
; Included from pm.asm. Original code, from RFC 1035.
;
; dns_resolve turns a host name into an IPv4 address: a dotted quad is
; read as it is, "localhost" is 127.0.0.1, an answer given before comes
; from an eight-name cache, and anything else is asked of the DNS server
; (net_dns_ip:net_dns_port, QEMU's 10.0.2.3:53 until DHCP or `dns` says
; otherwise) with one A query, recursion desired, sent twice at most.
; The first A record of the answer is used; CNAME records before it are
; stepped over. See documentation/kernel/network.md.

DNS_PORT    equ 53
DNS_LPORT   equ 5353                ; our end of the query
DNS_WAIT    equ 200                 ; two seconds for each answer
DNS_TRIES   equ 2
DNS_NAMEMAX equ 63                  ; the longest name we ask about
DNS_CACHE   equ 8
DNS_CENT    equ 68                  ; cache entry: name (64), address

; esi = ASCIIZ host name -> CF clear and eax = its address, or CF set
; (dns_why = 1 the server said no such name, 2 no answer, 3 a bad name).
; Keeps the other registers.
dns_resolve:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov byte [dns_why], 3
    cmp byte [esi], 0
    je .fail
    push esi
    call ip_aton
    pop esi
    jnc .ok
    mov edi, dns_localhost
    call dns_streqi
    jne .notlocal
    mov eax, 0x0100007F
    jmp .ok
.notlocal:
    call dns_cache_find
    jnc .ok
    call dns_build                  ; ecx = query length, or CF
    jc .fail
    mov [dns_qlen], ecx
    mov [dns_name], esi
    mov byte [dns_why], 2
    mov ebp, DNS_TRIES
.try:
    mov byte [dns_state], 0
    mov byte [dns_busy], 1
    mov eax, [net_dns_ip]
    movzx edx, word [net_dns_port]
    shl edx, 16
    mov dx, [dns_lport]
    mov esi, dns_q
    mov ecx, [dns_qlen]
    call udp_send_raw
    jc .next
    mov edx, [ticks]
    add edx, DNS_WAIT
.w:
    call net_pump
    cmp byte [dns_state], 0
    jne .answered
    cmp [ticks], edx
    jb .w
.next:
    dec ebp
    jnz .try
    mov byte [dns_busy], 0
    jmp .fail
.answered:
    mov byte [dns_busy], 0
    cmp byte [dns_state], 1
    jne .nx
    mov eax, [dns_addr]
    mov esi, [dns_name]
    call dns_cache_put
    jmp .ok
.nx:
    mov byte [dns_why], 1
.fail:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    stc
    ret
.ok:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret

; esi = name. Writes the query into dns_q with a new id.
; -> ecx = its length, or CF if a label is empty or longer than 63 or
; the name is longer than DNS_NAMEMAX.
dns_build:
    push eax
    push esi
    push edi
    inc word [dns_id]
    mov ax, [dns_id]
    add ax, [ticks]
    mov [dns_qid], ax
    mov edi, dns_q
    cld
    stosw                           ; id
    mov ax, 0x0001                  ; flags 01 00: recursion desired
    stosw
    mov ax, 0x0100                  ; one question
    stosw
    xor eax, eax
    stosd                           ; no answers, no authority
    stosw                           ; no additional
    xor ecx, ecx                    ; the whole name's length
.label:
    mov ebx, edi                    ; where this label's length goes
    inc edi
    xor edx, edx
.ch:
    mov al, [esi]
    test al, al
    jz .endlabel
    cmp al, '.'
    je .endlabel
    stosb
    inc esi
    inc edx
    inc ecx
    cmp ecx, DNS_NAMEMAX
    ja .bad
    jmp .ch
.endlabel:
    test edx, edx
    jz .bad
    cmp edx, 63
    ja .bad
    mov [ebx], dl
    cmp byte [esi], 0
    je .end
    inc esi                         ; the dot
    inc ecx
    cmp byte [esi], 0               ; "name." ends like "name"
    jne .label
.end:
    xor al, al
    stosb
    mov ax, 0x0100                  ; type A
    stosw
    stosw                           ; class IN
    mov ecx, edi
    sub ecx, dns_q
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

; esi = the UDP payload of an answer, ecx = its length. Sets dns_state
; to 1 (dns_addr holds the address) or 2 (no such name, or no A record).
dns_input:
    cmp ecx, 12
    jb .r
    mov eax, [net_rx + ETH_HDR + 12]
    cmp eax, [net_dns_ip]
    jne .r
    mov ax, [esi]
    cmp ax, [dns_qid]
    jne .r
    test byte [esi + 2], 0x80       ; QR: an answer
    jz .r
    lea edi, [esi + ecx]            ; the end
    mov [dns_end], edi
    mov [dns_msg], esi
    mov al, [esi + 3]
    and al, 0x0F                    ; RCODE
    jnz .no
    movzx ebx, byte [esi + 6]       ; answers
    shl ebx, 8
    mov bl, [esi + 7]
    movzx edx, byte [esi + 4]       ; questions
    shl edx, 8
    mov dl, [esi + 5]
    add esi, 12
.q:
    test edx, edx
    jz .ans
    call dns_skipname
    jc .no
    add esi, 4                      ; type, class
    dec edx
    jmp .q
.ans:
    test ebx, ebx
    jz .no
    call dns_skipname
    jc .no
    lea eax, [esi + 10]
    cmp eax, [dns_end]
    ja .no
    movzx ecx, byte [esi + 8]       ; data length
    shl ecx, 8
    mov cl, [esi + 9]
    lea eax, [esi + 10 + ecx]
    cmp eax, [dns_end]
    ja .no
    cmp word [esi], 0x0100          ; type A
    jne .other
    cmp word [esi + 2], 0x0100      ; class IN
    jne .other
    cmp ecx, 4
    jne .other
    mov eax, [esi + 10]
    mov [dns_addr], eax
    mov byte [dns_state], 1
    ret
.other:                             ; a CNAME or anything else: the next one
    lea esi, [esi + 10 + ecx]
    dec ebx
    jmp .ans
.no:
    mov byte [dns_state], 2
.r:
    ret

; esi = a name in the message -> esi just after it, CF if it runs past
; the end. A pointer (two bytes, 11xxxxxx) ends the name.
dns_skipname:
.l:
    cmp esi, [dns_end]
    jae .bad
    movzx eax, byte [esi]
    test al, al
    jz .z
    cmp al, 0xC0
    jae .ptr
    cmp al, 63
    ja .bad
    lea esi, [esi + eax + 1]
    jmp .l
.ptr:
    add esi, 2
    jmp .chk
.z:
    inc esi
.chk:
    cmp esi, [dns_end]
    ja .bad
    clc
    ret
.bad:
    stc
    ret

; esi, edi = ASCIIZ names -> ZF set if equal, letters in any case
dns_streqi:
    push eax
    push esi
    push edi
.l:
    mov al, [esi]
    mov ah, [edi]
    call dns_lower
    xchg al, ah
    call dns_lower
    cmp al, ah
    jne .o
    test al, al
    jz .o
    inc esi
    inc edi
    jmp .l
.o:
    pop edi
    pop esi
    pop eax
    ret

dns_lower:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r:
    ret

; esi = name -> CF clear and eax = the cached address, or CF
dns_cache_find:
    push ecx
    push edi
    mov edi, dns_cache
    xor ecx, ecx
.l:
    cmp byte [edi], 0
    je .n
    call dns_streqi
    je .hit
.n:
    add edi, DNS_CENT
    inc ecx
    cmp ecx, DNS_CACHE
    jb .l
    pop edi
    pop ecx
    stc
    ret
.hit:
    mov eax, [edi + 64]
    pop edi
    pop ecx
    clc
    ret

; esi = name, eax = address: keeps it, round robin over the slots
dns_cache_put:
    pushad
    movzx edi, byte [dns_turn]
    inc byte [dns_turn]
    and byte [dns_turn], DNS_CACHE - 1
    imul edi, edi, DNS_CENT
    add edi, dns_cache
    mov [edi + 64], eax
    mov ecx, 63
    cld
.c:
    lodsb
    stosb
    test al, al
    jz .d
    loop .c
    mov byte [edi], 0
.d:
    popad
    ret

; forget every cached answer
dns_flush:
    push eax
    push ecx
    push edi
    mov edi, dns_cache
    mov ecx, DNS_CACHE * DNS_CENT
    xor eax, eax
    cld
    rep stosb
    pop edi
    pop ecx
    pop eax
    ret

; host <name> — print the address of a name
cmd_host_run:
.sp:
    cmp byte [esi], ' '
    jne .go
    inc esi
    jmp .sp
.go:
    call dns_resolve
    jc .no
    push eax
    call puts                       ; the name
    mov esi, dns_m_is
    call puts
    pop eax
    call ip_ntoa
    mov al, 10
    jmp putc
.no:
    mov esi, [lstr + LS_NET_NOHOST * 4]
    cmp byte [dns_why], 1
    je .say
    mov esi, [lstr + LS_NET_BADADDR * 4]
    cmp byte [dns_why], 3
    je .say
    mov esi, [lstr + LS_NET_NOREPLY * 4]
.say:
    jmp lputs_nl

; dns            show the DNS server
; dns <ip> [port] set it (the port is for a test server; 53 by default)
cmd_dns_run:
    cmp byte [esi], 0
    je .show
    call next_word
    push edi
    call ip_aton
    pop esi
    jc .bad
    mov ecx, DNS_PORT
    cmp byte [esi], 0
    je .set
    push eax
    call tcp_port
    mov ecx, eax
    pop eax
    jc .bad
.set:
    mov [net_dns_ip], eax
    mov [net_dns_port], cx
    call dns_flush
.show:
    mov esi, dns_m_server
    call puts
    mov eax, [net_dns_ip]
    call ip_ntoa
    cmp word [net_dns_port], DNS_PORT
    je .nl
    mov al, ':'
    call putc
    movzx eax, word [net_dns_port]
    call itoa
    mov esi, num_buf
    call puts
.nl:
    mov al, 10
    jmp putc
.bad:
    mov esi, [lstr + LS_NET_BADADDR * 4]
    jmp lputs_nl

cmd_dns_show:
    mov esi, ifc_empty
    jmp cmd_dns_run

dns_localhost db 'localhost', 0
dns_m_is    db ' is ', 0
dns_m_server db 'dns ', 0
net_dns_ip  db 10, 0, 2, 3          ; QEMU user network's resolver
dns_busy    db 0
dns_state   db 0
dns_why     db 0
dns_turn    db 0
align 2
net_dns_port dw DNS_PORT
dns_lport   dw DNS_LPORT
dns_id      dw 0
dns_qid     dw 0
align 4
dns_qlen    dd 0
dns_name    dd 0
dns_addr    dd 0
dns_end     dd 0
dns_msg     dd 0
dns_q       times 12 + DNS_NAMEMAX + 2 + 4 + 4 db 0
dns_cache   times DNS_CACHE * DNS_CENT db 0
