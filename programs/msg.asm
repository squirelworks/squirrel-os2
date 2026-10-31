; msg — checks the message queues (1.2). Original code.
; run msg
; 1. Fills its own queue: MSG_QMAX sends succeed, the next returns -2,
;    and the messages come back in the order they were sent.
; 2. A send to a pid nobody has returns -1.
; 3. Sends the four bytes "ping" to a child, which prints them.
%include "sqx.inc"
SQX_HEADER main

QMAX equ 8                      ; MSG_QMAX in kernel/msg.asm

main:
    mov eax, SYS_GETPID
    int 0x80
    mov [self], eax
    xor esi, esi                ; 1. fill our own queue with 0..QMAX-1
.fill:
    mov eax, SYS_SEND
    mov ebx, [self]
    mov ecx, esi
    int 0x80
    test eax, eax
    jnz .fail
    inc esi
    cmp esi, QMAX
    jb .fill
    mov eax, SYS_SEND           ; one more: the queue is full
    mov ebx, [self]
    mov ecx, esi
    int 0x80
    cmp eax, -2
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, m_full
    int 0x80
    xor esi, esi                ; drain it, oldest first
.drain:
    mov eax, SYS_RECV
    int 0x80
    cmp eax, esi
    jne .fail
    inc esi
    cmp esi, QMAX
    jb .drain
    mov eax, SYS_SEND           ; 2. nobody has this pid
    mov ebx, 0x7FFFFFFF
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_SPAWN          ; 3. a child that prints what it receives
    mov ebx, child
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .fail
    mov [kid], eax
    mov eax, SYS_SEND
    mov ebx, [kid]
    mov ecx, 'ping'
    int 0x80
    test eax, eax
    jnz .fail
    mov eax, SYS_WAIT
    mov ebx, [kid]
    int 0x80
    test eax, eax
    jnz .fail
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

child:
    mov eax, SYS_RECV           ; waits until the parent has sent
    int 0x80
    mov [text], eax             ; the four bytes, then a newline
    mov eax, SYS_PUTS
    mov ebx, m_got
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, text
    int 0x80
    xor eax, eax
    ret

m_full db 'msg: queue full (-2)', 10, 0
m_got db 'msg: child got ', 0
m_pass db 'msg: PASS', 10, 0
m_fail db 'msg: FAIL', 10, 0
text db 0, 0, 0, 0, 10, 0

SQX_BSS
self resd 1
kid resd 1
SQX_END
