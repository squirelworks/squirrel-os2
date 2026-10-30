; wc — counts lines, words and bytes of a file. Original code.
; run wc <file>
%include "sqx.inc"
SQX_HEADER main

main:
    mov esi, [esp+4]
    cmp byte [esi], 0
    je .usage
    mov eax, SYS_OPEN
    mov ebx, esi
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .missing
    mov [fd], eax
    xor ebp, ebp                ; 1 while inside a word
.chunk:
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    mov edx, BUFSIZE
    int 0x80
    test eax, eax
    jle .eof
    add [bytes], eax
    mov ecx, eax
    mov esi, buf
.ch:
    lodsb
    cmp al, 10
    jne .notnl
    inc dword [lines]
.notnl:
    cmp al, ' '
    jbe .space
    test ebp, ebp
    jnz .next
    inc ebp
    inc dword [words]
    jmp .next
.space:
    xor ebp, ebp
.next:
    loop .ch
    jmp .chunk
.eof:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    mov eax, [lines]
    call putnum
    mov eax, [words]
    call putnum
    mov eax, [bytes]
    call putnum
    mov eax, SYS_PUTS
    mov ebx, [esp+4]
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
    xor eax, eax
    ret
.usage:
    mov ebx, m_usage
    jmp .fail
.missing:
    mov ebx, m_missing
.fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; eax = unsigned number, printed followed by a space
putnum:
    mov edi, numbuf+11
    mov byte [edi], 0
    mov ecx, 10
.d:
    xor edx, edx
    div ecx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .d
    mov eax, SYS_PUTS
    mov ebx, edi
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, ' '
    int 0x80
    ret

m_usage db 'usage: run wc <file>', 10, 0
m_missing db 'wc: file not found', 10, 0

BUFSIZE equ 512
SQX_BSS
fd      resd 1
lines   resd 1
words   resd 1
bytes   resd 1
numbuf  resb 12
buf     resb BUFSIZE
SQX_END
