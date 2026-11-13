; dbgtgt — a program for the debugger tests to trace (A.4). Original code.
; run dbgtgt [f|s|b]: f = page fault, s = spin forever, b = run an INT3
; The first instructions have fixed sizes: dbgtest steps through them.
%include "sqx.inc"
SQX_HEADER main

main:                           ; +0
    mov eax, 1                  ; +0, 5 bytes
    mov ebx, 2                  ; +5, 5 bytes
    add eax, ebx                ; +10, 2 bytes
here:                           ; +12: dbgtest's breakpoint
    mov ecx, eax                ; +12, 2 bytes
    mov [result], ecx
    mov esi, [esp+4]
    cmp byte [esi], 'f'
    je .fault
    cmp byte [esi], 's'
    je .spin
    cmp byte [esi], 'b'
    jne .out
    int3
.out:
    mov eax, SYS_PUTS
    mov ebx, msg
    int 0x80
    mov eax, [result]
    add eax, '0'
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
    mov eax, [result]
    ret
.fault:
    mov dword [0x00000010], eax ; kernel memory: a page fault
    jmp .out
.spin:
    inc dword [counter]
    jmp .spin

msg db 'dbgtgt result ', 0
result dd 0
counter dd 0
SQX_BSS
SQX_END
