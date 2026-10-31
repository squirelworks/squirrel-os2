; heap — grows its heap by 1 MB with SYS_SBRK, fills and checks it,
; then gives it back (0.6.2). Original code.
;   run heap          the test: prints "heap: PASS (1024 KB)"
;   run heap after    also touches the heap after giving it back, which
;                     faults and ends the program
;   run heap keep     exits still holding the 1 MB (the kernel frees it)
%include "sqx.inc"
SQX_HEADER main

HEAP_BASE equ 0x40000000
GROW      equ 0x100000

main:
    mov eax, [esp+4]
    mov [arg], eax
    mov eax, SYS_SBRK           ; where does the heap start?
    xor ebx, ebx
    int 0x80
    cmp eax, HEAP_BASE
    jne .fail
    mov eax, SYS_SBRK
    mov ebx, GROW
    int 0x80
    cmp eax, HEAP_BASE          ; returns the old break
    jne .fail
    ; new memory reads as zero; fill it with its own addresses
    mov edi, HEAP_BASE
.fill:
    cmp dword [edi], 0
    jne .fail
    mov [edi], edi
    add edi, 4
    cmp edi, HEAP_BASE+GROW
    jb .fill
    mov esi, HEAP_BASE
.check:
    cmp [esi], esi
    jne .fail
    add esi, 4
    cmp esi, HEAP_BASE+GROW
    jb .check
    ; more than the 4 MB heap is refused, and changes nothing
    mov eax, SYS_SBRK
    mov ebx, 0x400000
    int 0x80
    cmp eax, -1
    jne .fail
    mov esi, [arg]
    cmp byte [esi], 'k'
    jne .giveback
    mov eax, SYS_PUTS
    mov ebx, m_keep
    int 0x80
    xor eax, eax
    ret
.giveback:
    ; give it all back
    mov eax, SYS_SBRK
    mov ebx, -GROW
    int 0x80
    cmp eax, HEAP_BASE+GROW
    jne .fail
    mov eax, SYS_SBRK
    xor ebx, ebx
    int 0x80
    cmp eax, HEAP_BASE
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, m_pass
    int 0x80
    mov esi, [arg]
    cmp byte [esi], 'a'
    jne .done
    mov eax, SYS_PUTS
    mov ebx, m_after
    int 0x80
    mov eax, [HEAP_BASE]        ; unmapped again: page fault
.done:
    xor eax, eax
    ret
.fail:
    mov eax, SYS_PUTS
    mov ebx, m_fail
    int 0x80
    mov eax, 1
    ret

m_pass db 'heap: PASS (1024 KB)', 10, 0
m_keep db 'heap: exiting with 1024 KB still allocated', 10, 0
m_fail db 'heap: FAIL', 10, 0
m_after db 'heap: touching freed heap memory...', 10, 0

SQX_BSS
arg resd 1
SQX_END
