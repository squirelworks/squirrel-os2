; agetest — checks priority aging (2.0.2). Original code.
; run agetest
; The program raises itself to priority 3, starts a child at priority 0,
; and spins without yielding. Before 2.0.2 the child never ran while the
; parent spun (starvation). With aging, the child has waited AGE_TICKS
; (two seconds) and gets a slice anyway, so it sets the flag while the
; parent is still at priority 3.
%include "sqx.inc"
SQX_HEADER main

SPIN_ROUNDS equ 64              ; each round is 1 << 26 iterations

main:
    mov eax, SYS_SETPRIO
    mov ebx, 3
    int 0x80
    test eax, eax
    jnz .badcall
    mov eax, SYS_SPAWN
    mov ebx, low
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .nospawn
    mov [child], eax
    mov edx, SPIN_ROUNDS
.round:
    mov ecx, 1 << 26
.spin:
    cmp byte [flag], 0
    jne .ok                     ; the starved child ran: aging works
    dec ecx
    jnz .spin
    dec edx
    jnz .round
    mov ebx, m_fail
    jmp .finish
.ok:
    mov ebx, m_pass
.finish:
    push ebx
    mov eax, SYS_SETPRIO        ; let the child finish if it has not
    xor ebx, ebx
    int 0x80
    mov eax, SYS_WAIT
    mov ebx, [child]
    int 0x80
    pop ebx
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
.badcall:
    mov eax, SYS_PUTS
    mov ebx, m_bad
    int 0x80
    mov eax, 1
    ret

; priority 0, below everything: may run only through aging
low:
    mov eax, SYS_SETPRIO
    xor ebx, ebx
    int 0x80
    mov byte [flag], 1
    xor eax, eax
    ret

m_pass db 'age: PASS', 10, 0
m_fail db 'age: FAIL (priority 0 starved)', 10, 0
m_nospawn db 'age: spawn failed', 10, 0
m_bad db 'age: setprio failed', 10, 0

SQX_BSS
child resd 1
flag resb 1
SQX_END
