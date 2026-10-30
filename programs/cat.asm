; cat — prints one or more files. Original code.
; run cat <file> [file ...]
; run cat           copies its input (a pipe, < file, or the keyboard until Esc)
%include "sqx.inc"
SQX_HEADER main

main:
    mov esi, [esp+4]
    xor ebp, ebp                ; exit code
    cmp byte [esi], 0
    je .stdin
.file:
    ; cut the next space-separated name
    cmp byte [esi], ' '
    jne .name
    inc esi
    jmp .file
.name:
    cmp byte [esi], 0
    je .done
    mov edi, name
    xor ecx, ecx
.c:
    mov al, [esi]
    test al, al
    jz .cut
    cmp al, ' '
    je .cut
    cmp ecx, 15
    jae .skipch
    mov [edi+ecx], al
    inc ecx
.skipch:
    inc esi
    jmp .c
.cut:
    mov byte [edi+ecx], 0
    push esi
    call show
    pop esi
    jmp .file
.done:
    mov eax, ebp
    ret
.stdin:
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .done
    cmp eax, 27
    je .done
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    jmp .stdin

; prints the file called name; sets ebp = 1 if it is missing
show:
    mov eax, SYS_OPEN
    mov ebx, name
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .missing
    mov [fd], eax
    mov byte [last], 10
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
    movzx ebx, byte [esi]
    mov [last], bl
    mov eax, SYS_PUTC
    int 0x80
    inc esi
    loop .ch
    jmp .chunk
.eof:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    cmp byte [last], 10         ; end an unterminated last line
    je .r
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
.r:
    ret
.missing:
    mov eax, SYS_PUTS
    mov ebx, m_missing
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, name
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
    mov ebp, 1
    ret

m_missing db 'cat: not found: ', 0

BUFSIZE equ 512
SQX_BSS
fd      resd 1
last    resb 1
name    resb 16
buf     resb BUFSIZE
SQX_END
