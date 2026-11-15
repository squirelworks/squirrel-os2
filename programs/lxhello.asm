; lxhello — a Linux i386 static program (P.1). Original code.
; Uses only the Linux ABI: write(1, ...), write(2, ...) and exit(0).
; Checks argc/argv from the Linux initial stack and that its bss is zero.
; run lxhello [word]  ->  "Hello from Linux land! argc=N argv[0]=lxhello"
%include "lxelf.inc"
LX_ELF_HEADER _start

_start:
    mov eax, [esp]                  ; argc
    cmp eax, 1
    jb fail
    cmp eax, 2
    ja fail
    cmp dword [esp+eax*4+4], 0      ; argv[argc] must be NULL
    jne fail
    add al, '0'
    mov [argc_digit], al
    cmp dword [counter], 0          ; bss zeroed
    jne fail
    mov ecx, msg
    mov edx, msg_len
    call out1
    mov esi, [esp+4]                ; argv[0]
    call outz
    cmp dword [esp], 2
    jne .nl
    mov ecx, sep
    mov edx, 1
    call out1
    mov esi, [esp+8]                ; argv[1]
    call outz
.nl:
    mov ecx, nl
    mov edx, 1
    call out1
    mov eax, LX_WRITE               ; fd 2 goes to the console too
    mov ebx, 2
    mov ecx, okmsg
    mov edx, okmsg_len
    int 0x80
    cmp eax, okmsg_len
    jne fail
    mov eax, 77                     ; an unknown call must say -ENOSYS
    int 0x80
    cmp eax, -38
    jne fail
    mov eax, LX_EXIT
    xor ebx, ebx
    int 0x80
fail:
    mov eax, LX_WRITE
    mov ebx, 1
    mov ecx, badmsg
    mov edx, badmsg_len
    int 0x80
    mov eax, LX_EXIT_GROUP
    mov ebx, 1
    int 0x80

out1:                               ; write(1, ecx, edx)
    mov eax, LX_WRITE
    mov ebx, 1
    int 0x80
    ret

outz:                               ; writes the ASCIIZ string at esi
    mov ecx, esi
    xor edx, edx
.l: cmp byte [esi+edx], 0
    je .w
    inc edx
    jmp .l
.w: jmp out1

msg db 'Hello from Linux land! argc='
argc_digit db '?', ' argv[0]='
msg_len equ $ - msg
sep db ' '
nl db 10
okmsg db 'lxhello: PASS', 10
okmsg_len equ $ - okmsg
badmsg db 'lxhello: FAIL', 10
badmsg_len equ $ - badmsg
LX_ELF_BSS
counter resd 1
LX_ELF_END
