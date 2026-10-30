; devtest — uses devices by name through SYS_DEVFIND / SYS_DEVREAD /
; SYS_DEVWRITE (0.7.x). Original code. run devtest
%include "sqx.inc"
SQX_HEADER main

main:
    ; write to the console device
    mov eax, SYS_DEVFIND
    mov ebx, n_con
    int 0x80
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov eax, SYS_DEVWRITE
    mov ecx, m_hello
    mov edx, m_hello_len
    int 0x80
    cmp eax, m_hello_len
    jne .fail
    ; read the data disk's first sector: an SQFS superblock
    mov eax, SYS_DEVFIND
    mov ebx, n_hd1
    int 0x80
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov eax, SYS_DEVREAD
    mov ecx, sector
    xor edx, edx
    int 0x80
    cmp eax, 512
    jne .fail
    cmp dword [sector], 'SQFS'
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, m_sqfs
    int 0x80
    ; the boot disk refuses writes from programs
    mov eax, SYS_DEVFIND
    mov ebx, n_hd0
    int 0x80
    cmp eax, -1
    je .fail
    mov ebx, eax
    mov eax, SYS_DEVWRITE
    mov ecx, sector
    xor edx, edx
    int 0x80
    cmp eax, -1
    jne .fail
    ; unknown names and handles are refused
    mov eax, SYS_DEVFIND
    mov ebx, n_none
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_DEVREAD
    mov ebx, 99
    mov ecx, sector
    mov edx, 1
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, m_pass
    int 0x80
    xor eax, eax
    ret
.fail:
    mov eax, SYS_PUTS
    mov ebx, m_fail
    int 0x80
    mov eax, 1
    ret

n_con db 'con', 0
n_hd0 db 'hd0', 0
n_hd1 db 'hd1', 0
n_none db 'nope', 0
m_hello db 'devtest: written through con', 10
m_hello_len equ $ - m_hello
m_sqfs db 'devtest: hd1 holds SQFS', 10, 0
m_pass db 'devtest: PASS', 10, 0
m_fail db 'devtest: FAIL', 10, 0

SQX_BSS
sector resb 512
SQX_END
