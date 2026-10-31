; fpu — checks that each process keeps its own x87 registers (1.0.1).
; Loads 12345 onto the FPU stack, runs a copy of itself that fills the
; stack with 7s and exits, waits for it, then reads its own value back.
; Original code. run fpu
%include "sqx.inc"
SQX_HEADER main

KNOWN equ 12345

main:
    mov esi, [esp+4]            ; argument string
    cmp byte [esi], 'c'         ; "clobber": the child's half
    je clobber
    fninit
    fild dword [known]
    mov eax, SYS_EXEC
    mov ebx, self
    mov ecx, childarg
    int 0x80
    test eax, eax
    js .failed
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    fistp dword [back]
    cmp dword [back], KNOWN
    jne .lost
    mov eax, SYS_PUTS
    mov ebx, m_ok
    int 0x80
    xor eax, eax
    ret
.lost:
    mov eax, SYS_PUTS
    mov ebx, m_bad
    int 0x80
    mov eax, 2
    ret
.failed:
    mov eax, SYS_PUTS
    mov ebx, m_fail
    int 0x80
    mov eax, 1
    ret

; fill all eight FPU registers with 7 and leave them there
clobber:
    fninit
    mov ecx, 8
.fill:
    fild dword [seven]
    loop .fill
    xor eax, eax
    ret

known dd KNOWN
seven dd 7
self db 'fpu', 0
childarg db 'clobber', 0
m_ok db 'fpu: PASS', 10, 0
m_bad db 'fpu: FAIL (value lost across a process switch)', 10, 0
m_fail db 'fpu: could not start a second copy', 10, 0

SQX_BSS
back resd 1
SQX_END
