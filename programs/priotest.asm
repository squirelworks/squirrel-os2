; priotest — checks priority scheduling (1.9.9). Original code.
; run priotest
; The program raises its priority, starts a lower-priority child, and
; spins without yielding. The child must not run until the parent drops
; its priority. With plain round-robin the child would run during the
; spin (as spin.asm shows for equal priorities).
%include "sqx.inc"
SQX_HEADER main

SPIN_LIMIT equ 1 << 28

main:
    mov eax, SYS_SETPRIO
    mov ebx, 3                  ; high
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
    mov ecx, SPIN_LIMIT
.highspin:
    cmp byte [flag], 0
    jne .early                  ; child ran while we were high: FAIL
    dec ecx
    jnz .highspin
    mov eax, SYS_SETPRIO
    mov ebx, 0                  ; below the child's default of 1
    int 0x80
    mov ecx, SPIN_LIMIT
.lowspin:
    cmp byte [flag], 0
    jne .ok
    dec ecx
    jnz .lowspin
    mov ebx, m_fail_late
    jmp .finish
.ok:
    mov ebx, m_pass
    jmp .finish
.early:
    mov ebx, m_fail_early
.finish:
    push ebx
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

; default priority 1: must wait until the parent drops to 0
low:
    mov eax, SYS_SETPRIO
    mov ebx, 1
    int 0x80
    mov byte [flag], 1
    xor eax, eax
    ret

m_pass db 'prio: PASS', 10, 0
m_fail_early db 'prio: FAIL (low ran while high held the CPU)', 10, 0
m_fail_late db 'prio: FAIL (low never ran after the drop)', 10, 0
m_nospawn db 'prio: spawn failed', 10, 0
m_bad db 'prio: setprio failed', 10, 0

SQX_BSS
child resd 1
flag resb 1
SQX_END
