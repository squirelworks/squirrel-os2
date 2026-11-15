; lxcat — copies Linux stdin to stdout with read(0)/write(1) until
; end of input (P.2). Original code. Lines are prefixed with "lx: ".
;   echo acorns | run lxcat   ->  lx: acorns
; From the keyboard it ends at an empty line.
%include "lxelf.inc"
LX_ELF_HEADER _start

_start:
.line:
    mov eax, LX_READ
    xor ebx, ebx
    mov ecx, buf
    mov edx, 80
    int 0x80
    test eax, eax
    jle .done                       ; 0 = end of input, < 0 = error
    cmp eax, 1
    jne .out
    cmp byte [buf], 10
    je .done                        ; an empty line ends keyboard input
.out:
    mov esi, eax
    mov eax, LX_WRITE
    mov ebx, 1
    mov ecx, prefix
    mov edx, 4
    int 0x80
    mov eax, LX_WRITE
    mov ecx, buf
    mov edx, esi
    int 0x80
    jmp .line
.done:
    mov eax, LX_EXIT
    xor ebx, ebx
    int 0x80

prefix db 'lx: '
LX_ELF_BSS
buf resb 80
LX_ELF_END
