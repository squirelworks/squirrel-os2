; hello — smallest SQX program: greets and echoes its argument.
; Original code. run hello [text]
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, SYS_PUTS
    mov ebx, msg
    int 0x80
    mov esi, [esp+4]            ; argument string
    cmp byte [esi], 0
    je .done
    mov eax, SYS_PUTS
    mov ebx, argmsg
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, esi
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
.done:
    xor eax, eax                ; exit code 0
    ret

msg db 'Hello from a loaded program!', 10, 0
argmsg db 'Argument: ', 0

SQX_BSS
SQX_END
