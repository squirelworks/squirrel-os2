; nest — starts another program while it is itself running, waits for
; it, then checks its own memory survived. Both programs are linked at
; the same address; each has its own address space (0.6.1).
; Original code. run nest
%include "sqx.inc"
SQX_HEADER main

MARK equ 0x5EED1234

main:
    mov dword [mark], MARK
    mov eax, SYS_EXEC
    mov ebx, child
    mov ecx, childarg
    int 0x80
    test eax, eax
    js .failed
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    mov [code], eax
    mov eax, SYS_PUTS
    mov ebx, m_back
    int 0x80
    ; the child was loaded at our address: are we still ourselves?
    cmp dword [mark], MARK
    jne .clobbered
    cmp dword [PROG_BASE], 'SQX1'
    jne .clobbered
    mov eax, SYS_PUTS
    mov ebx, m_ok
    int 0x80
    xor eax, eax
    ret
.clobbered:
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

child db 'hello', 0
childarg db 'from nest', 0
m_back db 'nest: child finished', 10, 0
m_ok db 'nest: own memory intact', 10, 0
m_bad db 'nest: own memory CLOBBERED', 10, 0
m_fail db 'nest: could not start hello', 10, 0

SQX_BSS
mark resd 1
code resd 1
SQX_END
