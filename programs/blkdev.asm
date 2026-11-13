; blkdev — block device check for the H.x disk drivers (OS2-HW).
; Original code. run blkdev NAME   (sd0, sd1, nv0, ud0, ...)
; Reads sector 0 (it must start with 'SQHW', as tools/regress.sh writes
; the test disk) and sector 100 ('S100'), writes a pattern to sector 5,
; reads it back and compares, then prints "blkdev: NAME PASS".
%include "sqx.inc"
SQX_HEADER main

main:
    mov esi, [esp+4]
.sp:
    cmp byte [esi], ' '
    jne .name
    inc esi
    jmp .sp
.name:
    cmp byte [esi], 0
    je .fail
    mov [name], esi
    mov eax, SYS_DEVFIND
    mov ebx, esi
    int 0x80
    cmp eax, -1
    je .fail
    mov [handle], eax
    ; sector 0 and sector 100 carry markers
    xor edx, edx
    call rd
    jc .fail
    cmp dword [buf], 'SQHW'
    jne .fail
    mov edx, 100
    call rd
    jc .fail
    cmp dword [buf], 'S100'
    jne .fail
    ; write a pattern to sector 5 and read it back
    mov edi, pat
    mov ecx, 128
    mov eax, 0x5A5A0005
.fill:
    stosd
    add eax, 0x01010101
    loop .fill
    mov eax, SYS_DEVWRITE
    mov ebx, [handle]
    mov ecx, pat
    mov edx, 5
    int 0x80
    cmp eax, 512
    jne .fail
    mov edi, buf
    mov ecx, 128
    xor eax, eax
    rep stosd
    mov edx, 5
    call rd
    jc .fail
    mov esi, pat
    mov edi, buf
    mov ecx, 128
    repe cmpsd
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, m_head
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, [name]
    int 0x80
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

; edx = sector -> buf, CF on error
rd:
    mov eax, SYS_DEVREAD
    mov ebx, [handle]
    mov ecx, buf
    int 0x80
    cmp eax, 512
    jne .e
    clc
    ret
.e:
    stc
    ret

m_head db 'blkdev: ', 0
m_pass db ' PASS', 10, 0
m_fail db 'blkdev: FAIL', 10, 0

SQX_BSS
name resd 1
handle resd 1
buf resb 512
pat resb 512
SQX_END
