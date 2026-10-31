; waitcycle — a wait that could never end is refused (KB-16). Original code.
; run waitcycle
; 1. Waits for pid 0, the shell, which is itself waiting for this program.
;    The shell is waiting before this program runs, so the order is fixed:
;    this wait must return -1.
; 2. Starts a thread that waits for this program while this program waits
;    for the thread. Which of the two waits comes second depends on whether
;    the timer preempts this program between the spawn and its wait, and
;    no system call can tell when the other side has started waiting. So
;    the check takes either order: exactly the wait that closes the cycle
;    must be refused.
;    - The thread's wait came second (the usual order): it returns -1, the
;      thread exits with REFUSED, and this program's wait returns that.
;    - This program's wait came second: it returns -1 at once, while the
;      thread still waits for this program. It is woken when the program
;      exits, so it does not hang either.
; Before the fix, either cycle panicked the kernel.
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
    mov eax, SYS_WAIT
    int 0x80
    cmp eax, REFUSED            ; the thread closed the cycle
    je .pass
    cmp eax, -1                 ; we closed it: the thread is waiting for us
    jne .fail
.pass:
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

; exits with REFUSED if its wait returned -1, otherwise with what it got
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
