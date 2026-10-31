; ls — lists the data disk through SYS_READDIR. Original code.
; run ls          names and sizes
; run ls <text>   only names that contain <text>
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, [esp+4]
    mov [pattern], eax
    xor ebx, ebx                ; cursor
.next:
    mov eax, SYS_READDIR
    mov ecx, entry
    int 0x80
    cmp eax, -1
    je .nodisk
    test eax, eax
    jz .done
    push eax
    call match
    jnc .skip
    inc dword [shown]
    mov eax, SYS_PUTS
    mov ebx, entry
    int 0x80
    ; pad the name to 18 columns
    mov esi, entry
    xor ecx, ecx
.len:
    cmp byte [esi+ecx], 0
    je .pad
    inc ecx
    jmp .len
.pad:
    cmp ecx, 18
    jae .size
    mov eax, SYS_PUTC
    mov ebx, ' '
    int 0x80
    inc ecx
    jmp .pad
.size:
    mov eax, [entry+16]
    call putnum
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
.skip:
    pop ebx
    jmp .next
.done:
    mov eax, [shown]
    call putnum
    mov eax, SYS_PUTS
    mov ebx, m_files
    int 0x80
    xor eax, eax
    ret
.nodisk:
    mov eax, SYS_PUTS
    mov ebx, m_nodisk
    int 0x80
    mov eax, 1
    ret

; CF set when the entry name contains the pattern (or there is none)
match:
    mov edi, [pattern]
    cmp byte [edi], 0
    je .yes
    mov esi, entry
.start:
    cmp byte [esi], 0
    je .no
    xor ecx, ecx
.cmp:
    mov al, [edi+ecx]
    test al, al
    jz .yes
    cmp al, [esi+ecx]
    jne .adv
    inc ecx
    jmp .cmp
.adv:
    inc esi
    jmp .start
.yes:
    stc
    ret
.no:
    clc
    ret

; eax = unsigned number
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
    ret

m_files db ' file(s)', 10, 0
m_nodisk db 'ls: no data disk', 10, 0

SQX_BSS
pattern resd 1
shown   resd 1
entry   resb 20
numbuf  resb 12
SQX_END
