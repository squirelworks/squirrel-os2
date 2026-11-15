; Squirrel-OS/2 — DHCP client (3.0)
; Included from pm.asm. Original code, from RFC 2131 / RFC 2132.
;
; dhcp_run asks the network for an address: DISCOVER (broadcast from
; 0.0.0.0:68 to 255.255.255.255:67), the first OFFER, REQUEST for it,
; then ACK. The ACK's address, subnet mask (option 1), router (3), DNS
; server (6) and lease time (51) become the interface's settings. A NAK,
; or no answer after two tries of DHCP_WAIT, leaves the old settings.
; While it runs, udp_input hands datagrams for port 68 to dhcp_input,
; and ip_input accepts frames addressed to someone else (the offer goes
; to the address being offered). See documentation/kernel/network.md.

DHCP_SPORT  equ 67                  ; the server's port
DHCP_CPORT  equ 68                  ; ours
DHCP_WAIT   equ 300                 ; three seconds for each answer
DHCP_TRIES  equ 2
DHCP_MAGIC  equ 0x63538263          ; 63 82 53 63 on the wire
DHCP_OPTS   equ 240                 ; options start here in a message
DHCP_MSGLEN equ 300                 ; what we send (BOOTP's minimum)

; message types (option 53)
DHCPDISCOVER equ 1
DHCPOFFER   equ 2
DHCPREQUEST equ 3
DHCPACK     equ 5
DHCPNAK     equ 6

; -> CF clear and the interface configured, or CF set (no card, or no
; server answered, or it said no). Keeps every register.
dhcp_run:
    pushad
    cmp byte [ne_up], 0
    je .fail
    mov eax, [net_our_ip]           ; put back if this fails
    mov [dhcp_old], eax
    mov dword [net_our_ip], 0       ; RFC 2131: ask from 0.0.0.0
    mov eax, [ticks]
    xor eax, 0x5153AC0D             ; 'SQ' and a little noise
    mov [dhcp_xid], eax
    mov byte [dhcp_busy], 1
    mov dword [dhcp_yi], 0
    mov dword [dhcp_server], 0
    mov ebp, DHCP_TRIES
.discover:
    mov byte [dhcp_got], 0
    mov byte [dhcp_want], DHCPOFFER
    mov al, DHCPDISCOVER
    call dhcp_send
    call dhcp_wait
    jnc .offered
    dec ebp
    jnz .discover
    jmp .undo
.offered:
    mov ebp, DHCP_TRIES
.request:
    mov byte [dhcp_got], 0
    mov byte [dhcp_want], DHCPACK
    mov al, DHCPREQUEST
    call dhcp_send
    call dhcp_wait
    jnc .acked
    cmp byte [dhcp_got], DHCPNAK
    je .undo
    dec ebp
    jnz .request
    jmp .undo
.acked:
    mov byte [dhcp_busy], 0
    mov eax, [dhcp_yi]
    mov [net_our_ip], eax
    mov eax, [dhcp_mask]
    test eax, eax
    jnz .m
    mov eax, 0x00FFFFFF             ; no option 1: 255.255.255.0
.m:
    mov [net_netmask], eax
    mov eax, [dhcp_router]
    test eax, eax
    jz .nogw                        ; no router: keep the old gateway
    mov [net_gw_ip], eax
.nogw:
    mov eax, [dhcp_dns]
    test eax, eax
    jz .nodns
    mov [net_dns_ip], eax
    mov word [net_dns_port], DNS_PORT
.nodns:
    mov eax, [dhcp_lease]
    mov [net_lease], eax
    mov byte [net_dhcp_on], 1
    call dns_flush                  ; another network: old answers may be wrong
    popad
    clc
    ret
.undo:
    mov eax, [dhcp_old]
    mov [net_our_ip], eax
.fail:
    mov byte [dhcp_busy], 0
    popad
    stc
    ret

; Pump until dhcp_input saw the message type in dhcp_want (CF clear),
; a NAK (CF set, dhcp_got = DHCPNAK), or the wait ran out (CF set).
dhcp_wait:
    mov edx, [ticks]
    add edx, DHCP_WAIT
.w:
    call net_pump
    mov al, [dhcp_got]
    cmp al, [dhcp_want]
    je .ok
    cmp al, DHCPNAK
    je .no
    cmp [ticks], edx
    jb .w
.no:
    stc
    ret
.ok:
    clc
    ret

; al = message type. Builds a BOOTP request with the DHCP options and
; broadcasts it.
dhcp_send:
    push eax
    mov edi, dhcp_msg
    mov ecx, DHCP_MSGLEN
    xor eax, eax
    cld
    rep stosb
    mov byte [dhcp_msg + 0], 1      ; op: request
    mov byte [dhcp_msg + 1], 1      ; Ethernet
    mov byte [dhcp_msg + 2], 6      ; address length
    mov eax, [dhcp_xid]
    mov [dhcp_msg + 4], eax
    mov word [dhcp_msg + 10], 0x0080 ; flags: broadcast the answer (80 00)
    mov esi, ne_mac
    mov edi, dhcp_msg + 28          ; chaddr
    mov ecx, 6
    rep movsb
    mov dword [dhcp_msg + 236], DHCP_MAGIC
    mov edi, dhcp_msg + DHCP_OPTS
    pop eax
    mov ah, al
    mov al, 53                      ; message type
    stosb
    mov al, 1
    stosb
    mov al, ah
    stosb
    cmp ah, DHCPREQUEST
    jne .list
    mov al, 50                      ; the address offered
    stosb
    mov al, 4
    stosb
    mov eax, [dhcp_yi]
    stosd
    mov al, 54                      ; the server that offered it
    stosb
    mov al, 4
    stosb
    mov eax, [dhcp_server]
    stosd
.list:
    mov esi, dhcp_params
    mov ecx, dhcp_params_end - dhcp_params
    rep movsb
    mov al, 255                     ; end
    stosb
    mov eax, 0xFFFFFFFF
    mov edx, DHCP_CPORT | (DHCP_SPORT << 16)
    mov esi, dhcp_msg
    mov ecx, DHCP_MSGLEN
    jmp udp_send_raw

; esi = the UDP payload of a datagram for port 68, ecx = its length.
; A reply (op 2) with our transaction and hardware address is read; an
; OFFER is kept only while one is wanted, an ACK only for the offer.
dhcp_input:
    cmp ecx, DHCP_OPTS + 1
    jb .r
    cmp byte [esi], 2
    jne .r
    mov eax, [esi + 4]
    cmp eax, [dhcp_xid]
    jne .r
    mov eax, [esi + 28]
    cmp eax, [ne_mac]
    jne .r
    mov ax, [esi + 32]
    cmp ax, [ne_mac + 4]
    jne .r
    cmp dword [esi + 236], DHCP_MAGIC
    jne .r
    ; read the options into dhcp_t*
    xor eax, eax
    mov [dhcp_ttype], al
    mov [dhcp_tmask], eax
    mov [dhcp_trouter], eax
    mov [dhcp_tdns], eax
    mov [dhcp_tserver], eax
    mov [dhcp_tlease], eax
    lea edi, [esi + ecx]            ; the end
    push esi
    add esi, DHCP_OPTS
.opt:
    cmp esi, edi
    jae .done
    mov al, [esi]
    cmp al, 255
    je .done
    inc esi
    test al, al                     ; pad
    jz .opt
    cmp esi, edi
    jae .done
    movzx ecx, byte [esi]           ; length
    inc esi
    lea edx, [esi + ecx]
    cmp edx, edi
    ja .done
    cmp al, 53
    jne .o1
    mov ah, [esi]
    mov [dhcp_ttype], ah
    jmp .skip
.o1:
    cmp ecx, 4
    jb .skip
    mov edx, [esi]
    cmp al, 1
    jne .o3
    mov [dhcp_tmask], edx
    jmp .skip
.o3:
    cmp al, 3
    jne .o6
    mov [dhcp_trouter], edx
    jmp .skip
.o6:
    cmp al, 6
    jne .o51
    mov [dhcp_tdns], edx
    jmp .skip
.o51:
    cmp al, 51
    jne .o54
    bswap edx
    mov [dhcp_tlease], edx
    jmp .skip
.o54:
    cmp al, 54
    jne .skip
    mov [dhcp_tserver], edx
.skip:
    add esi, ecx
    jmp .opt
.done:
    pop esi
    mov al, [dhcp_ttype]
    cmp al, DHCPNAK
    jne .notnak
    cmp byte [dhcp_want], DHCPACK
    jne .r
    mov [dhcp_got], al
    ret
.notnak:
    cmp al, [dhcp_want]
    jne .r
    cmp byte [dhcp_got], 0          ; the first answer wins
    jne .r
    mov edx, [esi + 16]             ; yiaddr
    test edx, edx
    jz .r
    cmp al, DHCPACK
    jne .keep
    cmp edx, [dhcp_yi]              ; the ACK must be for what we asked
    jne .r
.keep:
    mov [dhcp_yi], edx
    mov eax, [dhcp_tserver]
    test eax, eax
    jnz .sv
    mov eax, [net_rx + ETH_HDR + 12] ; no option 54: whoever sent it
.sv:
    mov [dhcp_server], eax
    mov eax, [dhcp_tmask]
    mov [dhcp_mask], eax
    mov eax, [dhcp_trouter]
    mov [dhcp_router], eax
    mov eax, [dhcp_tdns]
    mov [dhcp_dns], eax
    mov eax, [dhcp_tlease]
    mov [dhcp_lease], eax
    mov al, [dhcp_ttype]
    mov [dhcp_got], al
.r:
    ret

; dhcp — ask for an address, then show the settings like ifconfig
cmd_dhcp_run:
    call dhcp_run
    jc .no
    mov esi, dhcp_m_ok
    call puts
    jmp cmd_ifconfig_show
.no:
    mov esi, [lstr + LS_NET_NODHCP * 4]
    jmp lputs_nl

dhcp_m_ok   db 'dhcp: bound', 10, 0
dhcp_params db 55, 4, 1, 3, 6, 51  ; ask for mask, router, DNS, lease
dhcp_params_end:

dhcp_busy   db 0
dhcp_got    db 0
dhcp_want   db 0
dhcp_ttype  db 0
net_dhcp_on db 0                    ; the settings came from DHCP
align 4
dhcp_xid    dd 0
dhcp_old    dd 0
dhcp_yi     dd 0
dhcp_server dd 0
dhcp_mask   dd 0
dhcp_router dd 0
dhcp_dns    dd 0
dhcp_lease  dd 0
dhcp_tmask  dd 0
dhcp_trouter dd 0
dhcp_tdns   dd 0
dhcp_tserver dd 0
dhcp_tlease dd 0
net_lease   dd 0                    ; seconds, from the last ACK
dhcp_msg    times DHCP_MSGLEN db 0
