; udptest — sends a UDP datagram to itself on 127.0.0.1 and reads it
; back, then checks that a second process cannot bind that port.
; Original code. run udptest
%include "sqx.inc"

PORT    equ 5000

SQX_HEADER main

main:
    mov word [rb], PORT
    mov word [rb + 2], 0
    mov dword [rb + 4], buf
    mov dword [rb + 8], 32
    mov dword [rb + 12], 0
    mov dword [rb + 16], 0          ; bind, do not wait
    mov eax, SYS_NETRECVFROM
    mov ebx, rb
    int 0x80
    cmp eax, -2
    jne .fail
    mov dword [sb], 0x0100007F      ; 127.0.0.1
    mov word [sb + 4], PORT
    mov word [sb + 6], PORT
    mov dword [sb + 8], msg
    mov dword [sb + 12], 5
    mov eax, SYS_NETSENDTO
    mov ebx, sb
    int 0x80
    cmp eax, 5
    jne .fail
    mov dword [rb + 16], 100
    mov eax, SYS_NETRECVFROM
    mov ebx, rb
    int 0x80
    cmp eax, 5
    jne .fail
    cmp dword [rb + 12], 0x0100007F
    jne .fail
    cmp word [rb + 2], PORT
    jne .fail
    mov esi, buf
    mov edi, msg
    mov ecx, 5
    cld
    repe cmpsb
    jne .fail
    mov eax, SYS_SPAWN
    mov ebx, other
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    test eax, eax
    jnz .fail
    mov ebx, m_pass
    jmp .say
.fail:
    mov ebx, m_fail
.say:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

; The port is ours. This process must be refused.
other:
    mov word [cb], PORT
    mov dword [cb + 4], buf
    mov dword [cb + 8], 32
    mov dword [cb + 16], 0
    mov eax, SYS_NETRECVFROM
    mov ebx, cb
    int 0x80
    cmp eax, -1
    jne .no
    xor eax, eax
    ret
.no:
    mov eax, 1
    ret

msg db 'udpok'
m_pass db 'udp: PASS', 10, 0
m_fail db 'udp: FAIL', 10, 0

align 4
sb  times 16 db 0
rb  times 20 db 0
cb  times 20 db 0

SQX_BSS
buf resb 32
SQX_END
