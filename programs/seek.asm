; seek — checks SYS_SEEK (1.0.2): writes "abcd", seeks to the second
; byte, reads "bcd" back; also checks a seek past the end is refused
; and SEEK_END - 1 reads the last byte. Original code. run seek
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, SYS_OPEN
    mov ebx, fname
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov [fd], eax
    mov eax, SYS_WRITE
    mov ebx, [fd]
    mov ecx, abcd
    mov edx, 4
    int 0x80
    cmp eax, 4
    jne .fail
    ; to the second byte, then read the rest
    mov eax, SYS_SEEK
    mov ebx, [fd]
    mov ecx, 1
    mov edx, 0                  ; from the start
    int 0x80
    cmp eax, 1
    jne .fail
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    mov edx, 8
    int 0x80
    cmp eax, 3
    jne .fail
    cmp dword [buf], 'bcd'      ; 'b','c','d',0
    jne .fail
    ; past the end: refused, position unchanged
    mov eax, SYS_SEEK
    mov ebx, [fd]
    mov ecx, 1
    mov edx, 1                  ; from the current position (4)
    int 0x80
    cmp eax, -1
    jne .fail
    ; one before the end
    mov eax, SYS_SEEK
    mov ebx, [fd]
    mov ecx, -1
    mov edx, 2                  ; from the end
    int 0x80
    cmp eax, 3
    jne .fail
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    mov edx, 8
    int 0x80
    cmp eax, 1
    jne .fail
    cmp byte [buf], 'd'
    jne .fail
    call close
    mov eax, SYS_DELETE
    mov ebx, fname
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, m_ok
    int 0x80
    xor eax, eax
    ret
.fail:
    call close
    mov eax, SYS_PUTS
    mov ebx, m_bad
    int 0x80
    mov eax, 1
    ret

close:
    mov ebx, [fd]
    test ebx, ebx
    js .no
    mov eax, SYS_CLOSE
    int 0x80
.no:
    ret

fname db 'seek.tmp', 0
abcd db 'abcd'
m_ok db 'seek: PASS', 10, 0
m_bad db 'seek: FAIL', 10, 0
fd dd -1

SQX_BSS
buf resb 8
SQX_END
