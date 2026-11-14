; nxheap — jumps into its heap; with NX (2.8-pae) that is a page fault.
; Original code. run nxheap
; Grows the heap by one page, writes a single-byte RET there and jumps to
; it. On a CPU with NX the kernel reports a fetch protection fault and
; ends this program. Without NX the RET runs and the program prints
; "nxheap: no NX" (the pentium3 regress check).
%include "sqx.inc"
SQX_HEADER main

HEAP_BASE equ 0x40000000

main:
    mov eax, SYS_SBRK
    mov ebx, 4096
    int 0x80
    cmp eax, HEAP_BASE
    jne .fail
    mov byte [HEAP_BASE], 0xC3      ; ret
    call HEAP_BASE                  ; NX: #PF (fetch, protection)
    mov ebx, m_nonx                 ; came back: CPU has no NX
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

m_nonx db 'nxheap: no NX', 10, 0
m_fail db 'nxheap: FAIL', 10, 0

SQX_BSS
SQX_END
