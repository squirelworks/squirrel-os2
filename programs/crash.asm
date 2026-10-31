; crash — touches memory that is not mapped. The page fault ends this
; program only; the shell carries on (0.6.1). Original code. run crash
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, SYS_PUTS
    mov ebx, msg
    int 0x80
    mov eax, [0xC0000000]       ; nothing is mapped up here
    xor eax, eax
    ret

msg db 'crash: reading unmapped memory...', 10, 0

SQX_BSS
SQX_END
