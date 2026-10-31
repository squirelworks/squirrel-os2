; errno — opens the file named by its argument and, if that fails, prints
; why with SYS_FSERROR (1.0.3): the same words the shell prints.
; Original code. run errno <name>
%include "sqx.inc"
SQX_HEADER main

main:
    mov esi, [esp+4]            ; argument string = the name
    mov eax, SYS_OPEN
    mov ebx, esi
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .why
    mov ebx, eax
    mov eax, SYS_CLOSE
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, m_opened
    int 0x80
    xor eax, eax
    ret
.why:
    mov eax, SYS_FSERROR
    mov ebx, reason
    mov ecx, 64
    int 0x80
    mov [code], eax
    mov eax, SYS_PUTS
    mov ebx, m_prefix
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, reason
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
    mov eax, [code]             ; exit code = the FE_* number
    ret

m_opened db 'errno: opened', 10, 0
m_prefix db 'errno: ', 0

SQX_BSS
reason resb 64
code resd 1
SQX_END
