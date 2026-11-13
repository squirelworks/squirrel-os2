; Squirrel-OS/2 — SYS_NET: names, TCP and settings for programs (3.0)
; Included from pm.asm. Original code.
;
; One system call, SYS_NET (37), with the operation in ebx, as SYS_GUI.
; Programs get the resolver, the kernel's TCP connection (one at a time,
; owned by the program that opened it until it closes it or ends) and
; the interface settings. See documentation/kernel/network.md.

NET_RESOLVE equ 0                   ; ecx = ASCIIZ name -> address, or -1
NET_CONNECT equ 1                   ; ecx = address, edx = port -> 0, -1 no answer, -2 busy
NET_SEND    equ 2                   ; ecx = bytes, edx = length -> length, or -1
NET_RECV    equ 3                   ; ecx = buffer, edx = size -> bytes, 0 closed, -2 nothing yet
NET_CLOSE   equ 4                   ; -> 0, or -1 when it is not the caller's
NET_INFO    equ 5                   ; ecx = 28-byte block (below) -> 0
NET_SET     equ 6                   ; ecx = 20-byte block -> 0, -1 bad (gateway off the subnet)
NET_DHCP    equ 7                   ; -> 0 configured, -1 no answer or no card
NET_OPS     equ 8

NET_RWAIT   equ 300                 ; NET_RECV waits up to three seconds

; NET_INFO block: +0 address, +4 mask, +8 gateway, +12 DNS server,
; +16 DNS port (word), +18 MAC (6 bytes), +24 flags: bit 0 a card is
; there, bit 1 the settings came from DHCP; bits 16-31 the lease in
; minutes (65535 at most).
; NET_SET block: +0 address, +4 mask, +8 gateway, +12 DNS server,
; +16 DNS port (0 = 53).

sys_net:
    cmp ebx, NET_OPS
    jae .bad
    jmp [net_ops + ebx * 4]
.bad:
    or eax, -1
    ret

net_ops:
    dd net_op_resolve, net_op_connect, net_op_send, net_op_recv
    dd net_op_close, net_op_info, net_op_set, net_op_dhcp

; ebx = operation, ecx/edx = its arguments -> CF if a pointer is not the
; ring-3 caller's (sys_uargs, UA_NET)
net_uargs:
    pushad
    cmp ebx, NET_RESOLVE
    je .str
    cmp ebx, NET_SEND
    je .cd
    cmp ebx, NET_RECV
    je .cd
    cmp ebx, NET_INFO
    je .info
    cmp ebx, NET_SET
    jne .ok
    mov esi, ecx
    mov ecx, 20
    jmp .range
.info:
    mov esi, ecx
    mov ecx, 28
    jmp .range
.str:
    mov esi, ecx
    call ua_str
    jc .bad
    jmp .ok
.cd:
    mov esi, ecx
    mov ecx, edx
.range:
    call ua_range
    jc .bad
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

net_op_resolve:
    mov esi, ecx
    call dns_resolve
    jnc .r
    or eax, -1
.r:
    ret

; -> eax = the caller's pid
net_pid:
    mov eax, [proc_cur]
    mov eax, [eax + PCB_PID]
    ret

; CF clear when the connection is free: closed, or its program is gone
net_tcp_free:
    cmp byte [tcp_state], 0
    je .yes
    mov ebx, [tcp_owner]
    call proc_find
    test edi, edi
    jz .gone
    cmp dword [edi + PCB_STATE], P_ZOMBIE
    je .gone
    stc
    ret
.gone:
    mov byte [tcp_state], 0
.yes:
    clc
    ret

net_op_connect:
    push ecx
    push edx
    call net_tcp_free
    pop edx
    pop ecx
    jnc .free
    mov eax, -2
    ret
.free:
    test edx, edx
    jz .bad
    cmp edx, 65535
    ja .bad
    call net_pid
    mov [tcp_owner], eax
    mov eax, ecx
    call tcp_connect
    jc .bad
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

; CF clear when the caller owns the open connection
net_mine:
    cmp byte [tcp_state], 0
    je .no
    push eax
    call net_pid
    cmp eax, [tcp_owner]
    pop eax
    jne .no
    clc
    ret
.no:
    stc
    ret

net_op_send:
    call net_mine
    jc .bad
    cmp byte [tcp_gotfin], 0        ; they closed: nothing more goes
    jne .bad
    push edx
    mov esi, ecx
    mov ecx, edx
    call tcp_send
    pop eax
    jc .bad
    ret
.bad:
    or eax, -1
    ret

net_op_recv:
    push eax
    call net_pid
    cmp eax, [tcp_owner]
    pop eax
    jne .bad
    mov edi, ecx
    mov ecx, edx
    mov edx, [ticks]
    add edx, NET_RWAIT
.l:
    call net_pump
    cmp dword [tcp_len], 0
    jne .take
    cmp byte [tcp_state], 2
    jne .closed                     ; reset, or never open
    cmp byte [tcp_gotfin], 0
    jne .closed
    cmp [ticks], edx
    jae .none
    pushad                          ; let the others run while we wait
    call proc_idle
    popad
    jmp .l
.take:
    call tcp_take
    ret
.closed:
    xor eax, eax
    ret
.none:
    mov eax, -2
    ret
.bad:
    or eax, -1
    ret

net_op_close:
    call net_pid
    cmp eax, [tcp_owner]
    jne .bad
    call tcp_close
    mov dword [tcp_len], 0
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

net_op_info:
    mov edi, ecx
    mov eax, [net_our_ip]
    mov [edi], eax
    mov eax, [net_netmask]
    mov [edi + 4], eax
    mov eax, [net_gw_ip]
    mov [edi + 8], eax
    mov eax, [net_dns_ip]
    mov [edi + 12], eax
    mov ax, [net_dns_port]
    mov [edi + 16], ax
    mov eax, [ne_mac]
    mov [edi + 18], eax
    mov ax, [ne_mac + 4]
    mov [edi + 22], ax
    xor eax, eax
    cmp byte [ne_up], 0
    je .f1
    or eax, 1
.f1:
    cmp byte [net_dhcp_on], 0
    je .f2
    or eax, 2
.f2:
    push eax
    mov eax, [net_lease]
    xor edx, edx
    mov ecx, 60
    div ecx
    cmp eax, 65535
    jbe .lm
    mov eax, 65535
.lm:
    shl eax, 16
    pop edx
    or eax, edx
    mov [edi + 24], eax
    xor eax, eax
    ret

net_op_set:
    mov esi, ecx
    mov eax, [esi + 8]              ; the gateway must be on the subnet (2.0.2)
    xor eax, [esi]
    and eax, [esi + 4]
    jnz .bad
    mov eax, [esi]
    test eax, eax
    jz .bad
    mov [net_our_ip], eax
    mov eax, [esi + 4]
    mov [net_netmask], eax
    mov eax, [esi + 8]
    mov [net_gw_ip], eax
    mov eax, [esi + 12]
    mov [net_dns_ip], eax
    mov ax, [esi + 16]
    test ax, ax
    jnz .p
    mov ax, DNS_PORT
.p:
    mov [net_dns_port], ax
    mov byte [net_dhcp_on], 0
    call dns_flush
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

net_op_dhcp:
    call dhcp_run
    sbb eax, eax                    ; CF -> -1
    ret
