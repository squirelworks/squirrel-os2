; Squirrel-OS/2 — SYS_NET numbers and address helpers for programs (3.0)
; Original code. Include after SQX_HEADER (it holds code):
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     %include "net.inc"
;
; See documentation/kernel/network.md (SYS_NET).

SYS_NET     equ 45
NET_RESOLVE equ 0               ; ecx = name -> address, or -1
NET_CONNECT equ 1               ; ecx = address, edx = port -> 0, -1, -2 busy
NET_SEND    equ 2               ; ecx = bytes, edx = length -> length, or -1
NET_RECV    equ 3               ; ecx = buffer, edx = size -> bytes, 0 closed, -2 nothing yet
NET_CLOSE   equ 4
NET_INFO    equ 5               ; ecx = 28-byte block
NET_SET     equ 6               ; ecx = 20-byte block -> 0, -1
NET_DHCP    equ 7               ; -> 0, -1

; NET_INFO block
NI_IP       equ 0
NI_MASK     equ 4
NI_GW       equ 8
NI_DNS      equ 12
NI_DNSPORT  equ 16
NI_MAC      equ 18
NI_FLAGS    equ 24              ; bit 0 card, bit 1 DHCP; bits 16-31 lease minutes
NI_SIZE     equ 28

; eax = address (first octet in the low byte), edi = buffer -> the dotted
; quad, zero-terminated; edi points at the zero. Keeps the other registers.
net_ntoa:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, eax
    mov ecx, 4
.o:
    movzx eax, bl
    shr ebx, 8
    call net_utoa
    dec ecx
    jz .d
    mov byte [edi], '.'
    inc edi
    jmp .o
.d:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; esi = text -> eax = the address and esi past it, CF if it is not four
; numbers 0..255 with dots. Stops at a space, a zero or a ':'.
net_aton:
    push ebx
    push ecx
    push edx
    push edi
    xor ebx, ebx                ; the address, built from the top octet down
    mov ecx, 4
.oct:
    xor eax, eax
    xor edx, edx                ; digits seen
.dig:
    movzx edi, byte [esi]
    cmp edi, '0'
    jb .end
    cmp edi, '9'
    ja .end
    imul eax, eax, 10
    lea eax, [eax + edi - '0']
    cmp eax, 255
    ja .bad
    inc esi
    inc edx
    jmp .dig
.end:
    test edx, edx
    jz .bad
    shrd ebx, eax, 8
    dec ecx
    jz .last
    cmp byte [esi], '.'
    jne .bad
    inc esi
    jmp .oct
.last:
    mov al, [esi]
    test al, al
    jz .ok
    cmp al, ' '
    je .ok
    cmp al, ':'
    je .ok
    cmp al, 13
    je .ok
    cmp al, 10
    je .ok
.bad:
    pop edi
    pop edx
    pop ecx
    pop ebx
    stc
    ret
.ok:
    mov eax, ebx
    pop edi
    pop edx
    pop ecx
    pop ebx
    clc
    ret

; eax = unsigned number, edi = buffer -> decimal text, zero-terminated;
; edi points at the zero. Keeps the other registers.
net_utoa:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.o:
    pop eax
    add al, '0'
    mov [edi], al
    inc edi
    loop .o
    mov byte [edi], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret
