; wc — counts lines, words and bytes of a file. Original code.
; run wc <file>     a file
; run wc            its input (a pipe, < file, or the keyboard until Esc)
%include "sqx.inc"
SQX_HEADER main

main:
    mov esi, [esp+4]
    xor ebp, ebp                ; 1 while inside a word
    cmp byte [esi], 0
    je .stdin
    mov eax, SYS_OPEN
    mov ebx, esi
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .missing
    mov [fd], eax
.chunk:
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    mov edx, BUFSIZE
    int 0x80
    test eax, eax
    jle .eof
    mov ecx, eax
    mov esi, buf
.ch:
    lodsb
    call count
    loop .ch
    jmp .chunk
.stdin:
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1                 ; end of redirected input
    je .report
    cmp eax, 27                 ; Esc ends keyboard input
    je .report
    call count
    jmp .stdin
.eof:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
.report:
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
.missing:
    mov ebx, m_missing
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; al = next byte: updates the counts (ebp = inside a word)
count:
    inc dword [bytes]
    cmp al, 10
    jne .notnl
    inc dword [lines]
.notnl:
    cmp al, ' '
    jbe .space
    test ebp, ebp
    jnz .r
    inc ebp
    inc dword [words]
    ret
.space:
    xor ebp, ebp
.r:
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
