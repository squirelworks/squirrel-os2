; drvtest — registers a null character device at run time (1.9.12).
; run drvtest
; SYS_DEVREG adds a ready char device under a name; writes to it are
; discarded and reads return zeros. devices must then list it.
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, SYS_DEVREG
    mov ebx, name
    int 0x80
    test eax, eax
    jnz .fail_reg
    mov eax, SYS_DEVFIND
    mov ebx, name
    int 0x80
    cmp eax, 0
    jl .fail_find
    mov [handle], eax
    mov eax, SYS_DEVWRITE
    mov ebx, [handle]
    mov ecx, payload
    mov edx, 4
    int 0x80
    cmp eax, 4
    jne .fail_io
    mov dword [buf], 0xFFFFFFFF
    mov eax, SYS_DEVREAD
    mov ebx, [handle]
    mov ecx, buf
    mov edx, 4
    int 0x80
    cmp eax, 4
    jne .fail_io
    cmp dword [buf], 0
    jne .fail_io
    mov ebx, m_pass
    jmp .print
.fail_reg:
    mov ebx, m_reg
    jmp .print
.fail_find:
    mov ebx, m_find
    jmp .print
.fail_io:
    mov ebx, m_io
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

name db 'null', 0
payload db 'xxxx'
m_pass db 'drv: PASS', 10, 0
m_reg db 'drv: FAIL (register)', 10, 0
m_find db 'drv: FAIL (find)', 10, 0
m_io db 'drv: FAIL (read/write)', 10, 0

SQX_BSS
handle resd 1
buf resd 1
SQX_END
