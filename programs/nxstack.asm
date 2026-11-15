; nxstack — jumps into its ring-3 stack; with NX (2.8-pae) that is a
; page fault. Original code. run nxstack
; Touches a page well below the stack top (the top page stays executable
; for the exit stub), writes a RET there and jumps to it. On a CPU with
; NX the kernel reports a fetch protection fault and ends this program.
; Without NX the RET runs and the program prints "nxstack: no NX".
%include "sqx.inc"
SQX_HEADER main

main:
    sub esp, 0x2000                 ; a page below the exit-stub page
    mov byte [esp], 0xC3            ; maps it (NX) and plants a ret
    mov eax, esp
    call eax                        ; NX: #PF (fetch, protection)
    add esp, 0x2000
    mov ebx, m_nonx
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

m_nonx db 'nxstack: no NX', 10, 0
m_fail db 'nxstack: FAIL', 10, 0

SQX_BSS
SQX_END
