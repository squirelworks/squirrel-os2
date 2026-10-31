; waitcycle — a wait that could never end is refused (KB-16). Original code.
; run waitcycle
; 1. Waits for pid 0, the shell, which is itself waiting for this program.
; 2. Starts a thread that waits for this program while this program waits
;    for the thread.
; Each closes a cycle of waits: with nobody left to run, the kernel used to
; panic. Both waits must now return -1 at once, and the thread's exit code
; must say its wait was refused.
%include "sqx.inc"
SQX_HEADER main

REFUSED equ 16

main:
    mov eax, SYS_GETPID
    int 0x80
    mov [self], eax
    mov eax, SYS_WAIT           ; 1. the shell waits for us
    xor ebx, ebx
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_SPAWN          ; 2. a thread that waits for us
    mov ebx, waiter
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WAIT           ; we wait first; its wait closes the cycle
    int 0x80
    cmp eax, REFUSED            ; the thread saw its wait refused
    jne .fail
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

; exits with REFUSED if its wait returned -1
waiter:
    mov eax, SYS_WAIT
    mov ebx, [self]
    int 0x80
    cmp eax, -1
    jne .r
    mov eax, REFUSED
.r:
    ret

m_pass db 'waitcycle: PASS', 10, 0
m_fail db 'waitcycle: FAIL', 10, 0

SQX_BSS
self resd 1
SQX_END
