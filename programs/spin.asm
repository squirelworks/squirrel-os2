; spin — checks preemption (1.1). Original code.
; run spin
; The program starts a second process in its own image, then spins
; without yielding or making a system call until that process has
; printed. With a cooperative scheduler the second process cannot run
; until the spin gives up, so the result line says FAIL.
%include "sqx.inc"
SQX_HEADER main

SPIN_LIMIT equ 1 << 30          ; several seconds of spinning in QEMU

main:
    mov eax, SYS_SPAWN
    mov ebx, second
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .nospawn
    mov [child], eax
    mov ecx, SPIN_LIMIT
.spin:
    cmp byte [done], 0          ; set by the second process
    jne .ran
    dec ecx
    jnz .spin
    mov ebx, m_fail
    jmp .finish
.ran:
    mov ebx, m_pass
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

; runs only if the scheduler takes the CPU away from the spin
second:
    mov eax, SYS_PUTS
    mov ebx, m_second
    int 0x80
    mov byte [done], 1
    xor eax, eax
    ret

m_second db 'spin: second process ran', 10, 0
m_pass db 'preempt: PASS', 10, 0
m_fail db 'preempt: FAIL (the second process waited for the spin)', 10, 0
m_nospawn db 'spin: spawn failed', 10, 0

SQX_BSS
child resd 1
done resb 1
SQX_END
