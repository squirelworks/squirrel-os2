; stackover — a stack overflow ends only the process it happens in
; (KB-17). Original code.
; run stackover
; Starts a thread that calls itself until its 8 KB stack runs into the
; guard page below it. The kernel reports "*** stack overflow" and ends
; the thread with exit code -1. This program then checks that the thread's
; wait returned -1 and that its own memory and stack are untouched.
; Before the fix the thread wrote over the next slot's stack, which
; belonged to this program, and crashed it.
%include "sqx.inc"
SQX_HEADER main

MARK equ 0x5EED5EED

main:
    mov dword [mark], MARK
    push dword MARK             ; one on our own stack as well
    mov eax, SYS_SPAWN
    mov ebx, deep
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    cmp eax, -1                 ; ended by the kernel
    jne .fail
    cmp dword [mark], MARK
    jne .fail
    cmp dword [esp], MARK
    jne .fail
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    add esp, 4
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

deep:
    call deep

m_pass db 'stackover: PASS', 10, 0
m_fail db 'stackover: FAIL', 10, 0

SQX_BSS
mark resd 1
SQX_END
