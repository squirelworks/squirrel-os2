; dbgtest — checks SYS_DEBUG (A.4): start a program stopped, single-step
; it, an INT3 breakpoint, registers and memory both ways, a fault that
; stops instead of ending it, attach/stop/kill on a running program, the
; refusals, and an untraced INT3. Original code. run dbgtest
%include "sqx.inc"
%include "debug.inc"
SQX_HEADER main

%macro DBG 3                    ; op, pid, argument -> eax
    mov eax, SYS_DEBUG
    mov ebx, %1
    mov ecx, %2
    mov edx, %3
    int 0x80
%endmacro
%macro EXPECT 2                 ; eax must be %1, else FAIL %2
    cmp eax, %1
    je %%ok
    mov eax, %2
    jmp fail
%%ok:
%endmacro

ENTRY equ PROG_BASE+16          ; dbgtgt's main

main:
    ; 1. started stopped at its entry
    DBG DBG_EXEC, tgt, noarg
    test eax, eax
    jg .s1
    mov eax, 1
    jmp fail
.s1:
    mov [pid], eax
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_ENTRY, 2
    DBG DBG_GETREGS, [pid], regs
    EXPECT 0, 3
    mov eax, [regs+DR_EIP]
    EXPECT ENTRY, 4
    cmp dword [regs+DR_ESP], 0x7FC00000
    jae .s5
    mov eax, 5
    jmp fail
.s5:
    ; 2. one instruction
    DBG DBG_CONT, [pid], 1
    EXPECT 0, 6
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_STEP, 7
    DBG DBG_GETREGS, [pid], regs
    mov eax, [regs+DR_EIP]
    EXPECT ENTRY+5, 8
    mov eax, [regs+DR_EAX]
    EXPECT 1, 9
    ; 3. a breakpoint at +12
    mov dword [xfer], ENTRY+12
    mov dword [xfer+4], saved
    mov dword [xfer+8], 1
    DBG DBG_READ, [pid], xfer
    EXPECT 1, 10
    cmp byte [saved], 0x89      ; mov ecx, eax
    je .s11
    mov eax, 11
    jmp fail
.s11:
    mov dword [xfer+4], int3op
    DBG DBG_WRITE, [pid], xfer
    EXPECT 1, 12
    DBG DBG_CONT, [pid], 0
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_BREAK, 13
    DBG DBG_GETREGS, [pid], regs
    mov eax, [regs+DR_EIP]
    EXPECT ENTRY+13, 14
    mov eax, [regs+DR_EAX]
    EXPECT 3, 15
    ; 4. put the byte back, rewind, change eax: it ends with exit code 7
    mov dword [xfer+4], saved
    DBG DBG_WRITE, [pid], xfer
    EXPECT 1, 16
    mov dword [regs+DR_EIP], ENTRY+12
    mov dword [regs+DR_EAX], 7
    DBG DBG_SETREGS, [pid], regs
    EXPECT 0, 17
    DBG DBG_CONT, [pid], 0
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_ENDED, 18
    mov eax, SYS_WAIT
    mov ebx, [pid]
    int 0x80
    EXPECT 7, 19
    ; 5. a page fault stops it; DBG_KILL ends it
    DBG DBG_EXEC, tgt, arg_f
    mov [pid], eax
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_ENTRY, 20
    DBG DBG_CONT, [pid], 0
    DBG DBG_WAIT, [pid], 0
    EXPECT 14, 21
    DBG DBG_GETREGS, [pid], regs
    mov eax, [regs+DR_CR2]
    EXPECT 0x10, 22
    mov eax, [regs+DR_ERR]
    EXPECT 7, 23                ; write, user, present
    DBG DBG_KILL, [pid], 0
    EXPECT 0, 24
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_ENDED, 25
    mov eax, SYS_WAIT
    mov ebx, [pid]
    int 0x80
    EXPECT -1, 26
    ; 6. attach to a running program, stop it, read it, kill it
    mov eax, SYS_EXEC
    mov ebx, tgt
    mov ecx, arg_s
    int 0x80
    mov [pid], eax
    mov ecx, 5
.y: push ecx
    mov eax, SYS_YIELD
    int 0x80
    pop ecx
    loop .y
    DBG DBG_ATTACH, [pid], 0
    EXPECT 0, 27
    DBG DBG_ATTACH, [pid], 0    ; only once
    EXPECT -1, 28
    DBG DBG_WAIT, [pid], 1
    EXPECT DBG_RUNNING, 29
    DBG DBG_STOP, [pid], 0
    EXPECT 0, 30
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_STOP, 31
    mov dword [xfer], ENTRY
    mov dword [xfer+4], buf
    mov dword [xfer+8], 4
    DBG DBG_READ, [pid], xfer
    EXPECT 4, 32
    cmp dword [buf], 0x000001B8 ; mov eax, 1
    je .s33
    mov eax, 33
    jmp fail
.s33:
    mov dword [xfer], 0x8000    ; kernel memory: nothing
    DBG DBG_READ, [pid], xfer
    EXPECT 0, 34
    mov dword [xfer], PROG_BASE+0x10000-2   ; the end of the area: 2 bytes
    DBG DBG_READ, [pid], xfer
    EXPECT 2, 35
    DBG DBG_GETREGS, [pid], 0x9000  ; a kernel buffer: refused
    EXPECT -1, 36
    DBG DBG_KILL, [pid], 0
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_ENDED, 37
    mov eax, SYS_WAIT
    mov ebx, [pid]
    int 0x80
    EXPECT -1, 38
    ; 7. refusals: itself, the shell, nobody
    mov eax, SYS_GETPID
    int 0x80
    mov [buf], eax
    DBG DBG_ATTACH, [buf], 0
    EXPECT -1, 39
    DBG DBG_ATTACH, 0, 0
    EXPECT -1, 40
    DBG DBG_ATTACH, 9999, 0
    EXPECT -1, 41
    DBG 99, 1, 0
    EXPECT -1, 42
    ; 8. detached at its entry, its INT3 ends it with a report
    DBG DBG_EXEC, tgt, arg_b
    mov [pid], eax
    DBG DBG_WAIT, [pid], 0
    EXPECT DBG_R_ENTRY, 43
    DBG DBG_DETACH, [pid], 0
    EXPECT 0, 44
    mov eax, SYS_WAIT
    mov ebx, [pid]
    int 0x80
    EXPECT -1, 45
    mov eax, SYS_PUTS
    mov ebx, m_pass
    int 0x80
    xor eax, eax
    ret

fail:
    push eax
    mov eax, SYS_PUTS
    mov ebx, m_fail
    int 0x80
    pop eax
    mov ecx, 10
    xor edx, edx
    div ecx
    push edx
    test eax, eax
    jz .one
    add eax, '0'
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
.one:
    pop ebx
    add ebx, '0'
    mov eax, SYS_PUTC
    int 0x80
    mov eax, SYS_PUTC
    mov ebx, 10
    int 0x80
    mov eax, 1
    ret

tgt db 'dbgtgt', 0
noarg db 0
arg_f db 'f', 0
arg_s db 's', 0
arg_b db 'b', 0
int3op db 0xCC
m_pass db 'dbgtest: PASS', 10, 0
m_fail db 'dbgtest: FAIL ', 0
SQX_BSS
pid resd 1
saved resb 4
xfer resd 3
regs resb DBG_REGS_SIZE
buf resd 4
SQX_END
