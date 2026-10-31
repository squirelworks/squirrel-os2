; thread — checks the thread primitive (1.1). Original code.
; run thread
; SYS_SPAWN with an entry in the program's own image starts a thread: a
; second process that shares the program's address space (kernel/processes.md).
; Both the program and the thread add STEPS to one counter in that memory,
; yielding as they go so the two take turns. If the memory is shared, the
; counter ends at 2 * STEPS.
%include "sqx.inc"
SQX_HEADER main

STEPS equ 1000

main:
    mov eax, SYS_SPAWN
    mov ebx, worker
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .nospawn
    mov [child], eax
    call worker                 ; this side does the same work
    mov eax, SYS_WAIT
    mov ebx, [child]
    int 0x80
    cmp eax, STEPS              ; the thread's own count, as its exit code
    jne .fail
    cmp dword [counter], 2 * STEPS
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
.nospawn:
    mov eax, SYS_PUTS
    mov ebx, m_nospawn
    int 0x80
    mov eax, 1
    ret

; adds STEPS to the shared counter, yielding every 100; returns STEPS
worker:
    push esi
    xor esi, esi
.step:
    inc dword [counter]         ; one instruction, so a timer switch cannot split it
    inc esi
    mov eax, esi
    xor edx, edx
    mov ecx, 100
    div ecx
    test edx, edx
    jnz .next
    mov eax, SYS_YIELD
    int 0x80
.next:
    cmp esi, STEPS
    jb .step
    mov eax, esi
    pop esi
    ret

m_pass db 'thread: PASS', 10, 0
m_fail db 'thread: FAIL (the counter is not shared)', 10, 0
m_nospawn db 'thread: spawn failed', 10, 0

SQX_BSS
counter resd 1
child resd 1
SQX_END
